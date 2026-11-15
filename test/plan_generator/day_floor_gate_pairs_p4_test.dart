@Timeout(Duration(minutes: 15))
library;

// Unit 2B (OI-452, plan docs/plans/2026-11-13-generator-step2b-day-floor.md §4): the whole-engine day-floor gate,
// block `pairs_p4`: the same pairs at phase 4, a lighter phase (d31). Each persona is generated with the floor on and off; harness, assertions
// and the kill-switch digest: test/helpers/day_floor_gate_lib.dart.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/day_floor_gate_lib.dart';
import '../helpers/injury_floor_sweep_lib.dart';

/// (runs, day-weeks, thin OFF, gained, knock-on, lead + 2 OFF, 2C-b swaps) per tier, measured on the 2B tree (2026-11-13). Every
/// thin OFF day-week gains rows and reaches 3; the knock-on days keep their exercises with fewer sets (pass B grows less
/// after a floor seat spent a group); lead + 2 OFF is a Unit 2A residue, identical with the floor on.
/// Unit 2C-a (2026-11-14), traced per persona: every moved count is a shoulder + elbow build_muscle plan. The
/// balanced 5-day's Push, Pull and Upper days (the default 5-day's, which the other goals already use) are thin with the
/// floor off for that injury; before, the body-part split's Shoulders + Arms day was (and, at phase 4, a 4-day Pull day
/// that the balanced 4-day no longer has). Gained = thin in every tier: the floor seats each one, no day ends under 3.
/// Thin OFF: home_dumbbells 40 -> 48, basic_gym 90 -> 88 (4 new, 6 gone), full_gym 48 -> 52.
/// Unit 2C-b (2026-11-15): 2C-b swaps bodyweight 4, home_dumbbells 6: a weekly-minimum target the walk
/// moved ahead takes the row of a group the week still trains, with the same row count (diagnose e9b3d7). For example,
/// knee + lower_back strength 3-day: Bench Dips (Triceps) for Pike Push Up, Dumbbell Alternate Bicep Curl (Biceps) for
/// Dumbbell Rear Lateral Raise (Shoulders stay credited elsewhere that week).
/// Unit 3A (2026-11-15), re-measured on the 2E tree: the goal's lower Cut / Maintain tops leave more floor-off days
/// under 3 (thin OFF up), and every one gains rows and reaches 3 (gained = thin OFF, 0 thin ON, 0 lost, every OFF digest
/// still main's); knock-on rises with them. Founder d65 (the floor may seat a reservation-blocked slot and trims a
/// 3-set row to 2 when only a session cap refuses) closed the 8 rep30 home_dumbbells day-weeks the floor had left at 2.
/// With the goal training off and d65 reverted, the pre-3A counts measured back exactly.
const _expected = <String, (int, int, int, int, int, int, int)>{
  'bodyweight': (720, 12960, 28, 28, 6, 0, 4),
  'home_dumbbells': (720, 12960, 188, 188, 27, 0, 6),
  'basic_gym': (720, 12960, 164, 164, 24, 0, 0),
  'full_gym': (720, 12960, 128, 128, 30, 0, 0),
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
