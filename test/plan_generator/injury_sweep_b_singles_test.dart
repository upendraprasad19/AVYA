@Timeout(Duration(minutes: 10))
library;

// Injury re-check sweep, block 1 of 5: SINGLES, 3 and 5 days, phases 1 and 3.
// docs/plans/2026-10-23-library-injury-recheck.md; split into five files, one test per equipment tier, by Batch C1
// (docs/plans/2026-10-25-library-batch-c-new-rows.md Task 5.3). The harness, the gates and the reasons for the split are in
// test/helpers/injury_floor_sweep_lib.dart. (These five files were injury_floor_sweep_*_test.dart before the B-pass.)
//
// The five blocks (each file is one block, every block runs the four tiers as four tests):
//   injury_sweep_b_singles_test.dart     singles, 3 and 5 days, phases 1 and 3        432 runs a tier   (block 1, this file)
//   injury_sweep_e_singles46_test.dart   singles, 4 and 6 days, phase 1                216              (block 2)
//   injury_sweep_a_pairs_test.dart       all 15 pairs of the six most-tagged injuries,
//                                        3 and 5 days, phase 1                          360              (block 3)
//   injury_sweep_c_pairs46_test.dart     the same pairs, 4 and 6 days, phase 1          360              (block 4)
//   injury_sweep_d_repeat_test.dart      phase 1 uninjured, then phase 2 with the injury and those pins,
//                                        3, 4, 5 and 6 days                              432              (block 5)
// All four day counts the product offers (3, 4, 5, 6) are swept (B-pass F3 of the injury re-check: 4 and 6 were missing).
//
// THE LETTER IN EACH NAME IS A CI SORT KEY, NOT A BLOCK NUMBER. .github/workflows/test.yml deals WHOLE test files to four
// shards by their index in the sorted list (scripts/ci_test_partition.dart), so these five heavy files (solo seconds:
// singles 514, pairs 426, pairs46 405, repeat 352, singles46 213) are spread by their NAMES. With a..e the heaviest shard
// carries about 680 s solo; under the old names it carried about 1,250 s. As dealt on PR #178 (the layout after the
// new-row pick test joined the sorted list): golden + pairs46 + scorecard on shard 1; repeat + the set-budget gate on 2;
// core gate + pairs + singles46 on 3; thin-day + singles on 4. CI wall times there: 8m48s, 7m50s, 11m01s, 8m13s. Merging
// main (a new test file) re-dealt them once more, as any file added to the sorted list before these does, so read the four
// shard times on the PR rather than trusting this.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/injury_floor_sweep_lib.dart';

void main() {
  final h = SweepHarness.install();

  // The tier loop below is what makes a tier run at all: a tier dropped from kSweepTiers would silently lose a quarter of
  // every block, so the list is pinned here as a literal (the other four blocks loop the same constant).
  test('the sweep covers the four equipment tiers, nine injuries, six pair injuries, four goals and three levels the product offers', () {
    expect(kSweepTiers, ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym']);
    expect(kSweepInjuries, ['ankle', 'elbow', 'hamstring', 'hip', 'knee', 'lower_back', 'neck', 'shoulder', 'wrist']);
    expect(kSweepPairInjuries, ['knee', 'shoulder', 'lower_back', 'wrist', 'elbow', 'hip']);
    expect(kSweepGoals, ['build_muscle', 'lose_fat', 'strength', 'general_fitness']);
    expect(kSweepLevels, ['beginner', 'intermediate', 'advanced']);
  });

  // B-pass finding (reviewer B, 2026-10-26): the pin above is on the constants, and nothing stopped a block file from
  // dropping its own `for (final tier in kSweepTiers)` loop or changing its day list. This reads the five files (comments
  // stripped) and pins each block's loop and call, so the shared-loop assumption is checked in each file, not assumed.
  test('every block file loops all of kSweepTiers exactly once and runs its own block with its own day list', () {
    // Patterns are regexes with every bracket escaped, so this file (which holds them as text) cannot match itself.
    final blocks = <String, RegExp>{
      'injury_sweep_b_singles_test.dart': RegExp(r'h\.runSingles\(tier, const \[3, 5\], const \[1, 3\]\)'),
      'injury_sweep_e_singles46_test.dart': RegExp(r'h\.runSingles\(tier, const \[4, 6\], const \[1\]\)'),
      'injury_sweep_a_pairs_test.dart': RegExp(r'h\.runPairs\(tier, const \[3, 5\]\)'),
      'injury_sweep_c_pairs46_test.dart': RegExp(r'h\.runPairs\(tier, const \[4, 6\]\)'),
      'injury_sweep_d_repeat_test.dart': RegExp(r'h\.runRepeat\(tier, const \[3, 4, 5, 6\]\)'),
    };
    for (final e in blocks.entries) {
      final text = File('test/plan_generator/${e.key}')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(RegExp(r'for \(final tier in kSweepTiers\)').allMatches(text).length, 1, reason: '${e.key} must loop every tier once');
      expect(e.value.allMatches(text).length, 1, reason: '${e.key} must run ${e.value.pattern}');
      expect(RegExp(r'h\.expectSafe\(t\)').allMatches(text).length, 1, reason: '${e.key} must gate every tier with expectSafe');
      expect(RegExp(r'h\.expectNoThin\(t\)').allMatches(text).length, 1, reason: '${e.key} must gate every tier with expectNoThin');
    }
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
