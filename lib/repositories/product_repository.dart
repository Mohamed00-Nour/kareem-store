import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/product_local.dart';
import '../sync/sync_queue_manager.dart';
import '../utils/entity_name_normalizer.dart';
import '../sync/cloud_snapshot_guard.dart';
import '../sync/firestore_read_diagnostics.dart';
import '../sync/firestore_sync_checkpoint.dart';
import '../sync/local_operation_journal.dart';

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
    final q = normalizeEntityName(query);
    if (q.isEmpty) return getAll();
    return productsBox.values
        .where((p) => normalizeEntityName(p.name).contains(q))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Find a single product by name (exact, case-insensitive).
  ProductLocal? findByName(String name) {
    final n = normalizeEntityName(name);
    try {
      return productsBox.values
          .firstWhere((p) => normalizeEntityName(p.name) == n);
    } catch (_) {
      return null;
    }
  }

  ProductLocal? getById(String id) => productsBox.get(id);

  /// Renames a cached product and records the cloud update in the durable
  /// journal before exposing it as a pending sync operation.
  Future<void> renameLocalFirst(String productId, String newName) async {
    final existing = getById(productId);
    if (existing == null) {
      throw StateError('Product must be cached before renaming: $productId');
    }
    final trimmedName = newName.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(newName, 'newName');
    }

    final localAfter = {
      ...existing.toMap(),
      'name': trimmedName,
      'updatedAt': DateTime.now(),
    };
    await LocalOperationJournal.commit((_) async => {
          'operationType': 'editProduct',
          'productId': productId,
          'data': {'name': trimmedName},
          'localWrites': [
            {
              'box': HiveBoxNames.products,
              'key': productId,
              'data': localAfter,
            }
          ],
        });
  }

  // ── Sync ──────────────────────────────────────────────────────────────────

  /// Performs a **full** initial sync from Firestore → Hive.
  /// Only call this once (first launch or after clearing app data).
  Future<void> fullSync() async {
    final snap = await _fs.collection('products').get();
    FirestoreReadDiagnostics.queryResult(
      'products (full)',
      snap.docs.length,
      trigger: 'compatibility bootstrap',
      fromCache: snap.metadata.isFromCache,
    );
    for (final doc in snap.docs) {
      await mergeCloud(doc.id, doc.data());
    }
    final checkpoint = FirestoreSyncCheckpoint.newest(
      snap.docs.map((doc) => doc.data()),
      const ['updatedAt'],
    );
    await appMetaBox.put(
        HiveMetaKeys.lastProductSyncAt, checkpoint.toIso8601String());
  }

  Future<void> mergeCloud(String id, Map<String, dynamic>? data) =>
      LocalOperationJournal.exclusive(() async {
        final path = 'products/' + id;
        if (!CloudSnapshotGuard.accepts(path, data)) return;
        if (data == null || data['_deleted'] == true)
          await deleteLocal(id);
        else
          await upsertLocal(id, data);
        if (data != null) await CloudSnapshotGuard.record(path, data);
      });

  /// Fetches only product documents changed after the initial compatibility
  /// baseline. All current product writers maintain `updatedAt`; invoice stock
  /// changes are additionally delivered through the financial receipt feed.
  Future<void> deltaSync() async {
    final raw = appMetaBox.get(HiveMetaKeys.lastProductSyncAt)?.toString();
    final cursor = DateTime.tryParse(raw ?? '');
    if (cursor == null) {
      await fullSync();
      return;
    }
    final snap = await _fs
        .collection('products')
        .where('updatedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(cursor))
        .get();
    FirestoreReadDiagnostics.queryResult(
      'products where updatedAt >= cursor',
      snap.docs.length,
      trigger: 'product delta',
      fromCache: snap.metadata.isFromCache,
    );
    for (final doc in snap.docs) {
      await mergeCloud(doc.id, doc.data());
    }
    final checkpoint = FirestoreSyncCheckpoint.newest(
      snap.docs.map((doc) => doc.data()),
      const ['updatedAt'],
      floor: cursor,
    );
    await appMetaBox.put(
        HiveMetaKeys.lastProductSyncAt, checkpoint.toIso8601String());
  }

  /// Updates a single product in the local cache (call after saving to Firestore).
  Future<void> upsertLocal(String docId, Map<String, dynamic> data) async {
    await productsBox.put(docId, ProductLocal.fromFirestore(docId, data));
  }

  /// Updates multiple products in the local cache in a single batch operation.
  Future<void> upsertAllLocal(Map<String, Map<String, dynamic>> items) async {
    if (items.isEmpty) return;
    final Map<String, ProductLocal> map = {};
    items.forEach((id, data) {
      map[id] = ProductLocal.fromFirestore(id, data);
    });
    await productsBox.putAll(map);
  }

  /// Removes a single product from local cache.
  Future<void> deleteLocal(String docId) async {
    await productsBox.delete(docId);
  }

  // ── Direct Firestore write helpers (used until Phase 3 SyncQueue) ─────────

  /// Updates product quantity in both local cache and Firestore.
  Future<void> updateQuantity(String docId, double newQty) async {
    await _fs.collection('products').doc(docId).update({
      'quantity': newQty,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final existing = productsBox.get(docId);
    if (existing != null) {
      existing.quantity = newQty;
      await existing.save();
    }
  }
}
