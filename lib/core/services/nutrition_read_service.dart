import 'hive_service.dart';

/// Canonical READ service for nutrition-domain Hive surfaces.
///
/// Mirrors `NutritionWriteService` on the writer side. The per-item
/// Atwater fallback semantic (`kcal > 0 ? kcal : 4P+4C+9F`) used to
/// be re-implemented inline at every consumer that summed `items[]`.
/// Centralising the sum here prevents drift — when the writer's fallback
/// rule changes, only this file needs to update.
///
/// closes-OI: OI-02 (architecture-gap — no symmetric ReadServices)
///
/// Hive field-name contract (READ side — must agree with the writer
/// contract documented in CLAUDE.md §15 "Hive field-name contract"):
///
/// `nlog_*` rows (canonical, from `NutritionWriteService.logMeal`):
///   - `date`               : String (IST `YYYY-MM-DD`)
///   - `meal_type`          : String ∈ {breakfast,lunch,dinner,snacks}
///   - `total_calories`     : num
///   - `total_protein`      : num
///   - `total_carbs`        : num
///   - `total_fat`          : num
///   - `total_fiber`        : num
///   - `items[]`            : List<Map> — per-item rows
///     - `name`             : String
///     - `quantity_g`       : num
///     - `calories`         : num
///     - `protein`          : num
///     - `carbs`            : num
///     - `fat`              : num
///     - `fiber`            : num
///   - `is_saved_meal`      : bool (exclude from daily totals)
class NutritionReadService {
  NutritionReadService._();
  static final NutritionReadService instance = NutritionReadService._();

  // ─────────────────────────────────────────────────────────────
  //  Display-name derivation (shared SoT — Obs 2 2026-06-05)
  // ─────────────────────────────────────────────────────────────

  /// Last-resort meal-name sentinel. Distinct from 'Unknown' (the pre-12.6
  /// silent-failure tell) so telemetry can detect new shape regressions.
  static const String kFallbackMealName = 'Logged meal';

  /// Canonical display name for a nutrition log [meal] map. The writer
  /// (`NutritionWriteService.logMeal`) stores names ONLY inside `items[].name`
  /// (+ a `meal_type`), never a top-level `food_name`. Resolution order:
  ///   1. `items[].name` joined by ` · ` (most informative)
  ///   2. capitalized `meal_type` (e.g. "Breakfast")
  ///   3. capitalized [slot] label, when provided
  ///   4. [kFallbackMealName] — caller should emit `food_log_unknown_name`.
  /// BOTH the nutrition Today's-Meals card AND the home recent-logs provider
  /// MUST call this (not a private copy) so the displayed name can't drift —
  /// Obs 2: the home reader read `food_name`/`meal_name` the writer never wrote
  /// → every row rendered "Unknown".
  static String deriveMealDisplayName(Map<String, dynamic> meal,
      {String slot = ''}) {
    final itemsArr = meal['items'];
    if (itemsArr is List && itemsArr.isNotEmpty) {
      final names = itemsArr
          .whereType<Map>()
          .map((m) => (m['name'] as String?)?.trim())
          .whereType<String>()
          .where((n) => n.isNotEmpty)
          .toList();
      if (names.isNotEmpty) return names.join(' · ');
    }
    final mealType = (meal['meal_type'] as String?)?.trim();
    if (mealType != null && mealType.isNotEmpty) {
      return '${mealType[0].toUpperCase()}${mealType.substring(1)}';
    }
    if (slot.isNotEmpty) {
      return '${slot[0].toUpperCase()}${slot.substring(1)}';
    }
    return kFallbackMealName;
  }

  // ─────────────────────────────────────────────────────────────
  //  Macro summation primitives
  // ─────────────────────────────────────────────────────────────

  /// Sums every `nlog_*` row whose stamped `date` matches the IST
  /// calendar date of [date]. Excludes `is_saved_meal: true` rows
  /// (those are templates, not actual logs).
  ///
  /// Returns a 5-key map: `calories`, `protein`, `carbs`, `fat`, `fiber`.
  /// All values are `num`; callers cast as needed.
  ///
  /// Date-key formula mirrors `NutritionWriteService.logMeal` exactly
  /// (`${date.year}-${m2}-${d2}` from the raw DateTime — no IST shift,
  /// the caller is responsible for passing the date they want to query
  /// in the same time zone the writer stamped). This preserves the
  /// pre-OI-02 reader semantic verbatim — there was a deliberate
  /// reader↔writer agreement here, see audit feedback for nutrition
  /// IST handling.
  Map<String, num> totalMacrosForDate(DateTime date) {
    final dateStr = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    num calories = 0;
    num protein = 0;
    num carbs = 0;
    num fat = 0;
    num fiber = 0;

    for (final raw in HiveService.instance.nutritionBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['date'] != dateStr) continue;
      if (log['is_saved_meal'] == true) continue;

      calories += (log['total_calories'] as num?) ?? 0;
      protein += (log['total_protein'] as num?) ?? 0;
      carbs += (log['total_carbs'] as num?) ?? 0;
      fat += (log['total_fat'] as num?) ?? 0;
      fiber += (log['total_fiber'] as num?) ?? 0;
    }

    return {
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'fiber': fiber,
    };
  }

  /// Sums macros across a per-item list (the `items[]` array on an
  /// `nlog_*` row, or a fresh list being prepared for a write).
  ///
  /// Applies Atwater fallback per item: when `calories <= 0`, computes
  /// `4*protein + 4*carbs + 9*fat`. This mirrors `FoodItem.kcalWithFallback`
  /// in `nutrition_write_source.dart` so writer + reader can never drift.
  ///
  /// Returns the same 5-key shape as [totalMacrosForDate]. Pass-through
  /// `0` totals when `items` is empty.
  static Map<String, num> totalMacrosFromItems(List<dynamic> items) {
    num calories = 0;
    num protein = 0;
    num carbs = 0;
    num fat = 0;
    num fiber = 0;

    for (final raw in items) {
      if (raw is! Map) continue;
      final p = (raw['protein'] as num?) ?? 0;
      final c = (raw['carbs'] as num?) ?? 0;
      final f = (raw['fat'] as num?) ?? 0;
      final fib = (raw['fiber'] as num?) ?? 0;
      final rawCals = (raw['calories'] as num?) ?? 0;
      final cals = rawCals > 0 ? rawCals : (4 * p) + (4 * c) + (9 * f);

      calories += cals;
      protein += p;
      carbs += c;
      fat += f;
      fiber += fib;
    }

    return {
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'fiber': fiber,
    };
  }
}
