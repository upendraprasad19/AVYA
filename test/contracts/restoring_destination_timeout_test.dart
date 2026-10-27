// test/contracts/restoring_destination_timeout_test.dart
//
// Contract — closes-diagnose e5b2a9 (Unit A). The post-auth routing read must
// have a hard ceiling so a hung backend (521/504, 10-36s per request) cannot
// hold RestoringScreen before its local-evidence branch can run — WITHOUT
// discarding a late answer for a user who has no local data to fall back on.
//
// Behavioral (fakeAsync) for the static helpers + ExclusiveRun; comment-stripped
// source-grep for the wiring (presence only — the behavioral half is the helper
// tests). `restoring_screen.dart` is a LIBRARY (head + part files), so the wiring
// reads it through readRestoringScreenSource().

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/auth_session_bootstrapper.dart';

import '../helpers/read_screen_source.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

typedef _Dest = PostSignInDestination;

void main() {
  group('boundDestination', () {
    test('a read that never answers becomes DestinationUnknown(read_ceiling) at the limit',
        () {
      fakeAsync((async) {
        _Dest? got;
        AuthSessionBootstrapper.boundDestination(Completer<_Dest>().future)
            .then((v) => got = v);
        async.elapse(const Duration(seconds: 7));
        expect(got, isNull, reason: 'must still be waiting before the limit');
        async.elapse(const Duration(seconds: 2));
        expect(got, isA<DestinationUnknown>());
        expect((got! as DestinationUnknown).reason,
            AuthSessionBootstrapper.kDestinationTimeoutReason);
      });
    });

    test('a prompt GoHome passes through untouched', () {
      fakeAsync((async) {
        _Dest? got;
        AuthSessionBootstrapper.boundDestination(
                Future<_Dest>.value(const GoHome()))
            .then((v) => got = v);
        async.flushMicrotasks();
        expect(got, isA<GoHome>());
      });
    });

    test('MIRROR: an ANSWERED StartMissionBrief inside the limit is not rewritten',
        () {
      fakeAsync((async) {
        _Dest? got;
        AuthSessionBootstrapper.boundDestination(Future<_Dest>.delayed(
                const Duration(seconds: 7), () => const StartMissionBrief()))
            .then((v) => got = v);
        async.elapse(const Duration(seconds: 8));
        expect(got, isA<StartMissionBrief>(),
            reason: 'a real "new user" answer must never become unknown');
      });
    });

    test('a timeout is NEVER StartMissionBrief (the c2e9f4 invariant)', () {
      fakeAsync((async) {
        _Dest? got;
        AuthSessionBootstrapper.boundDestination(Completer<_Dest>().future)
            .then((v) => got = v);
        async.elapse(const Duration(seconds: 10));
        expect(got, isNotNull, reason: 'the ceiling must have fired');
        expect(got, isNot(isA<StartMissionBrief>()));
      });
    });

    test('custom limit is honoured; disabled never times out', () {
      fakeAsync((async) {
        _Dest? a;
        _Dest? b;
        AuthSessionBootstrapper.boundDestination(Completer<_Dest>().future,
                limit: const Duration(seconds: 2))
            .then((v) => a = v);
        AuthSessionBootstrapper.boundDestination(Completer<_Dest>().future,
                disabled: true)
            .then((v) => b = v);
        async.elapse(const Duration(minutes: 5));
        expect(a, isA<DestinationUnknown>());
        expect(b, isNull);
      });
    });

    test('constants: 8 s ceiling and the documented kill-switch key', () {
      expect(AuthSessionBootstrapper.kDestinationReadLimit,
          const Duration(seconds: 8));
      expect(AuthSessionBootstrapper.kDisableDestinationTimeoutKey,
          'disable_resolve_destination_timeout');
    });
  });

  group('resolveBounded (the policy RestoringScreen runs)', () {
    test('timeout + local evidence → unknown at 8s so the existing branch goes home',
        () {
      fakeAsync((async) {
        _Dest? got;
        AuthSessionBootstrapper.resolveBounded(Completer<_Dest>().future,
                hasLocalEvidence: () async => true)
            .then((v) => got = v);
        async.elapse(const Duration(seconds: 7));
        expect(got, isNull);
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(got, isA<DestinationUnknown>());
      });
    });

    test('timeout + NO local evidence → keeps waiting; the LATE answer is used, not discarded',
        () {
      fakeAsync((async) {
        final c = Completer<_Dest>();
        _Dest? got;
        AuthSessionBootstrapper.resolveBounded(c.future,
                hasLocalEvidence: () async => false)
            .then((v) => got = v);
        async.elapse(const Duration(seconds: 9));
        async.flushMicrotasks();
        expect(got, isNull, reason: 'nothing to fall back to: must keep waiting');
        async.elapse(const Duration(minutes: 2));
        expect(got, isNull);
        c.complete(const GoHome());
        async.flushMicrotasks();
        expect(got, isA<GoHome>(),
            reason: 'the original read answered late — its answer must route');
      });
    });

    test('an evidence check that THROWS counts as no evidence (keeps waiting)', () {
      fakeAsync((async) {
        final c = Completer<_Dest>();
        _Dest? got;
        AuthSessionBootstrapper.resolveBounded(c.future,
                hasLocalEvidence: () async => throw StateError('box closed'))
            .then((v) => got = v);
        async.elapse(const Duration(seconds: 9));
        async.flushMicrotasks();
        expect(got, isNull);
        c.complete(const GoHome());
        async.flushMicrotasks();
        expect(got, isA<GoHome>());
      });
    });

    test('a prompt answer never consults local evidence', () {
      fakeAsync((async) {
        var consulted = 0;
        _Dest? got;
        AuthSessionBootstrapper.resolveBounded(
                Future<_Dest>.value(const GoHome()),
                hasLocalEvidence: () async {
                  consulted++;
                  return true;
                })
            .then((v) => got = v);
        async.flushMicrotasks();
        expect(got, isA<GoHome>());
        expect(consulted, 0);
      });
    });

    test('MIRROR: a StartMissionBrief answered at 7s is returned as-is', () {
      fakeAsync((async) {
        _Dest? got;
        AuthSessionBootstrapper.resolveBounded(
                Future<_Dest>.delayed(
                    const Duration(seconds: 7), () => const StartMissionBrief()),
                hasLocalEvidence: () async => true)
            .then((v) => got = v);
        async.elapse(const Duration(seconds: 8));
        async.flushMicrotasks();
        expect(got, isA<StartMissionBrief>());
      });
    });

    test('disabled → the raw read is awaited and evidence is never consulted', () {
      fakeAsync((async) {
        var consulted = 0;
        final c = Completer<_Dest>();
        _Dest? got;
        AuthSessionBootstrapper.resolveBounded(c.future,
                disabled: true,
                hasLocalEvidence: () async {
                  consulted++;
                  return true;
                })
            .then((v) => got = v);
        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();
        expect(got, isNull);
        c.complete(const GoHome());
        async.flushMicrotasks();
        expect(got, isA<GoHome>());
        expect(consulted, 0);
      });
    });
  });

  group('ExclusiveRun (the CONTINUE-retry stacking guard)', () {
    test('a second call while one is running gets whenBusy and does NOT start', () {
      fakeAsync((async) {
        final r = ExclusiveRun();
        final gate = Completer<int>();
        var started = 0;
        int? first;
        int? second;
        r.run<int>(() {
          started++;
          return gate.future;
        }, whenBusy: -1).then((v) => first = v);
        r.run<int>(() {
          started++;
          return gate.future;
        }, whenBusy: -1).then((v) => second = v);
        async.flushMicrotasks();
        expect(started, 1);
        expect(second, -1);
        gate.complete(7);
        async.flushMicrotasks();
        expect(first, 7);
      });
    });

    test('MIRROR: once the first finishes, the next call runs', () async {
      final r = ExclusiveRun();
      expect(await r.run<int>(() async => 1, whenBusy: -1), 1);
      expect(await r.run<int>(() async => 2, whenBusy: -1), 2);
    });

    test('a start that THROWS still releases the slot', () async {
      final r = ExclusiveRun();
      await expectLater(
          r.run<int>(() async => throw StateError('x'), whenBusy: -1),
          throwsStateError);
      expect(await r.run<int>(() async => 5, whenBusy: -1), 5);
    });
  });

  group('wiring (presence — comment-stripped)', () {
    final screen = _strip(readRestoringScreenSource());
    final boot = _strip(
        File('lib/core/services/auth_session_bootstrapper.dart').readAsStringSync());

    test('no bare resolveDestination( call remains in the restoring screen', () {
      expect(RegExp(r'\.resolveDestination\(').hasMatch(screen), isFalse,
          reason: 'every routing read in the screen must be bounded');
    });

    test('_kickoffRestore routes through resolveDestinationBounded with the local-evidence check',
        () {
      expect(
          screen.contains(
              'resolveDestinationBounded(user.id, _hasLocalOnboardedEvidence)'),
          isTrue);
    });

    test('the CONTINUE retry routes through the guarded, bounded variant', () {
      expect(screen.contains('resolveDestinationBoundedOnce(userId)'), isTrue);
    });

    test('the bootstrapper wrappers apply the kill-switch and the guard', () {
      final i = boot.indexOf('resolveDestinationBounded(');
      expect(i, greaterThan(-1));
      final w = boot.substring(i, i + 500);
      expect(w.contains('resolveBounded('), isTrue);
      expect(w.contains('destinationTimeoutDisabled'), isTrue);
      // The CONTINUE retry is its OWN method — slice it on its own signature
      // (a fixed window from the first wrapper drifts every time a member is
      // added between the two).
      final j = boot.indexOf('resolveDestinationBoundedOnce(');
      expect(j, greaterThan(-1));
      final once = boot.substring(j, j + 400);
      expect(once.contains('_continueRetry.run<'), isTrue);
      expect(once.contains('destinationTimeoutDisabled'), isTrue);
    });
  });
}
