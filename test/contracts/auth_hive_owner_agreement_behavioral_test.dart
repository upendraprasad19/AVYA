// Tech-debt audit 2026-05-20 finding T3.4 — BEHAVIORAL contract for the
// `auth_hive_owner_agreement` SoT registry concept.
//
// Concept: the two-layer cross-account guard pinned by APK Test #15.4
// / B1. Layer A is the `wrapUserScopedBox` ownership check (returns
// `GuardedBox.empty` on auth/Hive disagreement). Layer B is
// `HiveUserSession.currentOwnerListenable` — a ValueNotifier mirrored
// under `_sessionLock` from the 3 locked methods (`openForUser`,
// `closeAll`, `deleteAllFilesForCurrentUser`). The 56 user-scoped
// Riverpod providers watch this listenable so they auto-rebuild after
// the new user's openForUser completes.
//
// This test pins the LAYER B liveness invariant: every mutation of
// `_currentOwnerFullId` MUST also drive `currentOwnerListenable.value`
// to the same value. If they drift, Layer B fires stale rebuilds (or
// no rebuild at all) and providers cache the previous user's view of
// the world. That is the C-7 / C-15 class of provider cache race.
//
// Bug class prevented (cites
// `feedback_source_grep_false_confidence.md`): a source-grep that
// confirms `currentOwnerListenable.value = ...` appears in
// hive_user_session.dart passes even if a future refactor moves the
// assignment outside `_sessionLock`'s body OR forgets to update the
// listenable in one of the 3 locked methods. Only a behavioral
// open→close→reopen sequence that reads the listenable VALUE at each
// step catches the regression.
//
// Run: flutter test test/contracts/auth_hive_owner_agreement_behavioral_test.dart

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
        Directory.systemTemp.createTempSync('auth_hive_owner_');
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

  group('auth_hive_owner_agreement — Layer B liveness contract', () {
    test(
        'openForUser drives currentOwnerListenable.value to the new uid '
        '— and currentOwnerFullId agrees', () async {
      const userA = 'aaaa1111-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
      expect(HiveUserSession.currentOwnerListenable.value, isNull,
          reason: 'baseline — no session.');
      expect(HiveUserSession.currentOwnerFullId, isNull);

      await HiveUserSession.openForUser(userA);

      // Both static field AND listenable mirror MUST agree.
      expect(HiveUserSession.currentOwnerFullId, userA);
      expect(HiveUserSession.currentOwnerListenable.value, userA,
          reason: 'Layer B mirror MUST update inside openForUser '
              '(under _sessionLock). Drift here causes the 56 '
              'authUserIdTokenProvider watchers to either miss the '
              'rebuild or rebuild against the wrong uid.');
    });

    test(
        'closeAll drives currentOwnerListenable.value back to null in '
        'lock-step with currentOwnerFullId', () async {
      const userA = 'aaaa2222-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
      await HiveUserSession.openForUser(userA);
      expect(HiveUserSession.currentOwnerListenable.value, userA);

      await HiveUserSession.closeAll();

      expect(HiveUserSession.currentOwnerFullId, isNull);
      expect(HiveUserSession.currentOwnerListenable.value, isNull,
          reason: 'closeAll must clear the listenable so '
              'authUserIdTokenProvider resolves to "<anon>" and '
              'user-scoped providers swap to empty state, not '
              "keep serving userA's cached data.");
    });

    test(
        'deleteAllFilesForCurrentUser clears the listenable too — third '
        'locked method must mirror', () async {
      const userA = 'aaaa3333-cccc-cccc-cccc-cccccccccccc';
      await HiveUserSession.openForUser(userA);
      expect(HiveUserSession.currentOwnerListenable.value, userA);

      await HiveUserSession.deleteAllFilesForCurrentUser();

      expect(HiveUserSession.currentOwnerFullId, isNull);
      expect(HiveUserSession.currentOwnerListenable.value, isNull,
          reason: 'deleteAllFilesForCurrentUser is the third of the 3 '
              'locked methods and must mirror the listenable. A regression '
              'here only surfaces on account-delete flows, which is why '
              'a source-grep over openForUser/closeAll alone is '
              'insufficient.');
    });

    test(
        'live signOut+signUp sequence: A → closeAll → B drives the '
        'listenable through null then to userB', () async {
      const userA = 'aaaa4444-dddd-dddd-dddd-dddddddddddd';
      const userB = 'bbbb4444-eeee-eeee-eeee-eeeeeeeeeeee';

      // Track the listenable's progression so we can detect a missed
      // intermediate null state (Layer A relies on null to GuardedBox.empty).
      final progression = <String?>[
        HiveUserSession.currentOwnerListenable.value,
      ];
      void track() {
        progression.add(HiveUserSession.currentOwnerListenable.value);
      }

      HiveUserSession.currentOwnerListenable.addListener(track);

      try {
        await HiveUserSession.openForUser(userA);
        await HiveUserSession.closeAll();
        await HiveUserSession.openForUser(userB);
      } finally {
        HiveUserSession.currentOwnerListenable.removeListener(track);
      }

      // At minimum we must observe: null (start) → userA → null → userB.
      expect(progression.first, isNull);
      expect(progression.last, userB);
      expect(progression, contains(userA),
          reason: 'Layer B must surface userA owner before closeAll '
              'so providers can render userA data while authenticated.');
      // After closeAll there must be at least one null in the middle.
      final firstUserAIdx = progression.indexOf(userA);
      final firstUserBIdx = progression.indexOf(userB);
      expect(firstUserBIdx > firstUserAIdx, isTrue);
      final between =
          progression.sublist(firstUserAIdx + 1, firstUserBIdx);
      expect(between, contains(null),
          reason: 'Between userA and userB, the listenable MUST briefly '
              'go to null (closeAll → openForUser sequence). Without '
              'this null gap, authUserIdTokenProvider never enters its '
              '<anon> state and Layer A receives no "disagreement" '
              'signal during the transition window.');
    });

    test(
        'idempotent re-openForUser for the SAME uid does not flap the '
        'listenable through null', () async {
      const userA = 'aaaa5555-ffff-ffff-ffff-ffffffffffff';
      await HiveUserSession.openForUser(userA);

      final flaps = <String?>[];
      void track() {
        flaps.add(HiveUserSession.currentOwnerListenable.value);
      }

      HiveUserSession.currentOwnerListenable.addListener(track);
      try {
        // Same uid — should be a no-op (no listenable mutation).
        await HiveUserSession.openForUser(userA);
      } finally {
        HiveUserSession.currentOwnerListenable.removeListener(track);
      }

      expect(flaps, isEmpty,
          reason: 'openForUser(sameUid) is documented idempotent — must '
              'NOT toggle the listenable through null. Spurious flaps '
              'would force a full provider tree rebuild on every '
              'defensive _ensureSessionOpen call.');
      expect(HiveUserSession.currentOwnerFullId, userA);
      expect(HiveUserSession.currentOwnerListenable.value, userA);
    });
  });
}
