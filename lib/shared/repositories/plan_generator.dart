import 'dart:math';

import 'package:flutter/foundation.dart';

import 'exercise_repository.dart';

/// Local Dart plan generator V2. Queries Hive exerciseBox — zero API cost.
///
/// Pipeline architecture:
///   SplitSelector → ExerciseSelector → PeriodizationEngine →
///   SupersetPairer → (Phase output)
///
/// Produces 4 genuinely distinct weeks per phase with:
/// - Daily Undulating Periodization (DUP) — intensity varies per day
/// - Weekly volume wave — baseline → overreach → peak → deload
/// - A/B workout alternation — different exercises weeks 1&3 vs 2&4
/// - Smart antagonist superset pairing
/// - Experience-aware exercise filtering
///
/// DO NOT modify this file without explicit instruction.
class PlanGenerator {
  PlanGenerator._();
  static final PlanGenerator _instance = PlanGenerator._();
  static PlanGenerator get instance => _instance;

  final ExerciseRepository _exerciseRepo = ExerciseRepository.instance;

  /// Deterministic exercise count per workout: split days × effective experience.
  ///
  /// Bug #17 — Hard floor of 5 exercises per workout day. Bumped 5-day and
  /// 6-day beginners from 4 → 5 so the initial selection meets the floor
  /// without relying on `_ExerciseSelector._broadenSelection` to top up
  /// every day. The broadening logic is now the safety net for content
  /// gaps in the exercise library, not the normal path.
  static const _exerciseCounts = <int, Map<String, int>>{
    3: {'beginner': 5, 'intermediate': 6, 'advanced': 6},
    4: {'beginner': 5, 'intermediate': 5, 'advanced': 6},
    5: {'beginner': 5, 'intermediate': 5, 'advanced': 5},
    6: {'beginner': 5, 'intermediate': 5, 'advanced': 5},
  };

  /// Generates a workout phase with 4 distinct weeks.
  ///
  /// - [goal]: build_muscle | lose_fat | general_fitness | strength
  /// - [equipment]: bodyweight | home_dumbbells | basic_gym | full_gym
  /// - [daysPerWeek]: 3 | 4 | 5 | 6
  /// - [phase]: Phase number (1-12). Phase 1 is free; 2-12 require PRO.
  /// - [experienceLevel]: beginner | intermediate | advanced
  /// - [preferredDays]: User-selected training days (0=Mon..6=Sun). Null = defaults.
  Phase generate({
    required String goal,
    required String equipment,
    required int daysPerWeek,
    int phase = 1,
    String experienceLevel = 'beginner',
    List<int>? preferredDays,
  }) {
    final equipmentList = _getEquipmentList(equipment);
    final effectiveExp = effectiveLevel(experienceLevel, phase);
    final maxPerDay =
        _exerciseCounts[daysPerWeek]?[effectiveExp] ?? 5;

    // Stage 1: Split structure with A/B variants + intensity profiles
    final splitPlan = _SplitSelector.select(goal, daysPerWeek);

    // Stage 2: Exercise selection for both variants
    final populated = _ExerciseSelector.pick(
      splitPlan: splitPlan,
      exerciseRepo: _exerciseRepo,
      equipmentList: equipmentList,
      effectiveExp: effectiveExp,
      phase: phase,
      maxPerDay: maxPerDay,
      goal: goal,
    );

    // Stage 3: Periodization (DUP profiles + volume wave → 4 distinct weeks)
    final weeks = _PeriodizationEngine.apply(
      populated: populated,
      phase: phase,
      is6Day: daysPerWeek == 6,
    );

    // Stage 4: Smart antagonist superset pairing
    final paired = _SupersetPairer.pair(weeks);

    // Stage 5: Attach warm-up and cool-down
    final complete = _WarmupCooldownSelector.attach(
      paired, effectiveExp, equipmentList,
    );

    // Build Phase output
    final meta = _getPhaseMeta(phase, goal);

    return Phase(
      phase: phase,
      name: meta.name,
      focus: meta.focus,
      weeks: '${(phase - 1) * 4 + 1}-${phase * 4}',
      dailyCalories: meta.dailyCalories,
      proteinGrams: meta.proteinGrams,
      workouts: complete[0].workoutDays, // backward compat: week 1
      weekPlans: complete,
      preferredDays: preferredDays,
    );
  }

  // ── Experience progression ──────────────────────────────────────

  /// Effective experience level widens as users progress through phases.
  static String effectiveLevel(String experience, int phase) {
    if (experience == 'advanced') return 'advanced';
    if (experience == 'intermediate') {
      return phase >= 4 ? 'advanced' : 'intermediate';
    }
    // beginner
    if (phase >= 5) return 'advanced';
    if (phase >= 3) return 'intermediate';
    return 'beginner';
  }

  // ── Equipment mapping (unchanged) ──────────────────────────────

  List<String> _getEquipmentList(String equipment) {
    switch (equipment) {
      case 'bodyweight':
        return ['none', 'bodyweight'];
      case 'home_dumbbells':
        return ['none', 'bodyweight', 'dumbbells', 'resistance band'];
      case 'basic_gym':
        return [
          'none', 'bodyweight', 'dumbbells', 'barbell', 'bench',
          'pull-up bar', 'cables', 'resistance band',
        ];
      case 'full_gym':
        return [
          'none', 'bodyweight', 'dumbbells', 'barbell', 'bench',
          'pull-up bar', 'cables', 'machines', 'smith machine',
          'resistance band', 'kettlebell', 'ez-bar',
        ];
      default:
        return ['none', 'bodyweight'];
    }
  }

  // ── Phase metadata (unchanged) ─────────────────────────────────

  _PhaseMeta _getPhaseMeta(int phase, String goal) {
    if (phase == 1) {
      return _PhaseMeta(
        name: 'Foundation',
        focus: 'Movement patterns & baseline strength',
        dailyCalories: 0,
        proteinGrams: 0,
      );
    }
    const names = [
      '', 'Foundation', 'Adaptation', 'Building', 'Intensification',
      'Strength Peak', 'Volume Block', 'Power Phase', 'Hypertrophy Focus',
      'Conditioning', 'Peak Performance', 'Mastery', 'Elite',
    ];
    const focuses = [
      '', 'Movement patterns & baseline strength',
      'Increasing work capacity & form refinement',
      'Progressive overload & muscle growth',
      'Increasing intensity & strength gains',
      'Peak strength development', 'High volume training block',
      'Power & explosive movements', 'Maximum muscle growth',
      'Work capacity & endurance', 'Performance optimization',
      'Advanced techniques & periodization', 'Elite programming',
    ];
    return _PhaseMeta(
      name: phase < names.length ? names[phase] : 'Phase $phase',
      focus: phase < focuses.length ? focuses[phase] : 'Advanced training',
      dailyCalories: 0,
      proteinGrams: 0,
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// STAGE 1: SPLIT SELECTOR
// ══════════════════════════════════════════════════════════════════

class _SplitSelector {
  static List<_DaySlot> select(String goal, int daysPerWeek) {
    switch (daysPerWeek) {
      case 3:
        return _get3Day(goal);
      case 5:
        return _get5Day(goal);
      case 6:
        return _get6Day(goal);
      default:
        return _get4Day(goal);
    }
  }

  // Intensity profiles assigned per position within a week.
  static const _profiles3 = ['strength', 'hypertrophy', 'endurance'];
  static const _profiles4 = ['strength', 'hypertrophy', 'strength', 'endurance'];
  static const _profiles5 = ['strength', 'hypertrophy', 'endurance', 'strength', 'hypertrophy'];

  // ── 3-day splits ───────────────────────────────────────────────

  static List<_DaySlot> _get3Day(String goal) {
    if (goal == 'lose_fat' || goal == 'general_fitness') {
      return [
        _DaySlot(
          name: 'Full Body A', focus: 'Compound focus',
          dayType: 'full_body', intensity: _profiles3[0],
          specsA: [_CSpec('Push', 2), _CSpec('Pull', 2), _CSpec('Legs', 1)],
        ),
        _DaySlot(
          name: 'Full Body B', focus: 'Strength + cardio',
          dayType: 'full_body', intensity: _profiles3[1],
          specsA: [_CSpec('Push', 2), _CSpec('Pull', 2), _CSpec('Legs', 1)],
        ),
        _DaySlot(
          name: 'Full Body C', focus: 'Volume + core',
          dayType: 'full_body', intensity: _profiles3[2],
          specsA: [_CSpec('Legs', 2), _CSpec('Core', 2), _CSpec('Cardio', 1)],
        ),
      ];
    }
    // build_muscle / strength
    return [
      _DaySlot(
        name: 'Push + Core', focus: 'Chest, shoulders, triceps',
        dayType: 'push', intensity: _profiles3[0],
        specsA: [
          _CSpec('Push', 3, target: ['Chest', 'Upper Chest', 'Lower Chest']),
          _CSpec('Core', 2),
        ],
        specsB: [
          _CSpec('Push', 3, target: ['Deltoid', 'Shoulder'], exclude: ['Chest']),
          _CSpec('Core', 2),
        ],
      ),
      _DaySlot(
        name: 'Pull + Core', focus: 'Back, biceps',
        dayType: 'pull', intensity: _profiles3[1],
        specsA: [
          _CSpec('Pull', 3, exclude: ['Biceps', 'Forearm']),
          _CSpec('Core', 2),
        ],
        specsB: [
          _CSpec('Pull', 3),
          _CSpec('Core', 2),
        ],
      ),
      _DaySlot(
        name: 'Legs', focus: 'Quads, hamstrings, glutes',
        dayType: 'legs', intensity: _profiles3[2],
        specsA: [_CSpec('Legs', 5, target: ['Quad'])],
        specsB: [_CSpec('Legs', 5, target: ['Hamstring', 'Glute'])],
      ),
    ];
  }

  // ── 4-day splits ───────────────────────────────────────────────

  static List<_DaySlot> _get4Day(String goal) {
    if (goal == 'build_muscle') {
      return [
        _DaySlot(
          name: 'Push', focus: 'Chest, shoulders, triceps',
          dayType: 'push', intensity: _profiles4[0],
          specsA: [
            _CSpec('Push', 4, target: ['Chest', 'Upper Chest', 'Lower Chest']),
            _CSpec('Push', 2, target: ['Triceps']),
          ],
          specsB: [
            _CSpec('Push', 3, target: ['Deltoid', 'Shoulder'], exclude: ['Chest']),
            _CSpec('Push', 2, target: ['Triceps']),
            _CSpec('Push', 1, target: ['Chest']),
          ],
        ),
        _DaySlot(
          name: 'Pull', focus: 'Back, biceps',
          dayType: 'pull', intensity: _profiles4[1],
          specsA: [
            _CSpec('Pull', 4, exclude: ['Biceps', 'Forearm']),
            _CSpec('Pull', 2, target: ['Biceps']),
          ],
          specsB: [
            _CSpec('Pull', 4),
            _CSpec('Pull', 2, target: ['Biceps']),
          ],
        ),
        _DaySlot(
          name: 'Legs', focus: 'Quads, hamstrings, glutes',
          dayType: 'legs', intensity: _profiles4[2],
          specsA: [_CSpec('Legs', 6, target: ['Quad'])],
          specsB: [_CSpec('Legs', 6, target: ['Hamstring', 'Glute'])],
        ),
        _DaySlot(
          name: 'Upper', focus: 'Shoulders, back, arms',
          dayType: 'upper', intensity: _profiles4[3],
          specsA: [
            _CSpec('Push', 2, target: ['Deltoid', 'Shoulder'], exclude: ['Chest']),
            _CSpec('Pull', 2, exclude: ['Biceps', 'Forearm']),
            _CSpec('Push', 1, target: ['Triceps']),
            _CSpec('Pull', 1, target: ['Biceps']),
          ],
          specsB: [
            _CSpec('Push', 2, target: ['Chest']),
            _CSpec('Pull', 2, target: ['Biceps']),
            _CSpec('Push', 1, target: ['Triceps']),
            _CSpec('Pull', 1, exclude: ['Biceps', 'Forearm']),
          ],
        ),
      ];
    }
    if (goal == 'strength') {
      // Strength: primary lift fixed in A and B, accessories differ.
      return [
        _DaySlot(
          name: 'Squat Day', focus: 'Squat + accessories',
          dayType: 'legs', intensity: _profiles4[0],
          specsA: [_CSpec('Legs', 5)],
          specsB: [_CSpec('Legs', 5, target: ['Hamstring', 'Glute'])],
        ),
        _DaySlot(
          name: 'Bench Day', focus: 'Bench + upper push',
          dayType: 'push', intensity: _profiles4[1],
          specsA: [_CSpec('Push', 5, target: ['Chest'])],
          specsB: [_CSpec('Push', 5)],
        ),
        _DaySlot(
          name: 'Deadlift Day', focus: 'Deadlift + back',
          dayType: 'pull', intensity: _profiles4[2],
          specsA: [
            _CSpec('Pull', 3, exclude: ['Biceps', 'Forearm']),
            _CSpec('Legs', 2, target: ['Hamstring', 'Glute']),
          ],
          specsB: [
            _CSpec('Pull', 3),
            _CSpec('Legs', 2),
          ],
        ),
        _DaySlot(
          name: 'OHP Day', focus: 'Overhead press + accessories',
          dayType: 'push', intensity: _profiles4[3],
          specsA: [
            _CSpec('Push', 3, target: ['Deltoid', 'Shoulder'], exclude: ['Chest']),
            _CSpec('Core', 2),
          ],
          specsB: [
            _CSpec('Push', 3, target: ['Deltoid', 'Shoulder']),
            _CSpec('Core', 2),
          ],
        ),
      ];
    }
    // lose_fat / general_fitness
    return [
      _DaySlot(
        name: 'Upper Push', focus: 'Chest, shoulders, triceps',
        dayType: 'push', intensity: _profiles4[0],
        specsA: [_CSpec('Push', 5)],
      ),
      _DaySlot(
        name: 'Lower Body', focus: 'Legs + cardio',
        dayType: 'legs', intensity: _profiles4[1],
        specsA: [_CSpec('Legs', 3), _CSpec('Cardio', 2)],
      ),
      _DaySlot(
        name: 'Upper Pull', focus: 'Back, biceps',
        dayType: 'pull', intensity: _profiles4[2],
        specsA: [_CSpec('Pull', 5)],
      ),
      _DaySlot(
        name: 'Full Body + Core', focus: 'Total body + core',
        dayType: 'full_body', intensity: _profiles4[3],
        specsA: [_CSpec('Legs', 2), _CSpec('Core', 2), _CSpec('Cardio', 1)],
      ),
    ];
  }

  // ── 5-day splits ───────────────────────────────────────────────

  static List<_DaySlot> _get5Day(String goal) {
    if (goal == 'build_muscle') {
      return [
        _DaySlot(
          name: 'Chest', focus: 'Chest focus',
          dayType: 'push', intensity: _profiles5[0],
          specsA: [_CSpec('Push', 6, target: ['Chest', 'Upper Chest', 'Lower Chest'])],
        ),
        _DaySlot(
          name: 'Back', focus: 'Back focus',
          dayType: 'pull', intensity: _profiles5[1],
          specsA: [_CSpec('Pull', 6, exclude: ['Biceps', 'Forearm'])],
        ),
        _DaySlot(
          name: 'Shoulders + Arms', focus: 'Delts, biceps, triceps',
          dayType: 'shoulders_arms', intensity: _profiles5[2],
          specsA: [
            _CSpec('Push', 2, target: ['Deltoid', 'Shoulder'], exclude: ['Chest']),
            _CSpec('Push', 2, target: ['Triceps']),
            _CSpec('Pull', 2, target: ['Biceps']),
          ],
        ),
        _DaySlot(
          name: 'Legs', focus: 'Quads, hams, glutes',
          dayType: 'legs', intensity: _profiles5[3],
          specsA: [_CSpec('Legs', 6)],
          specsB: [_CSpec('Legs', 6, target: ['Hamstring', 'Glute'])],
        ),
        _DaySlot(
          name: 'Shoulders + Arms + Core', focus: 'Shoulders, arms, core',
          dayType: 'upper', intensity: _profiles5[4],
          specsA: [
            _CSpec('Push', 1, target: ['Deltoid', 'Shoulder'], exclude: ['Chest']),
            _CSpec('Pull', 1, target: ['Biceps']),
            _CSpec('Core', 2),
          ],
        ),
      ];
    }
    // Default 5-day
    return [
      _DaySlot(
        name: 'Push', focus: 'Chest, shoulders, triceps',
        dayType: 'push', intensity: _profiles5[0],
        specsA: [_CSpec('Push', 6)],
      ),
      _DaySlot(
        name: 'Pull', focus: 'Back, biceps',
        dayType: 'pull', intensity: _profiles5[1],
        specsA: [_CSpec('Pull', 6)],
      ),
      _DaySlot(
        name: 'Legs', focus: 'Quads, hamstrings, glutes',
        dayType: 'legs', intensity: _profiles5[2],
        specsA: [_CSpec('Legs', 6)],
      ),
      _DaySlot(
        name: 'Upper', focus: 'Shoulders, back, arms',
        dayType: 'upper', intensity: _profiles5[3],
        specsA: [
          _CSpec('Push', 2, target: ['Deltoid', 'Shoulder'], exclude: ['Chest']),
          _CSpec('Pull', 2, exclude: ['Biceps', 'Forearm']),
          _CSpec('Push', 1, target: ['Triceps']),
          _CSpec('Pull', 1, target: ['Biceps']),
        ],
      ),
      _DaySlot(
        name: 'Lower + Core', focus: 'Legs, core, conditioning',
        dayType: 'legs', intensity: _profiles5[4],
        specsA: [_CSpec('Legs', 2), _CSpec('Core', 2), _CSpec('Cardio', 1)],
      ),
    ];
  }

  // ── 6-day splits (A/B baked into split — no week-to-week alternation) ─

  static List<_DaySlot> _get6Day(String goal) {
    if (goal == 'build_muscle') {
      return [
        _DaySlot(
          name: 'Push A', focus: 'Heavy chest focus',
          dayType: 'push', intensity: 'strength',
          specsA: [
            _CSpec('Push', 4, target: ['Chest', 'Upper Chest', 'Lower Chest']),
            _CSpec('Push', 2, target: ['Triceps']),
          ],
        ),
        _DaySlot(
          name: 'Pull A', focus: 'Heavy back focus',
          dayType: 'pull', intensity: 'strength',
          specsA: [
            _CSpec('Pull', 4, exclude: ['Biceps', 'Forearm']),
            _CSpec('Pull', 2, target: ['Biceps']),
          ],
        ),
        _DaySlot(
          name: 'Legs A', focus: 'Quad dominant',
          dayType: 'legs', intensity: 'strength',
          specsA: [_CSpec('Legs', 6)],
        ),
        _DaySlot(
          name: 'Push B', focus: 'Volume shoulders + triceps',
          dayType: 'push', intensity: 'hypertrophy',
          specsA: [
            _CSpec('Push', 4, target: ['Deltoid', 'Shoulder'], exclude: ['Chest']),
            _CSpec('Push', 2, target: ['Triceps']),
          ],
        ),
        _DaySlot(
          name: 'Pull B', focus: 'Volume back + biceps',
          dayType: 'pull', intensity: 'hypertrophy',
          specsA: [
            _CSpec('Pull', 3, exclude: ['Biceps', 'Forearm']),
            _CSpec('Pull', 3, target: ['Biceps']),
          ],
        ),
        _DaySlot(
          name: 'Legs B', focus: 'Hamstring + glute focus',
          dayType: 'legs', intensity: 'hypertrophy',
          specsA: [_CSpec('Legs', 4), _CSpec('Core', 2)],
        ),
      ];
    }
    // Default 6-day PPL
    return [
      _DaySlot(name: 'Push', focus: 'Chest, shoulders, triceps',
          dayType: 'push', intensity: 'strength',
          specsA: [_CSpec('Push', 6)]),
      _DaySlot(name: 'Pull', focus: 'Back, biceps',
          dayType: 'pull', intensity: 'strength',
          specsA: [_CSpec('Pull', 6)]),
      _DaySlot(name: 'Legs', focus: 'Quads, hamstrings, glutes',
          dayType: 'legs', intensity: 'strength',
          specsA: [_CSpec('Legs', 6)]),
      _DaySlot(name: 'Push + Core', focus: 'Upper push + core',
          dayType: 'push', intensity: 'hypertrophy',
          specsA: [_CSpec('Push', 4), _CSpec('Core', 2)]),
      _DaySlot(name: 'Pull + Cardio', focus: 'Upper pull + conditioning',
          dayType: 'pull', intensity: 'hypertrophy',
          specsA: [_CSpec('Pull', 4), _CSpec('Cardio', 2)]),
      _DaySlot(name: 'Legs + Core', focus: 'Lower body + core',
          dayType: 'legs', intensity: 'hypertrophy',
          specsA: [_CSpec('Legs', 4), _CSpec('Core', 2)]),
    ];
  }
}

// ══════════════════════════════════════════════════════════════════
// STAGE 2: EXERCISE SELECTOR
// ══════════════════════════════════════════════════════════════════

class _ExerciseSelector {
  /// Bug #17 — Hard minimum exercises per workout day for both A and B
  /// variants. No workout day may ever have fewer than this. If the initial
  /// filtered selection comes up short, [_broadenSelection] runs a four-step
  /// retry chain (drop target → drop exclude → drop experience → drop
  /// equipment). If still short after all retries, [_universalPool] tops the
  /// variant up to exactly this number with hardcoded universal-bodyweight
  /// movements that are guaranteed to exist.
  static const int _hardFloor = 5;

  /// Categories to broaden across when [_broadenSelection] runs out of
  /// matches for the day's literal specs. Keyed by [_DaySlot.dayType].
  static const _broadenCategories = <String, List<String>>{
    'push':           ['Push'],
    'pull':           ['Pull'],
    'legs':           ['Legs'],
    'upper':          ['Push', 'Pull'],
    'shoulders_arms': ['Push', 'Pull'],
    'full_body':      ['Push', 'Pull', 'Legs', 'Core'],
  };

  /// Hardcoded universal-bodyweight pool. The five-deep ordered list per
  /// day type guarantees we can always reach [_hardFloor] regardless of how
  /// sparse the user's filtered exercise library is. Names that resolve in
  /// the seeded library (`exerciseBox`) are upgraded to full metadata via
  /// [ExerciseRepository.search]; the rest fall back to a minimal
  /// [PlannedExercise] built by [_buildUniversalFallback].
  static const _universalPool = <String, List<String>>{
    'push':           ['Push-Up', 'Incline Push-Up', 'Pike Push-Up', 'Decline Push-Up', 'Wide Push-Up'],
    'pull':           ['Inverted Row', 'Doorway Row', 'Towel Row', 'Superman Hold', 'Reverse Snow Angel'],
    'legs':           ['Bodyweight Squat', 'Reverse Lunge', 'Glute Bridge', 'Single-Leg RDL', 'Calf Raise'],
    'upper':          ['Push-Up', 'Pike Push-Up', 'Inverted Row', 'Superman Hold', 'Doorway Row'],
    'shoulders_arms': ['Pike Push-Up', 'Wall Handstand Hold', 'Doorway Row', 'Superman Hold', 'Plank'],
    'full_body':      ['Push-Up', 'Inverted Row', 'Bodyweight Squat', 'Plank', 'Glute Bridge'],
  };

  /// Universal-pool names that should be logged as `timed` rather than
  /// `bodyweight_reps` when the repo has no metadata for them. Used by
  /// [_buildUniversalFallback].
  static const _timedUniversal = <String>{
    'Plank', 'Dead Bug', 'Bird Dog', 'Hollow Hold', 'Side Plank',
    'Superman Hold', 'Wall Handstand Hold', 'Reverse Snow Angel',
  };

  /// Picks exercises for A and B variants of each day.
  static List<_PopulatedDay> pick({
    required List<_DaySlot> splitPlan,
    required ExerciseRepository exerciseRepo,
    required List<String> equipmentList,
    required String effectiveExp,
    required int phase,
    required int maxPerDay,
    required String goal,
  }) {
    final result = <_PopulatedDay>[];

    for (final slot in splitPlan) {
      // Cap spec counts to maxPerDay
      final cappedA = _capSpecs(slot.specsA, maxPerDay);
      final bSpecs = slot.specsB ?? slot.specsA;
      final cappedB = _capSpecs(bSpecs, maxPerDay);

      // Select Variant A exercises
      var exercisesA = _selectForSpecs(
        cappedA, exerciseRepo, equipmentList, effectiveExp, phase,
      );

      // Bug #17 — Enforce hard floor of 5 on Variant A. Broaden if short.
      exercisesA = _broadenSelection(
        current: exercisesA,
        slot: slot,
        equipmentList: equipmentList,
        effectiveExp: effectiveExp,
        repo: exerciseRepo,
        variant: 'A',
        excludeNamesParam: null,
      );

      // Select Variant B exercises, excluding A names
      final excludeNames = exercisesA.map((e) => e.exerciseName).toSet();

      // For strength goal, allow primary compound overlap (first spec's exercises)
      final firstSpecCount = cappedA.isNotEmpty ? cappedA.first.count : 0;
      Set<String> effectiveExclude;
      if (goal == 'strength' && exercisesA.length >= firstSpecCount) {
        // Don't exclude the primary compound exercises
        effectiveExclude = exercisesA
            .skip(firstSpecCount)
            .map((e) => e.exerciseName)
            .toSet();
      } else {
        effectiveExclude = excludeNames;
      }

      var exercisesB = _selectForSpecs(
        cappedB, exerciseRepo, equipmentList, effectiveExp, phase,
        excludeNames: effectiveExclude,
      );

      // Bug #17 — Enforce hard floor of 5 on Variant B. The broadening
      // chain will drop the A-variant exclusion at retry 2 if needed.
      exercisesB = _broadenSelection(
        current: exercisesB,
        slot: slot,
        equipmentList: equipmentList,
        effectiveExp: effectiveExp,
        repo: exerciseRepo,
        variant: 'B',
        excludeNamesParam: effectiveExclude,
      );

      result.add(_PopulatedDay(
        name: slot.name, focus: slot.focus,
        dayType: slot.dayType, intensity: slot.intensity,
        exercisesA: exercisesA,
        exercisesB: slot.specsB != null
            ? exercisesB.map((e) => e.copyWith(variant: 'B')).toList()
            : exercisesA, // no specsB → B uses same as A (6-day, simple splits)
      ));
    }
    return result;
  }

  /// Bug #17 — Top up [current] until it has at least [_hardFloor] exercises.
  ///
  /// Runs a four-step broadening retry chain if [current] is under the
  /// floor. Each retry progressively drops one filter:
  ///
  ///   retry 1 → drop targetMuscles
  ///   retry 2 → drop excludeMuscles AND excludeNamesParam (A-variant names)
  ///   retry 3 → drop suitableFor (experience level)
  ///   retry 4 → drop equipment
  ///
  /// If after all four retries the variant is still short, falls back to
  /// the hardcoded [_universalPool] for the day's [dayType] and tops the
  /// list up to exactly [_hardFloor]. The universal pool entries are
  /// upgraded with full metadata when found in the exercise library, or
  /// constructed minimally via [_buildUniversalFallback] otherwise.
  ///
  /// Telemetry: [debugPrint] writes a structured line whenever a retry
  /// past retry 1 fires or whenever the universal pool fallback fires —
  /// these are signals that the exercise library is too sparse for the
  /// user's filter combination and content should be added.
  static List<PlannedExercise> _broadenSelection({
    required List<PlannedExercise> current,
    required _DaySlot slot,
    required List<String> equipmentList,
    required String effectiveExp,
    required ExerciseRepository repo,
    required String variant,
    required Set<String>? excludeNamesParam,
  }) {
    if (current.length >= _hardFloor) return current;

    final result = List<PlannedExercise>.from(current);
    final pickedNames = result.map((e) => e.exerciseName).toSet();
    final dayName = slot.name;

    // Categories to query: prefer the literal categories from this day's
    // specs (preserves day intent — e.g. a Pull day stays in Pull) and
    // fall back to the [_broadenCategories] map for cross-category days.
    final specCategories = slot.specsA.map((s) => s.category).toSet().toList();
    final categories = specCategories.isNotEmpty
        ? specCategories
        : (_broadenCategories[slot.dayType] ?? const ['Push', 'Pull', 'Legs', 'Core']);

    // Aggregate target / exclude muscles across all of this day's specs.
    // Used as a soft preference on retry 0 (kept by default) and dropped
    // progressively on retries 1+.
    final allTargets = <String>[
      for (final s in slot.specsA) ...?s.targetMuscles,
    ];
    final allExcludes = <String>[
      for (final s in slot.specsA) ...?s.excludeMuscles,
    ];

    for (var retry = 1; retry <= 4 && result.length < _hardFloor; retry++) {
      // Telemetry — only log when we actually go past retry 1, since
      // retry 1 alone (drop target) is the most common quick top-up and
      // not necessarily a content gap.
      if (retry >= 2) {
        debugPrint(
          '[plan_generator] broadening retry=$retry day=$dayName variant=$variant exp=$effectiveExp eq=${equipmentList.length} have=${result.length}',
        );
      }

      final dropTarget    = retry >= 1;
      final dropExclude   = retry >= 2;
      final dropExp       = retry >= 3;
      final dropEquipment = retry >= 4;

      for (final cat in categories) {
        if (result.length >= _hardFloor) break;

        final candidates = repo.query(
          category: cat,
          equipment: dropEquipment ? null : equipmentList,
          suitableFor: dropExp ? null : effectiveExp,
          targetMuscles:
              dropTarget ? null : (allTargets.isEmpty ? null : allTargets),
          excludeMuscles:
              dropExclude ? null : (allExcludes.isEmpty ? null : allExcludes),
          limit: 50,
        );

        for (final c in candidates) {
          if (result.length >= _hardFloor) break;
          final name = c['name'] as String? ?? '';
          if (name.isEmpty || pickedNames.contains(name)) continue;
          // Honour A-variant exclusion until retry 2 drops it.
          if (!dropExclude && (excludeNamesParam?.contains(name) ?? false)) {
            continue;
          }
          result.add(_buildExercise(c).copyWith(variant: variant));
          pickedNames.add(name);
        }
      }
    }

    // Final safety net: hardcoded universal-bodyweight pool. Only fires
    // when the four broadening retries can't reach the floor — that's a
    // genuine content gap in the exercise library and worth surfacing.
    if (result.length < _hardFloor) {
      debugPrint(
        '[plan_generator] universal pool fired day=$dayName variant=$variant short=${_hardFloor - result.length} exp=$effectiveExp eq=${equipmentList.join(",")}',
      );
      final pool = _universalPool[slot.dayType] ?? _universalPool['upper']!;
      for (final exName in pool) {
        if (result.length >= _hardFloor) break;
        if (pickedNames.contains(exName)) continue;
        // Prefer real exercise data when available — gives the user
        // proper coaching cues, primary muscles, etc.
        final repoMatch = repo.search(exName);
        if (repoMatch.isNotEmpty) {
          result.add(_buildExercise(repoMatch.first).copyWith(variant: variant));
        } else {
          result.add(_buildUniversalFallback(exName, variant));
        }
        pickedNames.add(exName);
      }
    }

    return result;
  }

  /// Build a minimal [PlannedExercise] for a hardcoded universal-pool name
  /// when the seeded library has no entry for it. Used by
  /// [_broadenSelection] as the absolute last resort.
  static PlannedExercise _buildUniversalFallback(String name, String variant) {
    final isTimed = _timedUniversal.contains(name);
    return PlannedExercise(
      exerciseId: name.toLowerCase().replaceAll(' ', '_'),
      exerciseName: name,
      loggingType: isTimed ? 'timed' : 'bodyweight_reps',
      sets: 3,
      reps: isTimed ? '30s' : '10',
      restSeconds: 60,
      durationSeconds: isTimed ? 30 : null,
      category: _categoryForUniversalName(name),
      equipmentNeeded: const ['bodyweight'],
      variant: variant,
    );
  }

  /// Map a universal-pool exercise name back to its category for the
  /// minimal fallback record.
  static String _categoryForUniversalName(String name) {
    if (_universalPool['push']!.contains(name)) return 'Push';
    if (_universalPool['pull']!.contains(name)) return 'Pull';
    if (_universalPool['legs']!.contains(name)) return 'Legs';
    return 'Core';
  }

  /// Cap spec counts so total doesn't exceed [maxPerDay].
  static List<_CSpec> _capSpecs(List<_CSpec> specs, int maxPerDay) {
    final total = specs.fold<int>(0, (sum, s) => sum + s.count);
    if (total <= maxPerDay) return specs;

    // Trim from last spec first (isolations are typically last).
    final capped = specs.map((s) => _CSpec(s.category, s.count,
        target: s.targetMuscles, exclude: s.excludeMuscles)).toList();
    var excess = total - maxPerDay;
    for (var i = capped.length - 1; i >= 0 && excess > 0; i--) {
      final trim = min(excess, capped[i].count - 1); // keep at least 1
      capped[i] = _CSpec(capped[i].category, capped[i].count - trim,
          target: capped[i].targetMuscles, exclude: capped[i].excludeMuscles);
      excess -= trim;
    }
    return capped;
  }

  /// Query and select exercises for a list of category specs.
  static List<PlannedExercise> _selectForSpecs(
    List<_CSpec> specs,
    ExerciseRepository repo,
    List<String> equipment,
    String effectiveExp,
    int phase, {
    Set<String>? excludeNames,
  }) {
    final exercises = <PlannedExercise>[];

    for (final spec in specs) {
      var candidates = repo.query(
        category: spec.category,
        equipment: equipment,
        suitableFor: effectiveExp == 'advanced' ? null : effectiveExp,
        foundationalOnly: phase == 1,
        targetMuscles: spec.targetMuscles,
        excludeMuscles: spec.excludeMuscles,
        limit: spec.count + 4, // extra candidates for exclusion
      );

      // Exclude already-selected exercise names
      if (excludeNames != null && excludeNames.isNotEmpty) {
        candidates = candidates
            .where((c) => !excludeNames.contains(c['name'] as String? ?? ''))
            .toList();
      }

      // Also exclude exercises already picked in this variant
      final pickedNames = exercises.map((e) => e.exerciseName).toSet();
      candidates = candidates
          .where((c) => !pickedNames.contains(c['name'] as String? ?? ''))
          .toList();

      // Pick up to spec.count — compounds already sorted first by repo
      final selected = candidates.length <= spec.count
          ? candidates
          : candidates.sublist(0, spec.count);

      for (final ex in selected) {
        exercises.add(_buildExercise(ex));
      }
    }
    return exercises;
  }

  /// Build a PlannedExercise from an exercise map (with exercise defaults).
  static PlannedExercise _buildExercise(Map<String, dynamic> ex) {
    final equipRaw = ex['equipment_needed'];
    final equipList = equipRaw is List
        ? equipRaw.map((e) => e.toString()).toList()
        : <String>[];

    final musclesRaw = ex['primary_muscles'];
    final muscles = musclesRaw is List
        ? musclesRaw.map((m) => m.toString()).toList()
        : <String>[];

    final cues = ex['coaching_cues'];
    final notes = (cues is List && cues.isNotEmpty) ? cues.first.toString() : null;

    return PlannedExercise(
      exerciseId: ex['id'] as String? ?? '',
      exerciseName: ex['name'] as String? ?? 'Unknown',
      loggingType: ex['logging_type'] as String? ?? 'weight_reps',
      sets: ex['default_sets'] as int? ?? 3,
      reps: ex['default_reps'] as String? ?? '10',
      restSeconds: ex['default_rest_secs'] as int? ?? 60,
      durationSeconds: ex['default_duration_secs'] as int?,
      notes: notes,
      exerciseType: ex['exercise_type'] as String?,
      category: ex['category'] as String?,
      equipmentNeeded: equipList,
      primaryMuscles: muscles,
      variant: 'A',
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// STAGE 3: PERIODIZATION ENGINE
// ══════════════════════════════════════════════════════════════════

class _PeriodizationEngine {
  // Base parameters per intensity profile.
  static const _profileParams = <String, List<int>>{
    //                sets, reps, rest(s)
    'strength':      [4,    5,    150],
    'hypertrophy':   [3,    10,   75],
    'endurance':     [2,    18,   38],
  };

  // Volume wave: [sets multiplier desc, reps offset, weight cue, character]
  static const _waveNames = ['baseline', 'overreach', 'peak', 'deload'];
  static const _waveCues = [
    'Find working weight',
    'Same weight, more volume',
    '+2.5 kg if Week 2 felt good',
    'Light week — same weight, fewer sets. Come back stronger.',
  ];
  static const _waveNotes = [
    'Baseline week — learn the movements, find working weights.',
    'Overreach — extra set per exercise, push your limits.',
    'Peak intensity — heavier weight, fewer reps. Test yourself.',
    'Strategic recovery — your muscles grow during rest, not during lifting. Trust the process.',
  ];

  /// Produces 4 distinct WeekPlan objects from the populated split.
  static List<WeekPlan> apply({
    required List<_PopulatedDay> populated,
    required int phase,
    required bool is6Day,
  }) {
    return List.generate(4, (weekIdx) {
      // Determine which variant to use this week.
      // Week 0,2 = A; Week 1,3 = B. For 6-day: always A (A/B baked in).
      final useB = !is6Day && (weekIdx == 1 || weekIdx == 3);

      final workoutDays = <WorkoutDay>[];
      for (int d = 0; d < populated.length; d++) {
        final day = populated[d];
        final baseExercises = useB ? day.exercisesB : day.exercisesA;
        final profile = _profileParams[day.intensity] ?? _profileParams['hypertrophy']!;
        final baseSets = profile[0];
        final baseReps = profile[1];
        final baseRest = profile[2];

        // Apply volume wave to each exercise
        final adjusted = baseExercises.map((ex) {
          return _applyWave(ex, weekIdx, baseSets, baseReps, baseRest, day.intensity);
        }).toList();

        workoutDays.add(WorkoutDay(
          dayNumber: d + 1,
          name: day.name,
          focus: day.focus,
          exercises: adjusted,
        ));
      }

      return WeekPlan(
        weekNumber: (phase - 1) * 4 + weekIdx + 1,
        weekInPhase: weekIdx + 1,
        overloadNotes: _waveNotes[weekIdx],
        weekCharacter: _waveNames[weekIdx],
        workoutDays: workoutDays,
      );
    });
  }

  /// Apply DUP profile + volume wave to a single exercise.
  static PlannedExercise _applyWave(
    PlannedExercise ex, int weekIdx,
    int baseSets, int baseReps, int baseRest, String intensity,
  ) {
    final lt = ex.loggingType;
    // Only override sets/reps/rest for rep-based exercises.
    final isRepBased = lt == 'weight_reps' || lt == 'bodyweight_reps' ||
        lt == 'weighted_bodyweight' || lt == 'reps_only';

    if (!isRepBased) {
      // Timed/cardio/distance: keep exercise defaults, just apply set wave.
      final waveSets = _waveSets(ex.sets, weekIdx);
      return ex.copyWith(
        sets: waveSets,
        intensityProfile: intensity,
        weightCue: _waveCues[weekIdx],
        variant: ex.variant,
      );
    }

    // Rep-based: override with profile params + wave.
    final sets = _waveSets(baseSets, weekIdx);
    final reps = _waveReps(baseReps, weekIdx, intensity);
    final rest = baseRest;

    return ex.copyWith(
      sets: sets,
      reps: '$reps',
      restSeconds: rest,
      intensityProfile: intensity,
      weightCue: _waveCues[weekIdx],
      variant: ex.variant,
    );
  }

  /// Volume wave applied to sets.
  static int _waveSets(int base, int weekIdx) {
    switch (weekIdx) {
      case 0: return base;                              // baseline
      case 1: return base + 1;                          // overreach
      case 2: return base;                              // peak
      case 3: return max(1, (base * 0.6).floor());      // deload
      default: return base;
    }
  }

  /// Volume wave applied to reps.
  static int _waveReps(int base, int weekIdx, String intensity) {
    switch (weekIdx) {
      case 0: return base;                              // baseline
      case 1: return base;                              // overreach (same reps)
      case 2:                                           // peak: fewer reps
        return intensity == 'endurance' ? base - 1 : base - 2;
      case 3: return (base * 0.8).round();              // deload
      default: return base;
    }
  }
}

// ══════════════════════════════════════════════════════════════════
// STAGE 4: SUPERSET PAIRER
// ══════════════════════════════════════════════════════════════════

class _SupersetPairer {
  /// Antagonist muscle pair map. Key = muscle, Value = list of antagonists.
  static const _antagonists = <String, List<String>>{
    'chest':         ['lats', 'back', 'upper back', 'full back', 'rhomboids'],
    'upper chest':   ['lats', 'back', 'upper back'],
    'lower chest':   ['lats', 'back'],
    'lats':          ['chest', 'upper chest', 'lower chest'],
    'back':          ['chest', 'upper chest'],
    'upper back':    ['chest'],
    'front deltoid': ['rear deltoid', 'shoulders (rear)'],
    'deltoids':      ['rear deltoid'],
    'side deltoid':  ['rear deltoid'],
    'rear deltoid':  ['front deltoid', 'deltoids', 'side deltoid'],
    'biceps':        ['triceps'],
    'triceps':       ['biceps'],
    'quads':         ['hamstrings'],
    'quadriceps':    ['hamstrings'],
    'hamstrings':    ['quads', 'quadriceps'],
    'abs':           ['lower back', 'erector spinae'],
    'core':          ['lower back'],
    'lower back':    ['abs', 'core'],
    'hip flexors':   ['glutes'],
    'glutes':        ['hip flexors'],
  };

  /// Day types that get supersets.
  static const _supersetDays = {'legs', 'upper', 'full_body', 'shoulders_arms'};

  /// Pair exercises by antagonist muscles within each workout day.
  static List<WeekPlan> pair(List<WeekPlan> weeks) {
    return weeks.map((week) {
      final days = week.workoutDays.map((day) {
        // Find the dayType from the day name heuristic or pass-through.
        // We infer dayType from the existing data to avoid changing WorkoutDay.
        final dayType = _inferDayType(day);
        if (!_supersetDays.contains(dayType)) return day;

        final exercises = List<PlannedExercise>.from(day.exercises);
        if (exercises.length < 4) return day; // need at least 4 for a superset

        // First 2 exercises = standalone compounds (never superset).
        int groupIdx = 0;
        final paired = <int>{};

        for (int i = 2; i < exercises.length; i++) {
          if (paired.contains(i)) continue;
          final musclesI = _normalize(exercises[i].primaryMuscles);

          for (int j = i + 1; j < exercises.length; j++) {
            if (paired.contains(j)) continue;
            final musclesJ = _normalize(exercises[j].primaryMuscles);

            if (_areAntagonists(musclesI, musclesJ)) {
              exercises[i] = exercises[i].copyWith(supersetGroup: groupIdx);
              exercises[j] = exercises[j].copyWith(supersetGroup: groupIdx);
              paired.addAll([i, j]);
              groupIdx++;
              break;
            }
          }
        }

        return WorkoutDay(
          dayNumber: day.dayNumber,
          name: day.name,
          focus: day.focus,
          exercises: exercises,
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

  static List<String> _normalize(List<String>? muscles) =>
      muscles?.map((m) => m.toLowerCase()).toList() ?? [];

  static bool _areAntagonists(List<String> a, List<String> b) {
    for (final muscleA in a) {
      final antags = _antagonists[muscleA];
      if (antags == null) continue;
      for (final muscleB in b) {
        if (antags.contains(muscleB)) return true;
      }
    }
    return false;
  }

  /// Infer dayType from the workout day name.
  static String _inferDayType(WorkoutDay day) {
    final n = day.name.toLowerCase();
    if (n.contains('full body')) return 'full_body';
    if (n.contains('upper')) return 'upper';
    if (n.contains('shoulder') || n.contains('arms')) return 'shoulders_arms';
    if (n.contains('legs') || n.contains('lower') || n.contains('squat') || n.contains('deadlift')) return 'legs';
    if (n.contains('push') || n.contains('bench') || n.contains('chest') || n.contains('ohp')) return 'push';
    if (n.contains('pull') || n.contains('back')) return 'pull';
    return 'upper'; // default: allow supersets
  }
}

// ══════════════════════════════════════════════════════════════════
// STAGE 5: WARMUP & COOLDOWN SELECTOR
// ══════════════════════════════════════════════════════════════════

class _WarmupCooldownSelector {
  /// General cardio options (bodyweight — always available).
  static const _bodyweightCardio = ['Spot Jogging', 'Jumping Jacks'];

  /// Additional cardio options when user has gym equipment.
  static const _gymCardio = ['Jump Rope', 'Cycling (Stationary)', 'Running (Treadmill)'];

  /// Dynamic warm-up exercises per dayType, by experience tier.
  static const _dynamicWarmup = <String, Map<String, List<String>>>{
    'push': {
      'beginner': ['Arm Circles', 'Torso Twists', 'Wall Push Up'],
      'advanced': ['Arm Circles', 'Push Up', 'Band Pull Apart'],
    },
    'pull': {
      'beginner': ['Arm Circles', 'Wrist Rotations', 'Neck Rotations'],
      'advanced': ['Arm Circles', 'Dead Hang', 'Neck Rotations'],
    },
    'legs': {
      'beginner': ['High Knees', 'Leg Swings', 'Hip Circles'],
      'advanced': ['High Knees', 'Baithak (Hindu Squat)', 'Leg Swings'],
    },
    'upper': {
      'beginner': ['Arm Circles', 'Torso Twists', 'Wrist Rotations'],
      'advanced': ['Arm Circles', 'Push Up', 'Dead Hang'],
    },
    'full_body': {
      'beginner': ['Jumping Jacks', 'Arm Circles', 'Hip Circles'],
      'advanced': ['High Knees', 'Push Up', 'Baithak (Hindu Squat)'],
    },
    'shoulders_arms': {
      'beginner': ['Arm Circles', 'Wrist Rotations', 'Neck Rotations'],
      'advanced': ['Arm Circles', 'Wrist Rotations', 'Band Pull Apart'],
    },
  };

  /// Static stretch cool-down exercises per dayType.
  static const _cooldownStretches = <String, List<String>>{
    'push': ['Chest Doorway Stretch', 'Cross-body Shoulder Stretch', 'Overhead Stretch'],
    'pull': ['Standing Toe Touch', 'Cross-body Shoulder Stretch', 'Side Bend Stretch'],
    'legs': ['Standing Quad Stretch', 'Standing Toe Touch', 'Side Bend Stretch'],
    'upper': ['Chest Doorway Stretch', 'Standing Toe Touch', 'Cross-body Shoulder Stretch'],
    'full_body': ['Standing Toe Touch', 'Standing Quad Stretch', 'Chest Doorway Stretch'],
    'shoulders_arms': ['Cross-body Shoulder Stretch', 'Overhead Stretch', 'Deep Breathing'],
  };

  /// Attach warm-up and cool-down to every WorkoutDay in every WeekPlan.
  static List<WeekPlan> attach(
    List<WeekPlan> weeks,
    String effectiveExp,
    List<String> equipmentList,
  ) {
    final isAdvanced = effectiveExp != 'beginner';
    final hasGymEquipment = equipmentList.any(
        (e) => e.toLowerCase().contains('gym') || e.toLowerCase().contains('full'));

    // Build the full cardio pool.
    final cardioPool = [..._bodyweightCardio];
    if (hasGymEquipment) cardioPool.addAll(_gymCardio);

    return weeks.map((week) {
      final days = week.workoutDays.asMap().entries.map((entry) {
        final dayIndex = entry.key;
        final day = entry.value;
        final dayType = _inferDayType(day);

        // --- WARM-UP ---
        final warmup = <PlannedExercise>[];

        // 1. General cardio (rotate by day index for variety).
        final cardioName = cardioPool[dayIndex % cardioPool.length];
        warmup.add(_timedExercise(cardioName, '300', 'warmup'));

        // 2. Workout-specific dynamic (3 exercises).
        final tier = isAdvanced ? 'advanced' : 'beginner';
        final dynamicMap = _dynamicWarmup[dayType] ?? _dynamicWarmup['upper']!;
        final dynamicList = dynamicMap[tier] ?? dynamicMap['beginner']!;
        for (final name in dynamicList) {
          warmup.add(_warmupExercise(name));
        }

        // --- COOL-DOWN ---
        final cooldown = <PlannedExercise>[];

        // 1. Walk-off.
        cooldown.add(_timedExercise('Slow Walking', '300', 'cooldown'));

        // 2. Static stretches (3 exercises).
        final stretches = _cooldownStretches[dayType] ?? _cooldownStretches['upper']!;
        for (final name in stretches) {
          cooldown.add(_timedExercise(name, '30', 'cooldown'));
        }

        return WorkoutDay(
          dayNumber: day.dayNumber,
          name: day.name,
          focus: day.focus,
          exercises: day.exercises,
          warmup: warmup,
          cooldown: cooldown,
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

  /// Create a timed exercise (cardio warm-up, walk-off, stretches).
  static PlannedExercise _timedExercise(String name, String duration, String category) {
    return PlannedExercise(
      exerciseId: name,
      exerciseName: name,
      loggingType: 'timed',
      sets: 1,
      reps: '${duration}s',
      restSeconds: 0,
      category: category,
    );
  }

  /// Create a warm-up exercise. Activation exercises (Push Up, Baithak, etc.)
  /// get bodyweight_reps logging; dynamic stretches get timed logging.
  static PlannedExercise _warmupExercise(String name) {
    // Activation exercises use bodyweight_reps with low volume.
    const activationExercises = {
      'Push Up', 'Wall Push Up', 'Baithak (Hindu Squat)', 'Band Pull Apart',
    };
    if (activationExercises.contains(name)) {
      return PlannedExercise(
        exerciseId: name,
        exerciseName: name,
        loggingType: 'bodyweight_reps',
        sets: 1,
        reps: '10',
        restSeconds: 0,
        category: 'warmup',
      );
    }

    // Dead Hang is timed activation.
    if (name == 'Dead Hang') {
      return _timedExercise(name, '30', 'warmup');
    }

    // Dynamic stretches: default timed durations.
    const durationMap = <String, String>{
      'Arm Circles': '60',
      'Neck Rotations': '30',
      'Torso Twists': '60',
      'Hip Circles': '60',
      'Leg Swings': '60',
      'Wrist Rotations': '30',
      'Ankle Rotations': '30',
      'Jumping Jacks': '60',
      'High Knees': '60',
      'Butt Kicks': '60',
      'Spot Jogging': '60',
    };
    final dur = durationMap[name] ?? '60';
    return _timedExercise(name, dur, 'warmup');
  }

  /// Infer dayType from workout name (same logic as _SupersetPairer).
  static String _inferDayType(WorkoutDay day) {
    final n = day.name.toLowerCase();
    if (n.contains('full body')) return 'full_body';
    if (n.contains('upper')) return 'upper';
    if (n.contains('shoulder') || n.contains('arms')) return 'shoulders_arms';
    if (n.contains('legs') || n.contains('lower') || n.contains('squat') || n.contains('deadlift')) return 'legs';
    if (n.contains('push') || n.contains('bench') || n.contains('chest') || n.contains('ohp')) return 'push';
    if (n.contains('pull') || n.contains('back')) return 'pull';
    return 'upper'; // default
  }
}

// ══════════════════════════════════════════════════════════════════
// DATA CLASSES
// ══════════════════════════════════════════════════════════════════

class Phase {
  final int phase;
  final String name;
  final String focus;
  final String weeks;
  final int dailyCalories;
  final int proteinGrams;
  final List<WorkoutDay> workouts; // backward compat: week 1
  final List<WeekPlan> weekPlans;
  final List<int>? preferredDays;

  const Phase({
    required this.phase,
    required this.name,
    required this.focus,
    required this.weeks,
    required this.dailyCalories,
    required this.proteinGrams,
    required this.workouts,
    required this.weekPlans,
    this.preferredDays,
  });

  Map<String, dynamic> toMap() => {
        'phase': phase,
        'name': name,
        'focus': focus,
        'weeks': weeks,
        'daily_calories': dailyCalories,
        'protein_grams': proteinGrams,
        'workouts': workouts.map((w) => w.toMap()).toList(),
        'week_plans': weekPlans.map((w) => w.toMap()).toList(),
        if (preferredDays != null) 'preferred_days': preferredDays,
      };
}

class WeekPlan {
  final int weekNumber;
  final int weekInPhase;
  final String overloadNotes;
  final String weekCharacter; // baseline | overreach | peak | deload
  final List<WorkoutDay> workoutDays;

  const WeekPlan({
    required this.weekNumber,
    required this.weekInPhase,
    required this.overloadNotes,
    this.weekCharacter = 'baseline',
    required this.workoutDays,
  });

  Map<String, dynamic> toMap() => {
        'week_number': weekNumber,
        'week_in_phase': weekInPhase,
        'overload_notes': overloadNotes,
        'week_character': weekCharacter,
        'workout_days': workoutDays.map((d) => d.toMap()).toList(),
      };
}

class WorkoutDay {
  final int dayNumber;
  final String name;
  final String focus;
  final List<PlannedExercise> exercises;
  final List<PlannedExercise> warmup;
  final List<PlannedExercise> cooldown;

  const WorkoutDay({
    required this.dayNumber,
    required this.name,
    required this.focus,
    required this.exercises,
    this.warmup = const [],
    this.cooldown = const [],
  });

  Map<String, dynamic> toMap() => {
        'day_number': dayNumber,
        'name': name,
        'focus': focus,
        'exercises': exercises.map((e) => e.toMap()).toList(),
        if (warmup.isNotEmpty)
          'warmup': warmup.map((e) => e.toMap()).toList(),
        if (cooldown.isNotEmpty)
          'cooldown': cooldown.map((e) => e.toMap()).toList(),
      };
}

class PlannedExercise {
  final String exerciseId;
  final String exerciseName;
  final String loggingType;
  final int sets;
  final String reps;
  final int restSeconds;
  final int? durationSeconds;
  final String? notes;
  final String? exerciseType;
  final int? supersetGroup;
  final String? category;
  final List<String>? equipmentNeeded;
  // V2 fields
  final String intensityProfile; // strength | hypertrophy | endurance
  final String? weightCue;
  final String variant; // A | B
  final List<String>? primaryMuscles;

  const PlannedExercise({
    required this.exerciseId,
    required this.exerciseName,
    required this.loggingType,
    required this.sets,
    required this.reps,
    required this.restSeconds,
    this.durationSeconds,
    this.notes,
    this.exerciseType,
    this.supersetGroup,
    this.category,
    this.equipmentNeeded,
    this.intensityProfile = 'hypertrophy',
    this.weightCue,
    this.variant = 'A',
    this.primaryMuscles,
  });

  PlannedExercise copyWith({
    int? sets,
    String? reps,
    int? restSeconds,
    String? notes,
    int? supersetGroup,
    String? intensityProfile,
    String? weightCue,
    String? variant,
    List<String>? primaryMuscles,
  }) {
    return PlannedExercise(
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      loggingType: loggingType,
      sets: sets ?? this.sets,
      reps: reps ?? this.reps,
      restSeconds: restSeconds ?? this.restSeconds,
      durationSeconds: durationSeconds,
      notes: notes ?? this.notes,
      exerciseType: exerciseType,
      supersetGroup: supersetGroup ?? this.supersetGroup,
      category: category,
      equipmentNeeded: equipmentNeeded,
      intensityProfile: intensityProfile ?? this.intensityProfile,
      weightCue: weightCue ?? this.weightCue,
      variant: variant ?? this.variant,
      primaryMuscles: primaryMuscles ?? this.primaryMuscles,
    );
  }

  Map<String, dynamic> toMap() => {
        'exercise_id': exerciseId,
        'exercise_name': exerciseName,
        'logging_type': loggingType,
        'sets': sets,
        'reps': reps,
        'rest_seconds': restSeconds,
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
        if (notes != null) 'notes': notes,
        if (exerciseType != null) 'exercise_type': exerciseType,
        if (supersetGroup != null) 'superset_group': supersetGroup,
        if (category != null) 'category': category,
        if (equipmentNeeded != null) 'equipment_needed': equipmentNeeded,
        'intensity_profile': intensityProfile,
        if (weightCue != null) 'weight_cue': weightCue,
        'variant': variant,
        if (primaryMuscles != null) 'primary_muscles': primaryMuscles,
      };
}

// ══════════════════════════════════════════════════════════════════
// PRIVATE HELPERS
// ══════════════════════════════════════════════════════════════════

/// Category spec for exercise queries.
class _CSpec {
  final String category;
  final int count;
  final List<String>? targetMuscles;
  final List<String>? excludeMuscles;

  const _CSpec(this.category, this.count, {
    List<String>? target,
    List<String>? exclude,
  }) : targetMuscles = target, excludeMuscles = exclude;
}

/// A day slot in the split plan.
class _DaySlot {
  final String name;
  final String focus;
  final String dayType;     // push | pull | legs | upper | full_body | shoulders_arms
  final String intensity;   // strength | hypertrophy | endurance
  final List<_CSpec> specsA;
  final List<_CSpec>? specsB; // null = same as A (variety via exclusion or 6-day)

  const _DaySlot({
    required this.name,
    required this.focus,
    required this.dayType,
    required this.intensity,
    required this.specsA,
    this.specsB,
  });
}

/// Populated day with selected exercises for both variants.
class _PopulatedDay {
  final String name;
  final String focus;
  final String dayType;
  final String intensity;
  final List<PlannedExercise> exercisesA;
  final List<PlannedExercise> exercisesB;

  const _PopulatedDay({
    required this.name,
    required this.focus,
    required this.dayType,
    required this.intensity,
    required this.exercisesA,
    required this.exercisesB,
  });
}

class _PhaseMeta {
  final String name;
  final String focus;
  final int dailyCalories;
  final int proteinGrams;

  const _PhaseMeta({
    required this.name,
    required this.focus,
    required this.dailyCalories,
    required this.proteinGrams,
  });
}
