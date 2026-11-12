// Batch B1 Task 3 — the core-list pool (the only picker since Unit 1B-F deleted the
// `enable_core_list_pool` flag and the cascade it gated).
//
// Drives the REAL ExerciseSelector.pickV4 / PlanGenerator.generateV4 over the
// shipped library (or crafted rows). Provenance comes from
// CoreListSelector.debugTrace, which production writes and only tests read —
// not a reimplementation, so no new mirror (plan Ruling 9).
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/core_list_selector.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/exercise_selector.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/training_history_analyzer.dart';

import '../helpers/generator_golden_personas.dart';

const _rank = {'beginner': 0, 'intermediate': 1, 'advanced': 2};
// E101 left in Batch C2a and E179 in Batch C2b; G0474 Toes to Bar is the E179 twin and a calisthenics_skill row, so it takes its place
// (B-pass C2b finding 4: a stale id here silently stops covering the skill row that replaced it).
const _skillIds = {
  'E069', 'E070', 'E071', 'E072', 'E073', 'E074', 'E086', 'E180', 'G0474',
};
const _improvisedShoulder = {'E272', 'E273', 'E274', 'E276', 'E277', 'E289', 'E290'};

List<String> _strs(Object? v) =>
    v is List ? [for (final e in v) e.toString()] : const <String>[];

String _cap(String level) => level[0].toUpperCase() + level.substring(1);

Map<String, dynamic> _row(
  String id,
  String name, {
  String pattern = 'hip_dominant',
  List<String> focus = const ['Glutes'],
  List<String>? levels = const ['intermediate'],
  String? family = 'fam',
  List<String> needed = const ['bodyweight'],
  List<String> type = const ['compound'],
  int priority = 1,
  String discipline = 'strength',
  List<String> suitable = const ['Beginner', 'Intermediate', 'Advanced'],
}) =>
    {
      'id': id,
      'name': name,
      'movement_pattern': [pattern],
      'target_focus': focus,
      'primary_muscles': focus,
      'equipment_needed': needed,
      'equipment_tier': ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'],
      'exercise_type': type,
      'suitable_for': suitable,
      'is_foundational': true,
      'priority_tier': priority,
      'injury_contraindications': <String>[],
      'logging_type': 'bodyweight_reps',
      'default_sets': 3,
      'default_reps': '10',
      'default_rest_secs': 60,
      'rep_range': '8-12',
      'is_active': true,
      'core_levels': ?levels,
      'discipline': discipline,
      'variant_family': ?family,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  late List<Map<String, dynamic>> shipped;
  late Map<String, Map<String, dynamic>> byId;
  late CoreListTrace trace;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('core_list_pool');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    await Hive.openBox(HiveService.exerciseBoxName);
    shipped = (jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
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

  Future<void> seed(List<Map<String, dynamic>> rows) async {
    final box = Hive.box(HiveService.exerciseBoxName);
    await box.clear();
    for (final r in rows) {
      await box.put(r['id'] as String, r);
    }
    byId = {for (final r in rows) r['id'] as String: r};
  }

  setUp(() async {
    await seed(shipped);
    trace = CoreListTrace();
    CoreListSelector.debugTrace = trace;
  });

  tearDown(() async {
    CoreListSelector.debugTrace = null;
    final config = HiveService.instance.configBox;
    await config.delete('disable_equipment_capability_floor');
    await HiveService.instance.userBox.delete('profile');
    final workout = HiveService.instance.workoutBox;
    for (final k in workout.keys.toList()) {
      if (k.toString().startsWith('schedule_')) await workout.delete(k);
    }
  });

  Phase gen({
    String tier = 'full_gym',
    String goal = 'build_muscle',
    int days = 4,
    String level = 'intermediate',
    int phase = 1,
    List<String> injuries = const [],
    List<String> exclusions = const [],
    Map<int, ({List<String> a, List<String> b})>? prev,
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
        previousPhaseByDay: prev,
      );

  MuscleSlot slot(String muscle, String pattern,
          {String type = 'compound', String? sub}) =>
      MuscleSlot(
        targetMuscle: muscle,
        subFocus: sub,
        movementPattern: pattern,
        exerciseType: type,
        priority: 1,
      );

  MuscleSlotDay day(List<MuscleSlot> a, [List<MuscleSlot>? b]) => MuscleSlotDay(
        name: 'Test Day',
        focus: 'full_body',
        dayType: 'full_body',
        intensity: 'hypertrophy',
        slotsA: a,
        slotsB: b,
      );

  List<PopulatedDay> pick(
    List<MuscleSlotDay> days, {
    String tier = 'full_gym',
    String level = 'intermediate',
    int phase = 1,
    String goal = 'build_muscle',
    List<String> injuries = const [],
    bool subPref = false,
    Set<String> plateau = const {},
    Map<int, ({List<String> a, List<String> b})>? prev,
  }) =>
      ExerciseSelector.pickV4(
        slotDays: days,
        exerciseRepo: ExerciseRepository.instance,
        equipmentTier: tier,
        effectiveExp: level,
        phase: phase,
        goal: goal,
        injuries: injuries,
        applyInjurySubstitutePreference: subPref,
        exclusions: const {},
        capability: TrainingHistoryAnalyzer.resolveCapability(
            tier: tier, exclusions: const {}, flagEnabled: true),
        previousPhaseByDay: prev,
        plateauAvoidNames: plateau,
      );

  List<String> names(List<PlannedExercise> xs) =>
      [for (final x in xs) x.exerciseName];

  Iterable<CoreListTraceSlot> picks() =>
      trace.slots.where((s) => s.pickedId != null);

  Future<void> demote(String name) async {
    final date = DateTime.now().toIso8601String().substring(0, 10);
    await HiveService.instance.workoutBox.put('schedule_$date', {
      'date': date,
      'exercises': [
        {'name': 'Replacement', 'swapped_from': name, 'swapped_via': 'swap'}
      ],
    });
  }

  ({List<Map<String, dynamic>> ordered, String source, bool improvisedRemoved,
      int nonImprovisedInPool, Set<String> families, bool jumpRemoved,
      bool jumpOnlyPool, bool likeForLikeImplement}) pool(
    List<Map<String, dynamic>> rows,
    MuscleSlot s, {
    String level = 'intermediate',
    Set<String>? capability,
    bool anyCoreLevel = false,
  }) =>
      CoreListSelector.rankedPool(
        rows: rows,
        slot: s,
        level: level,
        phase: 1,
        equipmentTier: 'bodyweight',
        capability: capability ??
            TrainingHistoryAnalyzer.resolveCapability(
                tier: 'bodyweight', exclusions: const {}, flagEnabled: true),
        exclusions: const {},
        isContraindicated: (_) => false,
        pickedNames: const {},
        demotedNames: const {},
        anyCoreLevel: anyCoreLevel,
      );

  // Unit 1B-F (Ruling 7): replaces "OFF is the golden". The core-list gate holds the same zero over the 998 golden
  // personas; this is the fast local copy on four of them.
  test('no empty day', () async {
    const keys = [
      'grid|bodyweight|build_muscle|4d|beginner|p1',
      'grid|home_dumbbells|lose_fat|3d|intermediate|p2',
      'grid|basic_gym|strength|5d|advanced|p3',
      'grid|full_gym|general_fitness|6d|intermediate|p5',
    ];
    final personas = {for (final p in generatorGoldenPersonas()) p.key: p};
    for (final k in keys) {
      final p = personas[k]!.run();
      for (final w in p.weekPlans) {
        for (final d in w.workoutDays) {
          expect(d.exercises, isNotEmpty, reason: '$k week ${w.weekNumber} ${d.name}');
        }
      }
    }
    expect(picks(), isNotEmpty);
  });

  test('every ON pick is core for the effective level, or a fill core at no '
      'level at or below it', () {
    for (final tier in goldenTiers) {
      for (final level in ['beginner', 'intermediate', 'advanced']) {
        for (final phase in [1, 5]) {
          trace.slots.clear();
          gen(tier: tier, level: level, phase: phase);
          expect(trace.slots, isNotEmpty, reason: '$tier $level p$phase');
          for (final s in picks()) {
            final r = byId[s.pickedId]!;
            final levels = _strs(r['core_levels']);
            final where = '$tier $level p$phase ${s.pickedId} ${s.source}';
            expect(s.level, PlanGenerator.effectiveLevel(level, phase));
            expect(_skillIds, isNot(contains(s.pickedId)), reason: where);
            if (s.source == 'core') {
              expect(levels, contains(s.level), reason: where);
            } else if (s.source == 'fill') {
              expect(levels.any((l) => _rank[l]! <= _rank[s.level]!), isFalse,
                  reason: where);
              expect(s.families, contains(r['variant_family']), reason: where);
              expect(_strs(r['suitable_for']), contains(_cap(s.level)),
                  reason: where);
            }
          }
        }
      }
    }
  });

  group('never a lower level through fill', () {
    test('real data: bodyweight intermediate phase 1', () {
      gen(tier: 'bodyweight', level: 'intermediate');
      final fills = picks().where((s) => s.source == 'fill').toList();
      expect(fills, isNotEmpty, reason: 'the persona exercises the fill path');
      for (final s in fills) {
        expect(
            _strs(byId[s.pickedId]!['core_levels'])
                .any((l) => _rank[l]! <= _rank['intermediate']!),
            isFalse,
            reason: s.pickedId);
      }
    });

    test('unit: a beginner-core sibling never fills an intermediate slot', () {
      final rows = [
        _row('A_LOW', 'Low', levels: ['beginner'], family: 'f'),
        _row('B_HIGH', 'High', levels: ['advanced'], family: 'f'),
        _row('C_CORE', 'Core Only', levels: ['intermediate'], family: 'f',
            needed: ['barbell']),
      ];
      final r = pool(rows, slot('Glutes', 'hip_dominant'));
      expect(r.source, 'fill');
      expect([for (final x in r.ordered) x['id']], ['B_HIGH']);
    });
  });

  test('no skill or olympic row', () {
    final rows = [
      _row('A_SKILL', 'Skill', discipline: 'calisthenics_skill'),
      _row('B_OLY', 'Oly', discipline: 'olympic'),
      _row('C_OK', 'Fine'),
    ];
    final r = pool(rows, slot('Glutes', 'hip_dominant'));
    expect([for (final x in r.ordered) x['id']], ['C_OK']);
    for (final tier in ['bodyweight', 'full_gym']) {
      gen(tier: tier, level: 'advanced', phase: 5);
      expect(picks().map((s) => s.pickedId).toSet().intersection(_skillIds),
          isEmpty);
    }
  });

  test('ON honours injuries', () {
    for (final injury in ['knee', 'shoulder', 'lower_back']) {
      for (final tier in goldenTiers) {
        trace.slots.clear();
        gen(tier: tier, injuries: [injury]);
        expect(picks(), isNotEmpty, reason: '$injury $tier');
        for (final s in picks()) {
          expect(_strs(byId[s.pickedId]!['injury_contraindications']),
              isNot(contains(injury)),
              reason: '$injury $tier ${s.pickedId}');
        }
      }
    }
  });

  test('ON honours exclusions', () async {
    // Twice: with the capability floor (which already subtracts exclusions)
    // and without it, where only F's own exclusion clause can drop the row —
    // the two are independent kill switches, as in queryV4.
    for (final floorOff in [false, true]) {
      if (floorOff) {
        await HiveService.instance.configBox
            .put('disable_equipment_capability_floor', true);
      }
      trace.slots.clear();
      gen(tier: 'full_gym', exclusions: ['barbell']);
      expect(picks(), isNotEmpty);
      for (final s in picks()) {
        expect(_strs(byId[s.pickedId]!['equipment_needed']),
            isNot(contains('barbell')),
            reason: 'floorOff=$floorOff ${s.pickedId}');
      }
    }
  });

  test('ON with capability null uses the tier rule', () async {
    await HiveService.instance.configBox
        .put('disable_equipment_capability_floor', true);
    gen(tier: 'bodyweight', level: 'beginner');
    expect(picks(), isNotEmpty);
    for (final s in picks()) {
      expect(_strs(byId[s.pickedId]!['equipment_tier']), contains('bodyweight'),
          reason: s.pickedId);
    }
  });

  group('owned equipment turns the implement preference on', () {
    CoreListTraceSlot curlSlot() =>
        picks().firstWhere((s) => s.slot.movementPattern == 'elbow_flexion');

    test('nothing owned: the improvised curl', () {
      gen(tier: 'bodyweight', level: 'beginner', days: 3);
      expect(curlSlot().pickedId, 'E268');
    });

    test('owning dumbbells: a dumbbell curl instead', () async {
      await HiveService.instance.userBox.put('profile', {
        'equipment_owned': ['dumbbells'],
      });
      gen(tier: 'bodyweight', level: 'beginner', days: 3);
      expect(curlSlot().pickedId, isNot('E268'));
      expect(curlSlot().improvisedRemoved, isTrue);
    });
  });

  test('OI-388: a full_gym beginner gets no self-resisted curl or extension',
      () {
    gen(tier: 'full_gym', level: 'beginner', days: 3);
    expect(picks(), isNotEmpty);
    expect(picks().map((s) => s.pickedId), isNot(anyOf(contains('E268'), contains('E270'))));
  });

  group('OI-387', () {
    test('gym tiers after phase 1 pick no improvised shoulder row when the '
        'pool has an implement row', () {
      for (final tier in ['home_dumbbells', 'full_gym']) {
        for (final days in [3, 5]) {
          final p1 = gen(tier: tier, level: 'beginner', days: days);
          trace.slots.clear();
          gen(
              tier: tier,
              level: 'beginner',
              days: days,
              phase: 2,
              prev: namesByDay(p1, lower: true));
          expect(picks(), isNotEmpty, reason: '$tier ${days}d');
          for (final s in picks().where((s) => s.nonImprovisedInPool > 0)) {
            expect(_improvisedShoulder, isNot(contains(s.pickedId)),
                reason: '$tier ${days}d ${s.slot.targetMuscle}');
          }
        }
      }
    });

    test('bodyweight beginner phase 2, 5 days: Lateral Delts gets a raise', () {
      gen(tier: 'bodyweight', level: 'beginner', days: 5, phase: 2);
      final lat = picks().where((s) => s.slot.targetMuscle == 'Lateral Delts');
      expect(lat, isNotEmpty);
      for (final s in lat) {
        expect(['E273', 'E289'], contains(s.pickedId));
      }
    });
  });

  test('OI-385: a calisthenics-typed compound row is typed compound', () {
    expect(CoreListSelector.typeFor(
            {'exercise_type': ['calisthenics', 'compound']},
            slot('Back', 'horizontal_pull', type: 'isolation')),
        'compound');
    expect(CoreListSelector.typeFor(
            {'exercise_type': ['calisthenics', 'isolation']},
            slot('Biceps', 'elbow_flexion')),
        'isolation');
    expect(CoreListSelector.typeFor(
            {'exercise_type': ['calisthenics']}, slot('Core', 'core')),
        'compound');
    final p = gen(tier: 'bodyweight', level: 'beginner');
    expect(picks().map((s) => s.pickedId), contains('E264'));
    final rows = [
      for (final w in p.weekPlans)
        for (final d in w.workoutDays)
          for (final e in d.exercises)
            if (e.exerciseName == 'Table Row') e
    ];
    expect(rows, isNotEmpty);
    for (final e in rows) {
      expect(e.exerciseType, 'compound');
    }
  });

  group('OI-386', () {
    test('unit: a Triceps (Long Head) row ranks first for Triceps / long_head',
        () {
      final rows = [
        _row('A_PLAIN', 'Pushdown', pattern: 'elbow_extension',
            focus: ['Triceps'], type: ['isolation']),
        _row('B_LONG', 'Overhead', pattern: 'elbow_extension',
            focus: ['Triceps (Long Head)'], type: ['isolation'], priority: 2),
      ];
      final r = pool(rows,
          slot('Triceps', 'elbow_extension', type: 'isolation', sub: 'long_head'));
      expect(r.ordered.first['id'], 'B_LONG');
    });

    test('real data: a Core / obliques slot picks an obliques row', () {
      pick([day([slot('Core', 'core', type: 'isolation', sub: 'obliques')])]);
      final s = picks().single;
      expect(
          [..._strs(byId[s.pickedId]!['slot_focus'] ??
              byId[s.pickedId]!['target_focus']),
            ..._strs(byId[s.pickedId]!['primary_muscles'])],
          contains('Core/Obliques'));
      expect(['E090', 'E175'], contains(s.pickedId));
    });
  });

  test('slot_pattern fills the Front Delts isolation slot', () {
    pick([day([slot('Front Delts', 'shoulder_isolation', type: 'isolation')])]);
    final s = picks().single;
    expect(s.pickedId, 'E015');
    expect(s.source, 'core');
  });

  test('family fill, then drop', () {
    final rows = [
      _row('A_CORE', 'Core Barbell', levels: ['intermediate'], family: 'f',
          needed: ['barbell']),
      _row('B_FILL', 'Fill', levels: ['advanced'], family: 'f'),
      _row('C_OTHER', 'Other Family', levels: ['advanced'], family: 'g'),
    ];
    final filled = pool(rows, slot('Glutes', 'hip_dominant'));
    expect(filled.source, 'fill');
    expect(filled.families, {'f'});
    expect([for (final x in filled.ordered) x['id']], ['B_FILL']);
    final dropped = pool(rows.where((r) => r['id'] != 'B_FILL').toList(),
        slot('Glutes', 'hip_dominant'));
    expect(dropped.source, 'drop');
    expect(dropped.ordered, isEmpty);
  });

  // Unit 1B-F (Ruling 7): replaces "stale library delegates to OFF" and "mixed library". With no cascade behind
  // it, a library without `core_levels` has no core row at any level, so nothing is picked: no name-picked fallback
  // bypasses the level, capability and injury filters.
  test('a library without core_levels picks nothing', () async {
    await seed([
      for (final r in shipped) Map<String, dynamic>.from(r)..remove('core_levels')
    ]);
    final days = pick([
      day([slot('Chest', 'horizontal_push'), slot('Glutes', 'hip_dominant')],
          [slot('Chest', 'horizontal_push'), slot('Glutes', 'hip_dominant')]),
    ]);
    expect(picks(), isEmpty);
    expect(days.single.exercisesA, isEmpty);
    expect(days.single.exercisesB, isEmpty);
  });

  test('community and custom rows never selected', () async {
    await seed([
      ...shipped,
      _row('community_x', 'Community Curl', pattern: 'elbow_flexion',
          focus: ['Biceps'], levels: null, family: null)
        ..['source'] = 'community',
    ]);
    gen(tier: 'full_gym', level: 'beginner', days: 3);
    expect(picks(), isNotEmpty);
    expect(picks().map((s) => s.pickedId), isNot(contains('community_x')));
  });

  group('B soft-avoids A', () {
    test('one core row: A and B both pick it, B never drops', () async {
      await seed([_row('G1', 'Glute One')]);
      final d = pick([day([slot('Glutes', 'hip_dominant')],
          [slot('Glutes', 'hip_dominant')])]).single;
      expect(names(d.exercisesA), ['Glute One']);
      expect(names(d.exercisesB), ['Glute One']);
      expect(trace.slots.where((s) => s.variant == 'B' && s.source == 'drop'),
          isEmpty);
    });

    test('B repeats A rather than take a demoted row', () async {
      await seed([_row('G1', 'Glute One'), _row('G2', 'Glute Two', priority: 2)]);
      await demote('Glute Two');
      final d = pick([day([slot('Glutes', 'hip_dominant')],
          [slot('Glutes', 'hip_dominant')])], phase: 2).single;
      expect(names(d.exercisesA), ['Glute One']);
      expect(names(d.exercisesB), ['Glute One']);
    });
  });

  test('an emptied variant copies the other', () async {
    await seed([_row('G1', 'Glute One')]);
    final d = pick([day([slot('Glutes', 'hip_dominant')],
        [slot('Biceps', 'elbow_flexion')])]).single;
    expect(names(d.exercisesB), names(d.exercisesA));
    expect(names(d.exercisesA), ['Glute One']);
    expect(trace.copied, [(day: 0, variant: 'B')]);
  });

  test('both empty → any-level core, never retired', () async {
    await seed([
      _row('A_RET', 'Retired', levels: [], family: null),
      _row('B_LOW', 'Lower Core', levels: ['beginner'], family: 'f'),
    ]);
    final d = pick([day([slot('Glutes', 'hip_dominant')],
        [slot('Glutes', 'hip_dominant')])]).single;
    expect(names(d.exercisesA), ['Lower Core']);
    expect(names(d.exercisesB), ['Lower Core']);
    expect(trace.emergencyAnyLevel.map((e) => e.day), contains(0));
  });

  group('any-level emergency gives easier core moves only (Ruling 12)', () {
    test('nearest easier level first', () {
      final rows = [
        _row('A_BEG', 'Easy', levels: ['beginner']),
        _row('B_INT', 'Mid', levels: ['intermediate']),
      ];
      final r = pool(rows, slot('Glutes', 'hip_dominant'),
          level: 'advanced', anyCoreLevel: true);
      expect([for (final x in r.ordered) x['id']], ['B_INT', 'A_BEG']);
    });

    test('never a harder-only row', () {
      final rows = [
        _row('A_ADV', 'Hard', levels: ['advanced']),
        _row('B_BEG', 'Easy', levels: ['beginner']),
      ];
      final r = pool(rows, slot('Glutes', 'hip_dominant'), anyCoreLevel: true);
      expect([for (final x in r.ordered) x['id']], ['B_BEG']);
    });
  });

  test('injured user keeps the soft avoid and L6', () async {
    final rows = [
      _row('C1', 'Machine Chest Press', pattern: 'horizontal_push', focus: ['Chest']),
      _row('C2', 'Floor Press', pattern: 'horizontal_push', focus: ['Chest']),
      _row('C3', 'Push Up', pattern: 'horizontal_push', focus: ['Chest']),
      _row('C4', 'Other Press', pattern: 'horizontal_push', focus: ['Chest']),
    ];
    await seed(rows);
    final d = pick([day([slot('Chest', 'horizontal_push')],
            [slot('Chest', 'horizontal_push')])],
        injuries: ['shoulder'], subPref: true).single;
    // An injured user's one-slot day is thin, so the thin-day top-up (OI-401)
    // fills it to the floor AFTER the pool pick: the pick this test is about is
    // the FIRST entry, the rest is top-up from the same chest pattern.
    expect(names(d.exercisesA).first, 'Machine Chest Press');
    expect(names(d.exercisesA), hasLength(3));
    expect(names(d.exercisesB).first, 'Floor Press');
    expect(names(d.exercisesB), hasLength(3));
    await demote('Machine Chest Press');
    final d2 = pick([day([slot('Chest', 'horizontal_push')])],
        injuries: ['shoulder'], subPref: true, phase: 2).single;
    expect(names(d2.exercisesA).first, 'Floor Press');
    expect(names(d2.exercisesA), isNot(contains('Machine Chest Press')),
        reason: 'L6: three other safe rows exist, so the demoted name is not '
            'topped back in');
  });

  test('cables sub-focus', () {
    final rows = [
      _row('A_DB', 'DB Rear Fly', pattern: 'shoulder_isolation',
          focus: ['Rear Delts'], needed: ['dumbbells'], type: ['isolation']),
      _row('B_CABLE', 'Cable Rear Fly', pattern: 'shoulder_isolation',
          focus: ['Rear Delts'], needed: ['cables'], type: ['isolation']),
    ];
    final r = pool(
        rows,
        slot('Rear Delts', 'shoulder_isolation', type: 'isolation', sub: 'cable'),
        capability: TrainingHistoryAnalyzer.resolveCapability(
            tier: 'full_gym', exclusions: const {}, flagEnabled: true));
    expect(r.ordered.first['id'], 'B_CABLE');
  });

  group('variety levers work ON', () {
    final hipRows = [
      _row('H1', 'Hip One'),
      _row('H2', 'Hip Two', priority: 2),
    ];
    List<String> hipPick(
            {int phase = 1,
            Set<String> plateau = const {},
            Map<int, ({List<String> a, List<String> b})>? prev}) =>
        names(pick([day([slot('Glutes', 'hip_dominant')])],
                phase: phase, plateau: plateau, prev: prev)
            .single
            .exercisesA);

    test('L6: a demoted name loses even to a previous-phase name', () async {
      await seed(hipRows);
      await demote('Hip One');
      expect(hipPick(phase: 2, prev: {0: (a: ['hip two'], b: const <String>[])}),
          ['Hip Two']);
    });

    test('cross-phase: the previous phase\'s pick rotates', () async {
      await seed(hipRows);
      expect(hipPick(phase: 2), ['Hip One']);
      expect(hipPick(phase: 2, prev: {0: (a: ['hip one'], b: const <String>[])}),
          ['Hip Two']);
    });

    test('plateau: a plateaued name rotates to its sibling', () async {
      await seed(hipRows);
      expect(hipPick(plateau: {'hip one'}), ['Hip Two']);
    });
  });

  // ---------------------------------------------------------------------------
  // Generator step 1A (docs/plans/2026-11-08-generator-step1-core-list.md)
  // ---------------------------------------------------------------------------
  Set<String>? capOf(String tier) => TrainingHistoryAnalyzer.resolveCapability(
      tier: tier, exclusions: const {}, flagEnabled: true);
  List<String> ids(List<Map<String, dynamic>> xs) =>
      [for (final r in xs) r['id'] as String];

  group('R2: jump rows leave a mixed pool', () {
    final knee = slot('Quads', 'knee_dominant');
    Map<String, dynamic> jump(String id, {bool plyo = true, bool impact = true}) =>
        {
          ..._row(id, 'Jump $id', pattern: 'knee_dominant', focus: ['Quads'],
              discipline: plyo ? 'plyometric' : 'strength'),
          'high_impact': impact,
        };

    test('a jump row sorting first is removed (control: priority alone would '
        'pick it)', () {
      final rows = [
        jump('A_JUMP'),
        _row('B_SQUAT', 'Squat', pattern: 'knee_dominant', focus: ['Quads'],
            priority: 2),
      ];
      final r = pool(rows, knee);
      expect(ids(r.ordered), ['B_SQUAT']);
      expect(r.jumpRemoved, isTrue);
      expect(r.jumpOnlyPool, isFalse);
    });

    test('either marker is enough: high_impact alone, plyometric alone', () {
      for (final j in [
        jump('A_IMPACT', plyo: false),
        jump('A_PLYO', impact: false),
      ]) {
        final r = pool([
          j,
          _row('B_SQUAT', 'Squat', pattern: 'knee_dominant', focus: ['Quads']),
        ], knee);
        expect(ids(r.ordered), ['B_SQUAT'], reason: j['id'] as String);
      }
    });

    test('a jump-only pool is kept, never emptying the slot', () {
      final r = pool([jump('A_JUMP'), jump('B_JUMP')], knee);
      expect(ids(r.ordered), ['A_JUMP', 'B_JUMP']);
      expect(r.jumpRemoved, isFalse);
      expect(r.jumpOnlyPool, isTrue);
    });

    test('runs before the improvised filter: a lone implement jump row cannot '
        'outlive the improvised rows', () {
      final r = pool([
        {
          ..._row('A_JUMP_DB', 'DB Jump Curl', pattern: 'elbow_flexion',
              focus: ['Biceps'], needed: ['dumbbells'], type: ['isolation'],
              discipline: 'plyometric'),
        },
        _row('B_TOWEL', 'Towel Curl', pattern: 'elbow_flexion',
            focus: ['Biceps'], type: ['isolation']),
      ], slot('Biceps', 'elbow_flexion', type: 'isolation'),
          capability: capOf('home_dumbbells'));
      expect(ids(r.ordered), ['B_TOWEL']);
      expect(r.jumpRemoved, isTrue);
      expect(r.improvisedRemoved, isFalse);
    });

    test('real data: no jump row leads a knee slot for an intermediate on any '
        'tier when a non-jump core row exists', () {
      final jumpIds = {for (final r in shipped) if (CoreListSelector.isJumpRow(r)) r['id']};
      expect(jumpIds, containsAll(['E193', 'G3582']));
      for (final tier in ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym']) {
        final r = CoreListSelector.rankedPool(
          rows: shipped,
          slot: knee,
          level: 'intermediate',
          phase: 1,
          equipmentTier: tier,
          capability: capOf(tier),
          exclusions: const {},
          isContraindicated: (_) => false,
          pickedNames: const {},
          demotedNames: const {},
        );
        expect(r.ordered, isNotEmpty, reason: tier);
        if (!r.jumpOnlyPool) {
          expect(r.ordered.where(CoreListSelector.isJumpRow), isEmpty,
              reason: tier);
        }
      }
    });
  });

  group('R2 through the real pick: variant B, phase 2, a Strength Squat Day', () {
    // One non-jump row and a jump row that would win every earlier key. Once
    // variant B (or phase 2) avoids the non-jump row, _preferNovel would walk to
    // the jump row if it were only sorted last; the partition keeps it out.
    final knee = slot('Quads', 'knee_dominant');
    final rows = [
      {
        ..._row('A_JUMP', 'Jump Lunge', pattern: 'knee_dominant', focus: ['Quads'],
            discipline: 'plyometric'),
        'high_impact': true,
      },
      _row('B_SQUAT', 'Split Squat', pattern: 'knee_dominant', focus: ['Quads'],
          priority: 2),
    ];

    test('variant B repeats the squat rather than take the jump row', () async {
      await seed(rows);
      final d = pick([day([knee], [knee])]).single;
      expect(names(d.exercisesA), ['Split Squat']);
      expect(names(d.exercisesB), ['Split Squat']);
    });

    test('phase 2 with the squat in the avoid set keeps the squat', () async {
      await seed(rows);
      final d = pick([day([knee])],
          phase: 2, prev: {0: (a: ['split squat'], b: const <String>[])}).single;
      expect(names(d.exercisesA), ['Split Squat']);
    });

    test('real data: Strength 4-day home_dumbbells intermediate Squat Day holds '
        'no jump row, in either variant, phases 1 and 2', () {
      final jumpNames = {
        for (final r in shipped)
          if (CoreListSelector.isJumpRow(r)) (r['name'] as String).toLowerCase()
      };
      for (final phase in const [1, 2]) {
        final p = gen(
            goal: 'strength', tier: 'home_dumbbells', days: 4, phase: phase);
        final squatDays = [
          for (final w in p.weekPlans.take(2))
            for (final d in w.workoutDays)
              if (d.name == 'Squat Day') d
        ];
        expect(squatDays, hasLength(2), reason: 'phase $phase');
        for (final d in squatDays) {
          final n = [for (final e in d.exercises) e.exerciseName.toLowerCase()];
          expect(n.where(jumpNames.contains), isEmpty, reason: 'phase $phase $n');
        }
      }
    });
  });

  group('R3 (a): like-for-like implement rows in an isolation slot', () {
    final calves = slot('Calves', 'knee_dominant', type: 'isolation');
    final rows = [
      _row('A_BW', 'Bodyweight Calf Raise', pattern: 'knee_dominant',
          focus: ['Calves'], type: ['isolation']),
      {
        ..._row('B_LUNGE', 'DB Lunge', pattern: 'knee_dominant',
            focus: ['Calves'], needed: ['dumbbells']),
        'primary_muscles': ['Quads', 'Calves'],
      },
      {
        ..._row('C_SOLEUS', 'DB Seated Calf Raise', pattern: 'knee_dominant',
            focus: ['Calves'], needed: ['dumbbells'], type: ['isolation']),
        'primary_muscles': ['Calves (Soleus)'],
      },
      {
        ..._row('D_PERONEUS', 'DB Calf Eversion', pattern: 'knee_dominant',
            focus: ['Calves'], needed: ['dumbbells'], type: ['isolation']),
        'primary_muscles': ['Calves (Peroneus)'],
      },
    ];

    test('namesMuscle: equal, listed head, never a prefix or unlisted head', () {
      expect(CoreListSelector.namesMuscle('Calves', 'calves'), isTrue);
      expect(CoreListSelector.namesMuscle(' calves (soleus) ', 'Calves'), isTrue);
      expect(CoreListSelector.namesMuscle('Calves (Gastrocnemius)', 'Calves'),
          isTrue);
      expect(CoreListSelector.namesMuscle('Calves (Peroneus)', 'Calves'), isFalse);
      expect(CoreListSelector.namesMuscle('Calves extra', 'Calves'), isFalse);
      expect(CoreListSelector.namesMuscle('Glutes (Medius)', 'Glutes'), isFalse);
      expect(CoreListSelector.namesMuscle('Quads', 'Calves'), isFalse);
    });

    test('an implement user\'s pool is reduced to like-for-like rows', () {
      final r = pool(rows, calves, capability: capOf('home_dumbbells'));
      expect(ids(r.ordered), ['C_SOLEUS']);
      expect(r.likeForLikeImplement, isTrue);
    });

    test('a bodyweight-only user: no reduction (the implement rows fail the '
        'capability filter before it)', () {
      final r = pool(rows, calves);
      expect(r.likeForLikeImplement, isFalse);
      expect(ids(r.ordered), ['A_BW']);
    });

    test('a compound implement row that lists the muscle first is not '
        'like-for-like (only isolation rows are)', () {
      final r = pool([
        ...rows,
        {
          ..._row('E_DBHOP', 'DB Calf Complex', pattern: 'knee_dominant',
              focus: ['Calves'], needed: ['dumbbells']),
          'primary_muscles': ['Calves'],
        },
      ], calves, capability: capOf('home_dumbbells'));
      expect(ids(r.ordered), ['C_SOLEUS']);
    });

    test('no like-for-like row: the pool is left alone', () {
      final r = pool([rows[0], rows[1], rows[3]], calves,
          capability: capOf('home_dumbbells'));
      expect(r.likeForLikeImplement, isFalse);
      expect(r.ordered, hasLength(3));
    });

    test('a compound slot and a core slot are not reduced', () {
      final compound = pool(rows, slot('Calves', 'knee_dominant'),
          capability: capOf('home_dumbbells'));
      expect(compound.likeForLikeImplement, isFalse);
      final core = pool([
        _row('A_PLANK', 'Plank', pattern: 'core', focus: ['Core'],
            type: ['isolation']),
        _row('B_DB', 'DB Crunch', pattern: 'core', focus: ['Core'],
            needed: ['dumbbells'], type: ['isolation']),
      ], slot('Core', 'core', type: 'isolation'),
          capability: capOf('home_dumbbells'));
      expect(core.likeForLikeImplement, isFalse);
      expect(ids(core.ordered), ['A_PLANK', 'B_DB']);
    });

    test('real data: full_gym intermediate Calves keeps both calf machines', () {
      final r = CoreListSelector.rankedPool(
        rows: shipped,
        slot: calves,
        level: 'intermediate',
        phase: 1,
        equipmentTier: 'full_gym',
        capability: capOf('full_gym'),
        exclusions: const {},
        isContraindicated: (_) => false,
        pickedNames: const {},
        demotedNames: const {},
      );
      expect(r.likeForLikeImplement, isTrue);
      expect(ids(r.ordered), containsAll(['E051', 'E052']));
      for (final row in r.ordered) {
        expect(_strs(row['exercise_type']), contains('isolation'),
            reason: row['name'] as String);
      }
    });
  });

  group('R3 (b): implement fit before priority in a compound slot', () {
    final ohp = slot('Shoulders', 'vertical_push');
    final rows = [
      _row('A_PIKE', 'Pike', pattern: 'vertical_push', focus: ['Shoulders']),
      _row('B_OHP', 'Barbell OHP', pattern: 'vertical_push',
          focus: ['Shoulders'], needed: ['barbell']),
    ];

    test('a barbell user gets the barbell row (control: bodyweight gets Pike)',
        () {
      expect(ids(pool(rows, ohp, capability: capOf('basic_gym')).ordered).first,
          'B_OHP');
      expect(ids(pool(rows, ohp).ordered).first, 'A_PIKE');
    });

    test('fit outranks priority_tier', () {
      final r = pool([
        rows[0],
        {...rows[1], 'priority_tier': 2},
      ], ohp, capability: capOf('basic_gym'));
      expect(ids(r.ordered).first, 'B_OHP');
    });

    test('variant B of a dumbbell user walks to the other press, never to Pike '
        '(vertical_push is an implement pattern; a key alone lost to the '
        'phase-1 foundational key once A\'s press was avoided)', () async {
      await seed([
        _row('A_ARNOLD', 'Arnold Press', pattern: 'vertical_push',
            focus: ['Shoulders'], needed: ['dumbbells']),
        _row('B_PIKE', 'Pike', pattern: 'vertical_push', focus: ['Shoulders']),
        {
          ..._row('C_DBOHP', 'DB Alternate Press', pattern: 'vertical_push',
              focus: ['Shoulders'], needed: ['dumbbells'], priority: 2),
          'is_foundational': false,
        },
      ]);
      final d = pick([day([ohp], [ohp])], tier: 'home_dumbbells').single;
      expect(names(d.exercisesA), ['Arnold Press']);
      expect(names(d.exercisesB), ['DB Alternate Press']);
      final bw = pick([day([ohp], [ohp])], tier: 'bodyweight').single;
      expect(names(bw.exercisesA), ['Pike'], reason: 'control: bodyweight keeps Pike');
    });

    // Core only: since Unit 1B-R (Ruling 2) the fit key applies in isolation slots too; its isolation counterpart is
    // T1 in loaded_wins_behavioral_test.dart.
    test('core slots ignore the fit key', () {
      final core = pool([
        _row('A_BW', 'Hollow Hold', pattern: 'core', focus: ['Core']),
        _row('B_BAR', 'Barbell Rollout', pattern: 'core', focus: ['Core'],
            needed: ['barbell']),
      ], slot('Core', 'core'), capability: capOf('basic_gym'));
      expect(ids(core.ordered), ['A_BW', 'B_BAR']);
    });

    test('real data: basic_gym intermediate overhead press is E011, not Pike', () {
      final r = CoreListSelector.rankedPool(
        rows: shipped,
        slot: ohp,
        level: 'intermediate',
        phase: 1,
        equipmentTier: 'basic_gym',
        capability: capOf('basic_gym'),
        exclusions: const {},
        isContraindicated: (_) => false,
        pickedNames: const {},
        demotedNames: const {},
      );
      expect(ids(r.ordered).first, 'E011');
      expect(ids(r.ordered), isNot(contains('E010')),
          reason: 'vertical_push is an implement pattern: Pike leaves the pool');
      expect(r.improvisedRemoved, isTrue);
    });
  });

  group('R5: glute-first last tie-break in a Glutes hinge slot', () {
    final rows = [
      {
        ..._row('A_DL', 'Deadlift', needed: ['barbell']),
        'primary_muscles': ['Lower Back', 'Glutes'],
      },
      {
        ..._row('B_HT', 'Hip Thrust', needed: ['barbell']),
        'primary_muscles': ['Glutes'],
      },
    ];

    test('Glutes slot: glute-first wins the tie; Hamstrings slot: id order', () {
      expect(ids(pool(rows, slot('Glutes', 'hip_dominant'),
              capability: capOf('full_gym')).ordered),
          ['B_HT', 'A_DL']);
      final hams = [
        for (final r in rows) {...r, 'target_focus': ['Glutes', 'Hamstrings']}
      ];
      expect(ids(pool(hams, slot('Hamstrings', 'hip_dominant'),
              capability: capOf('full_gym')).ordered),
          ['A_DL', 'B_HT']);
    });

    test('it is the LAST key: a better priority still wins', () {
      final r = pool([
        rows[0],
        {...rows[1], 'priority_tier': 2},
      ], slot('Glutes', 'hip_dominant'), capability: capOf('full_gym'));
      expect(ids(r.ordered), ['A_DL', 'B_HT']);
    });

    test('real data: full_gym intermediate Glutes hinge picks E047 Hip Thrust, '
        'Hamstrings hinge keeps E021 Deadlift', () {
      ({List<Map<String, dynamic>> ordered, String source, bool improvisedRemoved,
          int nonImprovisedInPool, Set<String> families, bool jumpRemoved,
          bool jumpOnlyPool, bool likeForLikeImplement}) real(String m) =>
          CoreListSelector.rankedPool(
            rows: shipped,
            slot: slot(m, 'hip_dominant'),
            level: 'intermediate',
            phase: 1,
            equipmentTier: 'full_gym',
            capability: capOf('full_gym'),
            exclusions: const {},
            isContraindicated: (_) => false,
            pickedNames: const {},
            demotedNames: const {},
          );
      expect(real('Glutes').ordered.first['id'], 'E047');
      expect(real('Hamstrings').ordered.first['id'], 'E021');
    });
  });
}
