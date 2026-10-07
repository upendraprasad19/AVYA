// BEHAVIORAL contract for test/helpers/pro_downgrade_waiter.dart
// (diagnose b3f8e5, OI-242; recurrence of a3e9b7 + f3c7d2).
//
// Two layers, because a loaded-runner flake cannot be reproduced on demand
// (a3e9b7 recorded an 8-core busy-loop repro as uninformative in BOTH arms):
//
// 1. REAL CHAIN. The race is made deterministic instead of waited for: a
//    backlog of 2000 UNAWAITED puts is queued on the user box immediately
//    before isPro(). Hive serialises writes per box and each write is its own
//    I/O round trip, so every write inside `_downgradeLocally` — and both of
//    its hooks — sit behind ≥2000 sequential I/O completions, which no fixed
//    ~20-turn drain can outlast. Measured 2026-09-26: the OLD wait
//    (`pumpEventQueue()`) RED 5/5, primary discriminator `fired`; the waiter
//    green 3/3. A single 16 MiB put — the plan-review probes' fixture — was
//    NOT deterministic here: the old wait passed with it, because Hive
//    serialises the frame synchronously and one large page-cache write
//    completes inside the drain. COUNT, not size, is the lever.
//
// 2. PRIMITIVE. The waiter's own contract — waits for the signal however late
//    it is, fails BY NAME, refuses nested arms and a replaced hook, drains in
//    its OWN teardown before the file's tearDown, restores idempotently.
//
// Two kinds of assertion in case 1, labelled, because citing the wrong kind
// as proof is a recorded failure mode in this repo (CLAUDE.md §4.9):
//   DISCRIMINATING — fail on the old wait: `fired`, and the three keys the
//     downgrade DELETES after its first await (`expiresAt`, `plan`,
//     `lastVerifiedAt`). `plan`/`lastVerifiedAt` are SEEDED, or their null
//     check would pass vacuously.
//   INVARIANT — true under the old wait too, so NOT evidence: `isPro == false`
//     and the lapsed marker, both of which Hive applies to its in-memory
//     keystore synchronously (`box_impl.dart:85`) before isPro() returns.
//
// Run: flutter test test/contracts/pro_downgrade_waiter_behavioral_test.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/pro_downgrade_waiter.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    // MigratedKey — which every entitlement read funnels through — needs the
    // migration box, and the auth-uid seam so a PRO fixture is not silently
    // read as free (same setup as realtime_pro_gate_behavioral_test.dart).
    if (!Hive.isBoxOpen(HiveService.migrationBoxName)) {
      await Hive.openBox(HiveService.migrationBoxName);
    }
    debugAuthUidResolverForTests = () => kTestUserId;
  });

  tearDown(() async {
    SubscriptionService.onDowngrade = null;
    debugAuthUidResolverForTests = null;
    await tearDownHiveForTests(tempDir);
  });

  /// An expired PRO row carrying every key `_downgradeLocally` clears. Key
  /// names mirror SubscriptionService's private constants
  /// (`subscription_service.dart:109-112`); a plausible-but-wrong name makes
  /// the fixture read as free and every assertion pass for the wrong reason.
  Future<void> seedExpiredPro() async {
    final box = HiveService.instance.userBox;
    await box.put('isPro', true);
    await box.put(
      'expiresAt',
      DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
    );
    await box.put('plan', 'yearly');
    await box.put('lastVerifiedAt', DateTime.now().toIso8601String());
  }

  group('b3f8e5 — REAL chain: the downgrade queued behind real I/O', () {
    test('wait() returns only after every downgrade write has landed', () async {
      await seedExpiredPro();
      expect(MigratedKey.read<dynamic>('plan'), 'yearly',
          reason: 'fixture guard: the seed must be visible through MigratedKey, '
              'or the null checks below are vacuous');

      // Queued FIRST, unawaited: every later write on this box waits behind
      // all 2000 of them (per-box FIFO), including the downgrade's own.
      final backlog = <Future<void>>[
        for (var i = 0; i < 2000; i++)
          HiveService.instance.userBox.put('b3f8e5_q$i', i),
      ];
      final big = Future.wait(backlog);

      final downgrade = ProDowngradeWaiter.arm();
      expect(SubscriptionService.instance.isPro(), isFalse,
          reason: 'expired row → not PRO (decision, synchronous)');
      await downgrade.wait();

      // DISCRIMINATING — each of these fails under the old pumpEventQueue().
      expect(downgrade.fired, isTrue, reason: 'onDowngrade fired');
      expect(MigratedKey.read<dynamic>('expiresAt'), isNull,
          reason: 'deleted after the first await in _downgradeLocally');
      expect(MigratedKey.read<dynamic>('plan'), isNull,
          reason: 'deleted after the first await in _downgradeLocally');
      expect(MigratedKey.read<dynamic>('lastVerifiedAt'), isNull,
          reason: 'deleted after the first await in _downgradeLocally');

      // INVARIANT — holds under the old wait too; asserted, not evidence.
      expect(MigratedKey.readWithDefault<bool>('isPro', true), isFalse);
      expect(MigratedKey.read<dynamic>('pro_lapsed_at'), isNotNull);

      await big;
    });
  });

  group('b3f8e5 — the primitive', () {
    test('waits for the signal however late it arrives, and runs the chained '
        'hook first', () async {
      var previousRan = false;
      SubscriptionService.onDowngrade = () => previousRan = true;
      final downgrade = ProDowngradeWaiter.arm();

      final sw = Stopwatch()..start();
      Timer(const Duration(milliseconds: 300),
          () => SubscriptionService.onDowngrade?.call());
      await downgrade.wait();
      sw.stop();

      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(290),
          reason: 'returned before the signal — a fixed-turn drain, not a wait');
      expect(previousRan, isTrue,
          reason: 'the waiter must CHAIN the existing hook, never replace it');
    });

    test('fails BY NAME when the downgrade never happens', () async {
      final downgrade =
          ProDowngradeWaiter.arm(teardownDrain: const Duration(milliseconds: 50));
      await expectLater(
        downgrade.wait(timeout: const Duration(milliseconds: 200)),
        throwsA(isA<TestFailure>().having((e) => e.message, 'message',
            contains('onDowngrade never fired'))),
      );
    });

    test('fails BY NAME when the hook is replaced after arm()', () async {
      final downgrade =
          ProDowngradeWaiter.arm(teardownDrain: const Duration(milliseconds: 50));
      SubscriptionService.onDowngrade = () {}; // a later plain assignment
      await expectLater(
        downgrade.wait(),
        throwsA(isA<TestFailure>()
            .having((e) => e.message, 'message', contains('REPLACED'))),
      );
    });

    test('refuses a nested arm()', () async {
      final first = ProDowngradeWaiter.arm();
      expect(ProDowngradeWaiter.arm, throwsA(isA<TestFailure>()));
      SubscriptionService.onDowngrade?.call();
      await first.wait();
    });

    test('a THROWING chained hook still reads as fired, not "never fired"',
        () async {
      // Production calls the hook inside try/catch (subscription_service.dart
      // :1212-1214), so the throw is swallowed there — the waiter must still
      // complete, or the failure would misreport itself as a missing hook.
      SubscriptionService.onDowngrade = () => throw StateError('chained boom');
      final downgrade = ProDowngradeWaiter.arm();
      try {
        SubscriptionService.onDowngrade?.call();
      } catch (_) {}
      await downgrade.wait(timeout: const Duration(seconds: 1));
      expect(downgrade.fired, isTrue);
    });

    test('restores the previous hook once the wait is over', () async {
      void previous() {}
      SubscriptionService.onDowngrade = previous;
      final downgrade = ProDowngradeWaiter.arm();
      SubscriptionService.onDowngrade?.call();
      await downgrade.wait();
      expect(identical(SubscriptionService.onDowngrade, previous), isTrue);
    });
  });

  group('b3f8e5 — the self-draining teardown runs BEFORE the file tearDown', () {
    // These two tests are ORDER-DEPENDENT on purpose: the first leaves a chain
    // running past the end of its body; this group's tearDown records what it
    // sees; the second asserts on that record. test_api runs teardowns
    // last-in-first-out, so the waiter's addTearDown (registered in the body)
    // runs before this group tearDown, which runs before the file tearDown
    // that closes Hive.
    ProDowngradeWaiter? unawaited;
    bool? firedWhenGroupTearDownRan;
    void Function()? hookWhenGroupTearDownRan;
    void laterHook() {}

    tearDown(() {
      final w = unawaited;
      if (w != null) {
        firedWhenGroupTearDownRan = w.fired;
        hookWhenGroupTearDownRan = SubscriptionService.onDowngrade;
        unawaited = null;
      }
    });

    test('arm, never wait; the chain fires 150 ms AFTER the body ends', () async {
      unawaited = ProDowngradeWaiter.arm();
      Timer(const Duration(milliseconds: 150),
          () => SubscriptionService.onDowngrade?.call());
    });

    test('…and the waiter drained it in its own teardown, first', () {
      expect(firedWhenGroupTearDownRan, isTrue,
          reason: 'the waiter\'s teardown must WAIT for an unawaited chain '
              'before the file tears Hive down — this is the whole fix for a '
              'test that arms without waiting');
      expect(hookWhenGroupTearDownRan, isNull,
          reason: 'and must restore the hook it replaced (null here)');
    });

    test('a hook installed after arm() is never clobbered by the restore',
        () async {
      unawaited = ProDowngradeWaiter.arm(
          teardownDrain: const Duration(milliseconds: 50));
      SubscriptionService.onDowngrade = laterHook;
    });

    test('…so the later hook is still installed after the waiter\'s teardown',
        () {
      expect(identical(hookWhenGroupTearDownRan, laterHook), isTrue,
          reason: 'restore must only undo its OWN installation');
    });
  });
}
