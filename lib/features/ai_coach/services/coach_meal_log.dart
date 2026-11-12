import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/badge_service.dart';
import '../../../core/services/error_telemetry.dart';
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
String resolveCoachMealSlot(String? raw, DateTime at) {
  final lower = raw?.trim().toLowerCase() ?? '';
  if (_kMealSlots.contains(lower)) return lower;
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
