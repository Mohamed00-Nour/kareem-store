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
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

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
        await _syncDeleteReturn(payload);
        break;
      case 'createQuote':
        await _syncCreateQuote(payload);
        break;
      case 'createBuyingInvoice':
        await _syncCreateBuyingInvoice(payload);
        break;
      case 'createClient':
        await _syncCreateClient(payload);
        break;
      case 'createSupplier':
        await _syncCreateSupplier(payload);
        break;
      default:
        throw UnsupportedError('Unknown operation type: $operationType');
    }
  }

  // ── Operation Handlers ────────────────────────────────────────────────────

  /// Syncs an offline-created selling invoice to Firestore as a single batch:
  /// - Invoice document in clients/{clientId}/invoices
  /// - Stock decrements for each product line (FieldValue.increment)
  /// - Client balance update
  Future<void> _syncCreateInvoice(Map<String, dynamic> payload) async {
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

    // 1. Write the invoice document.
    final invoiceRef = _fs
        .collection('clients')
        .doc(clientId)
        .collection('invoices')
        .doc(invoiceId);
    batch.set(invoiceRef, invoiceData);

    // 2. Decrement stock for each product (atomic — safe for multi-device).
    for (final product in products) {
      if (product is! Map) continue;
      final String productName = product['product']?.toString() ?? '';
      final double qty = (product['amount'] as num?)?.toDouble() ?? 0.0;
      if (productName.isEmpty || qty <= 0) continue;

      final prodQuery = await _fs
          .collection('products')
          .where('name', isEqualTo: productName)
          .limit(1)
          .get();
      if (prodQuery.docs.isNotEmpty) {
        batch.update(
          prodQuery.docs.first.reference,
          {'quantity': FieldValue.increment(-qty)},
        );
        // Update local cache too.
        await ProductRepository.instance.upsertLocal(
          prodQuery.docs.first.id,
          {...prodQuery.docs.first.data(), 'quantity': 0}, // will be refreshed on next delta sync
        );
      }
    }

    // 3. Update client running balance.
    final double newBalance = totalSum - paidAmount;
    batch.update(
      _fs.collection('clients').doc(clientId),
      {'balance': FieldValue.increment(newBalance)},
    );

    await batch.commit();

    // Update local client cache.
    await ClientRepository.instance.deltaSync();
  }

  Future<void> _syncEditInvoice(Map<String, dynamic> payload) async {
    final String clientId = payload['clientId'];
    final String invoiceId = payload['invoiceId'];
    final Map<String, dynamic> updateData =
        Map<String, dynamic>.from(payload['updateData']);

    // Convert ISO date string back to DateTime for Firestore
    if (updateData['date'] is String) {
      updateData['date'] = DateTime.parse(updateData['date'] as String);
    }

    // Update root invoice document
    await _fs
        .collection('invoices')
        .doc(invoiceId)
        .update(updateData);

    // Also update in client sub-collection if clientId is available
    if (clientId.isNotEmpty) {
      try {
        // Find the matching sub-doc by invoiceId field
        final subQuery = await _fs
            .collection('clients')
            .doc(clientId)
            .collection('invoices')
            .where('invoiceId', isEqualTo: invoiceId)
            .limit(1)
            .get();
        if (subQuery.docs.isNotEmpty) {
          await subQuery.docs.first.reference.update(updateData);
        }
      } catch (_) {
        // Non-critical: sub-collection will be aligned by balance sync later
      }
    }
  }

  Future<void> _syncDeleteInvoice(Map<String, dynamic> payload) async {
    final String clientId = payload['clientId'];
    final String invoiceId = payload['invoiceId'];
    final List<dynamic> products = payload['products'] ?? [];
    final double totalSum = (payload['totalSum'] as num).toDouble();
    final double paidAmount = (payload['paidAmount'] as num).toDouble();

    final batch = _fs.batch();

    // 1. Delete invoice document.
    batch.delete(_fs
        .collection('clients')
        .doc(clientId)
        .collection('invoices')
        .doc(invoiceId));

    // 2. Restore stock quantities.
    for (final product in products) {
      if (product is! Map) continue;
      final String productName = product['product']?.toString() ?? '';
      final double qty = (product['amount'] as num?)?.toDouble() ?? 0.0;
      if (productName.isEmpty || qty <= 0) continue;
      final prodQuery = await _fs
          .collection('products')
          .where('name', isEqualTo: productName)
          .limit(1)
          .get();
      if (prodQuery.docs.isNotEmpty) {
        batch.update(
          prodQuery.docs.first.reference,
          {'quantity': FieldValue.increment(qty)},
        );
      }
    }

    // 3. Reverse client balance.
    final double balanceToReverse = totalSum - paidAmount;
    batch.update(
      _fs.collection('clients').doc(clientId),
      {'balance': FieldValue.increment(-balanceToReverse)},
    );

    await batch.commit();
    await ClientRepository.instance.deltaSync();
  }

  Future<void> _syncAdjustClientBalance(Map<String, dynamic> payload) async {
    final String clientId = payload['clientId'];
    final double amount = (payload['amount'] as num).toDouble();
    final bool isAddition = payload['isAddition'] == true;
    final Map<String, dynamic> logEntry =
        Map<String, dynamic>.from(payload['logEntry']);

    final batch = _fs.batch();

    // 1. Update client balance.
    batch.update(
      _fs.collection('clients').doc(clientId),
      {
        'balance': FieldValue.increment(isAddition ? -amount : amount),
      },
    );

    // 2. Write balance history log entry.
    batch.set(
      _fs.collection('clients').doc(clientId).collection('balanceHistory').doc(),
      logEntry,
    );

    await batch.commit();
    await ClientRepository.instance.updateLocalBalance(
      clientId,
      (payload['newBalance'] as num).toDouble(),
    );
  }

  Future<void> _syncAdjustSupplierBalance(
      Map<String, dynamic> payload) async {
    final String supplierId = payload['supplierId'];
    final double amount = (payload['amount'] as num).toDouble();
    final bool isAddition = payload['isAddition'] == true;
    final Map<String, dynamic> logEntry =
        Map<String, dynamic>.from(payload['logEntry']);

    final batch = _fs.batch();

    batch.update(
      _fs.collection('suppliers').doc(supplierId),
      {
        'balance': FieldValue.increment(isAddition ? -amount : amount),
      },
    );

    batch.set(
      _fs
          .collection('suppliers')
          .doc(supplierId)
          .collection('balanceHistory')
          .doc(),
      logEntry,
    );

    await batch.commit();
    await SupplierRepository.instance.updateLocalBalance(
      supplierId,
      (payload['newBalance'] as num).toDouble(),
    );
  }

  Future<void> _syncCreateProduct(Map<String, dynamic> payload) async {
    final String productId = payload['productId'];
    final Map<String, dynamic> data =
        Map<String, dynamic>.from(payload['data']);
    await _fs.collection('products').doc(productId).set(data);
    await ProductRepository.instance.upsertLocal(productId, data);
  }

  Future<void> _syncEditProduct(Map<String, dynamic> payload) async {
    final String productId = payload['productId'];
    final Map<String, dynamic> data =
        Map<String, dynamic>.from(payload['data']);
    await _fs.collection('products').doc(productId).update(data);
    await ProductRepository.instance.upsertLocal(productId, data);
  }

  Future<void> _syncDeleteProduct(Map<String, dynamic> payload) async {
    final String productId = payload['productId'];
    await _fs.collection('products').doc(productId).delete();
    await ProductRepository.instance.deleteLocal(productId);
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

    // 1. Write the return invoice document.
    final invoiceRef = _fs.collection('returnInvoices').doc(invoiceId);
    batch.set(invoiceRef, invoiceData);

    // 2. Restore stock for each product (atomic — safe for multi-device).
    for (final product in products) {
      if (product is! Map) continue;
      final String productName = product['product']?.toString() ?? '';
      final double qty = (product['amount'] as num?)?.toDouble() ?? 0.0;
      if (productName.isEmpty || qty <= 0) continue;

      final prodQuery = await _fs
          .collection('products')
          .where('name', isEqualTo: productName)
          .limit(1)
          .get();
      if (prodQuery.docs.isNotEmpty) {
        batch.update(
          prodQuery.docs.first.reference,
          {'quantity': FieldValue.increment(qty)}, // Restore stock
        );
      }
    }

    // 3. Update client running balance (return reduces debt).
    final double balanceReduction = totalSum - paidAmount;
    batch.update(
      _fs.collection('clients').doc(clientId),
      {'balance': FieldValue.increment(-balanceReduction)},
    );

    // 4. Write to client sub-collection.
    batch.set(
      _fs.collection('clients').doc(clientId).collection('returnInvoices').doc(),
      invoiceData,
    );

    // 5. Cash box update (subtract refund paid).
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
    final String clientId = payload['clientId'];
    final String invoiceId = payload['invoiceId'];
    final List<dynamic> products = payload['products'] ?? [];
    final double totalSum = (payload['totalSum'] as num).toDouble();
    final double paidAmount = (payload['paidAmount'] as num).toDouble();

    final batch = _fs.batch();

    // Delete return invoice.
    batch.delete(_fs.collection('returnInvoices').doc(invoiceId));

    // Reverse stock restores (decrement stock back).
    for (final product in products) {
      if (product is! Map) continue;
      final String productName = product['product']?.toString() ?? '';
      final double qty = (product['amount'] as num?)?.toDouble() ?? 0.0;
      if (productName.isEmpty || qty <= 0) continue;
      final prodQuery = await _fs
          .collection('products')
          .where('name', isEqualTo: productName)
          .limit(1)
          .get();
      if (prodQuery.docs.isNotEmpty) {
        batch.update(
          prodQuery.docs.first.reference,
          {'quantity': FieldValue.increment(-qty)},
        );
      }
    }

    // Reverse client balance change.
    final double balanceToReverse = totalSum - paidAmount;
    batch.update(
      _fs.collection('clients').doc(clientId),
      {'balance': FieldValue.increment(balanceToReverse)},
    );

    await batch.commit();
    await ClientRepository.instance.deltaSync();
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
    final batch = _fs.batch();
    final String supplierId = payload['supplierId'] ?? '';
    final String supplierName = payload['supplierName'] ?? '';
    final String invoiceId = payload['invoiceId'];
    final Map<String, dynamic> invoiceData =
        Map<String, dynamic>.from(payload['invoiceData']);
    final List<dynamic> products = payload['products'] ?? [];
    final double paidAmount =
        (payload['paidAmount'] as num?)?.toDouble() ?? 0.0;

    if (invoiceData['date'] is String) {
      invoiceData['date'] = DateTime.parse(invoiceData['date'] as String);
    }

    // 1. Write the buying invoice document.
    final invoiceRef = _fs.collection('buying invoices').doc(invoiceId);
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
      final String productName = product['product']?.toString() ?? '';
      final double qty = (product['amount'] as num?)?.toDouble() ?? 0.0;
      if (productName.isEmpty || qty <= 0) continue;

      final prodQuery = await _fs
          .collection('products')
          .where('name', isEqualTo: productName)
          .limit(1)
          .get();
      if (prodQuery.docs.isNotEmpty) {
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
        batch.update(prodQuery.docs.first.reference, updateMap);
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
      await ClientRepository.instance.upsertLocal(
          clientId, existingSnap.data()!);
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
}
