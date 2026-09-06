import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/sync_queue_item.dart';

/// Manages all pending offline write operations.
///
/// Any WRITE to Firestore (create invoice, adjust balance, update stock…)
/// should be captured here FIRST. The [BatchSyncEngine] drains this queue
/// when internet is available.
class SyncQueueManager {
  SyncQueueManager._();
  static final SyncQueueManager instance = SyncQueueManager._();

  static const _uuid = Uuid();

  // ── Enqueue ───────────────────────────────────────────────────────────────

  /// Adds a new pending operation to the local queue.
  ///
  /// [operationType] — one of [SyncOperationType] enum values as string.
  /// [payload]       — the operation data as a Dart Map. Will be JSON-encoded.
  ///
  /// Returns the unique [operationId] for this queued item.
  Future<String> enqueue({
    required String operationType,
    required Map<String, dynamic> payload,
  }) async {
    final id = _uuid.v4();
    final item = SyncQueueItem(
      operationId: id,
      operationType: operationType,
      payloadJson: jsonEncode(payload, toEncodable: _toEncodable),
      createdAt: DateTime.now(),
      retryCount: 0,
      status: 'pending',
    );
    await syncQueueBox.put(id, item);
    return id;
  }

  static dynamic _toEncodable(dynamic nonEncodable) {
    if (nonEncodable is DateTime) {
      return nonEncodable.toIso8601String();
    }
    if (nonEncodable is Timestamp) {
      return nonEncodable.toDate().toIso8601String();
    }
    return nonEncodable.toString();
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  bool get _isBoxReady => Hive.isBoxOpen(HiveBoxNames.syncQueue);

  /// All items that have not yet been synced, ordered by creation time.
  List<SyncQueueItem> getPending() {
    if (!_isBoxReady) return [];
    return syncQueueBox.values
        .where((item) => item.status == 'pending' || item.status == 'failed')
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// All items currently in the queue (any status).
  List<SyncQueueItem> getAll() {
    if (!_isBoxReady) return [];
    return syncQueueBox.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Number of pending (not yet synced) items.
  int get pendingCount => getPending().length;

  /// True when there are items waiting to be synced.
  bool get hasPending => pendingCount > 0;

  /// True for every state that still requires work. In particular, a stale
  /// `syncing` item must keep connectivity polling alive until it is recovered.
  bool get hasUnfinished {
    if (!_isBoxReady) return false;
    return syncQueueBox.values.any((item) =>
        item.status == 'pending' ||
        item.status == 'failed' ||
        item.status == 'syncing');
  }

  /// True when there are operations currently being uploaded.
  bool get hasSyncingItems {
    if (!_isBoxReady) return false;
    return syncQueueBox.values.any((item) => item.status == 'syncing');
  }

  /// Total count of all items in queue (any status).
  int get totalCount => getAll().length;

  // ── Status updates ────────────────────────────────────────────────────────

  /// Mark an item as currently being synced.
  Future<void> markSyncing(String operationId) async {
    final item = syncQueueBox.get(operationId);
    if (item != null) {
      item.status = 'syncing';
      await item.save();
    }
  }

  /// Mark an item as successfully synced and remove it from the queue.
  Future<void> markSynced(String operationId) async {
    await syncQueueBox.delete(operationId);
  }

  /// Mark an item as failed and increment its retry count.
  Future<void> markFailed(String operationId, String errorMessage) async {
    final item = syncQueueBox.get(operationId);
    if (item != null) {
      item.status = 'failed';
      item.retryCount++;
      item.lastError = errorMessage;
      await item.save();
    }
  }

  /// Reset a failed item back to 'pending' so it can be retried.
  Future<void> resetToPending(String operationId) async {
    final item = syncQueueBox.get(operationId);
    if (item != null) {
      item.status = 'pending';
      await item.save();
    }
  }

  /// Recovers uploads interrupted by an app/process shutdown.
  Future<void> recoverInterruptedItems() async {
    if (!_isBoxReady) return;
    final interrupted = syncQueueBox.values
        .where((item) => item.status == 'syncing')
        .toList(growable: false);
    for (final item in interrupted) {
      item.status = 'pending';
      await item.save();
    }
  }

  /// Manual retry starts failed operations with a fresh retry budget.
  Future<void> resetFailedItems() async {
    if (!_isBoxReady) return;
    final failed = syncQueueBox.values
        .where((item) => item.status == 'failed')
        .toList(growable: false);
    for (final item in failed) {
      item.status = 'pending';
      item.retryCount = 0;
      item.lastError = null;
      await item.save();
    }
  }

  /// Decode payload JSON back to a Dart Map.
  static Map<String, dynamic> decodePayload(SyncQueueItem item) {
    return jsonDecode(item.payloadJson) as Map<String, dynamic>;
  }
}
