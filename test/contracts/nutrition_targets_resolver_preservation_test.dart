// Pins the shown nutrition targets across the move of the resolver into
// lib/core/utils/nutrition_targets_resolver.dart (plan
// docs/plans/nutrition-history.md 5.1). Written and green on the code BEFORE
// the move; every literal below was produced by that code.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';

// No date_of_birth: the recompute then uses its fixed default age, so the
// literals do not move with the calendar.
Map<String, dynamic> _inputs() => {
      'current_weight_kg': 80.0,
      'height_cm': 178.0,
      'gender': 'male',
      'primary_goal': 'general_fitness',
      'activity_level': 'moderate',
    };

const _stored = {
  'daily_calories': 2540,
  'protein_grams': 140,
  'carb_grams': 300,
  'fat_grams': 70,
};

final _profiles = <String, Map<String, dynamic>?>{
  'null': null,
  'empty': <String, dynamic>{},
  'stored_singular': {..._stored},
  'stored_plural': {
    'daily_calories': 2540,
    'protein_grams': 140,
    'carbs_grams': 310,
    'fat_grams': 70,
  },
  'partial_with_inputs': {..._inputs(), 'daily_calories': 2540},
  'inputs_only': _inputs(),
  'keto': {..._stored, 'diet_strategy': 'keto'},
  'low_carb': {..._stored, 'diet_strategy': 'low_carb'},
};

const _fallback = {
  'daily_calories': 2400.0,
  'protein_grams': 184.0,
  'carb_grams': 280.0,
  'fat_grams': 80.0,
};
const _storedOut = {
  'daily_calories': 2540.0,
  'protein_grams': 140.0,
  'carb_grams': 300.0,
  'fat_grams': 70.0,
};
const _recomputed = {
  'daily_calories': 2602.0,
  'protein_grams': 128.0,
  'carb_grams': 360.0,
  'fat_grams': 72.0,
};

/// Expected map for (profile, strategyEnabled, pro).
Map<String, double> _expected(String name, bool enabled, bool pro) {
  switch (name) {
    case 'null':
    case 'empty':
      return _fallback;
    case 'stored_singular':
      return _storedOut;
    case 'stored_plural':
      return {..._storedOut, 'carb_grams': 310.0};
    case 'partial_with_inputs':
    case 'inputs_only':
      return _recomputed;
    case 'keto':
      if (enabled && pro) {
        return {
          'daily_calories': 2540.0,
          'protein_grams': 140.0,
          'carb_grams': 32.0,
          'fat_grams': 206.0,
          'strategy_index': 2.0,
        };
      }
      return _storedOut;
    case 'low_carb':
      if (enabled && pro) {
        return {
          'daily_calories': 2540.0,
          'protein_grams': 140.0,
          'carb_grams': 127.0,
          'fat_grams': 164.0,
          'strategy_index': 1.0,
        };
      }
      return _storedOut;
  }
  throw StateError('no expectation for $name');
}

void main() {
  for (final name in _profiles.keys) {
    for (final flags in const [(false, false), (true, false), (true, true)]) {
      test('$name, strategy ${flags.$1}, pro ${flags.$2}', () {
        final got = resolveNutritionTargetsForTest(
          _profiles[name],
          strategyEnabled: flags.$1,
          pro: flags.$2,
        );
        expect(got, _expected(name, flags.$1, flags.$2));
      });
    }
  }
}
