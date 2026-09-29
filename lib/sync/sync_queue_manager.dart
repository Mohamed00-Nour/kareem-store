import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/sync_queue_item.dart';
import 'sync_operation_diagnostics.dart';

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
      diagnosticsJson:
          SyncOperationDiagnostics.fromPayload(id, operationType, payload)
              .toJson(),
    );
    await syncQueueBox.put(id, item);
    await syncQueueBox.flush();
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

  /// IDs referenced by create operations that have not been durably completed.
  /// Repositories use this while refreshing from Firestore so a pending local
  /// record is never erased just because it is not in the cloud yet.
  Set<String> unfinishedEntityIds({
    required String operationType,
    required String idKey,
  }) {
    if (!_isBoxReady) return const <String>{};
    final ids = <String>{};
    for (final item in syncQueueBox.values) {
      if (item.operationType != operationType ||
          (item.status != 'pending' &&
              item.status != 'failed' &&
              item.status != 'syncing')) {
        continue;
      }
      try {
        final id = decodePayload(item)[idKey]?.toString().trim() ?? '';
        if (id.isNotEmpty) ids.add(id);
      } catch (_) {
        // A malformed queue item is handled by the sync engine. It must not
        // prevent other valid local records from being protected.
      }
    }
    return ids;
  }

  /// Number of pending (not yet synced) items.
  int get pendingCount => getAll().where((e) => e.status != 'synced').length;
  int get failedCount => getAll()
      .where((e) => e.status == 'failed' || e.status == 'preparing')
      .length;

  /// True when there are items waiting to be synced.
  bool get hasPending => pendingCount > 0;

  /// True for every state that still requires work. In particular, a stale
  /// `syncing` item must keep connectivity polling alive until it is recovered.
  bool get hasUnfinished {
    if (!_isBoxReady) return false;
    return syncQueueBox.values.any((item) =>
        item.status == 'pending' ||
        item.status == 'failed' ||
        item.status == 'syncing' ||
        item.status == 'preparing');
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
      item.lastAttemptAt = DateTime.now();
      item.nextRetryAt = null;
      await item.save();
      await syncQueueBox.flush();
    }
  }

  /// Mark an item as successfully synced and remove it from the queue.
  Future<void> markSynced(String operationId) async {
    await syncQueueBox.delete(operationId);
    await syncQueueBox.flush();
  }

  /// Mark an item as failed and increment its retry count.
  Future<void> markFailed(String operationId, Object error) async {
    final item = syncQueueBox.get(operationId);
    if (item != null) {
      final details = SyncFailureClassifier.classify(error);
      item.lastAttemptAt ??= DateTime.now();
      item.status = 'failed';
      item.retryCount++;
      item.lastError = details.technicalMessage;
      item.errorCategory = details.category;
      item.errorCode = details.code;
      item.nextRetryAt = details.canRetryAutomatically
          ? _automaticRetryTime(item.operationId, item.retryCount)
          : null;
      _appendAttempt(item, details);
      await item.save();
      await syncQueueBox.flush();
    }
  }

  static DateTime _automaticRetryTime(String operationId, int retryCount) {
    const seconds = [2, 5, 15, 60, 300];
    final index = (retryCount - 1).clamp(0, seconds.length - 1);
    final baseMs = seconds[index] * 1000;
    final jitterMs = operationId.hashCode.abs() % (baseMs ~/ 5 + 1);
    return DateTime.now().add(Duration(milliseconds: baseMs + jitterMs));
  }

  static void _appendAttempt(SyncQueueItem item, SyncFailureDetails details) {
    List<dynamic> history = [];
    try {
      history = jsonDecode(item.attemptHistoryJson) as List<dynamic>;
    } catch (_) {}
    history.add({
      'attempt': item.retryCount,
      'at': (item.lastAttemptAt ?? DateTime.now()).toIso8601String(),
      'category': details.category,
      'code': details.code,
      'message': details.technicalMessage,
    });
    if (history.length > 20) history = history.sublist(history.length - 20);
    item.attemptHistoryJson = jsonEncode(history);
  }

  /// Reset a failed item back to 'pending' so it can be retried.
  Future<bool> resetToPending(String operationId) async {
    final item = syncQueueBox.get(operationId);
    if (item != null && canRetry(item)) {
      item.status = 'pending';
      item.retryCount = 0;
      item.lastError = null;
      item.errorCategory = null;
      item.errorCode = null;
      item.nextRetryAt = null;
      await item.save();
      await syncQueueBox.flush();
      return true;
    }
    return false;
  }

  /// Recovers uploads interrupted by an app/process shutdown.
  Future<void> recoverInterruptedItems() async {
    if (!_isBoxReady) return;
    for (final item in syncQueueBox.values) {
      var changed = false;
      if (item.diagnosticsJson == null || item.diagnosticsJson!.isEmpty) {
        item.diagnosticsJson = SyncOperationDiagnostics.fromItem(item).toJson();
        changed = true;
      }
      if (item.status == 'failed' && item.errorCategory == null) {
        item.errorCategory =
            SyncFailureClassifier.inferCategory(item.lastError);
        changed = true;
      }
      // Older builds classified Firestore quota exhaustion as a temporary
      // network failure and retried it repeatedly. Preserve the operation but
      // stop automatic attempts until the user retries after resolving quota.
      final reclassified = SyncFailureClassifier.classify(item.lastError ?? '');
      if (item.status == 'failed' &&
          reclassified.category == SyncErrorCategories.quota) {
        if (item.errorCategory != SyncErrorCategories.quota ||
            item.errorCode != reclassified.code) {
          item.errorCategory = SyncErrorCategories.quota;
          item.errorCode = reclassified.code;
          changed = true;
        }
        if (item.nextRetryAt != null) {
          item.nextRetryAt = null;
          changed = true;
        }
      }
      if (changed) await item.save();
    }
    final interrupted = syncQueueBox.values
        .where((item) => item.status == 'syncing')
        .toList(growable: false);
    for (final item in interrupted) {
      item.status = 'pending';
      item.nextRetryAt = null;
      await item.save();
    }
    await syncQueueBox.flush();
  }

  /// Manual retry starts failed operations with a fresh retry budget.
  Future<void> resetFailedItems() async {
    if (!_isBoxReady) return;
    final failed = syncQueueBox.values
        .where((item) => item.status == 'failed' && canRetryAutomatically(item))
        .toList(growable: false);
    for (final item in failed) {
      item.status = 'pending';
      item.retryCount = 0;
      item.lastError = null;
      item.errorCategory = null;
      item.errorCode = null;
      item.nextRetryAt = null;
      await item.save();
    }
    await syncQueueBox.flush();
  }

  bool canRetry(SyncQueueItem item) {
    if (canRebaseLatestInvoiceDelete(item)) return true;
    final category = item.errorCategory ??
        (item.status == 'failed'
            ? SyncFailureClassifier.inferCategory(item.lastError)
            : null);
    return SyncErrorCategories.canRetry(category);
  }

  bool canRetryAutomatically(SyncQueueItem item) {
    if (canRebaseLatestInvoiceDelete(item)) return true;
    final category = item.errorCategory ??
        (item.status == 'failed'
            ? SyncFailureClassifier.inferCategory(item.lastError)
            : null);
    return SyncErrorCategories.canRetryAutomatically(category);
  }

  /// Version 2 invoice deletions are safe to retry after a conflict because
  /// the uploader rebuilds their balance, stock, and cash reversals from the
  /// latest cloud invoice inside the same transaction.
  bool canRebaseLatestInvoiceDelete(SyncQueueItem item) {
    if (!const {
      'deleteInvoice',
      'deleteReturn',
      'deleteReturnInvoice',
      'deleteBuyingInvoice',
    }.contains(item.operationType)) return false;
    try {
      if (decodePayload(item)['financialFormat'] != 2) return false;
      if (item.status != 'failed') return true;
      final category = item.errorCategory ??
          SyncFailureClassifier.inferCategory(item.lastError);
      return category == SyncErrorCategories.conflict;
    } catch (_) {
      return false;
    }
  }

  bool isReadyForAutomaticAttempt(SyncQueueItem item, DateTime now) {
    if (item.status == 'pending') return true;
    if (item.status != 'failed' ||
        !canRetryAutomatically(item) ||
        item.retryCount >= 5) {
      return false;
    }
    return item.nextRetryAt == null || !item.nextRetryAt!.isAfter(now);
  }

  /// Decode payload JSON back to a Dart Map.
  static Map<String, dynamic> decodePayload(SyncQueueItem item) {
    return jsonDecode(item.payloadJson) as Map<String, dynamic>;
  }
}
