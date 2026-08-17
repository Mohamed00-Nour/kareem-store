import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/client_local.dart';

/// Repository for Client data.
///
/// READ  → Hive local cache (instant, zero network).
/// SYNC  → Delta sync from Firestore using [lastClientSyncAt] timestamp.
class ClientRepository {
  ClientRepository._();
  static final ClientRepository instance = ClientRepository._();

  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  // ── Cache helpers ─────────────────────────────────────────────────────────

  /// All clients from local cache, sorted by name.
  List<ClientLocal> getAll() {
    final clients = clientsBox.values.toList();
    clients.sort((a, b) => a.name.compareTo(b.name));
    return clients;
  }

  /// Search clients locally by name — zero Firestore reads.
  List<ClientLocal> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return getAll();
    return clientsBox.values
        .where((c) => c.name.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Get a single client by Firestore document ID.
  ClientLocal? getById(String id) => clientsBox.get(id);

  /// Get a single client by name (case-insensitive).
  ClientLocal? findByName(String name) {
    final n = name.trim().toLowerCase();
    try {
      return clientsBox.values
          .firstWhere((c) => c.name.toLowerCase() == n);
    } catch (_) {
      return null;
    }
  }

  // ── Sync ──────────────────────────────────────────────────────────────────

  /// Full sync — downloads all clients from Firestore into Hive.
  Future<void> fullSync() async {
    final snap = await _fs.collection('clients').get();
    final box = clientsBox;
    await box.clear();
    final Map<String, ClientLocal> entries = {};
    for (final doc in snap.docs) {
      entries[doc.id] = ClientLocal.fromFirestore(doc.id, doc.data());
    }
    await box.putAll(entries);
    appMetaBox.put(
      HiveMetaKeys.lastClientSyncAt,
      DateTime.now().toIso8601String(),
    );
  }

  /// Delta sync — fetches clients into Hive.
  /// Performs fullSync to guarantee complete client list caching because client documents
  /// in Firestore may not contain an updatedAt field.
  Future<void> deltaSync() async {
    await fullSync();
  }

  /// Upsert a single client into the local cache.
  Future<void> upsertLocal(String docId, Map<String, dynamic> data) async {
    await clientsBox.put(docId, ClientLocal.fromFirestore(docId, data));
  }

  /// Update local cached balance for a client.
  Future<void> updateLocalBalance(String docId, double newBalance) async {
    final existing = clientsBox.get(docId);
    if (existing != null) {
      existing.balance = newBalance;
      await existing.save();
    }
  }

  /// Remove a client from local cache.
  Future<void> deleteLocal(String docId) async {
    await clientsBox.delete(docId);
  }
}
