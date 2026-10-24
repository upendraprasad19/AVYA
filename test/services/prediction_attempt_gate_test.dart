// Behavioural — PredictionAttemptGate and PredictionService.refreshEnabled
// (Hermes 2026-09-26, L1-F1 / L1-F3 / L29-F4, diagnose 125b81).
//
// The server's prediction cap is 3 ATTEMPTS per IST day, never refunded. The
// PRO 30-day auto-refresh fires on every rebuild of the prediction provider
// while the text is 30+ days old, and the PRO goal-change regenerate on every
// goal save, so with Gemini failing, automatic calls alone could spend all
// three units. The gate gives automatic callers one attempt a day between
// them and makes a concurrent request join the running one.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/prediction_service.dart';

class _Harness {
  String? lastAutomaticDay;
  String today = '2026-09-26';
  final writes = <String>[];
  late final gate = PredictionAttemptGate(
    readLastAutomaticDay: () => lastAutomaticDay,
    writeLastAutomaticDay: (day) async {
      writes.add(day);
      lastAutomaticDay = day;
    },
    today: () => today,
  );
}

void main() {
  group('PredictionAttemptGate', () {
    test('one automatic attempt per IST day; the second is skipped without a request', () async {
      final h = _Harness();
      var attempts = 0;
      Future<PredictionRefreshOutcome> attempt() async {
        attempts++;
        return PredictionRefreshOutcome.failed;
      }

      expect(await h.gate.run(attempt, automatic: true),
          PredictionRefreshOutcome.failed);
      expect(await h.gate.run(attempt, automatic: true),
          PredictionRefreshOutcome.skipped);
      expect(attempts, 1);
    });

    test('a new IST day allows one more automatic attempt', () async {
      final h = _Harness()..lastAutomaticDay = '2026-09-25';
      var attempts = 0;
      final outcome = await h.gate.run(() async {
        attempts++;
        return PredictionRefreshOutcome.success;
      }, automatic: true);
      expect(outcome, PredictionRefreshOutcome.success);
      expect(attempts, 1);
      expect(h.writes, ['2026-09-26']);
    });

    test('the day is recorded BEFORE the request runs', () async {
      final h = _Harness();
      String? recordedWhenAttemptRan;
      await h.gate.run(() async {
        recordedWhenAttemptRan = h.lastAutomaticDay;
        return PredictionRefreshOutcome.failed;
      }, automatic: true);
      expect(recordedWhenAttemptRan, '2026-09-26',
          reason: 'an app killed mid-call must still have spent its '
              'automatic attempt');
    });

    test('a manual tap is never skipped and never spends the automatic budget', () async {
      final h = _Harness()..lastAutomaticDay = '2026-09-26';
      var attempts = 0;
      Future<PredictionRefreshOutcome> attempt() async {
        attempts++;
        return PredictionRefreshOutcome.failed;
      }

      await h.gate.run(attempt, automatic: false);
      await h.gate.run(attempt, automatic: false);
      expect(attempts, 2);
      expect(h.writes, isEmpty);
    });

    test('a request made while one runs joins it instead of spending a second unit', () async {
      final h = _Harness();
      var attempts = 0;
      final serverReplies = Completer<void>();
      Future<PredictionRefreshOutcome> attempt() async {
        attempts++;
        await serverReplies.future;
        return PredictionRefreshOutcome.success;
      }

      final first = h.gate.run(attempt, automatic: false);
      final second = h.gate.run(attempt, automatic: false);
      final third = h.gate.run(attempt, automatic: true);
      await pumpEventQueue();
      expect(attempts, 1);
      serverReplies.complete();
      expect(await first, PredictionRefreshOutcome.success);
      expect(await second, PredictionRefreshOutcome.success);
      expect(await third, PredictionRefreshOutcome.success);
      expect(attempts, 1);
      expect(h.writes, isEmpty,
          reason: 'a call that joined a manual refresh made no automatic '
              'attempt of its own');
    });

    test('once the running request finishes, a new one runs', () async {
      final h = _Harness();
      var attempts = 0;
      Future<PredictionRefreshOutcome> attempt() async {
        attempts++;
        return PredictionRefreshOutcome.failed;
      }

      await h.gate.run(attempt, automatic: false);
      await h.gate.run(attempt, automatic: false);
      expect(attempts, 2);
    });

    test('a request that throws still frees the gate', () async {
      final h = _Harness();
      await expectLater(
          h.gate.run(() async => throw StateError('boom'), automatic: false),
          throwsStateError);
      var ran = false;
      await h.gate.run(() async {
        ran = true;
        return PredictionRefreshOutcome.success;
      }, automatic: false);
      expect(ran, isTrue);
    });

    // B-pass finding, 2026-09-26: without this, a new account's call joins
    // the OLD account's stale in-flight Future and is handed its outcome.
    test('clearInFlightForAccountChange makes the next call start fresh, '
        'not join the stale one', () async {
      final h = _Harness();
      final userAResolves = Completer<PredictionRefreshOutcome>();
      var attempts = 0;
      Future<PredictionRefreshOutcome> attempt() {
        attempts++;
        return attempts == 1
            ? userAResolves.future
            : Future.value(PredictionRefreshOutcome.success);
      }

      final userATap = h.gate.run(attempt, automatic: false);
      await pumpEventQueue();

      // Simulate the SingletonLifecycleRegistry account-switch callback.
      h.gate.clearInFlightForAccountChange();

      final userBTap = h.gate.run(attempt, automatic: false);
      expect(await userBTap, PredictionRefreshOutcome.success,
          reason: 'the new account must get its OWN attempt, not join the '
              'stale one');
      expect(attempts, 2, reason: 'clearing in-flight must start a new call');

      userAResolves.complete(PredictionRefreshOutcome.failed);
      expect(await userATap, PredictionRefreshOutcome.failed,
          reason: 'the old account\'s own original call still resolves to '
              'its own real outcome — clearing does not cancel it');
    });
  });

  group('PredictionService.safeToWriteForTest', () {
    // B-pass finding, 2026-09-26: MigratedKey.write resolves the CURRENT
    // userBox at write time, so a regenerate() started for one account
    // must refuse to write if a DIFFERENT account is signed in by the
    // time the network response arrives.
    test('same owner throughout — safe to write', () {
      expect(PredictionService.safeToWriteForTest('user-a', 'user-a'), isTrue);
    });

    test('owner changed mid-flight — NOT safe to write', () {
      expect(
          PredictionService.safeToWriteForTest('user-a', 'user-b'), isFalse);
    });

    test('signed out mid-flight (now null) — NOT safe to write', () {
      expect(PredictionService.safeToWriteForTest('user-a', null), isFalse);
    });

    test('no session throughout (both null) — safe (matches the pre-fix, '
        'pre-auth no-op case)', () {
      expect(PredictionService.safeToWriteForTest(null, null), isTrue);
    });
  });

  group('PredictionService.refreshEnabled', () {
    final now = DateTime(2026, 9, 26, 12);

    test('PRO + stale → enabled even inside the 30 days', () {
      expect(
          PredictionService.refreshEnabled(
              isPro: true,
              generatedAt: now.subtract(const Duration(days: 2)),
              isStale: true,
              now: now),
          isTrue,
          reason: 'the card tells a stale PRO user to refresh — the button '
              'must work');
    });

    test('PRO, not stale: monthly', () {
      expect(
          PredictionService.refreshEnabled(
              isPro: true,
              generatedAt: now.subtract(const Duration(days: 29)),
              isStale: false,
              now: now),
          isFalse);
      expect(
          PredictionService.refreshEnabled(
              isPro: true,
              generatedAt: now.subtract(const Duration(days: 30)),
              isStale: false,
              now: now),
          isTrue);
      expect(
          PredictionService.refreshEnabled(
              isPro: true, generatedAt: null, isStale: false, now: now),
          isFalse);
    });

    test('free users never get the PRO button, stale or not', () {
      expect(
          PredictionService.refreshEnabled(
              isPro: false,
              generatedAt: now.subtract(const Duration(days: 90)),
              isStale: true,
              now: now),
          isFalse);
    });
  });
}
