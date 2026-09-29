import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/supplier_local.dart';
import '../sync/cloud_snapshot_guard.dart';
import '../sync/local_operation_journal.dart';
import '../Services/supplier_balance_store.dart';
import '../utils/entity_name_normalizer.dart';

import 'balance_history_repository.dart';

/// Repository for Supplier data.
///
/// READ  → Hive local cache (instant, zero network).
/// SYNC  → Delta sync from Firestore using [lastSupplierSyncAt] timestamp.
class SupplierRepository {
  SupplierRepository._();
  static final SupplierRepository instance = SupplierRepository._();

  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  // ── Cache helpers ─────────────────────────────────────────────────────────

  /// Compute live running balance for a supplier directly from local Hive transaction history.
  double computeLiveBalanceFromHive(String supplierId) {
    final cached = suppliersBox.get(supplierId);
    if (SupplierBalanceStore.hasBase(supplierId)) {
      return SupplierBalanceStore.balance(supplierId,
          fallback: cached?.balance ?? 0);
    }
    return BalanceHistoryRepository.instance.calculateSupplierBalance(
      supplierId,
      fallback: cached?.balance ?? 0.0,
    );
  }

  /// All suppliers from local cache, with instant live balances computed from Hive.
  List<SupplierLocal> getAll() {
    final suppliers = suppliersBox.values.toList();
    for (final s in suppliers) {
      s.balance = computeLiveBalanceFromHive(s.id);
    }
    suppliers.sort((a, b) => a.name.compareTo(b.name));
    return suppliers;
  }

  /// Search suppliers locally by name — zero Firestore reads.
  List<SupplierLocal> search(String query) {
    final q = normalizeEntityName(query);
    if (q.isEmpty) return getAll();
    final list = suppliersBox.values
        .where((s) => normalizeEntityName(s.name).contains(q))
        .toList();
    for (final s in list) {
      s.balance = computeLiveBalanceFromHive(s.id);
    }
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// Get a single supplier by Firestore document ID with instant Hive balance.
  SupplierLocal? getById(String id) {
    final s = suppliersBox.get(id);
    if (s != null) {
      s.balance = computeLiveBalanceFromHive(s.id);
    }
    return s;
  }

  /// Get a single supplier by name (case-insensitive) with instant Hive balance.
  SupplierLocal? findByName(String name) {
    final n = normalizeEntityName(name);
    try {
      final s = suppliersBox.values
          .firstWhere((supplier) => normalizeEntityName(supplier.name) == n);
      s.balance = computeLiveBalanceFromHive(s.id);
      return s;
    } catch (_) {
      return null;
    }
  }

  // ── Sync ──────────────────────────────────────────────────────────────────

  /// Full sync — downloads all suppliers from Firestore into Hive.
  Future<void> fullSync() async {
    final startedAt = DateTime.now();
    final snap = await _fs.collection('suppliers').get();
    for (final doc in snap.docs) {
      await hydrateCloud(doc.id, doc.data());
    }
    await appMetaBox.put(
      HiveMetaKeys.lastSupplierSyncAt,
      startedAt.toIso8601String(),
    );
  }

  /// Fetches supplier profile changes after the initial compatibility
  /// baseline. Financial changes arrive through the sequenced receipt feed.
  Future<void> deltaSync() async {
    final raw = appMetaBox.get(HiveMetaKeys.lastSupplierSyncAt)?.toString();
    final cursor = DateTime.tryParse(raw ?? '');
    if (cursor == null) {
      await fullSync();
      return;
    }
    final startedAt = DateTime.now();
    final snap = await _fs
        .collection('suppliers')
        .where('updatedAt', isGreaterThan: Timestamp.fromDate(cursor))
        .get();
    for (final doc in snap.docs) {
      await hydrateCloud(doc.id, doc.data());
    }
    await appMetaBox.put(
      HiveMetaKeys.lastSupplierSyncAt,
      startedAt.toIso8601String(),
    );
  }

  Future<void> hydrateCloud(String id, Map<String, dynamic>? data) async {
    final events = <String, Map<String, dynamic>>{};
    if (data != null && data.containsKey('financialBaseBalance')) {
      final snap = await _fs
          .collection('suppliers')
          .doc(id)
          .collection('financialOperations')
          .get();
      for (final doc in snap.docs) events[doc.id] = doc.data();
    }
    await mergeCloud(id, data, events: events);
  }

  Future<void> mergeCloud(String id, Map<String, dynamic>? data,
          {Map<String, Map<String, dynamic>> events = const {}}) =>
      LocalOperationJournal.exclusive(() async {
        final path = 'suppliers/$id';
        if (data != null) {
          await appMetaBox.put('supplierCloudBalance:$id', {
            'balance': data['totalBalance'] ?? data['balance'],
            'version': data['_version'] ?? 0
          });
        }
        if (data == null || !CloudSnapshotGuard.accepts(path, data)) return;
        if (data['_deleted'] == true) {
          await deleteLocal(id);
          await CloudSnapshotGuard.record(path, data);
          return;
        }
        if (!suppliersBox.containsKey(id)) {
          await SupplierBalanceStore.initializeFromCloud(id, data);
        }
        for (final event in events.entries) {
          await SupplierBalanceStore.importEvent(id, event.key, event.value);
        }
        await upsertLocal(id, data);
        await CloudSnapshotGuard.record(path, data);
      });

  /// Upsert a single supplier into local cache.
  Future<void> upsertLocal(String docId, Map<String, dynamic> data) async {
    final incoming = SupplierLocal.fromFirestore(docId, data);
    if (SupplierBalanceStore.hasBase(docId)) {
      incoming.balance = SupplierBalanceStore.balance(docId);
    } else {
      final existing = suppliersBox.get(docId);
      if (existing != null) incoming.balance = existing.balance;
    }
    await suppliersBox.put(docId, incoming);
  }

  /// Update local cached balance for a supplier.
  Future<void> updateLocalBalance(String docId, double newBalance) async {
    final existing = suppliersBox.get(docId);
    if (existing != null) {
      existing.balance = newBalance;
      await existing.save();
    }
  }

  /// Remove a supplier from local cache.
  Future<void> deleteLocal(String docId) async {
    await suppliersBox.delete(docId);
  }
}
