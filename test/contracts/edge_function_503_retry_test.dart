import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// APK Test #15.1 / Bugs G + H — Edge Function 503 BOOT_ERROR retry.
/// APK Test #15.3 / Bug 7c4e1a — bumped to TWO retries [1500, 4000]
/// after ai-proxy logs showed 20+ s cold-starts.
///
/// Telemetry showed `push_snapshot FunctionException(status: 503, code:
/// BOOT_ERROR, message: Function failed to start)` and edge-function
/// logs showed `ai-proxy` 502 BAD_GATEWAY pairs followed by a 20219 ms
/// warm-start success. Edge Function logs confirm daily-snapshot takes
/// ~40 seconds per call (Gemini extraction inline) and ai-proxy
/// cold-start can take 20+ seconds (Gemini model load + tools
/// registry); when multiple users hit one of these simultaneously, the
/// first calls get a cold-start 502/503 while the function spins up.
///
/// Fix — in SupabaseService.callFunction, catch FunctionException with
/// status 502 or 503 and retry up to TWICE on the const backoff
/// schedule `_coldStartBackoffsMs = [1500, 4000]`. Persistent 5xx
/// still surfaces to caller; the retry only handles transient
/// cold-start blips. Auth errors (401/403) are NOT retried.
///
/// closes-diagnose: 2026-05-12-ai-proxy-retry-undersized-7c4e1a
/// supersedes-diagnose: 2026-05-12-edge-function-503-retry-0a7b9f
void main() {
  late String src;

  setUpAll(() {
    src = File('lib/core/services/supabase_service.dart').readAsStringSync();
  });

  group('callFunction 503 retry', () {
    test('FunctionException catch is present in callFunction', () {
      // Source-grep the try/catch around the invoke call.
      expect(
        src.contains('on FunctionException catch (e)'),
        isTrue,
        reason:
            'callFunction must wrap client.functions.invoke in a try block '
            'that catches FunctionException so the retry path can engage.',
      );
    });

    test('retry triggers ONLY on 502 + 503 (cold-start signatures)', () {
      expect(
        src.contains('e.status == 502 || e.status == 503'),
        isTrue,
        reason:
            'Retry must be gated on FunctionException.status of 502 or 503. '
            'Other status codes (401 auth, 400 validation, etc.) must NOT '
            'retry — they need caller handling or are not transient.',
      );
    });

    test('backoff schedule is the pinned [1500, 4000] ms list', () {
      // Bug 7c4e1a: bumped from single 1500 ms retry to two retries on
      // [1500, 4000]. The const list must contain both values; either
      // missing means the schedule has drifted from the pin.
      expect(src.contains('_coldStartBackoffsMs'), isTrue,
          reason:
              'callFunction must declare a _coldStartBackoffsMs const list '
              'so the backoff schedule is auditable.');
      final listMatch = RegExp(
        r'_coldStartBackoffsMs\s*=\s*\[(.*?)\]',
        dotAll: true,
      ).firstMatch(src);
      expect(listMatch, isNotNull,
          reason:
              '_coldStartBackoffsMs must be declared as a const list literal.');
      final body = listMatch!.group(1)!;
      expect(body.contains('1500'), isTrue,
          reason: 'First backoff entry must be 1500 ms (initial retry).');
      expect(body.contains('4000'), isTrue,
          reason: 'Second backoff entry must be 4000 ms (covers 20+ s cold-start).');
    });

    test('forbidden: unconditional retry (would mask sustained outages)', () {
      // A naive `try { invoke } catch (_) { invoke }` would retry on EVERY
      // exception, masking auth failures + sustained outages. Pin that
      // the retry happens only inside the 502/503 branch.
      //
      // Bug 7c4e1a refactor — retry is now a loop with ONE textual
      // `client.functions.invoke(` literal that runs up to 3 times.
      // We pin invokeCount to exactly 1 to forbid accidental
      // duplicate-invoke regression (e.g. inlining retries).
      final invokeCount =
          RegExp(r'client\.functions\.invoke\(').allMatches(src).length;
      expect(invokeCount, equals(1),
          reason:
              'callFunction body should contain exactly 1 client.functions.'
              'invoke call (single literal inside a bounded retry loop). '
              'Found $invokeCount. If more, audit for unsafe retry semantics.');
    });

    test('rethrow happens on non-cold-start FunctionExceptions', () {
      // Bug 7c4e1a refactor — rethrow guard renamed from
      // `isColdStart502_503` to `isColdStart`. Pin the new pattern + the
      // attempt-budget exhaustion condition.
      final rethrowGate = RegExp(
        r'if\s*\(\s*!isColdStart[^)]*\|\|[^)]*attempt[^)]*\)[\s\S]{0,40}?rethrow',
      );
      expect(rethrowGate.hasMatch(src), isTrue,
          reason:
              'Non-cold-start FunctionExceptions OR exhausted retry budget '
              'must rethrow so callers can handle 401 auth / 4xx validation '
              '/ persistent outage.');
    });

    test('each retry emits edge_function_cold_start_retry telemetry', () {
      // Ops visibility: every retry must log to ErrorTelemetry.logEvent
      // so cold-start frequency surfaces in client_errors.
      expect(src.contains("'edge_function_cold_start_retry'"), isTrue,
          reason:
              'Retry path must emit ErrorTelemetry.logEvent with op_type '
              "'edge_function_cold_start_retry' for ops visibility.");
      // Telemetry must be unawaited so the retry latency isn't doubled.
      final unawaitedTelemetry = RegExp(
        r'unawaited\(\s*ErrorTelemetry\.logEvent\(\s*[\x27"]edge_function_cold_start_retry',
      );
      expect(unawaitedTelemetry.hasMatch(src), isTrue,
          reason:
              'edge_function_cold_start_retry telemetry must be unawaited '
              'so the log-client-error round-trip does not double retry latency.');
    });
  });
}
