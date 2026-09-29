import 'package:flutter/foundation.dart';

/// Debug-only, process-local visibility into Firestore read paths.
///
/// These counters describe SDK requests, documents delivered to this process,
/// and listener lifecycle. They are deliberately not presented as billed-read
/// totals: cache state, reconnects, security rules, and Firestore billing rules
/// can make the console total differ from what the client observes.
class FirestoreReadDiagnostics {
  FirestoreReadDiagnostics._();

  static final Map<String, FirestoreReadMetric> _metrics = {};

  static void queryResult(
    String identity,
    int documents, {
    required String trigger,
    bool fromCache = false,
  }) {
    if (!kDebugMode) return;
    final metric = _metric(identity, trigger);
    metric
      ..requests += 1
      ..documents += documents;
    if (fromCache) metric.cacheResults++;
    _print(metric, 'query docs=$documents cache=$fromCache');
  }

  static void queryError(
    String identity,
    Object error, {
    required String trigger,
  }) {
    if (!kDebugMode) return;
    final metric = _metric(identity, trigger)..errors += 1;
    _print(metric, 'query error=$error');
  }

  static void listenerAttached(String identity, {required String trigger}) {
    if (!kDebugMode) return;
    final metric = _metric(identity, trigger)
      ..listenerAttaches += 1
      ..activeListeners += 1;
    _print(metric, 'listener attached active=${metric.activeListeners}');
  }

  static void listenerSnapshot(
    String identity,
    int documents, {
    required String trigger,
    bool fromCache = false,
    int? changes,
  }) {
    if (!kDebugMode) return;
    final metric = _metric(identity, trigger)
      ..listenerSnapshots += 1
      ..documents += documents
      ..listenerChanges += changes ?? 0;
    if (fromCache) metric.cacheResults++;
    _print(
      metric,
      'listener snapshot docs=$documents changes=${changes ?? 'unknown'} '
      'cache=$fromCache',
    );
  }

  static void listenerDetached(String identity, {required String trigger}) {
    if (!kDebugMode) return;
    final metric = _metric(identity, trigger)..listenerDetaches += 1;
    if (metric.activeListeners > 0) metric.activeListeners -= 1;
    _print(metric, 'listener detached active=${metric.activeListeners}');
  }

  static void transactionAttempt(String identity) {
    if (!kDebugMode) return;
    final metric = _metric(identity, 'transaction')..transactionAttempts += 1;
    _print(metric, 'transaction attempt=${metric.transactionAttempts}');
  }

  static void transactionRead(String identity, {required bool exists}) {
    if (!kDebugMode) return;
    final metric = _metric(identity, 'transaction')
      ..transactionReads += 1
      ..documents += exists ? 1 : 0;
    _print(metric, 'transaction read exists=$exists');
  }

  static List<FirestoreReadMetric> snapshot() =>
      _metrics.values.map((metric) => metric.copy()).toList(growable: false)
        ..sort((a, b) => b.documents.compareTo(a.documents));

  @visibleForTesting
  static void reset() => _metrics.clear();

  static FirestoreReadMetric _metric(String identity, String trigger) =>
      _metrics.putIfAbsent(
        '$trigger::$identity',
        () => FirestoreReadMetric(identity: identity, trigger: trigger),
      );

  static void _print(FirestoreReadMetric metric, String event) {
    debugPrint(
      '[FirestoreReads] ${metric.trigger} | ${metric.identity} | $event | '
      'requests=${metric.requests} delivered=${metric.documents}',
    );
  }
}

class FirestoreReadMetric {
  FirestoreReadMetric({required this.identity, required this.trigger});

  final String identity;
  final String trigger;
  int requests = 0;
  int documents = 0;
  int cacheResults = 0;
  int errors = 0;
  int listenerAttaches = 0;
  int listenerSnapshots = 0;
  int listenerChanges = 0;
  int listenerDetaches = 0;
  int activeListeners = 0;
  int transactionAttempts = 0;
  int transactionReads = 0;

  FirestoreReadMetric copy() {
    final copy = FirestoreReadMetric(identity: identity, trigger: trigger)
      ..requests = requests
      ..documents = documents
      ..cacheResults = cacheResults
      ..errors = errors
      ..listenerAttaches = listenerAttaches
      ..listenerSnapshots = listenerSnapshots
      ..listenerChanges = listenerChanges
      ..listenerDetaches = listenerDetaches
      ..activeListeners = activeListeners
      ..transactionAttempts = transactionAttempts
      ..transactionReads = transactionReads;
    return copy;
  }
}
