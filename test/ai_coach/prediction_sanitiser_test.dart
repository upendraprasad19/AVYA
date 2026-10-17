// test/ai_coach/prediction_sanitiser_test.dart
//
// Regression tests for F4 — the sanitiser must handle YAML-style key:value
// output from Gemini, not just JSON / code-fence shapes.
//
// _writeBackToHive is a no-op in test context (Hive not initialised) because
// it catches all exceptions internally, so these tests exercise the pure
// string-transformation logic only.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';

void main() {
  group('PredictionNotifier sanitise', () {
    test('extracts summary from JSON object shape', () {
      final raw = '{"summary": "You will lose 4kg in 12 weeks of training."}';
      expect(
        PredictionNotifierTestExports.sanitise(raw),
        'You will lose 4kg in 12 weeks of training.',
      );
    });

    test('extracts predictions[0].summary from nested JSON', () {
      final raw = '{"predictions": [{"summary": "Strength up by 15 percent."}]}';
      expect(
        PredictionNotifierTestExports.sanitise(raw),
        'Strength up by 15 percent.',
      );
    });

    test('strips code-fence wrapped JSON', () {
      final raw =
          '```json\n{"summary": "Plain prose response here for the user."}\n```';
      expect(
        PredictionNotifierTestExports.sanitise(raw),
        'Plain prose response here for the user.',
      );
    });

    test('extracts longest prose value from YAML-style key:value (F4)', () {
      final raw = 'outcome_3_months: weight_kg:77.5. body.\n'
          'rationale: You are projected to gain 4kg of lean mass over 12 weeks '
          'with consistent 4-day training and 2800 kcal intake.\n'
          'confidence: high';
      final result = PredictionNotifierTestExports.sanitise(raw);
      expect(
        result,
        contains('4kg of lean mass over 12 weeks'),
        reason: 'Should pick the longest prose value (the rationale line).',
      );
    });

    test('handles single-line key:value with prose value', () {
      final raw = 'prediction: In 12 weeks you will be visibly leaner with '
          'measurable strength gains across compound lifts.';
      final result = PredictionNotifierTestExports.sanitise(raw);
      expect(result, contains('visibly leaner'));
      expect(result, isNot(startsWith('prediction:')));
    });

    test('falls back to joining stripped values when no single prose value', () {
      final raw = 'weight: -3kg\n'
          'protein: 137g\n'
          'days: 4';
      final result = PredictionNotifierTestExports.sanitise(raw)!;
      expect(result.contains('-3kg'), true);
      expect(result.contains('137g'), true);
      expect(result.contains('weight:'), false);
      expect(result.contains('protein:'), false);
    });

    test('passes through plain prose unchanged', () {
      final raw = 'In 12 weeks you will be visibly leaner.';
      expect(
        PredictionNotifierTestExports.sanitise(raw),
        raw,
      );
    });

    test('returns null for null input', () {
      expect(PredictionNotifierTestExports.sanitise(null), null);
    });

    test('returns null for empty input', () {
      expect(PredictionNotifierTestExports.sanitise(''), null);
    });
  });
}
