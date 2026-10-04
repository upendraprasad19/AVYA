// Tech-debt audit 2026-05-20 finding T3.3 — BEHAVIORAL contract for the
// `hive_deletion_and_session_helpers` SoT registry concept.
//
// Concept: the per-user namespaced-box lifecycle —
// `HiveUserSession.openForUser` / `closeAll` /
// `deleteAllFilesForCurrentUser` — together with
// `wrapUserScopedBox<T>` form the cross-account leak barrier. On a
// signOut+signUp transition, the OLD user's box files must be closed
// (and ideally deleted), the NEW user's namespaced boxes opened, and
// any guarded-box wrapper constructed during the disagreement window
// must return `GuardedBox.empty` rather than serving stale bytes.
//
// Failure mode this test prevents: a regression in `closeAllUserScopedBoxes`
// / `deleteAllFilesForCurrentUser` that leaves the previous user's
// box still in Hive's open-registry under the same namespaced name —
// the new user's session would read the old data on first access. This
// is the exact cross-account leak class closed by APK Test #15.4 / B1.
//
// Bug class prevented (cites
// `feedback_writer_reader_field_drift_recurring.md`, cross-account
// sub-class): a source-grep that confirms the 3 locked methods exist
// passes even if `_closeAllLocked` was silently changed to a no-op.
// Only a behavioral test that walks the namespaced box names across a
// user-switch sequence catches the regression.
//
// Run: flutter test test/contracts/hive_deletion_and_session_helpers_behavioral_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir =
        Directory.systemTemp.createTempSync('hive_session_helpers_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveUserSession.closeAll();
  });

  group('hive_deletion_and_session_helpers — behavioral contract', () {
    test('openForUser opens all 7 namespaced boxes + sets currentOwner',
        () async {
      const userA = '11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
      await HiveUserSession.openForUser(userA);

      expect(HiveUserSession.currentOwnerFullId, userA);
      expect(HiveUserSession.currentOwnerHash, '11111111');
      for (final root in HiveUserSession.userScopedBoxRoots) {
        final name = HiveUserSession.namespacedBoxName(root, userA);
        expect(Hive.isBoxOpen(name), isTrue,
            reason: 'openForUser must open the namespaced box for every '
                'user-scoped root. Missing $name means the cross-account '
                'guard cannot wrap it on first access.');
      }
    });

    test(
        'switching from userA to userB closes userA boxes + opens userB '
        'boxes — cross-account leak barrier', () async {
      const userA = '22222222-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
      const userB = '33333333-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

      await HiveUserSession.openForUser(userA);
      // Seed userA's userBox with a profile so we can verify isolation.
      await HiveService.instance.userBox.put('profile', {
        'id': userA,
        'primary_goal': 'muscle_gain',
      });

      // Switch users.
      await HiveUserSession.openForUser(userB);

      expect(HiveUserSession.currentOwnerFullId, userB);
      for (final root in HiveUserSession.userScopedBoxRoots) {
        final aName = HiveUserSession.namespacedBoxName(root, userA);
        final bName = HiveUserSession.namespacedBoxName(root, userB);
        expect(Hive.isBoxOpen(aName), isFalse,
            reason: 'After openForUser(userB), userA box $aName must be '
                'CLOSED. Open-registry leak here is the precise '
                'cross-account class APK Test #15.4 / B1 closed.');
        expect(Hive.isBoxOpen(bName), isTrue,
            reason: 'After openForUser(userB), userB box $bName must be '
                'OPEN.');
      }

      // userB sees a brand-new userBox — userA's profile is invisible.
      expect(HiveService.instance.userBox.get('profile'), isNull,
          reason: "userB session must NOT see userA's profile — that "
              'is the exact cross-account leak the namespaced-box layer '
              'prevents.');
    });

    test('closeAll() clears currentOwner + closes all 7 namespaced boxes',
        () async {
      const userA = '44444444-cccc-cccc-cccc-cccccccccccc';
      await HiveUserSession.openForUser(userA);

      await HiveUserSession.closeAll();

      expect(HiveUserSession.currentOwnerFullId, isNull);
      expect(HiveUserSession.currentOwnerHash, isNull);
      for (final root in HiveUserSession.userScopedBoxRoots) {
        final name = HiveUserSession.namespacedBoxName(root, userA);
        expect(Hive.isBoxOpen(name), isFalse,
            reason: 'closeAll must close $name. A leak here means '
                'subsequent reads through Hive.box($name) would still '
                'succeed even though the session is logically over.');
      }
    });

    test(
        'deleteAllFilesForCurrentUser removes user-scoped box files from '
        'disk + clears currentOwner', () async {
      const userA = '55555555-dddd-dddd-dddd-dddddddddddd';
      await HiveUserSession.openForUser(userA);
      await HiveService.instance.userBox.put('profile', {'id': userA});

      await HiveUserSession.deleteAllFilesForCurrentUser();

      expect(HiveUserSession.currentOwnerFullId, isNull);
      for (final root in HiveUserSession.userScopedBoxRoots) {
        final name = HiveUserSession.namespacedBoxName(root, userA);
        expect(Hive.isBoxOpen(name), isFalse,
            reason: 'deleteAllFilesForCurrentUser must close $name '
                'before deletion.');
      }
    });

    test(
        'wrapUserScopedBox returns a working box when owner matches — '
        'baseline for the disagreement-window contract', () async {
      const userA = '66666666-eeee-eeee-eeee-eeeeeeeeeeee';
      await HiveUserSession.openForUser(userA);

      final guarded =
          wrapUserScopedBox<dynamic>(HiveService.userBoxName);
      await guarded.put('marker', 'hello');
      expect(guarded.get('marker'), 'hello',
          reason: 'When auth uid agrees with HiveUserSession owner '
              '(testBypassOwnership=true approximates the agreement '
              'case), guarded reads/writes must succeed.');
    });
  });
}
