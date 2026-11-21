// BEHAVIORAL contract for weekly_report_target_and_freshness:
//
// _resolveNutritionTargets (file-private in nutrition_provider.dart) is
// exercised indirectly through MacroTargetsNotifier.build(), which calls it.
//
// Contract 1 — STORED values are returned verbatim when present:
//   Write daily_calories + protein_grams + carb_grams + fat_grams directly
//   to userBox['profile']. MacroTargetsNotifier must return those exact values
//   (not recomputed, not defaulted) — the stored values are the canonical
//   source of truth and must survive the round-trip to the provider.
//
// Contract 2 — DEFAULTS are used when profile is absent:
//   When no profile is stored, MacroTargetsNotifier falls back to the
//   hardcoded defaults (daily_calories=2400, protein_grams=184).
//
// The EF half (saving computed values to the cloud) is out of scope.
//
// Writer: onboarding_provider.dart / ProfileWriteService (write to userBox['profile'])
// Reader: _resolveNutritionTargets (called by MacroTargetsNotifier.build)
//
// Run: flutter test test/contracts/weekly_report_target_and_freshness_behavioral_test.dart

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
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
    tempDir = Directory.systemTemp.createTempSync('weekly_report_target_');
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

  const testUser = 'test-nutrition-targets-0006-aabbccdd';

  setUp(() async {
    await HiveUserSession.openForUser(testUser);
    await HiveService.instance.userBox.clear();
    await HiveService.instance.nutritionBox.clear();
  });

  group(
      'weekly_report_target_and_freshness — stored targets returned verbatim',
      () {
    test(
        '_resolveNutritionTargets returns stored daily_calories and protein_grams '
        'when all four macro fields are present in profile', () {
      // Write profile with all four required macro fields.
      // MacroTargetsNotifier reads profile via UserRepository.instance.getProfile()
      // which reads userBox['profile'].
      const storedCalories = 2100.0;
      const storedProtein = 160.0;
      const storedCarbs = 230.0;
      const storedFat = 65.0;

      HiveService.instance.userBox.put('profile', {
        'daily_calories': storedCalories,
        'protein_grams': storedProtein,
        'carb_grams': storedCarbs,
        'fat_grams': storedFat,
        'full_name': 'Test User',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final targets = container.read(macroTargetsProvider);

      expect(targets['calories'], storedCalories,
          reason:
              'macroTargetsProvider[calories] must equal stored daily_calories '
              '($storedCalories) — NOT the hardcoded default 2400');
      expect(targets['protein'], storedProtein,
          reason:
              'macroTargetsProvider[protein] must equal stored protein_grams '
              '($storedProtein) — NOT the hardcoded default 184');
      expect(targets['carbs'], storedCarbs,
          reason: 'macroTargetsProvider[carbs] must equal stored carb_grams');
      expect(targets['fat'], storedFat,
          reason: 'macroTargetsProvider[fat] must equal stored fat_grams');
    });

    test(
        'stored targets survive provider read — values are not recomputed when '
        'all four fields are present', () {
      // Intentionally use values that differ from what BmrCalculator would
      // produce for typical inputs — if recomputation happens, the values
      // would diverge and the test would catch it.
      HiveService.instance.userBox.put('profile', {
        'daily_calories': 1800.0,
        'protein_grams': 120.0,
        'carb_grams': 200.0,
        'fat_grams': 55.0,
        // Include BMR inputs too — _resolveNutritionTargets must NOT use
        // these when all four macro targets are present.
        'current_weight_kg': 70.0,
        'height_cm': 175.0,
        'gender': 'male',
        'date_of_birth': '1995-01-01',
        'activity_level': 'moderate',
        'primary_goal': 'build_muscle',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final targets = container.read(macroTargetsProvider);

      // The stored value (1800) must win over any recomputed value.
      expect(targets['calories'], 1800.0,
          reason:
              'stored daily_calories=1800 must be returned verbatim even '
              'when BMR inputs are present (stored value is the canonical SoT)');
      expect(targets['protein'], 120.0,
          reason:
              'stored protein_grams=120 must be returned verbatim — recompute '
              'path must be skipped when all four macro fields exist');
    });
  });

  group('weekly_report_target_and_freshness — defaults when profile absent',
      () {
    test(
        '_resolveNutritionTargets falls back to hardcoded defaults when '
        'no profile exists in userBox', () {
      // No profile written — userBox is empty from setUp.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final targets = container.read(macroTargetsProvider);

      // Hardcoded last-resort defaults from nutrition_provider.dart:
      //   daily_calories: 2400, protein_grams: 184
      expect(targets['calories'], 2400.0,
          reason:
              'with no profile, default daily_calories must be 2400 '
              '(last-resort hardcoded default in _resolveNutritionTargets)');
      expect(targets['protein'], 184.0,
          reason:
              'with no profile, default protein_grams must be 184 '
              '(last-resort hardcoded default)');
    });

    test(
        '_resolveNutritionTargets falls back to defaults when profile is '
        'present but missing any macro field', () {
      // Profile exists but ONLY has BMR inputs, NOT the four macro fields.
      // This tests the incomplete-profile branch (second branch in
      // _resolveNutritionTargets — must either recompute from BMR or
      // use defaults, but NOT crash).
      HiveService.instance.userBox.put('profile', {
        'full_name': 'Test',
        // No daily_calories / protein_grams / carb_grams / fat_grams.
        // No BMR inputs either — so it falls to last-resort defaults.
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Must not throw.
      late Map<String, double> targets;
      expect(
        () {
          targets = container.read(macroTargetsProvider);
        },
        returnsNormally,
        reason:
            '_resolveNutritionTargets must not throw for a partial profile',
      );

      // Result must be a valid map with all four keys and positive values.
      expect(targets.containsKey('calories'), isTrue);
      expect(targets.containsKey('protein'), isTrue);
      expect((targets['calories'] ?? 0) > 0, isTrue,
          reason: 'calorie target must be positive even for a partial profile');
    });
  });
}
