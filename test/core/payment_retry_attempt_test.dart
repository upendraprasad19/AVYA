// OI-182 — ORDER of the side effects of one verify-payment retry attempt.
//
// The retry's success branch used to call refreshFromSupabase() and delete
// localActivationAt but NEVER clearPaymentInFlight(); with the grace window
// widened to outlive the last retry, that turns the retry's reconcile into a
// no-op (refreshFromSupabase returns early while isPaymentInFlight).
//
// Each side effect is a SEPARATELY injected callback so a recorder can assert
// the order. With one `onVerified` closure, "delete the clear" would redden
// nothing (plan-review R3 P1: a zero-red mutation).
//
// Run: flutter test test/core/payment_retry_attempt_test.dart

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/payment_timing.dart';
import 'package:icanbefitter/core/services/payment_retry_attempt.dart';

class _Recorder {
  final calls = <String>[];
  String? wroteExpiresAt;
  String? wrotePlan;
}

Future<bool> _run(
  _Recorder r, {
  required Future<Map<String, dynamic>?> Function() callVerify,
  bool sessionUnchanged = true,
  String fallbackPlan = 'monthly',
}) {
  return runVerificationRetryAttempt(
    callVerify: callVerify,
    sessionUnchanged: () => sessionUnchanged,
    fallbackPlan: fallbackPlan,
    fallbackEndDate: (plan) => 'fallback-end-for-$plan',
    writeState: ({required String expiresAt, required String plan}) async {
      r.calls.add('writeState');
      r.wroteExpiresAt = expiresAt;
      r.wrotePlan = plan;
    },
    clearGrace: () async => r.calls.add('clearGrace'),
    refresh: () async => r.calls.add('refresh'),
    clearLocalActivation: () async => r.calls.add('clearLocalActivation'),
  );
}

void main() {
  group('verified reply', () {
    test('runs writeState -> clearGrace -> refresh -> clearLocalActivation IN THAT ORDER',
        () async {
      final r = _Recorder();
      final verified = await _run(r, callVerify: () async => {
            'verified': true,
            'end_date': '2027-01-01T00:00:00.000Z',
            'plan': 'yearly',
          });
      expect(verified, isTrue);
      expect(r.calls,
          ['writeState', 'clearGrace', 'refresh', 'clearLocalActivation']);
    });

    test('writes the SERVER end_date and plan, not the optimistic fallback', () async {
      final r = _Recorder();
      await _run(r, callVerify: () async => {
            'verified': true,
            'end_date': '2027-01-01T00:00:00.000Z',
            'plan': 'yearly',
          });
      expect(r.wroteExpiresAt, '2027-01-01T00:00:00.000Z');
      expect(r.wrotePlan, 'yearly');
    });

    test('a missing end_date falls back to the caller-supplied computation for the reply plan',
        () async {
      final r = _Recorder();
      await _run(r,
          callVerify: () async => {'verified': true, 'plan': 'yearly'},
          fallbackPlan: 'monthly');
      expect(r.wroteExpiresAt, 'fallback-end-for-yearly');
      expect(r.wrotePlan, 'yearly');
    });

    test('an empty end_date string is treated as missing', () async {
      final r = _Recorder();
      await _run(r, callVerify: () async => {'verified': true, 'end_date': ''});
      expect(r.wroteExpiresAt, 'fallback-end-for-monthly');
      expect(r.wrotePlan, 'monthly');
    });
  });

  group('no verdict -> nothing is written, cleared or refreshed', () {
    test('verified:false (payment not captured yet)', () async {
      final r = _Recorder();
      expect(await _run(r, callVerify: () async => {'verified': false}), isFalse);
      expect(r.calls, isEmpty);
    });

    test('verified missing / not exactly true', () async {
      final r = _Recorder();
      expect(await _run(r, callVerify: () async => {'verified': 'true'}), isFalse);
      expect(await _run(r, callVerify: () async => <String, dynamic>{}), isFalse);
      expect(r.calls, isEmpty);
    });

    test('non-200 reply (callVerify returns null)', () async {
      final r = _Recorder();
      expect(await _run(r, callVerify: () async => null), isFalse);
      expect(r.calls, isEmpty);
    });

    test('callVerify throws -> rethrown, nothing written', () async {
      final r = _Recorder();
      await expectLater(
        _run(r, callVerify: () async => throw StateError('network down')),
        throwsA(isA<StateError>()),
      );
      expect(r.calls, isEmpty);
    });
  });

  group('session guard (H-20 class)', () {
    test('a verified reply that lands after an account switch writes NOTHING', () async {
      final r = _Recorder();
      final verified = await _run(r,
          callVerify: () async => {'verified': true, 'end_date': '2027-01-01T00:00:00.000Z'},
          sessionUnchanged: false);
      expect(verified, isFalse,
          reason: 'must not report success for a user who is no longer signed in');
      expect(r.calls, isEmpty);
    });
  });

  group('session guard BEFORE the call and failure ordering', () {
    test('an account switch BEFORE the attempt spends no verify call at all', () async {
      final r = _Recorder();
      var calls = 0;
      final verified = await _run(r,
          callVerify: () async {
            calls++;
            return {'verified': true};
          },
          sessionUnchanged: false);
      expect(verified, isFalse);
      expect(calls, 0, reason: 'a wrong-session timer must not spend the new user\'s verify-payment quota');
      expect(r.calls, isEmpty);
    });

    test('if writeState THROWS the grace is NOT cleared (it keeps protecting the user)', () async {
      final r = _Recorder();
      await expectLater(
        runVerificationRetryAttempt(
          callVerify: () async => {'verified': true, 'end_date': '2027-01-01T00:00:00.000Z'},
          sessionUnchanged: () => true,
          fallbackPlan: 'monthly',
          fallbackEndDate: (p) => 'x',
          writeState: ({required String expiresAt, required String plan}) async =>
              throw StateError('hive write failed'),
          clearGrace: () async => r.calls.add('clearGrace'),
          refresh: () async => r.calls.add('refresh'),
          clearLocalActivation: () async => r.calls.add('clearLocalActivation'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(r.calls, isEmpty, reason: 'clear-before-write would have closed the grace with no PRO write');
    });
  });

  group('scheduleVerificationRetries — the wiring guards', () {
    // A scheduler that records instead of waiting; tests fire the timers by hand.
    final timers = <(Duration, Future<void> Function())>[];
    setUp(timers.clear);

    late List<String> log;
    late int verifyCalls;
    late String? sessionUser;
    late String? inFlight;
    late List<String> verified;
    late List<String> notVerified;
    late List<Object> errors;
    late Future<Map<String, dynamic>?> Function() verifyImpl;

    void schedule({String userId = 'u1', String orderId = 'order-A'}) {
      log = [];
      verifyCalls = 0;
      verified = [];
      notVerified = [];
      errors = [];
      verifyImpl = () async => {'verified': true, 'end_date': '2027-01-01T00:00:00.000Z', 'plan': 'yearly'};
      scheduleVerificationRetries(
        delays: kVerificationRetryDelays,
        callVerify: () {
          verifyCalls++;
          return verifyImpl();
        },
        userId: userId,
        orderId: orderId,
        currentUserId: () => sessionUser,
        inFlightOrderId: () => inFlight,
        fallbackPlan: 'monthly',
        fallbackEndDate: (p) => 'fallback-$p',
        writeState: ({required String expiresAt, required String plan}) async => log.add('writeState'),
        clearPaymentInFlight: () async => log.add('clearPaymentInFlight'),
        refresh: () async => log.add('refresh'),
        clearLocalActivation: () async => log.add('clearLocalActivation'),
        onVerified: (d) => verified.add('${d.inSeconds}'),
        onNotVerified: (d) => notVerified.add('${d.inSeconds}'),
        onError: (d, e, st) => errors.add(e),
        scheduler: (d, run) => timers.add((d, run)),
      );
    }

    setUp(() {
      sessionUser = 'u1';
      inFlight = 'order-A';
    });

    test('schedules exactly kVerificationRetryDelays, in order', () {
      schedule();
      expect(timers.map((t) => t.$1).toList(), kVerificationRetryDelays);
    });

    test('happy path: the first timer runs the 4 side effects in order', () async {
      schedule();
      await timers[0].$2();
      expect(log, ['writeState', 'clearPaymentInFlight', 'refresh', 'clearLocalActivation']);
      expect(verified, ['60']);
    });

    test('an account switch: NO verify call, NO write, NO clear, on ANY timer', () async {
      schedule();
      sessionUser = 'someone-else';
      for (final t in timers) {
        await t.$2();
      }
      expect(verifyCalls, 0);
      expect(log, isEmpty);
      expect(verified, isEmpty);
    });

    test('a signed-out session (null user) is treated as changed', () async {
      schedule();
      sessionUser = null;
      await timers[0].$2();
      expect(verifyCalls, 0);
      expect(log, isEmpty);
    });

    test("a NEWER order's grace marker survives an older order's verified retry", () async {
      schedule(orderId: 'order-OLD');
      inFlight = 'order-NEW';
      await timers[0].$2();
      expect(log, contains('writeState'), reason: 'the old payment IS verified — PRO is written');
      expect(log, isNot(contains('clearPaymentInFlight')),
          reason: "must not end the newer order's grace window");
      expect(log, containsAllInOrder(['refresh', 'clearLocalActivation']));
    });

    test('no grace open (null) -> the grace clear is still issued (idempotent)', () async {
      schedule(orderId: 'order-A');
      inFlight = null;
      await timers[0].$2();
      expect(log, contains('clearPaymentInFlight'));
    });

    test("this order's OWN grace -> it IS cleared", () async {
      schedule(orderId: 'order-A');
      inFlight = 'order-A';
      await timers[0].$2();
      expect(log, contains('clearPaymentInFlight'));
    });

    test('after the FIRST verified attempt the later timers do nothing', () async {
      schedule();
      await timers[0].$2();
      final callsAfterFirst = verifyCalls;
      final logAfterFirst = List<String>.from(log);
      await timers[1].$2();
      await timers[2].$2();
      expect(verifyCalls, callsAfterFirst);
      expect(log, logAfterFirst);
      expect(verified, ['60']);
    });

    test('not verified does NOT latch: the next timer runs', () async {
      schedule();
      var n = 0;
      verifyImpl = () async => ++n == 1 ? {'verified': false} : {'verified': true};
      await timers[0].$2();
      expect(notVerified, ['60']);
      expect(log, isEmpty);
      await timers[1].$2();
      expect(verified, ['300']);
      expect(verifyCalls, 2);
    });

    test('an attempt that THROWS is reported and does not stop the next timer', () async {
      schedule();
      var n = 0;
      verifyImpl = () async {
        if (++n == 1) throw StateError('network down');
        return {'verified': true};
      };
      await timers[0].$2();
      expect(errors.single, isA<StateError>());
      await timers[1].$2();
      expect(verified, ['300']);
    });
  });

  group('bounded by kRetryAttemptTimeout', () {
    test('a wedged call fails with TimeoutException at the bound and writes nothing', () {
      fakeAsync((async) {
        final wedged = Completer<Map<String, dynamic>?>();
        final r = _Recorder();
        Object? thrown;
        _run(r, callVerify: () => wedged.future).catchError((Object e) {
          thrown = e;
          return false;
        });

        async.elapse(kRetryAttemptTimeout - const Duration(milliseconds: 1));
        expect(thrown, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(
            thrown,
            isA<TimeoutException>().having((e) => e.message, 'message',
                'verify-payment retry timed out after 60s'));
        expect(r.calls, isEmpty);

        // A LATE verified reply, after the timeout, must not be able to write:
        // the writes live outside the bounded unit and the future already failed.
        wedged.complete({'verified': true});
        async.flushMicrotasks();
        expect(r.calls, isEmpty);
      });
    });
  });
}
