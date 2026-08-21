import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/client_local.dart';
import '../sync/sync_queue_manager.dart';

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

  /// Compute live running balance for a client directly from local Hive transaction history.
  double computeLiveBalanceFromHive(String clientId) {
    final history = BalanceHistoryRepository.instance.getForClient(clientId);
    if (history.isEmpty) {
      final existing = clientsBox.get(clientId);
      return existing?.balance ?? 0.0;
    }
    double running = 0.0;
    for (final bh in history) {
      final type = bh.type;
      final isIncrease = type == 'sale' ||
          type == 'addition' ||
          type == 'opening' ||
          type == 'return_payment';
      if (isIncrease) {
        running += bh.enteredBalance;
      } else {
        running -= bh.enteredBalance;
      }
    }
    return running;
  }

  /// All clients from local cache, with instant live balances computed from Hive.
  List<ClientLocal> getAll() {
    final clients = clientsBox.values.toList();
    for (final c in clients) {
      c.balance = computeLiveBalanceFromHive(c.id);
    }
    clients.sort((a, b) => a.name.compareTo(b.name));
    return clients;
  }

  /// Search clients locally by name — zero Firestore reads.
  List<ClientLocal> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return getAll();
    final list = clientsBox.values
        .where((c) => c.name.toLowerCase().contains(q))
        .toList();
    for (final c in list) {
      c.balance = computeLiveBalanceFromHive(c.id);
    }
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// Get a single client by Firestore document ID with instant Hive balance.
  ClientLocal? getById(String id) {
    final c = clientsBox.get(id);
    if (c != null) {
      c.balance = computeLiveBalanceFromHive(c.id);
    }
    return c;
  }

  /// Get a single client by name (case-insensitive) with instant Hive balance.
  ClientLocal? findByName(String name) {
    final n = name.trim().toLowerCase();
    try {
      final c = clientsBox.values
          .firstWhere((client) => client.name.toLowerCase() == n);
      c.balance = computeLiveBalanceFromHive(c.id);
      return c;
    } catch (_) {
      return null;
    }
  }

  // ── Sync ──────────────────────────────────────────────────────────────────

  /// Full sync — downloads all clients from Firestore into Hive.
  Future<void> fullSync() async {
    final snap = await _fs.collection('clients').get();
    final box = clientsBox;

    // Track local balances for clients that have pending queued updates
    final pendingOps = SyncQueueManager.instance.getPending();
    final pendingClientIds = <String>{};
    for (final op in pendingOps) {
      try {
        final payload = jsonDecode(op.payloadJson) as Map<String, dynamic>;
        final cId = payload['clientId']?.toString();
        if (cId != null && cId.isNotEmpty) {
          pendingClientIds.add(cId);
        }
      } catch (_) {}
    }

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
    await box.clear();
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
