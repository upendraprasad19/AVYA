@Timeout(Duration(minutes: 15))
library;

// Unit 2B (OI-452, plan docs/plans/2026-11-13-generator-step2b-day-floor.md §4): the whole-engine day-floor gate,
// block `pairs_p1`: the 15 pairs x 4 goals x 3 levels x 3-6 days, phase 1, 60 minutes. Each persona is generated with the floor on and off; harness, assertions
// and the kill-switch digest: test/helpers/day_floor_gate_lib.dart.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/day_floor_gate_lib.dart';
import '../helpers/injury_floor_sweep_lib.dart';

/// (runs, day-weeks, thin OFF, gained, knock-on, lead + 2 OFF) per tier, measured on the 2B tree (2026-11-13). Every
/// thin OFF day-week gains rows and reaches 3; the knock-on days keep their exercises with fewer sets (pass B grows less
/// after a floor seat spent a group); lead + 2 OFF is a Unit 2A residue, identical with the floor on.
const _expected = <String, (int, int, int, int, int, int)>{
  'bodyweight': (720, 12960, 0, 0, 0, 0),
  'home_dumbbells': (720, 12960, 40, 40, 0, 9),
  'basic_gym': (720, 12960, 60, 60, 0, 0),
  'full_gym': (720, 12960, 40, 40, 0, 0),
};

void main() {
  final h = SweepHarness.install();
  final gate = DayFloorGate(h);
  for (final tier in kSweepTiers) {
    test('pairs_p1 [$tier]: no day under 3, nothing lost vs the floor off, the invariant holds, OFF = main', () {
      gate.finish('pairs_p1', tier, gate.run('pairs_p1', tier), _expected[tier]!);
    });
  }
}
