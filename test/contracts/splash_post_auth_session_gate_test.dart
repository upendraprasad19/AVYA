// C-7 (audit-2026-05-11) — regression test that splash-time post-auth
// fire-and-forget startup work bootstraps `HiveUserSession` before
// reading user-scoped Hive boxes. Pre-fix, `RankService.evaluateAndPromote`,
// `SubscriptionService.refreshFromSupabase`,
// `ScheduledWorkoutsResyncMigrator.runIfNeeded`, and the splash-local
// `_autoGenerateNextPhaseForPro` all raced ahead of `_ensureLocalUser`
// and silently no-opped on cold start.
//
// Source-grep style — pins the contract without booting the app.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  group('C-7 splash post-auth bootstrap gate', () {
    test(
      'shared helper `HiveUserSession.ensureOpenedForCurrentSession` exists',
      () {
        final src = _src('lib/core/services/hive_user_session.dart');
        expect(
          src,
          contains(
              'static Future<String?> ensureOpenedForCurrentSession()'),
          reason:
              'C-7 requires one shared static so every fire-and-forget '
              'caller routes through the same idempotent session-open '
              'helper. Splitting this back into private per-service '
              'helpers re-opens the original race.',
        );
      },
    );

    test(
      'RankService.evaluateAndPromote awaits the shared session helper',
      () {
        final src = _src('lib/core/services/rank_service.dart');
        final mIdx = src.indexOf('Future<void> evaluateAndPromote()');
        expect(mIdx, greaterThan(0));
        final mEnd = src.indexOf('\n  Future<', mIdx + 10);
        final body = src.substring(
            mIdx, mEnd > mIdx ? mEnd : (mIdx + 6000).clamp(0, src.length));
        expect(
          body.contains('HiveUserSession.ensureOpenedForCurrentSession'),
          isTrue,
          reason:
              'evaluateAndPromote runs fire-and-forget from splash; '
              'without the shared helper it reads user-scoped boxes '
              'before _ensureLocalUser opens the session and silently '
              'misses every promotion.',
        );
      },
    );

    test(
      'SubscriptionService.refreshFromSupabase awaits the shared session helper',
      () {
        final src = _src('lib/core/services/subscription_service.dart');
        final mIdx = src.indexOf('Future<void> refreshFromSupabase()');
        expect(mIdx, greaterThan(0));
        final mEnd = src.indexOf('\n  Future<', mIdx + 10);
        final body = src.substring(
            mIdx, mEnd > mIdx ? mEnd : (mIdx + 6000).clamp(0, src.length));
        expect(
          body.contains('HiveUserSession.ensureOpenedForCurrentSession'),
          isTrue,
          reason:
              'refreshFromSupabase fires from splash; without the '
              'shared helper the upgrade pill stays grey on cold '
              'start after a fresh payment.',
        );
      },
    );

    test(
      'ScheduledWorkoutsResyncMigrator.runIfNeeded awaits the shared helper',
      () {
        final src = _src(
            'lib/core/services/scheduled_workouts_resync_migrator.dart');
        final mIdx = src.indexOf('static Future<void> runIfNeeded()');
        expect(mIdx, greaterThan(0));
        final mEnd = src.indexOf('\n  static Future<', mIdx + 10);
        final body = src.substring(
            mIdx, mEnd > mIdx ? mEnd : (mIdx + 6000).clamp(0, src.length));
        expect(
          body.contains('HiveUserSession.ensureOpenedForCurrentSession'),
          isTrue,
          reason:
              'runIfNeeded fires from splash before _ensureLocalUser; '
              'without the shared helper `userBox.get`/`workoutBox.keys` '
              'throw HiveUserSession not opened, the catch swallows it, '
              'and the one-shot migration is silently skipped forever.',
        );
      },
    );

    test(
      'splash_screen._autoGenerateNextPhaseForPro awaits the shared helper',
      () {
        final src =
            _src('lib/features/auth/screens/splash_screen.dart');
        final mIdx =
            src.indexOf('Future<void> _autoGenerateNextPhaseForPro()');
        expect(mIdx, greaterThan(0));
        final mEnd = src.indexOf('\n  Future<', mIdx + 10);
        final body = src.substring(
            mIdx, mEnd > mIdx ? mEnd : (mIdx + 6000).clamp(0, src.length));
        expect(
          body.contains('HiveUserSession.ensureOpenedForCurrentSession'),
          isTrue,
          reason:
              '_autoGenerateNextPhaseForPro reads user-scoped Hive '
              'via UserRepository; without the shared helper PRO '
              'users on cold start with expired Phase silently miss '
              'auto-generation of the next phase.',
        );
      },
    );

    test(
      'splash_screen.dart no longer carries the legacy no-op try/catch '
      'around userBox.get("profile")',
      () {
        final src = _src('lib/features/auth/screens/splash_screen.dart');
        // The pre-fix block read `HiveService.instance.userBox.get("profile")`
        // directly during _runDeferredInit — at that point GuardedBox
        // throws because no `openForUser` has run yet, and the try/catch
        // swallowed it. C-6 lifted the guard into `openForUser`; the
        // splash block must be gone.
        expect(
          src.contains(
              "HiveService.instance.userBox.get('profile')"),
          isFalse,
          reason:
              'C-6: the splash-time cross-account guard was a no-op; '
              'the check now lives inside HiveUserSession.openForUser. '
              'Re-introducing the splash read brings back the silent-fail.',
        );
      },
    );
  });
}
