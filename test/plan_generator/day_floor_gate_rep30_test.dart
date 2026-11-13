@Timeout(Duration(minutes: 15))
library;

// Unit 2B (OI-452, plan docs/plans/2026-11-13-generator-step2b-day-floor.md §4): the whole-engine day-floor gate,
// block `rep30`: the pinned phase-2 repeat over the pairs at 30 minutes, beginner, 3-6 days. Each persona is generated with the floor on and off; harness, assertions
// and the kill-switch digest: test/helpers/day_floor_gate_lib.dart.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/day_floor_gate_lib.dart';
import '../helpers/injury_floor_sweep_lib.dart';

/// (runs, day-weeks, thin OFF, gained, knock-on, lead + 2 OFF) per tier, measured on the 2B tree (2026-11-13). Every
/// thin OFF day-week gains rows and reaches 3; the knock-on days keep their exercises with fewer sets (pass B grows less
/// after a floor seat spent a group); lead + 2 OFF is a Unit 2A residue, identical with the floor on.
const _expected = <String, (int, int, int, int, int, int)>{
  'bodyweight': (240, 4320, 120, 120, 4, 0),
  'home_dumbbells': (240, 4320, 242, 242, 3, 0),
  'basic_gym': (240, 4320, 192, 192, 0, 0),
  'full_gym': (240, 4320, 44, 44, 0, 0),
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
