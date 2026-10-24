import 'dart:math';

import 'budget_muscle_groups.dart';
import 'models.dart';
import 'session_budget.dart';

/// Stage 4: Periodization — 4 cycling archetypes + volume wave.
///
/// V3 changes:
/// - 4 phase archetypes cycling (hypertrophy → strength → metabolic → deload)
/// - 4-set minimum for intermediate+ (except deload)
/// - Volume progression across cycles (+10% per cycle)
/// - Body focus: +1 set on matching exercises
/// - Suggested starting weights from ProgressionResolver
class PeriodizationEngine {
  /// V3: Resolve archetype from phase number (cycling every 4 phases).
  static String archetypeForPhase(int phase) {
    const archetypes = ['hypertrophy', 'strength', 'metabolic', 'deload'];
    return archetypes[((phase - 1) % 4)];
  }

  /// V3: Volume multiplier per cycle (phases 1-4 = 1.0, 5-8 = 1.1, 9-12 = 1.2,
  /// 13-16 = 1.3).
  ///
  /// 2026-05-31 (post-12 deployment cycles): the ramp is CAPPED at cycle 3
  /// (1.3×). Beyond ~phase 16, continued progressive overload comes from LOAD
  /// — the autoregulated weight progression in the plan engine
  /// (TrainingHistoryAnalyzer / ProgressionResolver) — NOT from an ever-growing
  /// set count, which would become junk volume on the open-ended deployment
  /// rotation that carries a user from phase 13 to Lieutenant (~phase 32).
  static double cycleMultiplier(int phase) {
    final cycle = ((phase - 1) ~/ 4); // 0, 1, 2, 3, ...
    final cappedCycle = cycle > 3 ? 3 : cycle;
    return 1.0 + (cappedCycle * 0.1);
  }

  // ── V2 DUP profiles (used within each archetype for daily variation) ──

  static const _profileParams = <String, List<int>>{
    //                sets, reps, rest(s)
    'strength':      [4,    5,    150],
    'hypertrophy':   [3,    10,   75],
    'endurance':     [2,    18,   38],
  };

  // Volume wave names and cues
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
  ///
  /// V3: Uses archetype parameters for the phase, applies 4-set minimum
  /// for intermediate+, and stamps suggested weights.
  static List<WeekPlan> apply({
    required List<PopulatedDay> populated,
    required int phase,
    required bool is6Day,
    String effectiveExp = 'intermediate',
    List<String> bodyFocus = const [],
    Map<String, double>? previousWeights,
    // ⑥ 7-B-1 (W2.4): when true, the deload week (weekIdx 3) ALSO stashes the
    // peak-equivalent working sets/reps per exercise (for a lossless un-deload).
    // Resolved upstream from PlanEngineFlags.triggeredDeloadEnabled (ship-dark OFF)
    // so this stage stays pure (no Hive read).
    bool stashWorkingBase = false,
    // B2 (session set budget): when non-null each exercise's baseline is the sets
    // the allocator gave it (no cycle multiplier, no 4-set minimum, no physique
    // +1), week 2 adds a set only where the ledger allows, and week 4 is
    // floor(0.6 x that exercise's own baseline). null -> everything below verbatim.
    SessionBudgetContext? budget,
  }) {
    if (budget != null) {
      return _applyBudgeted(
        populated: populated,
        phase: phase,
        is6Day: is6Day,
        effectiveExp: effectiveExp,
        previousWeights: previousWeights,
        stashWorkingBase: stashWorkingBase,
        budget: budget,
      );
    }
    final archetype = archetypeForPhase(phase);
    final multiplier = cycleMultiplier(phase);
    final isBeginner = effectiveExp == 'beginner';
    final isDeload = archetype == 'deload';

    return List.generate(4, (weekIdx) {
      final useB = !is6Day && (weekIdx == 1 || weekIdx == 3);

      final workoutDays = <WorkoutDay>[];
      for (int d = 0; d < populated.length; d++) {
        final day = populated[d];
        final baseExercises = useB ? day.exercisesB : day.exercisesA;
        final profile = _profileParams[day.intensity] ?? _profileParams['hypertrophy']!;
        final baseSets = profile[0];
        final baseReps = profile[1];
        final baseRest = profile[2];

        final adjusted = baseExercises.map((ex) {
          var exercise = _applyWave(
            ex, weekIdx, baseSets, baseReps, baseRest, day.intensity,
            isBeginner: isBeginner, isDeload: isDeload, multiplier: multiplier,
            archetype: archetype,
          );

          // V3: Body focus — +1 set on matching exercises
          if (bodyFocus.isNotEmpty && exercise.primaryMuscles != null) {
            final muscles = exercise.primaryMuscles!.map((m) => m.toLowerCase()).toList();
            for (final focus in bodyFocus) {
              if (muscles.any((m) => m.contains(focus.toLowerCase()))) {
                exercise = exercise.copyWith(sets: exercise.sets + 1);
                break;
              }
            }
          }

          // V3: Suggested starting weight from ProgressionResolver
          if (previousWeights != null && previousWeights.containsKey(exercise.exerciseName)) {
            exercise = exercise.copyWith(
              suggestedWeight: previousWeights[exercise.exerciseName],
              weightCue: '${previousWeights[exercise.exerciseName]!.toStringAsFixed(1)} kg (from last phase + progression)',
            );
          }

          // ⑥ 7-B-1 (W2.4): on the DELOAD week (weekIdx 3), stash the peak-
          // equivalent (weekIdx 2) working sets/reps so a triggered deload can be
          // un-deloaded losslessly — the deload cut max(1,(base*0.6).floor()) is
          // non-invertible. Full _applyWave(...,2,...) reuse (exact multiplier /
          // min-4 clamp / rep-range path) on the SAME (week-4 variant-B) exercise
          // `ex`, plus the SAME body-focus +1. Written via copyWith so the superset
          // pairer (stage 6, after this) preserves it (the `?? this.workingSets` idiom).
          if (weekIdx == 3 && stashWorkingBase) {
            final peak = _applyWave(
              ex, 2, baseSets, baseReps, baseRest, day.intensity,
              isBeginner: isBeginner,
              isDeload: isDeload,
              multiplier: multiplier,
              archetype: archetype,
            );
            var peakSets = peak.sets;
            if (bodyFocus.isNotEmpty && exercise.primaryMuscles != null) {
              final muscles =
                  exercise.primaryMuscles!.map((m) => m.toLowerCase()).toList();
              for (final focus in bodyFocus) {
                if (muscles.any((m) => m.contains(focus.toLowerCase()))) {
                  peakSets += 1;
                  break;
                }
              }
            }
            exercise =
                exercise.copyWith(workingSets: peakSets, workingReps: peak.reps);
          }

          return exercise;
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

  // -- B2: the budgeted path ---------------------------------------------------

  /// `apply` under a [SessionBudgetContext]. The reps, rest, cue and note logic is
  /// `_applyWave`'s, untouched; only the SETS differ, because the allocator has
  /// already sized every exercise by the user's minutes:
  /// - weeks 1 and 3: the allocated sets;
  /// - week 2: +1 where the ledger allows (see [_weekTwoGains]); an exercise that
  ///   gained nothing carries week 1's cue, and the week keeps week 1's note when
  ///   nothing gained (Ruling 11);
  /// - week 4: `max(1, floor(0.6 x that exercise's own allocated sets))`;
  /// - the stash (`workingSets`) is that same exercise's allocated sets.
  /// Body focus is already inside the allocator (the focus groups), so the
  /// physique +1 is not applied here.
  static List<WeekPlan> _applyBudgeted({
    required List<PopulatedDay> populated,
    required int phase,
    required bool is6Day,
    required String effectiveExp,
    required Map<String, double>? previousWeights,
    required bool stashWorkingBase,
    required SessionBudgetContext budget,
  }) {
    final archetype = archetypeForPhase(phase);
    final isBeginner = effectiveExp == 'beginner';
    final isDeload = archetype == 'deload';

    return List.generate(4, (weekIdx) {
      final useB = !is6Day && (weekIdx == 1 || weekIdx == 3);
      final gains = weekIdx == 1 ? _weekTwoGains(populated, useB, budget) : const <(int, int)>{};

      final workoutDays = <WorkoutDay>[];
      for (int d = 0; d < populated.length; d++) {
        final day = populated[d];
        final baseExercises = useB ? day.exercisesB : day.exercisesA;
        final profile = _profileParams[day.intensity] ?? _profileParams['hypertrophy']!;
        final baseSets = profile[0];
        final baseReps = profile[1];
        final baseRest = profile[2];

        final adjusted = <PlannedExercise>[];
        for (int i = 0; i < baseExercises.length; i++) {
          final ex = baseExercises[i];
          var exercise = _applyWave(
            ex, weekIdx, baseSets, baseReps, baseRest, day.intensity,
            isBeginner: isBeginner, isDeload: isDeload, multiplier: 1.0,
            archetype: archetype,
          );
          final gained = gains.contains((d, i));
          final sets = switch (weekIdx) {
            1 => ex.sets + (gained ? 1 : 0),
            3 => max(1, (ex.sets * 0.6).floor()),
            _ => ex.sets,
          };
          exercise = exercise.copyWith(sets: sets);
          if (weekIdx == 1 && !gained) exercise = exercise.copyWith(weightCue: _waveCues[0]);

          if (previousWeights != null && previousWeights.containsKey(exercise.exerciseName)) {
            exercise = exercise.copyWith(
              suggestedWeight: previousWeights[exercise.exerciseName],
              weightCue: '${previousWeights[exercise.exerciseName]!.toStringAsFixed(1)} kg (from last phase + progression)',
            );
          }

          if (weekIdx == 3 && stashWorkingBase) {
            final peak = _applyWave(
              ex, 2, baseSets, baseReps, baseRest, day.intensity,
              isBeginner: isBeginner, isDeload: isDeload, multiplier: 1.0,
              archetype: archetype,
            );
            exercise = exercise.copyWith(workingSets: ex.sets, workingReps: peak.reps);
          }
          adjusted.add(exercise);
        }

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
        overloadNotes: weekIdx == 1 && gains.isEmpty ? _waveNotes[0] : _waveNotes[weekIdx],
        weekCharacter: _waveNames[weekIdx],
        workoutDays: workoutDays,
      );
    });
  }

  /// Which exercises get week 2's extra set, as (day, index in that day's list).
  ///
  /// A fresh ledger is seeded with the week's baseline: every exercise's sets (a
  /// not-budgeted row spends time only, at its own rest when timed and at the
  /// day's rest when rep-based). Then budgeted exercises are visited rank-major
  /// across the days, as the allocator's pass A does, and each gains a set when
  /// the ledger says it fits and it is under the per-exercise limit. Not-budgeted
  /// rows come last (they are not part of the priority order) and gain a set only
  /// when the day's time allows (Ruling 8).
  static Set<(int, int)> _weekTwoGains(
      List<PopulatedDay> populated, bool useB, SessionBudgetContext budget) {
    final n = populated.length;
    final ledger = BudgetLedger(budget, n);
    final ranked = List.generate(n, (_) => <int>[]);
    final unranked = <(int, int)>[];
    final groups = <(int, int), Set<String>>{};
    final restOf = <(int, int), int>{};

    for (var d = 0; d < n; d++) {
      final list = useB ? populated[d].exercisesB : populated[d].exercisesA;
      final dayRest = SessionBudget.restFor(populated[d].intensity);
      for (var i = 0; i < list.length; i++) {
        final ex = list[i];
        final budgeted = SessionBudget.isBudgeted(ex, budget);
        final rest = budgeted || _isRepBased(ex.loggingType) ? dayRest : ex.restSeconds;
        restOf[(d, i)] = rest;
        final g = budgeted
            ? BudgetMuscleGroups.of(ex.primaryMuscles ?? const [])
            : const <String>{};
        groups[(d, i)] = g;
        ledger.add(
          d,
          g,
          budgeted ? ex.sets : 0,
          SessionBudget.exerciseSeconds(
            archetype: SessionBudget.archetypeOfPlanned(ex, budget),
            sets: ex.sets,
            restSeconds: rest,
          ),
        );
        if (budgeted) {
          ranked[d].add(i);
        } else {
          unranked.add((d, i));
        }
      }
    }

    final gained = <(int, int)>{};
    void tryGain(int d, int i, {required bool budgeted}) {
      final ex = (useB ? populated[d].exercisesB : populated[d].exercisesA)[i];
      if (budgeted && ex.sets >= SessionBudget.maxSetsPerExercise) return;
      final arch = SessionBudget.archetypeOfPlanned(ex, budget);
      final rest = restOf[(d, i)]!;
      final dt = SessionBudget.exerciseSeconds(archetype: arch, sets: ex.sets + 1, restSeconds: rest) -
          SessionBudget.exerciseSeconds(archetype: arch, sets: ex.sets, restSeconds: rest);
      if (!ledger.fits(d, groups[(d, i)]!, 1, dt)) return;
      ledger.add(d, groups[(d, i)]!, budgeted ? 1 : 0, dt);
      gained.add((d, i));
    }

    var maxRank = 0;
    for (final r in ranked) {
      if (r.length > maxRank) maxRank = r.length;
    }
    for (var rank = 0; rank < maxRank; rank++) {
      for (var d = 0; d < n; d++) {
        if (rank < ranked[d].length) tryGain(d, ranked[d][rank], budgeted: true);
      }
    }
    for (final (d, i) in unranked) {
      tryGain(d, i, budgeted: false);
    }
    return gained;
  }

  static bool _isRepBased(String loggingType) =>
      loggingType == 'weight_reps' ||
      loggingType == 'bodyweight_reps' ||
      loggingType == 'weighted_bodyweight' ||
      loggingType == 'reps_only';

  /// Apply DUP profile + volume wave to a single exercise.
  ///
  /// V3: Applies 4-set minimum for intermediate+, cycle multiplier.
  /// V4: Uses exercise-specific rep_range when available; archetype selects
  ///     which end of that range to lean toward instead of fixed DUP reps.
  static PlannedExercise _applyWave(
    PlannedExercise ex, int weekIdx,
    int baseSets, int baseReps, int baseRest, String intensity, {
    required bool isBeginner,
    required bool isDeload,
    required double multiplier,
    required String archetype,
  }) {
    final lt = ex.loggingType;
    final isRepBased = lt == 'weight_reps' || lt == 'bodyweight_reps' ||
        lt == 'weighted_bodyweight' || lt == 'reps_only';

    if (!isRepBased) {
      final waveSets = _waveSets(ex.sets, weekIdx);
      return ex.copyWith(
        sets: waveSets,
        intensityProfile: intensity,
        weightCue: _waveCues[weekIdx],
        variant: ex.variant,
      );
    }

    // V3: Apply cycle multiplier to sets
    var sets = (baseSets * multiplier).round();
    sets = _waveSets(sets, weekIdx);

    // V3: 4-set minimum for intermediate+ (except deload)
    if (!isBeginner && !isDeload && weekIdx != 3) {
      sets = max(4, sets);
    }

    // V4: Use exercise-specific rep range when available.
    // Archetype determines which side of the range to lean toward:
    //   strength   → lower end (min reps, heavier weight)
    //   hypertrophy → midpoint
    //   metabolic  → upper end (more reps, lighter weight)
    //   deload     → midpoint (same range, reduced sets & load)
    // Shared parser (W2.1 F2) — one `parseRepRange` for both this wave and the
    // ProgressionResolver banding, so a 2nd hand-rolled split can't drift. Null
    // (no/invalid range) → the legacy baseReps path, byte-identical on real data
    // (pinned by periodization_wave_reps_invariant_test.dart).
    final parsed = parseRepRange(ex.repRange);
    int reps;
    if (parsed != null) {
      final (minReps, maxReps) = parsed;
      final midReps = ((minReps + maxReps) / 2).round();

      reps = switch (archetype) {
        'strength'    => minReps,
        'metabolic'   => maxReps,
        'deload'      => midReps,
        _             => midReps, // 'hypertrophy' and any unknown
      };

      // Apply wave modifier on top of archetype selection
      reps = _waveReps(reps, weekIdx, intensity);
      // Clamp to keep within library-defined bounds (wave can nudge but not escape)
      reps = reps.clamp(minReps, maxReps);
    } else {
      // Fallback: legacy DUP baseReps path (no/invalid rep_range in library)
      reps = _waveReps(baseReps, weekIdx, intensity);
    }

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
      case 0: return base;
      case 1: return base + 1;
      case 2: return base;
      case 3: return max(1, (base * 0.6).floor());
      default: return base;
    }
  }

  /// Volume wave applied to reps.
  static int _waveReps(int base, int weekIdx, String intensity) {
    switch (weekIdx) {
      case 0: return base;
      case 1: return base;
      case 2:
        return intensity == 'endurance' ? base - 1 : base - 2;
      case 3: return (base * 0.8).round();
      default: return base;
    }
  }
}
