// Batch B1 Task 0 — the persona set for the generator golden
// (test/plan_generator/generator_golden_test.dart) and the core-list ON gate
// (Task 4). Every persona runs the REAL PlanGenerator.instance.generateV4 against
// whatever library the caller has put in the exercise box.
//
// Personas that need Hive state (owned equipment in the profile, a custom row
// for a pin) set it up inside `run` and clear it before returning, so every
// persona is independent of the order the caller runs them in.

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';

class GoldenPersona {
  final String group;
  final String key;
  final Phase Function() run;
  const GoldenPersona(this.group, this.key, this.run);
}

const goldenTiers = ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'];
const _goals = ['build_muscle', 'lose_fat', 'strength', 'general_fitness'];
const _levels = ['beginner', 'intermediate', 'advanced'];

Phase _gen({
  required String tier,
  String goal = 'build_muscle',
  int days = 4,
  String level = 'intermediate',
  int phase = 1,
  List<String> injuries = const [],
  List<String> exclusions = const [],
  Map<int, ({List<String> a, List<String> b})>? previousPhaseByDay,
  Map<int, ({List<String> a, List<String> b})>? pins,
}) =>
    PlanGenerator.instance.generateV4(
      goal: goal,
      equipment: tier,
      daysPerWeek: days,
      phase: phase,
      experienceLevel: level,
      injuries: injuries,
      equipmentExclusions: exclusions,
      previousWeights: const {},
      previousPhaseByDay: previousPhaseByDay,
      pinnedExercisesByDay: pins,
    );

/// Per-day variant-A (week 1) and variant-B (week 2) names of [p].
Map<int, ({List<String> a, List<String> b})> namesByDay(Phase p,
    {bool lower = false}) {
  final wkA = p.weekPlans[0].workoutDays;
  final wkB = p.weekPlans.length > 1 ? p.weekPlans[1].workoutDays : wkA;
  String f(String n) => lower ? n.toLowerCase() : n;
  return {
    for (var i = 0; i < wkA.length; i++)
      i: (
        a: [for (final e in wkA[i].exercises) f(e.exerciseName)],
        b: i < wkB.length
            ? [for (final e in wkB[i].exercises) f(e.exerciseName)]
            : const <String>[],
      ),
  };
}

Phase _withOwned(List<String> owned, Phase Function() body) {
  final box = HiveService.instance.userBox;
  box.put('profile', {'equipment_owned': owned});
  try {
    return body();
  } finally {
    box.delete('profile');
  }
}

const _customKey = 'custom_exercise_golden-band-row';
const customPinName = 'My Band Row';

Phase _withCustom(Phase Function() body) {
  final box = HiveService.instance.customBox;
  box.put(_customKey, {
    'type': 'exercise',
    'name': customPinName,
    'equipment_needed': <String>[],
    'primary_muscles': ['Lats'],
    'movement_pattern': ['horizontal_pull'],
    'logging_type': 'weight_reps',
  });
  try {
    return body();
  } finally {
    box.delete(_customKey);
  }
}

/// Owned-equipment personas: `'<tier>|<level>'` → the `equipment_owned` written
/// to the profile for the run (the core-list gate rebuilds capability from it).
const goldenOwnedEquipment = {
  'bodyweight|beginner': ['dumbbells', 'pull-up bar'],
  'home_dumbbells|intermediate': ['pull-up bar', 'bench'],
};

List<GoldenPersona> generatorGoldenPersonas() {
  final out = <GoldenPersona>[];
  for (final tier in goldenTiers) {
    for (final goal in _goals) {
      for (final days in [3, 4, 5, 6]) {
        for (final level in _levels) {
          for (var phase = 1; phase <= 5; phase++) {
            out.add(GoldenPersona(
              'grid:$tier',
              'grid|$tier|$goal|${days}d|$level|p$phase',
              () => _gen(
                  tier: tier,
                  goal: goal,
                  days: days,
                  level: level,
                  phase: phase),
            ));
          }
        }
      }
    }
  }
  for (final injury in ['knee', 'shoulder', 'lower_back']) {
    for (final tier in goldenTiers) {
      for (final phase in [1, 2]) {
        out.add(GoldenPersona(
          'extra',
          'injury|$injury|$tier|build_muscle|4d|intermediate|p$phase',
          () => _gen(tier: tier, phase: phase, injuries: [injury]),
        ));
      }
    }
  }
  for (final excl in ['barbell', 'pull-up bar']) {
    for (final tier in ['basic_gym', 'full_gym']) {
      out.add(GoldenPersona(
        'extra',
        'exclusion|$excl|$tier|build_muscle|4d|intermediate|p1',
        () => _gen(tier: tier, exclusions: [excl]),
      ));
    }
  }
  for (final tier in ['full_gym', 'home_dumbbells']) {
    for (final level in ['beginner', 'intermediate']) {
      out.add(GoldenPersona(
        'extra',
        'cross|$tier|build_muscle|4d|$level|p2',
        () => _gen(
          tier: tier,
          level: level,
          phase: 2,
          previousPhaseByDay: namesByDay(
              _gen(tier: tier, level: level, phase: 1),
              lower: true),
        ),
      ));
    }
  }
  for (final entry in goldenOwnedEquipment.entries) {
    final parts = entry.key.split('|');
    for (final phase in [1, 3]) {
      out.add(GoldenPersona(
        'extra',
        'owned|${parts[0]}|build_muscle|4d|${parts[1]}|p$phase',
        () => _withOwned(
          entry.value,
          () => _gen(tier: parts[0], level: parts[1], phase: phase),
        ),
      ));
    }
  }
  for (final p in const [
    ('full_gym', 'intermediate'),
    ('bodyweight', 'beginner'),
  ]) {
    out.add(GoldenPersona(
      'extra',
      'pins|${p.$1}|build_muscle|4d|${p.$2}|p2',
      () => _withCustom(() {
        final prior = namesByDay(_gen(tier: p.$1, level: p.$2, phase: 1));
        final day0 = prior[0]!;
        prior[0] = (a: [...day0.a, customPinName], b: day0.b);
        return _gen(tier: p.$1, level: p.$2, phase: 2, pins: prior);
      }),
    ));
  }
  return out;
}
