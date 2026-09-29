import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kareem_store/sync/cloud_refresh_gate.dart';
import 'package:kareem_store/sync/firestore_read_diagnostics.dart';
import 'package:kareem_store/sync/firestore_sync_checkpoint.dart';

void main() {
  group('CloudRefreshGate', () {
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 9, 29, 8);
      CloudRefreshGate.resetForTest(clock: () => now);
    });

    test('coalesces concurrent requests for the same query', () async {
      final release = Completer<void>();
      var calls = 0;

      Future<void> action() async {
        calls++;
        await release.future;
      }

      final first = CloudRefreshGate.run('clients.delta', action);
      final second = CloudRefreshGate.run('clients.delta', action);
      expect(identical(first, second), isTrue);
      expect(calls, 1);

      release.complete();
      await Future.wait([first, second]);
      expect(calls, 1);
    });

    test('suppresses navigation repeats during cooldown then allows refresh',
        () async {
      var calls = 0;
      Future<void> action() async {
        calls++;
      }

      await CloudRefreshGate.run('suppliers.delta', action);
      await CloudRefreshGate.run('suppliers.delta', action);
      expect(calls, 1);

      now = now.add(const Duration(minutes: 2));
      await CloudRefreshGate.run('suppliers.delta', action);
      expect(calls, 2);
    });

    test('a failed refresh can be retried immediately', () async {
      var calls = 0;
      Future<void> action() async {
        calls++;
        if (calls == 1) throw StateError('offline');
      }

      await expectLater(
        CloudRefreshGate.run('invoices.delta', action),
        throwsStateError,
      );
      await CloudRefreshGate.run('invoices.delta', action);
      expect(calls, 2);
    });
  });

  test('read diagnostics distinguish queries and listener lifecycle', () {
    FirestoreReadDiagnostics.reset();
    FirestoreReadDiagnostics.queryResult(
      'invoices where updatedAt >= cursor',
      3,
      trigger: 'invoice delta',
    );
    FirestoreReadDiagnostics.listenerAttached(
      'financial receipts',
      trigger: 'realtime feed',
    );
    FirestoreReadDiagnostics.listenerSnapshot(
      'financial receipts',
      2,
      trigger: 'realtime feed',
      changes: 1,
    );
    FirestoreReadDiagnostics.listenerDetached(
      'financial receipts',
      trigger: 'realtime feed',
    );
    FirestoreReadDiagnostics.transactionAttempt('financial upload');
    FirestoreReadDiagnostics.transactionAttempt('financial upload');
    FirestoreReadDiagnostics.transactionRead(
      'clients/client-1',
      exists: true,
    );

    final metrics = FirestoreReadDiagnostics.snapshot();
    final query = metrics.singleWhere((m) => m.trigger == 'invoice delta');
    final listener = metrics.singleWhere((m) => m.trigger == 'realtime feed');
    expect(query.requests, 1);
    expect(query.documents, 3);
    expect(listener.listenerAttaches, 1);
    expect(listener.listenerSnapshots, 1);
    expect(listener.listenerDetaches, 1);
    expect(listener.activeListeners, 0);
    expect(listener.documents, 2);
    expect(listener.listenerChanges, 1);
    final transaction =
        metrics.singleWhere((m) => m.identity == 'financial upload');
    expect(transaction.transactionAttempts, 2);
    final transactionRead =
        metrics.singleWhere((m) => m.identity == 'clients/client-1');
    expect(transactionRead.transactionReads, 1);
  });

  group('FirestoreSyncCheckpoint', () {
    test('advances only to timestamps returned in persisted documents', () {
      final first = DateTime.utc(2026, 9, 29, 8);
      final second = DateTime.utc(2026, 9, 29, 9);
      final checkpoint = FirestoreSyncCheckpoint.newest(
        [
          {'updatedAt': first},
          {'updatedAt': second},
          {'updatedAt': null},
        ],
        const ['updatedAt'],
      );
      expect(checkpoint, second);
    });

    test('does not advance an existing cursor when a delta is empty', () {
      final existing = DateTime.utc(2026, 9, 29, 9);
      final checkpoint = FirestoreSyncCheckpoint.newest(
        const [],
        const ['updatedAt'],
        floor: existing,
      );
      expect(checkpoint, existing);
    });
  });
}
