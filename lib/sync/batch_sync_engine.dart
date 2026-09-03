import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/sync_queue_item.dart';
import '../repositories/product_repository.dart';
import '../repositories/client_repository.dart';
import '../repositories/supplier_repository.dart';
import '../Services/supplier_invoice_balance_sync_service.dart';
import '../Services/client_invoice_balance_sync_service.dart';
import 'sync_queue_manager.dart';

/// Processes the [SyncQueueManager] queue and uploads operations to Firestore.
///
/// Each operation is executed as an **atomic `WriteBatch`** or transaction:
/// - Creating an invoice = 1 batch write (invoice doc + stock decrements +
///   balance update + cash-box log) instead of 12–15 individual writes.
/// - Stock adjustments use `FieldValue.increment` for conflict-free
///   multi-device accumulation.
///
/// Retry strategy: exponential backoff  1s → 2s → 4s → 8s → 16s (max 5 tries).
class BatchSyncEngine {
  BatchSyncEngine._();
  static final BatchSyncEngine instance = BatchSyncEngine._();

  static const int _maxRetries = 5;
  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Processes all pending queue items sequentially.
  /// Safe to call multiple times — will no-op if already running.
  Future<void> processQueue() async {
    if (_isRunning) return;
    _isRunning = true;
    try {
      final pending = SyncQueueManager.instance.getPending();
      for (final item in pending) {
        if (item.retryCount >= _maxRetries) {
          // Exhausted retries — leave as 'failed', don't block others.
          continue;
        }
        await _processItem(item);
      }
    } finally {
      _isRunning = false;
    }
  }

  // ── Item Processor ────────────────────────────────────────────────────────

  Future<void> _processItem(SyncQueueItem item) async {
    await SyncQueueManager.instance.markSyncing(item.operationId);
    try {
      final payload = SyncQueueManager.decodePayload(item);
      await _dispatch(item.operationType, payload);
      await SyncQueueManager.instance.markSynced(item.operationId);
      _updateLastSyncMeta(item.operationType);
    } catch (e) {
      await SyncQueueManager.instance.markFailed(
        item.operationId,
        e.toString(),
      );
      // Exponential backoff before next item (1s, 2s, 4s…)
      final backoff = Duration(seconds: 1 << item.retryCount.clamp(0, 4));
      await Future.delayed(backoff);
    }
  }

  void _updateLastSyncMeta(String type) {
    final now = DateTime.now().toIso8601String();
    if (type.toLowerCase().contains('product')) {
      appMetaBox.put(HiveMetaKeys.lastProductSyncAt, now);
    } else if (type.toLowerCase().contains('supplier')) {
      appMetaBox.put(HiveMetaKeys.lastSupplierSyncAt, now);
    } else {
      appMetaBox.put(HiveMetaKeys.lastClientSyncAt, now);
    }
  }

  Future<DocumentReference<Map<String, dynamic>>?> _resolveProductRef(
      Map<dynamic, dynamic> product) async {
    final String id =
        product['id']?.toString() ?? product['productId']?.toString() ?? '';
    if (id.isNotEmpty) {
      final ref = _fs.collection('products').doc(id);
      final snap = await ref.get();
      if (snap.exists) return ref;
    }

    final String name = product['product']?.toString().trim() ??
        product['name']?.toString().trim() ??
        product['productName']?.toString().trim() ??
        '';
    if (name.isNotEmpty) {
      final local = ProductRepository.instance.findByName(name);
      if (local != null && local.id.isNotEmpty) {
        final ref = _fs.collection('products').doc(local.id);
        final snap = await ref.get();
        if (snap.exists) return ref;
      }

      final query = await _fs
          .collection('products')
          .where('name', isEqualTo: name)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) return query.docs.first.reference;
    }
    return null;
  }

  double _extractQty(Map<dynamic, dynamic> product) {
    final val = product['amount'] ??
        product['quantity'] ??
        product['count'] ??
        product['qty'];
    if (val is num) return val.toDouble();
    return double.tryParse(val?.toString() ?? '') ?? 0.0;
  }

  // ── Operation Dispatcher ──────────────────────────────────────────────────

  Future<void> _dispatch(
      String operationType, Map<String, dynamic> payload) async {
    switch (operationType) {
      case 'createInvoice':
        await _syncCreateInvoice(payload);
        break;
      case 'editInvoice':
        await _syncEditInvoice(payload);
        break;
      case 'deleteInvoice':
        await _syncDeleteInvoice(payload);
        break;
      case 'adjustClientBalance':
        await _syncAdjustClientBalance(payload);
        break;
      case 'adjustSupplierBalance':
        await _syncAdjustSupplierBalance(payload);
        break;
      case 'createProduct':
        await _syncCreateProduct(payload);
        break;
      case 'editProduct':
        await _syncEditProduct(payload);
        break;
      case 'deleteProduct':
        await _syncDeleteProduct(payload);
        break;
      case 'createReturn':
        await _syncCreateReturn(payload);
        break;
      case 'deleteReturn':
      case 'deleteReturnInvoice':
        await _syncDeleteReturn(payload);
        break;
      case 'createQuote':
        await _syncCreateQuote(payload);
        break;
      case 'deleteQuote':
        await _syncDeleteQuote(payload);
        break;
      case 'createBuyingInvoice':
        await _syncCreateBuyingInvoice(payload);
        break;
      case 'editBuyingInvoice':
        await _syncEditBuyingInvoice(payload);
        break;
      case 'deleteBuyingInvoice':
        await _syncDeleteBuyingInvoice(payload);
        break;
      case 'createClient':
        await _syncCreateClient(payload);
        break;
      case 'createSupplier':
        await _syncCreateSupplier(payload);
        break;
      case 'saveExpense':
        await _syncSaveExpense(payload);
        break;
      case 'deleteExpense':
        await _syncDeleteExpense(payload);
        break;
      case 'updateBox':
        await _syncUpdateBox(payload);
        break;
      case 'updateStock':
        await _syncUpdateStock(payload);
        break;
      default:
        throw UnsupportedError('Unknown operation type: $operationType');
    }
  }

  // ── Operation Handlers ────────────────────────────────────────────────────

  /// Syncs an offline-created selling invoice to Firestore as a single batch:
  /// - Invoice document in root invoices collection
  /// - Invoice document in clients/{clientId}/invoices
  /// - Stock decrements for each product line (FieldValue.increment)
  /// - Client balance update
  /// - Balance history log entries
  /// - Cash box update if paidAmount > 0
  Future<void> _syncCreateInvoice(Map<String, dynamic> payload) async {
    final batch = _fs.batch();
    final String clientId = payload['clientId'];
    final String invoiceId = payload['invoiceId'];
    final Map<String, dynamic> invoiceData =
        Map<String, dynamic>.from(payload['invoiceData']);
    final List<dynamic> products = payload['products'] ?? [];
    final double totalSum = (payload['totalSum'] as num).toDouble();
    final double paidAmount = (payload['paidAmount'] as num).toDouble();
    final int invoiceNumber =
        (invoiceData['invoiceNumber'] as num?)?.toInt() ?? 0;
    final String clientName = invoiceData['clientName']?.toString() ?? '';

    // Convert ISO date string back to DateTime for Firestore
    if (invoiceData['date'] is String) {
      invoiceData['date'] = DateTime.parse(invoiceData['date'] as String);
    }
    invoiceData['updatedAt'] = FieldValue.serverTimestamp();

    // 1. Root invoice doc
    final rootRef = _fs.collection('invoices').doc(invoiceId);

    // The queue may retry after Firestore committed the batch but before the
    // local queue item was removed. In that case increments must not run a
    // second time. The root invoice is written in the same atomic batch as all
    // stock, balance, history, and cash-box changes, so its existence is our
    // idempotency marker.
    final existingRoot = await rootRef.get();
    if (existingRoot.exists) {
      if (clientId.isNotEmpty) {
        await ClientInvoiceBalanceSyncService.syncForClient(clientId);
      }
      return;
    }

    batch.set(rootRef, invoiceData, SetOptions(merge: true));

    // 2. Client sub-collection doc
    if (clientId.isNotEmpty) {
      final clientInvoiceRef = _fs
          .collection('clients')
          .doc(clientId)
          .collection('invoices')
          .doc(invoiceId);
      batch.set(clientInvoiceRef, invoiceData, SetOptions(merge: true));

      // 3. Update client running balance.
      final double newBalance = totalSum - paidAmount;
      batch.set(
        _fs.collection('clients').doc(clientId),
        {
          'balance': FieldValue.increment(newBalance),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // 4. Balance history entries
      final histRef1 = _fs
          .collection('clients')
          .doc(clientId)
          .collection('balanceHistory')
          .doc('${invoiceId}_sale');
      batch.set(histRef1, {
        'enteredBalance': totalSum,
        'balanceBefore':
            (invoiceData['previousBalance'] as num?)?.toDouble() ?? 0.0,
        'timestamp': invoiceData['date'] ?? FieldValue.serverTimestamp(),
        'type': 'sale',
        'invoiceId': invoiceId,
        'invoiceNumber': invoiceNumber,
      });

      if (paidAmount > 0) {
        final histRef2 = _fs
            .collection('clients')
            .doc(clientId)
            .collection('balanceHistory')
            .doc('${invoiceId}_pay');
        batch.set(histRef2, {
          'enteredBalance': paidAmount,
          'balanceBefore':
              ((invoiceData['previousBalance'] as num?)?.toDouble() ?? 0.0) +
                  totalSum,
          'timestamp': invoiceData['date'] ?? FieldValue.serverTimestamp(),
          'type': 'sale_payment',
          'invoiceId': invoiceId,
          'invoiceNumber': invoiceNumber,
        });
      }
    }

    // 5. Decrement stock for each product line.
    for (final product in products) {
      if (product is! Map) continue;
      final double qty = _extractQty(product);
      if (qty <= 0) continue;
      final pRef = await _resolveProductRef(product);
      if (pRef != null) {
        batch.update(
          pRef,
          {
            'quantity': FieldValue.increment(-qty),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        batch.set(pRef.collection('changes').doc(), {
          'date': invoiceData['date'] ?? FieldValue.serverTimestamp(),
          'amount': qty,
          'type': 'decrease',
          'invoiceNumber': invoiceNumber,
        });
      }
    }

    // 6. Cash box update
    if (paidAmount > 0) {
      final boxRef = _fs.collection('box').doc('mainBox');
      batch.set(
        boxRef,
        {'value': FieldValue.increment(paidAmount)},
        SetOptions(merge: true),
      );
      batch.set(boxRef.collection('changes').doc(), {
        'date': invoiceData['date'] ?? FieldValue.serverTimestamp(),
        'value': paidAmount,
        'type': 'addition',
        'name': clientName,
        'invoiceNumber': invoiceNumber,
      });
    }

    await batch.commit();

    if (clientId.isNotEmpty) {
      await ClientInvoiceBalanceSyncService.syncForClient(clientId);
    }
  }

  Future<void> _syncEditInvoice(Map<String, dynamic> payload) async {
    final clientId = payload['clientId']?.toString() ?? '';
    final oldClientId = payload['oldClientId']?.toString() ?? clientId;
    final clientSubDocId = payload['clientSubInvoiceDocId']?.toString() ?? '';
    final invoiceId = payload['invoiceId']?.toString() ?? '';
    if (invoiceId.isEmpty) {
      throw ArgumentError('editInvoice payload missing invoiceId');
    }

    final sourceCollection =
        payload['sourceCollection']?.toString() == 'returnInvoices'
            ? 'returnInvoices'
            : 'invoices';
    final updateData =
        Map<String, dynamic>.from(payload['updateData'] as Map? ?? {});
    final oldProducts = payload['oldProducts'] as List? ?? [];
    final newProducts = payload['newProducts'] as List? ?? [];
    final hasPaidDelta = payload.containsKey('oldPaidAmount') &&
        payload.containsKey('paidAmount');
    final oldPaidAmount = (payload['oldPaidAmount'] as num?)?.toDouble() ?? 0.0;
    final newPaidAmount = (payload['paidAmount'] as num?)?.toDouble() ??
        (updateData['paidAmount'] as num?)?.toDouble() ??
        0.0;
    final rawOperationId = payload['syncOperationId']?.toString().trim() ?? '';
    final operationId = rawOperationId.isNotEmpty
        ? rawOperationId
        : '$invoiceId-${updateData['totalSum']}-$newPaidAmount-${updateData['date']}'
            .replaceAll('/', '_');
    final markerRef =
        _fs.collection('_sync_operations').doc('edit_invoice_$operationId');

    if ((await markerRef.get()).exists) {
      final clientIds = {clientId, oldClientId}
        ..removeWhere((id) => id.isEmpty);
      for (final id in clientIds) {
        await ClientInvoiceBalanceSyncService.syncForClient(id);
      }
      return;
    }

    if (updateData['date'] is String) {
      updateData['date'] = DateTime.parse(updateData['date'] as String);
    }
    updateData['updatedAt'] = FieldValue.serverTimestamp();

    DocumentReference<Map<String, dynamic>>? existingSubInvoiceRef(
      QuerySnapshot<Map<String, dynamic>> snapshot,
    ) {
      return snapshot.docs.isNotEmpty ? snapshot.docs.first.reference : null;
    }

    Future<DocumentReference<Map<String, dynamic>>?> findClientInvoiceRef(
      String ownerClientId,
    ) async {
      if (ownerClientId.isEmpty) return null;
      final invoices =
          _fs.collection('clients').doc(ownerClientId).collection('invoices');

      if (clientSubDocId.isNotEmpty) {
        final ref = invoices.doc(clientSubDocId);
        if ((await ref.get()).exists) return ref;
      }

      final matching = await invoices
          .where('invoiceId', isEqualTo: invoiceId)
          .limit(1)
          .get();
      return existingSubInvoiceRef(matching) ?? invoices.doc(invoiceId);
    }

    final oldSubRef =
        oldClientId.isNotEmpty ? await findClientInvoiceRef(oldClientId) : null;
    final newSubRef = clientId.isNotEmpty
        ? (clientId == oldClientId
            ? oldSubRef
            : await findClientInvoiceRef(clientId))
        : null;

    final productRefs = <String, DocumentReference<Map<String, dynamic>>>{};
    final quantityDeltas = <String, double>{};

    Future<void> accumulate(dynamic rawProduct, double sign) async {
      if (rawProduct is! Map) return;
      final qty = _extractQty(rawProduct);
      if (qty <= 0) return;
      final ref = await _resolveProductRef(rawProduct);
      if (ref == null) return;
      final key = ref.path;
      productRefs[key] = ref;
      quantityDeltas[key] = (quantityDeltas[key] ?? 0.0) + sign * qty;
    }

    for (final product in oldProducts) {
      await accumulate(product, 1);
    }
    for (final product in newProducts) {
      await accumulate(product, -1);
    }

    final batch = _fs.batch();
    final rootRef = _fs.collection(sourceCollection).doc(invoiceId);
    batch.set(rootRef, updateData, SetOptions(merge: true));

    if (newSubRef != null) {
      batch.set(
        newSubRef,
        {...updateData, 'invoiceId': invoiceId, 'clientId': clientId},
        SetOptions(merge: true),
      );
    }
    if (oldSubRef != null && oldClientId != clientId) {
      batch.delete(oldSubRef);
    }

    for (final entry in productRefs.entries) {
      final delta = quantityDeltas[entry.key] ?? 0.0;
      if (delta.abs() > 0.001) {
        batch.update(entry.value, {
          'quantity': FieldValue.increment(delta),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    final paidDelta = newPaidAmount - oldPaidAmount;
    if (hasPaidDelta && paidDelta.abs() > 0.001) {
      final boxRef = _fs.collection('box').doc('mainBox');
      batch.set(
        boxRef,
        {'value': FieldValue.increment(paidDelta)},
        SetOptions(merge: true),
      );
      batch.set(boxRef.collection('changes').doc('edit_$operationId'), {
        'date': FieldValue.serverTimestamp(),
        'value': paidDelta,
        'type': paidDelta >= 0 ? 'addition' : 'subtraction',
        'name': updateData['clientName']?.toString() ?? '',
        'invoiceNumber': updateData['invoiceNumber'],
      });
    }

    batch.set(markerRef, {
      'type': 'editInvoice',
      'invoiceId': invoiceId,
      'appliedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    final clientIds = {clientId, oldClientId}..removeWhere((id) => id.isEmpty);
    for (final id in clientIds) {
      await ClientInvoiceBalanceSyncService.syncForClient(id);
    }
  }

  Future<void> _syncDeleteInvoice(Map<String, dynamic> payload) async {
    final String clientId = payload['clientId']?.toString() ?? '';
    final String invoiceId = payload['invoiceId']?.toString() ?? '';
    final String clientSubDocId =
        payload['clientSubDocId']?.toString() ?? invoiceId;
    final List<dynamic> products = payload['products'] as List? ?? [];
    final double totalSum = (payload['totalSum'] as num?)?.toDouble() ?? 0.0;
    final double paidAmount =
        (payload['paidAmount'] as num?)?.toDouble() ?? 0.0;

    final batch = _fs.batch();

    // 1. Delete invoice documents (root + subcollection).
    if (invoiceId.isNotEmpty) {
      batch.delete(_fs.collection('invoices').doc(invoiceId));
    }
    if (clientId.isNotEmpty && clientSubDocId.isNotEmpty) {
      batch.delete(_fs
          .collection('clients')
          .doc(clientId)
          .collection('invoices')
          .doc(clientSubDocId));
    }
    if (clientId.isNotEmpty &&
        invoiceId.isNotEmpty &&
        invoiceId != clientSubDocId) {
      batch.delete(_fs
          .collection('clients')
          .doc(clientId)
          .collection('invoices')
          .doc(invoiceId));
    }

    // 2. Restore stock quantities in Firestore.
    for (final product in products) {
      if (product is! Map) continue;
      final double qty = _extractQty(product);
      if (qty <= 0) continue;
      final pRef = await _resolveProductRef(product);
      if (pRef != null) {
        batch.update(
          pRef,
          {
            'quantity': FieldValue.increment(qty),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        batch.set(pRef.collection('changes').doc(), {
          'date': FieldValue.serverTimestamp(),
          'amount': qty,
          'type': 'increase',
          'reason': 'delete_invoice',
        });
      }
    }

    // 3. Reverse client balance in Firestore.
    if (clientId.isNotEmpty && (totalSum > 0 || paidAmount > 0)) {
      final double balanceToReverse = totalSum - paidAmount;
      batch.update(
        _fs.collection('clients').doc(clientId),
        {'balance': FieldValue.increment(-balanceToReverse)},
      );
    }

    // 4. Delete balance history entries
    if (clientId.isNotEmpty) {
      final idsToCheck = <String>{
        if (invoiceId.isNotEmpty) invoiceId,
        if (clientSubDocId.isNotEmpty) clientSubDocId,
      };
      for (final id in idsToCheck) {
        batch.delete(_fs
            .collection('clients')
            .doc(clientId)
            .collection('balanceHistory')
            .doc(id));
        batch.delete(_fs
            .collection('clients')
            .doc(clientId)
            .collection('balanceHistory')
            .doc('${id}_sale'));
        batch.delete(_fs
            .collection('clients')
            .doc(clientId)
            .collection('balanceHistory')
            .doc('${id}_pay'));
      }
      try {
        final querySnap = await _fs
            .collection('clients')
            .doc(clientId)
            .collection('balanceHistory')
            .where('invoiceId', whereIn: idsToCheck.toList())
            .get();
        for (final doc in querySnap.docs) {
          batch.delete(doc.reference);
        }
      } catch (_) {}
    }

    // 5. Adjust mainBox balance if paid.
    if (paidAmount > 0) {
      final boxRef = _fs.collection('box').doc('mainBox');
      batch.set(
        boxRef,
        {'value': FieldValue.increment(-paidAmount)},
        SetOptions(merge: true),
      );
    }

    await batch.commit();

    if (clientId.isNotEmpty) {
      await ClientInvoiceBalanceSyncService.syncForClient(clientId);
    }
  }

  Future<void> _syncAdjustClientBalance(Map<String, dynamic> payload) async {
    final String clientId = payload['clientId'];
    final double amount = (payload['amount'] as num).toDouble();
    final bool isAddition = payload['isAddition'] == true;
    final Map<String, dynamic> logEntry =
        Map<String, dynamic>.from(payload['logEntry']);
    final timestamp = logEntry['timestamp'];
    if (timestamp is String) {
      logEntry['timestamp'] = DateTime.tryParse(timestamp) ?? DateTime.now();
    }

    // New callers provide the local history ID. The deterministic fallback
    // also makes queue items created by older app versions safe to retry.
    final historyId = payload['historyId']?.toString().trim().isNotEmpty == true
        ? payload['historyId'].toString().trim()
        : 'adjust_${logEntry['type']}_${timestamp}_${amount.toStringAsFixed(4)}'
            .replaceAll('/', '-');
    final clientRef = _fs.collection('clients').doc(clientId);
    final historyRef = clientRef.collection('balanceHistory').doc(historyId);
    final boxRef = _fs.collection('box').doc('mainBox');
    final boxChangeRef = boxRef.collection('changes').doc(historyId);

    // Only apply the financial effect when its matching history record does
    // not exist. This prevents retrying one queue item from changing balances
    // or the cash box twice.
    await _fs.runTransaction((transaction) async {
      final existingHistory = await transaction.get(historyRef);
      if (existingHistory.exists) return;

      transaction.update(clientRef, {
        'balance': FieldValue.increment(isAddition ? amount : -amount),
      });
      transaction.set(historyRef, logEntry);
      transaction.set(
        boxRef,
        {'value': FieldValue.increment(isAddition ? -amount : amount)},
        SetOptions(merge: true),
      );
      transaction.set(boxChangeRef, {
        'date': logEntry['timestamp'],
        'value': amount,
        'type': isAddition ? 'decrement' : 'addition',
        'notes': logEntry['notes']?.toString() ?? '',
        'invoiceNumber': null,
      });
    });

    await ClientInvoiceBalanceSyncService.syncForClient(clientId);
  }

  Future<void> _syncAdjustSupplierBalance(Map<String, dynamic> payload) async {
    final String supplierId = payload['supplierId'];
    final double amount = (payload['amount'] as num).toDouble();
    final bool isAddition = payload['isAddition'] == true;
    final Map<String, dynamic> logEntry =
        Map<String, dynamic>.from(payload['logEntry']);
    final timestamp = logEntry['timestamp'];
    if (timestamp is String) {
      logEntry['timestamp'] = DateTime.tryParse(timestamp) ?? DateTime.now();
    }

    final historyId = payload['historyId']?.toString().trim().isNotEmpty == true
        ? payload['historyId'].toString().trim()
        : 'supplier_adjust_${logEntry['type']}_${timestamp}_${amount.toStringAsFixed(4)}'
            .replaceAll('/', '-');
    final supplierName = payload['supplierName']?.toString() ?? '';
    final supplierRef = _fs.collection('suppliers').doc(supplierId);
    final historyRef = supplierRef.collection('balanceHistory').doc(historyId);
    final voucherRef =
        _fs.collection('supplier_vouchers').doc('${historyId}_voucher');
    final boxRef = _fs.collection('box').doc('mainBox');
    final boxChangeRef = boxRef.collection('changes').doc(historyId);
    final delta = isAddition ? amount : -amount;

    await _fs.runTransaction((transaction) async {
      final existingHistory = await transaction.get(historyRef);
      if (existingHistory.exists) return;

      transaction.set(
        supplierRef,
        {
          'totalBalance': FieldValue.increment(delta),
          'balance': FieldValue.increment(delta),
        },
        SetOptions(merge: true),
      );

      if (isAddition) {
        transaction.set(historyRef, logEntry);
        return;
      }

      transaction.set(voucherRef, {
        'supplierId': supplierId,
        'supplierName': supplierName,
        'direction': '\u0639\u0644\u064a\u0647',
        'amount': amount,
        'description': logEntry['notes']?.toString() ?? '',
        'date': logEntry['timestamp'],
        'timestamp': logEntry['timestamp'],
      });
      transaction.set(historyRef, {
        ...logEntry,
        'type': 'voucher',
        'direction': '\u0639\u0644\u064a\u0647',
        'voucherId': voucherRef.id,
      });
      transaction.set(
        boxRef,
        {'value': FieldValue.increment(-amount)},
        SetOptions(merge: true),
      );
      transaction.set(boxChangeRef, {
        'date': logEntry['timestamp'],
        'value': amount,
        'type': 'decrement',
        'name': supplierName,
        'notes': logEntry['notes']?.toString() ?? '',
        'invoiceNumber': null,
      });
    });

    await SupplierInvoiceBalanceSyncService.syncForSupplier(supplierId);
  }

  Future<void> _syncCreateProduct(Map<String, dynamic> payload) async {
    final String productId = payload['productId'];
    final Map<String, dynamic> data =
        Map<String, dynamic>.from(payload['data']);
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _fs
        .collection('products')
        .doc(productId)
        .set(data, SetOptions(merge: true));
    await ProductRepository.instance.upsertLocal(productId, data);
    await ProductRepository.instance.deltaSync();
  }

  Future<void> _syncEditProduct(Map<String, dynamic> payload) async {
    final String productId = payload['productId'];
    final Map<String, dynamic> data =
        Map<String, dynamic>.from(payload['data']);
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _fs
        .collection('products')
        .doc(productId)
        .set(data, SetOptions(merge: true));
    await ProductRepository.instance.upsertLocal(productId, data);
    await ProductRepository.instance.deltaSync();
  }

  Future<void> _syncDeleteProduct(Map<String, dynamic> payload) async {
    final String productId = payload['productId'];
    await _fs.collection('products').doc(productId).delete();
    await ProductRepository.instance.deleteLocal(productId);
    await ProductRepository.instance.deltaSync();
  }

  /// Syncs an offline-created return invoice to Firestore as a single batch:
  /// - Return invoice document in returnInvoices collection
  /// - Stock restores for each product line (FieldValue.increment)
  /// - Client balance update (decrease)
  /// - Client sub-collection return invoice
  /// - Balance history entries
  /// - Cash box update
  Future<void> _syncCreateReturn(Map<String, dynamic> payload) async {
    final batch = _fs.batch();
    final String clientId = payload['clientId'];
    final String invoiceId = payload['invoiceId'];
    final Map<String, dynamic> invoiceData =
        Map<String, dynamic>.from(payload['invoiceData']);
    final List<dynamic> products = payload['products'] ?? [];
    final double totalSum = (payload['totalSum'] as num).toDouble();
    final double paidAmount = (payload['paidAmount'] as num).toDouble();

    // Convert ISO date string back to DateTime for Firestore
    if (invoiceData['date'] is String) {
      invoiceData['date'] = DateTime.parse(invoiceData['date'] as String);
    }
    invoiceData['updatedAt'] = FieldValue.serverTimestamp();

    // 1. Write the return invoice document.
    final invoiceRef = _fs.collection('returnInvoices').doc(invoiceId);
    batch.set(invoiceRef, invoiceData, SetOptions(merge: true));

    // 2. Restore stock for each product (atomic — safe for multi-device).
    for (final product in products) {
      if (product is! Map) continue;
      final double qty = _extractQty(product);
      if (qty <= 0) continue;

      final pRef = await _resolveProductRef(product);
      if (pRef != null) {
        batch.update(
          pRef,
          {'quantity': FieldValue.increment(qty)}, // Restore stock
        );
      }
    }

    // 3. Update client running balance (return reduces debt).
    final double balanceReduction = totalSum - paidAmount;
    batch.set(
      _fs.collection('clients').doc(clientId),
      {'balance': FieldValue.increment(-balanceReduction)},
      SetOptions(merge: true),
    );

    // 4. Write to client sub-collection with exact invoiceId.
    batch.set(
      _fs
          .collection('clients')
          .doc(clientId)
          .collection('returnInvoices')
          .doc(invoiceId),
      invoiceData,
      SetOptions(merge: true),
    );

    // 5. Balance history log entries with deterministic IDs
    final int invoiceNumber =
        (invoiceData['invoiceNumber'] as num?)?.toInt() ?? 0;
    final histRef1 = _fs
        .collection('clients')
        .doc(clientId)
        .collection('balanceHistory')
        .doc('${invoiceId}_return');
    batch.set(histRef1, {
      'enteredBalance': totalSum,
      'balanceBefore':
          (invoiceData['previousBalance'] as num?)?.toDouble() ?? 0.0,
      'timestamp': invoiceData['date'] ?? FieldValue.serverTimestamp(),
      'type': 'return',
      'invoiceId': invoiceId,
      'invoiceNumber': invoiceNumber,
    });

    if (paidAmount > 0) {
      final histRef2 = _fs
          .collection('clients')
          .doc(clientId)
          .collection('balanceHistory')
          .doc('${invoiceId}_return_pay');
      batch.set(histRef2, {
        'enteredBalance': paidAmount,
        'balanceBefore':
            ((invoiceData['previousBalance'] as num?)?.toDouble() ?? 0.0) -
                totalSum,
        'timestamp': invoiceData['date'] ?? FieldValue.serverTimestamp(),
        'type': 'return_payment',
        'invoiceId': invoiceId,
        'invoiceNumber': invoiceNumber,
      });
    }

    // 6. Cash box update (subtract refund paid).
    if (paidAmount > 0) {
      batch.set(
        _fs.collection('box').doc('mainBox'),
        {'value': FieldValue.increment(-paidAmount)},
        SetOptions(merge: true),
      );
    }

    await batch.commit();

    // Update local cache.
    await ClientRepository.instance.deltaSync();
  }

  /// Syncs a deleted return invoice back to Firestore.
  Future<void> _syncDeleteReturn(Map<String, dynamic> payload) async {
    final String clientId = payload['clientId']?.toString() ?? '';
    final String invoiceId = payload['invoiceId']?.toString() ?? '';
    final String clientSubDocId =
        payload['clientSubDocId']?.toString() ?? invoiceId;
    final List<dynamic> products = payload['products'] as List? ?? [];
    final double totalSum = (payload['totalSum'] as num?)?.toDouble() ?? 0.0;
    final double paidAmount =
        (payload['paidAmount'] as num?)?.toDouble() ?? 0.0;

    final batch = _fs.batch();

    // 1. Delete return invoice document from root collection
    if (invoiceId.isNotEmpty) {
      batch.delete(_fs.collection('returnInvoices').doc(invoiceId));
    }

    // 2. Delete from client subcollection
    if (clientId.isNotEmpty && clientSubDocId.isNotEmpty) {
      batch.delete(_fs
          .collection('clients')
          .doc(clientId)
          .collection('returnInvoices')
          .doc(clientSubDocId));
    }
    if (clientId.isNotEmpty &&
        invoiceId.isNotEmpty &&
        invoiceId != clientSubDocId) {
      batch.delete(_fs
          .collection('clients')
          .doc(clientId)
          .collection('returnInvoices')
          .doc(invoiceId));
    }

    // 3. Reverse stock restores (decrement stock back in Firestore).
    for (final product in products) {
      if (product is! Map) continue;
      final double qty = _extractQty(product);
      if (qty <= 0) continue;
      final pRef = await _resolveProductRef(product);
      if (pRef != null) {
        batch.update(
          pRef,
          {
            'quantity': FieldValue.increment(-qty),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        batch.set(pRef.collection('changes').doc(), {
          'date': FieldValue.serverTimestamp(),
          'amount': qty,
          'type': 'decrease',
          'reason': 'delete_return_invoice',
        });
      }
    }

    // 4. Reverse client balance change (return reduced debt, so deleting it adds debt back)
    if (clientId.isNotEmpty && (totalSum > 0 || paidAmount > 0)) {
      final double balanceToReverse = totalSum - paidAmount;
      batch.update(
        _fs.collection('clients').doc(clientId),
        {'balance': FieldValue.increment(balanceToReverse)},
      );
    }

    // 5. Delete balance history entries
    if (clientId.isNotEmpty) {
      final idsToCheck = <String>{
        if (invoiceId.isNotEmpty) invoiceId,
        if (clientSubDocId.isNotEmpty) clientSubDocId,
      };
      for (final id in idsToCheck) {
        batch.delete(_fs
            .collection('clients')
            .doc(clientId)
            .collection('balanceHistory')
            .doc(id));
        batch.delete(_fs
            .collection('clients')
            .doc(clientId)
            .collection('balanceHistory')
            .doc('${id}_return'));
        batch.delete(_fs
            .collection('clients')
            .doc(clientId)
            .collection('balanceHistory')
            .doc('${id}_return_pay'));
      }
      try {
        final querySnap = await _fs
            .collection('clients')
            .doc(clientId)
            .collection('balanceHistory')
            .where('invoiceId', whereIn: idsToCheck.toList())
            .get();
        for (final doc in querySnap.docs) {
          batch.delete(doc.reference);
        }
      } catch (_) {}
    }

    // 6. Adjust mainBox if paidAmount > 0 (refund was paid out, so return money back to cash box)
    if (paidAmount > 0) {
      final boxRef = _fs.collection('box').doc('mainBox');
      batch.set(
        boxRef,
        {'value': FieldValue.increment(paidAmount)},
        SetOptions(merge: true),
      );
    }

    await batch.commit();

    if (clientId.isNotEmpty) {
      await ClientInvoiceBalanceSyncService.syncForClient(clientId);
    }
  }

  /// Syncs an offline-created price quote to Firestore.
  Future<void> _syncCreateQuote(Map<String, dynamic> payload) async {
    final String quoteId = payload['quoteId'];
    final Map<String, dynamic> quoteData =
        Map<String, dynamic>.from(payload['quoteData']);

    // Convert ISO date string back to DateTime for Firestore
    if (quoteData['date'] is String) {
      quoteData['date'] = DateTime.parse(quoteData['date'] as String);
    }
    quoteData['createdAt'] = FieldValue.serverTimestamp();

    await _fs.collection('price_quotes').doc(quoteId).set(
          quoteData,
          SetOptions(merge: true),
        );
  }

  /// Syncs an offline-created buying invoice to Firestore.
  Future<void> _syncCreateBuyingInvoice(Map<String, dynamic> payload) async {
    final String supplierId = payload['supplierId'] ?? '';
    final String supplierName = payload['supplierName'] ?? '';
    final String invoiceId = payload['invoiceId'];
    final invoiceRef = _fs.collection('buying invoices').doc(invoiceId);
    final Map<String, dynamic> invoiceData =
        Map<String, dynamic>.from(payload['invoiceData']);
    final List<dynamic> products = payload['products'] ?? [];
    final double paidAmount =
        (payload['paidAmount'] as num?)?.toDouble() ?? 0.0;

    if (invoiceData['date'] is String) {
      invoiceData['date'] = DateTime.parse(invoiceData['date'] as String);
    }

    // The root document is written in the same atomic batch as stock and cash.
    // Its existence therefore proves this create was already applied.
    final existingRoot = await invoiceRef.get();
    if (existingRoot.exists) {
      if (supplierId.isNotEmpty) {
        await SupplierInvoiceBalanceSyncService.syncForSupplier(supplierId);
      }
      return;
    }

    final batch = _fs.batch();

    // 1. Write the buying invoice document.
    batch.set(invoiceRef, invoiceData, SetOptions(merge: true));

    // 2. Write to supplier subcollection if supplier exists.
    if (supplierId.isNotEmpty) {
      final supplierInvoiceRef = _fs
          .collection('suppliers')
          .doc(supplierId)
          .collection('buying invoices')
          .doc(invoiceId);
      batch.set(
          supplierInvoiceRef,
          {
            ...invoiceData,
            'invoiceId': invoiceId,
          },
          SetOptions(merge: true));

      final supplierRef = _fs.collection('suppliers').doc(supplierId);
      batch.set(supplierRef, {'name': supplierName}, SetOptions(merge: true));
    }

    // 3. Increment stock for each product line.
    for (final product in products) {
      if (product is! Map) continue;
      final double qty = _extractQty(product);
      if (qty <= 0) continue;

      final pRef = await _resolveProductRef(product);
      if (pRef != null) {
        final updateMap = <String, dynamic>{
          'quantity': FieldValue.increment(qty),
        };
        if (product['newCostPrice'] != null) {
          updateMap['costPrice'] = (product['newCostPrice'] as num).toDouble();
        }
        if (product['newSellingPrice1'] != null) {
          updateMap['sellingPrice1'] =
              (product['newSellingPrice1'] as num).toDouble();
        }
        if (product['newSellingPrice2'] != null) {
          updateMap['sellingPrice2'] =
              (product['newSellingPrice2'] as num).toDouble();
        }
        if (product['newSellingPrice3'] != null) {
          updateMap['sellingPrice3'] =
              (product['newSellingPrice3'] as num).toDouble();
        }
        batch.update(pRef, updateMap);
      }
    }

    // 4. Update mainBox balance if paid.
    if (paidAmount > 0) {
      final boxRef = _fs.collection('box').doc('mainBox');
      batch.set(
        boxRef,
        {'value': FieldValue.increment(-paidAmount)},
        SetOptions(merge: true),
      );
    }

    await batch.commit();

    if (supplierId.isNotEmpty) {
      await SupplierInvoiceBalanceSyncService.syncForSupplier(supplierId);
    }
  }

  /// Applies only the differences of a buying-invoice edit. A stable marker is
  /// committed with all changes, so retrying the queue item is a no-op.
  Future<void> _syncEditBuyingInvoice(Map<String, dynamic> payload) async {
    final supplierId = payload['supplierId']?.toString() ?? '';
    final supplierName = payload['supplierName']?.toString() ?? '';
    final invoiceId = payload['invoiceId']?.toString() ?? '';
    if (invoiceId.isEmpty) {
      throw ArgumentError('editBuyingInvoice payload missing invoiceId');
    }

    final invoiceData =
        Map<String, dynamic>.from(payload['invoiceData'] as Map? ?? {});
    if (invoiceData['date'] is String) {
      invoiceData['date'] = DateTime.parse(invoiceData['date'] as String);
    }
    final oldProducts = payload['oldProducts'] as List? ?? [];
    final newProducts = payload['products'] as List? ?? [];
    final oldPaidAmount = (payload['oldPaidAmount'] as num?)?.toDouble() ?? 0.0;
    final newPaidAmount = (payload['paidAmount'] as num?)?.toDouble() ?? 0.0;
    final rawOperationId = payload['syncOperationId']?.toString().trim() ?? '';
    final operationId = rawOperationId.isNotEmpty
        ? rawOperationId
        : '$invoiceId-${invoiceData['totalSum']}-$newPaidAmount-${invoiceData['date']}'
            .replaceAll('/', '_');
    final markerRef =
        _fs.collection('_sync_operations').doc('edit_buying_$operationId');

    if ((await markerRef.get()).exists) {
      if (supplierId.isNotEmpty) {
        await SupplierInvoiceBalanceSyncService.syncForSupplier(supplierId);
      }
      return;
    }

    final rootRef = _fs.collection('buying invoices').doc(invoiceId);
    if (!(await rootRef.get()).exists) {
      await _syncCreateBuyingInvoice({
        ...payload,
        'products': newProducts,
        'paidAmount': newPaidAmount,
      });
      return;
    }

    DocumentReference<Map<String, dynamic>>? supplierInvoiceRef;
    if (supplierId.isNotEmpty) {
      final supplierInvoices = _fs
          .collection('suppliers')
          .doc(supplierId)
          .collection('buying invoices');
      final matching = await supplierInvoices
          .where('invoiceId', isEqualTo: invoiceId)
          .limit(1)
          .get();
      supplierInvoiceRef = matching.docs.isNotEmpty
          ? matching.docs.first.reference
          : supplierInvoices.doc(invoiceId);
    }

    final productRefs = <String, DocumentReference<Map<String, dynamic>>>{};
    final quantityDeltas = <String, double>{};
    final latestProducts = <String, Map<dynamic, dynamic>>{};

    Future<void> accumulate(dynamic rawProduct, double sign) async {
      if (rawProduct is! Map) return;
      final qty = _extractQty(rawProduct);
      if (qty <= 0) return;
      final ref = await _resolveProductRef(rawProduct);
      if (ref == null) return;
      final key = ref.path;
      productRefs[key] = ref;
      quantityDeltas[key] = (quantityDeltas[key] ?? 0.0) + sign * qty;
      if (sign > 0) latestProducts[key] = rawProduct;
    }

    for (final product in oldProducts) {
      await accumulate(product, -1);
    }
    for (final product in newProducts) {
      await accumulate(product, 1);
    }

    final batch = _fs.batch();
    batch.set(rootRef, invoiceData, SetOptions(merge: true));
    if (supplierInvoiceRef != null) {
      batch.set(
        supplierInvoiceRef,
        {...invoiceData, 'invoiceId': invoiceId},
        SetOptions(merge: true),
      );
      batch.set(
        _fs.collection('suppliers').doc(supplierId),
        {'name': supplierName},
        SetOptions(merge: true),
      );
    }

    for (final entry in productRefs.entries) {
      final delta = quantityDeltas[entry.key] ?? 0.0;
      final latest = latestProducts[entry.key];
      final update = <String, dynamic>{};
      if (delta.abs() > 0.001) {
        update['quantity'] = FieldValue.increment(delta);
      }
      if (latest?['newCostPrice'] != null) {
        update['costPrice'] = (latest!['newCostPrice'] as num).toDouble();
      }
      if (latest?['newSellingPrice1'] != null) {
        update['sellingPrice1'] =
            (latest!['newSellingPrice1'] as num).toDouble();
      }
      if (latest?['newSellingPrice2'] != null) {
        update['sellingPrice2'] =
            (latest!['newSellingPrice2'] as num).toDouble();
      }
      if (latest?['newSellingPrice3'] != null) {
        update['sellingPrice3'] =
            (latest!['newSellingPrice3'] as num).toDouble();
      }
      if (update.isNotEmpty) batch.update(entry.value, update);
    }

    final paidDelta = newPaidAmount - oldPaidAmount;
    if (paidDelta.abs() > 0.001) {
      batch.set(
        _fs.collection('box').doc('mainBox'),
        {'value': FieldValue.increment(-paidDelta)},
        SetOptions(merge: true),
      );
    }
    batch.set(markerRef, {
      'type': 'editBuyingInvoice',
      'invoiceId': invoiceId,
      'appliedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    if (supplierId.isNotEmpty) {
      await SupplierInvoiceBalanceSyncService.syncForSupplier(supplierId);
    }
  }

  /// Syncs a deleted buying invoice back to Firestore.
  Future<void> _syncDeleteBuyingInvoice(Map<String, dynamic> payload) async {
    final String supplierId = payload['supplierId']?.toString() ?? '';
    final String invoiceId = payload['invoiceId']?.toString() ?? '';
    final String supplierSubDocId =
        payload['supplierSubDocId']?.toString() ?? invoiceId;
    final List<dynamic> products = payload['products'] as List? ?? [];
    final double paidAmount =
        (payload['paidAmount'] as num?)?.toDouble() ?? 0.0;

    final operationId =
        payload['syncOperationId']?.toString().trim().isNotEmpty == true
            ? payload['syncOperationId'].toString().trim()
            : (invoiceId.isNotEmpty ? invoiceId : supplierSubDocId);
    final markerRef =
        _fs.collection('_sync_operations').doc('delete_buying_$operationId');
    if ((await markerRef.get()).exists) {
      if (supplierId.isNotEmpty) {
        await SupplierInvoiceBalanceSyncService.syncForSupplier(supplierId);
      }
      return;
    }

    final rootRef = _fs.collection('buying invoices').doc(invoiceId);
    final supplierSubRef = supplierId.isNotEmpty && supplierSubDocId.isNotEmpty
        ? _fs
            .collection('suppliers')
            .doc(supplierId)
            .collection('buying invoices')
            .doc(supplierSubDocId)
        : null;
    final rootExists = invoiceId.isNotEmpty && (await rootRef.get()).exists;
    final subExists =
        supplierSubRef != null && (await supplierSubRef.get()).exists;
    if (!rootExists && !subExists) {
      if (supplierId.isNotEmpty) {
        await SupplierInvoiceBalanceSyncService.syncForSupplier(supplierId);
      }
      return;
    }

    final batch = _fs.batch();

    // 1. Delete buying invoice from root collection
    if (invoiceId.isNotEmpty) {
      batch.delete(_fs.collection('buying invoices').doc(invoiceId));
    }

    // 2. Delete from supplier subcollection
    if (supplierId.isNotEmpty && supplierSubDocId.isNotEmpty) {
      batch.delete(_fs
          .collection('suppliers')
          .doc(supplierId)
          .collection('buying invoices')
          .doc(supplierSubDocId));
    }
    if (supplierId.isNotEmpty &&
        invoiceId.isNotEmpty &&
        invoiceId != supplierSubDocId) {
      batch.delete(_fs
          .collection('suppliers')
          .doc(supplierId)
          .collection('buying invoices')
          .doc(invoiceId));
    }

    // 3. Decrement stock for each product line (purchase increased stock, deleting it removes that stock)
    for (final product in products) {
      if (product is! Map) continue;
      final double qty = _extractQty(product);
      if (qty <= 0) continue;
      final pRef = await _resolveProductRef(product);
      if (pRef != null) {
        batch.update(
          pRef,
          {
            'quantity': FieldValue.increment(-qty),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        batch.set(pRef.collection('changes').doc(), {
          'date': FieldValue.serverTimestamp(),
          'amount': qty,
          'type': 'decrease',
          'reason': 'delete_buying_invoice',
        });
      }
    }

    // 4. Delete balance history entries. Reconciliation below derives the
    // supplier balance from the remaining invoices and vouchers.
    if (supplierId.isNotEmpty) {
      if (invoiceId.isNotEmpty) {
        batch.delete(_fs
            .collection('suppliers')
            .doc(supplierId)
            .collection('balanceHistory')
            .doc('${invoiceId}_buying'));
        batch.delete(_fs
            .collection('suppliers')
            .doc(supplierId)
            .collection('balanceHistory')
            .doc('${invoiceId}_pay'));
      }
      if (supplierSubDocId.isNotEmpty && supplierSubDocId != invoiceId) {
        batch.delete(_fs
            .collection('suppliers')
            .doc(supplierId)
            .collection('balanceHistory')
            .doc('${supplierSubDocId}_buying'));
        batch.delete(_fs
            .collection('suppliers')
            .doc(supplierId)
            .collection('balanceHistory')
            .doc('${supplierSubDocId}_pay'));
      }
    }

    // 6. If paidAmount > 0, return cash back to mainBox
    if (paidAmount > 0) {
      final boxRef = _fs.collection('box').doc('mainBox');
      batch.set(
        boxRef,
        {'value': FieldValue.increment(paidAmount)},
        SetOptions(merge: true),
      );
    }

    batch.set(markerRef, {
      'type': 'deleteBuyingInvoice',
      'invoiceId': invoiceId,
      'appliedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    if (supplierId.isNotEmpty) {
      await SupplierInvoiceBalanceSyncService.syncForSupplier(supplierId);
    }
  }

  // ── Create Client (offline sync) ──────────────────────────────────────────

  /// Syncs an offline-created client document to Firestore.
  /// Writes the client doc and (if balance != 0) an opening balanceHistory entry.
  Future<void> _syncCreateClient(Map<String, dynamic> payload) async {
    final String clientId = payload['clientId'] as String? ?? '';
    final Map<String, dynamic> data =
        Map<String, dynamic>.from(payload['data'] as Map? ?? {});
    final double openingBalance =
        (payload['openingBalance'] as num?)?.toDouble() ?? 0.0;

    if (clientId.isEmpty) {
      throw ArgumentError('createClient payload missing clientId');
    }

    // Remove the local 'id' field before writing — Firestore uses doc ID.
    data.remove('id');

    final docRef = _fs.collection('clients').doc(clientId);

    // Check if doc already exists (e.g. written on another device while offline).
    final existingSnap = await docRef.get();
    if (existingSnap.exists) {
      // Already synced — nothing to do.
      await ClientRepository.instance
          .upsertLocal(clientId, existingSnap.data()!);
      return;
    }

    final batch = _fs.batch();
    batch.set(docRef, data, SetOptions(merge: true));

    if (openingBalance != 0) {
      final histRef = docRef.collection('balanceHistory').doc();
      batch.set(histRef, {
        'enteredBalance': openingBalance,
        'balanceBefore': 0.0,
        'type': 'opening',
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    if (openingBalance != 0) {
      await ClientInvoiceBalanceSyncService.syncForClient(clientId);
    }

    // Update local cache with confirmed Firestore data.
    await ClientRepository.instance.upsertLocal(clientId, data);
  }

  // ── Create Supplier (offline sync) ────────────────────────────────────────

  /// Syncs an offline-created supplier document to Firestore.
  Future<void> _syncCreateSupplier(Map<String, dynamic> payload) async {
    final String supplierId = payload['supplierId'] as String? ?? '';
    final Map<String, dynamic> data =
        Map<String, dynamic>.from(payload['data'] as Map? ?? {});
    final double openingBalance =
        (payload['openingBalance'] as num?)?.toDouble() ?? 0.0;

    if (supplierId.isEmpty) {
      throw ArgumentError('createSupplier payload missing supplierId');
    }

    data.remove('id');

    final docRef = _fs.collection('suppliers').doc(supplierId);

    final existingSnap = await docRef.get();
    if (existingSnap.exists) {
      await SupplierRepository.instance
          .upsertLocal(supplierId, existingSnap.data()!);
      return;
    }

    final batch = _fs.batch();
    batch.set(docRef, data, SetOptions(merge: true));

    if (openingBalance != 0) {
      final voucherRef = _fs.collection('supplier_vouchers').doc();
      batch.set(voucherRef, {
        'supplierId': supplierId,
        'supplierName': data['name'],
        'direction': 'له',
        'amount': openingBalance,
        'description': 'رصيد افتتاحي',
        'date': FieldValue.serverTimestamp(),
        'timestamp': FieldValue.serverTimestamp(),
      });

      final histRef = docRef.collection('balanceHistory').doc();
      batch.set(histRef, {
        'enteredBalance': openingBalance,
        'balanceBefore': 0.0,
        'type': 'opening',
        'direction': 'له',
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    if (openingBalance != 0) {
      await SupplierInvoiceBalanceSyncService.syncForSupplier(supplierId);
    }

    await SupplierRepository.instance.upsertLocal(supplierId, data);
  }

  // ── Delete Quote (offline sync) ───────────────────────────────────────────
  Future<void> _syncDeleteQuote(Map<String, dynamic> payload) async {
    final String quoteId = payload['quoteId'];
    if (quoteId.isNotEmpty) {
      await _fs.collection('price_quotes').doc(quoteId).delete();
    }
  }

  // ── Save Expense (offline sync) ───────────────────────────────────────────
  Future<void> _syncSaveExpense(Map<String, dynamic> payload) async {
    final String id = payload['id'];
    final Map<String, dynamic> data =
        Map<String, dynamic>.from(payload['data']);

    if (data['dateTimestamp'] is String) {
      data['dateTimestamp'] =
          Timestamp.fromDate(DateTime.parse(data['dateTimestamp'] as String));
    }
    data['time'] = FieldValue.serverTimestamp();

    await _fs.collection('expenses').doc(id).set(data, SetOptions(merge: true));
  }

  // ── Delete Expense (offline sync) ─────────────────────────────────────────
  Future<void> _syncDeleteExpense(Map<String, dynamic> payload) async {
    final String id = payload['id'];
    if (id.isNotEmpty) {
      await _fs.collection('expenses').doc(id).delete();
    }
  }

  // ── Update Box (offline sync) ─────────────────────────────────────────────
  Future<void> _syncUpdateBox(Map<String, dynamic> payload) async {
    final double changeAmount = (payload['changeAmount'] as num).toDouble();
    final double value = (payload['value'] as num).toDouble();
    final String type = payload['type']?.toString() ?? 'addition';
    final String name = payload['name']?.toString() ?? '';
    final DateTime date = payload['date'] != null
        ? DateTime.parse(payload['date'] as String)
        : DateTime.now();

    final boxRef = _fs.collection('box').doc('mainBox');
    final batch = _fs.batch();

    batch.set(
      boxRef,
      {'value': FieldValue.increment(changeAmount)},
      SetOptions(merge: true),
    );

    batch.set(boxRef.collection('changes').doc(), {
      'date': Timestamp.fromDate(date),
      'value': value,
      'type': type,
      if (name.isNotEmpty) 'name': name,
    });

    await batch.commit();
  }

  // ── Update Stock (offline sync) ───────────────────────────────────────────
  Future<void> _syncUpdateStock(Map<String, dynamic> payload) async {
    final String productId = payload['productId'];
    final double delta = (payload['delta'] as num).toDouble();
    final String changeType = payload['changeType']?.toString() ?? 'adjustment';
    final DateTime date = payload['date'] != null
        ? DateTime.parse(payload['date'] as String)
        : DateTime.now();

    final prodRef = _fs.collection('products').doc(productId);
    final batch = _fs.batch();

    batch.update(prodRef, {
      'quantity': FieldValue.increment(delta),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.set(prodRef.collection('changes').doc(), {
      'date': Timestamp.fromDate(date),
      'amount': delta.abs(),
      'type': changeType,
    });

    await batch.commit();
  }
}
