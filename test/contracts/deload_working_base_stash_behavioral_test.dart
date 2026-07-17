// ⑥ 7-B-1 (W2.4): deload-week working-base STASH — production behavioral test
// (platform behavioral_test_path, §4.4 rule 21). Runs the REAL generateV4 FULL
// pipeline — including the superset pairer (stage 6, AFTER periodization) — NOT
// periodization in isolation. This is the N1 linchpin: the peak-equivalent
// working_sets/working_reps stashed on the deload week (weekIdx 3) MUST survive
// the superset pairer's `copyWith(supersetGroup:)` (the `?? this.workingSets`
// idiom on the new fields). A stash lost here would ship broken with green unit
// tests. Flag `enable_triggered_deload` (ship-dark DEFAULT OFF).
//
// Proves: (1) flag OFF → NO working_sets on any exercise + `toMap` omits the key
// (byte-identical); (2) flag ON → EVERY week-4 exercise carries working_sets/reps
// (so the pairer wiped none — N1) with working_sets >= the deload sets, and at
// least one strictly greater (it's the PEAK value, not a copy of the deload cut);
// (3) the persona actually PAIRS ≥1 wk-4 exercise (N1 non-vacuous) and each paired
// one keeps its stash; (4) only week 4 stashes (weeks 1-3 clean).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('deload_stash');
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
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> setFlag(bool on) async {
    final cfg = Hive.box(HiveService.configBoxName);
    if (on) {
      await cfg.put('enable_triggered_deload', true);
    } else {
      await cfg.delete('enable_triggered_deload');
    }
  }

  Phase gen() => PlanGenerator.instance.generateV4(
        goal: 'build_muscle',
        equipment: 'full_gym',
        daysPerWeek: 4,
        phase: 1,
        experienceLevel: 'intermediate',
      );

  List<PlannedExercise> weekEx(Phase p, int weekIdx) =>
      [for (final d in p.weekPlans[weekIdx].workoutDays) ...d.exercises];

  test('flag OFF → NO working_sets anywhere + toMap omits the key (byte-identical)',
      () async {
    await setFlag(false);
    final p = gen();
    for (int w = 0; w < 4; w++) {
      for (final ex in weekEx(p, w)) {
        expect(ex.workingSets, isNull, reason: 'wk${w + 1} ${ex.exerciseName}');
        expect(ex.workingReps, isNull);
      }
    }
    expect(jsonEncode(p.toMap()).contains('working_sets'), isFalse);
  });

  test('flag ON → EVERY wk-4 exercise carries the stash (N1: pairer wiped none)',
      () async {
    await setFlag(true);
    final p = gen();
    final wk4 = weekEx(p, 3); // weekIdx 3 = deload
    expect(wk4, isNotEmpty);
    for (final ex in wk4) {
      expect(ex.workingSets, isNotNull,
          reason: 'wk4 ${ex.exerciseName} lost its stash (superset-pairer wipe?)');
      expect(ex.workingReps, isNotNull);
      expect(ex.workingSets!, greaterThanOrEqualTo(ex.sets),
          reason:
              'wk4 ${ex.exerciseName} working(${ex.workingSets}) < deload(${ex.sets})');
    }
    // Peak strictly exceeds the deload cut somewhere → it's the PEAK value, not a
    // copy of the deloaded sets.
    expect(wk4.any((e) => e.workingSets! > e.sets), isTrue,
        reason: 'no wk4 exercise has working > deload — stash is not the peak value');
  });

  test('flag ON → N1 non-vacuous: ≥1 superset-paired wk-4 exercise, all keep the stash',
      () async {
    await setFlag(true);
    final p = gen();
    final paired =
        weekEx(p, 3).where((e) => e.supersetGroup != null).toList();
    expect(paired, isNotEmpty,
        reason:
            'persona produced no wk-4 supersets → the N1 pairer-wipe path is not '
            'exercised; pick a superset-producing persona.');
    for (final ex in paired) {
      expect(ex.workingSets, isNotNull,
          reason: 'paired wk4 ${ex.exerciseName} lost its stash');
    }
  });

  test('flag ON → only week 4 stashes (weeks 1-3 clean)', () async {
    await setFlag(true);
    final p = gen();
    for (final w in [0, 1, 2]) {
      for (final ex in weekEx(p, w)) {
        expect(ex.workingSets, isNull, reason: 'wk${w + 1} should NOT stash');
      }
    }
  });

  // B-pass F1: the stash uses `ex` (the wk-4 exercise), so it is variant-agnostic
  // — a 6-day plan's wk4 = variant A (vs the 4-day persona's variant B). Confirm
  // the stash still applies + peak >= deload on the variant-A path.
  test('flag ON → variant-agnostic: 6-day plan (wk4 = variant A) also stashes',
      () async {
    await setFlag(true);
    final p = PlanGenerator.instance.generateV4(
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 6,
      phase: 1,
      experienceLevel: 'advanced',
    );
    final wk4 = weekEx(p, 3);
    expect(wk4, isNotEmpty);
    for (final ex in wk4) {
      expect(ex.workingSets, isNotNull,
          reason: '6-day wk4 ${ex.exerciseName} lost its stash');
      expect(ex.workingReps, isNotNull);
      expect(ex.workingSets!, greaterThanOrEqualTo(ex.sets));
    }
  });
}
