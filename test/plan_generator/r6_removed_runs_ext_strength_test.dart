@Timeout(Duration(minutes: 10))
library;

// Unit 1B-F, Ruling 3: the CI hard test over the runs where the deleted R6 refill used to act, domain `ext`, goal
// `strength` (371 runs). Harness, assertions and provenance: test/helpers/r6_removed_runs_lib.dart and
// test/fixtures/r6_removed_runs.txt. The (thin, one-exercise) day counts are recorded on the final tree (Task 5).

import 'package:flutter_test/flutter_test.dart';

import '../helpers/injury_floor_sweep_lib.dart';
import '../helpers/r6_removed_runs_lib.dart';

void main() {
  final h = SweepHarness.install();
  defineR6RemovedRunsTests(
    h,
    domain: 'ext',
    goal: 'strength',
    runCounts: const {'bodyweight': 250, 'home_dumbbells': 99, 'basic_gym': 22},
    ceilings: const {'bodyweight': (18, 0), 'home_dumbbells': (8, 0), 'basic_gym': (0, 0)},
  );
}
