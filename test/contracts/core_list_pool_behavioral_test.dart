// Batch B1 Task 3 — the core-list pool (`enable_core_list_pool`, ship-dark).
//
// Drives the REAL ExerciseSelector.pickV4 / PlanGenerator.generateV4 over the
// shipped library (or crafted rows) with the flag ON. Provenance comes from
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

import '../../scripts/migration_ledger_hash_lib.dart' show sha256Hex;
import '../helpers/generator_golden_personas.dart';

const _rank = {'beginner': 0, 'intermediate': 1, 'advanced': 2};
const _skillIds = {
  'E069', 'E070', 'E071', 'E072', 'E073', 'E074', 'E086', 'E101', 'E179', 'E180',
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
    await HiveService.instance.configBox.put('enable_core_list_pool', true);
    trace = CoreListTrace();
    CoreListSelector.debugTrace = trace;
  });

  tearDown(() async {
    CoreListSelector.debugTrace = null;
    final config = HiveService.instance.configBox;
    await config.delete('enable_core_list_pool');
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
      int nonImprovisedInPool, Set<String> families}) pool(
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

  test('OFF is the golden', () async {
    await HiveService.instance.configBox.delete('enable_core_list_pool');
    final fixture = jsonDecode(
            File('test/fixtures/generator_golden_hashes.json').readAsStringSync())
        as Map<String, dynamic>;
    const keys = [
      'grid|bodyweight|build_muscle|4d|beginner|p1',
      'grid|home_dumbbells|lose_fat|3d|intermediate|p2',
      'grid|basic_gym|strength|5d|advanced|p3',
      'grid|full_gym|general_fitness|6d|intermediate|p5',
    ];
    final personas = {for (final p in generatorGoldenPersonas()) p.key: p};
    for (final k in keys) {
      expect(sha256Hex(utf8.encode(jsonEncode(personas[k]!.run().toMap()))),
          fixture[k],
          reason: k);
    }
    expect(trace.delegations, 0);
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

  test('stale library delegates to OFF', () async {
    await seed([
      for (final r in shipped) Map<String, dynamic>.from(r)..remove('core_levels')
    ]);
    final fixture = jsonDecode(
            File('test/fixtures/generator_golden_hashes.json').readAsStringSync())
        as Map<String, dynamic>;
    final p = gen(tier: 'full_gym', level: 'intermediate');
    expect(trace.delegations, 0);
    expect(sha256Hex(utf8.encode(jsonEncode(p.toMap()))),
        fixture['grid|full_gym|build_muscle|4d|intermediate|p1']);
  });

  test('mixed library', () async {
    await seed([
      for (final r in shipped)
        r['id'] == 'E001' ? r : (Map<String, dynamic>.from(r)..remove('core_levels'))
    ]);
    pick([day([slot('Chest', 'horizontal_push')])]);
    expect(trace.delegations, 1);
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
    expect(trace.refilled, isEmpty);
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

  test('OFF cascade only as the last resort', () async {
    await seed([_row('X1', 'Core Move', pattern: 'core', focus: ['Core'])]);
    pick([day([slot('Glutes', 'hip_dominant')], [slot('Glutes', 'hip_dominant')])]);
    expect(trace.refilled.map((e) => e.day), contains(0));
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
    expect(names(d.exercisesA), ['Machine Chest Press']);
    expect(names(d.exercisesB), ['Floor Press']);
    await demote('Machine Chest Press');
    final d2 = pick([day([slot('Chest', 'horizontal_push')])],
        injuries: ['shoulder'], subPref: true, phase: 2).single;
    expect(names(d2.exercisesA), ['Floor Press']);
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
}
