// Obs 4, internal-testing batch 2026-09-15. `formatWeightDisplayValue`
// (lib/features/train/screens/active_workout/exercise_card.dart) is the
// writer for both weight-prefill sites in `_ExerciseCardState._initControllers`
// (last-logged weight x effectiveLoadFactor, and restored setInputValues).
// Float multiplication rarely lands on an exact value, so the pre-fix
// fallback (`w == w.roundToDouble() ? w.toInt().toString() : w.toString()`)
// printed raw float noise like `27.900000000000002` straight into the weight
// input. This test is a real behavioral check on the pure formatting
// function, not a source-grep.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/train/screens/active_workout/screen.dart';

void main() {
  group('formatWeightDisplayValue', () {
    test('rounds float multiplication noise to 2 decimal places', () {
      // 31.0 * 0.9 == 27.900000000000002 in IEEE 754 double arithmetic —
      // exactly the lastWeight * effectiveLoadFactor shape that triggered
      // the bug report.
      final w = 31.0 * 0.9;
      expect(w.toString(), contains('27.9000000'),
          reason: 'sanity check: the raw double must actually be noisy, or '
              'this test proves nothing');
      expect(formatWeightDisplayValue(w), '27.9');
    });

    test('strips a clean trailing .0 for whole numbers', () {
      expect(formatWeightDisplayValue(28.0), '28');
    });

    test('keeps a genuine 1-decimal value intact', () {
      expect(formatWeightDisplayValue(27.5), '27.5');
    });

    test('never emits more than 2 decimal places', () {
      final result = formatWeightDisplayValue(19.0 * 1.333333333);
      final decimalPart = result.split('.').elementAtOrNull(1);
      expect(decimalPart == null || decimalPart.length <= 2, isTrue,
          reason: 'formatted weight "$result" has more than 2 decimals');
    });
  });
}
