// BEHAVIORAL contract for error_telemetry_helper:
//
// 1. ErrorTelemetry.recordNonFatal NEVER throws — even when the underlying
//    Supabase callFunction call fails (silent-on-failure contract).
//
// 2. isHighPriorityOpType classification is stable and symmetric for every
//    op_type pattern used by _reportSyncFailure callers.
//
// The SyncService._reportSyncFailure method calls
//   unawaited(ErrorTelemetry.recordNonFatal(error, null, reason: opType))
// — this test verifies the "never throws" invariant by calling recordNonFatal
// with various error types, including one that simulates a failed network call
// (SupabaseService will throw in test env with no real credentials).
//
// Writer: error_telemetry.dart (ErrorTelemetry.recordNonFatal)
// Reader: sync_service.dart (_reportSyncFailure), every catch block in the app
//
// Run: flutter test test/contracts/error_telemetry_helper_behavioral_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';

void main() {
  setUp(() {
    ErrorTelemetry.rateLimitedUntil = null;
    ErrorTelemetry.forceTreatAllAsLowPriorityForTest = false;
  });

  tearDown(() {
    ErrorTelemetry.rateLimitedUntil = null;
    ErrorTelemetry.forceTreatAllAsLowPriorityForTest = false;
  });

  group('error_telemetry_helper — silent-on-failure contract', () {
    test('recordNonFatal does not throw for a plain Exception', () async {
      await expectLater(
        ErrorTelemetry.recordNonFatal(
          Exception('plain error'),
          null,
          reason: 'test_plain_exception',
        ),
        completes,
        reason: 'recordNonFatal must complete without throwing',
      );
    });

    test('recordNonFatal does not throw for a StateError', () async {
      await expectLater(
        ErrorTelemetry.recordNonFatal(
          StateError('bad state'),
          StackTrace.current,
          reason: 'test_state_error',
        ),
        completes,
        reason: 'recordNonFatal must not throw even for StateError with stack',
      );
    });

    test('recordNonFatal does not throw for a TypeError (null dereference)',
        () async {
      // Simulate what happens when a nullable was unexpectedly null.
      final error = TypeError();
      await expectLater(
        ErrorTelemetry.recordNonFatal(
          error,
          null,
          reason: 'test_type_error',
        ),
        completes,
        reason: 'recordNonFatal must swallow TypeError silently',
      );
    });

    test('recordNonFatal does not throw when network call fails (test env)',
        () async {
      // In the test environment SupabaseService.instance.callFunction will
      // throw because there is no real Supabase client configured. The
      // catch (_) inside recordNonFatal must swallow that and return normally.
      await expectLater(
        ErrorTelemetry.recordNonFatal(
          Exception('simulate network failure path'),
          null,
          reason: 'sync_failure_push_workouts', // a real sync op_type
        ),
        completes,
        reason:
            'recordNonFatal must not propagate a network-call exception '
            '(silent-on-failure is the contract for the entire catch-block posture)',
      );
    });

    test('recordNonFatal with extra metadata does not throw', () async {
      await expectLater(
        ErrorTelemetry.recordNonFatal(
          Exception('extra test'),
          null,
          reason: 'test_with_extra',
          extra: {'key1': 'value1', 'key2': 'value2'},
        ),
        completes,
        reason: 'extra metadata must not cause a throw',
      );
    });

    test(
        'recordNonFatal during cooldown (LOW-priority) completes without '
        'throwing', () async {
      ErrorTelemetry.rateLimitedUntil =
          DateTime.now().toUtc().add(const Duration(hours: 1));
      ErrorTelemetry.forceTreatAllAsLowPriorityForTest = true;

      await expectLater(
        ErrorTelemetry.recordNonFatal(
          Exception('cooldown test'),
          null,
          reason: 'test_low_priority_during_cooldown',
        ),
        completes,
        reason: 'even the short-circuit cooldown path must not throw',
      );
    });
  });

  group('error_telemetry_helper — isHighPriorityOpType invariants', () {
    // These exact op_types are used by _reportSyncFailure callers. Drift
    // between client allowlist and server HIGH_PRIORITY_OP_TYPES is silent.
    // This test pins the client-side classification for known op_types.

    test('sync op_types are LOW-priority (should be rate-limited)', () {
      const lowPriorityOps = [
        'sync_failure_push_workouts',
        'sync_failure_push_nutrition',
        'sync_failure_push_health',
        'hive_service_maybe_compact',
        'test_low_priority',
      ];
      for (final op in lowPriorityOps) {
        expect(ErrorTelemetry.isHighPriorityOpType(op), isFalse,
            reason: '$op must be classified as LOW-priority');
      }
    });

    test('crash_ / auth_failure_ / 23502 are HIGH-priority (bypass cooldown)',
        () {
      const highPriorityOps = [
        'crash_native_oom',
        'app_crash_jni',
        'auth_failure_token_refresh',
        'auth_signed_out_unexpected',
        'guarded_box_disagreement',
        'hive_session_owner_mismatch',
        '42P10',
        '23502',
        '23505',
        '23503',
        'permission_denied',
        'unique_violation',
        'gate16_violation',
        'discipline_gate_violation',
        'sync_failure_dead_letter',
      ];
      for (final op in highPriorityOps) {
        expect(ErrorTelemetry.isHighPriorityOpType(op), isTrue,
            reason: '$op must be classified as HIGH-priority');
      }
    });

    test('null and empty string are LOW-priority', () {
      expect(ErrorTelemetry.isHighPriorityOpType(null), isFalse);
      expect(ErrorTelemetry.isHighPriorityOpType(''), isFalse);
    });
  });
}
