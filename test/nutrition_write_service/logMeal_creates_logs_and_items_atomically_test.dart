// ignore_for_file: file_names

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';

void main() {
  group('NutritionWriteService.logMeal', () {
    test('throws UnimplementedError until Task C-3 ships', () async {
      expect(
        () async => NutritionWriteService.instance.logMeal(
          date: DateTime(2026, 5, 1),
          mealType: 'breakfast',
          items: const [
            FoodItem(
              name: 'Oats',
              quantityG: 50,
              calories: 180,
              protein: 6,
              carbs: 30,
              fat: 3,
              fiber: 4,
            ),
          ],
          source: NutritionWriteSource.manualSearch,
        ),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}
