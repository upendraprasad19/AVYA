import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

/// One planned meal slot derived from the saved diet plan
/// (`userBox['saved_diet_plan']`, written by `DietPlanScreen._savePlan` —
/// migrated from configBox in Test #11.1).
///
/// Used by [TodaysMealsCard] to render a "From Your Diet Plan" hint on
/// any empty slot — BREAKFAST / LUNCH / DINNER / SNACK — so the user can
/// tap `+ LOG` and have the food search pre-filtered for the planned
/// first food.
class PlannedSlot {
  /// Normalised slot key: `breakfast` / `lunch` / `dinner` / `snack`.
  final String slot;

  /// One-line summary of planned foods joined by ` · `
  /// (e.g. "Oats · Boiled eggs · Banana").
  final String summary;

  /// Total kcal summed across items in this planned meal.
  final double calories;

  /// Total protein (g) summed across items.
  final double protein;

  /// First item's `name` (display hint) — used to pre-fill the food
  /// search query when the user taps `+ LOG` on an empty slot.
  final String? firstFoodName;

  const PlannedSlot({
    required this.slot,
    required this.summary,
    required this.calories,
    required this.protein,
    required this.firstFoodName,
  });
}

/// Returns the planned meal for each slot keyed by lowercase slot name.
/// Empty map when no diet plan is saved. Invalidate after save/clear.
///
/// Maps the free-form `name` field on each saved-meal entry to a
/// canonical slot key:
///   Breakfast → breakfast
///   Lunch     → lunch
///   Dinner    → dinner
///   Snack(s)  → snack
/// Unknown names fall back to `snack` so the plan is never silently
/// dropped.
class DietPlanNotifier extends Notifier<Map<String, PlannedSlot>> {
  @override
  Map<String, PlannedSlot> build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    final raw = UserRepository.instance.getSavedDietPlan();
    if (raw == null) return const {};

    final meals = raw['meals'];
    if (meals is! List || meals.isEmpty) return const {};

    final result = <String, PlannedSlot>{};
    for (final m in meals) {
      if (m is! Map) continue;
      final name = (m['name'] as String? ?? '').trim().toLowerCase();
      final slot = switch (name) {
        'breakfast' => 'breakfast',
        'lunch' => 'lunch',
        'dinner' => 'dinner',
        'snack' || 'snacks' => 'snack',
        _ => 'snack',
      };

      final items = (m['items'] as List?) ?? const [];
      if (items.isEmpty) continue;

      double cals = 0;
      double protein = 0;
      final names = <String>[];
      String? firstFoodName;
      for (final item in items) {
        if (item is! Map) continue;
        cals += (item['calories'] as num?)?.toDouble() ?? 0;
        protein += (item['protein'] as num?)?.toDouble() ?? 0;
        final itemName = (item['name'] as String? ?? '').trim();
        if (itemName.isEmpty) continue;
        firstFoodName ??= itemName;
        names.add(itemName);
      }
      if (names.isEmpty) continue;

      // Multi-items per slot is rare in the current diet-plan screen but
      // possible; last one wins so a user who tweaked the plan sees the
      // most recent version.
      result[slot] = PlannedSlot(
        slot: slot,
        summary: names.join(' \u00B7 '),
        calories: cals,
        protein: protein,
        firstFoodName: firstFoodName,
      );
    }
    return result;
  }
}

final dietPlanProvider =
    NotifierProvider<DietPlanNotifier, Map<String, PlannedSlot>>(
        DietPlanNotifier.new);
