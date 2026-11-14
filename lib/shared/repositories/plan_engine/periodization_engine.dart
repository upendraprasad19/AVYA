import 'dart:math';

import 'budget_muscle_groups.dart';
import 'models.dart';
import 'plan_engine_flags.dart';
import 'sequencing_engine.dart';
import 'session_budget.dart';

/// Stage 4: Periodization — 4 cycling archetypes + volume wave.
///
/// V3 changes:
/// - 4 phase archetypes cycling (hypertrophy → strength → metabolic → deload)
/// - Sets come from the session set budget allocator (B2, 2026-11-02)
/// - Suggested starting weights from ProgressionResolver
class PeriodizationEngine {
  /// V3: Resolve archetype from phase number (cycling every 4 phases).
  static String archetypeForPhase(int phase) {
    const archetypes = ['hypertrophy', 'strength', 'metabolic', 'deload'];
    return archetypes[((phase - 1) % 4)];
  }

  // ── V2 DUP profiles (used within each archetype for daily variation) ──

  static const _profileParams = <String, List<int>>{
    // Reps only. The sets column went with the flip (2026-11-02: the allocator
    // sizes every exercise's sets) and the rest column went with OI-456: the rest
    // follows the EXERCISE (`SessionBudget.restForArchetype`), not the day.
    //                reps
    'strength':      [5],
    'hypertrophy':   [10],
    'endurance':     [18],
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

  /// Produces 4 distinct WeekPlan objects from the populated split, sized by the
  /// session set budget (B2, flipped ON 2026-11-02; the unbudgeted body, the cycle
  /// multiplier, the 4-set minimum and the post-hoc physique +1 are deleted).
  ///
  /// The reps, rest (by the exercise's archetype), cue and note logic is `_applyWave`'s; only the SETS differ,
  /// because the allocator has already sized every exercise by the user's minutes:
  /// - weeks 1 and 3: the allocated sets;
  /// - week 2: +1 where the ledger allows (see [_weekTwoGains]); an exercise that
  ///   gained nothing carries week 1's cue, and the week keeps week 1's note when
  ///   nothing gained (Ruling 11);
  /// - week 4: `min(sets, max(2, floor(0.6 x that exercise's own allocated sets)))`,
  ///   so 1 stays 1, 2 stays 2, 3 and 4 become 2, 5 becomes 3 (OI-456: a floor of 2,
  ///   never RAISING a row);
  /// - the stash (`workingSets`) is that same exercise's allocated sets.
  /// Body focus is already inside the allocator (the focus groups), so the
  /// physique +1 is not applied here.
  ///
  /// [stashWorkingBase] — ⑥ 7-B-1 (W2.4): the deload week (weekIdx 3) ALSO stashes
  /// the peak-equivalent working sets/reps per exercise (for a lossless un-deload).
  /// Resolved upstream from PlanEngineFlags.triggeredDeloadEnabled.
  ///
  /// [leadFirst] — Unit 2A (OI-486), R5: week 2 holds a row that is not its day's lead to the lead's week-2 sets + 1
  /// (see [_weekTwoGains]). Null reads the kill switch `PlanEngineFlags.leadFirstEnabled` (default ON), this stage's
  /// one Hive read; a caller that passes it keeps the stage pure.
  static List<WeekPlan> apply({
    required List<PopulatedDay> populated,
    required int phase,
    required bool is6Day,
    Map<String, double>? previousWeights,
    bool stashWorkingBase = false,
    required SessionBudgetContext budget,
    bool? leadFirst,
  }) {
    final archetype = archetypeForPhase(phase);
    final capToLead = leadFirst ?? PlanEngineFlags.leadFirstEnabled;

    return List.generate(4, (weekIdx) {
      final useB = !is6Day && (weekIdx == 1 || weekIdx == 3);
      final gains = weekIdx == 1
          ? _weekTwoGains(populated, useB, budget, capToLead: capToLead)
          : const <(int, int)>{};

      final workoutDays = <WorkoutDay>[];
      for (int d = 0; d < populated.length; d++) {
        final day = populated[d];
        final baseExercises = useB ? day.exercisesB : day.exercisesA;
        final profile = _profileParams[day.intensity] ?? _profileParams['hypertrophy']!;
        final baseReps = profile[0];

        final adjusted = <PlannedExercise>[];
        for (int i = 0; i < baseExercises.length; i++) {
          final ex = baseExercises[i];
          // OI-456: the rest follows the exercise, the same value the allocator priced.
          final restSeconds =
              SessionBudget.restForArchetype(SessionBudget.archetypeOfPlanned(ex, budget));
          var exercise = _applyWave(
            ex, weekIdx, baseReps, restSeconds, day.intensity,
            archetype: archetype,
          );
          final gained = gains.contains((d, i));
          final sets = switch (weekIdx) {
            1 => ex.sets + (gained ? 1 : 0),
            3 => min(ex.sets, max(2, (ex.sets * 0.6).floor())),
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
              ex, 2, baseReps, restSeconds, day.intensity,
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
  ///
  /// [capToLead] (Unit 2A, R5): a row that is not its day's lead (`SequencingEngine.openerOf` over the day's budgeted
  /// rows, the allocator's definition) and credits no focus group, a not-budgeted row included, gains only while its
  /// week-2 sets stay at most the lead's week-2 sets + 1 (founder d26, d27).
  static Set<(int, int)> _weekTwoGains(
      List<PopulatedDay> populated, bool useB, SessionBudgetContext budget, {required bool capToLead}) {
    final n = populated.length;
    // Unit 2C-b (S4): week 2's +1 sees the allocation's own day budget: the allowance when the allocator used it.
    final ledger = BudgetLedger(budget, n, allowance: populated.isNotEmpty && populated.first.allowance);
    final ranked = List.generate(n, (_) => <int>[]);
    final unranked = <(int, int)>[];
    final groups = <(int, int), Set<String>>{};
    final restOf = <(int, int), int>{};

    for (var d = 0; d < n; d++) {
      final list = useB ? populated[d].exercisesB : populated[d].exercisesA;
      for (var i = 0; i < list.length; i++) {
        final ex = list[i];
        final budgeted = SessionBudget.isBudgeted(ex, budget);
        // OI-456: a budgeted row and a rep-based custom are priced at their archetype's rest,
        // exactly as the allocator priced them (`ex.restSeconds` is still the selector default
        // here: rests are stamped by `apply` AFTER this runs); a timed row keeps its own.
        final rest = budgeted || SessionBudget.isRepBased(ex.loggingType)
            ? SessionBudget.restForArchetype(SessionBudget.archetypeOfPlanned(ex, budget))
            : ex.restSeconds;
        restOf[(d, i)] = rest;
        final g = budgeted
            ? BudgetMuscleGroups.creditedOf(ex.primaryMuscles ?? const [],
                quadPrimaryCreditsGlutes: budget.quadPrimaryCreditsGlutes)
            : const <String>{};
        groups[(d, i)] = g;
        // A row that is not budgeted has no groups: only its time is spent.
        ledger.add(
          d,
          g,
          ex.sets,
          SessionBudget.plannedExerciseSeconds(ex, budget, sets: ex.sets, restSeconds: rest),
        );
        if (budgeted) {
          ranked[d].add(i);
        } else {
          unranked.add((d, i));
        }
      }
    }

    // Unit 2A, R5: each day's lead, as an index into the week's list (-1: no budgeted row, or the rule is off).
    final lead = List<int>.filled(n, -1);
    if (capToLead) {
      for (var d = 0; d < n; d++) {
        final list = useB ? populated[d].exercisesB : populated[d].exercisesA;
        final opener = SequencingEngine.openerOf([for (final i in ranked[d]) list[i]]);
        lead[d] = ranked[d].firstWhere((i) => identical(list[i], opener), orElse: () => -1);
      }
    }

    final gained = <(int, int)>{};
    void tryGain(int d, int i, {required bool budgeted}) {
      final list = useB ? populated[d].exercisesB : populated[d].exercisesA;
      final ex = list[i];
      if (budgeted && ex.sets >= SessionBudget.maxSetsPerExercise) return;
      final l = lead[d];
      if (l >= 0 && l != i && !groups[(d, i)]!.any(budget.focusGroups.contains)) {
        final leadSets = list[l].sets + (gained.contains((d, l)) ? 1 : 0);
        if (ex.sets + 1 > leadSets + 1) return;
      }
      final rest = restOf[(d, i)]!;
      final dt = SessionBudget.plannedExerciseSeconds(ex, budget, sets: ex.sets + 1, restSeconds: rest) -
          SessionBudget.plannedExerciseSeconds(ex, budget, sets: ex.sets, restSeconds: rest);
      if (!ledger.fits(d, groups[(d, i)]!, 1, dt)) return;
      ledger.add(d, groups[(d, i)]!, 1, dt);
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

  /// Apply DUP profile + volume wave to a single exercise.
  ///
  /// Sets are NOT touched here (the allocator sized them; `apply` writes week sets).
  /// V4: Uses exercise-specific rep_range when available; archetype selects
  ///     which end of that range to lean toward instead of fixed DUP reps.
  static PlannedExercise _applyWave(
    PlannedExercise ex, int weekIdx,
    int baseReps, int baseRest, String intensity, {
    required String archetype,
  }) {
    final isRepBased = SessionBudget.isRepBased(ex.loggingType);

    if (!isRepBased) {
      return ex.copyWith(
        intensityProfile: intensity,
        weightCue: _waveCues[weekIdx],
        variant: ex.variant,
      );
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
      reps: '$reps',
      restSeconds: rest,
      intensityProfile: intensity,
      weightCue: _waveCues[weekIdx],
      variant: ex.variant,
    );
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
