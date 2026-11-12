@Timeout(Duration(minutes: 10))
library;

// Unit 1B-F, Ruling 3: the CI hard test over the runs where the deleted R6 refill used to act, domain `r9`, goal
// `lose_fat` (249 runs). Harness, assertions and provenance: test/helpers/r6_removed_runs_lib.dart and
// test/fixtures/r6_removed_runs.txt. The (thin, one-exercise) day counts are recorded on the final tree (Task 5).

import 'package:flutter_test/flutter_test.dart';

import '../helpers/injury_floor_sweep_lib.dart';
import '../helpers/r6_removed_runs_lib.dart';

void main() {
  final h = SweepHarness.install();
  defineR6RemovedRunsTests(
    h,
    domain: 'r9',
    goal: 'lose_fat',
    runCounts: const {'bodyweight': 212, 'home_dumbbells': 20, 'basic_gym': 11, 'full_gym': 6},
    ceilings: const {'bodyweight': (6, 2), 'home_dumbbells': (22, 0), 'basic_gym': (24, 0), 'full_gym': (16, 0)},
  );
}
