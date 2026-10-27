// d4b8e1 — the plan generator NEVER auto-adds a user's custom exercises.
//
// Founder, web app, 2026-10-21: today's "Upper push + core" day listed 14
// exercises / 56 sets — 8 library picks + 6 of his own custom exercises
// (tuck planche, levers, L-sit, ...). Writer: personalization lever L2 in
// `ExerciseSelector._applyHistoryAdjustments` (phase >= 2) appended EVERY custom
// whose primary_muscles substring-matched any slot of the day, uncapped. L2 was
// removed; L6 (demote a lift the user swapped away from) in the same post-pass
// stays.
//
// Real Hive + the full seeded library + a user-scoped customBox, the REAL
// PlanGenerator.generateV4 at phase >= 2 (the only phases L2 ran at).
// Mutation (rule 21): re-adding the L2 append reddens (1) and (2).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late Box wb, custom;

  // Shaped like the founder's live customs: muscles that match push, pull, leg
  // and core slots, so the old L2 would have appended them to every day type.
  const customs = <String, List<String>>{
    'My Tuck Planche': ['Chest', 'Front Delts'],
    'My Elbow Lever': ['Triceps', 'Core'],
    'My Back Lever': ['Lats', 'Mid Back'],
    'My Jump Squat': ['Quads', 'Glutes'],
  };

  Phase gen({int phase = 2, String exp = 'intermediate'}) =>
      PlanGenerator.instance.generateV4(
        goal: 'build_muscle',
        equipment: 'full_gym',
        daysPerWeek: 4,
        phase: phase,
        experienceLevel: exp,
        injuries: const [],
      );

  List<String> allNames(Phase p) => [
        for (final w in p.weekPlans)
          for (final d in w.workoutDays)
            for (final e in d.exercises) e.exerciseName,
      ];

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('l2_no_custom_autoadd');
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
      final id = (r['id'] ?? r['name']).toString();
      await exBox.put(id, Map<String, dynamic>.from(r));
    }
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
    wb = HiveService.instance.workoutBox;
    custom = HiveService.instance.customBox;
  });

  tearDownAll(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await wb.clear();
    await custom.clear();
    var i = 0;
    for (final e in customs.entries) {
      await custom.put('custom_exercise_l2_${i++}', {
        'type': 'exercise',
        'name': e.key,
        'default_logging_type': 'weight_reps',
        'default_sets': 3,
        'default_reps': '10',
        'default_rest_secs': 60,
        'equipment_needed': ['bodyweight'],
        'primary_muscles': e.value,
      });
    }
  });

  test('(1) phase 2: no custom exercise appears on any day, variant A or B', () {
    final names = allNames(gen());
    expect(names, isNotEmpty);
    final leaked = names.where(customs.containsKey).toSet();
    expect(leaked, isEmpty,
        reason: 'd4b8e1: the generator must never auto-add a custom exercise; '
            'leaked: $leaked');
  });

  test('(2) later phases + advanced: still no custom exercise', () {
    for (final phase in [3, 4]) {
      final names = allNames(gen(phase: phase, exp: 'advanced'));
      final leaked = names.where(customs.containsKey).toSet();
      expect(leaked, isEmpty, reason: 'phase $phase leaked $leaked');
    }
  });

  test('(3) phase 1 stays custom-free (never ran L2, must stay so)', () {
    final leaked = allNames(gen(phase: 1)).where(customs.containsKey).toSet();
    expect(leaked, isEmpty);
  });

  test('(4) L6 still runs: a lift the user swapped away from is demoted', () async {
    // Baseline (no swap history) → pick a library lift the plan uses.
    final baseline = gen(exp: 'advanced');
    final victim = baseline.weekPlans.first.workoutDays.first.exercises.first
        .exerciseName;
    expect(customs.containsKey(victim), isFalse);

    // A coach swap 7 days ago replaced `victim` (swap_service stamps
    // swapped_via + swapped_from) → TrainingHistoryAnalyzer.demotedExercises.
    final d = istDateStr(DateTime.now().subtract(const Duration(days: 7)));
    await wb.put('schedule_$d', {
      'date': d,
      'type': 'workout',
      'status': 'completed',
      'exercises': [
        {
          'exercise_name': 'Some Replacement',
          'swapped_via': 'ai_coach',
          'swapped_from': victim,
        },
      ],
    });

    final after = gen(exp: 'advanced');
    final firstDay =
        after.weekPlans.first.workoutDays.first.exercises.map((e) => e.exerciseName);
    expect(firstDay.contains(victim), isFalse,
        reason: 'L6 (kept) must still swap a demoted lift for a same-pattern '
            'alternative — removing L2 must not disable the shared post-pass.');
    expect(allNames(after).where(customs.containsKey), isEmpty);
  });
}
