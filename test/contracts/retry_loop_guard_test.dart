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

    test('callFunction invokes edge function exactly once', () {
      final source = allSources.entries
          .firstWhere((e) => e.key.contains('supabase_service.dart'))
          .value;

      // Extract the callFunction method body
      final callFnStart = source.indexOf('Future<FunctionResponse> callFunction(');
      expect(callFnStart, isNot(-1), reason: 'callFunction must exist');

      // Count occurrences of client.functions.invoke within callFunction
      // (from callFunction declaration to end of file or next top-level method)
      final callFnBody = source.substring(callFnStart);
      final invokeCount =
          RegExp(r'client\.functions\.invoke\(').allMatches(callFnBody).length;

      expect(invokeCount, equals(1),
          reason:
              'callFunction must call client.functions.invoke exactly ONCE. '
              'Found $invokeCount invocations. Multiple calls = retry logic.');
    });
  });

  // ── Fix 2B: No recursive send() in AiCoachProvider ───────────

  group('Guard: AiCoachProvider.send has no recursive call', () {
    test('send() does NOT call itself recursively', () {
      final source = allSources.entries
          .firstWhere((e) => e.key.contains('ai_coach_provider.dart'))
          .value;

      // Extract the send() method body (from declaration to next method or end)
      final sendStart = source.indexOf('Future<void> send(String message');
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

      // Must still call ensureFreshToken on auth errors (to fix the token
      // for the NEXT user-initiated send)
      expect(source, contains('ensureFreshToken'),
          reason:
              'Auth error path must still refresh token for next attempt');

      // Must show an error message to the user (not silently retry)
      expect(source, contains("'Session expired"),
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
