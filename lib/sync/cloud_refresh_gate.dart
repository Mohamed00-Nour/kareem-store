/// Coalesces identical cloud refreshes and suppresses immediate repeats.
///
/// UI screens continue to render Hive immediately. A refresh already running
/// is shared by all callers, and opening the same screen repeatedly within the
/// cooldown does not issue another Firestore query.
class CloudRefreshGate {
  CloudRefreshGate._();

  static final Map<String, Future<void>> _active = {};
  static final Map<String, DateTime> _lastSuccess = {};
  static DateTime Function() _clock = DateTime.now;

  static Future<void> run(
    String identity,
    Future<void> Function() action, {
    Duration cooldown = const Duration(minutes: 1),
    bool force = false,
  }) {
    final running = _active[identity];
    if (running != null) return running;

    final last = _lastSuccess[identity];
    if (!force && last != null && _clock().difference(last) < cooldown) {
      return Future.value();
    }

    late final Future<void> future;
    future = Future.sync(action).then((_) {
      _lastSuccess[identity] = _clock();
    }).whenComplete(() {
      if (identical(_active[identity], future)) _active.remove(identity);
    });
    _active[identity] = future;
    return future;
  }

  static bool isRunning(String identity) => _active.containsKey(identity);

  static DateTime? lastSuccess(String identity) => _lastSuccess[identity];

  static void resetForTest({DateTime Function()? clock}) {
    _active.clear();
    _lastSuccess.clear();
    _clock = clock ?? DateTime.now;
  }
}
