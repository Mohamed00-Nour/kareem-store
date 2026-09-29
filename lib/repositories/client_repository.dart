import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/client_local.dart';
import '../utils/entity_name_normalizer.dart';

import 'balance_history_repository.dart';
import '../Services/customer_balance_store.dart';
import '../sync/cloud_snapshot_guard.dart';
import '../sync/local_operation_journal.dart';

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
    final startedAt = DateTime.now();
    final snap = await _fs.collection('clients').get();
    for (final doc in snap.docs) {
      await hydrateCloud(doc.id, doc.data());
    }
    await appMetaBox.put(
        HiveMetaKeys.lastClientSyncAt, startedAt.toIso8601String());
  }

  Future<void> hydrateCloud(String id, Map<String, dynamic>? data) async {
    final events = <String, Map<String, dynamic>>{};
    if (data != null && data.containsKey('financialBaseBalance')) {
      final snapshot = await _fs
          .collection('clients')
          .doc(id)
          .collection('financialOperations')
          .get();
      for (final doc in snapshot.docs) events[doc.id] = doc.data();
    }
    await mergeCloud(id, data, events: events);
  }

  Future<void> mergeCloud(String id, Map<String, dynamic>? data,
          {Map<String, Map<String, dynamic>> events = const {}}) =>
      LocalOperationJournal.exclusive(() async {
        final path = 'clients/' + id;
        if (data != null)
          await appMetaBox.put('customerCloudBalance:' + id,
              {'balance': data['balance'], 'version': data['_version'] ?? 0});
        if (data == null || !CloudSnapshotGuard.accepts(path, data)) return;
        if (data['_deleted'] == true) {
          // Financial history must remain reviewable; archived customers are
          // removed from the active cache without deleting their local ledger.
          await deleteLocal(id);
          await CloudSnapshotGuard.record(path, data);
          return;
        }
        if (!clientsBox.containsKey(id))
          await CustomerBalanceStore.initializeFromCloud(id, data);
        for (final event in events.entries) {
          await CustomerBalanceStore.importEvent(id, event.key, event.value);
        }
        await upsertLocal(id, data);
        await CloudSnapshotGuard.record(path, data);
      });

  /// Fetches client profile changes after the initial compatibility baseline.
  /// Financial changes arrive through the sequenced receipt feed.
  Future<void> deltaSync() async {
    final raw = appMetaBox.get(HiveMetaKeys.lastClientSyncAt)?.toString();
    final cursor = DateTime.tryParse(raw ?? '');
    if (cursor == null) {
      await fullSync();
      return;
    }
    final startedAt = DateTime.now();
    final snap = await _fs
        .collection('clients')
        .where('updatedAt', isGreaterThan: Timestamp.fromDate(cursor))
        .get();
    for (final doc in snap.docs) {
      await hydrateCloud(doc.id, doc.data());
    }
    await appMetaBox.put(
      HiveMetaKeys.lastClientSyncAt,
      startedAt.toIso8601String(),
    );
  }

  /// Upsert a single client into the local cache.
  Future<void> upsertLocal(String docId, Map<String, dynamic> data) async {
    final incoming = ClientLocal.fromFirestore(docId, data);
    final existing = clientsBox.get(docId);
    if (CustomerBalanceStore.hasBase(docId)) {
      incoming.balance = CustomerBalanceStore.balance(docId);
    } else if (existing != null &&
        CloudSnapshotGuard.pendingPath('clients/' + docId)) {
      incoming.balance = existing.balance;
    }
    await clientsBox.put(docId, incoming);
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
