// ⑥ slice C1 — equipment-exclusions ACTIVATION behavioral test (platform
// behavioral_test_path, §4.4 rule 21). THE rule-21 artifact: it writes
// `equipment_exclusions` into `userBox['profile']`, flips the flag ON, and calls
// `PlanGenerator.generateV4` WITHOUT the `equipmentExclusions` param — so the
// central-read wiring (TrainingHistoryAnalyzer.resolveEquipmentExclusions →
// generateV4) is exercised END TO END. A unit test of the helper alone would pass
// on a reverted generateV4 seam (the ⑤ "revert-passes-every-test" trap). Uses the
// shared setUpHiveForTests helper (opens a HiveUserSession so `userBox` is real).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';
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

  // Flipped 2026-08-05 (deps-board-equipment): DEFAULT ON behind the
  // `disable_equipment_exclusions` kill-switch — "on" is now the key's ABSENCE.
  Future<void> setFlag(bool on) async {
    final cfg = Hive.box('configBox');
    if (on) {
      await cfg.delete('disable_equipment_exclusions');
    } else {
      await cfg.put('disable_equipment_exclusions', true);
    }
  }

  Future<void> setProfileExclusions(List<String>? excl) async {
    // Written through the user-scoped box the generator's central read uses.
    await HiveService.instance.userBox.put('profile', <String, dynamic>{
      'equipment_access': 'full_gym',
      if (excl != null) 'equipment_exclusions': excl,
    });
  }

  // NO `equipmentExclusions` param — the profile central-read must drive it.
  Phase gen({int phase = 1}) => PlanGenerator.instance.generateV4(
        goal: 'build_muscle',
        equipment: 'full_gym',
        daysPerWeek: 4,
        phase: phase,
        experienceLevel: 'intermediate',
      );

  Set<String> equipTokensOf(Phase p) {
    final out = <String>{};
    for (final day in p.workouts) {
      for (final ex in day.exercises) {
        out.addAll(EquipmentVocab.fromProfile(ex.equipmentNeeded));
      }
    }
    return out;
  }

  String encode(Phase p) => jsonEncode(p.toMap());

  /// ⑥ C2: the WU-2 gym-cardio gate rides the SAME `enable_equipment_exclusions`
  /// flag, so flipping it ON intentionally adds gym cardio to the gym-tier warmup +
  /// finisher (covered by wu2_gym_cardio_gate_behavioral_test). The exclusion
  /// ACTIVATION's no-op is asserted on the whole plan MINUS those two WU-2-owned
  /// fields — main selection + cooldown + structure stay byte-identical.
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

  test('ACTIVATION: profile equipment_exclusions (flag ON, NO param) drops the excluded item',
      () async {
    await setFlag(true);
    await setProfileExclusions(['cables']);
    final plan = gen();
    expect(equipTokensOf(plan).contains('cables'), isFalse,
        reason: 'the central-read wiring (profile → resolveEquipmentExclusions → '
            'generateV4) must exclude cables WITHOUT the param — reverting the seam '
            'fails here (the rule-21 guarantee).');
    expect(plan.workouts.isNotEmpty, isTrue);
    await setFlag(false);
    await setProfileExclusions(null);
  });

  // ── THE REAL USER JOURNEY (added round-1 review, 2026-08-05) ─────────────
  //
  // Round-1 review found the batch's central claim untested end-to-end. The
  // sibling flip test in equipment_exclusion_filter_behavioral_test.dart deletes
  // the config keys but passes `exclusions:` as an EXPLICIT PARAM — and per
  // training_history_analyzer.dart:174-176 an explicit param SHORT-CIRCUITS
  // before the profile read. So "default config × explicit param" was covered,
  // and "profile read × forced flag" was covered (the test above), but
  // "profile read × DEFAULT config" — the only combination a real device ever
  // runs — was covered by nothing.
  test('THE USER JOURNEY: profile exclusions honoured at the DEFAULT config '
      '(no flag key set, no param)', () async {
    final cfg = Hive.box('configBox');
    // Round-2 review: register cleanup BEFORE the assertions, so a failure at any
    // expect() below still restores shared Hive state for the sibling tests
    // instead of leaking the kill-switch into them.
    addTearDown(() async {
      await cfg.delete('disable_equipment_exclusions');
      await setProfileExclusions(null);
    });
    await cfg.delete('enable_equipment_exclusions'); // retired key
    await cfg.delete('disable_equipment_exclusions'); // kill-switch absent
    await setProfileExclusions(['cables']);

    final plan = gen(); // no param — the profile central-read must drive it

    expect(equipTokensOf(plan).contains('cables'), isFalse,
        reason: 'a user who saved "no cables" in Edit Profile, on a device with '
            'no flag key set, must not be prescribed cable work. This is the '
            'exact journey diagnose e2d6b8 describes; before the flip it failed.');
    expect(plan.workouts.isNotEmpty, isTrue,
        reason: 'honouring the exclusion must not collapse generation');

    // Negative control on the SAME journey: the kill-switch must restore the
    // pre-flip behaviour through the profile path too, not just the param path.
    await cfg.put('disable_equipment_exclusions', true);
    final killed = gen();
    expect(equipTokensOf(killed).contains('cables'), isTrue,
        reason: 'kill-switch ON must make the profile exclusion inert again');

    await cfg.delete('disable_equipment_exclusions');
    await setProfileExclusions(null);
  });

  test('flag OFF → profile exclusions IGNORED, byte-identical to no exclusions',
      () async {
    await setFlag(false);
    await setProfileExclusions(const []);
    final baseline = encode(gen());
    await setProfileExclusions(['cables', 'barbell']);
    final withExcl = encode(gen());
    expect(withExcl, baseline,
        reason: 'flag OFF → resolveEquipmentExclusions short-circuits to {} with NO '
            'profile read → byte-identical (the ship-dark guarantee).');
    await setProfileExclusions(null);
  });

  test('flag ON + empty / absent profile exclusions → no-op (byte-identical to OFF)',
      () async {
    await setFlag(true);
    await setProfileExclusions(const []);
    final onEmptyPlan = gen();
    await setProfileExclusions(null); // absent key entirely
    final onAbsentPlan = gen();
    await setFlag(false);
    await setProfileExclusions(const []);
    final offPlan = gen();
    // ⑥ C2: flag ON also fires the WU-2 gym-cardio gate (shared flag) → the gym-tier
    // warmup/finisher legitimately differ from OFF. The exclusion ACTIVATION's no-op
    // is asserted on the plan sans those two WU-2-owned fields (encodeSansWu2).
    expect(encodeSansWu2(onEmptyPlan), encodeSansWu2(offPlan));
    expect(encodeSansWu2(onAbsentPlan), encodeSansWu2(offPlan),
        reason: 'flag ON + empty/absent exclusions → {} → main selection '
            'byte-identical to OFF.');
    await setProfileExclusions(null);
  });
}
