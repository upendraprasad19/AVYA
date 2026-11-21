// test/contracts/food_ai_telemetry_retry_test.dart
//
// Contract — Theme I (closes-diagnose 599d49).
//
// Pins the food-AI instrumentation + retry-on-500 + improved error
// toast for `food_text_analysis` calls.
//
// Pre-fix: founder tapped Nutrition → Log Food → AI tab → ANALYSE &
// LOG → got the toast "The AI is temporarily unavailable. Please try
// again in a minute." with ZERO per-call telemetry to tell us which
// underlying error happened (cold-start, Gemini timeout, regional
// outage). Additionally, ai-proxy returns 500 on transient Gemini
// upstream timeouts but the global retryColdStart only retried
// 502/503/504, so 500s got no retry budget.
//
// Fix pins:
//   1. `food_ai_call_initiated` telemetry BEFORE the callFunction.
//   2. `food_ai_call_succeeded` telemetry on 2xx, with ms latency.
//   3. `food_ai_call_failed` telemetry on throw, with status +
//      error_class + ms.
//   4. `retryOn500: true` in the callFunction call.
//   5. SupabaseService.retryColdStart accepts a `retryOn500` parameter
//      and extends `isColdStart` to include 500 when opted-in.
//   6. Error toast surfaces underlying status code when available
//      (e.g. "The AI is offline (502). Please try again in a minute.").
//
// Source-grep with comment-stripping per
// `feedback_source_grep_strip_comments_first.md`.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('SupabaseService.retryColdStart — retryOn500 opt-in', () {
    final src = File('lib/core/services/supabase_service.dart')
        .readAsStringSync();
    final stripped = _stripComments(src);

    test('retryColdStart accepts retryOn500 parameter', () {
      expect(
        RegExp(r'retryColdStart\s*\([\s\S]*?bool\s+retryOn500\s*=\s*false')
            .hasMatch(stripped),
        isTrue,
        reason: 'retryColdStart must accept an optional retryOn500=false '
            'parameter so callers can opt into 500-retry for Edge Functions '
            'where 500 is a transient upstream signal (ai-proxy + Gemini).',
      );
    });

    test('isColdStart predicate includes (retryOn500 && status == 500)', () {
      expect(
        RegExp(r'retryOn500\s*&&\s*e\.status\s*==\s*500').hasMatch(stripped),
        isTrue,
        reason: 'retryColdStart isColdStart predicate must extend to 500 '
            'when retryOn500=true. Otherwise the opt-in is dead code.',
      );
    });

    test('callFunction accepts retryOn500 and forwards to retryColdStart', () {
      expect(
        RegExp(r'callFunction\s*\([\s\S]*?bool\s+retryOn500\s*=\s*false')
            .hasMatch(stripped),
        isTrue,
        reason: 'callFunction must accept retryOn500 so callers can opt in '
            'at the call-site without re-implementing retryColdStart.',
      );
      // The forwarder must actually pass it through.
      expect(
        RegExp(r'retryColdStart\s*\([\s\S]*?retryOn500:\s*retryOn500')
            .hasMatch(stripped),
        isTrue,
        reason: 'callFunction must forward retryOn500 to retryColdStart — '
            'else the opt-in never reaches the retry loop.',
      );
    });
  });

  group('nutrition_provider food-AI call instrumentation', () {
    final src = File('lib/features/nutrition/providers/nutrition_provider.dart')
        .readAsStringSync();
    final stripped = _stripComments(src);

    test('emits food_ai_call_initiated before the callFunction', () {
      expect(
        stripped.contains("'food_ai_call_initiated'"),
        isTrue,
        reason: 'must emit food_ai_call_initiated telemetry BEFORE the '
            'callFunction so we can correlate against client_errors.',
      );
    });

    test('emits food_ai_call_succeeded on 2xx with ms latency', () {
      expect(
        RegExp(r"'food_ai_call_succeeded'[\s\S]{0,200}?ms=\$\{stopwatch")
            .hasMatch(stripped),
        isTrue,
        reason: 'must emit food_ai_call_succeeded with ms=${'\$'}{stopwatch...} '
            'so we can measure latency P50/P99 against client_errors.',
      );
    });

    test('emits food_ai_call_failed on throw with status + error_class', () {
      expect(
        stripped.contains("'food_ai_call_failed'"),
        isTrue,
        reason: 'must emit food_ai_call_failed telemetry on every catch path.',
      );
      // The payload must carry status + error_class to be useful.
      expect(
        RegExp(r"'food_ai_call_failed'[\s\S]{0,200}?status=").hasMatch(stripped),
        isTrue,
        reason: 'food_ai_call_failed must carry status=<n> for HTTP status.',
      );
      expect(
        RegExp(r"'food_ai_call_failed'[\s\S]{0,200}?error_class=")
            .hasMatch(stripped),
        isTrue,
        reason: 'food_ai_call_failed must carry error_class=<type> for the '
            'exception runtime type.',
      );
    });

    test('passes retryOn500: true to callFunction', () {
      expect(
        stripped.contains('retryOn500: true'),
        isTrue,
        reason: 'nutrition food-AI call must opt into 500-retry — Gemini '
            'upstream timeouts surface as 500 from ai-proxy.',
      );
    });
  });

  group('error toast surfaces underlying status code', () {
    final src = File('lib/features/nutrition/providers/nutrition_provider.dart')
        .readAsStringSync();
    final stripped = _stripComments(src);

    test('error toast template includes status code parenthetical', () {
      // Pre-fix message: "The AI is temporarily unavailable. Please try
      // again in a minute." — no status code. Post-fix: "The AI is
      // offline (502). Please try again in a minute." when status is
      // captured.
      expect(
        stripped.contains("'The AI is offline (\$httpStatus)"),
        isTrue,
        reason: 'service-error toast must surface the underlying HTTP '
            'status (e.g. "AI is offline (502)") so the user can '
            'distinguish transient (retry) from outage (wait).',
      );
    });

    test('isServiceError predicate includes 500 (matches retryOn500=true)',
        () {
      // Required so the retry-exhausted 500 still routes to the "service
      // unavailable" copy rather than the generic "could not analyse".
      expect(
        RegExp(r"msg\.contains\('500'\)").hasMatch(stripped),
        isTrue,
        reason: 'isServiceError predicate must include 500 — otherwise a '
            '500 that exhausted retries falls through to the generic '
            '"Could not analyse" message.',
      );
    });
  });
}
