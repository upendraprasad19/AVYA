// OI-401 thin-day top-up, behavioural proof (docs/plans/2026-10-24-thin-day-topup.md).
//
// Two halves in one file:
//  * REAL library, the real PlanGenerator.generateV4 (the path users get): named
//    personas whose thin day is asserted FIRST with the kill-switch set (so a
//    persona that stops being thin fails loudly instead of passing vacuously),
//    then lifted with it unset; plus the tag oracle and the equipment oracle.
//  * SEEDED library, ExerciseSelector.topUpDays called directly on hand-built
//    days: every rule whose proof must not depend on how deep the real library
//    happens to be (own pattern before neighbour, neighbour before core, the
//    soft-avoid sets, aliasing, identity, the pinned exit, customs).
//
// The oracle reads tags and equipment from assets/data/exercise_library.json
// (as the sweep does) and from the built PlannedExercise, never from production
// _isContraindicated.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/core_list_selector.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/equipment_capability.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/exercise_selector.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';

import '../helpers/generator_golden_personas.dart' show namesByDay;
import '../plan_engine_v4/_helpers.dart' show exercise;

Map<String, dynamic> _row(
  String id,
  String name,
  String pattern,
  String muscle, {
  String type = 'isolation',
  List<String> tags = const [],
  bool foundational = true,
  List<String> needs = const ['bodyweight'],
}) =>
    {
      'id': id,
      'name': name,
      'movement_pattern': pattern,
      'exercise_type': type,
      'target_focus': muscle,
      'primary_muscles': [muscle.toLowerCase()],
      'equipment_tier': ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'],
      'equipment_needed': needs,
      'suitable_for': ['Beginner', 'Intermediate', 'Advanced'],
      'is_foundational': foundational,
      'default_sets': 3,
      'default_reps': '10',
      'rep_range': '8-12',
      'logging_type': 'reps',
      'injury_contraindications': tags,
    };

const _words = ['', 'One', 'Two', 'Three', 'Four', 'Five'];

/// `n` safe horizontal_push rows for Mid Chest: HP One, HP Two, and so on.
List<Map<String, dynamic>> _hp(int n, {List<String> tags = const []}) => [
      for (var i = 1; i <= n; i++)
        _row('hp$i', 'HP ${_words[i]}', 'horizontal_push', 'Mid Chest',
            type: 'compound', tags: tags),
    ];

/// Core rows: CO Easy and CO Three are foundational isolation moves; CO Hard is
/// a non-foundational compound, which queryV4 sorts FIRST when the query does not
/// ask for foundational rows only.
List<Map<String, dynamic>> _core() => [
      _row('co1', 'CO Easy', 'core', 'Core'),
      _row('co2', 'CO Hard', 'core', 'Core',
          type: 'compound', foundational: false),
      _row('co3', 'CO Three', 'core', 'Core'),
    ];

MuscleSlot _slot(String muscle, String pattern, {int priority = 1}) =>
    MuscleSlot(
      targetMuscle: muscle,
      movementPattern: pattern,
      exerciseType: 'compound',
      priority: priority,
    );

MuscleSlotDay _slotDay(List<MuscleSlot> a, [List<MuscleSlot>? b]) =>
    MuscleSlotDay(
      name: 'Test day',
      focus: 'Test day',
      dayType: 'push',
      intensity: 'hypertrophy',
      slotsA: a,
      slotsB: b,
    );

/// A hand-built day. `b == null` makes B the SAME list as A (an alias); an
/// explicit `b` is always a fresh, non-const list, because two const empty lists
/// are `identical` in Dart and would read as an alias.
PopulatedDay _dayOf(List<String> a, [List<String>? b]) {
  final la = <PlannedExercise>[for (final n in a) exercise(name: n)];
  return PopulatedDay(
    name: 'Test day',
    focus: 'Test day',
    dayType: 'push',
    intensity: 'hypertrophy',
    exercisesA: la,
    exercisesB:
        b == null ? la : <PlannedExercise>[for (final n in b) exercise(name: n)],
  );
}

List<String> _names(List<PlannedExercise> xs) =>
    [for (final x in xs) x.exerciseName];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  final realRows = <Map<String, dynamic>>[];
  final tagsByName = <String, Set<String>>{};
  final bwCapability = EquipmentVocab.effectiveItems('bodyweight', null, null);

  Future<void> seed(List<Map<String, dynamic>> rows) async {
    if (Hive.isBoxOpen(HiveService.exerciseBoxName)) {
      await Hive.box(HiveService.exerciseBoxName).close();
    }
    try {
      await Hive.deleteBoxFromDisk(HiveService.exerciseBoxName);
    } catch (_) {}
    final box = await Hive.openBox(HiveService.exerciseBoxName);
    for (final r in rows) {
      await box.put(r['id'], Map<String, dynamic>.from(r));
    }
  }

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('thin_day_topup_behav');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final lib = jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List;
    for (final r in lib.whereType<Map>()) {
      final m = Map<String, dynamic>.from(r);
      m['id'] = (m['id'] ?? m['name']).toString();
      realRows.add(m);
      final ic = m['injury_contraindications'];
      tagsByName[(m['name'] as String).toLowerCase()] = {
        if (ic is List) ...ic.map((t) => t.toString().toLowerCase()),
      };
    }
    await seed(realRows);
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDownAll(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    await HiveService.instance.configBox.clear();
    await HiveService.instance.workoutBox.clear();
    await HiveService.instance.customBox.clear();
  });

  Future<void> killSwitch({required bool on}) async {
    if (on) {
      await HiveService.instance.configBox.put('disable_thin_day_topup', true);
    } else {
      await HiveService.instance.configBox.delete('disable_thin_day_topup');
    }
  }

  List<PopulatedDay> topUp(
    List<PopulatedDay> days,
    List<MuscleSlotDay> slots, {
    List<String> injuries = const ['shoulder'],
    int phase = 1,
    String goal = 'build_muscle',
    String level = 'intermediate',
    bool subPref = false,
    Map<int, ({List<String> a, List<String> b})>? prev,
    Set<String> plateau = const {},
    Set<String> exclusions = const {},
  }) =>
      ExerciseSelector.topUpDays(
        days,
        slotDays: slots,
        exerciseRepo: ExerciseRepository.instance,
        equipmentTier: 'bodyweight',
        effectiveExp: level,
        phase: phase,
        goal: goal,
        injuries: injuries,
        applyInjurySubstitutePreference: subPref,
        exclusions: exclusions,
        capability: bwCapability,
        previousPhaseByDay: prev,
        plateauAvoidNames: plateau,
      );

  // ---------------------------------------------------------------------------
  // Real library
  // ---------------------------------------------------------------------------
  group('real library, real generateV4', () {
    setUpAll(() async => seed(realRows));

    Phase gen({
      String tier = 'bodyweight',
      String goal = 'build_muscle',
      required String level,
      required int days,
      int phase = 1,
      required List<String> injuries,
      List<String> exclusions = const [],
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
          pinnedExercisesByDay: pins,
        );

    WorkoutDay dayOf(Phase p, int week, String focus) =>
        p.weekPlans[week].workoutDays.firstWhere((d) => d.focus == focus);

    List<String> unsafe(Iterable<PlannedExercise> xs, List<String> injuries) => [
          for (final e in xs)
            if (tagsByName[e.exerciseName.toLowerCase()] == null ||
                injuries.any(tagsByName[e.exerciseName.toLowerCase()]!.contains))
              e.exerciseName,
        ];

    List<String> unperformable(Iterable<PlannedExercise> xs, Set<String> cap) => [
          for (final e in xs)
            if (!EquipmentCapability.canPerform(e.equipmentNeeded, cap))
              '${e.exerciseName} needs ${e.equipmentNeeded}',
        ];

    Iterable<PlannedExercise> mainOf(Phase p) =>
        p.weekPlans.take(2).expand((w) => w.workoutDays).expand((d) => d.exercises);

    test(
        'shoulder bodyweight advanced 4-day: no empty or thin day, no tagged pick, '
        'no unperformable pick', () async {
      await killSwitch(on: true);
      final before = gen(level: 'advanced', days: 4, injuries: ['shoulder']);
      expect(dayOf(before, 1, 'Chest, shoulders, triceps').exercises, isEmpty,
          reason: 'precondition: empty on main with the kill-switch set');
      await killSwitch(on: false);
      final after = gen(level: 'advanced', days: 4, injuries: ['shoulder']);
      for (final wk in after.weekPlans.take(2)) {
        for (final d in wk.workoutDays) {
          expect(d.exercises.length, greaterThanOrEqualTo(3),
              reason: '${d.focus} is under the floor');
        }
      }
      expect(unsafe(mainOf(after), ['shoulder']), isEmpty);
      expect(unperformable(mainOf(after), bwCapability), isEmpty);
    });

    test('knee+hip bodyweight intermediate 3-day: week-2 day is lifted and safe',
        () async {
      await killSwitch(on: true);
      final before = gen(
          level: 'intermediate', days: 3, injuries: ['knee', 'hip']);
      expect(dayOf(before, 1, 'Quads, hamstrings, glutes').exercises, isEmpty,
          reason: 'precondition: the B variant is empty on main');
      await killSwitch(on: false);
      final after = gen(
          level: 'intermediate', days: 3, injuries: ['knee', 'hip']);
      final lifted = dayOf(after, 1, 'Quads, hamstrings, glutes').exercises;
      expect(lifted.length, greaterThanOrEqualTo(3));
      expect(unsafe(lifted, ['knee', 'hip']), isEmpty);
      expect(unperformable(lifted, bwCapability), isEmpty);
      expect(_names(lifted), kKneeHipWeek2Added);
    });

    test('repeat: one surviving pin is lifted to 3, safe, with no duplicate name',
        () async {
      final first = gen(
          goal: 'lose_fat', level: 'beginner', days: 6, injuries: const []);
      final pins = namesByDay(first);
      await killSwitch(on: true);
      final before = gen(
          goal: 'lose_fat', level: 'beginner', days: 6, phase: 2,
          injuries: ['elbow'], pins: pins);
      expect(dayOf(before, 0, 'Upper pull + conditioning').exercises, hasLength(1),
          reason: 'precondition: one surviving pin on main');
      await killSwitch(on: false);
      final after = gen(
          goal: 'lose_fat', level: 'beginner', days: 6, phase: 2,
          injuries: ['elbow'], pins: pins);
      for (final wk in after.weekPlans.take(2)) {
        for (final d in wk.workoutDays) {
          final n = _names(d.exercises);
          expect(n.length, greaterThanOrEqualTo(3), reason: '${d.focus}: $n');
          expect(n.toSet().length, n.length, reason: 'duplicate in ${d.focus}: $n');
        }
      }
      expect(unsafe(mainOf(after), ['elbow']), isEmpty);
      expect(unperformable(mainOf(after), bwCapability), isEmpty);
    });

    test('kill-switch: set gives the thin length recorded from main, unset gives >= 3',
        () async {
      await killSwitch(on: true);
      final off = gen(level: 'advanced', days: 4, injuries: ['shoulder']);
      expect(dayOf(off, 1, 'Chest, shoulders, triceps').exercises, hasLength(0));
      await killSwitch(on: false);
      final on = gen(level: 'advanced', days: 4, injuries: ['shoulder']);
      expect(dayOf(on, 1, 'Chest, shoulders, triceps').exercises.length,
          greaterThanOrEqualTo(3));
    });

    test('uninjured plan equals the plan with the switch set (a guard: green on main)',
        () async {
      await killSwitch(on: true);
      final off = gen(level: 'intermediate', days: 4, injuries: const []);
      await killSwitch(on: false);
      final on = gen(level: 'intermediate', days: 4, injuries: const []);
      expect(jsonEncode(on.toMap()), jsonEncode(off.toMap()));
    });

    test('B1 ON: the core-list path adds safe, performable moves to a thin day',
        () async {
      await HiveService.instance.configBox.put('enable_core_list_pool', true);
      final trace = CoreListTrace();
      CoreListSelector.debugTrace = trace;
      try {
        await killSwitch(on: true);
        final before = gen(level: 'beginner', days: 5, injuries: ['shoulder']);
        expect(trace.delegations, greaterThan(0),
            reason: 'precondition: the ON path ran');
        expect(dayOf(before, 0, 'Chest focus').exercises.length, lessThan(3),
            reason: 'precondition: thin under B1 ON with the kill-switch set');
        await killSwitch(on: false);
        final after = gen(level: 'beginner', days: 5, injuries: ['shoulder']);
        final lifted = dayOf(after, 0, 'Chest focus').exercises;
        expect(lifted.length, greaterThanOrEqualTo(3));
        expect(unsafe(lifted, ['shoulder']), isEmpty);
        expect(unperformable(lifted, bwCapability), isEmpty);
      } finally {
        CoreListSelector.debugTrace = null;
      }
    });

    test('exclusions: a user who excludes towel and doorway gets no such move in the '
        'top-up', () async {
      // Generate with the kill-switch set (the cascade's own picks) and unset.
      Future<List<PlannedExercise>> added(List<String> excl) async {
        await killSwitch(on: true);
        final off = gen(
            level: 'intermediate', days: 5, injuries: ['wrist'], exclusions: excl);
        await killSwitch(on: false);
        final on = gen(
            level: 'intermediate', days: 5, injuries: ['wrist'], exclusions: excl);
        final out = <PlannedExercise>[];
        for (var w = 0; w < 2; w++) {
          for (var i = 0; i < on.weekPlans[w].workoutDays.length; i++) {
            final offNames =
                _names(off.weekPlans[w].workoutDays[i].exercises).toSet();
            out.addAll(on.weekPlans[w].workoutDays[i].exercises
                .where((e) => !offNames.contains(e.exerciseName)));
          }
        }
        return out;
      }

      bool needsExcluded(PlannedExercise e) => EquipmentVocab.fromProfile(
              e.equipmentNeeded)
          .any(const {'doorway', 'towel'}.contains);

      final free = await added(const []);
      expect(free.where(needsExcluded), isNotEmpty,
          reason: 'precondition: without exclusions the top-up adds a towel or '
              'doorway move, so a filter that ignores the exclusions would show');
      final excluded = await added(const ['doorway', 'towel']);
      expect(excluded, isNotEmpty, reason: 'non-vacuity: moves were still added');
      expect(excluded.where(needsExcluded).map((e) => e.exerciseName), isEmpty);
    });

    test('phase 1 prefers foundational: a beginner\'s core top-up is Plank, not '
        'Farmers Carry', () async {
      await killSwitch(on: true);
      final off = gen(
          tier: 'home_dumbbells', level: 'beginner', days: 5, injuries: ['shoulder']);
      expect(dayOf(off, 0, 'Chest focus').exercises.length, lessThan(3),
          reason: 'precondition: thin with the kill-switch set');
      await killSwitch(on: false);
      final on = gen(
          tier: 'home_dumbbells', level: 'beginner', days: 5, injuries: ['shoulder']);
      final offNames = _names(dayOf(off, 0, 'Chest focus').exercises).toSet();
      final addedNames = _names(dayOf(on, 0, 'Chest focus').exercises)
          .where((n) => !offNames.contains(n))
          .toList();
      expect(addedNames, ['Plank']);
    });

    test('a topped-up day reaches PeriodizationEngine: the week-1 day holds the '
        'added moves with sets and reps', () async {
      await killSwitch(on: true);
      final before = gen(level: 'beginner', days: 5, injuries: ['shoulder']);
      final thin = dayOf(before, 0, 'Chest focus');
      expect(thin.exercises.length, lessThan(3), reason: 'precondition');
      await killSwitch(on: false);
      final after = gen(level: 'beginner', days: 5, injuries: ['shoulder']);
      final lifted = dayOf(after, 0, 'Chest focus').exercises;
      expect(lifted.length, greaterThanOrEqualTo(3));
      final kept = _names(thin.exercises).toSet();
      expect(kept.difference(_names(lifted).toSet()), isEmpty,
          reason: 'the top-up must not drop a pick the cascade made');
      for (final e in lifted.where((e) => !kept.contains(e.exerciseName))) {
        expect(e.sets, greaterThan(0), reason: '${e.exerciseName} has no sets');
        expect(e.reps, isNotEmpty, reason: '${e.exerciseName} has no reps');
      }
    });

    test('equipment oracle: every ADDED move is performable with the real capability',
        () async {
      final cases = <({List<String> inj, String level, int days, List<String> excl})>[
        (inj: ['shoulder'], level: 'advanced', days: 4, excl: const []),
        (inj: ['shoulder', 'lower_back'], level: 'beginner', days: 5, excl: const []),
        (inj: ['wrist'], level: 'beginner', days: 5, excl: const []),
        (inj: ['wrist'], level: 'intermediate', days: 5, excl: ['doorway', 'towel']),
      ];
      var added = 0;
      for (final c in cases) {
        await killSwitch(on: true);
        final off = gen(level: c.level, days: c.days, injuries: c.inj,
            exclusions: c.excl);
        await killSwitch(on: false);
        final on = gen(level: c.level, days: c.days, injuries: c.inj,
            exclusions: c.excl);
        final cap = EquipmentVocab.effectiveItems('bodyweight', null, c.excl);
        for (var w = 0; w < 2; w++) {
          for (var i = 0; i < on.weekPlans[w].workoutDays.length; i++) {
            final offNames =
                _names(off.weekPlans[w].workoutDays[i].exercises).toSet();
            for (final e in on.weekPlans[w].workoutDays[i].exercises) {
              if (offNames.contains(e.exerciseName)) continue;
              added++;
              expect(EquipmentCapability.canPerform(e.equipmentNeeded, cap), isTrue,
                  reason: '${c.inj} added ${e.exerciseName} needing '
                      '${e.equipmentNeeded}');
            }
          }
        }
      }
      expect(added, greaterThan(0), reason: 'non-vacuity: some move was added');
    });
  });

  // ---------------------------------------------------------------------------
  // Seeded library, topUpDays called directly
  // ---------------------------------------------------------------------------
  group('seeded library, direct', () {
    test('uninjured: identical list', () async {
      await seed([..._hp(3), ..._core()]);
      final days = [_dayOf(['HP One'])];
      final out = topUp(days, [_slotDay([_slot('Mid Chest', 'horizontal_push')])],
          injuries: const []);
      expect(identical(out, days), isTrue);
    });

    test('injured, no thin day: the same instance comes back', () async {
      await seed([..._hp(4), ..._core()]);
      final days = [_dayOf(['HP One', 'HP Two', 'HP Three'])];
      final out = topUp(days, [_slotDay([_slot('Mid Chest', 'horizontal_push')])]);
      expect(identical(out, days), isTrue);
    });

    test('length mismatch returns the same instance, in both directions', () async {
      await seed([..._hp(3), ..._core()]);
      final sd = _slotDay([_slot('Mid Chest', 'horizontal_push')]);
      final one = [_dayOf(['HP One'])];
      expect(identical(topUp(one, [sd, sd]), one), isTrue);
      final two = [_dayOf(['HP One']), _dayOf(['HP Two'])];
      expect(identical(topUp(two, [sd]), two), isTrue);
    });

    test('kill-switch set returns the same instance; unset tops the day up',
        () async {
      await seed([..._hp(3), ..._core()]);
      final days = [_dayOf(['HP One'])];
      final sds = [_slotDay([_slot('Mid Chest', 'horizontal_push')])];
      await killSwitch(on: true);
      expect(identical(topUp(days, sds), days), isTrue);
      await killSwitch(on: false);
      expect(topUp(days, sds).single.exercisesA.length, greaterThanOrEqualTo(3));
    });

    test('alias: B is the topped-up A, same identity and same names', () async {
      await seed([..._hp(3), ..._core()]);
      final out = topUp([_dayOf(['HP One'])],
          [_slotDay([_slot('Mid Chest', 'horizontal_push')])]).single;
      expect(out.exercisesA.length, greaterThanOrEqualTo(3));
      expect(identical(out.exercisesB, out.exercisesA), isTrue);
      expect(_names(out.exercisesB), _names(out.exercisesA));
    });

    test('alias through pickV4 with slotsB null keeps the alias and lifts the day',
        () async {
      await seed([
        _row('hp1', 'HP One', 'horizontal_push', 'Mid Chest', type: 'compound'),
        _row('hp2', 'HP Two', 'horizontal_push', 'Mid Chest',
            type: 'compound', tags: ['shoulder']),
        _row('vp1', 'VP One', 'vertical_push', 'Mid Chest', type: 'compound'),
        _row('et1', 'ET One', 'elbow_extension', 'Mid Chest'),
        ..._core(),
      ]);
      final days = ExerciseSelector.pickV4(
        slotDays: [_slotDay([_slot('Mid Chest', 'horizontal_push')])],
        exerciseRepo: ExerciseRepository.instance,
        equipmentTier: 'bodyweight',
        effectiveExp: 'intermediate',
        phase: 1,
        goal: 'build_muscle',
        injuries: const ['shoulder'],
        capability: bwCapability,
      );
      expect(days.single.exercisesA.length, greaterThanOrEqualTo(3));
      expect(identical(days.single.exercisesB, days.single.exercisesA), isTrue);
    });

    test('never picks a tagged row, a row needing an excluded item, or a row the '
        'capability set forbids', () async {
      await seed([
        _row('hp1', 'HP Tagged', 'horizontal_push', 'Mid Chest',
            type: 'compound', tags: ['shoulder']),
        _row('hp2', 'HP Doorway', 'horizontal_push', 'Mid Chest',
            type: 'compound', needs: ['doorway']),
        // The over-tag class: the tier list says bodyweight, equipment_needed says
        // barbell. Only the capability filter catches it.
        _row('hp3', 'HP Barbell', 'horizontal_push', 'Mid Chest',
            type: 'compound', needs: ['barbell']),
        _row('hp4', 'HP Safe', 'horizontal_push', 'Mid Chest', type: 'compound'),
      ]);
      final out = topUp([_dayOf(['Seed A', 'Seed B'])],
          [_slotDay([_slot('Mid Chest', 'horizontal_push')])],
          exclusions: const {'doorway'}).single;
      expect(_names(out.exercisesA), ['Seed A', 'Seed B', 'HP Safe']);
    });

    test('own pattern first: a thin B gets a move from its OWN slot pattern, not '
        'from A\'s and not from a neighbour', () async {
      await seed([
        ..._hp(2),
        _row('vl1', 'VL One', 'vertical_pull', 'Lats', type: 'compound'),
        _row('vl2', 'VL Two', 'vertical_pull', 'Lats', type: 'compound'),
        _row('hl1', 'HL One', 'horizontal_pull', 'Lats', type: 'compound'),
        ..._core(),
      ]);
      final out = topUp(
        [_dayOf(['A1', 'A2', 'A3'], ['VL One'])],
        [
          _slotDay([_slot('Mid Chest', 'horizontal_push')],
              [_slot('Lats', 'vertical_pull')]),
        ],
      ).single;
      expect(_names(out.exercisesB).take(2).toList(), ['VL One', 'VL Two']);
      expect(out.exercisesA, hasLength(3), reason: 'A was at the floor');
    });

    test('pinned: a dropped pin\'s slot is refilled from its own pattern before '
        'any neighbour', () async {
      await seed([
        ..._hp(3),
        _row('hpx', 'HP Tagged', 'horizontal_push', 'Mid Chest',
            type: 'compound', tags: ['shoulder']),
        _row('et1', 'ET One', 'elbow_extension', 'Triceps'),
        _row('vp1', 'VP One', 'vertical_push', 'Mid Chest', type: 'compound'),
      ]);
      final frame = _slotDay([
        _slot('Mid Chest', 'horizontal_push'),
        _slot('Triceps', 'elbow_extension', priority: 2),
      ]);
      final pins = (a: ['HP One', 'ET One', 'HP Tagged'], b: ['HP One', 'ET One', 'HP Tagged']);
      final out = ExerciseSelector.buildPinnedDays(
        frames: [frame],
        pinnedByDay: {0: pins},
        exerciseRepo: ExerciseRepository.instance,
        equipmentTier: 'bodyweight',
        effectiveExp: 'intermediate',
        phase: 2,
        goal: 'build_muscle',
        injuries: const ['shoulder'],
        capability: bwCapability,
      ).single;
      expect(_names(out.exercisesA), containsAll(['HP One', 'ET One']));
      expect(_names(out.exercisesA), isNot(contains('HP Tagged')));
      expect(out.exercisesA, hasLength(3));
      expect(_names(out.exercisesA), isNot(contains('VP One')),
          reason: 'the own pattern (horizontal_push) must be tried before a '
              'neighbour (vertical_push)');
      expect(out.exercisesB.length, greaterThanOrEqualTo(3));
    });

    test('neighbour before core', () async {
      await seed([
        _row('hp1', 'HP One', 'horizontal_push', 'Mid Chest', type: 'compound'),
        _row('vp1', 'VP One', 'vertical_push', 'Mid Chest', type: 'compound'),
        ..._core(),
      ]);
      final out = topUp([_dayOf(['HP One'])],
          [_slotDay([_slot('Mid Chest', 'horizontal_push')])]).single;
      expect(_names(out.exercisesA), ['HP One', 'VP One', 'CO Easy']);
    });

    test('core when no neighbour is safe', () async {
      await seed([
        _row('hp1', 'HP One', 'horizontal_push', 'Mid Chest', type: 'compound'),
        _row('vp1', 'VP Tagged', 'vertical_push', 'Mid Chest',
            type: 'compound', tags: ['shoulder']),
        ..._core(),
      ]);
      final out = topUp([_dayOf(['HP One'])],
          [_slotDay([_slot('Mid Chest', 'horizontal_push')])]).single;
      expect(_names(out.exercisesA), ['HP One', 'CO Easy', 'CO Three']);
    });

    test('phase 1 prefers foundational: the core top-up is the foundational row, '
        'not the compound that sorts first; later phases take the compound',
        () async {
      await seed(_core());
      final sds = [_slotDay([_slot('Mid Chest', 'horizontal_push')])];
      final p1 = topUp([_dayOf(['X1', 'X2'])], sds, phase: 1).single;
      expect(_names(p1.exercisesA).last, 'CO Easy');
      final p3 = topUp([_dayOf(['X1', 'X2'])], sds, phase: 3).single;
      expect(_names(p3.exercisesA).last, 'CO Hard');
    });

    test('B differs from A where the library allows (flag false: a curated sub may '
        'repeat otherwise)', () async {
      await seed(_hp(4));
      final out = topUp(
        [_dayOf(['HP One', 'HP Two', 'HP Three'], ['B Seed'])],
        [_slotDay([_slot('Mid Chest', 'horizontal_push')])],
      ).single;
      expect(_names(out.exercisesB)[1], 'HP Four',
          reason: 'the first move added to B must avoid A\'s names (mixed case in '
              'the day, lower case in the avoid set)');
    });

    test('strength does not soft-avoid, in either direction', () async {
      await seed(_hp(4));
      final sds = [_slotDay([_slot('Mid Chest', 'horizontal_push')])];
      final b = topUp(
        [_dayOf(['HP One', 'HP Two', 'HP Three'], ['B Seed'])], sds,
        goal: 'strength',
      ).single;
      expect(_names(b.exercisesB)[1], 'HP One', reason: 'B does not avoid A');
      final a = topUp(
        [_dayOf(['A Seed'], ['HP One', 'HP Two', 'HP Three'])], sds,
        goal: 'strength',
      ).single;
      expect(_names(a.exercisesA)[1], 'HP One', reason: 'A does not avoid B');
    });

    test('A avoids B\'s names whenever the day is not an alias and the goal is not '
        'strength, also when both variants are thin', () async {
      await seed(_hp(4));
      final sds = [_slotDay([_slot('Mid Chest', 'horizontal_push')])];
      final a = topUp(
        [_dayOf(['A Seed'], ['HP One', 'HP Two', 'HP Three'])], sds,
      ).single;
      expect(_names(a.exercisesA)[1], 'HP Four');

      final both = topUp([_dayOf(['A Seed'], ['B Seed'])], sds).single;
      final addedA = _names(both.exercisesA).skip(1).toSet();
      final addedB = _names(both.exercisesB).skip(1).toSet();
      expect(addedA, isNotEmpty);
      expect(addedB, isNotEmpty);
      expect(addedA.intersection(addedB), isEmpty,
          reason: 'with both thin, A is topped up first and B avoids A\'s result');
    });

    group('phase 2 avoid sets (each: control, then the set)', () {
      final sds = [_slotDay([_slot('Mid Chest', 'horizontal_push')])];

      test('control: with no avoid set the first candidate is HP One', () async {
        await seed(_hp(3));
        final out = topUp([_dayOf(['Seed'])], sds, phase: 2).single;
        expect(_names(out.exercisesA)[1], 'HP One');
      });

      test('previous-phase names', () async {
        await seed(_hp(3));
        final out = topUp([_dayOf(['Seed'])], sds, phase: 2, prev: {
          0: (a: ['HP One'], b: const <String>[]),
        }).single;
        expect(_names(out.exercisesA)[1], 'HP Two');
      });

      test('plateau names', () async {
        await seed(_hp(3));
        final out = topUp([_dayOf(['Seed'])], sds,
            phase: 2, plateau: {'HP One'}).single;
        expect(_names(out.exercisesA)[1], 'HP Two');
      });

      test('demoted names (a swapped-away-from row in the workout box)', () async {
        await seed(_hp(3));
        final date = DateTime.now().toIso8601String().substring(0, 10);
        await HiveService.instance.workoutBox.put('schedule_$date', {
          'date': date,
          'exercises': [
            {'name': 'Replacement', 'swapped_from': 'HP One', 'swapped_via': 'swap'},
          ],
        });
        final out = topUp([_dayOf(['Seed'])], sds, phase: 2).single;
        expect(_names(out.exercisesA)[1], 'HP Two');
      });
    });

    test('idempotent: a second pass returns the first result\'s instance when '
        'nothing is thin, and equal names when a residual 2 remains', () async {
      await seed([..._hp(3), ..._core()]);
      final sds = [_slotDay([_slot('Mid Chest', 'horizontal_push')])];
      final first = topUp([_dayOf(['HP One'])], sds);
      expect(identical(topUp(first, sds), first), isTrue);

      await seed([_row('x1', 'Lone', 'knee_dominant', 'Quads')]);
      final stuck = topUp([_dayOf(['A', 'B'])], sds);
      final again = topUp(stuck, sds);
      expect(_names(again.single.exercisesA), _names(stuck.single.exercisesA));
      expect(_names(again.single.exercisesA), ['A', 'B']);
    });

    test('repeat: all pins dropped (the fresh() path) gives >= 3, no duplicate, '
        'and equals a direct single-frame pickV4 day', () async {
      await seed([
        _row('hpx', 'HP Tagged', 'horizontal_push', 'Mid Chest',
            type: 'compound', tags: ['shoulder']),
        _row('hp1', 'HP One', 'horizontal_push', 'Mid Chest', type: 'compound'),
        _row('et1', 'ET One', 'elbow_extension', 'Triceps'),
        _row('vp1', 'VP One', 'vertical_push', 'Mid Chest', type: 'compound'),
        ..._core(),
      ]);
      final frame = _slotDay([
        _slot('Mid Chest', 'horizontal_push'),
        _slot('Triceps', 'elbow_extension', priority: 2),
      ]);
      final pinned = ExerciseSelector.buildPinnedDays(
        frames: [frame],
        pinnedByDay: {0: (a: ['HP Tagged'], b: ['HP Tagged'])},
        exerciseRepo: ExerciseRepository.instance,
        equipmentTier: 'bodyweight',
        effectiveExp: 'intermediate',
        phase: 2,
        goal: 'build_muscle',
        injuries: const ['shoulder'],
        capability: bwCapability,
      ).single;
      final direct = ExerciseSelector.pickV4(
        slotDays: [frame],
        exerciseRepo: ExerciseRepository.instance,
        equipmentTier: 'bodyweight',
        effectiveExp: 'intermediate',
        phase: 2,
        goal: 'build_muscle',
        injuries: const ['shoulder'],
        capability: bwCapability,
      ).single;
      final n = _names(pinned.exercisesA);
      expect(n.length, greaterThanOrEqualTo(3));
      expect(n.toSet().length, n.length);
      expect(n, _names(direct.exercisesA));
    });

    test('a pinned custom is counted and none is added', () async {
      await seed([..._hp(3), ..._core()]);
      await HiveService.instance.customBox.put('custom_exercise_t1', {
        'type': 'exercise',
        'name': 'My Custom Move',
        'default_logging_type': 'weight_reps',
        'default_sets': 3,
        'default_reps': '10',
        'default_rest_secs': 60,
        'equipment_needed': <String>[],
        'primary_muscles': ['mid chest'],
      });
      await HiveService.instance.customBox.put('custom_exercise_t2', {
        'type': 'exercise',
        'name': 'Other Custom',
        'default_logging_type': 'weight_reps',
        'default_sets': 3,
        'default_reps': '10',
        'default_rest_secs': 60,
        'equipment_needed': <String>[],
        'primary_muscles': ['mid chest'],
      });
      final out = ExerciseSelector.buildPinnedDays(
        frames: [_slotDay([_slot('Mid Chest', 'horizontal_push')])],
        pinnedByDay: {
          0: (a: ['My Custom Move', 'HP One'], b: ['My Custom Move', 'HP One']),
        },
        exerciseRepo: ExerciseRepository.instance,
        equipmentTier: 'bodyweight',
        effectiveExp: 'intermediate',
        phase: 2,
        goal: 'build_muscle',
        injuries: const ['shoulder'],
        capability: bwCapability,
      ).single;
      final n = _names(out.exercisesA);
      expect(n.where((x) => x == 'My Custom Move'), hasLength(1));
      expect(n, isNot(contains('Other Custom')),
          reason: 'the generator never adds a custom (d4b8e1)');
      expect(n.length, greaterThanOrEqualTo(3));
    });
  });
}

/// The knee+hip week-2 day the final code produces (the B variant was empty on
/// main), in order. Recorded from the first run of the final code, 2026-10-24.
/// B's names are a subset of A's here (the safe pool is four rows), so "B differs
/// from A" is NOT asserted for this persona; the direct tests carry that.
const kKneeHipWeek2Added = <String>[
  'Bodyweight Good Morning',
  'Standing Single Leg Hinge',
  'Glute Bridge',
];
