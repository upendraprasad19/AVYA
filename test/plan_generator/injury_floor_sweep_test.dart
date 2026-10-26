@Timeout(Duration(minutes: 10))
library;

// Injury re-check sweep, block 1 of 5: SINGLES, 3 and 5 days, phases 1 and 3.
// docs/plans/2026-10-23-library-injury-recheck.md; split into five files, one test per equipment tier, by Batch C1
// (docs/plans/2026-10-25-library-batch-c-new-rows.md Task 5.3). The harness, the gates and the reasons for the split are in
// test/helpers/injury_floor_sweep_lib.dart.
//
// The five blocks (each file is one block, every block runs the four tiers as four tests):
//   injury_floor_sweep_test.dart            singles, 3 and 5 days, phases 1 and 3        432 runs a tier
//   injury_floor_sweep_singles46_test.dart  singles, 4 and 6 days, phase 1                216
//   injury_floor_sweep_pairs_test.dart      all 15 pairs of the six most-tagged injuries,
//                                           3 and 5 days, phase 1                          360
//   injury_floor_sweep_pairs46_test.dart    the same pairs, 4 and 6 days, phase 1          360
//   injury_floor_sweep_repeat_test.dart     phase 1 uninjured, then phase 2 with the injury and those pins,
//                                           3, 4, 5 and 6 days                              432
// All four day counts the product offers (3, 4, 5, 6) are swept (B-pass F3 of the injury re-check: 4 and 6 were missing).

import 'package:flutter_test/flutter_test.dart';

import '../helpers/injury_floor_sweep_lib.dart';

void main() {
  final h = SweepHarness.install();

  // The tier loop below is what makes a tier run at all: a tier dropped from kSweepTiers would silently lose a quarter of
  // every block, so the list is pinned here as a literal (the other four blocks loop the same constant).
  test('the sweep covers the four equipment tiers the product offers', () {
    expect(kSweepTiers, ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym']);
    expect(kSweepInjuries.length, 9);
    expect(kSweepPairInjuries.length, 6);
  });

  for (final tier in kSweepTiers) {
    test('singles [$tier]: 9 injuries x goals x levels x 3/5 days x phases 1,3', () {
      final sw = Stopwatch()..start();
      final t = h.runSingles(tier, const [3, 5], const [1, 3]);
      h.report('singles $tier', t, sw);
      expect(t.runs, 432);
      h.expectSafe(t);
      h.expectNoThin(t);
    });
  }
}
