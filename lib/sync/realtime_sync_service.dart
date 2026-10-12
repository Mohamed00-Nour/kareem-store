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
import '../repositories/payment_breakdown_repository.dart';
import 'financial_cloud_store.dart';
import 'cloud_snapshot_guard.dart';
import 'firestore_read_diagnostics.dart';
import 'firestore_sync_checkpoint.dart';
import 'local_operation_journal.dart';

/// Imports cloud changes into Hive without reopening every business collection
/// on every application start.
///
/// Financial uploads atomically allocate a monotonically increasing receipt
/// sequence. This service persists the last imported sequence in Hive and asks
/// Firestore only for later receipts. An installation without a cursor performs
/// one compatibility baseline before enabling the incremental feed. Upgrades
/// from cache-based checkpoints also receive a verified recovery baseline.
class RealtimeSyncService {
  RealtimeSyncService({FirebaseFirestore? firestore}) : _firestore = firestore;
  static final instance = RealtimeSyncService();

  final FirebaseFirestore? _firestore;
  FirebaseFirestore get _fs => _firestore ?? FirebaseFirestore.instance;
  static const _baselineVersion = 2;
  static const _baselineKey = 'financialBaselineVersion';
  static const _deferredPrefix = 'deferredFinancialPath:';
  static const _server = GetOptions(source: Source.server);
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
      await refreshFromServer();
      final cursor = _storedSequence() ?? 0;
      await DataSyncService.instance
          .syncOnStartup(includeRealtimeCollections: false);

      _listenForFinancialReceipts(cursor);

      // Non-financial product writers publish updatedAt. This filtered listener
      // imports only later product changes; invoice stock changes also arrive
      // through the sequenced receipt feed.
      _listenProducts();
      _isListening = true;
      await appMetaBox.delete('cloudRefreshError');
    } catch (error) {
      _handleStreamError(error);
    }
  }

  /// A repair ignores old timestamp checkpoints and fills gaps left by earlier
  /// cache-based downloads. Normal startup performs this once after upgrading.
  Future<void> refreshFromServer({bool repair = false}) =>
      _enqueueDownload(() async {
        var cursor = _storedSequence();
        if (repair ||
            cursor == null ||
            appMetaBox.get(_baselineKey) != _baselineVersion) {
          cursor = await _runCompatibilityBaseline();
        }
        await _retryDeferredPaths();
        final snapshot = await _serverQuery(
            _receiptQuery(cursor), 'financial receipt catch-up');
        for (final doc in snapshot.docs) {
          _requireServer(doc.metadata, doc.reference.path);
          await _importReceipt(doc.id, doc.data());
        }
        await appMetaBox.delete('cloudRefreshError');
        await appMetaBox.delete('financialDownloadError');
      });

  bool get hasDeferredPaths =>
      appMetaBox.keys.any((key) => key.toString().startsWith(_deferredPrefix));

  Future<void> retryDeferredPaths() => _enqueueDownload(_retryDeferredPaths);

  Future<void> _enqueueDownload(Future<void> Function() action) {
    final work = _receiptWork
        .then((_) => action())
        .catchError((Object error, StackTrace stack) async {
      await appMetaBox.putAll({
        'cloudRefreshError': error.toString(),
        'financialDownloadError': error.toString()
      });
      Error.throwWithStackTrace(error, stack);
    });
    // Keep the serialization chain usable after a failed download. The caller
    // still receives the error; no checkpoint is advanced for that failure.
    _receiptWork = work.then<void>((_) {}, onError: (Object _) {});
    return work;
  }

  static void _requireServer(SnapshotMetadata metadata, String identity) {
    if (metadata.isFromCache || metadata.hasPendingWrites) {
      throw StateError('Server-confirmed financial data required: $identity');
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _serverDocument(
      String path) async {
    final snapshot =
        await _fs.doc(path).get(_server).timeout(const Duration(seconds: 30));
    _requireServer(snapshot.metadata, path);
    FirestoreReadDiagnostics.queryResult(path, snapshot.exists ? 1 : 0,
        trigger: 'verified financial download', fromCache: false);
    return snapshot;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _serverQuery(
      Query<Map<String, dynamic>> query, String identity) async {
    final snapshot =
        await query.get(_server).timeout(const Duration(seconds: 30));
    _requireServer(snapshot.metadata, identity);
    FirestoreReadDiagnostics.queryResult(identity, snapshot.docs.length,
        trigger: 'verified financial download', fromCache: false);
    return snapshot;
  }

  Query<Map<String, dynamic>> _receiptQuery(int cursor) => _fs
      .collection('financial_operation_receipts')
      .where('sequence', isGreaterThan: cursor)
      .orderBy('sequence');

  int? _storedSequence() {
    final raw = appMetaBox.get(HiveMetaKeys.financialChangeSequence);
    return raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
  }

  /// Establishes a safe point before downloading the legacy baseline. Changes
  /// committed after that point are replayed by the receipt listener, so a
  /// concurrent Device A upload cannot fall between the baseline and cursor.
  Future<int> _runCompatibilityBaseline() async {
    const progressKey = 'financialBaselineProgress';
    final saved = appMetaBox.get(progressKey);
    final progress = saved is Map && saved['version'] == _baselineVersion
        ? Map<String, dynamic>.from(saved)
        : <String, dynamic>{};
    if (progress.isEmpty) {
      final headSnapshot =
          await _serverDocument(FinancialCloudUploader.feedHeadPath);
      progress.addAll({
        'version': _baselineVersion,
        'head': (headSnapshot.data()?['lastSequence'] as num?)?.toInt() ?? 0,
        'completed': <String>[],
        'parties': <String>[]
      });
      await appMetaBox.put(progressKey, progress);
      await appMetaBox.flush();
    }
    final head = (progress['head'] as num).toInt();
    final completed = Set<String>.from(progress['completed'] as List);
    var parties = List<String>.from(progress['parties'] as List);
    Future<void> finishStep(String step,
        [Map<String, dynamic> checkpoints = const {}]) async {
      await _flushImports();
      completed.add(step);
      progress['completed'] = completed.toList();
      progress['parties'] = parties;
      await appMetaBox.putAll({...checkpoints, progressKey: progress});
      await appMetaBox.flush();
    }

    // Balances are needed before the larger invoice/product downloads. Stage
    // profiles until their ledger is available, then publish correct balances.
    if (!completed.contains('parties')) {
      final records = <String, Map<String, dynamic>>{};
      final checkpoints = <String, dynamic>{};
      for (final entry in const {
        'clients': HiveMetaKeys.lastClientSyncAt,
        'suppliers': HiveMetaKeys.lastSupplierSyncAt
      }.entries) {
        final snapshot = await _serverQuery(
            _fs.collection(entry.key), '${entry.key} financial baseline');
        for (final doc in snapshot.docs) {
          _requireServer(doc.metadata, doc.reference.path);
          records[doc.reference.path] = doc.data();
        }
        checkpoints[entry.value] = FirestoreSyncCheckpoint.newest(
                snapshot.docs.map((doc) => doc.data()), const ['updatedAt'])
            .toIso8601String();
      }
      parties = records.keys.toList();
      final operations =
          await _partyGroupDocuments('financialOperations', parties);
      final partyEvents = <String, Map<String, Map<String, dynamic>>>{};
      for (final doc in operations) {
        _requireServer(doc.metadata, doc.reference.path);
        final parent = doc.reference.parent.parent;
        if (parent != null) {
          (partyEvents[parent.path] ??= {})[doc.id] = doc.data();
        }
      }
      for (final record in records.entries) {
        await _importPath(record.key, record.value,
            events: partyEvents[record.key] ?? const {});
      }
      for (final doc in operations) {
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
      await finishStep('parties', checkpoints);
    }

    const collections = {
      'products': HiveMetaKeys.lastProductSyncAt,
      'invoices': HiveMetaKeys.lastInvoiceSyncAt,
      'returnInvoices': HiveMetaKeys.lastReturnInvoiceSyncAt,
      'buying invoices': HiveMetaKeys.lastBuyingInvoiceSyncAt,
      'price_quotes': HiveMetaKeys.lastQuoteSyncAt,
      'client_vouchers': null,
      'supplier_vouchers': null,
      'box': null
    };
    for (final entry in collections.entries) {
      if (completed.contains(entry.key)) continue;
      final snapshot = await _serverQuery(
          _fs.collection(entry.key), '${entry.key} financial baseline');
      for (final doc in snapshot.docs) {
        _requireServer(doc.metadata, doc.reference.path);
        await _importPath(doc.reference.path, doc.data());
      }
      await finishStep(
          entry.key,
          entry.value == null
              ? const {}
              : {
                  entry.value!: FirestoreSyncCheckpoint.newest(
                      snapshot.docs.map((doc) => doc.data()),
                      const ['updatedAt']).toIso8601String()
                });
    }
    if (!completed.contains('histories')) {
      final histories = await _partyGroupDocuments('balanceHistory', parties);
      for (final doc in histories) {
        _requireServer(doc.metadata, doc.reference.path);
        await _importPath(doc.reference.path, doc.data());
      }
      await finishStep('histories');
    }
    // The original head is retained across retries, so uploads during any
    // completed step are still replayed after this entire baseline finishes.
    await appMetaBox.delete(progressKey);
    await appMetaBox.putAll({
      HiveMetaKeys.financialChangeSequence: head,
      _baselineKey: _baselineVersion
    });
    await appMetaBox.flush();
    return head;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _partyGroupDocuments(String name, List<String> parties) async {
    try {
      return (await _serverQuery(_fs.collectionGroup(name), '$name baseline'))
          .docs;
    } on FirebaseException catch (error) {
      if (!['permission-denied', 'failed-precondition'].contains(error.code)) {
        rethrow;
      }
      // Some deployed rules allow party subcollections but not collection-group
      // queries. These reads still use ordinary Firestore permission checks.
      final documents = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final party in parties) {
        final path = '$party/$name';
        documents.addAll((await _serverQuery(_fs.collection(path), path)).docs);
      }
      return documents;
    }
  }

  Future<Map<String, Map<String, dynamic>>> _completePartyEvents(
      String path,
      Map<String, dynamic>? data,
      Map<String, Map<String, dynamic>> incoming) async {
    if (data == null || data['_deleted'] == true) return incoming;
    final requiredCount = (data['financialVersion'] as num?)?.toInt() ?? 0;
    if (requiredCount == 0) return incoming;
    final id = path.split('/')[1];
    final prefix = path.startsWith('clients/')
        ? 'customerBalanceEvent:$id:'
        : 'supplierBalanceEvent:$id:';
    final known = appMetaBox.keys
        .whereType<String>()
        .where((key) => key.startsWith(prefix))
        .map((key) => key.substring(prefix.length))
        .toSet()
      ..addAll(incoming.keys);
    if (known.length >= requiredCount) return incoming;
    final snapshot = await _serverQuery(
        _fs.collection('$path/financialOperations'),
        '$path financial ledger catch-up');
    if (snapshot.docs.length < requiredCount) {
      throw StateError(
          'Incomplete financial ledger for $path: expected at least $requiredCount events, received ${snapshot.docs.length}');
    }
    for (final doc in snapshot.docs) {
      _requireServer(doc.metadata, doc.reference.path);
    }
    return {for (final doc in snapshot.docs) doc.id: doc.data()};
  }

  void _listenForFinancialReceipts(int cursor) {
    final query = _receiptQuery(cursor);
    const identity = 'financial_operation_receipts sequence > cursor';
    const trigger = 'realtime financial feed';
    FirestoreReadDiagnostics.listenerAttached(identity, trigger: trigger);
    _subscriptions
        .add(query.snapshots(includeMetadataChanges: true).listen((snapshot) {
      FirestoreReadDiagnostics.listenerSnapshot(
        identity,
        snapshot.docs.length,
        trigger: trigger,
        fromCache: snapshot.metadata.isFromCache,
        changes: snapshot.docChanges.length,
      );
      // Stream callbacks do not await async listeners. Chain snapshots so a
      // later receipt can never advance the cursor past a failed earlier one.
      if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
        return;
      }
      unawaited(_enqueueDownload(() async {
        // A cache snapshot may contain only later receipts. Process all docs
        // again on server confirmation, including metadata-only snapshots.
        final added = snapshot.docs.toList()
          ..sort((a, b) =>
              _receiptSequence(a.data()).compareTo(_receiptSequence(b.data())));
        for (final doc in added) {
          _requireServer(doc.metadata, doc.reference.path);
          await _importReceipt(doc.id, doc.data());
        }
      }).catchError(_handleStreamError));
    }, onError: _handleStreamError));
  }

  static int _receiptSequence(Map<String, dynamic> data) =>
      (data['sequence'] as num?)?.toInt() ?? 0;

  Future<void> _importReceipt(
      String receiptId, Map<String, dynamic> receipt) async {
    final sequence = _receiptSequence(receipt);
    final current = _storedSequence() ?? 0;
    if (sequence <= current) return;
    if (sequence != current + 1) {
      throw StateError(
          'Missing financial receipt after sequence $current; received $sequence');
    }

    final operationId = receipt['operationId']?.toString().isNotEmpty == true
        ? receipt['operationId'].toString()
        : receiptId;
    final partyEvents = <String, Map<String, Map<String, dynamic>>>{};
    for (final collection in ['clients', 'suppliers']) {
      final ids =
          receipt[collection == 'clients' ? 'customerIds' : 'supplierIds']
                  as List? ??
              const [];
      for (final rawId in ids) {
        final path = '$collection/$rawId';
        final event =
            (await _serverDocument('$path/financialOperations/$operationId'))
                .data();
        if (event == null) {
          throw StateError('Missing financial event: $path/$operationId');
        }
        partyEvents[path] = {operationId: event};
      }
    }

    final versions = Map<String, dynamic>.from(
        receipt['versions'] as Map? ?? const <String, dynamic>{});
    int importPriority(String path) {
      final parts = path.split('/');
      return parts.length == 2 &&
              (parts.first == 'clients' || parts.first == 'suppliers')
          ? 0
          : parts.length;
    }

    final paths = versions.keys.toList()
      ..sort((a, b) => importPriority(a).compareTo(importPriority(b)));
    for (final path in paths) {
      if (!_isLocallyCachedPath(path)) continue;
      final snapshot = await _serverDocument(path);
      final data = snapshot.data();
      final expectedVersion = (versions[path] as num?)?.toInt() ?? 0;
      if (data == null ||
          ((data['_version'] as num?)?.toInt() ?? 0) < expectedVersion) {
        throw StateError(
            'Financial document has not reached receipt version $expectedVersion: $path');
      }
      await _importPath(path, data, events: partyEvents[path] ?? const {});
    }

    for (final party in partyEvents.entries) {
      final id = party.key.split('/')[1];
      await LocalOperationJournal.exclusive(() =>
          party.key.startsWith('clients/')
              ? CustomerBalanceStore.importEvent(
                  id, operationId, party.value[operationId]!)
              : SupplierBalanceStore.importEvent(
                  id, operationId, party.value[operationId]!));
    }

    // Advance only after records, ledger events and reminders for protected
    // local paths are durable. A crash before this write replays the receipt.
    await _flushImports();
    await appMetaBox.put(HiveMetaKeys.financialChangeSequence, sequence);
    await appMetaBox.flush();
  }

  Future<void> _importPath(String path, Map<String, dynamic>? data,
      {Map<String, Map<String, dynamic>> events = const {}}) async {
    if (!_isLocallyCachedPath(path)) return;
    final key = _deferredPrefix + path;
    final version = (data?['_version'] as num?)?.toInt() ?? 0;
    final requiredVersion =
        (appMetaBox.get(key, defaultValue: 0) as num).toInt();
    // Persist before invoking repositories, which can refuse a snapshot under
    // their journal lock if an edit was queued while the read was in flight.
    await appMetaBox.put(
        key, version > requiredVersion ? version : requiredVersion);
    if (CloudSnapshotGuard.pendingPath(path)) return;
    await _mergePath(path, data, events: events);
    await LocalOperationJournal.exclusive(() async {
      if (CloudSnapshotGuard.pendingPath(path)) return;
      final localVersion = (appMetaBox.get(CloudSnapshotGuard.versionKey(path),
              defaultValue: 0) as num)
          .toInt();
      if (localVersion >= (appMetaBox.get(key) as num).toInt()) {
        await appMetaBox.delete(key);
      }
    });
  }

  Future<void> _retryDeferredPaths() async {
    final keys = appMetaBox.keys
        .whereType<String>()
        .where((key) => key.startsWith(_deferredPrefix))
        .toList();
    if (keys.isEmpty) return;
    for (final key in keys) {
      final path = key.substring(_deferredPrefix.length);
      if (CloudSnapshotGuard.pendingPath(path)) continue;
      final snapshot = await _serverDocument(path);
      final data = snapshot.data();
      final requiredVersion = (appMetaBox.get(key) as num).toInt();
      if (requiredVersion > 0 &&
          (data == null ||
              ((data['_version'] as num?)?.toInt() ?? 0) < requiredVersion)) {
        throw StateError('Deferred financial document is incomplete: $path');
      }
      await _importPath(path, data);
    }
    await _flushImports();
  }

  Future<void> _flushImports() async {
    await Future.wait([
      productsBox.flush(),
      clientsBox.flush(),
      suppliersBox.flush(),
      invoicesBox.flush(),
      returnInvoicesBox.flush(),
      buyingInvoicesBox.flush(),
      quotesBox.flush(),
      boxCacheBox.flush(),
      balanceHistoryBox.flush(),
      PaymentBreakdownRepository.instance.box.flush(),
      appMetaBox.flush(),
    ]);
  }

  static bool _isLocallyCachedPath(String path) {
    final parts = path.split('/');
    if (parts.length == 2) {
      if (parts.first == 'box' && parts[1] != 'mainBox') return false;
      return const {
        'products',
        'invoices',
        'returnInvoices',
        'clients',
        'price_quotes',
        'client_vouchers',
        'supplier_vouchers',
        'payment_breakdowns',
        'suppliers',
        'buying invoices',
        'box',
      }.contains(parts.first);
    }
    return parts.length == 4 &&
        (parts.first == 'clients' || parts.first == 'suppliers') &&
        parts[2] == 'balanceHistory';
  }

  Future<void> _mergePath(String path, Map<String, dynamic>? data,
      {Map<String, Map<String, dynamic>> events = const {}}) async {
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
        await ClientRepository.instance.mergeCloud(parts[1], data,
            events: await _completePartyEvents(path, data, events));
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
      case 'payment_breakdowns':
        await PaymentBreakdownRepository.instance.mergeCloud(parts[1], data);
        break;
      case 'suppliers':
        await SupplierRepository.instance.mergeCloud(parts[1], data,
            events: await _completePartyEvents(path, data, events));
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
    appMetaBox.putAll({
      'cloudRefreshError': error.toString(),
      'financialDownloadError': error.toString()
    });
    unawaited(stopListening().whenComplete(() {
      _restartTimer?.cancel();
      _restartTimer = Timer(
        const Duration(minutes: 1),
        () => unawaited(startListening()),
      );
    }));
  }

  Future<void> stopListening() async {
    _restartTimer?.cancel();
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
