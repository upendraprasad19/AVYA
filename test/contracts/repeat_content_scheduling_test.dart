// ⑧ 8-A / UNIT 2-int — repeat-content SCHEDULING, PRODUCTION behavioral test
// (account behavioral_test_path, §4.4 rule 21; SoT concept `repeat_content_scheduling`).
//
// Two layers:
//  (A) PURE `WorkoutScheduleReadService.repeatPinsFrom` — the G5 faithfulness gate
//      + the prior-phase A/B extraction, with NO Hive/clock. This is the risky new
//      logic; testing it pure makes it robust + fast. Proves: match → per-day A/B
//      pins by index; MISMATCH on any of {planGoal, equipment, daysPerWeek,
//      effectiveExp} → null (fresh) — effectiveExp is the NEW-1 catch (frames widen
//      with phase); absent baseline / empty weeks → null (crash-guard); a gap
//      day-index → empty-name entry (buildPinnedDays fresh-fills), B-only index
//      spanned (union keys).
//  (B) HIVE — `generateAndSchedule` FORWARDS `pinnedExercisesByDay` to the rows
//      (the facade-drop bug class) AND writes `last_phase_profile` ONLY when the
//      adherence-gate flag is ON (ship-dark). Uses the seeded-library + session
//      harness the 2-cap test established.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─────────────────────────── (A) PURE repeatPinsFrom ───────────────────────
  group('repeatPinsFrom (pure G5 gate + A/B extraction)', () {
    Map<String, dynamic> wRow(int idx, List<String> names) => {
          'type': 'workout',
          'workout_day_index': idx,
          'exercises': [
            for (final n in names) {'exercise_name': n}
          ],
        };
    Map<String, dynamic> restRow() =>
        {'type': 'rest', 'exercises': const <dynamic>[]};

    const stored = {
      'plan_goal': 'build_muscle',
      'equipment': 'full_gym',
      'days_per_week': 4,
      'effective_exp': 'intermediate',
    };

    Map<int, ({List<String> a, List<String> b})>? call({
      Map? storedProfile = stored,
      required List<Map<String, dynamic>> w1,
      required List<Map<String, dynamic>> w2,
      String planGoal = 'build_muscle',
      String equipment = 'full_gym',
      int days = 4,
      String effExp = 'intermediate',
    }) =>
        WorkoutScheduleReadService.repeatPinsFrom(
          stored: storedProfile,
          week1: w1,
          week2: w2,
          currentPlanGoal: planGoal,
          equipment: equipment,
          daysPerWeek: days,
          newPhaseEffectiveExp: effExp,
        );

    test('match → per-day A (week1) / B (week2) pins by index', () {
      final pins = call(
        w1: [wRow(0, ['Bench', 'Fly']), wRow(1, ['Row']), restRow()],
        w2: [wRow(0, ['Overhead', 'Lateral']), wRow(1, ['Pulldown'])],
      );
      expect(pins, isNotNull);
      expect(pins![0]!.a, ['Bench', 'Fly']);
      expect(pins[0]!.b, ['Overhead', 'Lateral']);
      expect(pins[1]!.a, ['Row']);
      expect(pins[1]!.b, ['Pulldown']);
      expect(pins.length, 2); // rest row didn't create a phantom index
    });

    test('effectiveExp MISMATCH → null (NEW-1: frames widen with phase)', () {
      expect(
          call(
            w1: [wRow(0, ['Bench'])],
            w2: [wRow(0, ['Overhead'])],
            effExp: 'advanced', // stored was intermediate → widened → fresh
          ),
          isNull);
    });

    test('planGoal / equipment / daysPerWeek MISMATCH → null', () {
      final w1 = [wRow(0, ['Bench'])];
      final w2 = [wRow(0, ['Overhead'])];
      expect(call(w1: w1, w2: w2, planGoal: 'lose_fat'), isNull);
      expect(call(w1: w1, w2: w2, equipment: 'bodyweight'), isNull);
      expect(call(w1: w1, w2: w2, days: 5), isNull);
    });

    test('absent baseline (legacy / first flip-on) → null', () {
      expect(
          call(storedProfile: null, w1: [wRow(0, ['Bench'])], w2: [wRow(0, ['O'])]),
          isNull);
    });

    test('empty / rest-only weeks → null (crash-guard, no StateError)', () {
      expect(call(w1: const [], w2: const []), isNull);
      expect(call(w1: [restRow()], w2: [restRow()]), isNull);
    });

    test('gap day-index → empty entry (fresh-fill); a B-only index is spanned', () {
      final pins = call(
        w1: [wRow(0, ['A0']), wRow(2, ['A2'])], // gap at index 1
        w2: [wRow(0, ['B0']), wRow(1, ['B1'])], // B present at index 1
      );
      expect(pins, isNotNull);
      expect(pins!.keys.toList(), [0, 1, 2]); // union spanned 0..maxIdx
      expect(pins[0]!.a, ['A0']);
      expect(pins[0]!.b, ['B0']);
      expect(pins[1]!.a, isEmpty); // gap in A → empty → buildPinnedDays fresh-fills
      expect(pins[1]!.b, ['B1']); // but B present → not dropped
      expect(pins[2]!.a, ['A2']);
      expect(pins[2]!.b, isEmpty);
    });

    test('blank exercise_name entries are filtered out', () {
      final pins = call(
        w1: [
          {
            'type': 'workout',
            'workout_day_index': 0,
            'exercises': [
              {'exercise_name': 'Bench'},
              {'exercise_name': ''},
              {'other': 'x'},
            ],
          }
        ],
        w2: [wRow(0, ['Overhead'])],
      );
      expect(pins![0]!.a, ['Bench']);
    });
  });

  // ─────────────────────── (B) HIVE — generateAndSchedule ─────────────────────
  group('generateAndSchedule repeat wiring (Hive)', () {
    const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('repeat_sched');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => tempDir.path,
      );
      Hive.init(tempDir.path);
      GuardedBox.testBypassOwnership = true;

      await Hive.openBox(HiveService.configBoxName);
      await Hive.openBox(HiveService.migrationBoxName);
      final exBox = await Hive.openBox(HiveService.exerciseBoxName);
      final rows = jsonDecode(
        File('assets/data/exercise_library.json').readAsStringSync(),
      ) as List;
      for (final r in rows.whereType<Map>()) {
        await exBox.put((r['id'] ?? r['name']).toString(),
            Map<String, dynamic>.from(r));
      }
      // Two synthetic pinnable moves so the pinned names resolve deterministically.
      Map<String, dynamic> move(String id, String name) => {
            'id': id,
            'name': name,
            'movement_pattern': 'horizontal_push',
            'exercise_type': 'compound',
            'target_focus': 'chest',
            'primary_muscles': ['Chest'],
            'equipment_tier': ['bodyweight', 'basic_gym', 'full_gym'],
            'suitable_for': ['Beginner', 'Intermediate', 'Advanced'],
            'is_foundational': true,
            'default_sets': 3,
            'default_reps': '10',
            'rep_range': '8-12',
            'equipment_needed': ['bodyweight'],
          };
      await exBox.put('rc_pin_a', move('rc_pin_a', 'RC Pin A Move'));
      await exBox.put('rc_pin_b', move('rc_pin_b', 'RC Pin B Move'));

      HiveService.instance.markInitializedForTests();
      await HiveUserSession.openForUser(testUser);
    });

    tearDownAll(() async {
      await HiveUserSession.closeAll();
      GuardedBox.testBypassOwnership = false;
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    Future<void> setFlag(bool on) async {
      final cfg = Hive.box(HiveService.configBoxName);
      if (on) {
        await cfg.put('enable_adherence_gate', true);
      } else {
        await cfg.delete('enable_adherence_gate');
      }
      await MigratedKey.delete('last_phase_profile'); // reset (userBox + configBox)
    }

    List<String> firstWorkoutNames(List<Map<String, dynamic>> week) {
      for (final r in week) {
        if (r['type'] == 'workout') {
          return ((r['exercises'] as List?) ?? const [])
              .whereType<Map>()
              .map((e) => (e['exercise_name'] as String?) ?? '')
              .toList();
        }
      }
      return const [];
    }

    test('flag ON: pinnedExercisesByDay flows to the rows (A→wk1, B→wk2) + '
        'last_phase_profile is written', () async {
      await setFlag(true);
      final svc = WorkoutScheduleReadService.instance;
      await svc.generateAndSchedule(
        goal: 'build_muscle',
        equipment: 'full_gym',
        daysPerWeek: 4,
        startDate: DateTime(2026, 3, 2), // a Monday
        experienceLevel: 'intermediate',
        phase: 1,
        pinnedExercisesByDay: {
          0: (a: ['RC Pin A Move'], b: ['RC Pin B Move']),
        },
      );
      expect(firstWorkoutNames(svc.getWeek(1)).contains('RC Pin A Move'), isTrue,
          reason: 'generateAndSchedule forwarded the pin to generate() → wk1 (A).');
      expect(firstWorkoutNames(svc.getWeek(2)).contains('RC Pin B Move'), isTrue,
          reason: 'variant B (wk2) carries the B pin — not collapsed to A.');
      final lpp = MigratedKey.read<Map>('last_phase_profile'); // user-scoped (userBox)
      expect(lpp, isA<Map>());
      expect(lpp!['plan_goal'], 'build_muscle');
      expect(lpp['equipment'], 'full_gym');
      expect(lpp['days_per_week'], 4);
      expect(lpp['effective_exp'], 'intermediate');
      await setFlag(false);
    });

    test('flag OFF: last_phase_profile is NOT written (ship-dark)', () async {
      await setFlag(false);
      final svc = WorkoutScheduleReadService.instance;
      await svc.generateAndSchedule(
        goal: 'build_muscle',
        equipment: 'full_gym',
        daysPerWeek: 4,
        startDate: DateTime(2026, 3, 9),
        experienceLevel: 'intermediate',
        phase: 1,
      );
      expect(MigratedKey.read<Map>('last_phase_profile'), isNull,
          reason: 'the config write is flag-gated → OFF ⇒ no new write.');
    });

    test('e2e via FACADE: expired prior phase + repeatContent → new phase pins the '
        'prior selection (facade thread + pre-overwrite ordering + goal mapping)',
        () async {
      await setFlag(true);
      final read = WorkoutScheduleReadService.instance;
      // Seed an EXPIRED prior phase 2 (window ~40d in the past → isPhaseExpired).
      await read.generateAndSchedule(
        goal: 'build_muscle',
        equipment: 'full_gym',
        daysPerWeek: 4,
        startDate: DateTime.now().subtract(const Duration(days: 40)),
        experienceLevel: 'intermediate',
        phase: 2,
      );
      final priorA = firstWorkoutNames(read.getWeek(1)).toSet();
      final priorB = firstWorkoutNames(read.getWeek(2)).toSet();
      expect(priorA, isNotEmpty);
      expect(read.isPhaseExpired(), isTrue,
          reason: 'the seeded window is entirely in the past');

      // Advance via the FACADE with a DIFFERENT goal token that MAPS to the same
      // planGoal (recompose → build_muscle) + repeatContent → G5 matches → pin.
      final advanced =
          await WorkoutScheduleService.instance.autoGenerateNextPhaseIfNeeded(
        goal: 'recompose',
        equipment: 'full_gym',
        daysPerWeek: 4,
        experienceLevel: 'intermediate',
        currentPhase: 2,
        repeatContent: true,
      );
      expect(advanced, isTrue);

      // getWeek now reads the NEW phase's window → it must reproduce the prior
      // selection (pin honored end-to-end) stamped phase 3.
      expect(firstWorkoutNames(read.getWeek(1)).toSet(), priorA,
          reason: 'facade forwarded repeatContent; _buildRepeatPins read the prior '
              'window BEFORE plan_start moved; recompose→build_muscle mapped → G5 '
              'matched → variant A pinned.');
      expect(firstWorkoutNames(read.getWeek(2)).toSet(), priorB,
          reason: 'variant B (wk2) pinned too.');
      final workoutRow =
          read.getWeek(1).firstWhere((r) => r['type'] == 'workout');
      expect(workoutRow['phase'], 3,
          reason: 'new rows stamped phase = currentPhase + 1');
      await setFlag(false);
    });
  });
}
