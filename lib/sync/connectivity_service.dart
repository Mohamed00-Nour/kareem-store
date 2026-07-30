import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'batch_sync_engine.dart';
import 'sync_queue_manager.dart';

/// Listens to network connectivity changes and triggers [BatchSyncEngine]
/// when a **stable** internet connection is detected.
///
/// "Stable" means: connectivity_plus reports a non-none result
/// AND the check passes 3 consecutive times (avoids false positives
/// on weak/flapping Wi-Fi connections).
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  StreamSubscription? _subscription;
  bool _isOnline = false;
  bool _isChecking = false;

  /// True when the last stability check passed.
  bool get isOnline => _isOnline;

  /// Number of pending items waiting to be synced.
  int get pendingCount => SyncQueueManager.instance.pendingCount;

  /// Stream of connectivity state changes — use for UI status badge.
  /// Emits [true] when online, [false] when offline.
  final StreamController<bool> _onlineController =
      StreamController<bool>.broadcast();
  Stream<bool> get onlineStream => _onlineController.stream;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Start listening for connectivity changes.
  /// Call once from [main()] or from a top-level widget.
  void startListening() {
    _subscription?.cancel();
    _subscription = Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged);

    // Initial stability check
    _checkAndSync();
  }

  /// Stop listening (call on app dispose if needed).
  void dispose() {
    _subscription?.cancel();
    _isChecking = false;
    _onlineController.close();
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  Future<void> _onConnectivityChanged(dynamic event) async {
    final bool hasNetwork = _hasNetworkConnection(event);
    if (hasNetwork) {
      await _checkAndSync();
    } else {
      _isChecking = false;
      _setOnline(false);
    }
  }

  static bool _hasNetworkConnection(dynamic status) {
    if (status is List) {
      return status.any((r) => r != ConnectivityResult.none);
    } else if (status is ConnectivityResult) {
      return status != ConnectivityResult.none;
    }
    return false;
  }

  /// Validates connection stability with 3 re-checks before triggering sync.
  Future<void> _checkAndSync() async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      int stableCount = 0;
      for (int i = 0; i < 3; i++) {
        if (!_isChecking) return; // Aborted due to disconnect or dispose
        final dynamic rawResult = await Connectivity().checkConnectivity();
        final bool hasNetwork = _hasNetworkConnection(rawResult);
        if (hasNetwork) {
          stableCount++;
        } else {
          stableCount = 0;
          break;
        }
        if (i < 2) await Future.delayed(const Duration(seconds: 1));
      }

      if (stableCount >= 3) {
        _setOnline(true);
        // Only process queue if there are pending items.
        if (SyncQueueManager.instance.hasPending) {
          await BatchSyncEngine.instance.processQueue();
        }
      } else {
        _setOnline(false);
      }
    } finally {
      _isChecking = false;
    }
  }

  void _setOnline(bool online) {
    _isOnline = online;
    if (!_onlineController.isClosed) {
      _onlineController.add(online);
    }
  }

  /// Manually trigger a sync attempt (for the "Sync Now" button).
  Future<void> forceSync() async {
    await _checkAndSync();
  }

  @Deprecated('Use forceSync instead')
  Future<void> forcSync() => forceSync();
}
