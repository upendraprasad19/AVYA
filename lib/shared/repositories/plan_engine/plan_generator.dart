import '../exercise_repository.dart';
import 'cardio_finisher.dart';
import 'exercise_selector.dart';
import 'models.dart';
import 'periodization_engine.dart';
import 'progression_resolver.dart';
import 'sequencing_engine.dart';
import 'split_resolver.dart';
import 'superset_pairer.dart';
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

    // Stage 1: Split resolution → MuscleSlotDay[]
    final splitDays = SplitResolver.selectV4(goal, daysPerWeek,
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
      goal: goal,
      injuries: injuries,
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

    // Stage 4: Periodization → WeekPlan[]
    var weekPlans = PeriodizationEngine.apply(
      populated: populated,
      phase: phase,
      is6Day: daysPerWeek == 6,
      effectiveExp: effectiveExp,
      bodyFocus: bodyFocus,
      previousWeights: weights,
    );

    // Stage 3: Sequencing
    weekPlans = SequencingEngine.sequence(weekPlans);

    // Stage 5: Superset pairing
    weekPlans = SupersetPairer.pair(weekPlans);

    // Stage 6: Cardio finisher
    if (goal == 'lose_fat' || goal == 'general_fitness') {
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
    return PhaseMeta(
      name: phase < names.length ? names[phase] : 'Phase $phase',
      focus: phase < focuses.length ? focuses[phase] : 'Advanced training',
      dailyCalories: 0,
      proteinGrams: 0,
    );
  }
}
