// Behavioral regression — U3 warmup/cooldown injury filter (Ship 2).
//
// This is the SOLE proof of U3: the Batch-0 scorecard scores only main
// exercises (plan.allExercises), NEVER warmup/cooldown, so it cannot move for
// this change. End-to-end through the real generator (Hive + real library).
// Asserts against SPECIFIC known moves (not the production map) to stay
// non-circular.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/warmup_cooldown.dart';

// Specific shoulder-LOADING warmup/cooldown moves (Push Up is library wrist-only
// → intentionally NOT here; it must survive a shoulder filter).
const _shoulderMoves = {
  'Dead Hang',
  'Wall Push Up',
  'Chest Doorway Stretch',
  'Cross-body Shoulder Stretch',
  'Overhead Stretch',
};
// Specific knee-LOADING warmup/cooldown moves.
const _kneeMoves = {
  'High Knees',
  'Baithak (Hindu Squat)',
  'Jump Rope',
  'Spot Jogging',
  'Jumping Jacks',
  'Standing Quad Stretch',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_warmup_injury');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    for (final name in [
      HiveService.exerciseBoxName,
      HiveService.configBoxName,
      HiveService.migrationBoxName,
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    final lib = jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List;
    for (final e in lib) {
      final m = Map<String, dynamic>.from(e as Map);
      await exBox.put(m['id'], m);
    }
    HiveService.instance.markInitializedForTests();
  });

  Phase gen({required List<String> injuries}) =>
      PlanGenerator.instance.generate(
        goal: 'build_muscle',
        equipment: 'full_gym',
        daysPerWeek: 4,
        phase: 1,
        experienceLevel: 'advanced',
        injuries: injuries,
      );

  Set<String> warmupCooldownNames(Phase phase) => {
        for (final wp in phase.weekPlans)
          for (final d in wp.workoutDays) ...[
            ...d.warmup.map((e) => e.exerciseName),
            ...d.cooldown.map((e) => e.exerciseName),
          ],
      };

  test('uninjured plan CONTAINS shoulder+knee moves (non-vacuity baseline)', () {
    final names = warmupCooldownNames(gen(injuries: const []));
    expect(names.intersection(_shoulderMoves), isNotEmpty,
        reason: 'baseline must contain shoulder-loading warmup/cooldown moves, '
            'else the shoulder test below is vacuous');
    expect(names.intersection(_kneeMoves), isNotEmpty);
  });

  test('shoulder injury DROPS shoulder-loading warmup/cooldown moves (U3)', () {
    final names = warmupCooldownNames(gen(injuries: const ['shoulder']));
    expect(names.intersection(_shoulderMoves), isEmpty,
        reason: 'no shoulder-loading warmup/cooldown move for a shoulder injury');
    // Push Up is library wrist-only (main-selectable) → must STAY (consistent
    // with the main cascade, which also keeps it for a shoulder injury).
    expect(names, contains('Push Up'),
        reason: 'Push Up (library wrist-only) must not be dropped for shoulder — '
            'main+warmup stay consistent');
  });

  test('knee injury DROPS knee-loading warmup/cooldown moves (U3)', () {
    final names = warmupCooldownNames(gen(injuries: const ['knee']));
    expect(names.intersection(_kneeMoves), isEmpty,
        reason: 'no knee-loading warmup/cooldown move for a knee injury');
  });

  test('irrelevant injury (wrist) leaves knee/leg moves untouched', () {
    final names = warmupCooldownNames(gen(injuries: const ['wrist']));
    // A wrist injury must not drop leg/knee moves.
    final base = warmupCooldownNames(gen(injuries: const []));
    expect(names.intersection(_kneeMoves), base.intersection(_kneeMoves),
        reason: 'a wrist injury must not affect knee-loading moves');
  });

  test('multi-injury never empties any day warmup or cooldown (floor)', () {
    final phase = gen(injuries: const [
      'knee', 'hip', 'ankle', 'hamstring', 'lower_back', 'shoulder', 'wrist',
    ]);
    for (final wp in phase.weekPlans) {
      for (final d in wp.workoutDays) {
        expect(d.warmup, isNotEmpty,
            reason: 'warmup floor: ${d.name} emptied under multi-injury');
        expect(d.cooldown, isNotEmpty,
            reason: 'cooldown floor: ${d.name} emptied under multi-injury');
      }
    }
  });

  test('drift guard: every emittable fixed move has an injury mapping', () {
    // A move added to a warmup/cooldown/cardio list without a _moveInjuries
    // entry would silently bypass the filter (unfilterable = a safety hole).
    final unmapped = WarmupCooldownSelector.allFixedMoves
        .difference(WarmupCooldownSelector.mappedMoves);
    expect(unmapped, isEmpty,
        reason: 'these emittable warmup/cooldown moves have no _moveInjuries '
            'entry (add one, {} if genuinely safe): $unmapped');
  });

  test('kill-switch OFF → shoulder moves reappear (non-vacuity of the filter)',
      () async {
    await HiveService.instance.configBox
        .put('disable_warmup_injury_filter', true);
    final names = warmupCooldownNames(gen(injuries: const ['shoulder']));
    expect(names.intersection(_shoulderMoves), isNotEmpty,
        reason: 'filter disabled → warmup/cooldown revert to unfiltered');
  });
}
