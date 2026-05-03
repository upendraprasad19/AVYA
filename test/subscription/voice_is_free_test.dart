import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';

/// F13 · Test #9 — Voice MUST stay FREE.
///
/// Locks down the decision that voice (mic) input is not PRO-gated.
/// Reason: on-device speech_to_text has zero infra cost. Gating it
/// added zero margin while reducing engagement.
void main() {
  test('featureVoiceNotes is NOT in allProFeatures', () {
    expect(SubscriptionService.allProFeatures,
        isNot(contains(AppConstants.featureVoiceNotes)),
        reason: 'F13 — voice is free; do not re-add to allProFeatures');
  });
}
