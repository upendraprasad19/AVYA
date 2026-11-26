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
/// Unit 3A (2026-11-15), re-measured on the 2E tree: the goal's lower Cut / Maintain tops leave more floor-off days
/// under 3 (thin OFF up), and every one gains rows and reaches 3 (gained = thin OFF, 0 thin ON, 0 lost, every OFF digest
/// still main's); knock-on rises with them. Founder d65 (the floor may seat a reservation-blocked slot and trims a
/// 3-set row to 2 when only a session cap refuses) closed the 8 rep30 home_dumbbells day-weeks the floor had left at 2.
/// Attribution (review round 1): with the goal training off and d65 KEPT, this file's pre-3A counts pass unchanged, so
/// d65 alone moves nothing here and every moved count is the goal training's (and with d65 reverted too, likewise).
/// Unit 3C (diagnose f3c9a6, 2026-11-16): knock-on basic_gym 52 -> 41, full_gym 35 -> 31, nothing else. Only the gym
/// tiers carry a finisher for these injured personas (the bike, 4 rounds under 60, d74 / d76), and its reserved 240 s
/// leaves fewer sets for a floor seat to knock on; thin ON 0, gained = thin OFF and the OFF digest (taken with the
/// finisher switch set) are unchanged.
/// generator-killswitch-3a3c (2026-11-17, plan §6): the 3A / 3C switches are deleted, so the pinned repeat's pins (the
/// uninjured 30-minute phase-1 plan) are generated with goal training (Cut / Maintain pins differ) and the finisher
/// unreserved (`CardioFinisher.debugReserve`). Fewer pinned days are thin with the floor off and the floor gains exactly
/// those (thin OFF = gained: 240 / 428 / 304 / 128 -> 148 / 392 / 272 / 88); more days give a set to a floor seat
/// (knock-on 55 / 66 / 41 / 31 -> 64 / 89 / 57 / 35). Thin ON 0, nothing lost, pins differ 0; the OFF digests are the
/// world recorded on 421cd2d2 (the two-tree oracle).
const _expected = <String, (int, int, int, int, int, int, int)>{
  'bodyweight': (240, 4320, 148, 148, 64, 0, 0),
  'home_dumbbells': (240, 4320, 392, 392, 89, 0, 0),
  'basic_gym': (240, 4320, 272, 272, 57, 0, 0),
  'full_gym': (240, 4320, 88, 88, 35, 0, 0),
};

void main() {
  final h = SweepHarness.install();
  final gate = DayFloorGate(h);
  for (final tier in kSweepTiers) {
    test('rep30 [$tier]: no day under 3, nothing lost vs the floor off, the invariant holds, OFF = the 421cd2d2 recording', () {
      gate.finish('rep30', tier, gate.run('rep30', tier), _expected[tier]!);
    });
  }
}
