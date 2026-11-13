@Timeout(Duration(minutes: 10))
library;

// Unit 1B-F, Ruling 3: the CI hard test over the runs where the deleted R6 refill used to act, domain `r9`, goal
// `general_fitness` (270 runs). Harness, assertions and provenance: test/helpers/r6_removed_runs_lib.dart and
// test/fixtures/r6_removed_runs.txt. The (thin, one-exercise) day counts are recorded on the final tree (Task 5).

import 'package:flutter_test/flutter_test.dart';

import '../helpers/injury_floor_sweep_lib.dart';
import '../helpers/r6_removed_runs_lib.dart';

void main() {
  final h = SweepHarness.install();
  defineR6RemovedRunsTests(
    h,
    domain: 'r9',
    goal: 'general_fitness',
    runCounts: const {'bodyweight': 213, 'home_dumbbells': 31, 'basic_gym': 18, 'full_gym': 8},
    // Unit 2B (OI-452, diagnose b3f1d8): the 3-exercise day floor leaves no thin or one-exercise day here; was
    // const {'bodyweight': (12, 2), 'home_dumbbells': (47, 4), 'basic_gym': (50, 4), 'full_gym': (26, 0)},
    ceilings: const {'bodyweight': (0, 0), 'home_dumbbells': (0, 0), 'basic_gym': (0, 0), 'full_gym': (0, 0)},
  );
}
