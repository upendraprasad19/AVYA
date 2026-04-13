import '../exercise_repository.dart';
import 'cardio_finisher.dart';
import 'exercise_selector.dart';
import 'models.dart';
import 'periodization_engine.dart';
import 'progression_resolver.dart';
import 'sequencing_engine.dart';
import 'split_resolver.dart';
import 'superset_pairer.dart';
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

  final ExerciseRepository _exerciseRepo = ExerciseRepository.instance;

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
    final equipmentList = _getEquipmentList(equipment);
    final effectiveExp = effectiveLevel(experienceLevel, phase);

    // Resolve max exercises per day (session duration or defaults)
    final maxPerDay = ExerciseSelector.resolveMaxPerDay(
      daysPerWeek: daysPerWeek,
      effectiveExp: effectiveExp,
      sessionDuration: sessionDuration,
    );

    // Stage 1: Split structure
    final splitPlan = SplitResolver.select(
      goal, daysPerWeek,
      experienceLevel: effectiveExp,
    );

    // Stage 2: Exercise selection (with injury filter, body focus, non-negotiables)
    final populated = ExerciseSelector.pick(
      splitPlan: splitPlan,
      exerciseRepo: _exerciseRepo,
      equipmentList: equipmentList,
      effectiveExp: effectiveExp,
      phase: phase,
      maxPerDay: maxPerDay,
      goal: goal,
      injuries: injuries,
      bodyFocus: bodyFocus,
    );

    // Stage 0: Progression — resolve suggested weights for Phase 2+
    // Done after exercise selection so we know which exercise names to look up.
    final resolvedWeights = previousWeights ?? (phase >= 2
        ? ProgressionResolver.resolve(
            phase: phase,
            exerciseNames: populated
                .expand((d) => [...d.exercisesA, ...d.exercisesB])
                .map((e) => e.exerciseName)
                .toSet()
                .toList(),
          )
        : <String, double>{});

    // Stage 4: Periodization (V3 archetypes + volume wave + body focus + weights)
    var weeks = PeriodizationEngine.apply(
      populated: populated,
      phase: phase,
      is6Day: daysPerWeek == 6,
      effectiveExp: effectiveExp,
      bodyFocus: bodyFocus,
      previousWeights: resolvedWeights.isNotEmpty ? resolvedWeights : null,
    );

    // Stage 3: Sequencing (compound→isolation, bilateral→unilateral, CNS ordering)
    weeks = SequencingEngine.sequence(weeks);

    // Stage 5: Antagonist superset pairing
    weeks = SupersetPairer.pair(weeks);

    // Stage 6: Cardio finisher (fat_loss / general_fitness only)
    weeks = CardioFinisher.attach(
      weeks: weeks,
      goal: goal,
      cardioPreference: cardioPreference,
      equipmentList: equipmentList,
    );

    // Stage 7: Warmup + Cooldown
    weeks = WarmupCooldownSelector.attach(weeks, effectiveExp, equipmentList);

    // Build Phase output
    final meta = _getPhaseMeta(phase, goal);

    return Phase(
      phase: phase,
      name: meta.name,
      focus: meta.focus,
      weeks: '${(phase - 1) * 4 + 1}-${phase * 4}',
      dailyCalories: meta.dailyCalories,
      proteinGrams: meta.proteinGrams,
      workouts: weeks[0].workoutDays, // backward compat: week 1
      weekPlans: weeks,
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
