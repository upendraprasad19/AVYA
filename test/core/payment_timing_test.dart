// OI-182 — the payment grace window is DERIVED from the verify-retry schedule
// and every activation-flow network call is BOUNDED (payment_timing.dart).
//
// Pure: no Hive, no Supabase, no Razorpay plugin — so `fakeAsync` runs with no
// real I/O (CLAUDE.md §4.9: awaiting real disk I/O inside a fake-async zone
// hangs; this file has none).
//
// WHAT EACH GROUP PROVES, and what it does not:
//   - "derived budget/window": the numbers are recomputed here INDEPENDENTLY
//     (literals, not the library's own helpers), so mutating the derivation
//     reddens an assertion. `window > last + budget` alone would be an identity
//     and could never redden — it is deliberately not the only check.
//   - "boundedAttempt": proves the HELPER times out at the bound and does not
//     cancel the source. It does NOT prove razorpay_service.dart calls it — that
//     wiring is pinned separately by a source-grep contract
//     (payment_grace_window_derived_wiring_test.dart), which is presence-only.
//
// Run: flutter test test/core/payment_timing_test.dart

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/payment_timing.dart';

void main() {
  group('Phase-1 poll schedule', () {
    test('15 polls sleep 2s x5, 3s x5, 4s x5 = 45s (independent recompute)', () {
      expect(kPhase1PollAttempts, 15);
      var total = 0;
      for (var a = 0; a < kPhase1PollAttempts; a++) {
        total += pollDelaySeconds(a);
      }
      expect(total, 5 * 2 + 5 * 3 + 5 * 4);
      expect(total, 45);
      expect(pollDelaySeconds(0), 2);
      expect(pollDelaySeconds(4), 2);
      expect(pollDelaySeconds(5), 3);
      expect(pollDelaySeconds(9), 3);
      expect(pollDelaySeconds(10), 4);
      expect(pollDelaySeconds(14), 4);
    });

    test('exact-match polls are a strict prefix of all polls', () {
      // The loop has an exact-match leg and a fallback leg; if this ever
      // reaches kPhase1PollAttempts the fallback leg becomes unreachable.
      expect(kPhase1ExactMatchAttempts, lessThan(kPhase1PollAttempts));
      expect(kPhase1ExactMatchAttempts, 12);
    });
  });

  group('derived budget and window', () {
    test('retry schedule is 60s, 5m, 15m', () {
      expect(kVerificationRetryDelays, const [
        Duration(seconds: 60),
        Duration(minutes: 5),
        Duration(minutes: 15),
      ]);
    });

    test('kActivationPhasesBudget = 45s sleeps + 15 x 8s + 60s = 225s', () {
      // Independent: none of these literals come from the library's helpers.
      const sleeps = 45;
      const polls = 15 * 8;
      const phase2 = 60;
      expect(kActivationPhasesBudget, const Duration(seconds: sleeps + polls + phase2));
      expect(kActivationPhasesBudget, const Duration(seconds: 225));
    });

    test('kPaymentGraceWindow = 15m + 225s + 60s + 2m = 1305s (21m45s)', () {
      const last = 15 * 60;
      const budget = 225;
      const retryAttempt = 60;
      const margin = 2 * 60;
      expect(kPaymentGraceWindow, const Duration(seconds: last + budget + retryAttempt + margin));
      expect(kPaymentGraceWindow, const Duration(seconds: 1305));
    });

    test('the window outlives EVERY retry plus the phases before it', () {
      for (final d in kVerificationRetryDelays) {
        // Grace opens BEFORE Phase 1; a retry fires at (phases + d) after that
        // and then runs for up to kRetryAttemptTimeout.
        final lastActivity =
            d + kActivationPhasesBudget + kRetryAttemptTimeout;
        expect(kPaymentGraceWindow, greaterThan(lastActivity),
            reason: 'retry at +$d would run after grace closed');
      }
    });

    test('the window is longer than the OLD 10-minute literal that caused OI-182', () {
      expect(kPaymentGraceWindow, greaterThan(const Duration(minutes: 10)));
      // The pre-fix last retry fired at ~15m + phases: a 17-minute-old grace
      // record must still count as in flight.
      expect(kPaymentGraceWindow, greaterThan(const Duration(minutes: 17)));
    });
  });

  group('boundedAttempt', () {
    test('returns the value when the thunk completes inside the bound', () {
      fakeAsync((async) {
        int? got;
        boundedAttempt<int>(
          () => Future<int>.delayed(const Duration(seconds: 3), () => 42),
          const Duration(seconds: 8),
        ).then((v) => got = v);
        async.elapse(const Duration(seconds: 3));
        expect(got, 42);
      });
    });

    test('a never-completing thunk fails with TimeoutException AT the bound, not before', () {
      fakeAsync((async) {
        final wedged = Completer<void>();
        Object? thrown;
        boundedAttempt<void>(
          () => wedged.future,
          const Duration(seconds: 8),
          label: 'subscription poll',
        ).catchError((Object e) {
          thrown = e;
        });

        async.elapse(const Duration(seconds: 7, milliseconds: 999));
        expect(thrown, isNull, reason: 'must not fire before the bound');

        async.elapse(const Duration(milliseconds: 1));
        expect(thrown, isA<TimeoutException>());
        // The message names the call and the bound (a bare harness timeout
        // would name neither).
        expect((thrown as TimeoutException).message,
            'subscription poll timed out after 8s');
      });
    });

    test('a timeout frees the awaiter but does NOT cancel the source', () {
      fakeAsync((async) {
        final wedged = Completer<void>();
        var sourceRan = false;
        unawaited(wedged.future.then((_) => sourceRan = true));

        Object? thrown;
        boundedAttempt<void>(() => wedged.future, const Duration(seconds: 8))
            .catchError((Object e) {
          thrown = e;
        });
        async.elapse(const Duration(seconds: 8));
        expect(thrown, isA<TimeoutException>());
        expect(sourceRan, isFalse);

        // The work finishes LATE, after we gave up — it is not cancelled.
        // This is why writes must live OUTSIDE the thunk.
        wedged.complete();
        async.flushMicrotasks();
        expect(sourceRan, isTrue);
      });
    });

    test('a synchronous throw inside the thunk becomes a Future error', () {
      fakeAsync((async) {
        Object? thrown;
        boundedAttempt<void>(
          () => throw StateError('boom'),
          const Duration(seconds: 8),
        ).catchError((Object e) {
          thrown = e;
        });
        async.flushMicrotasks();
        expect(thrown, isA<StateError>());
      });
    });
  });
}
