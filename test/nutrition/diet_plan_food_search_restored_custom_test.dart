// test/nutrition/diet_plan_food_search_restored_custom_test.dart
//
// Diet chart v3 (docs/plans/diet-chart-v3.md §4.3, plan review round 2 N1):
// the swap search reads the user's own foods from the customBox by the
// `custom_food_` key prefix ALONE. A food restored from the cloud
// (`sync_community.dart` `_restoreCustomFoods`, the `_projectCustomFood`
// shape) has no `type` and no `is_custom`; requiring either hid every restored
// food (APK Test #15.4 was the same bug in the exercise reader).
//
// Mutant: filter getCustomFoods on `type == 'food'` -> the first test reddens.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_food_search.dart';
import 'package:icanbefitter/shared/repositories/food_repository.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await setUpHiveForTests());
  tearDown(() async => tearDownHiveForTests(dir));

  // The cloud projection: no `type`, no `is_custom`.
  Map<String, dynamic> restored(String id, String name) => {
        'id': id,
        'name': name,
        'calories_per_100g': 150,
        'protein_per_100g': 6,
        'carbs_per_100g': 18,
        'fat_per_100g': 5,
        'standard_serving_desc': '1 bowl',
        'standard_serving_g': 200,
        'created_at': '2026-11-02T08:00:00',
      };

  test('a cloud-restored own food (no type, no is_custom) is read; '
      'exercises and nameless rows are not', () async {
    final box = HiveService.instance.customBox;
    await box.put('custom_food_u-1', restored('u-1', 'Amma Upma'));
    await box.put('custom_exercise_e-1',
        {'id': 'e-1', 'name': 'Sled Push', 'type': 'exercise'});
    await box.put('custom_food_blank', {'id': 'b', 'name': '  '});
    // a row with no id: the key's suffix becomes the id
    await box.put('custom_food_k-9', {'name': 'No Id Poha'});
    final foods = FoodRepository.instance.getCustomFoods();
    expect({for (final f in foods) f['id']}, {'u-1', 'k-9'});
    expect(foods.where((f) => f['name'] == 'Sled Push'), isEmpty);
  });

  test('end to end: the search finds it, tagged Yours, for a vegan', () async {
    await HiveService.instance.customBox
        .put('custom_food_u-1', restored('u-1', 'Amma Upma'));
    final hits = searchDietPlanFoods(
      query: 'upma',
      foods: FoodRepository.instance.getAll(),
      customFoods: FoodRepository.instance.getCustomFoods(),
      dietPreference: 'vegan',
      adult: true,
      powdersAllowed: false,
    );
    expect(hits.first.id, 'u-1');
    expect(hits.first.yours, isTrue);
  });

  test('the foodBox copy that addCustomFood writes (is_custom) is not a '
      'second hit, and another account\'s copy never shows', () async {
    final row = {...restored('u-2', 'Zesty Salad'), 'is_custom': true, 'type': 'food'};
    await HiveService.instance.foodBox.put('u-2', row);
    // not in the customBox (the account was switched; the foodBox survives)
    final hits = searchDietPlanFoods(
      query: 'zesty',
      foods: FoodRepository.instance.getAll(),
      customFoods: FoodRepository.instance.getCustomFoods(),
      dietPreference: 'non-veg',
      adult: true,
      powdersAllowed: false,
    );
    expect(hits, isEmpty);
  });
}
