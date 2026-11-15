@Timeout(Duration(minutes: 20))
library;

// Unit 2D (OI-453, plan docs/plans/2026-11-15-generator-step2d-repeat-minutes.md §3): a repeat phase at more minutes
// keeps every pinned row with its sets in all four weeks and appends only library isolations, within the level's
// exercise count and the plain day budget. Harness and assertions: test/helpers/repeat_minutes_gate_lib.dart.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/injury_floor_sweep_lib.dart';
import '../helpers/repeat_minutes_gate_lib.dart';

/// (personas, fresh, measured, gained, extra rows, extra sets, extra seconds) per 'm1->m2|tier', measured on the 2D
/// tree (2026-11-15). Pinned exactly: a change in reach is a change to review.
const _expected = <String, (int, int, int, int, int, int, int)>{
  // Unit 2E (2026-11-15): three blocks re-pinned. Phase 1 at 30 minutes now holds the arm row in its arm-residue plans,
  // so the repeat pins it and has one fewer isolation left to append. With the 2E seam off
  // (`SessionSetAllocator.debugArmSwap`) the three blocks measured exactly the 2D values: 30->45 bodyweight
  // (48, 0, 48, 41, 128, 358, 25223), 30->60 bodyweight (48, 7, 41, 41, 350, 997, 68916), 30->60 home_dumbbells
  // (48, 7, 41, 41, 305, 920, 57902). 0 invariant failures either way.
  '30->45|bodyweight': (48, 0, 48, 39, 126, 352, 24417),
  '30->45|home_dumbbells': (48, 0, 48, 33, 119, 336, 20168),
  '30->45|basic_gym': (48, 0, 48, 25, 75, 220, 13381),
  '30->45|full_gym': (48, 0, 48, 30, 84, 250, 14701),
  '30->60|bodyweight': (48, 7, 41, 41, 348, 991, 68109),
  '30->60|home_dumbbells': (48, 7, 41, 41, 304, 918, 57645),
  '30->60|basic_gym': (48, 7, 41, 41, 263, 711, 44286),
  '30->60|full_gym': (48, 7, 41, 41, 254, 716, 44138),
  '45->60|bodyweight': (48, 7, 41, 8, 22, 44, 3084),
  '45->60|home_dumbbells': (48, 7, 41, 7, 14, 36, 2640),
  '45->60|basic_gym': (48, 7, 41, 2, 4, 8, 514),
  '45->60|full_gym': (48, 7, 41, 3, 6, 12, 771),
  '60->90|bodyweight': (48, 0, 48, 4, 8, 28, 1612),
  '60->90|home_dumbbells': (48, 0, 48, 6, 10, 33, 2272),
  '60->90|basic_gym': (48, 0, 48, 1, 1, 2, 0),
  '60->90|full_gym': (48, 0, 48, 2, 2, 5, 403),
};

void main() {
  final h = SweepHarness.install();
  for (final pair in kRepeatMinutePairs) {
    for (final tier in kSweepTiers) {
      final key = '${pair.$1}->${pair.$2}|$tier';
      test('repeat at more minutes [$key]: pins and their sets survive, extras fit', () {
        final t = runRepeatMinutes(h, pair, tier);
        // ignore: avoid_print
        print('REPEAT2D $key ${t.tuple}');
        expect(t.failures.take(10).toList(), isEmpty, reason: '${t.failures.length} failures');
        expect(t.gained, greaterThan(0), reason: 'no persona gained an accessory: the step never ran');
        expect(t.tuple, _expected[key], reason: 'measured reach changed');
      });
    }
  }
}
