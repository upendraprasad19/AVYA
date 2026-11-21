// BEHAVIORAL CONTRACT TEST — water_target
//
// Concept:   water_target
// Writer:    lib/core/services/water_target_service.dart (setUserOverride)
// Reader:    WaterTargetService.instance.currentTargetMl()
//            lib/features/nutrition/providers/nutrition_provider.dart
//            (waterTargetProvider)
//
// Assert:
//   1. After setUserOverride(N), currentTargetMl() returns N (no stale value).
//   2. After setUserOverride(null), currentTargetMl() falls back to the
//      formula-computed value (override cleared).
//   3. Out-of-range values are clamped (floor 2500, ceiling 4000).
//   4. waterTargetProvider (Riverpod) returns the new target on first read
//      after the override is set (no stale provider cache).

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/water_target_service.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// ---------------------------------------------------------------------------
// Fake path provider
// ---------------------------------------------------------------------------

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;

  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;

  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;
  const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-000000000020';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir =
        Directory.systemTemp.createTempSync('water_target_behavioral_');
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
    await HiveUserSession.openForUser(fakeUserId);
    // Start each test with a clean slate — remove any previous override.
    await WaterTargetService.instance.setUserOverride(null);
  });

  tearDown(() async {
    await WaterTargetService.instance.setUserOverride(null);
    await HiveUserSession.closeAll();
  });

  // -------------------------------------------------------------------------
  // Test 1 — setUserOverride persists and currentTargetMl reads it back
  // -------------------------------------------------------------------------

  test(
    'setUserOverride(3200) → currentTargetMl() returns 3200 (no stale value)',
    () async {
      // PRE-CONDITION: no override yet.
      expect(WaterTargetService.instance.hasUserOverride(), isFalse);

      // ACT
      await WaterTargetService.instance.setUserOverride(3200);

      // ASSERT — service reader returns new value immediately.
      expect(WaterTargetService.instance.currentTargetMl(), 3200,
          reason:
              'currentTargetMl() must return the overridden value 3200 ml '
              'immediately after setUserOverride(3200)');
      expect(WaterTargetService.instance.hasUserOverride(), isTrue);
    },
  );

  // -------------------------------------------------------------------------
  // Test 2 — clearing the override falls back to formula
  // -------------------------------------------------------------------------

  test(
    'setUserOverride(null) clears the override; currentTargetMl() returns formula value',
    () async {
      // Seed a profile so the formula has meaningful inputs.
      await HiveService.instance.userBox.put('profile', <String, dynamic>{
        'current_weight_kg': 70.0,
        'lifestyle_activity': 'moderate',
        'days_per_week': 3,
      });
      final formulaValue = WaterTargetService.computeFromProfile(
          HiveService.instance.userBox.get('profile') as Map);

      // Set then clear override.
      await WaterTargetService.instance.setUserOverride(3800);
      expect(WaterTargetService.instance.currentTargetMl(), 3800);

      await WaterTargetService.instance.setUserOverride(null);

      // ASSERT — back to formula.
      expect(WaterTargetService.instance.currentTargetMl(), formulaValue,
          reason:
              'After clearing the override, currentTargetMl() must return the '
              'formula-computed value, not the previous override');
      expect(WaterTargetService.instance.hasUserOverride(), isFalse);
    },
  );

  // -------------------------------------------------------------------------
  // Test 3 — values are clamped (floor 2500, ceiling 4000)
  // -------------------------------------------------------------------------

  test(
    'setUserOverride clamps values to [2500, 4000]',
    () async {
      // Below floor.
      await WaterTargetService.instance.setUserOverride(1000);
      expect(WaterTargetService.instance.currentTargetMl(), 2500,
          reason: 'values below floor 2500 must be clamped to 2500');

      // Above ceiling.
      await WaterTargetService.instance.setUserOverride(9000);
      expect(WaterTargetService.instance.currentTargetMl(), 4000,
          reason: 'values above ceiling 4000 must be clamped to 4000');

      // In-range value survives unchanged.
      await WaterTargetService.instance.setUserOverride(3000);
      expect(WaterTargetService.instance.currentTargetMl(), 3000,
          reason: 'in-range value 3000 must survive unchanged');
    },
  );

  // -------------------------------------------------------------------------
  // Test 4 — waterTargetProvider (Riverpod) reflects the new target
  // -------------------------------------------------------------------------

  test(
    'waterTargetProvider returns the overridden target on first read (no stale cache)',
    () async {
      await WaterTargetService.instance.setUserOverride(3600);

      // Create a fresh ProviderContainer — this simulates the provider being
      // read for the first time after the service state changes.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final target = container.read(waterTargetProvider);

      expect(target, 3600,
          reason:
              'waterTargetProvider must return 3600 after setUserOverride(3600); '
              'it delegates to WaterTargetService.instance.currentTargetMl() '
              'which reads directly from Hive on every call');
    },
  );
}
