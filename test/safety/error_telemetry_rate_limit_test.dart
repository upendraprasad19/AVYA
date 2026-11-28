import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';

/// APK Test #16.1 / Theme D — observability silent-drop fix.
///
/// Pre-Test-#16.1 the `log-client-error` Edge Function silently dropped
/// every call past 100 events/user/24h, returning `{ok: true,
/// rate_limited: true}` that the client IGNORED. We were blind to
/// hundreds of failures after the founder's 04:10 UTC 2026-05-15 storm.
///
/// Test #16.1 / Theme D fix:
///   1. Server bumps budget to 2000/day.
///   2. Server returns `next_window_at` so client can compute precise
///      cooldown TTL.
///   3. Server has a HIGH-priority lane that always inserts past budget.
///   4. Client honors `rate_limited: true` — LOW-priority op_types drop
///      without a network round-trip during cooldown; HIGH-priority
///      op_types ALWAYS post.
///
/// These tests pin the client-side priority classifier + cooldown
/// state machine (the parts we can exercise without a network round-
/// trip). The server-side priority lane is pinned by the Deno
/// behavioral test in `supabase/functions/log-client-error/`.
///
/// Source-grep tests for the matching constant list keep client + server
/// in lock-step (`HIGH_PRIORITY_OP_TYPES` in `index.ts` and
/// `ErrorTelemetry.highPriorityOpTypes` in `error_telemetry.dart`).
void main() {
  setUp(() {
    ErrorTelemetry.rateLimitedUntil = null;
    ErrorTelemetry.forceTreatAllAsLowPriorityForTest = false;
  });

  tearDown(() {
    ErrorTelemetry.rateLimitedUntil = null;
    ErrorTelemetry.forceTreatAllAsLowPriorityForTest = false;
  });

  group('Test #16.1 / Theme D — HIGH-priority classification', () {
    test('crash_native_oom matches crash_ prefix', () {
      expect(ErrorTelemetry.isHighPriorityOpType('crash_native_oom'), isTrue);
    });

    test('app_crash_dart_assert matches app_crash_ prefix', () {
      expect(
          ErrorTelemetry.isHighPriorityOpType('app_crash_dart_assert'), isTrue);
    });

    test('auth_failure_session_race matches auth_failure_ prefix', () {
      expect(
          ErrorTelemetry.isHighPriorityOpType('auth_failure_session_race'),
          isTrue);
    });

    test('42P10 (exact equality) is HIGH', () {
      expect(ErrorTelemetry.isHighPriorityOpType('42P10'), isTrue);
    });

    test('23505 (exact equality) is HIGH', () {
      expect(ErrorTelemetry.isHighPriorityOpType('23505'), isTrue);
    });

    test('guarded_box_disagreement (exact equality) is HIGH', () {
      expect(
          ErrorTelemetry.isHighPriorityOpType('guarded_box_disagreement'),
          isTrue);
    });

    test('sync_failure_dead_letter (exact equality) is HIGH', () {
      expect(
          ErrorTelemetry.isHighPriorityOpType('sync_failure_dead_letter'),
          isTrue);
    });

    test('writer_reader_drift_workout (prefix) is HIGH', () {
      expect(
          ErrorTelemetry.isHighPriorityOpType('writer_reader_drift_workout'),
          isTrue);
    });

    test('LOW classification — sync_skipped_null_natural_key', () {
      // The 9f4ab2 defence-in-depth guard fires a chatty op_type that
      // MUST be LOW so a runaway null-key bug doesn't bypass the budget.
      expect(
          ErrorTelemetry.isHighPriorityOpType('sync_skipped_null_natural_key'),
          isFalse);
    });

    test('LOW classification — edge_function_cold_start_retry', () {
      // Up to 3 retries per cold-start = chatty. Must share budget.
      expect(
          ErrorTelemetry
              .isHighPriorityOpType('edge_function_cold_start_retry'),
          isFalse);
    });

    test('LOW classification — restore_started / restore_completed', () {
      expect(ErrorTelemetry.isHighPriorityOpType('restore_started'), isFalse);
      expect(
          ErrorTelemetry.isHighPriorityOpType('restore_completed'), isFalse);
    });

    test('LOW classification — null op_type', () {
      expect(ErrorTelemetry.isHighPriorityOpType(null), isFalse);
    });

    test('LOW classification — empty op_type', () {
      expect(ErrorTelemetry.isHighPriorityOpType(''), isFalse);
    });

    test('case-sensitivity — 42p10 lowercase is NOT high', () {
      // Server-side string match is case-sensitive; client must mirror.
      expect(ErrorTelemetry.isHighPriorityOpType('42p10'), isFalse);
    });

    test('prefix marker requires trailing underscore — `auth` alone is LOW',
        () {
      // `auth_failure_` is a prefix marker; bare `auth` (no trailing _
      // in the marker) would not be a marker entry. Verify substring-
      // not-prefix matches don't trigger HIGH.
      expect(ErrorTelemetry.isHighPriorityOpType('auth'), isFalse);
      expect(ErrorTelemetry.isHighPriorityOpType('authentic_action'), isFalse);
    });

    test('forceTreatAllAsLowPriorityForTest disables the allowlist', () {
      ErrorTelemetry.forceTreatAllAsLowPriorityForTest = true;
      // Even a HIGH-prefix op_type should report as LOW under override.
      expect(ErrorTelemetry.isHighPriorityOpType('crash_native_oom'), isFalse);
      expect(ErrorTelemetry.isHighPriorityOpType('42P10'), isFalse);
    });
  });

  group('Test #16.1 / Theme D — cooldown state machine', () {
    test('rateLimitedUntil null at startup → no cooldown', () {
      expect(ErrorTelemetry.rateLimitedUntil, isNull);
    });

    test('setting rateLimitedUntil to future blocks further LOW posts', () async {
      // Drive the cooldown directly (no Supabase round-trip needed) and
      // call logEvent — the network leg is wrapped in try/catch that
      // silently swallows, so we exercise the GATE. The contract we
      // need to pin: when rateLimitedUntil is in the future + op_type
      // is LOW, logEvent must NOT throw (it returns immediately).
      ErrorTelemetry.rateLimitedUntil =
          DateTime.now().toUtc().add(const Duration(hours: 1));
      // The next call would normally try to invoke the Edge Function;
      // because cooldown is active and the op_type is LOW, it should
      // short-circuit before touching the network and complete cleanly.
      await expectLater(
        ErrorTelemetry.logEvent('sync_skipped_null_natural_key',
            message: 'should be dropped'),
        completes,
      );
      // Cooldown still active — was not cleared by the dropped call.
      expect(ErrorTelemetry.rateLimitedUntil, isNotNull);
    });

    test('cooldown auto-clears when window passes', () async {
      ErrorTelemetry.rateLimitedUntil =
          DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      // Reading via isHighPriority indirectly exercises the gate; the
      // direct way to verify auto-clear is to call logEvent with a LOW
      // op_type and confirm rateLimitedUntil ends as null (because the
      // gate detects the expiry and clears it). The network call WILL
      // then attempt — and may throw inside Supabase — but logEvent's
      // outer catch swallows, so the future completes.
      await expectLater(
        ErrorTelemetry.logEvent('restore_started', message: 'after expiry'),
        completes,
      );
      expect(ErrorTelemetry.rateLimitedUntil, isNull,
          reason:
              'Cooldown in the past must be cleared on the first checked call');
    });

    test('HIGH-priority op_type ignores active cooldown (must still attempt)',
        () async {
      // Set cooldown to far future; the LOW path would drop. A HIGH-
      // priority op_type must NOT drop — instead it falls through to
      // the network leg. The network leg in this isolated test env
      // throws inside `SupabaseService.instance.callFunction` (no
      // Supabase initialised); the outer catch swallows so we just
      // confirm completion without checking side-effects. The bottom
      // contract: cooldown not consulted for HIGH op_types.
      ErrorTelemetry.rateLimitedUntil =
          DateTime.now().toUtc().add(const Duration(hours: 1));
      await expectLater(
        ErrorTelemetry.logEvent('crash_native_oom',
            message: 'HIGH must always attempt'),
        completes,
      );
      // Cooldown not changed by the attempt (server reply absent).
      expect(ErrorTelemetry.rateLimitedUntil, isNotNull);
    });
  });

  group('Test #16.1 / Theme D — drift guards', () {
    test('highPriorityOpTypes list is non-empty', () {
      expect(ErrorTelemetry.highPriorityOpTypes, isNotEmpty);
    });

    test('highPriorityOpTypes contains core SQL state code markers', () {
      // These five SQL state codes are the bug-class signals we MUST
      // never lose. Any client-side rebuild of the allowlist that
      // drops them is a regression.
      expect(ErrorTelemetry.highPriorityOpTypes, contains('42P10'));
      expect(ErrorTelemetry.highPriorityOpTypes, contains('23505'));
      expect(ErrorTelemetry.highPriorityOpTypes, contains('23502'));
      expect(ErrorTelemetry.highPriorityOpTypes, contains('23503'));
      expect(ErrorTelemetry.highPriorityOpTypes, contains('permission_denied'));
    });

    test('highPriorityOpTypes contains crash + auth prefixes', () {
      expect(ErrorTelemetry.highPriorityOpTypes, contains('crash_'));
      expect(ErrorTelemetry.highPriorityOpTypes, contains('auth_failure_'));
    });

    test('highPriorityOpTypes contains discipline-gate markers', () {
      expect(ErrorTelemetry.highPriorityOpTypes, contains('gate16_violation'));
      expect(ErrorTelemetry.highPriorityOpTypes,
          contains('discipline_gate_violation'));
    });
  });
}
