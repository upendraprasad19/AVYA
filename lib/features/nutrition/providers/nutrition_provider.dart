import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/core/services/badge_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/repositories/food_repository.dart';
import 'package:icanbefitter/features/nutrition/repositories/nutrition_repository.dart';
import 'package:uuid/uuid.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';

// ── Helpers ──────────────────────────────────────────────────────

/// Resolves nutrition targets from profile, falling back to BmrCalculator
/// when computed fields are missing. Only uses hardcoded defaults as a
/// last resort when even BMR inputs are unavailable.
///
/// When [date] is provided, an active calorie-target override (written by
/// the AI coach `adjustCaloricTarget` tool) is applied to `daily_calories`.
/// Macro targets (protein/carb/fat) are NOT scaled — the override is a
/// signed kcal delta only, intentionally narrow in scope. Result is
/// clamped to [800, 6000] for safety.
Map<String, double> _resolveNutritionTargets(
  Map<String, dynamic>? profile, {
  DateTime? date,
}) {
  Map<String, double> targets;

  if (profile != null &&
      profile['daily_calories'] != null &&
      profile['protein_grams'] != null &&
      profile['carb_grams'] != null &&
      profile['fat_grams'] != null) {
    targets = {
      'daily_calories': (profile['daily_calories'] as num).toDouble(),
      'protein_grams': (profile['protein_grams'] as num).toDouble(),
      'carb_grams': (profile['carb_grams'] as num).toDouble(),
      'fat_grams': (profile['fat_grams'] as num).toDouble(),
    };
    return _applyCalorieOverride(targets, date);
  }

  // Try to recalculate from profile inputs.
  if (profile != null) {
    final weightKg = (profile['current_weight_kg'] as num?)?.toDouble();
    final heightCm = (profile['height_cm'] as num?)?.toDouble();
    final gender = profile['gender'] as String?;
    if (weightKg != null && weightKg > 0 && heightCm != null && heightCm > 0 && gender != null) {
      final goal = profile['primary_goal'] as String? ?? 'general_fitness';
      final activityLevel = profile['activity_level'] as String? ?? 'moderate';
      final dob = profile['date_of_birth'] as String?;
      int age = 25;
      if (dob != null) {
        final birthDate = DateTime.tryParse(dob);
        if (birthDate != null) {
          final now = DateTime.now();
          age = now.year - birthDate.year;
          if (now.month < birthDate.month || (now.month == birthDate.month && now.day < birthDate.day)) {
            age--;
          }
          if (age <= 0) age = 25;
        }
      }
      final bodyFat = (profile['body_fat_percent'] as num?)?.toDouble();
      final targets = BmrCalculator.calculateTargets(
        weightKg: weightKg,
        heightCm: heightCm,
        age: age,
        gender: gender,
        activityLevel: activityLevel,
        goal: goal,
        pacePreference: (profile['pace_preference'] as String?) ?? 'balanced',
        bodyFatPercent: bodyFat,
      );
      return _applyCalorieOverride({
        'daily_calories': targets.dailyCalories.toDouble(),
        'protein_grams': targets.proteinGrams.toDouble(),
        'carb_grams': targets.carbGrams.toDouble(),
        'fat_grams': targets.fatGrams.toDouble(),
      }, date);
    }
  }

  // Last resort hardcoded defaults.
  return _applyCalorieOverride({
    'daily_calories': 2400,
    'protein_grams': 184,
    'carb_grams': 280,
    'fat_grams': 80,
  }, date);
}

/// Applies an active `target_override_<date>` calorie delta to the
/// resolved targets map. Macros are intentionally NOT scaled (the AI
/// coach tool only ships a kcal delta). Result clamped to [800, 6000].
/// Returns the input map unchanged when [date] is null or no active
/// override exists.
Map<String, double> _applyCalorieOverride(
  Map<String, double> targets,
  DateTime? date,
) {
  if (date == null) return targets;
  final override = NutritionRepository.instance.getActiveTargetOverride(date);
  if (override == null) return targets;
  final delta = (override['delta_kcal'] as num?)?.toDouble() ?? 0;
  final base = targets['daily_calories'] ?? 0;
  final adjusted = (base + delta).clamp(800, 6000).toDouble();
  return {
    ...targets,
    'daily_calories': adjusted,
  };
}

/// Estimates nutrition for a meal description when AI analysis fails.
/// Uses simple keyword matching to classify meal type.
// ignore: unused_element
AiBreakdownData _estimateMealNutrition(String text) {
  final lower = text.toLowerCase();

  int kcal;
  int protein;
  int carbs;
  int fat;

  // ── Specific food matches (checked first for accuracy) ──────────
  if (_containsAny(lower, ['whey', 'protein powder', 'protein shake', 'protein supplement'])) {
    // ~1.5 scoops = 45g whey protein powder
    final scoops = _extractNumber(lower, ['scoop', 'scoops']) ?? 1.5;
    final factor = scoops / 1.0;
    kcal = (120 * factor).round(); protein = (25 * factor).round(); carbs = (3 * factor).round(); fat = (2 * factor).round();
  } else if (_containsAny(lower, ['egg', 'eggs', 'anda'])) {
    final count = _extractNumber(lower, ['egg', 'eggs', 'anda']) ?? 2.0;
    kcal = (70 * count).round(); protein = (6 * count).round(); carbs = 0; fat = (5 * count).round();
  } else if (_containsAny(lower, ['roti', 'chapati', 'chapatti'])) {
    final count = _extractNumber(lower, ['roti', 'chapati']) ?? 2.0;
    kcal = (100 * count).round(); protein = (3 * count).round(); carbs = (18 * count).round(); fat = (2 * count).round();
  } else if (_containsAny(lower, ['paneer'])) {
    final grams = _extractNumber(lower, ['g', 'gram', 'grams']) ?? 100.0;
    final factor = grams / 100;
    kcal = (265 * factor).round(); protein = (18 * factor).round(); carbs = (4 * factor).round(); fat = (20 * factor).round();
  } else if (_containsAny(lower, ['dal', 'daal', 'lentil'])) {
    final factor = _extractNumber(lower, ['bowl', 'bowls']) ?? 1.0;
    kcal = (180 * factor).round(); protein = (12 * factor).round(); carbs = (28 * factor).round(); fat = (2 * factor).round();
  } else if (_containsAny(lower, ['rice', 'chawal'])) {
    final factor = _extractNumber(lower, ['cup', 'bowl']) ?? 1.0;
    kcal = (200 * factor).round(); protein = (4 * factor).round(); carbs = (44 * factor).round(); fat = (0);
  } else if (_containsAny(lower, ['banana', 'kela'])) {
    final count = _extractNumber(lower, ['banana', 'bananas']) ?? 1.0;
    kcal = (90 * count).round(); protein = (1 * count).round(); carbs = (23 * count).round(); fat = 0;
  } else if (_containsAny(lower, ['chicken breast', 'grilled chicken'])) {
    final grams = _extractNumber(lower, ['g', 'gram', 'grams']) ?? 150.0;
    final factor = grams / 100;
    kcal = (165 * factor).round(); protein = (31 * factor).round(); carbs = 0; fat = (4 * factor).round();
  } else if (_containsAny(lower, ['milk', 'doodh'])) {
    final ml = _extractNumber(lower, ['ml', 'glass', 'cup']) ?? 1.0;
    final factor = (lower.contains('ml') ? ml : ml * 240) / 100;
    kcal = (61 * factor).round(); protein = (3 * factor).round(); carbs = (5 * factor).round(); fat = (3 * factor).round();
  // ── Meal-type estimates ─────────────────────────────────────────
  } else if (_containsAny(lower, ['breakfast', 'morning', 'oats', 'cereal', 'paratha', 'poha', 'idli', 'dosa', 'upma', 'toast'])) {
    kcal = 400; protein = 20; carbs = 50; fat = 15;
  } else if (_containsAny(lower, ['lunch', 'afternoon', 'thali', 'sabzi'])) {
    kcal = 600; protein = 30; carbs = 70; fat = 20;
  } else if (_containsAny(lower, ['dinner', 'night', 'curry', 'fish', 'mutton'])) {
    kcal = 700; protein = 35; carbs = 80; fat = 25;
  } else {
    // Default snack estimate.
    kcal = 200; protein = 8; carbs = 25; fat = 6;
  }

  return AiBreakdownData(
    mealName: text,
    totalKcal: kcal,
    items: [
      AiFoodItem(
        name: text,
        quantity: '1 serving (estimated)',
        calories: kcal,
        protein: '${protein}g',
        carbs: '${carbs}g',
        fat: '${fat}g',
      ),
    ],
  );
}

bool _containsAny(String text, List<String> keywords) {
  for (final kw in keywords) {
    if (text.contains(kw)) return true;
  }
  return false;
}

/// Extracts a leading number before any of the given unit words.
/// e.g. "1.5 scoops whey" → 1.5 (when units=['scoop','scoops'])
/// Returns null if no number found near those units.
double? _extractNumber(String text, List<String> units) {
  for (final unit in units) {
    final pattern = RegExp(r'(\d+(?:\.\d+)?)\s*' + RegExp.escape(unit));
    final match = pattern.firstMatch(text);
    if (match != null && match.group(1) != null) {
      return double.tryParse(match.group(1)!);
    }
  }
  // Also look for a leading number anywhere in text
  final leadingNum = RegExp(r'^(\d+(?:\.\d+)?)').firstMatch(text.trim());
  if (leadingNum != null && leadingNum.group(1) != null) {
    return double.tryParse(leadingNum.group(1)!);
  }
  return null;
}

// ── Selected Date ────────────────────────────────────────────────

class SelectedDateNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime.now();

  void select(DateTime date) => state = date;

  void previousDay() => state = state.subtract(const Duration(days: 1));

  void nextDay() {
    final tomorrow = state.add(const Duration(days: 1));
    if (!tomorrow.isAfter(DateTime.now())) {
      state = tomorrow;
    }
  }
}

final selectedDateProvider =
    NotifierProvider<SelectedDateNotifier, DateTime>(SelectedDateNotifier.new);

// ── Daily Nutrition ──────────────────────────────────────────────

class DailyNutritionData {
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
  final double calorieTarget;
  final double proteinTarget;
  final double carbTarget;
  final double fatTarget;
  final double fiberTarget;
  final Map<String, List<Map<String, dynamic>>> meals;

  const DailyNutritionData({
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.fiber = 0,
    this.calorieTarget = 2400,
    this.proteinTarget = 184,
    this.carbTarget = 280,
    this.fatTarget = 80,
    this.fiberTarget = 30,
    this.meals = const {},
  });

  /// Flat list of all meals for display in "Today's Meals" section.
  List<Map<String, dynamic>> get allMeals {
    final result = <Map<String, dynamic>>[];
    for (final entry in meals.entries) {
      for (final item in entry.value) {
        result.add({...item, 'meal_type_label': entry.key});
      }
    }
    return result;
  }
}

class DailyNutritionNotifier extends Notifier<DailyNutritionData> {
  @override
  DailyNutritionData build() {
    final selectedDate = ref.watch(selectedDateProvider);
    final dateStr =
        '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';

    // F7 · Single source of truth for summed macros.
    final macros = NutritionRepository.instance.dailyMacros(selectedDate);
    final calories = (macros['calories'] as num?)?.toDouble() ?? 0.0;
    final protein = (macros['protein'] as num?)?.toDouble() ?? 0.0;
    final carbs = (macros['carbs'] as num?)?.toDouble() ?? 0.0;
    final fat = (macros['fat'] as num?)?.toDouble() ?? 0.0;
    final fiber = (macros['fiber'] as num?)?.toDouble() ?? 0.0;

    // Build meal breakdown (this provider's unique responsibility — not
    // relevant to Home). Same box, same date filter.
    final nutritionBox = HiveService.instance.nutritionBox;
    final meals = <String, List<Map<String, dynamic>>>{
      'breakfast': [],
      'lunch': [],
      'dinner': [],
      'snacks': [],
    };
    for (final raw in nutritionBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['date'] != dateStr) continue;
      if (log['is_saved_meal'] == true) continue;
      final mealType =
          (log['meal_type'] as String?)?.toLowerCase() ?? 'snacks';
      final key = meals.containsKey(mealType) ? mealType : 'snacks';
      meals[key]!.add(log);
    }

    final profile = UserRepository.instance.getProfile();
    // Pass selectedDate so any active calorie-target override (AI coach
    // adjustCaloricTarget tool) is applied for the displayed day.
    final targets = _resolveNutritionTargets(profile, date: selectedDate);
    final calorieTarget = targets['daily_calories']!;
    final proteinTarget = targets['protein_grams']!;
    final carbTarget = targets['carb_grams']!;
    final fatTarget = targets['fat_grams']!;
    final fiberTarget = (profile?['fiber_grams'] as num?)?.toDouble() ?? 30;

    return DailyNutritionData(
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      fiber: fiber,
      calorieTarget: calorieTarget,
      proteinTarget: proteinTarget,
      carbTarget: carbTarget,
      fatTarget: fatTarget,
      fiberTarget: fiberTarget,
      meals: meals,
    );
  }
}

final dailyNutritionProvider =
    NotifierProvider<DailyNutritionNotifier, DailyNutritionData>(
        DailyNutritionNotifier.new);

// ── Macro Targets ────────────────────────────────────────────────

class MacroTargetsNotifier extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() {
    final profile = UserRepository.instance.getProfile();
    final targets = _resolveNutritionTargets(profile);
    return {
      'bmr': (profile?['bmr'] as num?)?.toDouble() ?? 0,
      'tdee': (profile?['tdee'] as num?)?.toDouble() ?? 0,
      'calories': targets['daily_calories']!,
      'protein': targets['protein_grams']!,
      'carbs': targets['carb_grams']!,
      'fat': targets['fat_grams']!,
    };
  }
}

final macroTargetsProvider =
    NotifierProvider<MacroTargetsNotifier, Map<String, double>>(
        MacroTargetsNotifier.new);

// ── Water Intake (ml-based) ─────────────────────────────────────

class WaterIntakeNotifier extends Notifier<int> {
  @override
  int build() {
    final healthBox = HiveService.instance.healthBox;
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final raw = healthBox.get('water_ml_$todayStr');
    return (raw as int?) ?? 0;
  }

  Future<void> addWater(int ml) async {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    state = (state + ml).clamp(0, 5000);
    await HiveService.instance.healthBox.put('water_ml_$todayStr', state);
    // Fire-and-forget cloud sync + AI coach snapshot refresh.
    unawaited(SyncService.instance.syncNutritionData());
    unawaited(SyncService.instance.pushSnapshot());
  }

  Future<void> increment() async => addWater(250);

  Future<void> decrement() async {
    if (state <= 0) return;
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    state = (state - 250).clamp(0, 5000);
    await HiveService.instance.healthBox.put('water_ml_$todayStr', state);
    unawaited(SyncService.instance.syncNutritionData());
    unawaited(SyncService.instance.pushSnapshot());
  }
}

final waterIntakeProvider =
    NotifierProvider<WaterIntakeNotifier, int>(WaterIntakeNotifier.new);

// ── Water Unit Toggle ───────────────────────────────────────────

class WaterUnitNotifier extends Notifier<String> {
  @override
  String build() => 'ml';

  void toggle(String unit) => state = unit;
}

final waterUnitProvider =
    NotifierProvider<WaterUnitNotifier, String>(WaterUnitNotifier.new);

// ── Urine Color Selection ───────────────────────────────────────

class UrineColorNotifier extends Notifier<int> {
  static const _labels = [
    'Pale straw', 'Clear yellow', 'Yellow', 'Dark yellow',
    'Amber', 'Brown', 'Dark brown',
  ];

  @override
  int build() {
    // Restore today's selection from Hive if previously saved.
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final saved = HiveService.instance.healthBox.get('urine_color_$todayStr');
    if (saved is Map) {
      return (saved['index'] as int?) ?? -1;
    }
    return -1; // -1 means none selected
  }

  void select(int index) {
    state = index;
    // Persist to Hive for data analysis
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    HiveService.instance.healthBox.put('urine_color_$todayStr', {
      'type': 'urine_color',
      'date': todayStr,
      'index': index,
      'label': index >= 0 && index < _labels.length ? _labels[index] : 'unknown',
      'recorded_at': now.toIso8601String(),
    });
    // Refresh AI coach snapshot — urine color is part of the hydration
    // context the coach uses for dehydration warnings.
    unawaited(SyncService.instance.pushSnapshot());
  }
}

final urineColorProvider =
    NotifierProvider<UrineColorNotifier, int>(UrineColorNotifier.new);

// ── Hydration Save State ────────────────────────────────────────

class HydrationSaveNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> save() async {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final waterMl = ref.read(waterIntakeProvider);
    final urineIdx = ref.read(urineColorProvider);

    await HiveService.instance.healthBox.put('hydration_$todayStr', {
      'water_ml': waterMl,
      'urine_color_index': urineIdx,
      'saved_at': now.toIso8601String(),
    });

    state = true;
    await Future.delayed(const Duration(milliseconds: 2500));
    state = false;
  }
}

final hydrationSaveProvider =
    NotifierProvider<HydrationSaveNotifier, bool>(HydrationSaveNotifier.new);

// ── Food Search ──────────────────────────────────────────────────

class FoodSearchNotifier extends Notifier<List<Map<String, dynamic>>> {
  @override
  List<Map<String, dynamic>> build() => [];

  void search(String query) {
    if (query.trim().isEmpty) {
      state = [];
      return;
    }
    state = FoodRepository.instance.search(query, limit: 30);
  }

  void clear() => state = [];
}

final foodSearchProvider =
    NotifierProvider<FoodSearchNotifier, List<Map<String, dynamic>>>(
        FoodSearchNotifier.new);

// ── AI Analysis State ───────────────────────────────────────────

class AiBreakdownData {
  final String mealName;
  final int totalKcal;
  final List<AiFoodItem> items;
  final String? error;

  const AiBreakdownData({
    required this.mealName,
    required this.totalKcal,
    required this.items,
    this.error,
  });

  AiBreakdownData copyWith({
    String? mealName,
    int? totalKcal,
    List<AiFoodItem>? items,
    String? error,
  }) {
    return AiBreakdownData(
      mealName: mealName ?? this.mealName,
      totalKcal: totalKcal ?? this.totalKcal,
      items: items ?? this.items,
      error: error ?? this.error,
    );
  }
}

class AiFoodItem {
  final String name;
  final String quantity;
  final int calories;
  final String protein;
  final String carbs;
  final String fat;
  final int fiber;

  const AiFoodItem({
    required this.name,
    required this.quantity,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.fiber = 0,
  });

  AiFoodItem copyWith({
    String? name,
    String? quantity,
    int? calories,
    String? protein,
    String? carbs,
    String? fat,
    int? fiber,
  }) {
    return AiFoodItem(
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
      fiber: fiber ?? this.fiber,
    );
  }
}

class AiBreakdownNotifier extends Notifier<AiBreakdownData?> {
  @override
  AiBreakdownData? build() => null;

  /// Calls Edge Function for AI text analysis.
  /// Falls back to mock data if Edge Function is unreachable.
  Future<void> analyse(String text) async {
    try {
      // F11 — refresh subscription cache to avoid stale-PRO/free state after restore.
      // Cheap (~50ms hit if cache miss); resolves the most-likely cause of
      // rate-limit trigger firing on a user who's actually under their daily cap.
      try {
        await SubscriptionService.instance.verifyFromServer();
      } catch (_) {
        // Non-fatal — continue with cached state. Server-side trigger is the
        // authoritative gate.
      }

      final response = await SupabaseService.instance.callFunction(
        AppConstants.aiProxyFunction,
        body: {
          'type': 'food_text_analysis',
          'text': text,
        },
      );

      if (response.status == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String) as Map<String, dynamic>
            : response.data as Map<String, dynamic>;

        final items = (data['items'] as List<dynamic>?)
                ?.map((item) => AiFoodItem(
                      name: item['name'] as String? ?? 'Unknown',
                      quantity: item['quantity'] as String? ?? '1 serving',
                      calories: (item['calories'] as num?)?.toInt() ?? 0,
                      protein: '${(item['protein'] as num?)?.toInt() ?? 0}g',
                      carbs: '${(item['carbs'] as num?)?.toInt() ?? 0}g',
                      fat: '${(item['fat'] as num?)?.toInt() ?? 0}g',
                      fiber: (item['fiber'] as num?)?.toInt() ?? 0,
                    ))
                .toList() ??
            [];

        final totalKcal =
            items.fold<int>(0, (sum, item) => sum + item.calories);

        state = AiBreakdownData(
          mealName: data['meal_name'] as String? ?? text,
          totalKcal: totalKcal,
          items: items,
        );
        return;
      }
    } catch (e, stack) {
      // F11 — detailed instrumentation for food analysis failures
      if (kDebugMode) {
        debugPrint('[F11 food_analysis] error: $e');
        debugPrint('[F11 food_analysis] stack: $stack');
      }

      final msg = e.toString().toLowerCase();
      final isAuthError = msg.contains('401') || msg.contains('token') ||
                          msg.contains('unauthorized') || msg.contains('jwt') ||
                          msg.contains('no active session') || msg.contains('session expired');
      final isServiceError = msg.contains('503') || msg.contains('502') ||
                             msg.contains('unavailable') || msg.contains('non-2xx') ||
                             msg.contains('food ai') || msg.contains('food analysis failed');
      final isRateLimitError = msg.contains('food_text_daily_limit_reached') ||
                               msg.contains('daily food analysis limit') ||
                               msg.contains('429') || msg.contains('rate limit');
      final isMessageTooLong = msg.contains('message too long') ||
                               msg.contains('exceeds maximum');
      final isSnapshotTooLarge = msg.contains('snapshot too large') ||
                                 msg.contains('context too large');

      // Auto-refresh session on auth error (same pattern as AI Coach).
      // User can tap "Analyse & Log" again without signing out.
      if (isAuthError) {
        try {
          await SupabaseService.instance.client.auth.refreshSession();
          debugPrint('[NutritionProvider] Session refreshed — user can retry.');
        } catch (refreshErr) {
          debugPrint('[NutritionProvider] Session refresh failed: $refreshErr');
        }
      }

      final errorMsg = isRateLimitError
          ? 'Daily food analysis limit reached. Try again tomorrow or upgrade to PRO.'
          : isAuthError
              ? 'Session refreshed. Please tap Analyse again.'
              : isMessageTooLong
                  ? 'That description is too long (max 5000 chars). Please shorten it.'
                  : isSnapshotTooLarge
                      ? 'Your nutrition data is unusually large. Please try a shorter question.'
                      : isServiceError
                          ? 'The AI is temporarily unavailable. Please try again in a minute.'
                          : 'Could not analyse that. Please try a clearer description.';
      state = AiBreakdownData(
        mealName: text,
        totalKcal: 0,
        items: [],
        error: errorMsg,
      );
      return;
    }

    // Edge Function returned non-200 — show error
    state = AiBreakdownData(
      mealName: text,
      totalKcal: 0,
      items: [],
      error: 'Could not analyse this meal. Please try again.',
    );
  }

  /// Update a single item's macros (called from the edit icon in the breakdown card).
  void updateItem(int index, {required int calories, required int protein, required int carbs, required int fat, int? fiber}) {
    final data = state;
    if (data == null || index < 0 || index >= data.items.length) return;
    final newItems = List<AiFoodItem>.from(data.items);
    newItems[index] = newItems[index].copyWith(
      calories: calories,
      protein: '${protein}g',
      carbs: '${carbs}g',
      fat: '${fat}g',
      fiber: fiber,
    );
    final newTotalKcal = newItems.fold<int>(0, (sum, item) => sum + item.calories);
    state = data.copyWith(items: newItems, totalKcal: newTotalKcal);
  }

  void clear() => state = null;

  /// Save the analysed meal to nutrition log.
  Future<void> saveMeal({String mealType = 'snacks'}) async {
    final data = state;
    if (data == null) return;

    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    int totalProtein = 0;
    int totalCarbs = 0;
    int totalFat = 0;
    int totalFiber = 0;
    for (final item in data.items) {
      totalProtein += int.tryParse(item.protein.replaceAll('g', '')) ?? 0;
      totalCarbs += int.tryParse(item.carbs.replaceAll('g', '')) ?? 0;
      totalFat += int.tryParse(item.fat.replaceAll('g', '')) ?? 0;
      totalFiber += item.fiber;
    }

    final id = 'nlog_${now.millisecondsSinceEpoch}';
    final logMap = {
      'id': id,
      'date': dateStr,
      'meal_type': mealType.toLowerCase(),
      'food_name': data.mealName,
      'total_calories': data.totalKcal,
      'total_protein': totalProtein,
      'total_carbs': totalCarbs,
      'total_fat': totalFat,
      'total_fiber': totalFiber,
      'created_at': now.toIso8601String(),
      'source': 'ai_text',
    };
    await HiveService.instance.nutritionBox.put(id, logMap);
    NutritionRepository.syncLogToSupabase(data: logMap);
    // AI coach snapshot refresh — keeps "what did I eat today?" accurate
    // without waiting for the next app launch.
    unawaited(SyncService.instance.pushSnapshot());

    state = null;
    ref.invalidate(dailyNutritionProvider);
    ref.invalidate(weeklyNutritionProvider);
    ref.invalidate(nutritionSummaryProvider);
    ref.invalidate(recentFoodLogsProvider);
    BadgeService.instance.checkAll();
  }
}

final aiBreakdownProvider =
    NotifierProvider<AiBreakdownNotifier, AiBreakdownData?>(
        AiBreakdownNotifier.new);

// ── AI Analysing Loader ─────────────────────────────────────────

class AiAnalysingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool val) => state = val;
}

final aiAnalysingProvider =
    NotifierProvider<AiAnalysingNotifier, bool>(AiAnalysingNotifier.new);

// ── Log Food ─────────────────────────────────────────────────────

class FoodLogNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<void> logFood({
    required Map<String, dynamic> food,
    required String mealType,
    required double quantityG,
  }) async {
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final id = 'nlog_${now.millisecondsSinceEpoch}';

    final caloriesPer100 =
        (food['calories_per_100g'] as num?)?.toDouble() ?? 0;
    final proteinPer100 =
        (food['protein_per_100g'] as num?)?.toDouble() ?? 0;
    final carbsPer100 = (food['carbs_per_100g'] as num?)?.toDouble() ?? 0;
    final fatPer100 = (food['fat_per_100g'] as num?)?.toDouble() ?? 0;
    final fiberPer100 = (food['fiber_per_100g'] as num?)?.toDouble() ?? 0;

    final factor = quantityG / 100.0;

    final logMap = {
      'id': id,
      'date': dateStr,
      'meal_type': mealType.toLowerCase(),
      'food_id': food['id'],
      'food_name': food['name'] ?? 'Unknown',
      'quantity_g': quantityG,
      'total_calories': (caloriesPer100 * factor).round(),
      'total_protein': (proteinPer100 * factor).round(),
      'total_carbs': (carbsPer100 * factor).round(),
      'total_fat': (fatPer100 * factor).round(),
      'total_fiber': (fiberPer100 * factor).round(),
      'created_at': now.toIso8601String(),
      'source': 'manual',
    };
    await HiveService.instance.nutritionBox.put(id, logMap);
    NutritionRepository.syncLogToSupabase(data: logMap);
    unawaited(SyncService.instance.pushSnapshot());

    ref.invalidate(dailyNutritionProvider);
    ref.invalidate(weeklyNutritionProvider);
    ref.invalidate(nutritionSummaryProvider);
    ref.invalidate(recentFoodLogsProvider);
    BadgeService.instance.checkAll();
  }

  Future<void> deleteFoodLog(String logId) async {
    await HiveService.instance.nutritionBox.delete(logId);
    // Delete is a mutation too — AI coach needs to see the correction.
    unawaited(SyncService.instance.syncNutritionData());
    unawaited(SyncService.instance.pushSnapshot());
    ref.invalidate(dailyNutritionProvider);
    ref.invalidate(weeklyNutritionProvider);
    ref.invalidate(nutritionSummaryProvider);
    ref.invalidate(recentFoodLogsProvider);
  }

  /// Bug #20 — Restores a previously-deleted food log from an undo snackbar.
  /// Writes back at the original Hive key carried on `log['id']` so the
  /// restored row lands exactly where the delete removed it from — preserving
  /// the Supabase sync linkage. Fires sync + snapshot so the AI coach sees
  /// the correction.
  Future<void> restoreFoodLog(Map<String, dynamic> log) async {
    final key = log['id'] as String?;
    if (key == null) return;
    await HiveService.instance.nutritionBox.put(key, log);

    unawaited(SyncService.instance.syncNutritionData());
    unawaited(SyncService.instance.pushSnapshot());
    ref.invalidate(dailyNutritionProvider);
    ref.invalidate(weeklyNutritionProvider);
    ref.invalidate(nutritionSummaryProvider);
    ref.invalidate(recentFoodLogsProvider);
  }

  Future<void> updateFoodLog({
    required String logId,
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    double fiber = 0,
  }) async {
    final box = HiveService.instance.nutritionBox;
    final existing = box.get(logId);
    if (existing == null) return;
    final updated = Map<String, dynamic>.from(existing as Map);
    updated['total_calories'] = calories.round();
    updated['total_protein'] = protein.round();
    updated['total_carbs'] = carbs.round();
    updated['total_fat'] = fat.round();
    updated['total_fiber'] = fiber.round();
    await box.put(logId, updated);
    NutritionRepository.syncLogToSupabase(data: updated);
    unawaited(SyncService.instance.pushSnapshot());
    ref.invalidate(dailyNutritionProvider);
    ref.invalidate(weeklyNutritionProvider);
    ref.invalidate(nutritionSummaryProvider);
    ref.invalidate(recentFoodLogsProvider);
  }
}

final foodLogProvider =
    NotifierProvider<FoodLogNotifier, void>(FoodLogNotifier.new);

// ── Saved Meals ──────────────────────────────────────────────────

class SavedMealsNotifier extends Notifier<List<Map<String, dynamic>>> {
  @override
  List<Map<String, dynamic>> build() {
    final nutritionBox = HiveService.instance.nutritionBox;
    final results = <Map<String, dynamic>>[];

    for (final raw in nutritionBox.values) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      if (item['is_saved_meal'] == true) {
        results.add(item);
      }
    }

    results.sort((a, b) {
      final aUsed = (a['times_used'] as int?) ?? 0;
      final bUsed = (b['times_used'] as int?) ?? 0;
      return bUsed.compareTo(aUsed);
    });

    return results;
  }

  /// Save the current AI breakdown as a reusable saved meal.
  Future<void> saveMealPreset({
    required String name,
    required int totalCalories,
    required int totalProtein,
    required int totalCarbs,
    required int totalFat,
    required List<Map<String, dynamic>> items,
  }) async {
    final now = DateTime.now();
    final id = 'saved_meal_${now.millisecondsSinceEpoch}';

    await HiveService.instance.nutritionBox.put(id, {
      'id': id,
      'is_saved_meal': true,
      'name': name,
      'total_calories': totalCalories,
      'total_protein': totalProtein,
      'total_carbs': totalCarbs,
      'total_fat': totalFat,
      'items': items,
      'times_used': 0,
      'created_at': now.toIso8601String(),
    });

    ref.invalidateSelf();
    unawaited(SyncService.instance.syncNutritionData());
    unawaited(SyncService.instance.pushSnapshot());
  }

  /// Re-log a saved meal.
  Future<void> relogSavedMeal(Map<String, dynamic> savedMeal,
      {String mealType = 'snacks'}) async {
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final id = 'nlog_${now.millisecondsSinceEpoch}';

    final logMap = {
      'id': id,
      'date': dateStr,
      'meal_type': mealType.toLowerCase(),
      'food_name': savedMeal['name'] ?? 'Saved Meal',
      'total_calories': savedMeal['total_calories'] ?? 0,
      'total_protein': savedMeal['total_protein'] ?? 0,
      'total_carbs': savedMeal['total_carbs'] ?? 0,
      'total_fat': savedMeal['total_fat'] ?? 0,
      'created_at': now.toIso8601String(),
      'source': 'saved_meal',
    };
    await HiveService.instance.nutritionBox.put(id, logMap);
    NutritionRepository.syncLogToSupabase(data: logMap);
    unawaited(SyncService.instance.pushSnapshot());

    // Increment times_used counter on the saved meal
    final savedId = savedMeal['id'] as String?;
    if (savedId != null) {
      final existing = HiveService.instance.nutritionBox.get(savedId);
      if (existing is Map) {
        final updated = Map<String, dynamic>.from(existing);
        updated['times_used'] = ((updated['times_used'] as int?) ?? 0) + 1;
        await HiveService.instance.nutritionBox.put(savedId, updated);
      }
    }

    ref.invalidate(dailyNutritionProvider);
    ref.invalidate(weeklyNutritionProvider);
    ref.invalidate(nutritionSummaryProvider);
    ref.invalidate(recentFoodLogsProvider);
    ref.invalidateSelf();
  }

  /// Delete a saved meal preset.
  Future<void> deleteSavedMeal(String id) async {
    await HiveService.instance.nutritionBox.delete(id);
    ref.invalidateSelf();
    unawaited(SyncService.instance.syncNutritionData());
    unawaited(SyncService.instance.pushSnapshot());
  }
}

final savedMealsProvider =
    NotifierProvider<SavedMealsNotifier, List<Map<String, dynamic>>>(
        SavedMealsNotifier.new);

// ── Custom Food ──────────────────────────────────────────────────

class CustomFoodNotifier extends Notifier<void> {
  @override
  void build() {}

  /// Add a custom food to customBox and sync to Supabase (background).
  Future<void> addCustomFood({
    required String name,
    required double caloriesPer100g,
    required double proteinPer100g,
    required double carbsPer100g,
    required double fatPer100g,
    double fiberPer100g = 0,
    String? servingDesc,
    double? servingG,
    bool submittedToDb = false,
  }) async {
    final now = DateTime.now();
    // Stable id (F22): deterministic v5 from (user_id, 'food', lower(name)).
    // Cloud upserts now dedupe correctly instead of inserting a new row on
    // every sync from every device.
    const customNs = '5a1f0b0c-9dad-11d1-80b4-00c04fd430c8';
    final userId = SupabaseService.instance.currentUser?.id ?? 'anon';
    final id = const Uuid().v5(customNs, '$userId|food|${name.toLowerCase()}');
    final hiveKey = 'custom_food_${now.millisecondsSinceEpoch}';
    final factor = (servingG ?? 100) / 100.0;

    final food = {
      'id': id,
      'name': name,
      'calories_per_100g': caloriesPer100g,
      'protein_per_100g': proteinPer100g,
      'carbs_per_100g': carbsPer100g,
      'fat_per_100g': fatPer100g,
      'fiber_per_100g': fiberPer100g,
      'standard_serving_desc': servingDesc ?? '100g',
      'standard_serving_g': servingG ?? 100,
      'calories_std': (caloriesPer100g * factor).round(),
      'protein_std': (proteinPer100g * factor).round(),
      'carbs_std': (carbsPer100g * factor).round(),
      'fat_std': (fatPer100g * factor).round(),
      'times_logged': 0,
      'type': 'food',
      'is_custom': true,
      'submitted_to_db': submittedToDb,
      'approved': false,
      'created_at': now.toIso8601String(),
    };

    // Save to customBox (keyed by timestamp for chronological iteration;
    // the `id` field is the stable deterministic uuid used for cloud sync).
    await HiveService.instance.customBox.put(hiveKey, food);

    // Also add to foodBox so it appears in search (keyed by stable id for
    // dedupe against future imports of the same food).
    await HiveService.instance.foodBox.put(id, food);

    // Background sync to Supabase
    NutritionRepository.syncCustomFoodToSupabase(data: food);
    unawaited(SyncService.instance.pushSnapshot());
  }
}

final customFoodProvider =
    NotifierProvider<CustomFoodNotifier, void>(CustomFoodNotifier.new);

// ── Meal Type Selector ──────────────────────────────────────────

class MealTypeNotifier extends Notifier<String> {
  @override
  String build() {
    // Time-windowed inference, matching `inferMealSlot` in
    // meal_slot_inference.dart. Kept inline here to avoid an import cycle
    // from the provider layer; keep windows in sync if edited.
    final now = DateTime.now();
    final mins = now.hour * 60 + now.minute;
    if (mins >= 5 * 60 && mins < 10 * 60 + 30) return 'breakfast';
    if (mins >= 11 * 60 + 30 && mins < 15 * 60 + 30) return 'lunch';
    if (mins >= 18 * 60 && mins < 22 * 60) return 'dinner';
    return 'snacks';
  }

  void select(String mealType) => state = mealType;
}

final mealTypeProvider =
    NotifierProvider<MealTypeNotifier, String>(MealTypeNotifier.new);

// ── Scan Meal State ─────────────────────────────────────────────

class ScanMealNotifier extends Notifier<ScanMealState> {
  @override
  ScanMealState build() => const ScanMealState();

  /// Process a meal image via Edge Function.
  Future<void> scanImage(List<int> imageBytes) async {
    state = state.copyWith(isScanning: true, error: null);

    try {
      final base64Image = base64Encode(imageBytes);

      final response = await SupabaseService.instance.callFunction(
        AppConstants.aiProxyFunction,
        body: {
          'type': 'scan_meal',
          'image': base64Image,
        },
      );

      if (response.status == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String) as Map<String, dynamic>
            : response.data as Map<String, dynamic>;

        state = state.copyWith(
          isScanning: false,
          result: data,
        );
        // Increment quota only on actual success — not on failure/error
        await UsageCounterService.instance.increment(
          AppConstants.featureScanMealPro,
          SubscriptionService.instance.isPro(),
        );
        return;
      }

      state = state.copyWith(
        isScanning: false,
        error: 'Could not analyse the image. Please try again.',
      );
    } catch (e) {
      state = state.copyWith(
        isScanning: false,
        error: 'Scan failed. Check your connection and try again.',
      );
    }
  }

  void clear() => state = const ScanMealState();
}

class ScanMealState {
  final bool isScanning;
  final Map<String, dynamic>? result;
  final String? error;

  const ScanMealState({
    this.isScanning = false,
    this.result,
    this.error,
  });

  ScanMealState copyWith({
    bool? isScanning,
    Map<String, dynamic>? result,
    String? error,
  }) {
    return ScanMealState(
      isScanning: isScanning ?? this.isScanning,
      result: result ?? this.result,
      error: error,
    );
  }
}

final scanMealProvider =
    NotifierProvider<ScanMealNotifier, ScanMealState>(ScanMealNotifier.new);

// ── Cart Auditor State ──────────────────────────────────────────

class CartAuditorNotifier extends Notifier<CartAuditorState> {
  @override
  CartAuditorState build() => const CartAuditorState();

  /// Process a grocery cart screenshot via Edge Function.
  Future<void> analyseCart(List<int> imageBytes) async {
    state = state.copyWith(isAnalysing: true, error: null);

    try {
      final base64Image = base64Encode(imageBytes);

      final response = await SupabaseService.instance.callFunction(
        AppConstants.aiProxyFunction,
        body: {
          'type': 'cart_auditor',
          'image': base64Image,
        },
      );

      if (response.status == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String) as Map<String, dynamic>
            : response.data as Map<String, dynamic>;

        state = state.copyWith(
          isAnalysing: false,
          result: data,
        );
        // Increment quota only on actual success — not on failure/error
        await UsageCounterService.instance.increment(
          AppConstants.featureCartAuditorPro,
          SubscriptionService.instance.isPro(),
        );
        return;
      }

      state = state.copyWith(
        isAnalysing: false,
        error: 'Could not analyse the cart. Please try again.',
      );
    } catch (e) {
      state = state.copyWith(
        isAnalysing: false,
        error: 'Analysis failed. Check your connection and try again.',
      );
    }
  }

  void clear() => state = const CartAuditorState();
}

class CartAuditorState {
  final bool isAnalysing;
  final Map<String, dynamic>? result;
  final String? error;

  const CartAuditorState({
    this.isAnalysing = false,
    this.result,
    this.error,
  });

  CartAuditorState copyWith({
    bool? isAnalysing,
    Map<String, dynamic>? result,
    String? error,
  }) {
    return CartAuditorState(
      isAnalysing: isAnalysing ?? this.isAnalysing,
      result: result ?? this.result,
      error: error,
    );
  }
}

final cartAuditorProvider =
    NotifierProvider<CartAuditorNotifier, CartAuditorState>(
        CartAuditorNotifier.new);

// ── Usage Counter Providers ─────────────────────────────────────

/// Returns remaining AI text log count for display.
final aiTextLogRemainingProvider = Provider<int>((ref) {
  final isPro = SubscriptionService.instance.isPro();
  return UsageCounterService.instance
      .remaining(AppConstants.featureAiTextLogPro, isPro);
});

/// Returns remaining scan meal count for display.
final scanMealRemainingProvider = Provider<int>((ref) {
  final isPro = SubscriptionService.instance.isPro();
  return UsageCounterService.instance
      .remaining(AppConstants.featureScanMealPro, isPro);
});

/// Returns remaining cart auditor count for display.
final cartAuditorRemainingProvider = Provider<int>((ref) {
  final isPro = SubscriptionService.instance.isPro();
  return UsageCounterService.instance
      .remaining(AppConstants.featureCartAuditorPro, isPro);
});

// ── Weekly Nutrition Data (real from Hive) ───────────────────────

class WeeklyNutritionData {
  final List<double> calories;
  final List<double> protein;
  final double avgCalories;
  final double avgProtein;
  final double calorieTarget;
  final double proteinTarget;
  /// True if the current week is incomplete (today is not Sunday).
  final bool isPartialWeek;

  const WeeklyNutritionData({
    this.calories = const [0, 0, 0, 0, 0, 0, 0],
    this.protein = const [0, 0, 0, 0, 0, 0, 0],
    this.avgCalories = 0,
    this.avgProtein = 0,
    this.calorieTarget = 2400,
    this.proteinTarget = 184,
    this.isPartialWeek = true,
  });
}

class WeeklyNutritionNotifier extends Notifier<WeeklyNutritionData> {
  @override
  WeeklyNutritionData build() {
    final nutritionBox = HiveService.instance.nutritionBox;
    final profile = UserRepository.instance.getProfile();
    final targets = _resolveNutritionTargets(profile);
    final calorieTarget = targets['daily_calories']!;
    final proteinTarget = targets['protein_grams']!;

    final now = DateTime.now();
    // Start of the week (Monday)
    final weekStart = now.subtract(Duration(days: now.weekday - 1));

    final weekCalories = <double>[0, 0, 0, 0, 0, 0, 0];
    final weekProtein = <double>[0, 0, 0, 0, 0, 0, 0];

    for (final raw in nutritionBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['is_saved_meal'] == true) continue;
      final dateStr = log['date'] as String?;
      if (dateStr == null) continue;

      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;

      final dayIdx = date.difference(weekStart).inDays;
      if (dayIdx < 0 || dayIdx > 6) continue;

      weekCalories[dayIdx] +=
          (log['total_calories'] as num?)?.toDouble() ?? 0;
      weekProtein[dayIdx] +=
          (log['total_protein'] as num?)?.toDouble() ?? 0;
    }

    int daysWithData = 0;
    double totalCals = 0;
    double totalProt = 0;
    for (int i = 0; i < 7; i++) {
      if (weekCalories[i] > 0) {
        daysWithData++;
        totalCals += weekCalories[i];
        totalProt += weekProtein[i];
      }
    }

    final avgCals = daysWithData > 0 ? totalCals / daysWithData : 0.0;
    final avgProt = daysWithData > 0 ? totalProt / daysWithData : 0.0;

    return WeeklyNutritionData(
      calories: weekCalories,
      protein: weekProtein,
      avgCalories: avgCals,
      avgProtein: avgProt,
      calorieTarget: calorieTarget,
      proteinTarget: proteinTarget,
      isPartialWeek: now.weekday != DateTime.sunday,
    );
  }
}

final weeklyNutritionProvider =
    NotifierProvider<WeeklyNutritionNotifier, WeeklyNutritionData>(
        WeeklyNutritionNotifier.new);

// ── Delete Nutrition Log ────────────────────────────────────────

class DeleteNutritionLogNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<void> delete(String logId) async {
    await HiveService.instance.nutritionBox.delete(logId);
    ref.invalidate(dailyNutritionProvider);
    ref.invalidate(weeklyNutritionProvider);
    unawaited(SyncService.instance.syncNutritionData());
    unawaited(SyncService.instance.pushSnapshot());
  }
}

final deleteNutritionLogProvider =
    NotifierProvider<DeleteNutritionLogNotifier, void>(
        DeleteNutritionLogNotifier.new);
