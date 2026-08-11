import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/supplier_local.dart';

/// Repository for Supplier data.
///
/// READ  → Hive local cache (instant, zero network).
/// SYNC  → Delta sync from Firestore using [lastSupplierSyncAt] timestamp.
class SupplierRepository {
  SupplierRepository._();
  static final SupplierRepository instance = SupplierRepository._();

  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  // ── Cache helpers ─────────────────────────────────────────────────────────

  /// All suppliers from local cache, sorted by name.
  List<SupplierLocal> getAll() {
    final suppliers = suppliersBox.values.toList();
    suppliers.sort((a, b) => a.name.compareTo(b.name));
    return suppliers;
  }

  /// Search suppliers locally by name — zero Firestore reads.
  List<SupplierLocal> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return getAll();
    return suppliersBox.values
        .where((s) => s.name.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Get a single supplier by Firestore document ID.
  SupplierLocal? getById(String id) => suppliersBox.get(id);

  /// Get a single supplier by name (case-insensitive).
  SupplierLocal? findByName(String name) {
    final n = name.trim().toLowerCase();
    try {
      return suppliersBox.values
          .firstWhere((s) => s.name.toLowerCase() == n);
    } catch (_) {
      return null;
    }
  }

  // ── Sync ──────────────────────────────────────────────────────────────────

  /// Full sync — downloads all suppliers from Firestore into Hive.
  Future<void> fullSync() async {
    final snap = await _fs.collection('suppliers').get();
    final box = suppliersBox;
    await box.clear();
    final Map<String, SupplierLocal> entries = {};
    for (final doc in snap.docs) {
      entries[doc.id] = SupplierLocal.fromFirestore(doc.id, doc.data());
    }
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
    await suppliersBox.put(docId, SupplierLocal.fromFirestore(docId, data));
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
