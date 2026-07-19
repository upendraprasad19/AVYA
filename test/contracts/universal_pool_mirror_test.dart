// test/contracts/universal_pool_mirror_test.dart
//
// Batch 13-A (H5): the pure-Dart cascade_tracer (which the scorecard/generator_matrix
// run off) holds a MANUAL copy of ExerciseSelector.universalPoolV4. Before this batch
// nothing asserted the two are equal, so a fix to one that forgot the other would
// silently diverge the harness from production. This pins them byte-for-byte.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/exercise_selector.dart';
import '../plan_generator/v4_diagnostic/cascade_tracer.dart';

void main() {
  test('cascade_tracer universalPoolV4Mirror == ExerciseSelector.universalPoolV4', () {
    expect(universalPoolV4Mirror, ExerciseSelector.universalPoolV4);
  });
}
