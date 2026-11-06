// test/contracts/diet_plan_saved_loaded_behavioral_test.dart
//
// BEHAVIORAL contract for the `diet_plan_saved_loaded` SoT registry concept.
//
// Concept: a diet plan saved via `UserRepository.saveDietPlan(map)` MUST be
// readable with the correct `calories` and `protein` targets via
// `UserRepository.getSavedDietPlan()` — the exact reader path called inside
// `DietPlanNotifier.build()` on every provider build.
//
// This test exercises the real write→read round-trip:
//   writer: UserRepository.saveDietPlan → MigratedKey.write('saved_diet_plan', …)
//   reader: UserRepository.getSavedDietPlan → MigratedKey.read<Map>('saved_diet_plan')
//
// It FAILS if:
//   - the Hive key 'saved_diet_plan' is renamed on either side
//   - the meals[*].calories or meals[*].protein field names drift
//   - MigratedKey.write routes to a different box than MigratedKey.read
//
// Bug class prevented: DietPlanNotifier.build() reads raw['meals'][*]['calories']
// and raw['meals'][*]['protein']. If the writer uses different field names (e.g.
// 'kcal' instead of 'calories'), the provider silently returns 0.0 for every
// slot — "FROM YOUR DIET PLAN" hints show 0 kcal. Source-grep tests pass either
// way; only a Hive round-trip catches the semantic drift.
//
// Concepts covered: `diet_plan_saved_loaded`
// Writer:  lib/shared/repositories/user_repository.dart  saveDietPlan
// Reader:  lib/features/nutrition/providers/diet_plan_provider.dart
//          DietPlanNotifier.build → UserRepository.getSavedDietPlan
//
// Run: flutter test test/contracts/diet_plan_saved_loaded_behavioral_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
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
    tempDir = Directory.systemTemp.createTempSync('diet_plan_hive_');
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

  group('diet_plan_saved_loaded — write→read round-trip (behavioral)', () {
    const testUserId = 'dddd1111-dddd-dddd-dddd-dddddddddddd';

    test(
        'saveDietPlan → getSavedDietPlan preserves calories and protein '
        'for each meal slot (the reader field names DietPlanNotifier uses)', () async {
      await HiveUserSession.openForUser(testUserId);

      // Construct a plan map with the exact shape DietPlanNotifier.build()
      // expects: raw['meals'] is a List of maps, each with 'name', 'items',
      // and items[*] with 'calories', 'protein', 'name'.
      final dietPlan = <String, dynamic>{
        'meals': [
          {
            'name': 'Breakfast',
            'items': [
              {'name': 'Oats', 'calories': 350.0, 'protein': 12.0},
              {'name': 'Boiled eggs', 'calories': 140.0, 'protein': 12.0},
            ],
          },
          {
            'name': 'Lunch',
            'items': [
              {'name': 'Brown rice', 'calories': 400.0, 'protein': 8.0},
              {'name': 'Dal', 'calories': 200.0, 'protein': 14.0},
            ],
          },
          {
            'name': 'Dinner',
            'items': [
              {'name': 'Chicken breast', 'calories': 300.0, 'protein': 55.0},
            ],
          },
        ],
      };

      // Write via the canonical writer (MigratedKey.write → userBox).
      await UserRepository.instance.saveDietPlan(dietPlan);

      // Read via the canonical reader (MigratedKey.read → userBox).
      // This is the EXACT call DietPlanNotifier.build() makes.
      final loaded = UserRepository.instance.getSavedDietPlan();

      expect(loaded, isNotNull,
          reason: 'getSavedDietPlan() must return non-null after saveDietPlan');

      final meals = loaded!['meals'] as List;
      expect(meals.length, 3, reason: 'all 3 meal slots must survive the round-trip');

      // --- Breakfast slot -------------------------------------------------
      final breakfast = meals[0] as Map;
      final bfItems = breakfast['items'] as List;
      final bfCalories =
          bfItems.fold<double>(0, (s, i) => s + (((i as Map<String, dynamic>)['calories'] as num).toDouble()));
      final bfProtein =
          bfItems.fold<double>(0, (s, i) => s + (((i as Map<String, dynamic>)['protein'] as num).toDouble()));

      expect(bfCalories, closeTo(490.0, 0.01),
          reason: "'calories' field name must be exactly 'calories' — "
              "if the writer uses 'kcal' or 'cal', DietPlanNotifier.build() "
              "reads 0.0 for every breakfast slot.");
      expect(bfProtein, closeTo(24.0, 0.01),
          reason: "'protein' field name must be exactly 'protein' — "
              "if it drifts to 'protein_g' or 'prot', DietPlanNotifier "
              "shows 0.0 protein hints on the nutrition screen.");

      // --- Lunch slot -----------------------------------------------------
      final lunch = meals[1] as Map;
      final lunchItems = lunch['items'] as List;
      final lunchCalories =
          lunchItems.fold<double>(0, (s, i) => s + (((i as Map<String, dynamic>)['calories'] as num).toDouble()));
      final lunchProtein =
          lunchItems.fold<double>(0, (s, i) => s + (((i as Map<String, dynamic>)['protein'] as num).toDouble()));

      expect(lunchCalories, closeTo(600.0, 0.01));
      expect(lunchProtein, closeTo(22.0, 0.01));

      // --- Dinner slot ----------------------------------------------------
      final dinner = meals[2] as Map;
      final dinnerItems = dinner['items'] as List;
      final dinnerProtein =
          dinnerItems.fold<double>(0, (s, i) => s + (((i as Map<String, dynamic>)['protein'] as num).toDouble()));

      expect(dinnerProtein, closeTo(55.0, 0.01),
          reason: 'high-protein anchor must survive the round-trip');

      // --- Item name (firstFoodName) round-trip ----------------------------
      final firstItemName = (bfItems.first as Map<String, dynamic>)['name'] as String;
      expect(firstItemName, 'Oats',
          reason: 'item name must survive the Hive round-trip — '
              "DietPlanNotifier uses items[0]['name'] as firstFoodName "
              'to pre-fill the food search query on tap.');
    });

    test(
        'getSavedDietPlan returns null when no plan has been saved '
        '(no plan = empty map in DietPlanNotifier)', () async {
      // Fresh user session — no plan written.
      const freshUserId = 'dddd2222-dddd-dddd-dddd-dddddddddddd';
      await HiveUserSession.openForUser(freshUserId);

      final result = UserRepository.instance.getSavedDietPlan();

      expect(result, isNull,
          reason: 'getSavedDietPlan MUST return null when no plan is saved; '
              'DietPlanNotifier.build() returns const {} in that case — '
              'no phantom diet-plan hints on the nutrition screen.');
    });

    test(
        'plan written as user-A is NOT visible to user-B '
        '(MigratedKey routes via namespaced userBox)', () async {
      const userA = 'dddd3333-dddd-dddd-dddd-aaaaaaaaaaaa';
      const userB = 'dddd4444-dddd-dddd-dddd-bbbbbbbbbbbb';

      // User A writes a plan.
      await HiveUserSession.openForUser(userA);
      await UserRepository.instance.saveDietPlan(<String, dynamic>{
        'meals': [
          {
            'name': 'Breakfast',
            'items': [
              {'name': 'Dosa', 'calories': 250.0, 'protein': 5.0}
            ],
          }
        ],
      });
      final planA = UserRepository.instance.getSavedDietPlan();
      expect(planA, isNotNull, reason: 'sanity: user-A can read their own plan');

      // Swap to user B.
      await HiveUserSession.closeAll();
      await HiveUserSession.openForUser(userB);

      final planB = UserRepository.instance.getSavedDietPlan();
      expect(planB, isNull,
          reason: 'user-B must NOT see user-A\'s diet plan; '
              'MigratedKey routes to the namespaced userBox — '
              'a cross-user read would mean MigratedKey.write/read '
              'use different box namespacing, breaking isolation.');
    });
  });
}
