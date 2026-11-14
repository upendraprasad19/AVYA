@Timeout(Duration(minutes: 10))
library;

// Unit 1B-F, Ruling 3: the CI hard test over the runs where the deleted R6 refill used to act, domain `ext`, goal
// `build_muscle` (492 runs). Harness, assertions and provenance: test/helpers/r6_removed_runs_lib.dart and
// test/fixtures/r6_removed_runs.txt. The (thin, one-exercise) day counts are recorded on the final tree (Task 5).

import 'package:flutter_test/flutter_test.dart';

import '../helpers/injury_floor_sweep_lib.dart';
import '../helpers/r6_removed_runs_lib.dart';

void main() {
  final h = SweepHarness.install();
  defineR6RemovedRunsTests(
    h,
    domain: 'ext',
    goal: 'build_muscle',
    runCounts: const {'bodyweight': 250, 'home_dumbbells': 198, 'basic_gym': 44},
    // Unit 2B (OI-452, diagnose b3f1d8): the 3-exercise day floor leaves no thin or one-exercise day here; was
    // const {'bodyweight': (4, 0), 'home_dumbbells': (0, 0), 'basic_gym': (44, 0)},
    ceilings: const {'bodyweight': (0, 0), 'home_dumbbells': (0, 0), 'basic_gym': (0, 0)},
  );
}
