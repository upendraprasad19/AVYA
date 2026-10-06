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

  // Flipped 2026-08-05 (deps-board-equipment): the flag is now DEFAULT ON behind
  // the `disable_equipment_exclusions` kill-switch, so "on" is the ABSENCE of the
  // key and "off" is the explicit kill. Only this helper inverts — every caller's
  // setFlag(true)/setFlag(false) still means exactly what it says.
  Future<void> setFlag(bool on) async {
    final cfg = Hive.box(HiveService.configBoxName);
    if (on) {
      await cfg.delete('disable_equipment_exclusions');
    } else {
      await cfg.put('disable_equipment_exclusions', true);
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

  /// ⑥ C2: the WU-2 gym-cardio gate rides the SAME `enable_equipment_exclusions`
  /// flag, so flipping the flag ON intentionally adds gym cardio to the gym-tier
  /// warmup + finisher (verified by wu2_gym_cardio_gate_behavioral_test). This
  /// test proves the EXCLUSION FILTER's no-op, so it asserts byte-identity on the
  /// whole plan MINUS those two WU-2-owned fields (main selection + cooldown +
  /// structure — everything the exclusion filter can touch — stay byte-identical).
  String encodeSansWu2(Phase p) {
    final m = p.toMap();
    void strip(Map day) => day
      ..remove('warmup')
      ..remove('finisher');
    // Phase.toMap carries the days TWICE: the week-1 `workouts` compat list AND
    // the full `week_plans[].workout_days[]` — strip both.
    for (final w in (m['workouts'] as List)) {
      strip(w as Map);
    }
    for (final wk in (m['week_plans'] as List)) {
      for (final d in ((wk as Map)['workout_days'] as List)) {
        strip(d as Map);
      }
    }
    return jsonEncode(m);
  }

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
    final basePlan = gen(exclusions: const []);
    final baseline = encode(basePlan);
    final offWithExclusions = encode(gen(exclusions: const ['cables', 'barbell']));
    expect(offWithExclusions, baseline,
        reason: 'flag OFF → exclusions threaded as {} → byte-identical to today '
            '(the ship-dark guarantee).');

    await setFlag(true);
    final onEmptyPlan = gen(exclusions: const []);
    // ⑥ C2: flag ON also fires the WU-2 gym-cardio gate (shared flag), which adds
    // gym cardio to the gym-tier warmup/finisher — so full-plan byte-identity no
    // longer holds. The EXCLUSION FILTER's no-op is asserted on the plan sans those
    // two WU-2-owned fields (encodeSansWu2 docstring).
    expect(encodeSansWu2(onEmptyPlan), encodeSansWu2(basePlan),
        reason: 'flag ON but nothing excluded → the .isNotEmpty guards keep the main '
            'selection byte-identical (empty-set is the no-op signal, not the flag).');
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

  // ── THE FLIP TEST (2026-08-05, deps-board-equipment) ──────────────────────
  //
  // Every other test in this file drives the flag EXPLICITLY via setFlag(), so
  // every one of them passes both before and after the flip — none of them can
  // detect which way the DEFAULT points. That is the whole gap this test closes:
  // it asserts behaviour with NO config key present at all, which is the state a
  // real user's device is in. It FAILS on the pre-flip code (default OFF ⇒ the
  // exclusion is ignored ⇒ cables are prescribed) and PASSES after.
  //
  // This is the live broken promise being closed: edit_profile_screen.dart:1686
  // already writes `equipment_exclusions` and sync_profile.dart:200 already syncs
  // it, so before the flip a user could save "I have no cables" and still be
  // prescribed cable work.
  test('DEFAULT (no config key at all): exclusions are HONOURED — the flip',
      () async {
    final cfg = Hive.box(HiveService.configBoxName);
    // Pristine: neither the retired `enable_` key nor the new kill-switch.
    await cfg.delete('enable_equipment_exclusions');
    await cfg.delete('disable_equipment_exclusions');

    final plan = gen(exclusions: const ['cables']);
    expect(equipTokensOf(plan).contains('cables'), isFalse,
        reason: 'with NO flag key set — the state of every real install — a user '
            'who excluded cables must not be prescribed cable work. Before the '
            '2026-08-05 flip this failed: the default was OFF, so the profile '
            'field was collected, synced, and then silently ignored.');
    expect(exerciseCount(plan), greaterThan(0),
        reason: 'the plan must still be non-trivial; honouring an exclusion must '
            'not collapse generation.');

    // NEGATIVE CONTROL: the kill-switch still reverts to the pre-flip path, so
    // §4.6\'s "old path preserved and reachable" holds. Without this half, the
    // test above could pass for a build that had simply deleted the flag.
    await cfg.put('disable_equipment_exclusions', true);
    final killed = gen(exclusions: const ['cables']);
    expect(equipTokensOf(killed).contains('cables'), isTrue,
        reason: 'kill-switch ON must restore the verbatim pre-flip behaviour '
            '(exclusions ignored). If this ever fails, the kill-switch is dead '
            'and the flip is no longer revertible.');

    await cfg.delete('disable_equipment_exclusions');
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
