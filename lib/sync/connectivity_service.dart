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

    _subscription = Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged);

    // Periodic check every 25 seconds to drain queue when online
    _periodicTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (SyncQueueManager.instance.hasPending) {
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
      final dynamic rawResult = await Connectivity().checkConnectivity();
      final bool hasNetwork = _hasNetworkConnection(rawResult);

      if (hasNetwork) {
        _setOnline(true);
        if (SyncQueueManager.instance.hasPending) {
          await BatchSyncEngine.instance.processQueue();
        }
      } else {
        _setOnline(false);
      }
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
  Future<void> forceSync() async {
    await _checkAndSync();
  }

  @Deprecated('Use forceSync instead')
  Future<void> forcSync() => forceSync();
}
