import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// APK Test #15 / Cross-account isolation contract pins.
///
/// Replaces the original 3 stubs that referenced
/// `HiveService.lastAuthenticatedUserIdKey` — a constant from an abandoned
/// design (the early Plan A namespacing prototype). The current
/// cross-account isolation surface is:
///
///   1. `HiveUserSession.openForUser(userId)` opens 7 user-scoped boxes.
///   2. `HiveUserSession.closeAll()` closes them on sign-out.
///   3. `GuardedBox<T>` wraps every user-scoped box and throws if a read
///      / write fires after closeAll, or under a different userId than
///      the one that called openForUser.
///   4. `UserRepository.clearAllData()` wipes user-scoped + shared
///      mutable boxes; preserves seeded reference boxes (exerciseBox,
///      foodBox) and one-shot device-lifetime flags (migrationBox).
///
/// These source-grep contracts prevent silent regression of the cross-
/// account leak that bit founders pre-Test-#11.1 (a previous user's
/// templates / coach memory / streaks survived to a fresh sign-up on
/// the same device when Auto Backup or in-memory state crossed the
/// session boundary).
///
/// closes-diagnose: 2026-05-10-cross-account-tests-unskip
void main() {
  late String hiveServiceSrc;
  late String hiveUserSessionSrc;
  late String guardedBoxSrc;
  late String userRepositorySrc;

  setUpAll(() {
    final hs = File('lib/core/services/hive_service.dart');
    expect(hs.existsSync(), isTrue, reason: 'hive_service.dart must exist');
    hiveServiceSrc = hs.readAsStringSync();

    final hus = File('lib/core/services/hive_user_session.dart');
    expect(hus.existsSync(), isTrue,
        reason: 'hive_user_session.dart must exist (cross-account isolation surface)');
    hiveUserSessionSrc = hus.readAsStringSync();

    final gb = File('lib/core/services/guarded_box.dart');
    expect(gb.existsSync(), isTrue,
        reason: 'guarded_box.dart must exist (per-user box wrapper)');
    guardedBoxSrc = gb.readAsStringSync();

    final ur = File('lib/shared/repositories/user_repository.dart');
    expect(ur.existsSync(), isTrue,
        reason: 'user_repository.dart must exist (clearAllData lives here)');
    userRepositorySrc = ur.readAsStringSync();
  });

  group('cross-account isolation surface — current API', () {
    test('HiveUserSession.openForUser exists', () {
      expect(
        hiveUserSessionSrc
            .contains('static Future<void> openForUser(String userId)'),
        isTrue,
        reason:
            'HiveUserSession.openForUser is the entry point that opens '
            'the 7 user-scoped boxes. Without it, GuardedBox reads throw '
            'and the app cannot read user state.',
      );
    });

    test('HiveUserSession.closeAll exists', () {
      expect(
        hiveUserSessionSrc.contains('static Future<void> closeAll()'),
        isTrue,
        reason:
            'HiveUserSession.closeAll is invoked on sign-out / cross-'
            'account guard. Required for the GuardedBox session check '
            'to flip to "no current owner."',
      );
    });

    test('GuardedBox class exists with cross-user check', () {
      expect(
        guardedBoxSrc.contains('class GuardedBox<T>'),
        isTrue,
        reason:
            'GuardedBox<T> is the wrapper that prevents cross-account '
            'data leakage. It throws when accessed by a userId that '
            'does not match the openForUser owner.',
      );
      expect(
        guardedBoxSrc.contains('Call HiveUserSession.openForUser(userId)'),
        isTrue,
        reason:
            'GuardedBox throws an actionable error message when accessed '
            'before openForUser ran. The literal string is part of the '
            'error contract — telemetry greps on it.',
      );
    });
  });

  group('UserRepository.clearAllData — wipes mutable, preserves seeds', () {
    test('clearAllData clears user-scoped boxes', () {
      // Each user-scoped box must appear inside the clearAllData method.
      // Pin the explicit list so a missing entry surfaces as a test fail.
      const userScopedBoxes = [
        '_hive.userBox.clear()',
        '_hive.workoutBox.clear()',
        '_hive.nutritionBox.clear()',
        '_hive.healthBox.clear()',
        '_hive.coachBox.clear()',
        '_hive.customBox.clear()',
        '_hive.notificationsBox.clear()',
      ];
      for (final box in userScopedBoxes) {
        expect(userRepositorySrc.contains(box), isTrue,
            reason: 'clearAllData must clear $box (user-scoped)');
      }
    });

    test('clearAllData clears shared mutable boxes (syncBox, configBox)', () {
      // syncBox + configBox are "shared mutable" — they hold state that
      // must NOT cross sessions even though they are not user-scoped via
      // GuardedBox. Pre-Test-#10.1 forgetting to clear them was the
      // founder's PRO-pill cross-account leak class.
      expect(userRepositorySrc.contains('_hive.syncBox.clear()'), isTrue,
          reason: 'clearAllData must clear syncBox to drop cross-session state');
      expect(userRepositorySrc.contains('_hive.configBox.clear()'), isTrue,
          reason: 'clearAllData must clear configBox until '
              'UserConfigMigrator fully completes the move to userBox');
    });

    test('clearAllData does NOT clear seeded reference boxes', () {
      // exerciseBox + foodBox are seeded read-only reference data. They
      // contain ~1431 foods + ~250 exercises. Clearing them on every
      // sign-out would force a re-seed on next launch (slow, lossy).
      expect(userRepositorySrc.contains('_hive.exerciseBox.clear()'), isFalse,
          reason: 'forbidden — exerciseBox is seed data, must survive sign-out');
      expect(userRepositorySrc.contains('_hive.foodBox.clear()'), isFalse,
          reason: 'forbidden — foodBox is seed data, must survive sign-out');
    });

    test('clearAllData does NOT clear migrationBox', () {
      // migrationBox holds one-shot device-lifetime flags
      // (e.g., 'config_to_user_migration_v2_done', 'apk_test_14_completion_resync_done').
      // If wiped on sign-out, migrations re-run and re-leak data —
      // exactly the pre-Test-#11.1 class of bug.
      expect(userRepositorySrc.contains('_hive.migrationBox.clear()'), isFalse,
          reason:
              'forbidden — migrationBox holds device-lifetime flags that '
              'MUST survive sign-out. Clearing causes migrations to '
              're-run and re-leak data. See feedback_main_is_source_of_truth.md.');
    });
  });

  group('HiveService box-name registry', () {
    test('user-scoped box list excludes seed boxes', () {
      // The static `_userScopedBoxNames` list in HiveService is what
      // openForUser iterates over. It must NOT contain exerciseBoxName /
      // foodBoxName (those are seeds opened lazily without per-user
      // namespacing).
      final userScopedBlock = _extractUserScopedListBlock(hiveServiceSrc);
      expect(userScopedBlock.contains('exerciseBoxName'), isFalse,
          reason:
              '_userScopedBoxNames must NOT include exerciseBoxName — '
              'exercise library is seed data, opened once at startup.');
      expect(userScopedBlock.contains('foodBoxName'), isFalse,
          reason:
              '_userScopedBoxNames must NOT include foodBoxName — '
              'food database is seed data, opened once at startup.');
    });

    test('user-scoped list contains the 7 mutable per-user boxes', () {
      final userScopedBlock = _extractUserScopedListBlock(hiveServiceSrc);
      const expected = [
        'userBoxName',
        'workoutBoxName',
        'nutritionBoxName',
        'healthBoxName',
        'coachBoxName',
        'customBoxName',
        'notificationsBoxName',
      ];
      for (final boxName in expected) {
        expect(userScopedBlock.contains(boxName), isTrue,
            reason:
                '_userScopedBoxNames must include $boxName so HiveUserSession '
                '.openForUser opens it under the per-user namespace.');
      }
    });
  });
}

/// Extracts the body of `_userScopedBoxNames` so source-grep tests scope
/// to that list and don't false-positive on commentary elsewhere in the
/// file.
String _extractUserScopedListBlock(String src) {
  const marker = '_userScopedBoxNames';
  final start = src.indexOf(marker);
  if (start < 0) {
    fail('Could not locate _userScopedBoxNames in hive_service.dart. '
        'Did it get renamed? Update this test.');
  }
  // The list spans roughly 12-15 lines following the declaration.
  final end = (start + 800).clamp(0, src.length);
  return src.substring(start, end);
}
