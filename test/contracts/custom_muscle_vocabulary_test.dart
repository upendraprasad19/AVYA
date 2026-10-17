// CONTRACT TEST — custom-exercise muscle chip vocabulary
// (custom-picker-fix, 2026-09-17)
//
// The creation sheet's muscle chips MUST use tokens that are keys of the
// canonical library map `_muscleToGroup` (plan_engine/muscle_groups.dart).
// Non-canonical tokens would be silently ignored by the plan-engine
// readers (`_muscleTokens` lowercases, `muscleGroupOf` maps — an
// unmapped token is dropped from titration/coverage and never matches a
// split slot).
//
// `canonicalMuscleTokens` is an ADDITIVE read-only getter; the map
// content itself stays frozen (D3 scorecard baseline).
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/train/widgets/create_custom_exercise_sheet.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/muscle_groups.dart';

void main() {
  group('custom exercise muscle vocabulary', () {
    test('every UI chip token is library-canonical', () {
      final canonical = canonicalMuscleTokens;
      expect(canonical, isNotEmpty);
      for (final (token, _) in CreateCustomExerciseSheet.muscleOptions) {
        expect(
          canonical.contains(token),
          isTrue,
          reason: 'UI muscle token "$token" is not a key of _muscleToGroup. '
              'Add the key to the canonical map FIRST (a deliberate act — '
              'the map content is frozen for the D3 baseline), then extend '
              'muscleOptions.',
        );
      }
    });

    test('muscle tokens lowercase-compose with the plan-engine readers', () {
      // _muscleTokens + muscleGroupOf both lowercase before matching, so a
      // lowercase token must map non-null for the majors the UI offers.
      expect(muscleGroupOf('chest'), equals('Chest'));
      expect(muscleGroupOf('lats'), equals('Back'));
      expect(muscleGroupOf('quads'), equals('Quads'));
      expect(muscleGroupOf('obliques'), equals('Core'));
      // A token the UI offers must NEVER map to null (it would silently
      // contribute nothing to coverage/titration).
      for (final (token, _) in CreateCustomExerciseSheet.muscleOptions) {
        expect(muscleGroupOf(token), isNotNull,
            reason: 'UI token "$token" must map to a major group');
      }
    });

    test('core groups the UI promises are represented', () {
      final uiTokens =
          CreateCustomExerciseSheet.muscleOptions.map((o) => o.$1).toSet();
      for (final required in [
        'chest', 'lats', 'shoulders', 'biceps', 'triceps', 'quads',
        'hamstrings', 'glutes', 'calves', 'abs',
      ]) {
        expect(uiTokens.contains(required), isTrue,
            reason: 'the UI chip set must keep covering "$required"');
      }
    });
  });
}
