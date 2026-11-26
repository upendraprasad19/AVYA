import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/badge_service.dart';
import '../../../core/services/error_telemetry.dart';
import '../../../core/services/hive_service.dart';
import '../../../core/services/nutrition_write_service.dart';
import '../../../core/services/nutrition_write_source.dart';
import '../../../core/services/write_result.dart';
import '../../nutrition/services/meal_slot_inference.dart';

/// OI-493 Landing A: the ONE writer for a meal logged from the AI coach.
///
/// Both coach doors land here: the `logMealByText` tool (APPLY card,
/// `ToolDispatcher._executeLogMealByText`) and the legacy `log_food` tag
/// (auto-saving card, `ConversationalLogHandler._logFood`), so a coach meal
/// stores and counts the same whichever door it came through, and the same as
/// the Nutrition screen's AI-text tab (`AiBreakdownNotifier.saveMeal`): the
/// same item shape, the same writer, the same badge check.
///
/// [at] is the instant the meal was reported: the server's `intent.createdAt`
/// for the tool, the card's creation for the tag. Its IST day is the log day
/// (`logMeal` applies the IST shift once) and, through [resolveCoachMealSlot],
/// its device-local hour picks the slot when the coach named none.
class CoachMealLog {
  CoachMealLog._();

  /// Test seam: replaces the badge check (count the calls, or throw to prove
  /// a failing check never fails a stored meal). Null in production.
  @visibleForTesting
  static void Function()? debugBadgeCheck;

  static Future<WriteResult> write({
    required DateTime at,
    required String? mealType,
    required List<FoodItem> items,
    int? overrideTotalCals,
    int? overrideTotalProtein,
  }) async {
    final result = await NutritionWriteService.instance.logMeal(
      date: at,
      mealType: resolveCoachMealSlot(mealType, at),
      items: items,
      overrideTotalCals: overrideTotalCals,
      overrideTotalProtein: overrideTotalProtein,
      source: NutritionWriteSource.aiCoachTool,
    );
    if (result.success) {
      // The badge check FoodLogNotifier.logFood runs after a search log.
      // Synchronous; a throw here must never turn a stored meal into a
      // failure (a retry would then log it again).
      try {
        final hook = debugBadgeCheck;
        if (hook != null) {
          hook();
        } else {
          BadgeService.instance.checkAll();
        }
      } catch (e, st) {
        debugPrint('[CoachMealLog] badge check failed: $e\n$st');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'coach_meal_log_badge_check'));
      }
    }
    return result;
  }
}

const _kMealSlots = {'breakfast', 'lunch', 'dinner', 'snacks'};

/// The slot a coach meal is written to: the coach's own slot when it named a
/// valid one, else the Nutrition screen's clock rule for [at]. `.toLocal()` is
/// load-bearing: the tool's `createdAt` is UTC-flagged and [inferMealSlot]
/// reads the raw hour, so without it a 13:00 IST lunch reads as breakfast.
///
/// Any value naming a snack ("snack", "Evening snack") is `snacks`: the old
/// coach paths mapped every unknown value to `snacks`, and a snack reported at
/// dinner time must not become dinner (B-pass seat A, P2).
String resolveCoachMealSlot(String? raw, DateTime at) {
  final lower = raw?.trim().toLowerCase() ?? '';
  if (_kMealSlots.contains(lower)) return lower;
  if (lower.contains('snack')) return 'snacks';
  return inferMealSlot(at.toLocal());
}

double _num(Object? v) => (v is num && v.isFinite) ? v.toDouble() : 0.0;

/// The items a `log_meal_by_text` intent writes: one [FoodItem] per parsed
/// `items[]` entry, in the shape `AiBreakdownNotifier.saveMeal` writes (the
/// parser gives no grams, so the 100 g sentinel; fibre from `fiber_g`). A
/// payload with no usable item becomes one item from the meal totals.
List<FoodItem> coachItemsFromParsedMeal(Map<String, dynamic> payload) {
  final out = <FoodItem>[];
  final raw = payload['items'];
  if (raw is List) {
    for (final e in raw) {
      if (e is! Map) continue;
      final name = e['name'];
      if (name is! String || name.trim().isEmpty) continue;
      out.add(FoodItem(
        name: name.trim(),
        quantityG: 100.0,
        calories: _num(e['calories']),
        protein: _num(e['protein_g']),
        carbs: _num(e['carbs_g']),
        fat: _num(e['fat_g']),
        fiber: _num(e['fiber_g']),
      ));
    }
  }
  if (out.isNotEmpty) return out;
  final foodName = payload['food_name'];
  return [
    FoodItem(
      name: foodName is String && foodName.trim().isNotEmpty
          ? foodName.trim()
          : 'Meal',
      quantityG: 100.0,
      calories: _num(payload['total_calories']),
      protein: _num(payload['total_protein_g']),
      carbs: _num(payload['total_carbs_g']),
      fat: _num(payload['total_fat_g']),
      fiber: 0,
    ),
  ];
}

/// The tool card's override totals, parsed the way the dispatcher stores them
/// (`toInt`, truncating). Never casts: it runs in a widget `build`, so a
/// wrong-typed field gives 0 (then [NutritionWriteService.mealTotals] falls
/// back to the items' sum) instead of throwing (OI-348 Landing 3b, R2-3).
({int cals, int protein}) coachToolOverrides(Map<String, dynamic> payload) {
  int whole(Object? v) => (v is num && v.isFinite) ? v.toInt() : 0;
  return (
    cals: whole(payload['total_calories']),
    protein: whole(payload['total_protein_g']),
  );
}

/// OI-348 Landing 3b test seam: overrides the configBox kill switch
/// (`true` = card OFF, `false` = card ON). Null in production.
@visibleForTesting
bool? debugCoachMealItemsCardDisabled;

/// Whether the coach meal cards show one row per food and the food tag waits
/// for CONFIRM (OI-348 Landing 3b, founder P5). Kill switch
/// `configBox['disable_coach_meal_items_card'] == true` restores the old
/// cards (one line, 5 s auto-save for a food tag). A closed box = the fix ON.
bool coachMealItemsCardEnabled() {
  final forced = debugCoachMealItemsCardDisabled;
  if (forced != null) return !forced;
  try {
    return HiveService.instance.configBox.get('disable_coach_meal_items_card') !=
        true;
  } catch (_) {
    return true;
  }
}

/// The items a `log_food` tag writes (OI-348 Landing 3b). With the card ON,
/// one [FoodItem] per usable `items[]` entry (a non-blank `name` and finite
/// `calories` >= 0; grams > 0 else 100); unusable entries are skipped, and no
/// usable entry falls back to the flat-key item. With it OFF, the flat-key
/// item only (today). Null when there is nothing to log (no card).
List<FoodItem>? coachItemsFromTag(Map<String, dynamic> data) {
  final single = coachItemFromTag(data);
  if (!coachMealItemsCardEnabled()) return single == null ? null : [single];
  final out = <FoodItem>[];
  final raw = data['items'];
  if (raw is List) {
    for (final e in raw) {
      final item = _tagListItem(e);
      if (item != null) out.add(item);
    }
  }
  if (out.isNotEmpty) return out;
  return single == null ? null : [single];
}

/// How many `items[]` entries of a `log_food` tag [coachItemsFromTag] skips
/// (B-pass F3): 0 with the card off or no list. The caller reports a partial
/// parse (`coach_food_tag_items_partial`) so a dropped food is never silent.
int coachTagUnusableItemCount(Map<String, dynamic> data) {
  if (!coachMealItemsCardEnabled()) return 0;
  final raw = data['items'];
  if (raw is! List) return 0;
  return raw.where((e) => _tagListItem(e) == null).length;
}

/// One `items[]` entry of a tag: a non-blank `name` and finite `calories`
/// >= 0, else null. Grams > 0 else 100, the same sentinel as the tool path
/// ([coachItemsFromParsedMeal]).
FoodItem? _tagListItem(Object? e) {
  if (e is! Map) return null;
  final name = e['name'];
  if (name is! String || name.trim().isEmpty) return null;
  final cal = e['calories'];
  if (cal is! num || !cal.isFinite || cal < 0) return null;
  final q = e['quantity_g'];
  return FoodItem(
    name: name.trim(),
    quantityG: (q is num && q.isFinite && q > 0) ? q.toDouble() : 100.0,
    calories: cal.toDouble(),
    protein: _num(e['protein_g']),
    carbs: _num(e['carbs_g']),
    fat: _num(e['fat_g']),
    fiber: 0,
  );
}

/// The coach's named meal slot, or null when the payload's `meal_type` is
/// absent or not a String (B-pass F2: model JSON can carry a number or a
/// list; a cast would throw in `build` or lose the reply's other actions).
String? coachMealTypeOf(Map<String, dynamic> data) {
  final m = data['meal_type'];
  return m is String ? m : null;
}

/// The one item a `log_food` tag writes: the coach's own name and estimates
/// (never a food-database substitute, never invented defaults). Null when the
/// tag has no usable `calories_estimate`: such a tag shows no card.
FoodItem? coachItemFromTag(Map<String, dynamic> data) {
  final name = data['food_name'];
  if (name is! String || name.trim().isEmpty) return null;
  final cal = data['calories_estimate'];
  if (cal is! num || !cal.isFinite || cal < 0) return null;
  final q = data['quantity_g'];
  return FoodItem(
    name: name.trim(),
    quantityG: (q is num && q.isFinite && q > 0) ? q.toDouble() : 100.0,
    calories: cal.toDouble(),
    protein: _num(data['protein_estimate']),
    carbs: _num(data['carbs_estimate']),
    fat: _num(data['fat_estimate']),
    fiber: 0,
  );
}
