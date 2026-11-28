// Diagnose a9d5c3: the weekly Insights cards follow a target change.
//
// `WeeklyNutritionNotifier` reads the calorie / protein targets straight from
// the profile. It was in no refresh list, so after Edit Profile's Save, the
// coach goal switch or a weigh-in that moved the targets
// (`invalidateProfileDerivedSurfaces`) the cards kept the old target line
// until the next meal log or day rollover. It is now in
// `profileDerivedSurfaceProviders`.
//
// Diagnose c2a4e8: Home and Nutrition show the same targets for every
// profile, including one with no stored targets (Home used its own fallback
// numbers 2000 / 120 / 250 / 65).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/nutrition/services/diet_strategy_flags.dart';
import 'package:icanbefitter/features/profile/providers/profile_surface_invalidation.dart';
import 'package:icanbefitter/features/profile/services/profile_write_service.dart';

import '../sync/sync_domain_skip_harness.dart';

void main() {
  final h = SyncHarness();
  setUp(() async {
    await h.setUp();
    h.server.clear();
    DietStrategyFlags.debugEnabledOverride = false;
  });
  tearDown(() async {
    DietStrategyFlags.debugEnabledOverride = null;
    await h.tearDown();
  });

  test('the weekly cards take the new target on the shared refresh', () async {
    await ProfileWriteService.instance.updateProfile(
        {'daily_calories': 2540, 'protein_grams': 140, 'carb_grams': 300, 'fat_grams': 70});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(weeklyNutritionProvider).calorieTarget, 2540);

    await ProfileWriteService.instance
        .patchProfile({'daily_calories': 2200, 'protein_grams': 150});
    expect(c.read(weeklyNutritionProvider).calorieTarget, 2540,
        reason: 'no refresh yet: the notifier reads Hive once per build');

    invalidateProfileDerivedSurfaces(c.invalidate, source: 'test');
    final week = c.read(weeklyNutritionProvider);
    expect((week.calorieTarget, week.proteinTarget), (2200, 150));
  });

  final profiles = <String, Map<String, dynamic>>{
    'stored pack': {
      'daily_calories': 2540, 'protein_grams': 140, 'carb_grams': 300, 'fat_grams': 70,
    },
    'restored pack (plural carbs)': {
      'daily_calories': 2540, 'protein_grams': 140, 'carbs_grams': 310, 'fat_grams': 70,
    },
    'inputs only': {
      'current_weight_kg': 80.0, 'height_cm': 178.0, 'gender': 'male',
      'primary_goal': 'general_fitness', 'activity_level': 'moderate',
    },
    'partial pack with inputs': {
      'daily_calories': 2540,
      'current_weight_kg': 80.0, 'height_cm': 178.0, 'gender': 'male',
      'primary_goal': 'general_fitness', 'activity_level': 'moderate',
    },
    'nothing': {'name': 'x'},
  };
  const expected = <String, List<double>>{
    'stored pack': [2540, 140, 300, 70],
    'restored pack (plural carbs)': [2540, 140, 310, 70],
    'inputs only': [2602, 128, 360, 72],
    'partial pack with inputs': [2602, 128, 360, 72],
    'nothing': [2400, 184, 280, 80],
  };

  for (final name in profiles.keys) {
    test('Home == Nutrition targets: $name', () async {
      await HiveService.instance.userBox.put('profile', profiles[name]);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final home = c.read(nutritionSummaryProvider);
      final nutrition = c.read(macroTargetsProvider);
      final homeTargets = [
        home.calorieTarget, home.proteinTarget, home.carbTarget, home.fatTarget,
      ];
      expect(homeTargets, expected[name]);
      expect(homeTargets, [
        nutrition['calories'], nutrition['protein'],
        nutrition['carbs'], nutrition['fat'],
      ]);
    });
  }
}
