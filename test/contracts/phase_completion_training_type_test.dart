import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/phase_completion.dart';

void main() {
  group('isPhaseCompletionTrainingType', () {
    test('workout and custom_template count as training (pre-existing whitelist)', () {
      expect(isPhaseCompletionTrainingType('workout'), isTrue);
      expect(isPhaseCompletionTrainingType('custom_template'), isTrue);
    });

    test('logged now counts as training — the OI-126 fix', () {
      expect(isPhaseCompletionTrainingType('logged'), isTrue);
    });

    test('rest, off, null, and unrecognized types are NOT training', () {
      expect(isPhaseCompletionTrainingType('rest'), isFalse);
      expect(isPhaseCompletionTrainingType('off'), isFalse);
      expect(isPhaseCompletionTrainingType(null), isFalse);
      expect(isPhaseCompletionTrainingType('some_future_type'), isFalse);
    });

    test('stays a WHITELIST, not the exclusion shape', () {
      // isTrainingDayType (exclusion-shaped) would count 'some_future_type' as
      // training. isPhaseCompletionTrainingType must NOT.
      expect(isTrainingDayType('some_future_type'), isTrue);
      expect(isPhaseCompletionTrainingType('some_future_type'), isFalse);
    });
  });
}
