import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the infinite loop bug (Fix 2, 2026-04-07).
///
/// **ROOT CAUSE:** Two independent retry layers compounded into 30+ requests
/// per user tap:
///   1. SupabaseService.callFunction() retried on 401 (refresh + retry)
///   2. AiCoachProvider.send() caught auth error, recursively called send()
///   3. Send button had zero debounce — rapid taps slipped through
///
/// These tests scan source code to ensure the architectural guardrails
/// remain in place. If anyone re-introduces a retry layer or removes
/// the debounce, these tests break immediately.
void main() {
  final libDir = Directory('lib');

  Map<String, String> readAllDartFiles(Directory dir) {
    final files = <String, String>{};
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        files[entity.path] = entity.readAsStringSync();
      }
    }
    return files;
  }

  late Map<String, String> allSources;

  setUpAll(() {
    expect(libDir.existsSync(), isTrue, reason: 'Run from project root');
    allSources = readAllDartFiles(libDir);
  });

  // ── Fix 2A: No auto-retry in callFunction ────────────────────

  group('Guard: SupabaseService.callFunction has no 401 retry', () {
    test('callFunction docstring does not promise retry behavior', () {
      final source = allSources.entries
          .firstWhere((e) => e.key.contains('supabase_service.dart'))
          .value;

      // The docstring above callFunction must NOT mention "retry" or "401"
      // since the implementation is now single-attempt.
      final docStart = source.indexOf('/// Shortcut to invoke a Supabase Edge Function');
      final docEnd = source.indexOf('Future<FunctionResponse> callFunction(');
      expect(docStart, isNot(-1));
      expect(docEnd, isNot(-1));

      final docstring = source.substring(docStart, docEnd);
      expect(docstring.toLowerCase().contains('retry'), isFalse,
          reason: 'callFunction docstring must not mention "retry" — implementation is single-attempt');
      expect(docstring.contains('401'), isFalse,
          reason: 'callFunction docstring must not mention "401" — no retry logic exists');
    });

    test('callFunction does NOT contain 401 retry logic', () {
      final source = allSources.entries
          .firstWhere((e) => e.key.contains('supabase_service.dart'))
          .value;

      // Must NOT have the old retry pattern:
      // if (response.status == 401) { ... refreshSession() ... invoke() }
      expect(source.contains('response.status == 401'), isFalse,
          reason:
              'supabase_service.callFunction must NOT retry on 401. '
              'The old retry here compounded with AiCoachProvider retry '
              'to create 30+ duplicate requests.');
    });

    test('callFunction invokes edge function at most THREE times (two retries max)',
        () {
      // APK Test #15.3 / Bug 7c4e1a — bumped to TWO retries on
      // cold-start 502/503 (backoff schedule [1500ms, 4000ms]) because
      // ai-proxy cold-start can take 20+ seconds; single 1500 ms retry
      // wasn't enough wait time. Edge-function logs showed two
      // consecutive 502 BAD_GATEWAY at 05:08:05/05:08:13 UTC followed
      // by a 20219 ms warm-start success.
      //
      // Prior bound (APK Test #15.1 / Bug G+H) was at most 2; this
      // raises it to at most 3 (1 initial + 2 retries). The original
      // 2026-04-07 401-recursion guard is preserved in the tests above
      // — this is a different class (bounded loop, status-gated, no
      // recursion).
      //
      // The retry path uses a loop, so we only expect 1 textual
      // `client.functions.invoke(` literal in the source — the
      // assertion below tolerates the implementation choice (1 literal
      // in a loop OR up to 3 inline retries).
      final source = allSources.entries
          .firstWhere((e) => e.key.contains('supabase_service.dart'))
          .value;

      final callFnStart =
          source.indexOf('Future<FunctionResponse> callFunction(');
      expect(callFnStart, isNot(-1), reason: 'callFunction must exist');

      final callFnBody = source.substring(callFnStart);
      final invokeCount =
          RegExp(r'client\.functions\.invoke\(').allMatches(callFnBody).length;

      expect(invokeCount, lessThanOrEqualTo(3),
          reason:
              'callFunction must call client.functions.invoke AT MOST 3 '
              'times (first attempt + two 502/503 cold-start retries). '
              'Found $invokeCount. closes-diagnose: 2026-05-12-ai-proxy-'
              'retry-undersized-7c4e1a');
      expect(invokeCount, greaterThanOrEqualTo(1),
          reason:
              'callFunction must call client.functions.invoke at least once.');
    });

    test('retry uses a const backoff schedule with exactly two entries', () {
      // Backoff schedule [1500ms, 4000ms] is the contract. Both values
      // must be present, must be ascending, and the list must have
      // exactly two entries (1 initial + 2 retries = 3 total
      // invocations). Bumping to 3 retries silently would re-introduce
      // the runaway-retry risk — keep it pinned here.
      final source = allSources.entries
          .firstWhere((e) => e.key.contains('supabase_service.dart'))
          .value;

      expect(source, contains('_coldStartBackoffsMs'),
          reason:
              'callFunction must declare _coldStartBackoffsMs const list '
              'so the backoff schedule is readable and pinned by this test.');

      final listMatch = RegExp(
        r'_coldStartBackoffsMs\s*=\s*\[(.*?)\]',
        dotAll: true,
      ).firstMatch(source);
      expect(listMatch, isNotNull,
          reason:
              '_coldStartBackoffsMs must be declared as a const list literal');
      final entries = listMatch!
          .group(1)!
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      expect(entries.length, 2,
          reason:
              'Backoff schedule must have exactly 2 entries (= 2 retries). '
              'Found ${entries.length}: $entries');
      // Pinned values from the diagnose-doc.
      expect(entries[0], '1500',
          reason: 'First retry delay must be 1500 ms');
      expect(entries[1], '4000',
          reason: 'Second retry delay must be 4000 ms');
    });

    test('retry path emits edge_function_cold_start_retry telemetry', () {
      // Each retry must log to ErrorTelemetry.logEvent so ops can see
      // cold-start frequency in client_errors. Telemetry must be
      // unawaited so it doesn't double the retry latency.
      final source = allSources.entries
          .firstWhere((e) => e.key.contains('supabase_service.dart'))
          .value;

      final callFnStart =
          source.indexOf('Future<FunctionResponse> callFunction(');
      final callFnBody = source.substring(callFnStart);

      expect(callFnBody, contains("'edge_function_cold_start_retry'"),
          reason:
              'Retry path must emit ErrorTelemetry.logEvent with op_type '
              "'edge_function_cold_start_retry' for ops visibility.");
      // Confirm the telemetry call is wrapped in unawaited(...) so we
      // don't await a network round-trip inside the retry loop.
      final unawaitedTelemetryRegex = RegExp(
        r'unawaited\(\s*ErrorTelemetry\.logEvent\(\s*[\x27"]edge_function_cold_start_retry',
        multiLine: true,
      );
      expect(unawaitedTelemetryRegex.hasMatch(callFnBody), isTrue,
          reason:
              'edge_function_cold_start_retry telemetry must be wrapped in '
              'unawaited() so the retry delay is not doubled by the '
              'log-client-error round-trip.');
    });

    test('non-502/503 errors still rethrow (no retry on auth/validation)', () {
      // Defence-in-depth: the retry path must rethrow when the status
      // gate fails. A regression that drops `rethrow` would retry every
      // 4xx (auth, validation, payload-too-large) and re-introduce the
      // pre-2026-04-07 compounding-retry class.
      final source = allSources.entries
          .firstWhere((e) => e.key.contains('supabase_service.dart'))
          .value;

      final callFnStart =
          source.indexOf('Future<FunctionResponse> callFunction(');
      final callFnBody = source.substring(callFnStart);

      // After the 502/503 gate fails, we must rethrow.
      // Tolerant pattern: `if (!isColdStart` followed by `rethrow` on a
      // nearby line.
      final rethrowAfterGate = RegExp(
        r'if\s*\(\s*!isColdStart[^)]*\)[^;]*rethrow',
        dotAll: true,
      );
      expect(rethrowAfterGate.hasMatch(callFnBody), isTrue,
          reason:
              'Non-cold-start FunctionException must rethrow. Missing '
              'rethrow re-introduces unbounded-retry risk for 4xx.');
    });

    test('any retry path is gated on 502 OR 503 status (not unconditional)',
        () {
      // If 2+ invokes are present, they must be inside a `if (e.status
      // == 502 || e.status == 503)` branch — never unconditional.
      final source = allSources.entries
          .firstWhere((e) => e.key.contains('supabase_service.dart'))
          .value;

      final callFnStart =
          source.indexOf('Future<FunctionResponse> callFunction(');
      final callFnBody = source.substring(callFnStart);
      final invokeCount =
          RegExp(r'client\.functions\.invoke\(').allMatches(callFnBody).length;

      if (invokeCount >= 2) {
        // Must have the 502/503 gate
        expect(
          callFnBody.contains('e.status == 502 || e.status == 503'),
          isTrue,
          reason:
              'callFunction has 2+ invocations but no 502/503 gate — that '
              'is the 2026-04-07 retry-loop bug class. Add `if (e.status '
              '== 502 || e.status == 503)` around the retry.',
        );
      }
    });
  });

  // ── Fix 2B: No recursive send() in AiCoachProvider ───────────

  group('Guard: AiCoachProvider.send has no recursive call', () {
    test('send() does NOT call itself recursively', () {
      final source = allSources.entries
          .firstWhere((e) => e.key.contains('ai_coach_provider.dart'))
          .value;

      // Extract the send() method body. Signature is multi-line:
      //   Future<void> send(
      //     String message, { ... }
      // — search for the opening line, not the inlined form.
      final sendStart = source.indexOf('Future<void> send(');
      expect(sendStart, isNot(-1), reason: 'send() method must exist');

      // Get everything from send() declaration to the next top-level method
      // We look for 'return send(' which is the recursive call pattern
      final sendBody = source.substring(sendStart);

      // Should NOT contain 'return send(' — that's the recursive call
      expect(sendBody.contains('return send('), isFalse,
          reason:
              'send() must NOT call itself recursively. '
              'The old recursive pattern caused infinite message loops.');

      // Should NOT contain '.send(message' either (delegate-style recursion)
      final delegateRecursion = RegExp(r'\.send\(message,?\s*mode:');
      expect(delegateRecursion.hasMatch(sendBody), isFalse,
          reason: 'send() must not delegate back to itself');
    });

    test('_hasRetriedAuth field no longer exists', () {
      final source = allSources.entries
          .firstWhere((e) => e.key.contains('ai_coach_provider.dart'))
          .value;

      expect(source.contains('_hasRetriedAuth'), isFalse,
          reason:
              '_hasRetriedAuth flag was part of the old retry mechanism. '
              'It should be removed since we no longer retry.');
    });

    test('auth error path refreshes token but shows error (no retry)', () {
      final source = allSources.entries
          .firstWhere((e) => e.key.contains('ai_coach_provider.dart'))
          .value;

      // Must still call refreshSession() on auth errors (to fix the token
      // for the NEXT user-initiated send). Note: keyword changed during
      // 2026-04-24 auth refactor — was `ensureFreshToken`, now
      // `refreshSession()`. Both names mean the same thing.
      expect(source, contains('refreshSession()'),
          reason:
              'Auth error path must still refresh token for next attempt');

      // Must surface "Session expired" copy to the user (not silently retry)
      expect(source, contains('Session expired'),
          reason:
              'Auth error must surface a "Session expired" message to user');
    });
  });

  // ── Fix 2C: Debounce on send button ──────────────────────────

  group('Guard: AI coach screen has send debounce', () {
    test('_doSend checks a local sending flag before proceeding', () {
      final source = allSources.entries
          .firstWhere((e) => e.key.contains('ai_coach_screen.dart'))
          .value;

      // Must have a local sending flag (synchronous, not async provider state)
      expect(source, contains('_localSending'),
          reason:
              'ai_coach_screen must have a _localSending flag to debounce taps. '
              'Provider state propagation is async — rapid taps slip through.');
    });

    test('_doSend returns early if _localSending is true', () {
      final source = allSources.entries
          .firstWhere((e) => e.key.contains('ai_coach_screen.dart'))
          .value;

      // The method must check the flag before doing anything
      // Pattern: if (_localSending) return;
      expect(source, contains('if (_localSending) return'),
          reason: '_doSend must bail out immediately if already sending');
    });

    test('text field is cleared before async send (not after)', () {
      final source = allSources.entries
          .firstWhere((e) => e.key.contains('ai_coach_screen.dart'))
          .value;

      // Find _doSend method
      final doSendStart = source.indexOf('void _doSend(');
      expect(doSendStart, isNot(-1));

      final doSendBody = source.substring(doSendStart, doSendStart + 500);

      // _messageController.clear() must come BEFORE the async send() call
      final clearIdx = doSendBody.indexOf('_messageController.clear()');
      final sendIdx = doSendBody.indexOf('.send(');

      expect(clearIdx, isNot(-1), reason: 'Must clear text field in _doSend');
      expect(sendIdx, isNot(-1), reason: 'Must call send() in _doSend');
      expect(clearIdx, lessThan(sendIdx),
          reason:
              'Text field must be cleared BEFORE async send() starts. '
              'Otherwise, rapid taps re-read the same text.');
    });

    test('_localSending is reset in whenComplete callback', () {
      final source = allSources.entries
          .firstWhere((e) => e.key.contains('ai_coach_screen.dart'))
          .value;

      // Must reset the flag when the future completes
      expect(source, contains('whenComplete'),
          reason:
              '_localSending must be reset via whenComplete to handle '
              'both success and error paths');
    });
  });

  // ── Meta: No other retry layers exist ──────────────────────────

  group('Guard: no hidden retry layers for Edge Function calls', () {
    test('no file has recursive callFunction retry', () {
      for (final entry in allSources.entries) {
        final source = entry.value;
        // Check for patterns like: response.status == 401 + functions.invoke
        // within the same narrow scope (suggesting retry)
        if (entry.key.contains('supabase_service.dart')) {
          // Already checked above
          continue;
        }
        // No other file should be wrapping callFunction with its own 401 retry
        final has401Retry = source.contains('status == 401') &&
            source.contains('callFunction(');
        expect(has401Retry, isFalse,
            reason:
                '${entry.key}: Contains 401 check + callFunction call. '
                'Retry logic must only exist in one place to prevent compounding.');
      }
    });
  });
}
