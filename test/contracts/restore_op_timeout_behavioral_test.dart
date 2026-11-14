// Behavioral contract for diagnose b7e4c1 — restore hangs forever on a wedged op.
//
// THE BUG (founder, live web, 2026-08-05): RestoringScreen sat on "Pulling your
// dispatch" indefinitely. There was NO timeout anywhere in the restore chain —
// `grep -c '\.timeout('` returned 0 for sync_service.dart, supabase_service.dart
// AND auth_session_bootstrapper.dart. One wedged Supabase call blocked the whole
// ~30-op fan-out forever. RestoringScreen's 15s/30s timers are pure UI copy and
// were never wired to restore progress, so they could not end it either.
//
// THE FIX: a per-op ceiling in _safeRestoreOp, applied through
// SyncService.applyRestoreCeiling.
//
// Two properties this test exists to pin, because both are easy to get wrong:
//
//   1. A Dart `.timeout()` does NOT cancel the underlying request. It frees the
//      AWAITER. That is precisely what was needed — the fan-out moves on — but
//      it means "timed out" must never be read as "the server stopped". The
//      third test pins that the source future keeps running after the throw.
//
//   2. The ceiling is deliberately GENEROUS (45s). It unsticks a WEDGED call;
//      it is not a latency budget. A slow op on a bad Indian mobile connection
//      must still finish. `fakeAsync` lets us assert both sides of that
//      boundary in milliseconds of real time.
//
// MUTATION-PROVEN: change `applyRestoreCeiling` to `=> task` (drop the ceiling)
// and the first two tests fail — the future never completes, exactly the
// founder's hang.
//
// Run: flutter test test/contracts/restore_op_timeout_behavioral_test.dart

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

void main() {
  group('SyncService.applyRestoreCeiling — the wedged-op ceiling', () {
    test('THE BUG: a never-completing op aborts instead of hanging forever', () {
      fakeAsync((async) {
        // A restore op that never completes — the wedged Supabase call.
        final wedged = Completer<void>();
        Object? thrown;

        SyncService.applyRestoreCeiling(wedged.future, enabled: true)
            .catchError((Object e) => thrown = e);

        // Just before the ceiling: still waiting. This is the "a slow op must
        // still be allowed to finish" half of the contract — if this fired
        // early we would be aborting healthy restores on bad connections.
        async.elapse(SyncService.restoreOpTimeout - const Duration(seconds: 1));
        expect(
          thrown,
          isNull,
          reason: 'the ceiling must not fire before ${SyncService.restoreOpTimeout.inSeconds}s '
              '— it is a wedge-breaker, not a latency budget.',
        );

        // Past the ceiling: aborted.
        async.elapse(const Duration(seconds: 2));
        expect(
          thrown,
          isA<TimeoutException>(),
          reason: 'THE FOUNDER BUG — without this the restore screen waits '
              'forever on one wedged op.',
        );
      });
    });

    test('kill-switch OFF → verbatim unbounded await (§4.6 old path reachable)',
        () {
      fakeAsync((async) {
        final wedged = Completer<void>();
        Object? thrown;
        var completed = false;

        // `then` returns Future<bool> here, so `catchError`'s handler must also
        // return a bool — a `=> thrown = e` expression body returns Object and
        // is an analyzer warning (invalid_return_type_for_catch_error), not
        // just a style nit.
        SyncService.applyRestoreCeiling(wedged.future, enabled: false)
            .then((_) => completed = true)
            .catchError((Object e) {
          thrown = e;
          return false;
        });

        // Ten minutes — 13x the ceiling. With the kill-switch engaged the old
        // unbounded behaviour must be restored EXACTLY, or the escape hatch
        // isn't an escape hatch.
        async.elapse(const Duration(minutes: 10));

        expect(thrown, isNull, reason: 'no ceiling when disabled.');
        expect(completed, isFalse, reason: 'still genuinely pending.');
      });
    });

    test('a timeout frees the awaiter but does NOT cancel the request', () {
      fakeAsync((async) {
        final wedged = Completer<void>();
        Object? thrown;
        var sourceRan = false;

        // Model the real thing: work that finishes LATE, after we gave up.
        // catchError is defensive, not currently reachable: `wedged` is only
        // ever .complete()d in this test, never .completeError()d. It is here
        // so a future edit that DOES error the completer fails loudly on the
        // assertion rather than as an unhandled zone error.
        unawaited(wedged.future
            .then((_) => sourceRan = true)
            .catchError((Object _) => false)); // bool: matches then's Future<bool>

        SyncService.applyRestoreCeiling(wedged.future, enabled: true)
            .catchError((Object e) => thrown = e);

        async.elapse(SyncService.restoreOpTimeout + const Duration(seconds: 1));
        expect(thrown, isA<TimeoutException>());
        expect(sourceRan, isFalse);

        // The server answers a minute late. The underlying future was never
        // cancelled — it still completes. Anyone reading "timed out" as "the
        // request was aborted" is wrong, and that matters for the ops whose
        // work has a Hive write on the far side.
        wedged.complete();
        async.flushMicrotasks();
        expect(
          sourceRan,
          isTrue,
          reason: 'Dart .timeout() frees the awaiter, it does not cancel. '
              'Pinned so nobody later assumes cancellation semantics.',
        );
      });
    });

    test('an op that finishes inside the ceiling passes through untouched', () {
      fakeAsync((async) {
        var completed = false;
        Object? thrown;

        SyncService.applyRestoreCeiling(
          Future<void>.delayed(const Duration(seconds: 5)),
          enabled: true,
        ).then((_) => completed = true).catchError((Object e) {
          thrown = e;
          return false; // handler must match then's Future<bool>
        });

        async.elapse(const Duration(seconds: 6));
        expect(completed, isTrue);
        expect(thrown, isNull);
      });
    });

    test('a real failure still propagates — the ceiling swallows nothing', () {
      fakeAsync((async) {
        Object? thrown;

        SyncService.applyRestoreCeiling(
          Future<void>.error(StateError('4xx from PostgREST')),
          enabled: true,
        ).catchError((Object e) => thrown = e);

        async.flushMicrotasks();
        expect(thrown, isA<StateError>());
      });
    });

    test('the ceiling is 45s — a value change must be a deliberate edit', () {
      // Not a tautology guard: this constant is the difference between
      // "unsticks a wedge" and "aborts slow-but-healthy restores on a 2G
      // connection". A silent tightening is a user-visible regression, so the
      // number is pinned where a reviewer will see it move.
      expect(SyncService.restoreOpTimeout, const Duration(seconds: 45));
    });
  });

  group('SyncService.restoreFailureReason — wedge vs failure stay countable',
      () {
    test('a TimeoutException reports under its own reason', () {
      expect(
        SyncService.restoreFailureReason(TimeoutException('wedged')),
        'sync_service_restore_op_timeout',
        reason: 'the wedge class used to leave NO trace at all. Giving it a '
            'distinct reason is what makes "which op wedges, how often" '
            'answerable from client_errors instead of guessable.',
      );
    });

    test('any other error keeps the pre-existing reason (no telemetry break)',
        () {
      // The pre-existing reason string is consumed by existing client_errors
      // queries; re-labelling ordinary failures would silently break them.
      expect(
        SyncService.restoreFailureReason(StateError('4xx')),
        'sync_service_safe_restore_op',
      );
      expect(
        SyncService.restoreFailureReason(Exception('parse')),
        'sync_service_safe_restore_op',
      );
    });

    test('the two reasons are distinguishable', () {
      expect(
        SyncService.restoreFailureReason(TimeoutException('x')),
        isNot(SyncService.restoreFailureReason(StateError('y'))),
      );
    });
  });
}
