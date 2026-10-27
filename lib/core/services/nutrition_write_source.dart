/// Origin of a `NutritionWriteService.logMeal` call. Determines which
/// usage counter (if any) increments after a successful write.
///
/// Free, unlimited sources (manualSearch / barcode / savedMealRelog /
/// prelog) do NOT increment any counter. AI/vision sources do.
enum NutritionWriteSource {
  /// Add-from-search row in the Log Food sheet.
  manualSearch,

  /// "Describe what you ate" AI text mode in Log Food sheet.
  aiText,

  /// Photo-of-plate scan flow (`_ScanResultEditor.save`).
  scan,

  /// Grocery cart audit save flow.
  cart,

  /// Barcode lookup save flow.
  barcode,

  /// Re-log of a saved meal template from SAVED MEALS tab.
  savedMealRelog,

  /// AI coach `logMealByText` tool dispatch (server-confirmed text).
  aiCoachTool,

  /// AI coach `prelog` tool dispatch (planned-meal stash).
  prelog,
}

/// Input model shared by every `logMeal` callsite. Fields mirror the
/// per-item shape persisted in the `items[]` array of an `nlog_*` Hive
/// row AND each `nutrition_log_items` cloud row.
///
/// `quantityG` is grams of food consumed; macros are absolute totals
/// for that quantity (NOT per-100g — Atwater 4/4/9 is a fallback only
/// when calories is 0 in payload).
class FoodItem {
  final String name;
  final double quantityG;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;

  const FoodItem({
    required this.name,
    required this.quantityG,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fiber,
  });

  /// Atwater-fallback kcal for cases where AI returned 0 in `calories`.
  double get kcalWithFallback =>
      calories > 0 ? calories : (4 * protein) + (4 * carbs) + (9 * fat);

  Map<String, dynamic> toMap() => {
        'name': name,
        'quantity_g': quantityG,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'fiber': fiber,
      };

  factory FoodItem.fromMap(Map<String, dynamic> m) => FoodItem(
        name: (m['name'] ?? '') as String,
        quantityG: ((m['quantity_g'] ?? 0) as num).toDouble(),
        calories: ((m['calories'] ?? 0) as num).toDouble(),
        protein: ((m['protein'] ?? 0) as num).toDouble(),
        carbs: ((m['carbs'] ?? 0) as num).toDouble(),
        fat: ((m['fat'] ?? 0) as num).toDouble(),
        fiber: ((m['fiber'] ?? 0) as num).toDouble(),
      );
}
