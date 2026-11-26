// Everything the Nutrition History screen shows, built from Hive in one pass
// (plan docs/plans/nutrition-history.md 6.1). No network, no AI call.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/target_history_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart'
    show WeightEntryData, restoreCompletedTickProvider, weightHistoryProvider;

import '../repositories/nutrition_repository.dart';
import '../services/nutrition_history.dart';
import 'nutrition_provider.dart';

class NutritionHistoryData {
  /// IST today.
  final String todayKey;

  /// The first day of the history: the earlier of the onboarding day and the
  /// first meal day (today when there is neither).
  final String fromDay;

  /// Continuous, oldest first, [fromDay] .. [todayKey], each with its target
  /// and status.
  final List<JudgedDay> days;

  /// Whether any target is known (false: the screen hides its target-based
  /// sections and the statuses stay neutral).
  final bool hasTargets;

  /// The first day judged against its own recorded target; days before it
  /// use that first target ("assumed"). Null without targets.
  final String? firstTargetDay;

  /// The CURRENT water target (water has no history).
  final int waterTargetMl;
  final List<WeightEntryData> weights;
  final Set<String> trainingDays;
  final TopFoods foods;
  final List<String> insights;

  const NutritionHistoryData({
    required this.todayKey,
    required this.fromDay,
    this.days = const [],
    this.hasTargets = false,
    this.firstTargetDay,
    this.waterTargetMl = 0,
    this.weights = const [],
    this.trainingDays = const {},
    this.foods = const TopFoods(),
    this.insights = const [],
  });

  /// Days with at least one meal (partial days and today included).
  int get daysLogged => days.where((j) => j.day.logged).length;

  bool get isEmpty => daysLogged == 0;
}

/// The longest history the screen builds (ten years).
const int kHistoryMaxDays = 3653;

/// Pure assembly (tested without Riverpod).
NutritionHistoryData buildNutritionHistoryData({
  required NutritionHistoryInputs inputs,
  required String todayKey,
  required int waterTargetMl,
  required List<WeightEntryData> weights,
}) {
  // Never further back than [kHistoryMaxDays]: one garbled row dated decades
  // ago must not build a series of hundreds of thousands of days.
  final today = parseDayKey(todayKey);
  final floor = today == null
      ? todayKey
      : dayKeyOf(today.subtract(const Duration(days: kHistoryMaxDays - 1)));
  var fromDay = todayKey;
  for (final candidate in [inputs.onboardingDay, firstMealDay(inputs.rows)]) {
    if (candidate != null && candidate.compareTo(fromDay) < 0) {
      fromDay = candidate;
    }
  }
  if (fromDay.compareTo(floor) < 0) fromDay = floor;
  final series = buildNutritionDays(inputs.rows, inputs.waterByDay,
      fromDay: fromDay, toDay: todayKey);
  final entries = inputs.targets;
  DayTarget? targetOf(String day) {
    final hit = TargetHistoryService.targetFor(day, entries);
    // A zero calorie target judges nothing (every day would read "over").
    if (hit == null || hit.entry.calories <= 0) return null;
    return (
      calories: hit.entry.calories.toDouble(),
      protein: hit.entry.protein.toDouble(),
      carbs: hit.entry.carbs.toDouble(),
      fat: hit.entry.fat.toDouble(),
      assumed: hit.assumed,
    );
  }

  final days = judgeDays(series, targetOf, todayKey);
  return NutritionHistoryData(
    todayKey: todayKey,
    fromDay: fromDay,
    days: days,
    hasTargets: entries.isNotEmpty,
    firstTargetDay: entries.isEmpty ? null : entries.first.from,
    waterTargetMl: waterTargetMl,
    weights: weights,
    trainingDays: inputs.trainingDays,
    foods: topFoods(inputs.rows, fromDay: fromDay, toDay: todayKey),
    insights: nutritionInsights(days, inputs.trainingDays, todayKey),
  );
}

final nutritionHistoryProvider = Provider<NutritionHistoryData>((ref) {
  final token = ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
  final todayKey = istDateStr(DateTime.now());
  // '<anon>' = no session to read (sign-out / account-swap window).
  if (token == '<anon>') {
    return NutritionHistoryData(todayKey: todayKey, fromDay: todayKey);
  }
  // Rebuild triggers: a restore, a meal log or day rollover, a target change,
  // a water log, a weigh-in.
  ref.watch(restoreCompletedTickProvider);
  ref.watch(dailyNutritionProvider);
  ref.watch(macroTargetsProvider);
  ref.watch(waterIntakeProvider);
  final weights = ref.watch(weightHistoryProvider);
  final waterTarget = ref.watch(waterTargetProvider);
  return buildNutritionHistoryData(
    inputs: NutritionRepository.instance.loadHistoryInputs(),
    todayKey: todayKey,
    waterTargetMl: waterTarget,
    weights: weights,
  );
});
