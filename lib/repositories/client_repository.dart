import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/client_local.dart';
import '../sync/sync_queue_manager.dart';
import '../utils/entity_name_normalizer.dart';

import 'balance_history_repository.dart';

/// Repository for Client data.
///
/// READ  → Hive local cache (instant, zero network).
/// SYNC  → Delta sync from Firestore using [lastClientSyncAt] timestamp.
class ClientRepository {
  ClientRepository._();
  static final ClientRepository instance = ClientRepository._();

  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  // ── Cache helpers ─────────────────────────────────────────────────────────

  /// Returns the same ledger-derived balance used by the clients screen.
  ///
  /// The stored client balance is only a fallback for clients whose transaction
  /// history has not been cached yet.
  double computeLiveBalanceFromHive(String clientId) {
    final existing = clientsBox.get(clientId);
    return BalanceHistoryRepository.instance.calculateClientBalance(
      clientId,
      fallback: existing?.balance ?? 0.0,
    );
  }

  /// Resolves a client by name and returns their ledger-derived current balance.
  double currentBalanceByName(String clientName) {
    final client = findByName(clientName);
    if (client == null) return 0.0;
    return computeLiveBalanceFromHive(client.id);
  }

  /// All clients from local cache. Returns stored balances — no live recomputation.
  /// Use [computeLiveBalanceFromHive] explicitly when you need a full recalculation.
  List<ClientLocal> getAll() {
    final clients = clientsBox.values.toList();
    clients.sort((a, b) => a.name.compareTo(b.name));
    return clients;
  }

  /// Search clients locally by name — zero Firestore reads. Returns stored balances.
  List<ClientLocal> search(String query) {
    final q = normalizeEntityName(query);
    if (q.isEmpty) return getAll();
    final list = clientsBox.values
        .where((c) => normalizeEntityName(c.name).contains(q))
        .toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// Get a single client by Firestore document ID. Returns stored balance.
  ClientLocal? getById(String id) {
    return clientsBox.get(id);
  }

  /// Get a single client by name (case-insensitive). Returns stored balance.
  ClientLocal? findByName(String name) {
    final n = normalizeEntityName(name);
    try {
      return clientsBox.values
          .firstWhere((client) => normalizeEntityName(client.name) == n);
    } catch (_) {
      return null;
    }
  }

  // ── Sync ──────────────────────────────────────────────────────────────────

  /// Full sync — downloads all clients from Firestore into Hive.
  Future<void> fullSync() async {
    final snap = await _fs.collection('clients').get();
    final box = clientsBox;

    final pendingClientIds = SyncQueueManager.instance.unfinishedEntityIds(
      operationType: 'createClient',
      idKey: 'clientId',
    );
    final Map<String, ClientLocal> entries = {};
    for (final doc in snap.docs) {
      final serverClient = ClientLocal.fromFirestore(doc.id, doc.data());
      final localExisting = box.get(doc.id);
      if (localExisting != null) {
        // Hive is our primary local DB — preserve local Hive balance from being overwritten by stale server reads
        serverClient.balance = localExisting.balance;
      }
      entries[doc.id] = serverClient;
    }
    final staleKeys = box.keys
        .where((key) =>
            !entries.containsKey(key.toString()) &&
            !pendingClientIds.contains(key.toString()))
        .toList(growable: false);
    await box.deleteAll(staleKeys);
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
