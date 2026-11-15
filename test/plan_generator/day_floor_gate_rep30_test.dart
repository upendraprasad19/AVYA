@Timeout(Duration(minutes: 15))
library;

// Unit 2B (OI-452, plan docs/plans/2026-11-13-generator-step2b-day-floor.md §4): the whole-engine day-floor gate,
// block `rep30`: the pinned phase-2 repeat over the pairs at 30 minutes, beginner, 3-6 days. Each persona is generated with the floor on and off; harness, assertions
// and the kill-switch digest: test/helpers/day_floor_gate_lib.dart.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/day_floor_gate_lib.dart';
import '../helpers/injury_floor_sweep_lib.dart';

/// (runs, day-weeks, thin OFF, gained, knock-on, lead + 2 OFF, 2C-b swaps) per tier, measured on the 2B tree
/// (2026-11-13) and re-measured on the 2C-b tree (2026-11-15). Every thin OFF day-week gains rows and reaches 3; the
/// knock-on days keep their exercises with fewer sets (pass B grows less after a floor seat spent a group); lead + 2 OFF
/// is a Unit 2A residue, identical with the floor on. Unit 2C-b moved knock-on 4 / 3 / 0 / 0 -> 40 / 30 / 48 / 21: the
/// ON run takes the under-60 allowance, whose 285 s replaces the count floor's 300 s forcing bound (never stacked,
/// founder d47), so a day the floor-off world forced past its budget can hold fewer sets (diagnose e9b3d7, CI round 1).
/// No 2C-b swap at 30 minutes: the row cap holds R's rows.
const _expected = <String, (int, int, int, int, int, int, int)>{
  'bodyweight': (240, 4320, 120, 120, 40, 0, 0),
  'home_dumbbells': (240, 4320, 242, 242, 30, 0, 0),
  'basic_gym': (240, 4320, 192, 192, 48, 0, 0),
  'full_gym': (240, 4320, 44, 44, 21, 0, 0),
};

void main() {
  final h = SweepHarness.install();
  final gate = DayFloorGate(h);
  for (final tier in kSweepTiers) {
    test('rep30 [$tier]: no day under 3, nothing lost vs the floor off, the invariant holds, OFF = main', () {
      gate.finish('rep30', tier, gate.run('rep30', tier), _expected[tier]!);
    });
  }
}
