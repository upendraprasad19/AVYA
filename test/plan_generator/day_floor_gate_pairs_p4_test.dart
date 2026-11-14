@Timeout(Duration(minutes: 15))
library;

// Unit 2B (OI-452, plan docs/plans/2026-11-13-generator-step2b-day-floor.md §4): the whole-engine day-floor gate,
// block `pairs_p4`: the same pairs at phase 4, a lighter phase (d31). Each persona is generated with the floor on and off; harness, assertions
// and the kill-switch digest: test/helpers/day_floor_gate_lib.dart.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/day_floor_gate_lib.dart';
import '../helpers/injury_floor_sweep_lib.dart';

/// (runs, day-weeks, thin OFF, gained, knock-on, lead + 2 OFF) per tier, measured on the 2B tree (2026-11-13). Every
/// thin OFF day-week gains rows and reaches 3; the knock-on days keep their exercises with fewer sets (pass B grows less
/// after a floor seat spent a group); lead + 2 OFF is a Unit 2A residue, identical with the floor on.
/// Unit 2C-a (2026-11-14), traced per persona: every moved count is a shoulder + elbow build_muscle plan. The
/// balanced 5-day's Push, Pull and Upper days (the default 5-day's, which the other goals already use) are thin with the
/// floor off for that injury; before, the body-part split's Shoulders + Arms day was (and, at phase 4, a 4-day Pull day
/// that the balanced 4-day no longer has). Gained = thin in every tier: the floor seats each one, no day ends under 3.
/// Thin OFF: home_dumbbells 40 -> 48, basic_gym 90 -> 88 (4 new, 6 gone), full_gym 48 -> 52.
const _expected = <String, (int, int, int, int, int, int)>{
  'bodyweight': (720, 12960, 0, 0, 0, 0),
  'home_dumbbells': (720, 12960, 48, 48, 0, 0),
  'basic_gym': (720, 12960, 88, 88, 0, 0),
  'full_gym': (720, 12960, 52, 52, 0, 0),
};

void main() {
  final h = SweepHarness.install();
  final gate = DayFloorGate(h);
  for (final tier in kSweepTiers) {
    test('pairs_p4 [$tier]: no day under 3, nothing lost vs the floor off, the invariant holds, OFF = main', () {
      gate.finish('pairs_p4', tier, gate.run('pairs_p4', tier), _expected[tier]!);
    });
  }
}
