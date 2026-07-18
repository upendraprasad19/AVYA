import 'package:icanbefitter/core/constants/fitness_goals.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/core/utils/injury_vocab.dart';
import 'plan_engine_flags.dart';

import '../exercise_repository.dart';
import 'cardio_finisher.dart';
import 'exercise_selector.dart';
import 'models.dart';
import 'periodization_engine.dart';
import 'progression_resolver.dart';
import 'sequencing_engine.dart';
import 'split_resolver.dart';
import 'superset_pairer.dart';
import 'training_history_analyzer.dart';
import 'volume_filter.dart';
import 'volume_titration.dart';
import 'warmup_cooldown.dart';

/// Plan Generator V3 — Orchestrator.
///
/// Pipeline:
///   Stage 0 (Progression) → Stage 1 (Split) → Stage 2 (Exercise Select)
///   → Stage 3 (Sequencing) → Stage 4 (Periodization) → Stage 5 (Supersets)
///   → Stage 6 (Cardio Finisher) → Stage 7 (Warmup/Cooldown) → Phase Output
///
/// Zero API cost. Runs entirely on-device using Hive exercise library.
class PlanGenerator {
  PlanGenerator._();
  static final PlanGenerator _instance = PlanGenerator._();
  static PlanGenerator get instance => _instance;

  /// Generates a workout phase with 4 distinct weeks.
  ///
  /// V3 additions: injuries, bodyFocus, sessionDuration, cardioPreference,
  /// previousWeights (from ProgressionResolver).
  Phase generate({
    required String goal,
    required String equipment,
    required int daysPerWeek,
    int phase = 1,
    String experienceLevel = 'beginner',
    List<int>? preferredDays,
    // V3 parameters
    List<String> injuries = const [],
    List<String> bodyFocus = const [],
    int? sessionDuration,
    String? cardioPreference,
    Map<String, double>? previousWeights,
    List<String> equipmentExclusions = const [], // ⑥ B1 forward (facade omitted it)
    Map<int, ({List<String> a, List<String> b})>?
        pinnedExercisesByDay, // ⑧ 8-A/2-cap forward
    bool applyVolumeTitration = false, // W2.7 Batch 9 (opt-in; fresh advance only)
  }) {
    return generateV4(
      goal: goal,
      equipment: equipment,
      daysPerWeek: daysPerWeek,
      phase: phase,
      experienceLevel: experienceLevel,
      preferredDays: preferredDays,
      injuries: injuries,
      bodyFocus: bodyFocus,
      sessionDuration: sessionDuration,
      cardioPreference: cardioPreference,
      previousWeights: previousWeights,
      equipmentExclusions: equipmentExclusions,
      pinnedExercisesByDay: pinnedExercisesByDay,
      applyVolumeTitration: applyVolumeTitration,
    );
  }

  /// V4 pipeline: MuscleSlot-based exercise selection with cascading fallback.
  Phase generateV4({
    required String goal,
    required String equipment,
    required int daysPerWeek,
    int phase = 1,
    String experienceLevel = 'beginner',
    List<int>? preferredDays,
    List<String> injuries = const [],
    List<String> bodyFocus = const [],
    int? sessionDuration,
    String? cardioPreference,
    Map<String, double>? previousWeights,
    List<String> equipmentExclusions = const [], // ⑥ B1 (default → no-op)
    // ⑧ 8-A / UNIT 2-cap (W2.5 repeat-content): day-INDEX → prior-phase exercise
    // NAMES to PIN into the current split frames instead of running the cascade
    // (SHIP-DARK; null → the normal pickV4 cascade → byte-identical). Faithful
    // only when the prior phase's goal+daysPerWeek match the current profile —
    // the caller (UNIT 2-int) gates on that. Value = per-day (variant-A names for
    // weeks 1/3, variant-B names for weeks 2/4) — see buildPinnedDays.
    Map<int, ({List<String> a, List<String> b})>? pinnedExercisesByDay,
    // W2.7 (Batch 9 volume titration): opt-in intent — applied ONLY on a genuine
    // FRESH phase advance (the two advance callers pass `pins == null`). Default
    // false → every other caller (coach-regen / edit-profile / previews / hotel /
    // onboarding) is untouched regardless of `enable_volume_titration`.
    bool applyVolumeTitration = false,
  }) {
    final equipmentList = _getEquipmentList(equipment);
    final effectiveExp = effectiveLevel(experienceLevel, phase);

    // U4 (injury vocabulary — CENTRAL normalization). Every generation path
    // (the 2 scheduling callers + the coach regen/hotel planners + any direct
    // generateV4 caller) funnels through here, so normalizing ONCE at the engine
    // seam makes the injury filter canonical for all of them — instead of
    // sprinkling normalize() at each caller, which re-creates the fan-out-drop
    // bug this fixes (a legacy chip value `back` or muster free-text `lower back`
    // never matched the library token `lower_back`, so the filter silently
    // excluded ZERO exercises). InjuryVocab.normalize is a pure read-side alias
    // — no cloud migration, heals local/legacy/restored/free-text uniformly.
    final normalizedInjuries = InjuryVocab.normalize(injuries);

    // ⑥ slice B1 (mirror the injury seam above): derive the equipment-EXCLUSIONS
    // Set ONCE — flag-gated + normalized to canonical + floor-sanitized
    // (none/bodyweight can never be excluded, so the bodyweight floor always
    // survives). OFF or empty ⇒ `{}` ⇒ every downstream drop (queryV4 att1-4 /
    // att5 pool / L2 custom-append / L6 swap) is `.isNotEmpty`-inert ⇒
    // byte-identical to pre-B1. Threaded to pickV4 like normalizedInjuries.
    // ⑥ slice C1 — the central-read ACTIVATION: source the exclusions from the
    // user's `equipment_exclusions` profile field (Customize UI) via the flag-gated
    // plan-engine helper (mirrors resolveBodyFocus). The `equipmentExclusions`
    // param stays a test/direct-caller override; production callers pass nothing →
    // the profile read drives it. Flag OFF → `{}` (no Hive read) → byte-identical.
    final equipmentExclusionSet = TrainingHistoryAnalyzer.resolveEquipmentExclusions(
        equipmentExclusions,
        flagEnabled: PlanEngineFlags.equipmentExclusionsEnabled);

    // F19 / recompose: the plan engine (split + exercise selection) only knows
    // build_muscle / lose_fat / strength / general_fitness. Map the goal to its
    // plan archetype (FitnessGoals.planGoal) so a token like 'recompose'
    // (→ build_muscle) never falls through. Calorie/protein targets + cardio
    // attach still key off the ORIGINAL goal via FitnessGoals.
    final goalSpec = FitnessGoals.of(goal);
    final planGoal = goalSpec.planGoal;

    // Stage 1: Split resolution → MuscleSlotDay[]
    final splitDays = SplitResolver.selectV4(planGoal, daysPerWeek,
        experienceLevel: effectiveExp);

    // Stage 1.5: Volume Filter — trim slots by experience + frequency
    final filteredDays = VolumeFilter.filterDays(
      splitDays,
      experience: effectiveExp,
      weekCharacter: 'baseline', // first-pass uses baseline
    );

    // Stage 2: Exercise selection with filtered slots. ⑧ 8-A/2-cap: when a pinned
    // selection is supplied (repeat-content), slot those exercise NAMES into the
    // SAME frames instead of running the cascade — the tail (Stage 0 decay +
    // periodization) then runs UNCHANGED. null → verbatim pickV4 → byte-identical.
    final populated = pinnedExercisesByDay != null
        ? ExerciseSelector.buildPinnedDays(
            frames: filteredDays,
            pinnedByDay: pinnedExercisesByDay,
            exerciseRepo: ExerciseRepository.instance,
            equipmentTier: equipment,
            effectiveExp: effectiveExp,
            phase: phase,
            goal: planGoal,
            injuries: normalizedInjuries,
            applyInjuryUniversalFilter:
                PlanEngineFlags.injuryUniversalFilterEnabled,
            applyInjurySubstitutePreference:
                PlanEngineFlags.injurySubstitutePreferenceEnabled,
            exclusions: equipmentExclusionSet,
          )
        : ExerciseSelector.pickV4(
            slotDays: filteredDays,
            exerciseRepo: ExerciseRepository.instance,
            equipmentTier: equipment,
            effectiveExp: effectiveExp,
            phase: phase,
            goal: planGoal,
            injuries: normalizedInjuries,
            applyInjuryUniversalFilter:
                PlanEngineFlags.injuryUniversalFilterEnabled,
            applyInjurySubstitutePreference:
                PlanEngineFlags.injurySubstitutePreferenceEnabled,
            exclusions: equipmentExclusionSet,
          );

    // Stage 0: Progression (Phase 2+ weight suggestions)
    final allExercises = populated
        .expand((d) => [...d.exercisesA, ...d.exercisesB])
        .toList();
    final allNames = allExercises.map((e) => e.exerciseName).toSet().toList();
    // W2.1: per-exercise rep-range (from the library, carried on PlannedExercise)
    // for the graded rule's band gate.
    final repRanges = <String, String?>{
      for (final e in allExercises) e.exerciseName: e.repRange,
    };
    // W3.3 (Batch 11-A): per-exercise library id for the resolver's INCLUSIVE
    // id-OR-name history match (flag-gated inside resolve() → OFF = name-only).
    final exerciseIds = <String, String?>{
      for (final e in allExercises) e.exerciseName: e.exerciseId,
    };
    Map<String, double>? weights = previousWeights;
    if (weights == null && phase >= 2) {
      weights = ProgressionResolver.resolve(
        phase: phase,
        exerciseNames: allNames,
        repRanges: repRanges,
        exerciseIds: exerciseIds,
      );
    }

    // 2026-05-31 personalization lever L5 (weak-point → bodyFocus).
    // SAFE lever — does NOT touch the exercise-selection cascade. When the user
    // hasn't explicitly chosen a body focus and we're on Phase 2+, auto-populate
    // it from training history: the laggard muscle groups (lowest recent volume
    // share) become bodyFocus tokens, which PeriodizationEngine turns into +1 set
    // on matching exercises. No-ops to empty for Phase 1 / sparse history.
    // ⑤ (Batch 4): resolve the effective body-focus — explicit `physique_focus`
    // bring-up (ship-dark, precedes the auto weakMuscles() laggard signal). Flag
    // OFF → byte-identical to the prior `bodyFocus.isEmpty && phase >= 2 ?
    // weakMuscles() : bodyFocus`. The flag-gate + precedence glue lives in the
    // tested `TrainingHistoryAnalyzer.resolveBodyFocus` (B-pass P2).
    final effectiveBodyFocus = TrainingHistoryAnalyzer.resolveBodyFocus(
      explicitBodyFocus: bodyFocus,
      phase: phase,
    );

    // Stage 4: Periodization → WeekPlan[]
    var weekPlans = PeriodizationEngine.apply(
      populated: populated,
      phase: phase,
      is6Day: daysPerWeek == 6,
      effectiveExp: effectiveExp,
      bodyFocus: effectiveBodyFocus,
      previousWeights: weights,
      // ⑥ 7-B-1 (W2.4): stash peak-equivalent working sets/reps on the deload week
      // for a lossless triggered-deload lift (ship-dark; flag OFF → no stash →
      // byte-identical). Consumed by the 7-B-2 eval/un-deload.
      stashWorkingBase: PlanEngineFlags.triggeredDeloadEnabled,
    );

    // Stage 4.5: W2.7 volume titration (Batch 9) — phase-boundary per-major-group
    // ±1 set adjustment from phase-N evidence. Opt-in + ship-dark: only a genuine
    // fresh advance passes `applyVolumeTitration:true` (via `pins == null`);
    // resolveDeltas additionally returns {} unless `enable_volume_titration` is ON
    // AND phase>=2. Any of those false → applyToWeeks is identity → byte-identical.
    // Placed BEFORE sequencing/superset (neither reads `sets`) so it sees the
    // bodyFocus-adjusted counts and its result flows through unchanged.
    if (applyVolumeTitration) {
      weekPlans = VolumeTitration.applyToWeeks(
        weekPlans,
        VolumeTitration.resolveDeltas(phase: phase),
      );
    }

    // Stage 3: Sequencing
    weekPlans = SequencingEngine.sequence(weekPlans);

    // Stage 5: Superset pairing
    weekPlans = SupersetPairer.pair(weekPlans);

    // ⑥ C2 (WU-2 gym-cardio gate) — fix the always-false hasGymEquipment on the
    // GENERATED path (equipmentList is item tokens, not the tier string). When
    // exclusions are enabled, resolve the gym-cardio signal from the EFFECTIVE
    // (exclusion-subtracted) equipment: `cardio machine` (in the gym tiers as of
    // ⑥ C2) gates the gym-cardio pools (Treadmill/Bike). Flag OFF → null → attach
    // uses the old predicate → byte-identical (template_service + tier-string tests
    // pass the tier string, where the old predicate is TRUE, untouched).
    final bool? hasGymOverride;
    if (PlanEngineFlags.equipmentExclusionsEnabled) {
      final effectiveEquip = equipmentExclusionSet.isEmpty
          ? equipmentList
          : equipmentList
              .where((e) => !equipmentExclusionSet.contains(e))
              .toList();
      hasGymOverride = effectiveEquip.contains('cardio machine');
    } else {
      hasGymOverride = null;
    }

    // Stage 6: Cardio finisher — attach per the goal's FitnessGoals spec
    // (recompose now gets a light finisher; was excluded by the old hardcoded
    // lose_fat/general_fitness check).
    if (goalSpec.cardio) {
      weekPlans = CardioFinisher.attach(
        weeks: weekPlans,
        goal: goal,
        cardioPreference: cardioPreference,
        equipmentList: equipmentList,
        hasGymEquipmentOverride: hasGymOverride,
      );
    }

    // Stage 7: Warmup/cooldown
    weekPlans = WarmupCooldownSelector.attach(
      weekPlans,
      effectiveExp,
      equipmentList,
      injuries: normalizedInjuries, // U3: injury-filter warmup/cooldown moves
      hasGymEquipmentOverride: hasGymOverride, // ⑥ C2 (WU-2)
    );

    // Build Phase output
    final meta = _getPhaseMeta(phase, goal);
    final weekStart = (phase - 1) * 4 + 1;
    final weekEnd = weekStart + 3;

    return Phase(
      phase: phase,
      name: meta.name,
      focus: meta.focus,
      weeks: '$weekStart-$weekEnd',
      dailyCalories: meta.dailyCalories,
      proteinGrams: meta.proteinGrams,
      workouts: weekPlans.isNotEmpty ? weekPlans.first.workoutDays : [],
      weekPlans: weekPlans,
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

  // ── Equipment mapping ──────────────────────────────────────────

  // ⑥ slice C1 — delegates to the single-source `EquipmentVocab.tierItems` so the
  // tier→items map (also read by the Customize UI) can never drift from the
  // generator. Preserves the pre-C1 unknown-tier fallback `['none','bodyweight']`.
  List<String> _getEquipmentList(String equipment) =>
      EquipmentVocab.tierItems[equipment] ?? const ['none', 'bodyweight'];

  // ── Phase metadata ─────────────────────────────────────────────

  PhaseMeta _getPhaseMeta(int phase, String goal) {
    if (phase == 1) {
      return const PhaseMeta(
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
    // 2026-05-31 (post-12 deployment cycles): beyond the fixed 12-phase
    // curriculum, phases continue indefinitely as "Deployment N" (N = phase-12)
    // and recycle the advanced phase-9-12 focuses on rotation
    // (templateIndex = 9 + ((phase-9) % 4) → 9,10,11,12,9,...). Exercise
    // selection is phase-invariant; continued overload comes from periodization
    // load progression (see PeriodizationEngine.cycleMultiplier cap + the
    // autoregulated weight progression).
    final int recycledIndex = 9 + ((phase - 9) % 4);
    return PhaseMeta(
      name: phase < names.length ? names[phase] : 'Deployment ${phase - 12}',
      focus: phase < focuses.length ? focuses[phase] : focuses[recycledIndex],
      dailyCalories: 0,
      proteinGrams: 0,
    );
  }
}
