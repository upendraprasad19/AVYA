import 'package:test/test.dart';

import 'ai_proxy_hard_failure_lib.dart';

/// Diagnose d3e8a1 (recurrence of a7c3e9, 2026-09-07): `ai_proxy_test.dart`
/// T19 asserted the AI's reply content even when the Edge Function's own
/// `had_hard_failure` flag says the reply is the hardcoded apology, not real
/// model output. This pins the extracted predicate in isolation, since the
/// live E2E path it guards can't be reliably re-triggered on demand without
/// spending more of the shared, rate-limited QA account's daily Gemini quota
/// (e2e-sim-testing skill §5 -- "do not machine-gun the coach").
void main() {
  group('isHardFailureReply', () {
    test('true when had_hard_failure is the literal bool true', () {
      expect(
        isHardFailureReply({
          'reply': 'I had trouble reaching the model. Try again in a moment.',
          'had_hard_failure': true,
        }),
        isTrue,
      );
    });

    test('false when had_hard_failure is false (real model output)', () {
      expect(
        isHardFailureReply({
          'reply': 'Since your goal is to build muscle, ...',
          'had_hard_failure': false,
        }),
        isFalse,
      );
    });

    test('false when had_hard_failure key is absent', () {
      expect(isHardFailureReply({'reply': 'hello'}), isFalse);
    });

    test('false when had_hard_failure is a non-bool truthy-looking value', () {
      // A loose truthy check (`data['had_hard_failure'] != null && ... != false`)
      // would wrongly treat a stray JSON string "true" as a hard failure.
      // Only the literal bool counts.
      expect(
        isHardFailureReply({'reply': 'hello', 'had_hard_failure': 'true'}),
        isFalse,
      );
    });
  });
}
