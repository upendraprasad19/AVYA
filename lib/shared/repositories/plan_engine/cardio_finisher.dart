import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:icanbefitter/core/constants/fitness_goals.dart';

import 'equipment_capability.dart';
import 'models.dart';
import 'plan_engine_flags.dart';

/// Stage 6: Appends HIIT cardio finishers to 2 workout days per week.
///
/// Only activates for goals whose FitnessGoals spec has `cardio == true`
/// (lose_fat / general_fitness / recompose). Finisher shape is driven by
/// `cardioPreference`; when unset (always today — there is no preference UI)
/// it defaults to the GOAL via `_defaultForGoal` (④, Batch 3a), or the mildest
/// mini-HIIT when the `disable_cardio_goal_default` kill-switch is off.
/// Finisher goes between main exercises and cooldown.
/// Unit 3C (OI-396, d61): the finisher one generation attaches, decided ONCE before sets are sized, so the same
/// decision feeds the session budget (its seconds on [days]) and Stage 6 (what is attached).
class FinisherPlan {
  const FinisherPlan({this.days = const {}, this.exercises = const [], this.reserved = false});

  /// No finisher.
  static const none = FinisherPlan();

  /// Day indices in the week (the order every ledger and `WeekPlan.workoutDays` use).
  final Set<int> days;

  /// The finisher's items (the same list on every finisher day of every week).
  final List<PlannedExercise> exercises;

  /// Whether its time is taken from those days' budgets (false only under the [CardioFinisher.debugReserve] test seam).
  final bool reserved;

  /// The finisher's time ([CardioFinisher.secondsOf]).
  int get seconds => CardioFinisher.secondsOf(exercises);

  /// The reservation the session budget takes (`SessionBudgetContext.finisherSecondsByDay`): empty when nothing is
  /// reserved or attached.
  Map<int, int> get secondsByDay =>
      reserved && exercises.isNotEmpty ? {for (final d in days) d: seconds} : const {};
}

class CardioFinisher {
  /// Unit 3C (OI-396, d74): the finisher an injured user gets in a gym (any injury); at home they get none.
  static const String injuredGymFinisherName = 'Stationary Bike Sprints';

  /// d76: the short finisher's time under 60 minutes (the mini HIIT 180 s + 2 x 30 s round rest; 4 bike rounds 240 s).
  static const int shortFinisherSeconds = 240;

  /// Unit 3C test seam (plan §3 attribution oracle 1): false builds the same finisher with `reserved: false`, so a
  /// golden run can separate what the finisher ATTACHES from what its reserved time moves. Never set in the app.
  @visibleForTesting
  static bool debugReserve = true;

  /// A finisher's time: each item's `durationSeconds` (its whole work time across its sets) plus `sets x restSeconds`
  /// (the rest after each round, stored on a circuit's last item since 3C). The display prices a stored finisher with
  /// the same rule (`SessionBudget.finisherSecondsOfPlanDay`).
  static int secondsOf(List<PlannedExercise> items) =>
      items.fold(0, (sum, e) => sum + (e.durationSeconds ?? 0) + e.sets * e.restSeconds);

  /// Unit 3C (OI-396, founder 2026-10-22 / d56 / d61 / d74): the finisher for one generation, decided before sizing.
  /// Empty when the goal has no cardio or the week has under 2 days. No injury -> today's
  /// shape with each circuit's round rest stored; any injury ([injuries] are canonical tokens, `generateV4`'s
  /// `normalizedInjuries`) -> [injuredGymFinisherName] with gym cardio, none without. d76: under 60 resolved
  /// [minutes] the finisher is the short one ([shortFinisherSeconds]): the mini HIIT, or 4 rounds of the bike for an
  /// injured gym user. Null [minutes] = 60+ (the full finisher).
  static FinisherPlan plan({
    required String goal,
    required String? cardioPreference,
    required List<String> equipmentList,
    bool? hasGymEquipmentOverride,
    Set<String>? capability,
    List<String> injuries = const [],
    required int dayCount,
    int? minutes,
  }) {
    if (!FitnessGoals.of(goal).cardio || dayCount < 2) return FinisherPlan.none;
    final preference = cardioPreference ?? _defaultForGoal(goal);
    final hasGymEquipment = hasGymEquipmentOverride ??
        equipmentList.any(
          (e) => e.toLowerCase().contains('gym') || e.toLowerCase().contains('full'),
        );
    final days = _pickFinisherDays(dayCount);
    final short = minutes != null && minutes < 60;
    if (injuries.isNotEmpty) {
      if (!hasGymEquipment) return FinisherPlan.none;
      return FinisherPlan(
          days: days, exercises: _cyclingFinisher(true, rounds: short ? 4 : 8), reserved: debugReserve);
    }
    if (short) {
      return FinisherPlan(days: days, exercises: _miniHiitFinisher(roundRests: true), reserved: debugReserve);
    }
    return FinisherPlan(
      days: days,
      exercises: _buildFinisher(preference, hasGymEquipment, capability: capability, roundRests: true),
      reserved: debugReserve,
    );
  }

  /// Attach cardio finishers to 2 days per week (`_pickFinisherDays`: {0, 1} for 2 days, {0, 2} for 3-4, {0, 3} for 5-6). With [plan] (Unit 3C, `generateV4`) the plan decided
  /// before sizing is attached as it is; without it (direct callers) the plan is built here per week, as before.
  static List<WeekPlan> attach({
    required List<WeekPlan> weeks,
    required String goal,
    required String? cardioPreference,
    required List<String> equipmentList,
    bool? hasGymEquipmentOverride, // ⑥ C2 (WU-2) — null → old predicate
    // ⑦ OI-89: the user's capability set, or null for "do not enforce".
    Set<String>? capability,
    // Unit 3C (d56): the user's canonical injuries.
    List<String> injuries = const [],
    FinisherPlan? plan,
  }) {
    if (!FitnessGoals.of(goal).cardio) return weeks;

    return weeks.map((week) {
      final dayCount = week.workoutDays.length;
      if (dayCount < 2) return week;

      final p = plan ??
          CardioFinisher.plan(
            goal: goal,
            cardioPreference: cardioPreference,
            equipmentList: equipmentList,
            hasGymEquipmentOverride: hasGymEquipmentOverride,
            capability: capability,
            injuries: injuries,
            dayCount: dayCount,
          );
      if (p.exercises.isEmpty) return week;

      final days = week.workoutDays.asMap().entries.map((entry) {
        final day = entry.value;
        if (!p.days.contains(entry.key)) return day;

        return WorkoutDay(
          dayNumber: day.dayNumber,
          name: day.name,
          focus: day.focus,
          exercises: day.exercises,
          warmup: day.warmup,
          cooldown: day.cooldown,
          finisher: p.exercises,
        );
      }).toList();

      return WeekPlan(
        weekNumber: week.weekNumber,
        weekInPhase: week.weekInPhase,
        overloadNotes: week.overloadNotes,
        weekCharacter: week.weekCharacter,
        workoutDays: days,
      );
    }).toList();
  }

  /// Goal-keyed default finisher shape (④, Batch 3a) — the fix for the blanket
  /// `hate_cardio` fallback that gave EVERY cardio-goal user the mildest ~5-min
  /// mini-HIIT regardless of intent. Only reached for the 3 cardio-enabled goals
  /// (guarded by `FitnessGoals.of(goal).cardio` in [attach]); every token below
  /// is an existing `_buildFinisher` case with a bodyweight fallback. Kill-switch
  /// off → verbatim pre-④ behavior (`hate_cardio` for all).
  static String _defaultForGoal(String goal) {
    if (!PlanEngineFlags.cardioGoalDefaultEnabled) return 'hate_cardio';
    switch (goal) {
      case 'lose_fat':
        return 'hiit'; // fullest ~10-min finisher — the goal most wanting burn
      case 'general_fitness':
        return 'cycling'; // ~8-min balanced
      case 'recompose':
        return 'jump_rope'; // ~7.5-min moderate
      default:
        return 'hate_cardio'; // build_muscle/strength never reach here (cardio==false)
    }
  }

  /// Pick 2 non-consecutive day indices from a day count.
  /// e.g., 4 days → [0, 2], 3 days → [0, 2], 5 days → [0, 2], 6 days → [0, 3]
  static Set<int> _pickFinisherDays(int dayCount) {
    if (dayCount <= 2) return {0, 1};
    if (dayCount <= 4) return {0, 2};
    if (dayCount == 5) return {0, 3};
    return {0, 3}; // 6 days
  }

  /// Build finisher exercises based on user preference.

  /// ⑦ OI-89: every finisher preference this class can build.
  static const allFinisherTokens = <String>[
    'running', 'cycling', 'hiit', 'jump_rope', 'hate_cardio',
  ];

  /// ⑦ OI-89: what a preference MINIMALLY requires.
  ///
  /// running / cycling / hiit / hate_cardio all carry a documented bodyweight
  /// fallback (Spot Jogging, High Knees, burpee circuits), so at worst they need
  /// nothing. `jump_rope` was the ONLY case of the five with no fallback at all
  /// — `_buildFinisher` called `_jumpRopeFinisher()` without `hasGymEquipment`
  /// while every sibling took it. Since `_defaultForGoal` maps `recompose` to it
  /// and the goal-default flag is ON by default, a bodyweight recompose user got
  /// a jump rope twice a week in the shipped APK.
  static List<String> equipmentForFinisher(String preference) =>
      preference == 'jump_rope' ? const ['jump rope'] : const ['bodyweight'];

  static List<PlannedExercise> _buildFinisher(
    String preference,
    bool hasGymEquipment, {
    // ⑦ OI-89: null = do not enforce (see TrainingHistoryAnalyzer.resolveCapability).
    required Set<String>? capability,
    // Unit 3C: store a circuit's round rest on its last item (priced by [secondsOf]); false = today's items.
    bool roundRests = false,
  }) {
    switch (preference) {
      case 'running':
        return _runningFinisher(hasGymEquipment);
      case 'cycling':
        return _cyclingFinisher(hasGymEquipment);
      case 'hiit':
        return _hiitFinisher(roundRests: roundRests);
      case 'jump_rope':
        // ⑦ OI-89: degrade like every sibling. Previously this was the only
        // case that ignored the equipment signal entirely.
        if (capability != null &&
            !EquipmentCapability.canPerform(
                equipmentForFinisher('jump_rope'), capability)) {
          return _miniHiitFinisher(roundRests: roundRests);
        }
        return _jumpRopeFinisher();
      case 'hate_cardio':
      default:
        return _miniHiitFinisher(roundRests: roundRests);
    }
  }

  /// Treadmill Intervals: 30s sprint / 60s walk × 5 rounds (~8 min)
  /// Bodyweight fallback: Spot Jogging Intervals
  static List<PlannedExercise> _runningFinisher(bool hasGym) {
    final name = hasGym ? 'Treadmill Intervals' : 'Spot Jogging Intervals';
    return [
      _finisherExercise(
        name: name,
        sets: 5,
        reps: '30s sprint / 60s walk',
        durationSeconds: 450,
        notes: '30s sprint → 60s walk recovery × 5 rounds',
      ),
    ];
  }

  /// Stationary Bike Sprints: 30s fast / 30s slow × 8 rounds (~8 min)
  /// Bodyweight fallback: High Knees Intervals
  static List<PlannedExercise> _cyclingFinisher(bool hasGym, {int rounds = 8}) {
    final name = hasGym ? 'Stationary Bike Sprints' : 'High Knees Intervals';
    return [
      _finisherExercise(
        name: name,
        sets: rounds,
        reps: '30s fast / 30s slow',
        durationSeconds: 60 * rounds,
        notes: '30s max effort → 30s easy recovery × $rounds rounds',
      ),
    ];
  }

  /// Bodyweight Circuit: burpees, mountain climbers, jump squats (3 rounds, ~10 min)
  static List<PlannedExercise> _hiitFinisher({bool roundRests = false}) {
    return [
      _finisherExercise(
        name: 'Burpees',
        sets: 3,
        reps: '10',
        durationSeconds: 120,
        notes: 'Part 1 of HIIT circuit — minimal rest between exercises',
      ),
      _finisherExercise(
        name: 'Mountain Climbers',
        sets: 3,
        reps: '30s',
        durationSeconds: 120,
        notes: 'Part 2 of HIIT circuit',
      ),
      _finisherExercise(
        name: 'Jump Squats',
        sets: 3,
        reps: '10',
        durationSeconds: 120,
        notes: 'Part 3 of HIIT circuit — 60s rest after each full round',
        restSeconds: roundRests ? 60 : 0,
      ),
    ];
  }

  /// Jump Rope Intervals: 1 min on / 30s rest × 5 rounds (~7.5 min)
  static List<PlannedExercise> _jumpRopeFinisher() {
    return [
      _finisherExercise(
        name: 'Jump Rope Intervals',
        sets: 5,
        reps: '60s on / 30s rest',
        durationSeconds: 450,
        notes: '1 min continuous jump rope → 30s rest × 5 rounds',
      ),
    ];
  }

  /// Mini HIIT: high knees 30s + burpees 30s + mountain climbers 30s × 2 rounds (~5 min)
  /// Default for "hate_cardio" — shortest finisher.
  static List<PlannedExercise> _miniHiitFinisher({bool roundRests = false}) {
    return [
      _finisherExercise(
        name: 'High Knees',
        sets: 2,
        reps: '30s',
        durationSeconds: 60,
        notes: 'Mini HIIT round 1/3 — go hard, minimal rest',
      ),
      _finisherExercise(
        name: 'Burpees',
        sets: 2,
        reps: '30s',
        durationSeconds: 60,
        notes: 'Mini HIIT round 2/3',
      ),
      _finisherExercise(
        name: 'Mountain Climbers',
        sets: 2,
        reps: '30s',
        durationSeconds: 60,
        notes: 'Mini HIIT round 3/3 — 30s rest after each full round',
        restSeconds: roundRests ? 30 : 0,
      ),
    ];
  }

  static PlannedExercise _finisherExercise({
    required String name,
    required int sets,
    required String reps,
    required int durationSeconds,
    String? notes,
    int restSeconds = 0,
  }) {
    return PlannedExercise(
      exerciseId: name.toLowerCase().replaceAll(' ', '_').replaceAll('/', '_'),
      exerciseName: name,
      loggingType: 'timed',
      sets: sets,
      reps: reps,
      restSeconds: restSeconds,
      durationSeconds: durationSeconds,
      notes: notes,
      category: 'finisher',
    );
  }
}
