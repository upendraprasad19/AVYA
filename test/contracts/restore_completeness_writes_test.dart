import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// APK Test #11 — Theme A push-side contract.
///
/// Asserts that the three Hive-only surfaces that previously vanished on
/// reinstall now fan out to cloud via SyncService immediately after
/// every local mutation (CLAUDE.md §15 fire-and-forget pattern).
///
/// Migration 048 (applied as '047_restore_completeness' in prod) added:
///   • user_progress.streak_freezes_* columns (Theme A1)
///   • notifications_inbox table (Theme A4)
///   • saved_diet_plans table (Theme A5)
///
/// The READ / restore path (Task 7.3) will pull these rows back on
/// cross-device sign-in. This test only guards the WRITE path.
void main() {
  group('APK Test #11 · Theme A · restore-completeness write contract', () {
    test('SyncService exposes 3 new restore-completeness methods', () {
      final src =
          File('lib/core/services/sync_service.dart').readAsStringSync();
      expect(src.contains('Future<void> syncFreezes'), isTrue,
          reason: 'SyncService must expose syncFreezes() (Theme A1)');
      expect(src.contains('Future<void> syncNotificationsInboxEntry'), isTrue,
          reason:
              'SyncService must expose syncNotificationsInboxEntry() (Theme A4)');
      expect(src.contains('Future<void> syncSavedDietPlan'), isTrue,
          reason: 'SyncService must expose syncSavedDietPlan() (Theme A5)');
    });

    test('streak_freeze mutations fan out to syncFreezes (workout_repository)',
        () {
      // C-15 (audit-2026-05-11) — the `syncFreezes` call moved out of
      // `workout_repository` into `StreakProgressService.commitConsume`.
      // The contract is preserved: workout_repository routes through
      // the service, which fires syncFreezes. Accept either form.
      final repoSrc = File(
              'lib/features/train/repositories/workout_repository.dart')
          .readAsStringSync();
      final svcSrc =
          File('lib/core/services/streak_progress_service.dart')
              .readAsStringSync();
      final repoCallsService =
          repoSrc.contains('StreakProgressService.instance.commitConsume');
      final serviceFiresSync =
          svcSrc.contains('SyncService.instance.syncFreezes');
      expect(
        (repoCallsService && serviceFiresSync) ||
            repoSrc.contains('SyncService.instance.syncFreezes'),
        isTrue,
        reason: 'workout_repository must push freeze state to cloud after '
            'consuming a freeze (CLAUDE.md §15). Now routed through '
            'StreakProgressService.commitConsume which fires syncFreezes.',
      );
    });

    test(
        'streak_freeze weekly refill fans out to syncFreezes (home_provider)',
        () {
      // C-15 — same pattern: refill moved into
      // StreakProgressService.commitRefill which fires syncFreezes.
      final homeSrc =
          File('lib/features/home/providers/home_provider.dart')
              .readAsStringSync();
      final svcSrc =
          File('lib/core/services/streak_progress_service.dart')
              .readAsStringSync();
      final homeCallsService =
          homeSrc.contains('StreakProgressService.instance.commitRefill');
      final serviceFiresSync =
          svcSrc.contains('SyncService.instance.syncFreezes');
      expect(
        (homeCallsService && serviceFiresSync) ||
            homeSrc.contains('SyncService.instance.syncFreezes'),
        isTrue,
        reason: 'home_provider._refillIfNewWeek must push refilled freeze '
            'count to cloud (CLAUDE.md §15). Now routed through '
            'StreakProgressService.commitRefill which fires syncFreezes.',
      );
    });

    test(
        'notification_inbox_service.record fans out to '
        'syncNotificationsInboxEntry', () {
      final src = File(
              'lib/features/profile/services/notification_inbox_service.dart')
          .readAsStringSync();
      expect(
          src.contains('SyncService.instance.syncNotificationsInboxEntry'),
          isTrue,
          reason:
              'NotificationInboxService.record must push every inbox entry '
              'to cloud (CLAUDE.md §15). Without this the full inbox is '
              'lost on reinstall.');
    });

    test('diet_plan_screen._savePlan fans out to syncSavedDietPlan', () {
      final src =
          File('lib/features/nutrition/screens/diet_plan_screen.dart')
              .readAsStringSync();
      expect(src.contains('SyncService.instance.syncSavedDietPlan'), isTrue,
          reason:
              'DietPlanScreen._savePlan must push the saved plan to cloud '
              '(CLAUDE.md §15). Without this the plan is lost on reinstall.');
    });

    test('all sync callsites use unawaited() (never block UI)', () {
      // C-15 (audit-2026-05-11) — syncFreezes moved into
      // StreakProgressService; workout_repository + home_provider now
      // call commitConsume / commitRefill instead. The service file
      // itself wraps SyncService.syncFreezes in unawaited().
      final files = {
        'lib/core/services/streak_progress_service.dart': 'syncFreezes',
        'lib/features/profile/services/notification_inbox_service.dart':
            'syncNotificationsInboxEntry',
        'lib/features/nutrition/screens/diet_plan_screen.dart':
            'syncSavedDietPlan',
      };
      for (final entry in files.entries) {
        final src = File(entry.key).readAsStringSync();
        // Confirm the call appears inside an unawaited(...) wrapper.
        // We look for the pattern: unawaited(SyncService.instance.<method>
        expect(
            src.contains('unawaited(SyncService.instance.${entry.value}'),
            isTrue,
            reason:
                '${entry.key} must wrap ${entry.value}() in unawaited() '
                'per CLAUDE.md §15 fire-and-forget. Awaiting would block '
                'the UI / provider build.');
      }
    });

    test('syncFreezes reads from userBox progress key (not raw Hive.box)', () {
      final src =
          File('lib/core/services/sync_service.dart').readAsStringSync();
      // Confirm it uses HiveService.instance or _hive accessor — not raw Hive.box
      expect(src.contains('Hive.box('), isFalse,
          reason:
              'SyncService must use _hive.<box> accessors, not raw Hive.box().'
              ' Raw Hive.box() throws HiveError on cold-start paths.');
      expect(src.contains('_hive.userBox'), isTrue,
          reason: 'syncFreezes must read from _hive.userBox (progress key)');
    });
  });
}
