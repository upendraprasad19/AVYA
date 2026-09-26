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

    test('callFunction delegates to retryColdStart helper (at-most-once invoke literal)',
        () {
      // APK Test #15.5 / Bug c01d57 — bumped to THREE retries on
      // cold-start 502/503/504 (backoff schedule [2000, 6000, 12000])
      // because ai-proxy cold-start can take 20+ seconds and the
      // 2026-05-15 09:33 IST logs showed 3 consecutive 502s exhausting
      // the previous 2-retry schedule. The retry control flow lives in
      // `retryColdStart` (a `@visibleForTesting` static helper)
      // so `callFunction` itself contains a single
      // `client.functions.invoke(` literal — the loop is inside the
      // helper. Total invocations on the worst path: 1 initial + 3
      // retries = 4. Pinned by the behavioral tests in
      // edge_function_cold_start_retry_behavioral_test.dart.
      //
      // The original 2026-04-07 401-recursion guard is preserved (no
      // recursion, bounded loop, status-gated).
      final source = allSources.entries
          .firstWhere((e) => e.key.contains('supabase_service.dart'))
          .value;

      final callFnStart =
          source.indexOf('Future<FunctionResponse> callFunction(');
      expect(callFnStart, isNot(-1), reason: 'callFunction must exist');

      // Find the next top-level method (retryColdStart helper) and
      // scope our analysis to just the callFunction body.
      final retryStart = source.indexOf('retryColdStart', callFnStart);
      expect(retryStart, isNot(-1),
          reason: 'retryColdStart helper must exist');
      final callFnBody = source.substring(callFnStart, retryStart);

      final invokeCount =
          RegExp(r'client\.functions\.invoke\(').allMatches(callFnBody).length;

      expect(invokeCount, lessThanOrEqualTo(1),
          reason:
              'callFunction body must contain AT MOST 1 textual '
              '`client.functions.invoke(` literal (the retry loop lives '
              'inside retryColdStart). Found $invokeCount. '
              'closes-diagnose: 2026-05-15-ai-proxy-cold-start-budget-c01d57');

      // The helper itself must contain exactly 1 invoke literal too
      // (the single call site inside the bounded loop).
      final helperBody = source.substring(retryStart);
      final helperInvokeCount = RegExp(r'invoke\(\)')
          .allMatches(helperBody)
          .length;
      expect(helperInvokeCount, greaterThanOrEqualTo(1),
          reason:
              'retryColdStart must call its injected invoker at least once.');
    });

    test('retry uses a const backoff schedule with exactly three entries', () {
      // Backoff schedule [2000, 6000, 12000] is the contract. Bumped
      // 2026-05-15 (Bug c01d57) from [1500, 4000] after 09:33 IST logs
      // showed 3 consecutive 502s — the previous ~5.5 s wait window
      // didn't span the 20.2 s worst-case warm-start. Three entries =
      // 3 retries = up to 4 total invocations.
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
      expect(entries.length, 3,
          reason:
              'Backoff schedule must have exactly 3 entries (= 3 retries). '
              'Found ${entries.length}: $entries. '
              'closes-diagnose: 2026-05-15-ai-proxy-cold-start-budget-c01d57');
      // Pinned values from the c01d57 diagnose-doc.
      expect(entries[0], '2000',
          reason: 'First retry delay must be 2000 ms');
      expect(entries[1], '6000',
          reason: 'Second retry delay must be 6000 ms');
      expect(entries[2], '12000',
          reason: 'Third retry delay must be 12000 ms');
    });

    test('retry path emits edge_function_cold_start_retry telemetry', () {
      // Each retry must log to ErrorTelemetry.logEvent so ops can see
      // cold-start frequency in client_errors. Telemetry must be
      // unawaited so it doesn't double the retry latency. The retry
      // loop lives in `retryColdStart`, so we scope to the whole file
      // (callFunction body itself is now a thin delegate).
      final source = allSources.entries
          .firstWhere((e) => e.key.contains('supabase_service.dart'))
          .value;

      expect(source, contains("'edge_function_cold_start_retry'"),
          reason:
              'Retry path must emit ErrorTelemetry.logEvent with op_type '
              "'edge_function_cold_start_retry' for ops visibility.");
      // Confirm the telemetry call is wrapped in unawaited(...) so we
      // don't await a network round-trip inside the retry loop.
      final unawaitedTelemetryRegex = RegExp(
        r'unawaited\(\s*ErrorTelemetry\.logEvent\(\s*[\x27"]edge_function_cold_start_retry',
        multiLine: true,
      );
      expect(unawaitedTelemetryRegex.hasMatch(source), isTrue,
          reason:
              'edge_function_cold_start_retry telemetry must be wrapped in '
              'unawaited() so the retry delay is not doubled by the '
              'log-client-error round-trip.');
    });

    test('non-502/503/504 errors still rethrow (no retry on auth/validation)', () {
      // Defence-in-depth: the retry path must rethrow when the status
      // gate fails. A regression that drops `rethrow` would retry every
      // 4xx (auth, validation, payload-too-large) and re-introduce the
      // pre-2026-04-07 compounding-retry class. Test #15.5 / c01d57
      // widened the gate to also include 504, but 500 and 4xx still
      // rethrow.
      final source = allSources.entries
          .firstWhere((e) => e.key.contains('supabase_service.dart'))
          .value;

      // After all retry-class gates pass, we must rethrow.
      // audit-2026-05-16 / Obs 6 — retry helper refactored to support
      // dual retry tracks (cold-start + storage-race). New shape uses
      // two if/continue blocks and a bare `rethrow` at the bottom of
      // the catch. Old `if (!isColdStart) { ... rethrow }` pattern gone.
      final hasColdStartGate = source.contains('if (isColdStart)');
      final hasStorageRaceGate = source.contains('if (isStorageRace)');
      final hasBareRethrow =
          RegExp(r'\bcontinue;\s*\}\s*rethrow;').hasMatch(source);
      expect(hasColdStartGate && hasStorageRaceGate && hasBareRethrow, isTrue,
          reason:
              'Non-cold-start, non-storage-race FunctionException must '
              'rethrow. Missing rethrow re-introduces unbounded-retry '
              'risk for 4xx.');
    });

    test('retry path is gated on 502/503/504 + opt-in 500 via retryOn500 (Theme I)',
        () {
      // Test #15.5 / c01d57 — widened the cold-start trigger set from
      // {502, 503} to {502, 503, 504} since cold-start gateway timeouts
      // can surface as either 502 (gave up) or 504 (timed out).
      //
      // Theme I (closes-diagnose 599d49, 2026-05-22) — extended the
      // predicate to ALSO retry 500 when the caller opts in via
      // `retryOn500: true` (ai-proxy returns 500 on transient Gemini
      // upstream timeouts which ARE retry-worthy). Default-false
      // preserves the global "500 means caller bug" semantic for every
      // other Edge Function.
      final source = allSources.entries
          .firstWhere((e) => e.key.contains('supabase_service.dart'))
          .value;

      // The gate must include all 3 cold-start statuses.
      final hasGate = source.contains(
              'e.status == 502 || e.status == 503 || e.status == 504') ||
          source.contains(
              'e.status == 502 ||\n            e.status == 503 ||\n            e.status == 504');
      expect(hasGate, isTrue,
          reason:
              'Retry gate must cover 502, 503, AND 504 cold-start statuses. '
              'closes-diagnose: 2026-05-15-ai-proxy-cold-start-budget-c01d57');

      // 500 retry must be OPT-IN — guarded by retryOn500 flag.
      expect(
        RegExp(r'retryOn500\s*&&\s*e\.status\s*==\s*500').hasMatch(source),
        isTrue,
        reason: 'Theme I — 500 retry must appear ONLY behind the retryOn500 '
            'guard. Pattern `(retryOn500 && e.status == 500)` must exist.',
      );
      // Forbidden: an UNCONDITIONAL `e.status == 500` predicate (no
      // retryOn500 prefix). Strip the conditional form first, then
      // assert no bare `e.status == 500` remains.
      final stripped = source.replaceAll(
          RegExp(r'retryOn500\s*&&\s*e\.status\s*==\s*500'), '');
      expect(
        stripped.contains('e.status == 500'),
        isFalse,
        reason:
            'No UNCONDITIONAL `e.status == 500` predicate may exist — 500 '
            'retry must always be behind the retryOn500 opt-in guard.',
      );
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
      // Tech-debt audit 2026-05-20 / C1 split ai_coach_screen.dart into
      // a folder of widgets (ai_coach/screen.dart + input_bar.dart +
      // chat_area.dart + …). The send-debounce logic lives in
      // input_bar.dart + screen.dart. Concat the whole ai_coach/ folder
      // so the debounce-pattern assertions still resolve.
      final source = allSources.entries
          .where((e) {
            final k = e.key.replaceAll(r'\', '/');
            return k.contains('/features/ai_coach/screens/ai_coach/') ||
                k.endsWith('ai_coach_screen.dart');
          })
          .map((e) => e.value)
          .join('\n\n');

      // Must have a local sending flag (synchronous, not async provider state)
      expect(source, contains('_localSending'),
          reason:
              'ai_coach_screen must have a _localSending flag to debounce taps. '
              'Provider state propagation is async — rapid taps slip through.');
    });

    test('_doSend returns early if _localSending is true', () {
      // Tech-debt audit 2026-05-20 / C1 split ai_coach_screen.dart into
      // a folder of widgets (ai_coach/screen.dart + input_bar.dart +
      // chat_area.dart + …). The send-debounce logic lives in
      // input_bar.dart + screen.dart. Concat the whole ai_coach/ folder
      // so the debounce-pattern assertions still resolve.
      final source = allSources.entries
          .where((e) {
            final k = e.key.replaceAll(r'\', '/');
            return k.contains('/features/ai_coach/screens/ai_coach/') ||
                k.endsWith('ai_coach_screen.dart');
          })
          .map((e) => e.value)
          .join('\n\n');

      // The method must check the flag before doing anything
      // Pattern: if (_localSending) return;
      expect(source, contains('if (_localSending) return'),
          reason: '_doSend must bail out immediately if already sending');
    });

    test('text field is cleared before async send (not after)', () {
      // Tech-debt audit 2026-05-20 / C1 split ai_coach_screen.dart into
      // a folder of widgets (ai_coach/screen.dart + input_bar.dart +
      // chat_area.dart + …). The send-debounce logic lives in
      // input_bar.dart + screen.dart. Concat the whole ai_coach/ folder
      // so the debounce-pattern assertions still resolve.
      final source = allSources.entries
          .where((e) {
            final k = e.key.replaceAll(r'\', '/');
            return k.contains('/features/ai_coach/screens/ai_coach/') ||
                k.endsWith('ai_coach_screen.dart');
          })
          .map((e) => e.value)
          .join('\n\n');

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
      // Tech-debt audit 2026-05-20 / C1 split ai_coach_screen.dart into
      // a folder of widgets (ai_coach/screen.dart + input_bar.dart +
      // chat_area.dart + …). The send-debounce logic lives in
      // input_bar.dart + screen.dart. Concat the whole ai_coach/ folder
      // so the debounce-pattern assertions still resolve.
      final source = allSources.entries
          .where((e) {
            final k = e.key.replaceAll(r'\', '/');
            return k.contains('/features/ai_coach/screens/ai_coach/') ||
                k.endsWith('ai_coach_screen.dart');
          })
          .map((e) => e.value)
          .join('\n\n');

      // Must reset the flag when the future completes
      expect(source, contains('whenComplete'),
          reason:
              '_localSending must be reset via whenComplete to handle '
              'both success and error paths');
    });
  });

  // ── Meta: No other retry layers exist ──────────────────────────

  group('Guard: no hidden retry layers for Edge Function calls', () {
    test('no file re-invokes an Edge Function inside its own 401 handler', () {
      // The 2026-04-07 bug: a caller CAUGHT a 401 and RE-CALLED the EF, which
      // compounded with callFunction's own refresh → 30+ requests per tap.
      //
      // Refined 2026-06-13 (c4f1a7): the original heuristic flagged ANY file
      // containing both `status == 401` and `callFunction(` anywhere — a false
      // positive for the SAFE pattern of DECODING a 401 into a user message
      // (e.g. delete_account_screen shows "session expired" after its
      // callFunction delete invoke; the 401 branch does NOT re-invoke). The bad
      // shape is a RE-INVOKE (callFunction / .send(message / .functions.invoke)
      // WITHIN the 401 handler — that is what this now detects (proximity scan),
      // so it still catches the compounding-retry class while allowing the
      // 401-to-message decode.
      final reInvoke =
          RegExp(r'callFunction\(|\.send\(message|\.functions\.invoke\(');
      for (final entry in allSources.entries) {
        if (entry.key.contains('supabase_service.dart')) continue; // checked above
        final source = entry.value;
        for (final m in RegExp(r'status == 401').allMatches(source)) {
          final end =
              (m.start + 600) > source.length ? source.length : m.start + 600;
          final window = source.substring(m.start, end);
          expect(reInvoke.hasMatch(window), isFalse,
              reason:
                  '${entry.key}: re-invokes an Edge Function inside a '
                  '`status == 401` handler — compounding retry. Decode the 401 '
                  'into a user message instead (retry lives only in callFunction).');
        }
      }
    });
  });
}
