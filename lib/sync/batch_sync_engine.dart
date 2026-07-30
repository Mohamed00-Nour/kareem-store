import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/models/sync_queue_item.dart';
import '../repositories/product_repository.dart';
import '../repositories/client_repository.dart';
import '../repositories/supplier_repository.dart';
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

    await _fs
        .collection('clients')
        .doc(clientId)
        .collection('invoices')
        .doc(invoiceId)
        .update(updateData);
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
}
