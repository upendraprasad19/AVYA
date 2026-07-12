import 'package:icanbefitter/core/constants/fitness_goals.dart';
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

    // Stage 2: Exercise selection with filtered slots
    final populated = ExerciseSelector.pickV4(
      slotDays: filteredDays,
      exerciseRepo: ExerciseRepository.instance,
      equipmentTier: equipment,
      effectiveExp: effectiveExp,
      phase: phase,
      goal: planGoal,
      injuries: normalizedInjuries,
      applyInjuryUniversalFilter: PlanEngineFlags.injuryUniversalFilterEnabled,
    );

    // Stage 0: Progression (Phase 2+ weight suggestions)
    final allNames = populated
        .expand((d) => [...d.exercisesA, ...d.exercisesB])
        .map((e) => e.exerciseName)
        .toSet()
        .toList();
    Map<String, double>? weights = previousWeights;
    if (weights == null && phase >= 2) {
      weights = ProgressionResolver.resolve(
        phase: phase,
        exerciseNames: allNames,
      );
    }

    // 2026-05-31 personalization lever L5 (weak-point → bodyFocus).
    // SAFE lever — does NOT touch the exercise-selection cascade. When the user
    // hasn't explicitly chosen a body focus and we're on Phase 2+, auto-populate
    // it from training history: the laggard muscle groups (lowest recent volume
    // share) become bodyFocus tokens, which PeriodizationEngine turns into +1 set
    // on matching exercises. No-ops to empty for Phase 1 / sparse history.
    var effectiveBodyFocus = bodyFocus;
    if (bodyFocus.isEmpty && phase >= 2) {
      effectiveBodyFocus = TrainingHistoryAnalyzer.weakMuscles();
    }

    // Stage 4: Periodization → WeekPlan[]
    var weekPlans = PeriodizationEngine.apply(
      populated: populated,
      phase: phase,
      is6Day: daysPerWeek == 6,
      effectiveExp: effectiveExp,
      bodyFocus: effectiveBodyFocus,
      previousWeights: weights,
    );

    // Stage 3: Sequencing
    weekPlans = SequencingEngine.sequence(weekPlans);

    // Stage 5: Superset pairing
    weekPlans = SupersetPairer.pair(weekPlans);

    // Stage 6: Cardio finisher — attach per the goal's FitnessGoals spec
    // (recompose now gets a light finisher; was excluded by the old hardcoded
    // lose_fat/general_fitness check).
    if (goalSpec.cardio) {
      weekPlans = CardioFinisher.attach(
        weeks: weekPlans,
        goal: goal,
        cardioPreference: cardioPreference,
        equipmentList: equipmentList,
      );
    }

    // Stage 7: Warmup/cooldown
    weekPlans = WarmupCooldownSelector.attach(
      weekPlans,
      effectiveExp,
      equipmentList,
      injuries: normalizedInjuries, // U3: injury-filter warmup/cooldown moves
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
