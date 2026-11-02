// freeze-refill-sync (T1): the streak chip providers follow a completed
// restore even when Home (the only screen that used to invalidate them) is not
// mounted. Class 9c8958 (a Hive write with no provider invalidation).
//
// Behavioral: a real ProviderContainer, real Hive, the real refill that
// `heal_after_restore.dart:52` runs, and the real tick bump that
// `DayRolloverObserver.reckonAndNotifyAfterRestore` ends with
// (`SyncService.bumpRestoreCompleted`). No screen is mounted, which is the
// Train-first-mount case.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/sync_stub_server.dart';
import '../sync/sync_domain_skip_harness.dart';

class _CountingStreak extends StreakNotifier {
  static int builds = 0;
  @override
  int build() {
    builds++;
    return super.build();
  }
}

void main() {
  final h = SyncHarness();

  setUp(() async {
    await h.setUp();
    h.server.clear();
    // The refill fires an unawaited freeze push: answer it so nothing hits the network.
    h.server.rpcResponders['update_streak_progress'] = (r) => const StubRpcReply(200, 1);
    h.server.getResponders['user_progress'] = (r) => <Map<String, dynamic>>[];
    // Fixed Monday, not today (a literal equal to the authoring day goes red).
    setTestClockTo(DateTime(2026, 11, 2, 10, 40));
    final cfg = HiveService.instance.configBox;
    await cfg.put('isPro', true);
    await cfg.put('expiresAt', '2027-09-01T00:00:00Z');
    await HiveService.instance.userBox.put('profile', {
      'id': kTestUserId,
      'onboarding_completed_at': '2026-09-01T00:00:00+05:30',
    });
    // The heal that calls the refill runs AFTER the restore settled its marker
    // (freeze-order-d1: the refill is deferred until then).
    SyncService.instance.debugSetRestoreSettledUserIdForTest(kTestUserId);
    // The state a restore leaves just before the Monday refill: 0 freezes,
    // last refill the previous Monday.
    await HiveService.instance.userBox.put('progress', {
      'streak_freezes_available': 0,
      'streak_freezes_last_refill': '2026-10-26',
      'streak_freeze_used_dates': <String>['2026-10-24', '2026-10-31'],
    });
  });

  tearDown(() async {
    SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
    resetTestClock();
    await h.tearDown();
  });

  int hiveFreezes() =>
      (HiveService.instance.userBox.get('progress') as Map)['streak_freezes_available'] as int;

  test('refill then restore tick: the freeze chip reads the refilled value with no screen mounted', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(streakFreezeProvider), 0, reason: 'built before the refill');

    StreakProgressService.instance.refillIfNewWeek(); // heal_after_restore.dart:52
    expect(hiveFreezes(), 1, reason: 'the refill wrote Hive');
    expect(container.read(streakFreezeProvider), 0,
        reason: 'no tick yet: a Notifier reads Hive once per build (the stale window)');

    SyncService.instance.bumpRestoreCompleted(); // the LAST step of the post-restore heal
    expect(container.read(streakFreezeProvider), 1,
        reason: 'the tick rebuilds the chip provider from Hive');
    // Let the refill's unawaited freeze push finish against the stub before teardown.
    await Future<void>.delayed(const Duration(milliseconds: 400));
  });

  test('the streak count provider is rebuilt by the same tick (counted through a subclass)', () async {
    final container = ProviderContainer(overrides: [
      streakProvider.overrideWith(_CountingStreak.new),
    ]);
    addTearDown(container.dispose);
    container.read(streakProvider);
    final builds0 = _CountingStreak.builds;
    SyncService.instance.bumpRestoreCompleted();
    container.read(streakProvider);
    expect(_CountingStreak.builds, builds0 + 1,
        reason: 'a completed restore rebuilds the streak count from Hive');
  });

  test('disposing the container removes the tick listener (the singleton does not accumulate them)', () async {
    final tick = SyncService.instance.restoreCompletedTick;
    // Every earlier container in this file was disposed: a leaked listener from
    // one of them (the mutant without removeListener) shows up right here.
    // ignore: invalid_use_of_protected_member
    expect(tick.hasListeners, isFalse, reason: 'no listener survives a disposed container');
    final container = ProviderContainer();
    container.read(streakFreezeProvider);
    // ignore: invalid_use_of_protected_member
    expect(tick.hasListeners, isTrue, reason: 'the bridge is listening while the container lives');
    container.dispose();
    // ignore: invalid_use_of_protected_member
    expect(tick.hasListeners, isFalse, reason: 'and stops when it is disposed');
    // A bump after dispose must not throw ("used after dispose").
    SyncService.instance.bumpRestoreCompleted();
  });
}
