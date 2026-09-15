// Regression test for audit 2026-05-16 / F6-3
// (ai-proxy food_text_analysis placeholder resolution contract).
//
// Bug: the reserved `ai_coach_interactions` placeholder row (inserted before
// calling Gemini for the `food_text_analysis` channel) was only updated
// fire-and-forget on the SUCCESS branch. The two failure branches —
// (1) Gemini returns no content (`!content` → 502) and
// (2) Gemini returns non-JSON content (parse failure → 502) —
// returned `err()` without touching the row. Result: 8 stuck `pending`
// placeholder rows across 2026-05-11→15 from Gemini failures during the
// 502 storm. Each had `ai_response=''` + `model_used='pending'` forever,
// polluting analytics and counting against the 60s dedup window in a
// confusing way.
//
// Fix: a `resolvePlaceholder(finalModel, finalResponse, tokens)` helper
// awaits the UPDATE on EVERY exit branch — success / Gemini-failure /
// parse-failure. Terminal models: `failed_gemini`, `failed_parse`, or
// the real model label on success.
//
// This is a source-grep contract test that scans `ai-proxy/index.ts`
// for the canonical pattern. If any future edit removes the resolution
// from a failure branch, the test fails before deploy.
//
// closes-diagnose: 2026-05-16-ai-proxy-placeholder-resolution

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ai-proxy food_text_analysis placeholder resolution', () {
    late String src;

    setUpAll(() {
      final file = File('supabase/functions/ai-proxy/index.ts');
      expect(file.existsSync(), isTrue,
          reason: 'ai-proxy/index.ts must exist at the expected path');
      src = file.readAsStringSync();
    });

    test('resolvePlaceholder helper is defined inside food_text_analysis branch', () {
      expect(src.contains('const resolvePlaceholder = async ('), isTrue,
          reason:
              'ai-proxy must declare a resolvePlaceholder helper that closes '
              'the reserved row on every exit branch (success/Gemini-failure/'
              'parse-failure). Without it, failure branches orphan the '
              'placeholder row in the pending state — the 8-stuck-rows bug '
              'class from audit 2026-05-16 / F6-3.');
    });

    test('Gemini-no-content branch (`!content`) resolves placeholder to failed_gemini', () {
      // Find the !content guard and verify the resolvePlaceholder call
      // happens in the same block before the err() return.
      final guardIdx = src.indexOf('if (!content) {');
      expect(guardIdx, isNot(-1),
          reason: '!content guard must exist on the Gemini-failure path');
      final guardSlice = src.substring(
        guardIdx,
        (guardIdx + 500).clamp(0, src.length),
      );
      expect(guardSlice.contains('resolvePlaceholder('), isTrue,
          reason:
              'On Gemini failure (!content), the placeholder MUST be resolved '
              'before returning err(502). Otherwise the row stays pending '
              'forever — orphaned-placeholder class.');
      expect(guardSlice.contains('"failed_gemini"'), isTrue,
          reason:
              'Gemini-failure branch must use terminal model "failed_gemini" '
              'so analytics can distinguish it from in-flight rows.');
    });

    test('JSON-parse-failure branch (catch block) resolves placeholder to failed_parse', () {
      // The catch block at the bottom of the try{ JSON.parse(...) } must call
      // resolvePlaceholder before returning err(502, "...invalid JSON").
      // Anchor on the unique err message so we find the RIGHT catch block
      // (the file has 6 `} catch (_)` patterns; only one is for parse failure).
      final errIdx = src.indexOf('"Food analysis returned invalid JSON"');
      expect(errIdx, isNot(-1),
          reason: 'parse-failure err message must exist');
      // Walk back ~600 chars to find the catch block + resolution above it.
      final start = (errIdx - 600).clamp(0, src.length);
      final catchSlice = src.substring(start, errIdx + 100);
      expect(catchSlice.contains('} catch (_) {'), isTrue,
          reason: 'parse-failure catch block must exist immediately before err');
      expect(catchSlice.contains('resolvePlaceholder('), isTrue,
          reason:
              'Parse-failure catch must resolve placeholder before err(502). '
              'Otherwise rows where Gemini returned non-JSON stay pending.');
      expect(catchSlice.contains('"failed_parse"'), isTrue,
          reason:
              'Parse-failure branch must use terminal model "failed_parse".');
    });

    test('success branch awaits resolvePlaceholder (not fire-and-forget)', () {
      // The success path used to be fire-and-forget: `.update(...).then(...)`.
      // Audit F6-3 made it `await`. The pre-fix shape was the cause of
      // intermittent stale-pending rows on network blips. Now must await.
      //
      // Detection: there must be a literal `await resolvePlaceholder(` on a
      // path immediately following the JSON.parse success. Easiest stable
      // detection: count occurrences — there should be ≥1 `await resolvePlaceholder(`.
      final awaitCalls =
          RegExp(r'await\s+resolvePlaceholder\(').allMatches(src).length;
      expect(awaitCalls, greaterThanOrEqualTo(3),
          reason:
              'Every exit branch (success + 2 failure modes) must AWAIT the '
              'resolution. Fire-and-forget `.then(...)` was the pre-fix '
              'anti-pattern. Found $awaitCalls await calls; expected ≥3.');

      // Anti-regression: the legacy fire-and-forget shape on the
      // ai_coach_interactions update path must not return. Detect by
      // scanning for `.eq("id", reservationId)` immediately followed by
      // `.then(` within ~120 chars — the exact pre-fix shape.
      final legacy =
          RegExp(r'\.eq\("id",\s*reservationId\)[\s\S]{0,120}\.then\(')
              .hasMatch(src);
      expect(legacy, isFalse,
          reason:
              'Legacy fire-and-forget `.eq("id", reservationId)...then(...)` '
              'is banned. Use awaited resolvePlaceholder helper instead.');
    });
  });
}
