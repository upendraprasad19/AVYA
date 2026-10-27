// Phase 2 Unit C — BEHAVIORAL contract test for the one-time
// first-PRO instant-3 streak-freeze grant.
//
// Concept: streak_freeze_first_pro_grant (docs/sot_registry.yaml)
// Writer:  StreakProgressService.grantFirstProFreezes
//          StreakProgressService.resetToFreeCapOnLapse
//
// Each test seeds Hive state (userBox['progress']) to a known
// baseline, calls the service method under test, then asserts the
// exact post-condition. Tests are SELF-SUFFICIENT (no network, no
// Supabase) and use the same Hive setUp pattern as every other
// behavioral contract test in this directory.
//
// Four scenarios:
//   1. First PRO transition  → available becomes max(current,3), flag set.
//   2. Second activation     → flag already true, no re-grant,
//                              available unchanged.
//   3. Lapse (resetToFreeCapOnLapse) → available clamped to 1, flag
//                              PRESERVED; re-buy call after lapse →
//                              no re-grant (flag still true).
//   4. Reinstall-legacy-PRO  → flag=true (backfilled), boot
//                              writeSubscriptionState(isPro:true) path
//                              → grantFirstProFreezes is a no-op
//                              (verified by seeding flag=true and
//                              calling grantFirstProFreezes directly).
//
// Run: flutter test test/contracts/streak_freeze_first_pro_grant_behavioral_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';
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
        Directory.systemTemp.createTempSync('streak_first_pro_grant_');
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
    // Open a fresh user session for each test. Each test seeds its own
    // progress map via userBox.put to keep scenarios independent.
    await HiveUserSession.closeAll();
    const fakeUserId = 'deadbeef-aaaa-bbbb-cccc-111111111111';
    await HiveUserSession.openForUser(fakeUserId);
    await HiveService.instance.userBox.clear();
  });

  group('streak_freeze_first_pro_grant — behavioral contract', () {
    // ── Test 1 ──────────────────────────────────────────────────────
    test(
        'first PRO transition — grantFirstProFreezes bumps available '
        'to 3 and sets the flag to true', () {
      // Seed: fresh free user, 1 freeze available, flag absent.
      HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 1,
        'streak_freeze_used_dates': <String>[],
        // flag absent — simulates a brand-new user who just upgraded
      });

      StreakProgressService.instance.grantFirstProFreezes();

      final progress =
          HiveService.instance.userBox.get('progress') as Map;
      expect(
        progress['streak_freezes_available'],
        3,
        reason: 'First PRO upgrade must jump available to 3 (the PRO cap). '
            'Failure = grant did not fire or wrote the wrong value.',
      );
      expect(
        progress['streak_freezes_first_pro_grant_done'],
        true,
        reason: 'Flag must be set to true so subsequent calls are no-ops. '
            'Failure = idempotency not wired.',
      );
    });

    // ── Test 2 ──────────────────────────────────────────────────────
    test(
        'second activation (flag already true) — grantFirstProFreezes '
        'is a no-op, available unchanged', () {
      // Seed: PRO user mid-subscription, 2 freezes left, flag already set.
      HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 2,
        'streak_freeze_used_dates': <String>['2026-06-10'],
        'streak_freezes_first_pro_grant_done': true,
      });

      StreakProgressService.instance.grantFirstProFreezes();

      final progress =
          HiveService.instance.userBox.get('progress') as Map;
      expect(
        progress['streak_freezes_available'],
        2,
        reason: 'Flag is already true — grant must be a no-op. '
            'Available must stay at 2 (not jump to 3). '
            'Failure = boot-refresh phantom-grant not blocked.',
      );
      expect(
        progress['streak_freezes_first_pro_grant_done'],
        true,
        reason: 'Flag must remain true (idempotent write — does not '
            'toggle back to false).',
      );
    });

    // ── Test 3 ──────────────────────────────────────────────────────
    test(
        'lapse (resetToFreeCapOnLapse) clamps available to 1, '
        'preserves the grant-done flag; re-buy attempt after lapse '
        'does not re-grant', () {
      // Seed: PRO user who has 3 freezes and a set flag.
      HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 3,
        'streak_freeze_used_dates': <String>[],
        'streak_freezes_first_pro_grant_done': true,
      });

      // Simulate subscription lapse.
      StreakProgressService.instance.resetToFreeCapOnLapse();

      final afterLapse =
          HiveService.instance.userBox.get('progress') as Map;
      expect(
        afterLapse['streak_freezes_available'],
        1,
        reason: 'Lapse must clamp available to the free-tier cap (1). '
            'Failure = resetToFreeCapOnLapse did not reduce available.',
      );
      expect(
        afterLapse['streak_freezes_first_pro_grant_done'],
        true,
        reason: 'Lapse must NOT clear the grant-done flag. '
            'Clearing it would cause a phantom re-grant on re-purchase. '
            'Failure = flag was reset to false or deleted by lapse method.',
      );

      // Simulate re-purchase: grantFirstProFreezes must be a no-op
      // because the flag is still true.
      StreakProgressService.instance.grantFirstProFreezes();

      final afterRebuy =
          HiveService.instance.userBox.get('progress') as Map;
      expect(
        afterRebuy['streak_freezes_available'],
        1,
        reason: 'Re-purchase after lapse must NOT re-grant 3 freezes — '
            'the flag survived the lapse so grantFirstProFreezes is still '
            'a no-op. The weekly refill on the first PRO Monday is the '
            'correct restore path. Failure = phantom re-grant on re-buy.',
      );
    });

    // ── Test 4 ──────────────────────────────────────────────────────
    test(
        'reinstall-legacy-PRO: flag=true (backfilled by migration-095) '
        'in Hive — grantFirstProFreezes is a no-op on boot-refresh', () {
      // Seed: _restoreFreezes has already run (Step C of restore),
      // landing the cloud backfill-true flag into Hive. The user had
      // 3 freezes from before their reinstall.
      HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 3,
        'streak_freeze_used_dates': <String>[],
        'streak_freezes_first_pro_grant_done': true, // cloud backfill landed
      });

      // This is the call path from subscription_service.writeSubscriptionState
      // when oldIsPro==false && isPro==true (first boot after reinstall
      // with no local Hive key but cloud-backed state just restored).
      StreakProgressService.instance.grantFirstProFreezes();

      final progress =
          HiveService.instance.userBox.get('progress') as Map;
      expect(
        progress['streak_freezes_available'],
        3,
        reason: 'Legacy PRO reinstall: backfill flag already in Hive via '
            '_restoreFreezes (Step C). grantFirstProFreezes must be a '
            'no-op — available must stay 3, not phantom-jump again. '
            'Failure = migration-095 backfill protection not working '
            'because grantFirstProFreezes ignores the flag from Hive.',
      );
      expect(
        progress['streak_freezes_first_pro_grant_done'],
        true,
        reason: 'Flag must remain true after the no-op call.',
      );
    });

    // ── Test 5 (edge case) ──────────────────────────────────────────
    test(
        'resetToFreeCapOnLapse is a no-op when available is already '
        'at or below the free cap (1)', () {
      // Seed: user already on free cap — e.g. they used 2 of their 3
      // freezes before lapsing, so only 1 remains.
      HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 1,
        'streak_freeze_used_dates': <String>['2026-06-10', '2026-06-11'],
        'streak_freezes_first_pro_grant_done': true,
      });

      StreakProgressService.instance.resetToFreeCapOnLapse();

      final progress =
          HiveService.instance.userBox.get('progress') as Map;
      expect(
        progress['streak_freezes_available'],
        1,
        reason: 'Already at free cap — resetToFreeCapOnLapse must not '
            'reduce below 1 or corrupt the value.',
      );
      // Flag still untouched.
      expect(progress['streak_freezes_first_pro_grant_done'], true);
    });

    // ── Test 6 (edge case) ──────────────────────────────────────────
    test(
        'grantFirstProFreezes preserves available when user already '
        'has more than 3 freezes (should not reduce)', () {
      // Unlikely in prod (cap is 3), but guards against future
      // refactors that raise the PRO cap.
      HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 5, // hypothetically above 3
        'streak_freeze_used_dates': <String>[],
        // no flag — fresh first-time grant scenario with >3 available
      });

      StreakProgressService.instance.grantFirstProFreezes();

      final progress =
          HiveService.instance.userBox.get('progress') as Map;
      expect(
        progress['streak_freezes_available'],
        5,
        reason: 'grantFirstProFreezes uses max(current, 3) — must NOT '
            'reduce available below its current value. '
            'Failure = grant capped current>3 to exactly 3.',
      );
      expect(progress['streak_freezes_first_pro_grant_done'], true);
    });
  });
}
