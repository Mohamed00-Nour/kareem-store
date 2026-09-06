import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'batch_sync_engine.dart';
import 'sync_queue_manager.dart';

/// Listens to network connectivity changes and triggers [BatchSyncEngine]
/// when internet connection is detected.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  StreamSubscription? _subscription;
  Timer? _periodicTimer;
  bool _isOnline = false;
  bool _isChecking = false;
  // When forceSync is called while a check is running, this flag ensures the
  // sync is retried immediately after the current check completes.
  bool _pendingForce = false;

  /// True when the last check passed.
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
  /// Call once from [main()] before [runApp()].
  void startListening() {
    _subscription?.cancel();
    _periodicTimer?.cancel();

    _subscription =
        Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);

    // Periodic check — every 5 s when there are pending items, otherwise every 30 s.
    // This ensures a freshly enqueued item is always picked up quickly.
    _periodicTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (SyncQueueManager.instance.hasUnfinished) {
        _checkAndSync();
      }
    });

    // Initial check
    _checkAndSync();
  }

  /// Stop listening (call on app dispose if needed).
  void dispose() {
    _subscription?.cancel();
    _periodicTimer?.cancel();
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

  /// Validates connection and triggers background queue processing.
  Future<void> _checkAndSync() async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      do {
        _pendingForce = false;
        final dynamic rawResult = await Connectivity().checkConnectivity();
        final bool hasNetwork = _hasNetworkConnection(rawResult);

        if (hasNetwork) {
          _setOnline(true);
          if (SyncQueueManager.instance.hasUnfinished) {
            await BatchSyncEngine.instance.processQueue();
          }
        } else {
          _setOnline(false);
        }
        // If forceSync() was called while we were busy, loop and re-run.
      } while (_pendingForce);
    } catch (_) {
      _setOnline(false);
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

  /// Manually trigger a sync attempt (e.g. after adding an invoice or "Sync Now" button).
  /// If a check is already running, the sync is guaranteed to execute once the
  /// current check finishes (no silent drop).
  Future<void> forceSync() async {
    await SyncQueueManager.instance.resetFailedItems();
    if (_isChecking) {
      // Signal that a full re-run is needed after the current check finishes.
      _pendingForce = true;
      return;
    }
    await _checkAndSync();
  }

  @Deprecated('Use forceSync instead')
  Future<void> forcSync() => forceSync();
}
