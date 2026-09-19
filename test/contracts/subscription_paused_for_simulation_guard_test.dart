// Regression test for diagnose `c7e1a4` — the dev year-sim's PRO grant was
// silently wiped mid-run, gating off phase generation (stuck-at-Phase-1 →
// rank never climbed past LS).
//
// Root cause: `SubscriptionService.pausedForSimulation` was checked only at
// the TOP of `refreshFromSupabase`. But a refresh kicked off during the
// ~100s boot-restore (when the flag was still false) stays IN FLIGHT, then
// resolves AFTER the sim sets the flag + grants PRO — and its `no-active-row`
// branch calls `_downgradeLocally()`, wiping the dev grant. An entry-guard
// cannot catch an already-in-flight call.
//
// Fix: guard the shared SINK — `_downgradeLocally()` itself — so EVERY
// downgrade path (refreshFromSupabase, verifyFromServer, AND the in-line
// expiry / cross-account checks inside isPro()) becomes a no-op while a sim
// is paused. `pausedForSimulation` is debug-only and always false in
// release/normal flow, so production downgrade behaviour is unchanged.
//
// This test drives the downgrade via the isPro() EXPIRY path (deterministic,
// no network mock needed). The guard sits at the common sink, so proving it
// preserves state on the expiry path proves it for every caller.
//
// Fails WITHOUT the fix: CASE B's isPro() expiry branch calls
// _downgradeLocally(), which wipes `isPro`/`expiresAt` → assertions fail.
// Passes WITH the fix: the guard no-ops the wipe → state preserved.
//
// Run: flutter test test/contracts/subscription_paused_for_simulation_guard_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
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
    tempDir = Directory.systemTemp.createTempSync('sub_paused_guard_');
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
    SubscriptionService.pausedForSimulation = false;
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    SubscriptionService.pausedForSimulation = false;
    await HiveUserSession.closeAll();
    const fakeUserId = 'cafeface-aaaa-bbbb-cccc-dddddddddddd';
    await HiveUserSession.openForUser(fakeUserId);
    await HiveService.instance.userBox.clear();
  });

  // Seed an "expired PRO" state: would normally be downgraded by isPro().
  Future<void> seedExpiredPro() async {
    final past =
        DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
    await MigratedKey.write('isPro', true);
    await MigratedKey.write('expiresAt', past);
    await MigratedKey.write('plan', 'yearly');
  }

  group('pausedForSimulation guard on _downgradeLocally (diagnose c7e1a4)', () {
    test(
        'CASE A (NOT paused): expired PRO → isPro() downgrades — proves the '
        'downgrade path is live', () async {
      SubscriptionService.pausedForSimulation = false;
      await seedExpiredPro();

      final result = SubscriptionService.instance.isPro();
      // _downgradeLocally fires asynchronously inside isPro(); let it settle.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(result, isFalse,
          reason: 'expired PRO must report not-PRO');
      expect(MigratedKey.readWithDefault<bool>('isPro', false), isFalse,
          reason: 'normal downgrade clears the isPro flag');
      expect(MigratedKey.read<dynamic>('expiresAt'), isNull,
          reason: 'normal downgrade deletes expiresAt');
    });

    test(
        'CASE B (paused): expired PRO → _downgradeLocally is a no-op — the '
        'dev-granted state is PRESERVED (the fix)', () async {
      SubscriptionService.pausedForSimulation = true;
      await seedExpiredPro();

      // isPro() still returns false for THIS call (state is expired), but the
      // guard must prevent the wipe so the persistent grant survives for the
      // rest of the sim (where the grant's real expiry is far in the future).
      SubscriptionService.instance.isPro();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(MigratedKey.readWithDefault<bool>('isPro', false), isTrue,
          reason: 'PAUSED: _downgradeLocally must NOT clear the isPro flag — '
              'this is the regression that wiped the dev grant mid-sim');
      expect(MigratedKey.read<dynamic>('expiresAt'), isNotNull,
          reason: 'PAUSED: _downgradeLocally must NOT delete expiresAt');
      expect(MigratedKey.read<dynamic>('plan'), 'yearly',
          reason: 'PAUSED: _downgradeLocally must NOT delete plan');
    });

    test(
        'guard is scoped to the flag — flipping it back off restores normal '
        'downgrade behaviour', () async {
      // Paused: preserve.
      SubscriptionService.pausedForSimulation = true;
      await seedExpiredPro();
      SubscriptionService.instance.isPro();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(MigratedKey.readWithDefault<bool>('isPro', false), isTrue);

      // Un-paused: downgrade resumes.
      SubscriptionService.pausedForSimulation = false;
      SubscriptionService.instance.isPro();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(MigratedKey.readWithDefault<bool>('isPro', false), isFalse,
          reason: 'once the sim flag is cleared, the expiry downgrade fires '
              'normally — guard must not leak state across the flag flip');
    });
  });
}
