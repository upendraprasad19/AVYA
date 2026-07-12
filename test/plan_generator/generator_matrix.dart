// ignore_for_file: avoid_print
//
// Batch 0 · D1 — Full-matrix generator sweep (pure-Dart, no Hive).
//
// Enumerates synthetic personas across the input space and generates each
// plan via the SAME pure-Dart cascade path the existing sample_plans_report
// uses (SplitResolver → VolumeFilter → CascadeTracer). Each cascade pick is
// enriched with its full library record so the Plan Quality Scorecard (D2)
// can score muscle coverage / equipment / injury-safety / volume without Hive.
//
// NOT a rewrite of the engine — a measurement harness OVER it. Touches zero
// lib/ files. Run: `dart run test/plan_generator/generator_matrix.dart`.

import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/volume_filter.dart';
import 'v4_diagnostic/library_loader.dart';
import 'v4_diagnostic/cascade_tracer.dart';

/// A synthetic user the generator produces a plan for.
class Persona {
  final String goal; // build_muscle | lose_fat | general_fitness | strength
  final String equipment; // bodyweight | home_dumbbells | basic_gym | full_gym
  final int days; // 3..6
  final String experience; // beginner | intermediate | advanced
  final int phase; // 1, 2, 6
  final List<String> injuries; // library tokens, e.g. ['lower_back']

  const Persona({
    required this.goal,
    required this.equipment,
    required this.days,
    required this.experience,
    required this.phase,
    this.injuries = const [],
  });

  String get injuryLabel => injuries.isEmpty ? 'none' : injuries.join('+');

  String get id =>
      '$goal | $equipment | ${days}d | $experience | p$phase | inj:$injuryLabel';
}

/// One selected exercise in a generated plan, enriched with its library record.
class PlanExercise {
  final String name;
  final String source; // CascadePickSource.name
  final Map<String, dynamic>? record; // null when a universal-pool placeholder
  final MuscleSlot slot;

  const PlanExercise({
    required this.name,
    required this.source,
    required this.record,
    required this.slot,
  });

  /// A "fallback" pick means the cascade could not find an on-target exercise
  /// (attempt3 drops target+type, universalPool is the last resort). These are
  /// the picks the plan-engine's own golden target is "0 of".
  bool get isFallback =>
      source == CascadePickSource.attempt3DropTypeAndTarget.name ||
      source == CascadePickSource.universalPool.name ||
      source == CascadePickSource.universalPoolPlaceholder.name;

  bool get isMissing =>
      name == '(none)' || source == CascadePickSource.universalPoolPlaceholder.name;

  /// U2: the slot was intentionally left empty because every universal-pool move
  /// for its pattern was contraindicated for the persona's injuries. This is a
  /// SAFE omission (fewer-but-safe), NOT a bug — so it is neither `isMissing`
  /// (a hard failure) nor `isFallback` (a target-fidelity miss). The scorecard
  /// excludes it from the realism denominator and the balance ratios; safety /
  /// coverage / volume already skip it (its library record is null).
  bool get isSafelyOmitted => source == CascadePickSource.safelyOmitted.name;
}

class PlanDay {
  final String name;
  final String focus;
  final List<PlanExercise> exercises;
  const PlanDay({required this.name, required this.focus, required this.exercises});
}

class GeneratedPlan {
  final Persona persona;
  final List<PlanDay> days;
  const GeneratedPlan({required this.persona, required this.days});

  Iterable<PlanExercise> get allExercises => days.expand((d) => d.exercises);
}

/// Pure-Dart mirror of `PlanGenerator.effectiveLevel` (plan_generator.dart:190).
/// Kept local so the harness stays Hive-free; if the production rule changes,
/// update here too (documented dependency).
String effectiveLevel(String experience, int phase) {
  if (experience == 'advanced') return 'advanced';
  if (experience == 'intermediate') return phase >= 4 ? 'advanced' : 'intermediate';
  if (phase >= 5) return 'advanced';
  if (phase >= 3) return 'intermediate';
  return 'beginner';
}

/// Pure-Dart mirror of `PlanGenerator._getEquipmentList` (plan_generator.dart:203).
/// Expands a tier to its item tokens — used by the scorecard's equipment check.
List<String> equipmentItemsForTier(String tier) {
  switch (tier) {
    case 'bodyweight':
      return const ['none', 'bodyweight'];
    case 'home_dumbbells':
      return const ['none', 'bodyweight', 'dumbbells', 'resistance band'];
    case 'basic_gym':
      return const [
        'none', 'bodyweight', 'dumbbells', 'barbell', 'bench',
        'pull-up bar', 'cables', 'resistance band',
      ];
    case 'full_gym':
      return const [
        'none', 'bodyweight', 'dumbbells', 'barbell', 'bench',
        'pull-up bar', 'cables', 'machines', 'smith machine',
        'resistance band', 'kettlebell', 'ez-bar',
      ];
    default:
      return const ['none', 'bodyweight'];
  }
}

/// Builds a case-insensitive name → library-record index for enrichment.
Map<String, Map<String, dynamic>> indexByName(List<Map<String, dynamic>> library) {
  final map = <String, Map<String, dynamic>>{};
  for (final e in library) {
    final n = (e['name'] as String?)?.toLowerCase();
    if (n != null) map[n] = e;
  }
  return map;
}

/// Generate one persona's plan via the pure-Dart selection path.
GeneratedPlan generatePlan(
  List<Map<String, dynamic>> library,
  Map<String, Map<String, dynamic>> byName,
  Persona persona,
) {
  final effExp = effectiveLevel(persona.experience, persona.phase);

  final splitDays = SplitResolver.selectV4(
    persona.goal,
    persona.days,
    experienceLevel: effExp,
  );
  final filteredDays = VolumeFilter.filterDays(
    splitDays,
    experience: effExp,
    weekCharacter: 'baseline',
  );

  final pickedNames = <String>{};
  final days = <PlanDay>[];

  for (final day in filteredDays) {
    final exercises = <PlanExercise>[];
    for (final slot in day.slotsA) {
      final trace = CascadeTracer.trace(
        library,
        slot: slot,
        equipmentTier: persona.equipment,
        effectiveExp: effExp,
        phase: persona.phase,
        injuries: persona.injuries,
        pickedNames: pickedNames,
      );
      final pick = trace.finalPick;
      final name = pick?.name ?? '(none)';
      final source = pick?.source.name ?? 'none';
      if (pick != null) pickedNames.add(pick.name);
      exercises.add(PlanExercise(
        name: name,
        source: source,
        record: byName[name.toLowerCase()],
        slot: slot,
      ));
    }
    days.add(PlanDay(name: day.name, focus: day.focus, exercises: exercises));
  }

  return GeneratedPlan(persona: persona, days: days);
}

/// The persona matrix. Two sub-sweeps keep coverage thorough without a 4608-cell
/// blow-up: a core grid (all goal×equip×days×exp×phase, no injuries) that
/// exercises coverage/balance/volume/progression, and an injury sub-sweep that
/// exercises the safety dimension across every library injury token.
///
/// Deferred (NOT silently dropped — the owning feature does not exist yet):
///  - equipment-EXCLUSION personas → Batch 5 (⑥ exclusions).
///  - body-focus / cardio-preference personas → Batches 4 / 1.
List<Persona> personaMatrix() {
  const goals = ['build_muscle', 'lose_fat', 'general_fitness', 'strength'];
  const equipment = ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'];
  const days = [3, 4, 5, 6];
  const experiences = ['beginner', 'intermediate', 'advanced'];
  const phases = [1, 2, 6];
  // Library injury tokens (verified present in exercise_library.json):
  const injuryTokens = ['lower_back', 'knee', 'shoulder', 'wrist', 'hip', 'ankle'];

  final personas = <Persona>[];

  // Core grid — no injuries.
  for (final g in goals) {
    for (final eq in equipment) {
      for (final d in days) {
        for (final exp in experiences) {
          for (final ph in phases) {
            personas.add(Persona(
              goal: g, equipment: eq, days: d, experience: exp, phase: ph,
            ));
          }
        }
      }
    }
  }

  // Injury sub-sweep — full_gym (widest pool, so any exclusion that empties a
  // slot is a real coverage problem, not just equipment scarcity), 4-day,
  // all experiences, each single injury + one combo, phase 1 (foundational
  // pool is the shallowest → hardest injury case).
  for (final exp in experiences) {
    for (final tok in injuryTokens) {
      personas.add(Persona(
        goal: 'build_muscle', equipment: 'full_gym', days: 4,
        experience: exp, phase: 1, injuries: [tok],
      ));
    }
    personas.add(Persona(
      goal: 'build_muscle', equipment: 'full_gym', days: 4,
      experience: exp, phase: 1, injuries: const ['shoulder', 'knee'],
    ));
  }

  return personas;
}

/// Generate every persona's plan. Shared by the report runner + the gate test.
List<GeneratedPlan> generateAll() {
  final library = LibraryLoader.loadFromAssets();
  final byName = indexByName(library);
  return personaMatrix()
      .map((p) => generatePlan(library, byName, p))
      .toList(growable: false);
}

void main() {
  final plans = generateAll();
  var totalExercises = 0;
  var fallbacks = 0;
  var missing = 0;
  for (final plan in plans) {
    for (final ex in plan.allExercises) {
      totalExercises++;
      if (ex.isFallback) fallbacks++;
      if (ex.isMissing) missing++;
    }
  }
  print('Generated ${plans.length} personas, $totalExercises exercises total.');
  print('Fallback picks (attempt3/universalPool): $fallbacks');
  print('Missing/(none) picks: $missing');
  if (fallbacks > 0 || missing > 0) {
    print('\nPersonas with fallback/missing picks:');
    for (final plan in plans) {
      final bad = plan.allExercises.where((e) => e.isFallback || e.isMissing).toList();
      if (bad.isNotEmpty) {
        print('  ${plan.persona.id}: ${bad.map((e) => "${e.name}[${e.source}]").join(", ")}');
      }
    }
  }
}
