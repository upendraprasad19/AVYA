// ignore_for_file: file_names

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';

import 'helpers/nws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(nwsTestSetup);
  tearDown(nwsTestTeardown);

  // -------- Mapping checks (deterministic, no Hive dependency) --------

  test('aiText maps to featureAiTextLogPro', () {
    expect(
      NutritionWriteService.counterFeatureForSource(
          NutritionWriteSource.aiText),
      AppConstants.featureAiTextLogPro,
    );
  });

  test('aiCoachTool maps to featureAiTextLogPro', () {
    expect(
      NutritionWriteService.counterFeatureForSource(
          NutritionWriteSource.aiCoachTool),
      AppConstants.featureAiTextLogPro,
    );
  });

  test('scan maps to featureScanMealPro', () {
    expect(
      NutritionWriteService.counterFeatureForSource(NutritionWriteSource.scan),
      AppConstants.featureScanMealPro,
    );
  });

  test('cart maps to featureCartAuditorPro', () {
    expect(
      NutritionWriteService.counterFeatureForSource(NutritionWriteSource.cart),
      AppConstants.featureCartAuditorPro,
    );
  });

  test('manualSearch / barcode / savedMealRelog / prelog map to no counter',
      () {
    for (final s in [
      NutritionWriteSource.manualSearch,
      NutritionWriteSource.barcode,
      NutritionWriteSource.savedMealRelog,
      NutritionWriteSource.prelog,
    ]) {
      expect(
        NutritionWriteService.counterFeatureForSource(s),
        isNull,
        reason: '$s is a free unlimited path (no counter)',
      );
    }
  });

  // -------- Behavioral check: write succeeds end-to-end for each source ----

  test('logMeal succeeds for all 8 sources', () async {
    for (var i = 0; i < NutritionWriteSource.values.length; i++) {
      final s = NutritionWriteSource.values[i];
      // Vary item name per iteration so the deterministic key differs;
      // this avoids cross-source key collisions in the same date+meal.
      final items = [
        FoodItem(
          name: 'Apple-${s.name}',
          quantityG: 150 + i.toDouble(),
          calories: 80,
          protein: 0,
          carbs: 21,
          fat: 0,
          fiber: 4,
        ),
      ];
      final r = await NutritionWriteService.instance.logMeal(
        date: DateTime(2026, 5, 1),
        mealType: 'snacks',
        items: items,
        source: s,
      );
      expect(r.success, true,
          reason: 'source=$s should produce a successful WriteResult');
    }
  });
}
