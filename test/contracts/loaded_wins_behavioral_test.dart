// Unit 1B-R (founder d24 / d25, OI-497, OI-387; plan docs/plans/2026-11-12-generator-1br-loaded-wins.md, diagnose
// docs/diagnoses/2026-11-12-generator-loaded-wins-e4b7a2.md): for a user with dumbbells or a gym the loaded move wins
// over the bodyweight one.
//   Ruling 2: `CoreListSelector.rankedPool`'s fit key orders rows of equal sub-focus and type match in every non-core
//             slot (it was compound slots only), so the quad slot typed `isolation` takes a loaded lunge.
//   Ruling 3: in phase 1 a bodyweight row gives way to `topFit`, the loaded row that will actually be picked (skipping
//             the names `_preferNovel` walks past), when `topFit` matches the slot at least as well.
//   Ruling 4: kill switch `disable_loaded_wins` (`rankedPool(loadedWins: false)` restores both).
// Synthetic rows through the pure `rankedPool` unless stated; the real `pickV4` / `generateV4` where named.
//
// Mutations (diagnose doc, each reddens the test named in brackets): M1 `fitApplies` back to compound only [T1]; M2 the
// new key dropped [T3, T4b]; M3 the new key after key d [T3]; M4 / M4b the `phase == 1` guard dropped / `>= 1` [T3d];
// M5 the key's match test -> true [T2, T3b]; M5b `<=` -> `<` [T3, T4b]; M6 `fits` ignores household items [T11]; M7
// `!fits` -> `fits` [T3]; M8 `fitApplies` dropped from the `topFit` guard [T9]; M9 `loadedWins` ignored by Ruling 2 /
// by Ruling 3 [T1 / T3 switch-off cases]; M10 the flag read ignored [T5 switch-off, the kill-switch golden]; M11
// `slotMatch` without the sub-focus term [T3c]; M13 `slotMatch` weights swapped [T3e]; M14 `topFit` ignores
// `walkedNames` [T3d]; M15 `topFit` ignores the soft avoid [T10b]; M16 `topFit` chosen by id [T3f]; M17 the default
// `topFitMatch` 4 -> 3 [T14, T6]; M18 the new key before the soft-avoid key [T10]; M19 no `toLowerCase()` in the walked
// check [T3d]; M20 `topFit` ignores demoted names [T10c]; M21 `byRest` without the easier gap [T12b]; M22 the new key
// before the easier-gap key [T12b].
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
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/training_history_analyzer.dart';

const _all = ['beginner', 'intermediate', 'advanced'];

Map<String, dynamic> _row(
  String id,
  String name, {
  String pattern = 'hip_dominant',
  List<String> focus = const ['Glutes'],
  List<String> needed = const ['bodyweight'],
  List<String> type = const ['compound'],
  bool foundational = true,
  int priority = 1,
  List<String> levels = _all,
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
      'suitable_for': ['Beginner', 'Intermediate', 'Advanced'],
      'is_foundational': foundational,
      'priority_tier': priority,
      'injury_contraindications': <String>[],
      'logging_type': 'weighted_reps',
      'default_sets': 3,
      'default_reps': '10',
      'default_rest_secs': 60,
      'rep_range': '8-12',
      'is_active': true,
      'core_levels': levels,
      'discipline': 'strength',
    };

Set<String>? _cap(String tier) =>
    TrainingHistoryAnalyzer.resolveCapability(tier: tier, exclusions: const {}, flagEnabled: true);

MuscleSlot _slot(String muscle, String pattern, {String type = 'compound', String? sub}) => MuscleSlot(
      targetMuscle: muscle,
      subFocus: sub,
      movementPattern: pattern,
      exerciseType: type,
      priority: 1,
    );

List<String> _order(
  List<Map<String, dynamic>> rows,
  MuscleSlot slot, {
  int phase = 1,
  String tier = 'home_dumbbells',
  String level = 'intermediate',
  Set<String> walked = const {},
  Set<String> soft = const {},
  Set<String> demoted = const {},
  bool anyCoreLevel = false,
  bool loadedWins = true,
}) =>
    [
      for (final r in CoreListSelector.rankedPool(
        rows: rows,
        slot: slot,
        level: level,
        phase: phase,
        equipmentTier: tier,
        capability: _cap(tier),
        exclusions: const {},
        isContraindicated: (_) => false,
        pickedNames: const {},
        demotedNames: demoted,
        softAvoidNames: soft,
        walkedNames: walked,
        anyCoreLevel: anyCoreLevel,
        loadedWins: loadedWins,
      ).ordered)
        r['id'] as String
    ];

/// The first row `_preferNovel` would return: the first one not walked past.
String _firstNotWalked(List<String> ids, Map<String, String> nameOf, Set<String> walked) =>
    ids.firstWhere((id) => !walked.contains(nameOf[id]!.toLowerCase()));

void main() {
  // The quad slot typed `isolation` (split_resolver.dart, Legs / Lower Body / Squat Day).
  final quadIso = _slot('Quads', 'knee_dominant', type: 'isolation', sub: 'isolation');
  final hinge = _slot('Glutes', 'hip_dominant');
  final hingeUpper = _slot('Glutes', 'hip_dominant', sub: 'upper');

  group('Ruling 2: the fit key reaches isolation-typed slots', () {
    final rows = [
      _row('A_WL', 'Walking Lunge', pattern: 'knee_dominant', focus: ['Quads', 'Glutes']),
      _row('B_DWL', 'Dumbbell Walking Lunge',
          pattern: 'knee_dominant', focus: ['Quads', 'Glutes'], needed: ['dumbbells'], foundational: false),
    ];

    test('T1: phase 2, a dumbbell user gets the loaded lunge in the isolation-typed quad slot', () {
      expect(_order(rows, quadIso, phase: 2).first, 'B_DWL');
    });

    test('T1 control: a bodyweight user keeps Walking Lunge first (the dumbbell row does not fit their kit)', () {
      expect(_order(rows, quadIso, phase: 2, tier: 'bodyweight').first, 'A_WL');
    });

    test('T1 switch off (Ruling 2 only): the bodyweight lunge first again, by foundational', () {
      expect(_order(rows, quadIso, phase: 2, loadedWins: false).first, 'A_WL');
    });

    test('T2: an isolation bodyweight row still outranks a loaded compound in an isolation slot, phases 1 and 2', () {
      final r = [
        _row('A_WS', 'Wall Sit', pattern: 'knee_dominant', focus: ['Quads'], type: ['isolation']),
        _row('B_SU', 'Step Up', pattern: 'knee_dominant', focus: ['Quads', 'Glutes'], needed: ['dumbbells']),
      ];
      expect(_order(r, quadIso, phase: 1).first, 'A_WS');
      expect(_order(r, quadIso, phase: 2).first, 'A_WS');
    });
  });

  group('Ruling 3: in phase 1 the loaded row that will be picked wins when it fits the slot as well', () {
    final hingeRows = [
      _row('A_SLGB', 'Single Leg Glute Bridge'),
      _row('B_DHT', 'Dumbbell Hip Thrust', needed: ['dumbbells'], foundational: false),
    ];

    test('T3: phase 1, a non-foundational loaded hinge outranks a foundational bodyweight one', () {
      expect(_order(hingeRows, hinge), ['B_DHT', 'A_SLGB']);
    });

    test('T3 phase 2: the fit key already put the loaded hinge first', () {
      expect(_order(hingeRows, hinge, phase: 2), ['B_DHT', 'A_SLGB']);
    });

    test('T3 switch off (Ruling 3 only): phase 1 keeps the foundational bodyweight hinge first', () {
      expect(_order(hingeRows, hinge, loadedWins: false), ['A_SLGB', 'B_DHT']);
    });

    test('T3b: a bodyweight row of the right type stays ahead of a loaded row of the wrong type, phases 1 and 2', () {
      final r = [
        _row('A_BW', 'Bodyweight Hinge'),
        _row('B_ISO', 'Dumbbell Hinge Iso', needed: ['dumbbells'], type: ['isolation']),
      ];
      expect(_order(r, hinge).first, 'A_BW');
      expect(_order(r, hinge, phase: 2).first, 'A_BW');
    });

    test('T3c: a bodyweight row that matches the sub-focus stays ahead of a loaded row that misses it', () {
      final r = [
        _row('A_UP', 'Bodyweight Upper Glute', focus: ['Glutes (Upper)']),
        _row('B_DB', 'Dumbbell Glute', needed: ['dumbbells']),
      ];
      expect(_order(r, hingeUpper).first, 'A_UP');
    });

    // Review round 2: A bodyweight right type, B loaded wrong type, C loaded best; all foundational.
    final abc = [
      _row('A_BW', 'A Row'),
      _row('B_ISO', 'B Row', needed: ['dumbbells'], type: ['isolation']),
      _row('C_BEST', 'C Row', needed: ['dumbbells'], focus: ['Glutes (Upper)']),
    ];
    final nameOf = {for (final r in abc) r['id'] as String: r['name'] as String};

    test('T3d: with C walked past, the pick is A in phase 1 as in phase 2 (never B)', () {
      const walked = {'c row'};
      final p1 = _order(abc, hingeUpper, walked: walked);
      final p2 = _order(abc, hingeUpper, phase: 2, walked: walked);
      expect(p1, ['C_BEST', 'A_BW', 'B_ISO']);
      expect(p2, ['C_BEST', 'A_BW', 'B_ISO']);
      expect(_firstNotWalked(p1, nameOf, walked), 'A_BW');
    });

    test('T3d: with C available, phase 1 puts A behind both loaded rows, phase 2 keeps the slot match order', () {
      expect(_order(abc, hingeUpper), ['C_BEST', 'B_ISO', 'A_BW']);
      expect(_order(abc, hingeUpper, phase: 2), ['C_BEST', 'A_BW', 'B_ISO']);
    });

    test('T3d companion: a foundational loaded topFit still beats a non-foundational better-matching bodyweight '
        'row (key d, as before 1B-R)', () {
      final r = [
        _row('A_UPNF', 'Upper Glute Bodyweight', focus: ['Glutes (Upper)'], foundational: false),
        _row('B_DB', 'Dumbbell Glute', needed: ['dumbbells']),
      ];
      expect(_order(r, hingeUpper).first, 'B_DB');
      expect(_order(r, hingeUpper, loadedWins: false).first, 'B_DB');
    });

    test('T3e: the sub-focus weighs more than the type (a sub-hit type-miss bodyweight row stays first)', () {
      final r = [
        _row('A_SUBHIT', 'Upper Glute Iso', focus: ['Glutes (Upper)'], type: ['isolation']),
        _row('B_TYPEHIT', 'Dumbbell Glute', needed: ['dumbbells']),
      ];
      expect(_order(r, hingeUpper).first, 'A_SUBHIT');
    });

    test('T3f: topFit is the first loaded row by the keys that follow, not by id', () {
      final r = [
        _row('A_F', 'Dumbbell Glute Miss', needed: ['dumbbells']),
        _row('B_F', 'Dumbbell Glute Hit', needed: ['dumbbells'], focus: ['Glutes (Upper)']),
        _row('C_W', 'Upper Glute Iso Bodyweight', focus: ['Glutes (Upper)'], type: ['isolation']),
      ];
      expect(_order(r, hingeUpper), ['B_F', 'A_F', 'C_W']);
    });

    test('T4: a gym user\'s loaded rows keep their foundational order; the bodyweight row goes behind both', () {
      final r = [
        _row('A_BAR', 'Barbell Hinge', needed: ['barbell'], priority: 2),
        _row('B_MACH', 'Machine Hinge', needed: ['machines'], foundational: false),
        _row('C_BW', 'Bodyweight Hinge'),
      ];
      expect(_order(r, hinge, tier: 'full_gym'), ['A_BAR', 'B_MACH', 'C_BW']);
      expect(_order(r, hinge, tier: 'full_gym', loadedWins: false), ['A_BAR', 'C_BW', 'B_MACH']);
    });

    test('T4b: transitive (a bodyweight row of a worse class cannot jump ahead of the loaded best row)', () {
      final r = [
        _row('A_W1', 'Bodyweight Hinge Iso', type: ['isolation']),
        _row('B_L', 'Dumbbell Hinge', needed: ['dumbbells'], foundational: false),
        _row('C_W2', 'Bodyweight Hinge'),
      ];
      expect(_order(r, hinge).first, 'B_L');
    });

    test('T9: a CORE slot ignores both rules in phase 1', () {
      final r = [
        _row('A_HOLLOW', 'Hollow Hold', pattern: 'core', focus: ['Core']),
        _row('B_ROLL', 'Barbell Rollout', pattern: 'core', focus: ['Core'], needed: ['barbell'], foundational: false),
      ];
      expect(_order(r, _slot('Core', 'core'), tier: 'full_gym'), ['A_HOLLOW', 'B_ROLL']);
    });

    test('T10: a soft-avoided loaded row still sorts after the bodyweight row (the new key follows the soft avoid)', () {
      final r = [
        _row('A_L1', 'Dumbbell Hinge One', needed: ['dumbbells']),
        _row('B_L2', 'Dumbbell Hinge Two', needed: ['dumbbells'], foundational: false),
        _row('C_W', 'Bodyweight Hinge'),
      ];
      expect(_order(r, hinge, soft: {'Dumbbell Hinge One'}), ['B_L2', 'C_W', 'A_L1']);
    });

    final softCase = [
      _row('A_L1', 'Dumbbell Hinge Best', needed: ['dumbbells']),
      _row('B_L2', 'Dumbbell Hinge Iso', needed: ['dumbbells'], type: ['isolation']),
      _row('C_W', 'Bodyweight Hinge'),
    ];

    test('T10b: the best loaded row soft-avoided, the remaining loaded row matches worse: the bodyweight row is first', () {
      expect(_order(softCase, hinge, soft: {'Dumbbell Hinge Best'}).first, 'C_W');
    });

    test('T10c: the same with the best loaded row demoted', () {
      expect(_order(softCase, hinge, demoted: {'Dumbbell Hinge Best'}).first, 'C_W');
    });

    test('T11: a household-only row (towel) is not "loaded" for a user with real kit', () {
      final r = [
        _row('A_TOWEL', 'Towel Hinge', needed: ['towel'], foundational: false),
        _row('B_BW', 'Bodyweight Hinge'),
      ];
      expect(_order(r, hinge).first, 'B_BW');
    });

    test('T12: the emergency keeps the easier-gap key first (advanced user, rows core only at easier levels)', () {
      final r = [
        _row('A_GAP1', 'Dumbbell Hinge Int', needed: ['dumbbells'], levels: ['intermediate']),
        _row('B_GAP0', 'Bodyweight Hinge Adv', levels: ['advanced']),
      ];
      expect(_order(r, hinge, level: 'advanced', anyCoreLevel: true), ['B_GAP0', 'A_GAP1']);
    });

    test('T12b: under the emergency topFit is chosen inside the nearest gap, and the new key stays inside it', () {
      // topFit from the gap-1 row would push B behind the worse gap-0 loaded row F3 (review round 3).
      final r1 = [
        _row('A_F1', 'Dumbbell Upper Glute Int', needed: ['dumbbells'], focus: ['Glutes (Upper)'], levels: ['intermediate']),
        _row('B_W', 'Bodyweight Glute Adv', levels: ['advanced']),
        _row('C_F3', 'Dumbbell Glute Iso Adv', needed: ['dumbbells'], type: ['isolation'], levels: ['advanced']),
      ];
      expect(_order(r1, hingeUpper, level: 'advanced', anyCoreLevel: true), ['B_W', 'C_F3', 'A_F1']);
      final r2 = [
        _row('A_F1', 'Dumbbell Glute Int', needed: ['dumbbells'], levels: ['intermediate']),
        _row('B_W', 'Bodyweight Glute Adv', levels: ['advanced']),
        _row('C_F2', 'Dumbbell Glute Adv', needed: ['dumbbells'], foundational: false, levels: ['advanced']),
      ];
      expect(_order(r2, hinge, level: 'advanced', anyCoreLevel: true), ['C_F2', 'B_W', 'A_F1']);
    });

    test('T13: two bodyweight rows keep their order when no topFit matches as well as either', () {
      final r = [
        _row('A_W1', 'Upper Glute Bodyweight', focus: ['Glutes (Upper)'], foundational: false),
        _row('B_W2', 'Bodyweight Glute'),
        _row('C_L', 'Dumbbell Glute Iso', needed: ['dumbbells'], type: ['isolation']),
      ];
      expect(_order(r, hingeUpper), _order(r, hingeUpper, loadedWins: false));
    });

    test('T14: with no row the user can load, a foundational worst-match row keeps its place', () {
      final r = [
        _row('A_WORST', 'Bodyweight Glute Iso', type: ['isolation']),
        _row('B_BEST', 'Upper Glute Bodyweight', focus: ['Glutes (Upper)'], foundational: false),
      ];
      expect(_order(r, hingeUpper, tier: 'bodyweight'), ['A_WORST', 'B_BEST']);
    });
  });

  group('the real picker and library', () {
    const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    late Directory tempDir;
    late List<Map<String, dynamic>> shipped;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tempDir = await Directory.systemTemp.createTemp('loaded_wins');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => tempDir.path,
      );
      Hive.init(tempDir.path);
      GuardedBox.testBypassOwnership = true;
      await Hive.openBox(HiveService.configBoxName);
      await Hive.openBox(HiveService.migrationBoxName);
      await Hive.openBox(HiveService.exerciseBoxName);
      shipped = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List)
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
    }

    tearDown(() async => HiveService.instance.configBox.delete('disable_loaded_wins'));

    Set<String> namesOf(Phase p) => {
          for (final w in p.weekPlans)
            for (final d in w.workoutDays)
              for (final e in d.exercises) e.exerciseName,
        };

    Phase gen(String goal, int days, String level, String tier, int minutes, int phase) =>
        PlanGenerator.instance.generateV4(
          goal: goal,
          equipment: tier,
          daysPerWeek: days,
          phase: phase,
          experienceLevel: level,
          injuries: const [],
          bodyFocus: const [],
          sessionDuration: minutes,
          previousWeights: const {},
        );

    test('T5: the Upper-day walk lands on the next loaded row, not the bodyweight one (real pickV4)', () async {
      final chest = _slot('Mid Chest', 'horizontal_push');
      MuscleSlot s(MuscleSlot x) => x;
      await seed([
        _row('A_MCP', 'Machine Chest Press', pattern: 'horizontal_push', focus: ['Mid Chest'], needed: ['machines']),
        _row('B_PU', 'Push Up', pattern: 'horizontal_push', focus: ['Mid Chest']),
        _row('C_SMITH', 'Smith Bench Press',
            pattern: 'horizontal_push', focus: ['Mid Chest'], needed: ['smith machine', 'bench'], foundational: false),
      ]);
      List<PopulatedDay> run() => ExerciseSelector.pickV4(
            slotDays: [
              MuscleSlotDay(name: 'Chest', focus: 'chest', dayType: 'push', intensity: 'hypertrophy', slotsA: [s(chest)]),
              MuscleSlotDay(name: 'Upper', focus: 'upper', dayType: 'upper', intensity: 'hypertrophy', slotsA: [s(chest)]),
            ],
            exerciseRepo: ExerciseRepository.instance,
            equipmentTier: 'full_gym',
            effectiveExp: 'intermediate',
            phase: 1,
            goal: 'build_muscle',
            capability: _cap('full_gym'),
          );
      final on = run();
      expect(on[0].exercisesA.single.exerciseName, 'Machine Chest Press');
      expect(on[1].exercisesA.single.exerciseName, 'Smith Bench Press');
      await HiveService.instance.configBox.put('disable_loaded_wins', true);
      final off = run();
      expect(off[1].exercisesA.single.exerciseName, 'Push Up', reason: 'switch off: the pre-1B-R walk');
    });

    test('T6: a bodyweight user\'s order is unchanged for every slot of every split, phases 1-3, every level', () {
      final bw = _cap('bodyweight');
      var compared = 0;
      for (final goal in const ['build_muscle', 'lose_fat', 'general_fitness', 'strength']) {
        for (final days in const [3, 4, 5, 6]) {
          for (final level in _all) {
            for (final d in SplitResolver.selectV4(goal, days, experienceLevel: level)) {
              for (final slot in [...d.slotsA, ...?d.slotsB]) {
                for (final phase in const [1, 2, 3]) {
                  List<String> ord(bool lw) => [
                        for (final r in CoreListSelector.rankedPool(
                          rows: shipped,
                          slot: slot,
                          level: level,
                          phase: phase,
                          equipmentTier: 'bodyweight',
                          capability: bw,
                          exclusions: const {},
                          isContraindicated: (_) => false,
                          pickedNames: const {},
                          demotedNames: const {},
                          loadedWins: lw,
                        ).ordered)
                          r['id'] as String
                      ];
                  expect(ord(true), ord(false), reason: '$goal ${days}d $level p$phase ${slot.targetMuscle}');
                  compared++;
                }
              }
            }
          }
        }
      }
      expect(compared, greaterThan(1000));
    });

    test('T8: real data, the d25 and d24 cases', () async {
      await seed(shipped);
      final legs = namesOf(gen('build_muscle', 4, 'intermediate', 'home_dumbbells', 60, 2));
      expect(legs, isNot(contains('Walking Lunge')), reason: 'the isolation-typed quad slot takes a loaded row');
      final p1 = namesOf(gen('build_muscle', 4, 'beginner', 'home_dumbbells', 45, 1));
      expect(p1, isNot(contains('Single Leg Glute Bridge')), reason: 'phase-1 glute hinge is loaded');
      expect(p1, isNot(contains('Bodyweight Good Morning')));
      for (final days in const [5, 6]) {
        for (final tier in const ['home_dumbbells', 'basic_gym']) {
          for (final phase in const [1, 2]) {
            expect(namesOf(gen('build_muscle', days, 'beginner', tier, 60, phase)), isNot(contains('Towel Lateral Raise')),
                reason: '${days}d $tier p$phase: G0355 is the second loaded lateral raise (d24)');
          }
        }
      }
    });
  });
}
