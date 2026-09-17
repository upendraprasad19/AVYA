// Behavioral regression test — manual force-retry + enqueueFresh count
// notify (branch sync-banner-force-retry, 2026-09-17).
//
// Two defects this pins, both on the REAL SyncQueue runtime path with a
// real Hive syncBox (repo precedent: bodyweight_capability_leak_test.dart
// — Hive.init(tempDir) + openBox + markInitializedForTests, no
// path_provider mock needed since syncBox is a SHARED box with no
// migrator dependency):
//
// 1. The manual "Retry now" tap used to issue a plain drain() whose
//    `_isDue` backoff filter could skip the very op the user is asking to
//    retry — a silent no-op with zero feedback. `drain({force: true})`
//    must retry an op sitting inside its backoff window, a force request
//    arriving WHILE a pass is in flight must force the coalesced rerun
//    pass (capture-then-apply at the TOP of the loop — plan-review round 2
//    Finding 1), and a plain drain() must never force.
// 2. `enqueueFresh`'s success path removed the op without notifying the
//    pending-count stream — the banner could stick at "1 change waiting"
//    until an unrelated event (plan-review round 2 Finding 4,
//    pre-existing).
//
// Also pins the retry budget end-to-end: an op dies after maxRetries(7)
// total attempts, replacing the phantom
// `sync_queue_retry_budget_consistency_test.dart` promise the old
// sync_queue.dart header comment made (never written; corrected in this
// batch).
//
// Run: flutter test test/contracts/sync_queue_force_retry_test.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/result.dart';
import 'package:icanbefitter/core/services/sync_error.dart';
import 'package:icanbefitter/core/services/sync_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_force_retry');
    Hive.init(tempDir.path);
    HiveService.instance.markInitializedForTests();
  });

  tearDownAll(() async {
    // Cleanup is hygiene, not an assertion — a throw here would stack a
    // second failure that hides the real one (see the precedent file).
    try {
      if (Hive.isBoxOpen(HiveService.syncBoxName)) {
        await Hive.box(HiveService.syncBoxName).close();
      }
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    if (Hive.isBoxOpen(HiveService.syncBoxName)) {
      await Hive.box(HiveService.syncBoxName).close();
    }
    try {
      await Hive.deleteBoxFromDisk(HiveService.syncBoxName);
    } catch (_) {}
    await Hive.openBox(HiveService.syncBoxName);
    await SyncQueue.instance.clearAll();
    SyncQueue.instance.onDeadLetter = null;
  });

  tearDown(() async {
    SyncQueue.instance.onDeadLetter = null;
    await SyncQueue.instance.clearAll();
  });

  group('force retry (the manual-tap fix)', () {
    test('plain drain() SKIPS an op inside its backoff window; '
        'drain(force: true) retries and clears it', () async {
      var attempts = 0;
      // Every scenario registers its own fake over the same opType —
      // registerExecutor overwrites (no unregister API exists; plan-review
      // round 2 Finding 7) and no other test touches this singleton at
      // runtime (grep-verified).
      SyncQueue.instance.registerExecutor(
        'test_op',
        (payload) async {
          attempts++;
          return Result.ok(null);
        },
      );

      final errAt = DateTime.now();
      await SyncQueue.instance.enqueue(
        opType: 'test_op',
        payload: const <String, dynamic>{},
        initialError: NetworkError(message: 'seed', at: errAt),
      );

      // Legible-failure guard (plan-review round 2 Finding 6): the
      // not-due premise below rides the 1s backoff of a freshly enqueued
      // op (retryCount=1 → backoff idx 0). If this environment stalls
      // past ~900ms between err construction and here, fail THIS instead
      // of a confusing skip assertion.
      expect(
        DateTime.now().difference(errAt).inMilliseconds,
        lessThan(900),
        reason: 'test env too slow for the 1s backoff premise — this run '
            'proves nothing about the skip path',
      );

      await SyncQueue.instance.drain();
      expect(attempts, 0,
          reason: 'the op sits inside its 1s backoff window — a PLAIN '
              'drain must skip it (this is the mutation target: removing '
              '`!passForce && ` reddens exactly this assertion)');
      expect(SyncQueue.instance.pendingOps(), hasLength(1),
          reason: 'a skipped op stays queued — the banner would still '
              'show it');

      await SyncQueue.instance.drain(force: true);
      expect(attempts, 1,
          reason: 'the forced pass must retry the backoff-windowed op — '
              'the Retry tap can never again be a silent no-op');
      expect(SyncQueue.instance.pendingOps(), isEmpty);
    });

    test('forced drain dead-letters a NON-TRANSIENT failure immediately '
        '(the executor RETURNS Result.err — _runOne has no try/catch, so '
        'a throwing executor is out of contract)', () async {
      SyncQueue.instance.registerExecutor(
        'test_op',
        (payload) async =>
            Result.err(ValidationError(message: 'never valid', at: DateTime.now())),
      );
      final deadLettered = <PendingSyncOp>[];
      final dlGate = Completer<void>();
      SyncQueue.instance.onDeadLetter = (op) async {
        deadLettered.add(op);
        if (!dlGate.isCompleted) dlGate.complete();
      };

      await SyncQueue.instance.enqueue(
        opType: 'test_op',
        payload: const <String, dynamic>{},
        initialError: NetworkError(message: 'seed', at: DateTime.now()),
      );

      await SyncQueue.instance.drain(force: true);

      await dlGate.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () =>
            fail('onDeadLetter never fired for a non-transient failure'),
      );
      expect(SyncQueue.instance.pendingOps(), isEmpty,
          reason: 'a non-transient failure must dead-letter (be removed) '
              'on the FIRST attempt, forced or not — retrying a '
              'never-valid op just inflates the banner count');
      expect(deadLettered.single.lastErrorCode, 'ValidationError');
    });

    test('a force request arriving WHILE a pass is in flight forces the '
        'COALESCED RERUN pass (plan-review round 2 Finding 1 — the '
        'capture-then-apply-at-top ordering)', () async {
      final gate = Completer<Result<void, SyncError>>();
      var attempts = 0;
      SyncQueue.instance.registerExecutor(
        'test_op',
        (payload) async {
          attempts++;
          if (attempts == 1) return gate.future;
          return Result.ok(null);
        },
      );

      // Seed an op that is ALREADY due: enqueue paths set
      // firstAttemptAt/lastAttemptAt to the error time, so backdate it 5s
      // past the 1s backoff. enqueueFresh is deliberately NOT used — it
      // awaits its own _runOne internally (would deadlock this scenario)
      // and a plain pass would double-fire the still-persisted op
      // (plan-review round 2 Finding 2).
      await SyncQueue.instance.enqueue(
        opType: 'test_op',
        payload: const <String, dynamic>{},
        initialError: NetworkError(
          message: 'seed',
          at: DateTime.now().subtract(const Duration(seconds: 5)),
        ),
      );

      // Start a PLAIN drain. drain() runs synchronously to its first
      // await, so by the time this statement returns, pass 1 is already
      // parked inside the gated executor future.
      final drained = SyncQueue.instance.drain();
      expect(attempts, 1,
          reason: 'the op is due — pass 1 must already be inside the '
              'executor; if this fails the interleaving assumption is '
              'wrong, not the production code');

      // The user taps Retry while pass 1 is in flight: the in-flight
      // guard must record BOTH a rerun request AND its force.
      await SyncQueue.instance.drain(force: true);

      // Pass 1 fails transiently → withRetry → retryCount=2 → 5s backoff
      // → the op is NOT due on the rerun pass. Only the sticky force can
      // get it retried.
      gate.complete(
        Result.err(NetworkError(message: 'still conflicting', at: DateTime.now())),
      );
      await drained;

      expect(attempts, 2,
          reason: 'the rerun pass must be FORCED (capture-then-apply at '
              'the top of the loop): the op is inside a 5s backoff '
              'window, so an unforced rerun would skip it and this '
              'assertion reddens if the ordering is swapped (mutation '
              'm3)');
      expect(SyncQueue.instance.pendingOps(), isEmpty);
    });

    test('plain drain() never force-retries (regression: a force must not '
        'leak into later auto passes)', () async {
      var attempts = 0;
      SyncQueue.instance.registerExecutor(
        'test_op',
        (payload) async {
          attempts++;
          return Result.err(
              NetworkError(message: 'still failing', at: DateTime.now()));
        },
      );

      await SyncQueue.instance.enqueue(
        opType: 'test_op',
        payload: const <String, dynamic>{},
        initialError: NetworkError(message: 'seed', at: DateTime.now()),
      );

      await SyncQueue.instance.drain(force: true);
      expect(SyncQueue.instance.pendingOps().single.retryCount, 2,
          reason: 'one failed forced attempt bumps retryCount to 2 → '
              'backoff idx 1 → 5s window');
      final attemptsAfterForce = attempts;

      await SyncQueue.instance.drain();
      expect(attempts, attemptsAfterForce,
          reason: 'a PLAIN pass must skip the op in its 5s backoff window '
              '— force is per-call, never sticky into auto drains');
      expect(SyncQueue.instance.pendingOps(), hasLength(1));
    });
  });

  group('enqueueFresh notifies the pending-count stream (round 2 Finding 4)',
      () {
    test('success path ends the stream at 0 — no other notify path exists '
        'on removal', () async {
      SyncQueue.instance.registerExecutor(
        'test_op',
        (payload) async => Result.ok(null),
      );
      final events = <int>[];
      final sub = SyncQueue.instance.pendingCount.listen(events.add);
      // Let the subscription deliver before the mutations.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await SyncQueue.instance.enqueueFresh(
        opType: 'test_op',
        payload: const <String, dynamic>{},
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events, contains(0),
          reason: 'the op was enqueued (event 1 from _persist) and then '
              'successfully removed — removal has NO notify of its own '
              'except the one this batch added after _runOne; without it '
              'the stream stays at 1 and the banner sticks at '
              '"1 change waiting to sync" until an unrelated event '
              '(mutation m4: deleting that _notifyPending reddens this)');
      await sub.cancel();
    });
  });

  group('retry budget end-to-end (replaces the phantom '
      'sync_queue_retry_budget_consistency_test.dart promise)', () {
    test('an op dead-letters on the 7th total attempt, not before — '
        'pins maxRetries == backoff-schedule semantics at runtime', () async {
      var attempts = 0;
      SyncQueue.instance.registerExecutor(
        'test_op',
        (payload) async {
          attempts++;
          return Result.err(
              NetworkError(message: 'transient forever', at: DateTime.now()));
        },
      );
      final deadLettered = <PendingSyncOp>[];
      SyncQueue.instance.onDeadLetter = (op) async => deadLettered.add(op);

      await SyncQueue.instance.enqueue(
        opType: 'test_op',
        payload: const <String, dynamic>{},
        initialError: NetworkError(message: 'seed', at: DateTime.now()),
      );

      // retries 1..5: still queued (rc goes 2..6, below maxRetries=7).
      for (var i = 0; i < 5; i++) {
        await SyncQueue.instance.drain(force: true);
        expect(SyncQueue.instance.pendingOps(), hasLength(1),
            reason: 'attempt ${i + 2} of 7 — must not dead-letter yet');
      }
      expect(SyncQueue.instance.pendingOps().single.retryCount, 6);

      // 6th forced failed drain → rc=7 == maxRetries → dead-letter.
      await SyncQueue.instance.drain(force: true);
      expect(SyncQueue.instance.pendingOps(), isEmpty,
          reason: 'the 7th total attempt exhausts the budget');
      expect(deadLettered, hasLength(1));
      expect(attempts, 6,
          reason: '1 enqueue seed + 5 queued retries + the 6th retry that '
              'dead-letters — the executor ran exactly 6 times after the '
              'seed');
    });
  });
}
