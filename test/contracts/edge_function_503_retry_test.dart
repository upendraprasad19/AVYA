import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// APK Test #15.1 / Bugs G + H — Edge Function 503 BOOT_ERROR retry.
/// APK Test #15.3 / Bug 7c4e1a — bumped to TWO retries [1500, 4000].
/// APK Test #15.5 / Bug c01d57 — bumped to THREE retries
/// [2000, 6000, 12000] after 2026-05-15 09:33 IST logs showed 3
/// consecutive 502s; also widened trigger set to {502, 503, 504}.
///
/// Telemetry showed `push_snapshot FunctionException(status: 503, code:
/// BOOT_ERROR, message: Function failed to start)` and edge-function
/// logs showed `ai-proxy` 502 BAD_GATEWAY pairs followed by a 20219 ms
/// warm-start success. Edge Function logs confirm daily-snapshot takes
/// ~40 seconds per call (Gemini extraction inline) and ai-proxy
/// cold-start can take 20+ seconds (Gemini model load + tools
/// registry).
///
/// Fix — in SupabaseService.retryColdStart (delegated from
/// callFunction), catch FunctionException with status 502, 503, or 504
/// and retry up to THREE times on the const backoff schedule
/// `_coldStartBackoffsMs = [2000, 6000, 12000]`. Persistent 5xx still
/// surfaces to caller; the retry only handles transient cold-start
/// blips. Auth errors (401/403) and 500 are NOT retried.
///
/// closes-diagnose: 2026-05-15-ai-proxy-cold-start-budget-c01d57
/// supersedes-diagnose: 2026-05-12-ai-proxy-retry-undersized-7c4e1a
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

    test('retry triggers on 502/503/504 (cold-start) + opt-in 500 (Theme I)',
        () {
      // Bug c01d57 (2026-05-15): widened from {502, 503} to add 504
      // since cold-start gateway timeouts can surface as either 502
      // (gateway gave up) or 504 (gateway timed out).
      //
      // Theme I (closes-diagnose 599d49, 2026-05-22): extended the
      // predicate to ALSO retry 500 when the caller opts in via
      // `retryOn500: true` (ai-proxy returns 500 on transient Gemini
      // upstream timeouts which ARE retry-worthy). 500 retry stays
      // off by default for every other Edge Function where 500 is a
      // caller bug (log-client-error validation, ai-media-proxy
      // bucket misconfig).
      final hasGate = src.contains(
              'e.status == 502 || e.status == 503 || e.status == 504') ||
          src.contains(
              'e.status == 502 ||\n            e.status == 503 ||\n            e.status == 504');
      expect(hasGate, isTrue,
          reason:
              'Retry must be gated on FunctionException.status of 502, 503, '
              'OR 504. Other status codes (401 auth, 400 validation) must '
              'NOT retry. 500 retry is opt-in via retryOn500 — see Theme I.');
      // 500 must be OPT-IN only — guarded by retryOn500 flag. The bare
      // `e.status == 500` predicate (without retryOn500 &&) is forbidden;
      // it would auto-retry every server runtime error.
      expect(
        RegExp(r'retryOn500\s*&&\s*e\.status\s*==\s*500').hasMatch(src),
        isTrue,
        reason: 'Theme I — 500 retry must appear ONLY behind the retryOn500 '
            'guard. Pattern `(retryOn500 && e.status == 500)` must exist.',
      );
      // Forbidden: an unconditional `e.status == 500` predicate (no
      // retryOn500 prefix). The conditional form passes this check
      // because `e.status == 500` is preceded by `retryOn500 && `.
      // We assert by stripping all `retryOn500 && e.status == 500`
      // occurrences first, then checking no bare `e.status == 500`
      // remains.
      final stripped =
          src.replaceAll(RegExp(r'retryOn500\s*&&\s*e\.status\s*==\s*500'), '');
      expect(
        stripped.contains('e.status == 500'),
        isFalse,
        reason:
            'No UNCONDITIONAL `e.status == 500` predicate may exist — 500 '
            'retry must always be behind the retryOn500 opt-in guard.',
      );
    });

    test('backoff schedule is the pinned [2000, 6000, 12000] ms list', () {
      // Bug c01d57: bumped from [1500, 4000] (2 retries) to [2000, 6000,
      // 12000] (3 retries) after 09:33 IST logs showed 3 consecutive
      // 502s exhausting the previous schedule. Total wait window ~20 s
      // now covers the 20.2 s worst-case warm-start.
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
      expect(body.contains('2000'), isTrue,
          reason: 'First backoff entry must be 2000 ms.');
      expect(body.contains('6000'), isTrue,
          reason: 'Second backoff entry must be 6000 ms.');
      expect(body.contains('12000'), isTrue,
          reason: 'Third backoff entry must be 12000 ms (covers 20 s budget).');
    });

    test('forbidden: unconditional retry (would mask sustained outages)', () {
      // A naive `try { invoke } catch (_) { invoke }` would retry on EVERY
      // exception, masking auth failures + sustained outages. Pin that
      // the retry happens only inside the 502/503/504 branch.
      //
      // Bug 7c4e1a refactor — retry is a loop with ONE textual
      // `client.functions.invoke(` literal (inside callFunction's
      // delegation to retryColdStart, which itself calls the injected
      // invoker via `invoke()`).
      final invokeCount =
          RegExp(r'client\.functions\.invoke\(').allMatches(src).length;
      expect(invokeCount, equals(1),
          reason:
              'supabase_service.dart should contain exactly 1 client.'
              'functions.invoke literal (single call site in callFunction '
              'delegating into retryColdStart). Found $invokeCount. If more, '
              'audit for unsafe retry semantics.');
    });

    test('rethrow happens on non-cold-start FunctionExceptions', () {
      // Bug 7c4e1a refactor — rethrow guard renamed from
      // `isColdStart502_503` to `isColdStart`.
      // audit-2026-05-16 / Obs 6 — retry helper refactored to support
      // dual retry tracks (cold-start + storage-race). Old pattern
      // `if (!isColdStart || attempt >= ...) rethrow` is gone; new
      // shape uses two if/continue blocks and a bare `rethrow` at the
      // bottom of the catch:
      //   if (isColdStart) { ... continue; }
      //   if (isStorageRace) { ... continue; }
      //   rethrow;
      // Contract unchanged: anything that isn't cold-start or storage-
      // race exits the catch via rethrow.
      final hasColdStartGate = src.contains('if (isColdStart)');
      final hasStorageRaceGate = src.contains('if (isStorageRace)');
      final hasBareRethrow =
          RegExp(r'\bcontinue;\s*\}\s*rethrow;').hasMatch(src);
      expect(hasColdStartGate && hasStorageRaceGate && hasBareRethrow, isTrue,
          reason:
              'Non-cold-start, non-storage-race FunctionExceptions must '
              'rethrow so callers can handle 401 auth / 4xx validation / '
              'persistent outage. Looked for the two if/continue blocks + '
              'bare rethrow shape.');
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
