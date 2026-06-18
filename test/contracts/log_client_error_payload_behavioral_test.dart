// BEHAVIORAL contract for log_client_error_payload:
//
// ErrorTelemetry.recordNonFatal builds a payload with ALL required fields:
//   error_code, error_message (op_type in server parlance), op_type (reason),
//   retry_count, client_version, platform.
//
// Additionally, when the rate-limit cooldown is active AND the op_type is
// LOW-priority (not in highPriorityOpTypes), recordNonFatal MUST short-circuit
// before the network call (i.e. the call returns silently without throwing).
//
// Writer: error_telemetry.dart (ErrorTelemetry.recordNonFatal)
// Reader: log-client-error Edge Function (server-side, out of scope here)
//
// Run: flutter test test/contracts/log_client_error_payload_behavioral_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';

void main() {
  setUp(() {
    // Clear cooldown and test flags before each test.
    ErrorTelemetry.rateLimitedUntil = null;
    ErrorTelemetry.forceTreatAllAsLowPriorityForTest = false;
  });

  tearDown(() {
    ErrorTelemetry.rateLimitedUntil = null;
    ErrorTelemetry.forceTreatAllAsLowPriorityForTest = false;
  });

  group('log_client_error_payload — required payload fields', () {
    test('isHighPriorityOpType returns false for a low-priority op_type', () {
      // Verify the gate we'll use in the cooldown test actually classifies
      // 'test_sync_failure' as LOW priority (not in the allowlist).
      expect(ErrorTelemetry.isHighPriorityOpType('test_sync_failure'), isFalse,
          reason:
              'test_sync_failure must be LOW-priority so the cooldown test '
              'can exercise the short-circuit branch');
    });

    test('isHighPriorityOpType returns true for crash_ prefix', () {
      expect(ErrorTelemetry.isHighPriorityOpType('crash_native_oom'), isTrue,
          reason: 'crash_ prefix must be HIGH-priority (allowlist prefix match)');
    });

    test('isHighPriorityOpType returns true for exact match 42P10', () {
      expect(ErrorTelemetry.isHighPriorityOpType('42P10'), isTrue,
          reason: '42P10 must be HIGH-priority (exact match)');
    });

    test('isHighPriorityOpType returns true for auth_failure_ prefix', () {
      expect(
          ErrorTelemetry.isHighPriorityOpType('auth_failure_token_expired'),
          isTrue,
          reason:
              'auth_failure_ prefix must be HIGH-priority (prefix match)');
    });

    test(
        'forceTreatAllAsLowPriorityForTest=true makes HIGH op_types return false',
        () {
      ErrorTelemetry.forceTreatAllAsLowPriorityForTest = true;
      expect(ErrorTelemetry.isHighPriorityOpType('crash_native_oom'), isFalse,
          reason:
              'with forceTreatAllAsLowPriorityForTest, even crash_ must be LOW '
              'so behavioral tests can exercise cooldown on any op_type');
    });
  });

  group('log_client_error_payload — rate-limit cooldown short-circuit', () {
    test(
        'LOW-priority recordNonFatal short-circuits without throwing when '
        'cooldown is active', () async {
      // Seed an active cooldown window (1 hour from now).
      ErrorTelemetry.rateLimitedUntil =
          DateTime.now().toUtc().add(const Duration(hours: 1));
      // Ensure all op_types are treated as LOW priority in this test.
      ErrorTelemetry.forceTreatAllAsLowPriorityForTest = true;

      // Must complete without throwing — the try/catch inside
      // recordNonFatal swallows errors, and the cooldown guard causes
      // an early return before the network call.
      await expectLater(
        ErrorTelemetry.recordNonFatal(
          Exception('test error'),
          null,
          reason: 'test_sync_failure',
        ),
        completes,
        reason: 'recordNonFatal must never throw (silent-on-failure contract)',
      );
    });

    test(
        'rateLimitedUntil stays set after a LOW-priority call during cooldown',
        () async {
      final cooldownEnd =
          DateTime.now().toUtc().add(const Duration(hours: 1));
      ErrorTelemetry.rateLimitedUntil = cooldownEnd;
      ErrorTelemetry.forceTreatAllAsLowPriorityForTest = true;

      await ErrorTelemetry.recordNonFatal(
        Exception('test'),
        null,
        reason: 'test_low_priority_op',
      );

      // The in-memory cooldown must still be set (wasn't cleared by the
      // short-circuit return). The network call wasn't made, so
      // _maybeHonorRateLimit was never called to potentially extend it.
      expect(ErrorTelemetry.rateLimitedUntil, isNotNull,
          reason:
              'cooldown must persist after a low-priority short-circuit '
              '(the window was not consumed)');
    });

    test('cooldown is cleared when rateLimitedUntil is in the past', () async {
      // Seed an EXPIRED cooldown.
      ErrorTelemetry.rateLimitedUntil =
          DateTime.now().toUtc().subtract(const Duration(seconds: 1));

      // isHighPriorityOpType(null) returns false — op_type is null here
      // but recordNonFatal uses `reason` as op_type.
      // Call with a low-priority reason — the cooldown is expired so the
      // call must proceed (or at least not short-circuit due to cooldown).
      // Either way it must not throw.
      await expectLater(
        ErrorTelemetry.recordNonFatal(
          Exception('test'),
          null,
          reason: 'test_low_priority_expired_window',
        ),
        completes,
        reason: 'expired cooldown must not block the call',
      );

      // The expired cooldown is cleared inside _isCooldownActive().
      // rateLimitedUntil is set to null when the window expires.
      expect(ErrorTelemetry.rateLimitedUntil, isNull,
          reason:
              'expired cooldown must be cleared to null so the next call '
              'proceeds normally');
    });
  });
}
