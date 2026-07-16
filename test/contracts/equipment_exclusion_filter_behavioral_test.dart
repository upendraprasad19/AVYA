// ⑥ slice B1 — equipment item-level EXCLUSION filter, PRODUCTION behavioral test
// (platform behavioral_test_path, §4.4 rule 21).
//
// Builds the generateV4 Hive-boot harness the sibling ship-dark tests lacked
// (physique_focus_bringup_test.dart:48 "No generateV4 Hive-boot harness exists"):
// seed the FULL library into exerciseBox, flip the flag in configBox, call the
// REAL PlanGenerator.instance.generateV4 — so the flag-read + EquipmentVocab
// normalize + floor-sanitize + the queryV4/att5/L2 drops are all exercised end
// to end, not on source-grep confidence.
//
// Proves: (1) NO-OP — flag OFF, or ON+empty, is BYTE-IDENTICAL to no exclusions
// (the ship-dark guarantee that closes the rejected-intersection 41-regression);
// (2) exclude 'cables' @ full_gym → no selected exercise requires cables;
// (3) exclude EVERYTHING → a valid bodyweight plan still fills every slot AND no
// selected exercise requires an excluded item (the att5 floor holds); (4) a
// bare-String / un-normalized community exerciseBox row is excluded correctly and
// never crashes (the e9d1c7 read class).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/exercise_selector.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  // The 11 non-bodyweight canonical tokens — an "exclude everything" set. `none`
  // and `bodyweight` are NOT excludable (floor-sanitize strips them anyway).
  const excludeEverything = <String>[
    'dumbbells', 'barbell', 'bench', 'pull-up bar', 'cables', 'machines',
    'smith machine', 'resistance band', 'kettlebell', 'ez-bar', 'cardio machine',
  ];

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('eq_excl_behavioral');
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

    // Seed the FULL bundled library (the same asset the app seeds), so generateV4
    // produces a realistic plan across every movement pattern.
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
      await cfg.put('enable_equipment_exclusions', true);
    } else {
      await cfg.delete('enable_equipment_exclusions');
    }
  }

  Phase gen({
    String equipment = 'full_gym',
    List<String> exclusions = const [],
    int phase = 1,
  }) =>
      PlanGenerator.instance.generateV4(
        goal: 'build_muscle',
        equipment: equipment,
        daysPerWeek: 4,
        phase: phase,
        experienceLevel: 'intermediate',
        equipmentExclusions: exclusions,
      );

  String encode(Phase p) => jsonEncode(p.toMap());

  /// Every canonical equipment token required by any exercise in the plan.
  Set<String> equipTokensOf(Phase p) {
    final out = <String>{};
    for (final day in p.workouts) {
      for (final ex in day.exercises) {
        out.addAll(EquipmentVocab.fromProfile(ex.equipmentNeeded));
      }
    }
    return out;
  }

  int exerciseCount(Phase p) =>
      p.workouts.fold(0, (n, d) => n + d.exercises.length);

  test('NO-OP: flag OFF ignores exclusions; flag ON + empty == baseline (byte-identical)',
      () async {
    await setFlag(false);
    final baseline = encode(gen(exclusions: const []));
    final offWithExclusions = encode(gen(exclusions: const ['cables', 'barbell']));
    expect(offWithExclusions, baseline,
        reason: 'flag OFF → exclusions threaded as {} → byte-identical to today '
            '(the ship-dark guarantee).');

    await setFlag(true);
    final onEmpty = encode(gen(exclusions: const []));
    expect(onEmpty, baseline,
        reason: 'flag ON but nothing excluded → the .isNotEmpty guards keep it '
            'byte-identical (empty-set is the no-op signal, not just the flag).');
    await setFlag(false);
    // (B-pass P2-3) The phase≥2-only L2 custom-append + L6 demote-swap use the
    // SAME `if (exclusions.isNotEmpty)` guard, so their inertness under `{}` is
    // trivially guard-covered (verified by inspection + the B-pass); a phase≥2
    // byte-identical harness would need the full history/customBox Hive stack for
    // no additional coverage of the guard itself.
  });

  test('exclude cables @ full_gym (flag ON): no selected exercise requires cables',
      () async {
    await setFlag(true);
    final plan = gen(exclusions: const ['cables']);
    expect(equipTokensOf(plan).contains('cables'), isFalse,
        reason: 'a cables-excluding user must never be prescribed a cables '
            'exercise (the pure-exclusion drop, all pick paths).');
    expect(exerciseCount(plan), greaterThan(0));
    await setFlag(false);
  });

  test('exclude EVERYTHING (flag ON): valid bodyweight plan, no excluded equipment',
      () async {
    await setFlag(true);
    final baselineCount = exerciseCount(gen(exclusions: const []));
    await setFlag(true);
    final plan = gen(exclusions: excludeEverything);
    // A VALID bodyweight plan is still produced. It is not necessarily the SAME
    // count as the baseline: a movement pattern with only ONE distinct bodyweight
    // move (e.g. vertical_pull → Inverted Row) cannot fill a SECOND same-pattern
    // slot with a DISTINCT move, so that slot is safely OMITTED (fewer-but-safe,
    // exactly like the injury filter) rather than duplicated. The floor guarantee
    // is a non-trivial plan, not a full count — assert the bulk still fills.
    expect(exerciseCount(plan), greaterThanOrEqualTo((baselineCount * 0.8).floor()),
        reason: 'the att5 bodyweight floor keeps the plan substantially full under '
            'exclude-everything (only single-floor same-pattern 2nd slots omit); a '
            'collapse to near-zero would mean the floor failed.');
    // THE safety guarantee: no selected exercise requires an excluded item — only
    // bodyweight survives at every pick path (incl. the att5 pool skip).
    final excl = excludeEverything.toSet();
    expect(equipTokensOf(plan).intersection(excl), isEmpty,
        reason: 'exclude-everything → only pure-bodyweight moves survive at every '
            'pick path (incl. the att5 pool skip: Inverted Row, not Pull Up).');
    await setFlag(false);
  });

  test('community bare-String / un-normalized row: excluded correctly, never crashes',
      () async {
    // Inject an un-normalized community-shaped row (bare String equipment_needed,
    // pre-B2-normalize) — the fromProfile read must (a) not crash and (b) still
    // exclude it when the user excludes its canonical equipment.
    final exBox = Hive.box(HiveService.exerciseBoxName);
    await exBox.put('community_test_row', {
      'id': 'community_test_row',
      'name': 'Community Cable Move',
      'movement_pattern': 'horizontal_pull',
      'exercise_type': 'isolation',
      'target_focus': 'lats',
      'primary_muscles': ['Lats'],
      'equipment_tier': ['full_gym'],
      'suitable_for': ['Beginner', 'Intermediate', 'Advanced'],
      'is_foundational': true,
      'default_sets': 3,
      'default_reps': '12',
      'rep_range': '10-15',
      'equipment_needed': 'Cable Machine', // BARE STRING + un-normalized casing
    });
    addTearDown(() => exBox.delete('community_test_row'));

    await setFlag(true);
    // Must not throw (the e9d1c7 crash class) and must exclude the community row.
    late Phase plan;
    expect(() => plan = gen(exclusions: const ['cables']), returnsNormally,
        reason: 'fromProfile reads a bare-String/community equipment_needed '
            'crash-safe (never `as List`).');
    final names = <String>{};
    for (final d in plan.workouts) {
      for (final ex in d.exercises) {
        names.add(ex.exerciseName);
      }
    }
    expect(names.contains('Community Cable Move'), isFalse,
        reason: 'the un-normalized community row ["Cable Machine"] normalizes to '
            'cables on read and is excluded — B1 is correct before B2.');
    await setFlag(false);
  });

  test('att5 FLOOR INVARIANT: every universalPoolV4 pattern retains a bodyweight '
      'survivor under exclude-everything (B-pass P2-1)', () {
    // The att5 skip's "never empties a slot" guarantee is a property of the pool
    // DATA + library tags, NOT of floor-sanitize. vertical_pull + elbow_flexion
    // survive ONLY via Inverted Row (equipment_needed:['bodyweight']) today —
    // this pins the invariant so a retag/removal of a pool floor move red-flags
    // here instead of silently dropping a bodyweight-only user's slots.
    final rows = jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List;
    final eqByName = <String, dynamic>{};
    for (final r in rows.whereType<Map>()) {
      eqByName[(r['name'] as String).toLowerCase()] = r['equipment_needed'];
    }
    bool survives(String name) {
      final eq = eqByName[name.toLowerCase()];
      if (eq == null) return true; // not in library → placeholder = bodyweight
      final canon = EquipmentVocab.fromProfile(eq).toSet();
      return canon.isEmpty || canon.every((t) => t == 'bodyweight');
    }
    final patternsWithoutSurvivor = <String>[];
    ExerciseSelector.universalPoolV4.forEach((pattern, pool) {
      if (!pool.any(survives)) patternsWithoutSurvivor.add(pattern);
    });
    expect(patternsWithoutSurvivor, isEmpty,
        reason: 'every universalPoolV4 pattern must retain ≥1 bodyweight-surviving '
            'pool move so the att5 exclusion skip never empties a slot. '
            'Offenders: $patternsWithoutSurvivor');
  });
}
