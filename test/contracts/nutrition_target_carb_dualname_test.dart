// OBS-11 (2026-06-21) — contract for _resolveNutritionTargets dual-name read.
//
// The cloud column + restore/sync path (sync_profile `_restoreUserProfile`,
// sync_service) use the PLURAL `carbs_grams`; the nutrition + home readers use
// the SINGULAR `carb_grams`. A RESTORED profile (established account) therefore
// carries only `carbs_grams`, so `_resolveNutritionTargets`'s all-four canonical
// check failed on `carb_grams` and fell through to the RECOMPUTE branch (or, with
// no BMR inputs, the hardcoded 2400/184 defaults) — Nutrition targets drifted
// from the stored canonical (live: 2540/140 -> 2583/150). The dual-name read
// (`carb_grams ?? carbs_grams`) lets the canonical branch fire for a restored
// profile, so Home == Nutrition == user_profile.
//
// RED→GREEN: the restored fixture below has NO carb_grams and NO BMR inputs, so
// without the fix it returns the 2400/184 hardcoded defaults; with the fix it
// returns the stored canonical 2540/140.
//
// Run: flutter test test/contracts/nutrition_target_carb_dualname_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';

void main() {
  group('_resolveNutritionTargets — OBS-11 carb_grams/carbs_grams dual-name', () {
    test(
        'RESTORED profile (carbs_grams only, no carb_grams, no BMR inputs) reads '
        'the stored canonical — does NOT recompute or hit defaults', () {
      final restored = <String, dynamic>{
        'daily_calories': 2540,
        'protein_grams': 140,
        'carbs_grams': 280, // plural — the cloud/restore name
        'fat_grams': 80,
      };
      final t = resolveNutritionTargetsForTest(restored);
      expect(t['daily_calories'], 2540,
          reason: 'canonical daily_calories must be read as-is, not recomputed '
              'to 2583 (live) / 2400 (default).');
      expect(t['protein_grams'], 140,
          reason: 'canonical protein must be read as-is, not 150 / 184.');
      expect(t['carb_grams'], 280, reason: 'carb read from the plural carbs_grams.');
      expect(t['fat_grams'], 80);
    });

    test('NEW profile (carb_grams singular present) still reads canonical', () {
      final fresh = <String, dynamic>{
        'daily_calories': 2540,
        'protein_grams': 140,
        'carb_grams': 280, // singular — the onboarding name
        'fat_grams': 80,
      };
      final t = resolveNutritionTargetsForTest(fresh);
      expect(t['daily_calories'], 2540);
      expect(t['protein_grams'], 140);
      expect(t['carb_grams'], 280);
      expect(t['fat_grams'], 80);
    });
  });
}
