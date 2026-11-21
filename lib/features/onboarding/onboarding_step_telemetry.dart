import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';

/// Onboarding funnel telemetry (onboarding-fuse-commit, 2026-11-14).
///
/// One `onboarding_step` event the FIRST time each stepped screen is shown in
/// a process, so drop-off per step can be counted in `client_errors`
/// (`error_code = 'event'`). BEST EFFORT, not a reliable funnel: it is a
/// LOW-priority op type, dropped client-side during a rate-limit cooldown
/// (`ErrorTelemetry.logEvent`). Only post-auth screens call it: an anonymous
/// event would need the `log-client-error` anonymous allow-list.
///
/// The message is the step name only (no user data).
final Set<String> _loggedSteps = <String>{};

void logOnboardingStep(String step) {
  if (!_loggedSteps.add(step)) return;
  unawaited(ErrorTelemetry.logEvent('onboarding_step', message: step));
}

/// Test-only: forget which steps were logged.
@visibleForTesting
void resetOnboardingStepTelemetryForTests() => _loggedSteps.clear();
