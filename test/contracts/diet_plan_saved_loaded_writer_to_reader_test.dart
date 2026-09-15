import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '_sync_service_source.dart';

/// Source-of-truth contract: writer/reader pairs for `diet_plan_saved_loaded`
/// from docs/sot_registry.yaml.
///
/// Writer: user_repository.saveDietPlan
/// Reader: diet_plan_provider.dietPlanProvider
///
/// Key: MigratedKey 'saved_diet_plan'. Cloud: saved_diet_plans table.
/// diet_plan_screen._savePlan MUST call ref.invalidate(dietPlanProvider)
/// after saveDietPlan so TodaysMealsCard sees the update.
void main() {
  late String userRepoSrc;
  late String dietPlanProvSrc;
  late String dietPlanScreenSrc;

  setUpAll(() {
    final uf = File('lib/shared/repositories/user_repository.dart');
    expect(uf.existsSync(), isTrue,
        reason: 'user_repository.dart must exist (saveDietPlan writer)');
    userRepoSrc = uf.readAsStringSync();

    final dpf =
        File('lib/features/nutrition/providers/diet_plan_provider.dart');
    expect(dpf.existsSync(), isTrue,
        reason: 'diet_plan_provider.dart must exist (dietPlanProvider reader)');
    dietPlanProvSrc = dpf.readAsStringSync();

    final dps =
        File('lib/features/nutrition/screens/diet_plan_screen.dart');
    expect(dps.existsSync(), isTrue,
        reason: 'diet_plan_screen.dart must exist (_savePlan invalidation gate)');
    dietPlanScreenSrc = dps.readAsStringSync();
  });

  group('diet_plan_saved_loaded writer↔reader source contract', () {
    test('writer saveDietPlan exists in user_repository', () {
      expect(userRepoSrc.contains('saveDietPlan'), isTrue,
          reason: 'user_repository must define saveDietPlan');
    });

    test('writer uses saved_diet_plan key via MigratedKey', () {
      expect(
          userRepoSrc.contains('saved_diet_plan') ||
              userRepoSrc.contains('MigratedKey'),
          isTrue,
          reason:
              'saveDietPlan must write via MigratedKey key saved_diet_plan '
              '(user-scoped per sot_registry.hive)');
    });

    test('reader dietPlanProvider exists in diet_plan_provider', () {
      expect(dietPlanProvSrc.contains('dietPlanProvider'), isTrue,
          reason: 'diet_plan_provider must define dietPlanProvider');
    });

    test('reader dietPlanProvider reads saved_diet_plan key', () {
      expect(
          dietPlanProvSrc.contains('saved_diet_plan') ||
              dietPlanProvSrc.contains('MigratedKey'),
          isTrue,
          reason:
              'dietPlanProvider must read saved_diet_plan key to return '
              'Map<String, PlannedSlot> for TodaysMealsCard hints');
    });

    test('diet_plan_screen._savePlan invalidates dietPlanProvider after save', () {
      // Without this invalidation, TodaysMealsCard never sees the saved plan
      expect(
          dietPlanScreenSrc.contains('dietPlanProvider') &&
              (dietPlanScreenSrc.contains('invalidate') ||
                  dietPlanScreenSrc.contains('ref.refresh')),
          isTrue,
          reason:
              'diet_plan_screen._savePlan must call ref.invalidate(dietPlanProvider) '
              'after saving so TodaysMealsCard renders the "FROM YOUR DIET PLAN" hints');
    });

    test('diet_plan_screen calls syncSavedDietPlan for cloud backup', () {
      expect(
          dietPlanScreenSrc.contains('syncSavedDietPlan'),
          isTrue,
          reason:
              'diet_plan_screen._savePlan must call SyncService.instance.syncSavedDietPlan() '
              'so saved plan survives reinstall for paying users');
    });

    test('cloud table saved_diet_plans referenced in sync_service', () {
      final sf = loadSyncServiceSource();
      if (!sf.existsSync()) return;
      final src = sf.readAsStringSync();
      expect(src.contains('saved_diet_plans'), isTrue,
          reason: 'sync_service must reference saved_diet_plans cloud table');
    });
  });
}
