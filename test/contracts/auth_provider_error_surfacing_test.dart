import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for Bug A's silent-swallow class.
///
/// _ensureLocalUser previously caught all errors with just debugPrint,
/// hiding 23505/23503 violations for 48h. This test pins the requirement
/// that errors get routed to the telemetry sink so they're visible.
///
/// Audit 2026-05-20 / A11: previously asserted the literal string
/// `'log-client-error'` appeared in the source — broke when the inline
/// call was deleted in favor of `ErrorTelemetry.recordNonFatal` (which
/// internally wraps log-client-error with the rate-limit cooldown fixed
/// in #16.1 D). Updated to assert the canonical path. See
/// `feedback_source_grep_false_confidence.md` for the class.
void main() {
  test('_ensureLocalUser routes catch-path errors to telemetry sink', () {
    final source = File(
      'lib/features/auth/providers/auth_provider.dart',
    ).readAsStringSync();

    // Find the _ensureLocalUser method body
    final ensureStart = source.indexOf('Future<void> _ensureLocalUser(');
    expect(ensureStart, isNot(-1),
        reason: '_ensureLocalUser must exist on AuthNotifier');

    // The method runs from declaration to the next top-level method
    // declaration. Test #10.1 — bumped to 8000 chars because the
    // verify-after-clear + UserConfigMigrator block added ~50 lines.
    // audit-2026-05-11 H-3 — bumped to 10000 because the email-prefix
    // self-heal block added another ~30 lines inside the same method.
    final body = source.substring(
      ensureStart,
      (ensureStart + 10000).clamp(0, source.length),
    );

    // Must route through the canonical telemetry sink. ErrorTelemetry
    // .recordNonFatal internally posts to log-client-error AND honors
    // the rate-limit cooldown (silent-drop fix #16.1 D).
    final routesThroughTelemetry =
        body.contains('ErrorTelemetry.recordNonFatal') ||
            body.contains('log-client-error');
    expect(
      routesThroughTelemetry,
      isTrue,
      reason:
          '_ensureLocalUser catch blocks must route errors to the canonical '
          'ErrorTelemetry sink (or inline log-client-error) so silent FK / '
          'UNIQUE violations show up in client_errors. Bug A hid for 48h '
          'because of silent swallow.',
    );

    // Must check for Postgres error codes 23505/23503 explicitly so the
    // error type is preserved in the log payload.
    expect(
      body.contains('23505') || body.contains('23503'),
      isTrue,
      reason:
          'Catch path should detect 23505 (unique_violation) and '
          '23503 (foreign_key_violation) so the AI-readable error_type '
          'is correct.',
    );
  });
}
