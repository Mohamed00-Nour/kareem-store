import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../Services/customer_balance_store.dart';
import '../Services/supplier_balance_store.dart';
import '../local_db/hive_init.dart';
import '../repositories/balance_history_repository.dart';
import '../repositories/box_repository.dart';
import '../repositories/client_repository.dart';
import '../repositories/customer_voucher_repository.dart';
import '../repositories/data_sync_service.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/quote_repository.dart';
import '../repositories/supplier_repository.dart';
import '../repositories/supplier_voucher_repository.dart';
import 'financial_cloud_store.dart';
import 'firestore_read_diagnostics.dart';
import 'local_operation_journal.dart';

/// Imports cloud changes into Hive without reopening every business collection
/// on every application start.
///
/// Financial uploads atomically allocate a monotonically increasing receipt
/// sequence. This service persists the last imported sequence in Hive and asks
/// Firestore only for later receipts. An installation without a cursor performs
/// one compatibility baseline before enabling the incremental feed.
class RealtimeSyncService {
  RealtimeSyncService._();
  static final instance = RealtimeSyncService._();

  FirebaseFirestore get _fs => FirebaseFirestore.instance;
  final List<StreamSubscription> _subscriptions = [];
  Future<void> _receiptWork = Future.value();
  Future<void>? _startFuture;
  Timer? _restartTimer;
  bool _isListening = false;

  bool get isListening => _isListening;

  Future<void> startListening() {
    final running = _startFuture;
    if (running != null) return running;
    if (_isListening) return Future.value();

    final future = _start();
    _startFuture = future;
    return future.whenComplete(() {
      if (identical(_startFuture, future)) _startFuture = null;
    });
  }

  Future<void> _start() async {
    try {
      _restartTimer?.cancel();
      var cursor = _storedSequence();
      if (cursor == null) {
        cursor = await _runCompatibilityBaseline();
      } else {
        // These collections are not all part of the financial transaction
        // feed yet. Their existing startup sync remains until each has its own
        // durable change event.
        await DataSyncService.instance
            .syncOnStartup(includeRealtimeCollections: false);
      }

      _listenForFinancialReceipts(cursor);

      // Non-financial product writers publish updatedAt. This filtered listener
      // imports only later product changes; invoice stock changes also arrive
      // through the sequenced receipt feed.
      _listenProducts();
      _isListening = true;
      await appMetaBox.delete('cloudRefreshError');
    } catch (error) {
      _isListening = false;
      await appMetaBox.put('cloudRefreshError', error.toString());
    }
  }

  int? _storedSequence() {
    final raw = appMetaBox.get(HiveMetaKeys.financialChangeSequence);
    return raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
  }

  /// Establishes a safe point before downloading the legacy baseline. Changes
  /// committed after that point are replayed by the receipt listener, so a
  /// concurrent Device A upload cannot fall between the baseline and cursor.
  Future<int> _runCompatibilityBaseline() async {
    final headSnapshot =
        await _fs.doc(FinancialCloudUploader.feedHeadPath).get();
    FirestoreReadDiagnostics.queryResult(
      FinancialCloudUploader.feedHeadPath,
      headSnapshot.exists ? 1 : 0,
      trigger: 'compatibility bootstrap head',
      fromCache: headSnapshot.metadata.isFromCache,
    );
    final head = (headSnapshot.data()?['lastSequence'] as num?)?.toInt() ?? 0;

    await DataSyncService.instance
        .syncOnStartup(includeRealtimeCollections: true);
    final syncError = appMetaBox.get('cloudRefreshError');
    if (syncError != null) throw StateError(syncError.toString());

    // Import historical financial events once for a new installation. This is
    // one collection-group query rather than one subcollection query per party.
    // The document count is inherently proportional to historical operations;
    // later launches use only sequenced receipts.
    final operations = await _fs.collectionGroup('financialOperations').get();
    FirestoreReadDiagnostics.queryResult(
      'collectionGroup(financialOperations)',
      operations.docs.length,
      trigger: 'compatibility bootstrap',
      fromCache: operations.metadata.isFromCache,
    );
    for (final doc in operations.docs) {
      final parent = doc.reference.parent.parent;
      if (parent == null) continue;
      if (parent.parent.id == 'clients') {
        await LocalOperationJournal.exclusive(() =>
            CustomerBalanceStore.importEvent(parent.id, doc.id, doc.data()));
      } else if (parent.parent.id == 'suppliers') {
        await LocalOperationJournal.exclusive(() =>
            SupplierBalanceStore.importEvent(parent.id, doc.id, doc.data()));
      }
    }

    // Legacy statement rows live in a separate collection group. Import those
    // once for a new installation.
    final histories = await _fs.collectionGroup('balanceHistory').get();
    FirestoreReadDiagnostics.queryResult(
      'collectionGroup(balanceHistory)',
      histories.docs.length,
      trigger: 'compatibility bootstrap',
      fromCache: histories.metadata.isFromCache,
    );
    for (final doc in histories.docs) {
      final parent = doc.reference.parent.parent;
      if (parent == null) continue;
      if (parent.parent.id == 'clients') {
        await BalanceHistoryRepository.instance
            .mergeCloudClientHistory(parent.id, doc.id, doc.data());
      } else if (parent.parent.id == 'suppliers') {
        await BalanceHistoryRepository.instance
            .mergeCloudSupplierHistory(parent.id, doc.id, doc.data());
      }
    }

    await appMetaBox.put(HiveMetaKeys.financialChangeSequence, head);
    await appMetaBox.flush();
    return head;
  }

  void _listenForFinancialReceipts(int cursor) {
    final query = _fs
        .collection('financial_operation_receipts')
        .where('sequence', isGreaterThan: cursor)
        .orderBy('sequence');
    const identity = 'financial_operation_receipts sequence > cursor';
    const trigger = 'realtime financial feed';
    FirestoreReadDiagnostics.listenerAttached(identity, trigger: trigger);
    _subscriptions.add(query.snapshots().listen((snapshot) {
      FirestoreReadDiagnostics.listenerSnapshot(
        identity,
        snapshot.docs.length,
        trigger: trigger,
        fromCache: snapshot.metadata.isFromCache,
        changes: snapshot.docChanges.length,
      );
      // Stream callbacks do not await async listeners. Chain snapshots so a
      // later receipt can never advance the cursor past a failed earlier one.
      _receiptWork = _receiptWork.then((_) async {
        final added = snapshot.docChanges
            .where((change) => change.type == DocumentChangeType.added)
            .map((change) => change.doc)
            .toList()
          ..sort((a, b) => _receiptSequence(a.data() ?? const {})
              .compareTo(_receiptSequence(b.data() ?? const {})));
        for (final doc in added) {
          final data = doc.data();
          if (data != null) await _importReceipt(doc.id, data);
        }
      }).catchError((Object error) async {
        await appMetaBox.put('cloudRefreshError', error.toString());
        await stopListening();
      });
    }, onError: _handleStreamError));
  }

  static int _receiptSequence(Map<String, dynamic> data) =>
      (data['sequence'] as num?)?.toInt() ?? 0;

  Future<void> _importReceipt(
      String receiptId, Map<String, dynamic> receipt) async {
    final sequence = _receiptSequence(receipt);
    final current = _storedSequence() ?? 0;
    if (sequence <= current) return;

    final versions = Map<String, dynamic>.from(
        receipt['versions'] as Map? ?? const <String, dynamic>{});
    final paths = versions.keys.toList()
      ..sort((a, b) => a.split('/').length.compareTo(b.split('/').length));
    for (final path in paths) {
      if (!_isLocallyCachedPath(path)) continue;
      final snapshot = await _fs.doc(path).get();
      FirestoreReadDiagnostics.queryResult(
        'receipt path $path',
        snapshot.exists ? 1 : 0,
        trigger: 'realtime receipt import',
        fromCache: snapshot.metadata.isFromCache,
      );
      final data = snapshot.data();
      await _mergePath(path, data);
    }

    final operationId = receipt['operationId']?.toString().isNotEmpty == true
        ? receipt['operationId'].toString()
        : receiptId;
    for (final rawId in receipt['customerIds'] as List? ?? const []) {
      final clientId = rawId.toString();
      final eventSnapshot = await _fs
          .doc('clients/$clientId/financialOperations/$operationId')
          .get();
      FirestoreReadDiagnostics.queryResult(
        'client financial operation by id',
        eventSnapshot.exists ? 1 : 0,
        trigger: 'realtime receipt import',
        fromCache: eventSnapshot.metadata.isFromCache,
      );
      final event = eventSnapshot.data();
      if (event != null) {
        await LocalOperationJournal.exclusive(() =>
            CustomerBalanceStore.importEvent(clientId, operationId, event));
      }
    }
    for (final rawId in receipt['supplierIds'] as List? ?? const []) {
      final supplierId = rawId.toString();
      final eventSnapshot = await _fs
          .doc('suppliers/$supplierId/financialOperations/$operationId')
          .get();
      FirestoreReadDiagnostics.queryResult(
        'supplier financial operation by id',
        eventSnapshot.exists ? 1 : 0,
        trigger: 'realtime receipt import',
        fromCache: eventSnapshot.metadata.isFromCache,
      );
      final event = eventSnapshot.data();
      if (event != null) {
        await LocalOperationJournal.exclusive(() =>
            SupplierBalanceStore.importEvent(supplierId, operationId, event));
      }
    }

    // Advance only after every affected Hive record is durable. A crash before
    // this write safely replays the idempotent receipt on the next start.
    await appMetaBox.put(HiveMetaKeys.financialChangeSequence, sequence);
    await appMetaBox.flush();
  }

  static bool _isLocallyCachedPath(String path) {
    final parts = path.split('/');
    if (parts.length == 2) {
      return const {
        'products',
        'invoices',
        'returnInvoices',
        'clients',
        'price_quotes',
        'client_vouchers',
        'supplier_vouchers',
        'suppliers',
        'buying invoices',
        'box',
      }.contains(parts.first);
    }
    return parts.length == 4 && parts[2] == 'balanceHistory';
  }

  Future<void> _mergePath(String path, Map<String, dynamic>? data) async {
    final parts = path.split('/');
    if (parts.length == 4 && parts[2] == 'balanceHistory') {
      if (parts[0] == 'clients') {
        await BalanceHistoryRepository.instance
            .mergeCloudClientHistory(parts[1], parts[3], data);
      } else if (parts[0] == 'suppliers') {
        await BalanceHistoryRepository.instance
            .mergeCloudSupplierHistory(parts[1], parts[3], data);
      }
      return;
    }
    if (parts.length != 2) return;
    switch (parts[0]) {
      case 'products':
        await ProductRepository.instance.mergeCloud(parts[1], data);
        break;
      case 'invoices':
      case 'returnInvoices':
        await InvoiceRepository.instance
            .mergeCloudInvoice(parts[0], parts[1], data);
        break;
      case 'clients':
        await ClientRepository.instance.mergeCloud(parts[1], data);
        break;
      case 'price_quotes':
        await QuoteRepository.instance.mergeCloud(parts[1], data);
        break;
      case 'client_vouchers':
        await CustomerVoucherRepository.mergeCloud(parts[1], data);
        break;
      case 'supplier_vouchers':
        await SupplierVoucherRepository.mergeCloud(parts[1], data);
        break;
      case 'suppliers':
        await SupplierRepository.instance.mergeCloud(parts[1], data);
        break;
      case 'buying invoices':
        await InvoiceRepository.instance.mergeCloudBuying(parts[1], data);
        break;
      case 'box':
        if (data != null) await BoxRepository.instance.mergeCloud(data);
        break;
    }
  }

  void _listenProducts() {
    final rawCursor =
        appMetaBox.get(HiveMetaKeys.lastProductSyncAt)?.toString();
    final cursor = DateTime.tryParse(rawCursor ?? '');
    Query<Map<String, dynamic>> query = _fs.collection('products');
    if (cursor != null) {
      query = query.where(
        'updatedAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(cursor),
      );
    }
    const identity = 'products where updatedAt >= cursor';
    const trigger = 'realtime product feed';
    FirestoreReadDiagnostics.listenerAttached(identity, trigger: trigger);
    _subscriptions.add(query.snapshots().listen(
      (snapshot) async {
        FirestoreReadDiagnostics.listenerSnapshot(
          identity,
          snapshot.docs.length,
          trigger: trigger,
          fromCache: snapshot.metadata.isFromCache,
          changes: snapshot.docChanges.length,
        );
        try {
          DateTime? newest;
          for (final change in snapshot.docChanges) {
            final data = change.doc.data();
            await ProductRepository.instance.mergeCloud(
              change.doc.id,
              change.type == DocumentChangeType.removed ? null : data,
            );
            final updatedAt = data?['updatedAt'];
            final changedAt = updatedAt is Timestamp
                ? updatedAt.toDate()
                : updatedAt is DateTime
                    ? updatedAt
                    : null;
            if (changedAt != null &&
                (newest == null || changedAt.isAfter(newest))) {
              newest = changedAt;
            }
          }
          if (!snapshot.metadata.isFromCache && newest != null) {
            await appMetaBox.put(
              HiveMetaKeys.lastProductSyncAt,
              newest.toIso8601String(),
            );
          }
        } catch (error) {
          await appMetaBox.put('cloudRefreshError', error.toString());
        }
      },
      onError: _handleStreamError,
    ));
  }

  void _handleStreamError(Object error) {
    appMetaBox.put('cloudRefreshError', error.toString());
    unawaited(stopListening().whenComplete(() {
      _restartTimer?.cancel();
      _restartTimer = Timer(
        const Duration(minutes: 1),
        () => unawaited(startListening()),
      );
    }));
  }

  Future<void> stopListening() async {
    final hadSubscriptions = _subscriptions.isNotEmpty;
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    if (hadSubscriptions) {
      FirestoreReadDiagnostics.listenerDetached(
        'financial_operation_receipts sequence > cursor',
        trigger: 'realtime financial feed',
      );
      FirestoreReadDiagnostics.listenerDetached(
        'products where updatedAt >= cursor',
        trigger: 'realtime product feed',
      );
    }
    _isListening = false;
  }
}
