import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';

/// F13 · Test #9 — Voice MUST stay FREE.
///
/// Locks down the decision that voice (mic) input is not PRO-gated.
/// Reason: on-device speech_to_text has zero infra cost. Gating it
/// added zero margin while reducing engagement.
///
/// audit-2026-05-16 E.8 — `AppConstants.featureVoiceNotes` constant DELETED
/// entirely (had 0 callsites since Test #9 made it free; founder approved
/// Phase D NEEDS_DECISION 4 Option A). Test reframed to assert the string
/// literal `'voice_notes'` no longer appears in the PRO feature list.
void main() {
  test('"voice_notes" string is NOT in allProFeatures', () {
    expect(SubscriptionService.allProFeatures, isNot(contains('voice_notes')),
        reason:
            'F13 — voice is free; do not re-add "voice_notes" to '
            'allProFeatures. The featureVoiceNotes constant was deleted in '
            'audit-2026-05-16 E.8.');
  });
}
