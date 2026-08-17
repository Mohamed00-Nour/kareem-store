import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/product_local.dart';

/// Repository for Product data.
///
/// READ strategy:  Serve from Hive local cache immediately.
///                 On demand, delta-sync from Firestore (only docs changed
///                 since [lastProductSyncAt]) and update the local cache.
///
/// WRITE strategy: During Phase 3 writes will go through [SyncQueueManager].
///                 For now, direct Firestore writes are still used so the app
///                 behaviour is unchanged while the cache layer is introduced.
class ProductRepository {
  ProductRepository._();
  static final ProductRepository instance = ProductRepository._();

  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  // ── Cache helpers ─────────────────────────────────────────────────────────

  /// All products from the local Hive cache, sorted by name.
  List<ProductLocal> getAll() {
    final box = productsBox;
    final products = box.values.toList();
    products.sort((a, b) => a.name.compareTo(b.name));
    return products;
  }

  /// Search products locally by name (case-insensitive) — zero Firestore reads.
  List<ProductLocal> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return getAll();
    return productsBox.values
        .where((p) => p.name.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Find a single product by name (exact, case-insensitive).
  ProductLocal? findByName(String name) {
    final n = name.trim().toLowerCase();
    try {
      return productsBox.values
          .firstWhere((p) => p.name.toLowerCase() == n);
    } catch (_) {
      return null;
    }
  }

  // ── Sync ──────────────────────────────────────────────────────────────────

  /// Performs a **full** initial sync from Firestore → Hive.
  /// Only call this once (first launch or after clearing app data).
  Future<void> fullSync() async {
    final snap = await _fs.collection('products').get();
    final box = productsBox;
    await box.clear();
    final Map<String, ProductLocal> entries = {};
    for (final doc in snap.docs) {
      final data = doc.data();
      entries[doc.id] = ProductLocal.fromFirestore(doc.id, data);
    }
    await box.putAll(entries);
    appMetaBox.put(
      HiveMetaKeys.lastProductSyncAt,
      DateTime.now().toIso8601String(),
    );
  }

  /// Performs a **delta** sync — only fetches docs updated since the last sync.
  /// Dramatically reduces Firestore read costs on subsequent app opens.
  Future<void> deltaSync() async {
    final lastSyncStr =
        appMetaBox.get(HiveMetaKeys.lastProductSyncAt) as String?;

    // If never synced, do a full sync instead.
    if (lastSyncStr == null) {
      await fullSync();
      return;
    }

    final lastSync = DateTime.parse(lastSyncStr);
    final snap = await _fs
        .collection('products')
        .where('updatedAt', isGreaterThan: Timestamp.fromDate(lastSync))
        .get();

    if (snap.docs.isEmpty) {
      await appMetaBox.put(
        HiveMetaKeys.lastProductSyncAt,
        DateTime.now().toIso8601String(),
      );
      return;
    }

    final box = productsBox;
    for (final doc in snap.docs) {
      final data = doc.data();
      // Check if deleted flag is set
      if (data['deleted'] == true) {
        await box.delete(doc.id);
      } else {
        await box.put(doc.id, ProductLocal.fromFirestore(doc.id, data));
      }
    }

    appMetaBox.put(
      HiveMetaKeys.lastProductSyncAt,
      DateTime.now().toIso8601String(),
    );
  }

  /// Updates a single product in the local cache (call after saving to Firestore).
  Future<void> upsertLocal(String docId, Map<String, dynamic> data) async {
    await productsBox.put(docId, ProductLocal.fromFirestore(docId, data));
  }

  /// Removes a single product from local cache.
  Future<void> deleteLocal(String docId) async {
    await productsBox.delete(docId);
  }

  // ── Direct Firestore write helpers (used until Phase 3 SyncQueue) ─────────

  /// Updates product quantity in both local cache and Firestore.
  Future<void> updateQuantity(String docId, double newQty) async {
    await _fs.collection('products').doc(docId).update({'quantity': newQty});
    final existing = productsBox.get(docId);
    if (existing != null) {
      existing.quantity = newQty;
      await existing.save();
    }
  }
}
