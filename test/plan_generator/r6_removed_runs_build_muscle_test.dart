@Timeout(Duration(minutes: 10))
library;

// Unit 1B-F, Ruling 3: the CI hard test over the runs where the deleted R6 refill used to act, domain `r9`, goal
// `build_muscle` (325 runs). Harness, assertions and provenance: test/helpers/r6_removed_runs_lib.dart and
// test/fixtures/r6_removed_runs.txt. The (thin, one-exercise) day counts are recorded on the final tree (Task 5).

import 'package:flutter_test/flutter_test.dart';

import '../helpers/injury_floor_sweep_lib.dart';
import '../helpers/r6_removed_runs_lib.dart';

void main() {
  final h = SweepHarness.install();
  defineR6RemovedRunsTests(
    h,
    domain: 'r9',
    goal: 'build_muscle',
    runCounts: const {'bodyweight': 292, 'home_dumbbells': 25, 'basic_gym': 7, 'full_gym': 1},
    ceilings: const {'bodyweight': (4, 2), 'home_dumbbells': (4, 0), 'basic_gym': (8, 0), 'full_gym': (1, 0)},
  );
}
