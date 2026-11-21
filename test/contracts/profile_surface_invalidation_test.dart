// OI-191: the ONE list of profile-derived surfaces that both writers (Edit Profile's
// Save and the coach switchGoal) invalidate. Behavioural: the helper is driven with
// a recording `invalidate`, so a shortened list or a swallowed failure is caught.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart'
    show nutritionSummaryProvider;
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart'
    show dailyNutritionProvider, macroTargetsProvider;
import 'package:icanbefitter/features/profile/providers/profile_completeness_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart'
    show userProfileProvider, userStatsProvider;
import 'package:icanbefitter/features/profile/providers/profile_surface_invalidation.dart';

void main() {
  test('every profile-derived surface is invalidated, each once', () {
    final seen = <Object>[];
    invalidateProfileDerivedSurfaces(seen.add, source: 'test');
    expect(seen.toSet(), {
      userProfileProvider,
      userStatsProvider,
      nutritionSummaryProvider,
      dailyNutritionProvider,
      macroTargetsProvider,
      profileCompletenessProvider,
    });
    expect(seen.length, 6, reason: 'once each');
  });

  test('one failing invalidate never stops the rest', () {
    final seen = <Object>[];
    var first = true;
    invalidateProfileDerivedSurfaces((p) {
      if (first) {
        first = false;
        throw StateError('disposed');
      }
      seen.add(p);
    }, source: 'test');
    expect(seen.length, 5);
  });
}
