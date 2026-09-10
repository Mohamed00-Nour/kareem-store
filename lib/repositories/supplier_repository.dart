import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/supplier_local.dart';
import '../sync/sync_queue_manager.dart';
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
    return BalanceHistoryRepository.instance.calculateSupplierBalance(
      supplierId,
      fallback: suppliersBox.get(supplierId)?.balance ?? 0.0,
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
    final snap = await _fs.collection('suppliers').get();
    final box = suppliersBox;
    final pendingIds = SyncQueueManager.instance.unfinishedEntityIds(
      operationType: 'createSupplier',
      idKey: 'supplierId',
    );
    final Map<String, SupplierLocal> entries = {};
    for (final doc in snap.docs) {
      final serverSupplier = SupplierLocal.fromFirestore(doc.id, doc.data());
      final localExisting = box.get(doc.id);
      if (localExisting != null) {
        serverSupplier.balance = localExisting.balance;
      }
      entries[doc.id] = serverSupplier;
    }
    final staleKeys = box.keys
        .where((key) =>
            !entries.containsKey(key.toString()) &&
            !pendingIds.contains(key.toString()))
        .toList(growable: false);
    await box.deleteAll(staleKeys);
    await box.putAll(entries);
    appMetaBox.put(
      HiveMetaKeys.lastSupplierSyncAt,
      DateTime.now().toIso8601String(),
    );
  }

  /// Delta sync — fetches suppliers into Hive.
  /// Performs fullSync to guarantee complete supplier list caching because supplier documents
  /// in Firestore may not contain an updatedAt field.
  Future<void> deltaSync() async {
    await fullSync();
  }

  /// Upsert a single supplier into local cache.
  Future<void> upsertLocal(String docId, Map<String, dynamic> data) async {
    final incoming = SupplierLocal.fromFirestore(docId, data);
    final existing = suppliersBox.get(docId);
    if (existing != null) {
      // Supplier balance is owned by the local Hive ledger. Realtime supplier
      // metadata must never replace it with a delayed Firestore aggregate.
      incoming.balance = existing.balance;
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
