@Timeout(Duration(minutes: 5))
library;

// Unit 2D (OI-453, plan docs/plans/2026-11-15-generator-step2d-repeat-minutes.md S4): the accessory candidates a
// repeat at more minutes carries beside each day. A candidate is a row of the frame's fresh pick that the allocator
// budgets (a library row, not a custom, not timed / cardio / distance) and is an isolation, whose name and same-movement
// partners no pinned row of the variant, no row of the day and no earlier candidate holds, and whose
// (movement pattern, first primary muscle) no row of the day holds. After the thin-day top-up, a candidate held by any
// row of its variant on any day is dropped. With the flag off nothing changes and the fields stay empty.
//
// Real library (the sweep harness loads it into Hive).

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/exercise_selector.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/same_movement.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';

import '../helpers/generator_golden_personas.dart' show namesByDay;
import '../helpers/injury_floor_sweep_lib.dart';

PlannedExercise lib(String name, {String? customOrigin}) {
  final r = ExerciseRepository.instance.getByExactName(name)!;
  final t = r['exercise_type'];
  return PlannedExercise(
    exerciseId: '${r['id']}',
    exerciseName: name,
    loggingType: '${r['logging_type'] ?? 'weight_reps'}',
    sets: 3,
    reps: '10',
    restSeconds: 60,
    exerciseType: t is List && t.isNotEmpty ? '${t.first}' : '$t',
    primaryMuscles: [for (final m in (r['primary_muscles'] as List)) '$m'],
    customOrigin: customOrigin,
  );
}

List<String> names(List<PlannedExercise> xs) => [for (final e in xs) e.exerciseName];

void main() {
  final h = SweepHarness.install();

  group('repeatCandidatesFor', () {
    late SameMovement sm;
    setUp(() => sm = SameMovement.fromRows(ExerciseRepository.instance.getAll()));
    List<PlannedExercise> call(List<PlannedExercise> pick, List<PlannedExercise> day,
            {Set<String> pinned = const {}, Set<String>? taken}) =>
        ExerciseSelector.repeatCandidatesFor(
            pick, day, pinned, taken ?? <String>{}, sm, ExerciseRepository.instance);

    test('only budgeted library isolations; no pinned name; no (pattern, first muscle) the day holds', () {
      final out = call(
        [
          lib('Barbell Bench Press'), // compound
          lib('Skull Crusher'), // (elbow_extension, Triceps), held by the day's pushdown
          lib('Lateral Raise'), // pinned on another day
          lib('Plank'), // timed
          lib('Dumbbell Curl', customOrigin: 'user'), // a custom
          lib('Dumbbell Curl'),
        ],
        [lib('Tricep Pushdown (Cable)')],
        pinned: {'lateral raise'},
      );
      expect(names(out), ['Dumbbell Curl']);
    });

    test('a same-movement partner of a row of the day is refused (the patterns differ)', () {
      expect(call([lib('Dumbbell Glute Bridge')], [lib('Glute Bridge')]), isEmpty);
      expect(names(call([lib('Dumbbell Glute Bridge')], [lib('Tricep Pushdown (Cable)')])), ['Dumbbell Glute Bridge'],
          reason: 'without the partner on the day it qualifies');
    });

    test('an earlier candidate of the variant (taken) and its partner are refused; the call extends taken', () {
      final taken = <String>{};
      expect(names(call([lib('Dumbbell Glute Bridge')], const [], taken: taken)), ['Dumbbell Glute Bridge']);
      expect(taken, containsAll(['dumbbell glute bridge', 'glute bridge']));
      expect(call([lib('Dumbbell Glute Bridge'), lib('Glute Bridge')], const [], taken: taken), isEmpty);
    });

    test('a timed isolation and a custom named like a library row are refused', () {
      expect(call([lib('Wall Sit')], const []), isEmpty, reason: 'timed: the allocator does not budget it');
      expect(call([lib('Dumbbell Curl', customOrigin: 'user')], const []), isEmpty,
          reason: 'a custom keeps its own sets; it is never an appended accessory');
    });

    test('the final screen drops a candidate held by a row of its variant on another day (and a partner)', () {
      PopulatedDay d(List<PlannedExercise> a, List<PlannedExercise> b, List<PlannedExercise> ca,
              List<PlannedExercise> cb) =>
          PopulatedDay(
              name: 'D',
              focus: 'F',
              dayType: 'push',
              intensity: 'hypertrophy',
              exercisesA: a,
              exercisesB: b,
              repeatAccessoriesA: ca,
              repeatAccessoriesB: cb);
      final days = [
        d([lib('Barbell Bench Press')], [lib('Barbell Bench Press')],
            [lib('Dumbbell Curl'), lib('Dumbbell Glute Bridge'), lib('Lateral Raise')], [lib('Dumbbell Curl')]),
        d([lib('Dumbbell Curl'), lib('Glute Bridge')], [lib('Skull Crusher')], const [], const []),
      ];
      final out = ExerciseSelector.dropHeldCandidatesForTest(days, sm);
      expect(names(out[0].repeatAccessoriesA), ['Lateral Raise'],
          reason: 'Dumbbell Curl is a day-1 A row; Dumbbell Glute Bridge partners Glute Bridge');
      expect(names(out[0].repeatAccessoriesB), ['Dumbbell Curl'], reason: 'B holds no curl');
      final clean = [days[0]];
      expect(identical(ExerciseSelector.dropHeldCandidatesForTest(clean, sm), clean), isTrue);
    });

    test('a candidate is not repeated within one day', () {
      expect(names(call([lib('Dumbbell Curl'), lib('Dumbbell Curl')], const [])), ['Dumbbell Curl']);
    });
  });

  group('buildPinnedDays', () {
    const goal = 'general_fitness', tier = 'full_gym', level = 'intermediate';

    List<PopulatedDay> build(int days, {required bool on, List<String> injuries = const []}) {
      final p1 = h.gen(tier: tier, goal: goal, level: level, days: days, phase: 1, injuries: const [], minutes: 30);
      return ExerciseSelector.buildPinnedDays(
        frames: SplitResolver.selectV4(goal, days, experienceLevel: level, sessionMinutes: 60),
        pinnedByDay: namesByDay(p1),
        exerciseRepo: ExerciseRepository.instance,
        equipmentTier: tier,
        effectiveExp: level,
        phase: 2,
        goal: goal,
        injuries: injuries,
        capability: null,
        appendAccessories: on,
      );
    }

    test('flag off: the candidate fields are empty; on: the days are the same and candidates appear', () {
      for (final days in [3, 4]) {
        final off = build(days, on: false);
        final on = build(days, on: true);
        expect(off.every((d) => d.repeatAccessoriesA.isEmpty && d.repeatAccessoriesB.isEmpty), isTrue);
        expect([for (final d in on) names(d.exercisesA)], [for (final d in off) names(d.exercisesA)]);
        expect([for (final d in on) names(d.exercisesB)], [for (final d in off) names(d.exercisesB)]);
        expect(on.any((d) => d.repeatAccessoriesA.isNotEmpty), isTrue, reason: '$days days');
        // No candidate is a row of its variant on any day.
        final rowsA = {for (final d in on) ...names(d.exercisesA)};
        final rowsB = {for (final d in on) ...names(d.exercisesB)};
        for (final d in on) {
          expect(names(d.repeatAccessoriesA).where(rowsA.contains), isEmpty);
          expect(names(d.repeatAccessoriesB).where(rowsB.contains), isEmpty);
          expect(d.repeatAccessoriesA.every((e) => e.exerciseType == 'isolation'), isTrue);
        }
      }
    });

    test('a candidate is never a fresh-filled row of another day (the final screen, at its call site)', () {
      // Pins on day 0 only: days 1-2 fresh-fill, and their fresh rows include day 0's candidates (measured: Russian
      // Twist on build_muscle beginner 3-day plans) unless the screen after the top-up drops them.
      for (final tier in ['bodyweight', 'full_gym']) {
        final p1 = h.gen(
            tier: tier, goal: 'build_muscle', level: 'beginner', days: 3, phase: 1, injuries: const [], minutes: 30);
        final exp = 'beginner';
        final out = ExerciseSelector.buildPinnedDays(
          frames: SplitResolver.selectV4('build_muscle', 3, experienceLevel: exp, sessionMinutes: 45),
          pinnedByDay: {0: namesByDay(p1)[0]!},
          exerciseRepo: ExerciseRepository.instance,
          equipmentTier: tier,
          effectiveExp: exp,
          phase: 2,
          goal: 'build_muscle',
          capability: null,
          appendAccessories: true,
        );
        final rowsA = {for (final d in out) for (final e in d.exercisesA) e.exerciseName.toLowerCase()};
        final rowsB = {for (final d in out) for (final e in d.exercisesB) e.exerciseName.toLowerCase()};
        for (final d in out) {
          expect([for (final c in d.repeatAccessoriesA) c.exerciseName.toLowerCase()].where(rowsA.contains), isEmpty,
              reason: tier);
          expect([for (final c in d.repeatAccessoriesB) c.exerciseName.toLowerCase()].where(rowsB.contains), isEmpty,
              reason: tier);
        }
      }
    });

    test('topUpDays carries the candidates on a day it rebuilds, and keeps the A/B alias', () {
      final c = [lib('Dumbbell Curl')];
      final thin = PopulatedDay(
        name: 'D',
        focus: 'F',
        dayType: 'push',
        intensity: 'hypertrophy',
        exercisesA: [lib('Barbell Bench Press')],
        exercisesB: [lib('Barbell Bench Press')],
        repeatAccessoriesA: c,
        repeatAccessoriesB: c,
      );
      final frames = SplitResolver.selectV4('general_fitness', 3, experienceLevel: level, sessionMinutes: 60);
      final out = ExerciseSelector.topUpDays(
        [thin],
        slotDays: [frames.first],
        exerciseRepo: ExerciseRepository.instance,
        equipmentTier: tier,
        effectiveExp: level,
        phase: 2,
        goal: goal,
        injuries: const ['knee'],
        applyInjurySubstitutePreference: false,
        exclusions: const {},
        capability: null,
      );
      expect(identical(out.first, thin), isFalse, reason: 'the day was rebuilt (the fixture must be thin)');
      expect(identical(out.first.repeatAccessoriesA, c), isTrue);
      expect(identical(out.first.repeatAccessoriesB, c), isTrue);
    });
  });
}
