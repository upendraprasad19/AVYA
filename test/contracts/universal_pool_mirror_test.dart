// test/contracts/universal_pool_mirror_test.dart
//
// Batch 13-A (H5): the pure-Dart cascade_tracer (which the scorecard/generator_matrix
// run off) holds a MANUAL copy of ExerciseSelector.universalPoolV4. Before this batch
// nothing asserted the two are equal, so a fix to one that forgot the other would
// silently diverge the harness from production. This pins them byte-for-byte.
//
// ⑦ OI-89 (2026-08-28) adds the ORDER invariant below. The B-pass found this batch
// reordering two pools while its own comment claimed it had not, and the reorder was
// a live regression — see that group's header.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/exercise_selector.dart';
import '../plan_generator/v4_diagnostic/cascade_tracer.dart';

void main() {
  test('cascade_tracer universalPoolV4Mirror == ExerciseSelector.universalPoolV4', () {
    expect(universalPoolV4Mirror, ExerciseSelector.universalPoolV4);
  });

  group('universalPoolV4 is APPEND-ONLY (⑦ OI-89)', () {
    // WHY THIS IS AN INVARIANT AND NOT A STYLE RULE.
    //
    // attempt-5 does NOT check equipment_tier. It resolves a pool name through
    // repo.search and applies only exclusions, injuries and capability — and
    // capability is null ABOVE the bodyweight tier by decision 1. So for a
    // gym-tier user nothing in att5 filters on equipment: the first pool entry
    // not already picked simply wins. Position IS the prescription.
    //
    // The regression this pins, found by the B-pass on this batch's own diff:
    // `Dip (Parallel Bars)` was promoted to the head of elbow_extension while
    // adding the new bodyweight tails. `parallel bars` is NOT granted by
    // home_dumbbells, so a home user reaching att5 would have been handed a dip
    // station where the previous order gave them a Diamond Push Up — a pure
    // regression, invisible to the capability floor because that tier is above
    // its scope.
    //
    // The prefixes below are the pool AS IT STOOD before OI-89. Adding to a pool
    // is fine and expected; reordering or removing is what must be deliberate
    // enough to come here and say so.
    const preOi89Prefixes = <String, List<String>>{
      'horizontal_push': ['Push Up', 'Incline Push Up', 'Wall Push Up', 'Decline Push Up', 'Diamond Push Up'],
      'vertical_push': ['Pike Push Up', 'Handstand Hold', 'Dand (Hindu Pushup)'],
      'horizontal_pull': ['Inverted Row', 'TRX Row'],
      'vertical_pull': ['Pull Up', 'Chin Up', 'Inverted Row'],
      'knee_dominant': ['Baithak (Hindu Squat)', 'Reverse Lunge', 'Bulgarian Split Squat', 'Jump Squat'],
      'hip_dominant': ['Glute Bridge', 'Single Leg Romanian Deadlift', 'Good Morning'],
      'core': ['Plank', 'Dead Bug', 'Hollow Body Hold', 'Bicycle Crunch', 'Mountain Climber'],
      'elbow_flexion': ['Chin Up', 'Inverted Row'],
      'elbow_extension': ['Diamond Push Up', 'Bench Dips', 'Dip (Parallel Bars)'],
      'shoulder_isolation': ['Bodyweight Rear Delt Raise', 'Band Pull Apart', 'Arm Circles'],
      'hip_isolation': ['Glute Bridge', 'Glute Kickback'],
    };

    test('every pre-OI-89 entry keeps its exact position', () {
      preOi89Prefixes.forEach((pattern, expectedPrefix) {
        final actual = ExerciseSelector.universalPoolV4[pattern];
        expect(actual, isNotNull, reason: 'pattern "$pattern" vanished');
        expect(actual!.length, greaterThanOrEqualTo(expectedPrefix.length),
            reason: '"$pattern" lost entries; this pool is append-only');
        expect(actual.sublist(0, expectedPrefix.length), expectedPrefix,
            reason: 'The head of "$pattern" changed. att5 does not filter on '
                'equipment_tier and capability is null above bodyweight, so the '
                'first unpicked entry IS what a gym-tier user is prescribed — '
                'reordering silently changes their plan. If this is deliberate, '
                'update preOi89Prefixes and say why in the commit.');
      });
    });

    test('every pattern the pre-OI-89 pool had still exists', () {
      // Guards the mirror case of the length check above: a pattern deleted
      // wholesale would otherwise slip past a per-pattern loop over the CURRENT
      // pool rather than the expected one.
      expect(ExerciseSelector.universalPoolV4.keys.toSet(),
          containsAll(preOi89Prefixes.keys));
    });
  });
}
