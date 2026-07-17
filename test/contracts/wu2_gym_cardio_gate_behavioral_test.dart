// ⑥ C2 (WU-2 gym-cardio gate) — behavioral test (platform behavioral_test_path,
// §4.4 rule 21). Proves the FIX for the `hasGymEquipment` always-false bug: on a
// GENERATED plan, gym users now get gym-cardio WARMUP + FINISHER variants (flag
// ON), and excluding `cardio machine` removes them; flag OFF is byte-identical
// (the always-false old predicate). Reverting the generateV4 override compute →
// flag ON falls back to the old predicate → the "gym variant offered" assertions
// go red. Uses the generateV4 Hive-boot + userBox harness (C1's activation test).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await setUpHiveForTests();
    final exBox = Hive.box('exerciseBox');
    final rows = jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List;
    for (final r in rows.whereType<Map>()) {
      final id = (r['id'] ?? r['name']).toString();
      await exBox.put(id, Map<String, dynamic>.from(r));
    }
  });

  tearDownAll(() async {
    await tearDownHiveForTests(tempDir);
  });

  Future<void> setFlag(bool on) async {
    final cfg = Hive.box('configBox');
    if (on) {
      await cfg.put('enable_equipment_exclusions', true);
    } else {
      await cfg.delete('enable_equipment_exclusions');
    }
  }

  Future<void> setProfileExclusions(List<String>? excl) async {
    await HiveService.instance.userBox.put('profile', <String, dynamic>{
      'equipment_access': 'full_gym',
      if (excl != null) 'equipment_exclusions': excl,
    });
  }

  // 5-day week so the gym-cardio pool moves (rotated by day index, surfacing at
  // index 2) appear across days (P2-4 / round-2). full_gym → the gym tier.
  Phase gen({String goal = 'build_muscle'}) => PlanGenerator.instance.generateV4(
        goal: goal,
        equipment: 'full_gym',
        daysPerWeek: 5,
        phase: 1,
        experienceLevel: 'intermediate',
      );

  // The gym-cardio warmup moves — offered only when hasGymEquipment (WU-2 fix).
  const gymWarmupMoves = {
    'Jump Rope',
    'Cycling (Stationary)',
    'Running (Treadmill)',
  };

  Set<String> warmupNamesOf(Phase p) {
    final out = <String>{};
    for (final d in p.workouts) {
      for (final w in d.warmup) {
        out.add(w.exerciseName);
      }
    }
    return out;
  }

  Set<String> finisherNamesOf(Phase p) {
    final out = <String>{};
    for (final d in p.workouts) {
      for (final f in d.finisher) {
        out.add(f.exerciseName);
      }
    }
    return out;
  }

  test('WARMUP: flag ON + full_gym → a gym-cardio move is offered; flag OFF → none',
      () async {
    await setFlag(true);
    await setProfileExclusions(const []);
    final on = warmupNamesOf(gen());
    expect(on.intersection(gymWarmupMoves).isNotEmpty, isTrue,
        reason: 'flag ON + full_gym → the WU-2 fix offers a gym-cardio warmup move '
            '(the pre-existing always-false hasGymEquipment denied it).');

    await setFlag(false);
    final off = warmupNamesOf(gen());
    expect(off.intersection(gymWarmupMoves), isEmpty,
        reason: 'flag OFF → the always-false OLD predicate → NO gym-cardio warmup '
            '(byte-identical to pre-C2).');
    await setProfileExclusions(null);
  });

  test('WARMUP: flag ON + exclude cardio machine → NO gym-cardio warmup', () async {
    await setFlag(true);
    await setProfileExclusions(['cardio machine']);
    final excl = warmupNamesOf(gen());
    expect(excl.intersection(gymWarmupMoves), isEmpty,
        reason: 'excluding cardio machine drops it from the effective equipment → '
            'hasGym false → bodyweight warmup cardio only.');
    await setFlag(false);
    await setProfileExclusions(null);
  });

  test('FINISHER (general_fitness → cycling → hasGym branch): flag ON → gym variant; '
      'exclude → bodyweight; flag OFF → bodyweight', () async {
    // general_fitness is the only ④ goal-default that hits the finisher hasGym
    // branch (→ cycling → _cyclingFinisher(hasGym)); lose_fat/recompose default to
    // bodyweight hiit/jump_rope (P2-4 / round-2).
    await setFlag(true);
    await setProfileExclusions(const []);
    final on = finisherNamesOf(gen(goal: 'general_fitness'));
    expect(on.contains('Stationary Bike Sprints'), isTrue,
        reason: 'general_fitness → cycling → _cyclingFinisher(hasGym=true) → gym variant.');

    await setProfileExclusions(['cardio machine']);
    final excl = finisherNamesOf(gen(goal: 'general_fitness'));
    expect(excl.contains('High Knees Intervals'), isTrue,
        reason: 'exclude cardio machine → hasGym false → bodyweight finisher.');
    expect(excl.contains('Stationary Bike Sprints'), isFalse);

    await setFlag(false);
    final off = finisherNamesOf(gen(goal: 'general_fitness'));
    expect(off.contains('High Knees Intervals'), isTrue,
        reason: 'flag OFF → old predicate always-false → bodyweight finisher '
            '(byte-identical to pre-C2).');
    await setProfileExclusions(null);
  });
}
