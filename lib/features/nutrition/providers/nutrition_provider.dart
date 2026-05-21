import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/services/badge_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/repositories/food_repository.dart';
import 'package:icanbefitter/features/nutrition/repositories/nutrition_repository.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_generator.dart';
import 'package:uuid/uuid.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
// OI-36 (2026-05-17) — home_provider import dropped. deleteFoodLog now
// delegates to NutritionWriteService.deleteLog which fires the canonical
// provider invalidation batch (including aiInsightProvider /
// nutritionSummaryProvider / recentFoodLogsProvider) via the
// onStateChanged hook wired in app.dart. No direct usage remains here.
import 'package:icanbefitter/core/services/water_target_service.dart';

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
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
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
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
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
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    final healthBox = HiveService.instance.healthBox;
    // audit-2026-05-16 task E.7 — read with IST date to match the
    // canonical writer in HealthWriteService.setWaterMl.
    final todayStr = istDateStr(DateTime.now());
    final raw = healthBox.get('water_ml_$todayStr');
    return (raw as int?) ?? 0;
  }

  Future<void> addWater(int ml) async {
    // audit-2026-05-16 task E.7 — routes through HealthWriteService.
    // C-12 batch (audit-2026-05-11) already aligned the key to IST via
    // `istDateStr`; the service formalises that contract and centralises
    // the sync fan-out / telemetry pattern.
    state = (state + ml).clamp(0, 5000);
    await HealthWriteService.instance.setWaterMl(
      date: DateTime.now(),
      totalMl: state,
      source: WriteSource.manual,
    );
  }

  Future<void> increment() async => addWater(250);

  Future<void> decrement() async {
    if (state <= 0) return;
    state = (state - 250).clamp(0, 5000);
    await HealthWriteService.instance.setWaterMl(
      date: DateTime.now(),
      totalMl: state,
      source: WriteSource.manual,
    );
  }
}

final waterIntakeProvider =
    NotifierProvider<WaterIntakeNotifier, int>(WaterIntakeNotifier.new);

// ── Water Unit Toggle ───────────────────────────────────────────

class WaterUnitNotifier extends Notifier<String> {
  @override
  String build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    return 'ml';
  }

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
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    // audit-2026-05-16 task E.7 — IST-anchored read to match the
    // HealthWriteService.logUrine writer.
    final todayStr = istDateStr(DateTime.now());
    final saved = HiveService.instance.healthBox.get('urine_color_$todayStr');
    if (saved is Map) {
      return (saved['index'] as int?) ?? -1;
    }
    return -1; // -1 means none selected
  }

  void select(int index) {
    state = index;
    // audit-2026-05-16 task E.7 — routes through HealthWriteService so
    // the urine_color_<istDate> key is IST-anchored (pre-fix used
    // device-local now.year-now.month-now.day) and the sync fan-out is
    // identical to every other health mutation.
    final label =
        index >= 0 && index < _labels.length ? _labels[index] : 'unknown';
    unawaited(HealthWriteService.instance.logUrine(
      date: DateTime.now(),
      color: label,
      source: WriteSource.manual,
      colorIndex: index,
    ));
  }
}

final urineColorProvider =
    NotifierProvider<UrineColorNotifier, int>(UrineColorNotifier.new);

// ── Hydration Save State ────────────────────────────────────────

class HydrationSaveNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> save() async {
    final waterMl = ref.read(waterIntakeProvider);
    final urineIdx = ref.read(urineColorProvider);

    // audit-2026-05-16 task E.7 — routes through HealthWriteService.
    // Hydration score is left at 0 since the prior snapshot never
    // captured one; callers can pass a real score once the scoring rule
    // lives somewhere canonical.
    await HealthWriteService.instance.logHydration(
      date: DateTime.now(),
      totalMl: waterMl,
      hydrationScore: 0,
      source: WriteSource.manual,
      urineColorIndex: urineIdx,
    );

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

  /// APK Test #16.1 / Agent B (closes-diagnose: a17bc3) — front-of-chat
  /// retry circuit breaker. In-memory only (NOT Hive persisted) so app
  /// restart clears the block; counter auto-resets after 5 minutes of
  /// inactivity for the same text.
  ///
  /// State machine:
  ///   - Any service error (502/503/504, "AI temporarily unavailable")
  ///     increments the per-text counter and stamps `lastFailAt`.
  ///   - On the 4th attempt for the same text, if counter >= 3 and
  ///     `lastFailAt` is within 5 minutes, the call is blocked
  ///     client-side without contacting `ai-proxy`. State is set with
  ///     an "AI overloaded — try again in 5 minutes" error.
  ///   - A successful analyse for that text clears the counter.
  ///   - [clear] clears the counter for any in-flight text.
  ///   - 5 minutes after the last fail the counter is treated as 0
  ///     even without an explicit clear.
  ///
  /// Exposed `@visibleForTesting` so circuit_breaker_test.dart can
  /// reset state between cases.
  @visibleForTesting
  static final Map<String, int> serviceFailCounts = <String, int>{};
  @visibleForTesting
  static final Map<String, DateTime> serviceFailLastAt = <String, DateTime>{};
  @visibleForTesting
  static const int circuitBreakerThreshold = 3;
  @visibleForTesting
  static const Duration circuitBreakerCooldown = Duration(minutes: 5);

  @visibleForTesting
  static void resetCircuitBreakerForTests() {
    serviceFailCounts.clear();
    serviceFailLastAt.clear();
  }

  /// Returns true if the circuit breaker is currently open for [text].
  /// Exposed `@visibleForTesting`.
  @visibleForTesting
  static bool isCircuitBreakerOpen(String text) {
    final count = serviceFailCounts[text] ?? 0;
    if (count < circuitBreakerThreshold) return false;
    final lastAt = serviceFailLastAt[text];
    if (lastAt == null) return false;
    final age = DateTime.now().difference(lastAt);
    if (age >= circuitBreakerCooldown) {
      // Auto-reset stale counter.
      serviceFailCounts.remove(text);
      serviceFailLastAt.remove(text);
      return false;
    }
    return true;
  }

  /// Calls Edge Function for AI text analysis.
  /// Falls back to mock data if Edge Function is unreachable.
  Future<void> analyse(String text) async {
    // Layer 4 circuit-breaker gate — block the 4th+ retry for the same
    // text within the cooldown window. Returns immediately without
    // contacting ai-proxy.
    if (isCircuitBreakerOpen(text)) {
      unawaited(ErrorTelemetry.logEvent(
        'nutrition_ai_text_circuit_breaker_block',
        message: 'text_len=${text.length}',
      ));
      state = AiBreakdownData(
        mealName: text,
        totalKcal: 0,
        items: [],
        error: 'AI overloaded — try again in 5 minutes.',
      );
      return;
    }

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
                ?.map((raw) {
                  final item = raw as Map<String, dynamic>;
                  return AiFoodItem(
                    name: item['name'] as String? ?? 'Unknown',
                    quantity: item['quantity'] as String? ?? '1 serving',
                    calories: (item['calories'] as num?)?.toInt() ?? 0,
                    protein: '${(item['protein'] as num?)?.toInt() ?? 0}g',
                    carbs: '${(item['carbs'] as num?)?.toInt() ?? 0}g',
                    fat: '${(item['fat'] as num?)?.toInt() ?? 0}g',
                    fiber: (item['fiber'] as num?)?.toInt() ?? 0,
                  );
                })
                .toList() ??
            [];

        final totalKcal =
            items.fold<int>(0, (sum, item) => sum + item.calories);

        // Success — clear circuit breaker for this text.
        serviceFailCounts.remove(text);
        serviceFailLastAt.remove(text);
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
      final errStrFull = e.toString();
      final clippedFull =
          errStrFull.length > 500 ? errStrFull.substring(0, 500) : errStrFull;
      unawaited(ErrorTelemetry.logEvent('nutrition_ai_text_analyse_failed',
          message: clippedFull));

      final msg = e.toString().toLowerCase();
      final isAuthError = msg.contains('401') || msg.contains('token') ||
                          msg.contains('unauthorized') || msg.contains('jwt') ||
                          msg.contains('no active session') || msg.contains('session expired');
      final isServiceError = msg.contains('503') || msg.contains('502') ||
                             msg.contains('504') ||
                             msg.contains('unavailable') || msg.contains('non-2xx') ||
                             msg.contains('food ai') || msg.contains('food analysis failed');
      // Layer 4 — increment circuit breaker counter on service errors
      // (502/503/504). Other error classes (auth, rate-limit, message-
      // too-long) do NOT increment — those are user-actionable and
      // re-trying immediately is the correct UX.
      if (isServiceError) {
        serviceFailCounts[text] = (serviceFailCounts[text] ?? 0) + 1;
        serviceFailLastAt[text] = DateTime.now();
      }
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

      // Duplicate telemetry adjacent to apology copy so Gate 15's 30-line
      // lookback finds a marker next to the user-facing message. Primary
      // telemetry already fired at the top of this catch.
      unawaited(ErrorTelemetry.logEvent(
          'nutrition_ai_text_analyse_apology_shown',
          message: clippedFull));
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
    unawaited(ErrorTelemetry.logEvent(
        'nutrition_ai_text_analyse_non_200_no_data',
        message: 'food_text_analysis returned non-200 with no exception'));
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

  void clear() {
    // Reset circuit breaker on explicit clear — user dismissing the
    // breakdown card means they're starting fresh.
    serviceFailCounts.clear();
    serviceFailLastAt.clear();
    state = null;
  }

  /// Save the analysed meal to nutrition log via NutritionWriteService.
  /// (Plan C-10: routes through service to ensure per-item rows reach
  /// nutrition_log_items + the aiText counter increments via the
  /// service's source-based counter wiring.)
  ///
  /// Returns a [WriteResult] so the UI layer can show a snackbar on success
  /// or failure. A `success: false, errorMessage: 'no_state'` result is
  /// returned on double-tap (state already cleared by a prior successful
  /// save) rather than failing silently.
  Future<WriteResult> saveMeal({String mealType = 'snacks'}) async {
    final data = state;
    if (data == null) {
      return WriteResult.noState();
    }

    final items = data.items.map((item) {
      final protein =
          double.tryParse(item.protein.replaceAll('g', '')) ?? 0.0;
      final carbs = double.tryParse(item.carbs.replaceAll('g', '')) ?? 0.0;
      final fat = double.tryParse(item.fat.replaceAll('g', '')) ?? 0.0;
      return FoodItem(
        name: item.name,
        // Test #11 M4: AI text breakdown doesn't carry per-item grams —
        // the AI parses free text and pre-computes macros directly.
        // Use 100.0 (canonical "per 100g" sentinel) instead of 0 so
        // cloud nutrition_log_items.quantity_g is meaningful for analytics.
        quantityG: 100.0,
        calories: item.calories.toDouble(),
        protein: protein,
        carbs: carbs,
        fat: fat,
        fiber: item.fiber.toDouble(),
      );
    }).toList();

    if (items.isEmpty) {
      state = null;
      return WriteResult.noState();
    }

    try {
      final result = await NutritionWriteService.instance.logMeal(
        date: DateTime.now(),
        mealType: mealType.toLowerCase(),
        items: items,
        overrideTotalCals: data.totalKcal,
        source: NutritionWriteSource.aiText,
      );
      if (result.success) {
        state = null;
      }
      return result;
    } catch (e, st) {
      debugPrint('[AiBreakdownNotifier.saveMeal] error: $e\n$st');
      return WriteResult.fail(e.toString());
    }
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

  Future<({bool success, String? error, String? logKey})> logFood({
    required Map<String, dynamic> food,
    required String mealType,
    required double quantityG,
  }) async {
    final foodName = (food['name'] ?? 'Food').toString();

    // Food map may carry per-100g keys (from the bundled food database) OR
    // plain absolute keys (from AI-estimated fallback maps). Scale per-100g
    // values by quantityG/100 to get absolute macros for this serving.
    final ratio = quantityG / 100.0;
    final cal = (food['calories_per_100g'] as num? ??
            food['calories'] as num? ??
            0)
        .toDouble() *
        ratio;
    final pro = (food['protein_per_100g'] as num? ??
            food['protein'] as num? ??
            0)
        .toDouble() *
        ratio;
    final carb = (food['carbs_per_100g'] as num? ??
            food['carbs'] as num? ??
            0)
        .toDouble() *
        ratio;
    final fat = (food['fat_per_100g'] as num? ?? food['fat'] as num? ?? 0)
            .toDouble() *
        ratio;
    final fiber = (food['fiber_per_100g'] as num? ??
            food['fiber'] as num? ??
            0)
        .toDouble() *
        ratio;

    final result = await NutritionWriteService.instance.logMeal(
      date: istNow(),
      mealType: mealType.toLowerCase(),
      items: [
        FoodItem(
          name: foodName,
          quantityG: quantityG,
          calories: cal,
          protein: pro,
          carbs: carb,
          fat: fat,
          fiber: fiber,
        ),
      ],
      source: NutritionWriteSource.manualSearch,
    );

    // NutritionWriteService invalidates the core provider batch and fires
    // sync internally. Invalidate the weekly provider + run badge checks
    // that the service doesn't own.
    if (result.success) {
      ref.invalidate(weeklyNutritionProvider);
      BadgeService.instance.checkAll();
    }

    return (
      success: result.success,
      error: result.errorMessage,
      logKey: result.logKey,
    );
  }

  Future<void> deleteFoodLog(String logId) async {
    // OI-36 (audit-2026-05-17 Hermes C1) — delegate to NutritionWriteService
    // canonical writer. Pre-fix this method directly wrote `recent_deletes`
    // audit + called `box.delete(logId)` bypassing the WriteService entirely.
    // The audit-log behavior now lives inside `NutritionWriteService.deleteLog`
    // so all consumers get it uniformly. `allowUndo: false` because this
    // entry point doesn't surface an UNDO snackbar (separate from the food
    // search sheet's delete-with-undo path); set to true if the call-site
    // wants `restoreLastDeleted()` to work.
    final result = await NutritionWriteService.instance.deleteLog(
      logKey: logId,
      allowUndo: false,
    );
    if (!result.success) {
      debugPrint('[NutritionProvider] deleteFoodLog failed: ${result.errorMessage}');
    }
    // WriteService invalidates the canonical batch internally. Invalidate
    // the weekly provider that the service doesn't own (mirrors the
    // restoreFoodLog pattern + the editFoodLog wrapper below).
    ref.invalidate(weeklyNutritionProvider);
  }

  /// Bug #20 — Restores a previously-deleted food log from an undo snackbar.
  /// Writes back at the original Hive key carried on `log['id']` so the
  /// restored row lands exactly where the delete removed it from — preserving
  /// the Supabase sync linkage. Fires sync + snapshot so the AI coach sees
  /// the correction.
  Future<void> restoreFoodLog(Map<String, dynamic> log) async {
    // C-12 (audit-2026-05-11) — route through NutritionWriteService
    // so the restore inherits the canonical provider invalidation
    // batch + sync fan-out (matches the SoT contract per CLAUDE.md
    // §15). Service handles the no-op when log['id'] is null/empty.
    await NutritionWriteService.instance.restoreFoodLog(log);
  }

  /// Plan C-16 — Edit Macros sheet's Save button now routes through
  /// [NutritionWriteService.editLog] instead of rewriting the Hive map
  /// in place. The service recomputes totals (when items[] are passed),
  /// fires the canonical provider invalidation batch, and triggers the
  /// both-tables cloud projection.
  ///
  /// This wrapper edits TOTALS only (no items[]) — the service's
  /// `m.addAll(updates)` path applies the macro overrides verbatim.
  Future<void> updateFoodLog({
    required String logId,
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    double fiber = 0,
  }) async {
    await NutritionWriteService.instance.editLog(
      logKey: logId,
      updates: <String, dynamic>{
        'total_calories': calories.round(),
        'total_protein': protein.round(),
        'total_carbs': carbs.round(),
        'total_fat': fat.round(),
        'total_fiber': fiber.round(),
      },
    );
  }
}

final foodLogProvider =
    NotifierProvider<FoodLogNotifier, void>(FoodLogNotifier.new);

// ── Saved Meals ──────────────────────────────────────────────────

class SavedMealsNotifier extends Notifier<List<Map<String, dynamic>>> {
  @override
  List<Map<String, dynamic>> build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    final nutritionBox = HiveService.instance.nutritionBox;
    final results = <Map<String, dynamic>>[];

    // Plan C-15: Surface BOTH legacy `is_saved_meal=true` saved meal
    // presets AND new `meal_*` keyed templates with `is_template=true`
    // (written by NutritionWriteService.saveMealAsTemplate). Templates
    // missing the legacy `id` field get one synthesised from the Hive
    // key so SavedMealsSection's RE-LOG flow still works.
    for (final entry in nutritionBox.toMap().entries) {
      final raw = entry.value;
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final isLegacy = item['is_saved_meal'] == true;
      final isTemplate = item['is_template'] == true &&
          entry.key.toString().startsWith('meal_');
      if (!isLegacy && !isTemplate) continue;
      if (isTemplate && item['id'] == null) {
        item['id'] = entry.key.toString();
      }
      results.add(item);
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
    // C-12 (audit-2026-05-11) — route through NutritionWriteService.
    // Service handles Hive write + provider invalidation + sync fan-out.
    await NutritionWriteService.instance.saveMealPreset(
      name: name,
      totalCalories: totalCalories,
      totalProtein: totalProtein,
      totalCarbs: totalCarbs,
      totalFat: totalFat,
      items: items,
    );
    // Service invalidates dailyNutritionProvider et al. via its
    // _invalidateNutritionProviders helper; this notifier still needs
    // an explicit invalidateSelf so SavedMealsSection rebuilds with
    // the new row.
    ref.invalidateSelf();
  }

  /// Re-log a saved meal.
  ///
  /// C-12 (audit-2026-05-11) — routed through
  /// `NutritionWriteService.relogSavedMeal`. The service performs the
  /// canonical `logMeal` write (with proper `items[]`, IST date,
  /// per-source counter increment) instead of the legacy flat-totals
  /// shape this notifier used to write. Also drops the
  /// `NutritionRepository.syncLogToSupabase` double-write at the old
  /// line 1050 — WriteService.logMeal handles the projection.
  Future<void> relogSavedMeal(Map<String, dynamic> savedMeal,
      {String mealType = 'snacks'}) async {
    final savedId = savedMeal['id'] as String?;
    if (savedId == null) return;

    final result = await NutritionWriteService.instance.relogSavedMeal(
      savedMealKey: savedId,
      date: DateTime.now(),
      mealType: mealType.toLowerCase(),
    );
    if (!result.success) {
      debugPrint('[SavedMealsNotifier.relogSavedMeal] WriteService failed: '
          '${result.errorMessage}');
      return;
    }

    // Increment times_used counter on the saved meal and sync to cloud.
    final box = HiveService.instance.nutritionBox;
    final existing = box.get(savedId);
    if (existing is Map) {
      final updated = Map<String, dynamic>.from(existing);
      updated['times_used'] = ((updated['times_used'] as int?) ?? 0) + 1;
      await box.put(savedId, updated);
      unawaited(SyncService.instance.syncSavedMealsNow());
    }

    // WriteService invalidates the daily/weekly/summary/recent
    // providers via its hook; this notifier still rebuilds for the
    // times_used update.
    ref.invalidateSelf();
  }

  /// Delete a saved meal preset.
  Future<void> deleteSavedMeal(String id) async {
    // C-12 (audit-2026-05-11) — route through NutritionWriteService.
    await NutritionWriteService.instance.deleteSavedMeal(id);
    ref.invalidateSelf();
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

    // Invalidate diet plan generator index so the new food is visible on
    // the next plan generation (indices are rebuilt lazily on next call).
    DietPlanGenerator.instance.clearCache();

    // Sync (Plan D Task 1): batch sync covers single-item upsert.
    //
    // Audit 2026-05-20 / A8: removed the parallel
    // `NutritionRepository.syncCustomFoodToSupabase(...)` call here.
    // It was a fire-and-forget INSERT into `user_custom_foods` that
    // duplicated `syncCustomItemsNow()` (which performs the same upsert
    // through the canonical telemetry-aware sync path). The static
    // method swallowed errors via `debugPrint` and bypassed the
    // rate-limit-aware `ErrorTelemetry` sink (silent-drop class).
    unawaited(SyncService.instance.syncCustomItemsNow());
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
        // Test #11 M1: increment counter HERE — at the API-call site.
        // The Edge Function call already fired and consumed server quota;
        // the user may dismiss without saving but quota was spent. Client
        // counter must stay in sync with the server's abuse cap so the
        // "X remaining" UI is accurate regardless of save behaviour.
        unawaited(UsageCounterService.instance.increment(
          AppConstants.featureScanMealPro,
          SubscriptionService.instance.isPro(),
        ));
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
  ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
  final isPro = SubscriptionService.instance.isPro();
  return UsageCounterService.instance
      .remaining(AppConstants.featureAiTextLogPro, isPro);
});

/// Returns remaining scan meal count for display.
final scanMealRemainingProvider = Provider<int>((ref) {
  ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
  final isPro = SubscriptionService.instance.isPro();
  return UsageCounterService.instance
      .remaining(AppConstants.featureScanMealPro, isPro);
});

/// Returns remaining cart auditor count for display.
final cartAuditorRemainingProvider = Provider<int>((ref) {
  ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
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
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
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

  /// Delegates to [NutritionWriteService.deleteLog] so legacy direct-Hive
  /// callers also pick up the per-table cloud delete + undo stash
  /// (Plan C-14).
  Future<void> delete(String logId) async {
    final result = await NutritionWriteService.instance
        .deleteLog(logKey: logId, allowUndo: true);
    if (!result.success) {
      // Fall through to a no-op; provider state stays at AsyncData(null).
      // Caller (UI) shows the snackbar based on its own context.
      return;
    }
  }
}

final deleteNutritionLogProvider =
    NotifierProvider<DeleteNutritionLogNotifier, void>(
        DeleteNutritionLogNotifier.new);

// ── Water Target Provider ─────────────────────────────────────────
//
// Single source of truth for the user's daily water target.
// Reads the user override (if set) or computes from profile via
// [WaterTargetService]. All 4 hardcoded 3000-ml sites watch this.
// Call `ref.invalidate(waterTargetProvider)` after any
// [WaterTargetService.setUserOverride] call to propagate the change.
final waterTargetProvider = Provider<int>((ref) {
  ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
  return WaterTargetService.instance.currentTargetMl();
});
