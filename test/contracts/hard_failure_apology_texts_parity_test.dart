// Plan-review round 1 finding (APK +43 obs 2, diagnose a1c6b9): ai-proxy's
// reservation-resolve UPDATE persists ai_response to the cloud
// ai_coach_interactions row UNCONDITIONALLY, with no column carrying
// ToolLoopResult.hadHardFailure — so a cold restore of a hard-failure
// apology turn (reinstall / new device) had no flag to exclude it from
// recentHistoryExchanges's replay window, reproducing the exact
// self-perpetuation bug the live-path fix (APK +43 obs 2's original commit)
// closes, just via the restore trigger instead of the live-failure trigger.
//
// Fix: _restoreCoachInteractions (sync_coach.dart) recognizes a restored
// hard-failure turn by matching its exact ai_response text against
// kKnownHardFailureApologyTexts — a client-side MIRROR of the two exported
// TS constants in supabase/functions/_shared/tool-loop.ts
// (HARD_FAILURE_APOLOGY_GEMINI_CALL_FAILED /
// HARD_FAILURE_APOLOGY_ROUNDS_EXHAUSTED).
//
// Plan-review round 2 finding, same diagnose: that recognizer covers only
// the two known apology TEXTS and misses a THIRD, structurally distinct
// failure case — ai-proxy/index.ts's runToolLoop-THREW catch block (a
// genuine crash calling the tool loop, separate from the two apologies
// runToolLoop itself returns via a normal 200 response), which writes
// ai_response: "[failed] runToolLoop threw", model_used: "failed"
// unconditionally, text not in kKnownHardFailureApologyTexts. Fix:
// isRestoredHardFailureRow composes isKnownHardFailureApologyText with a
// second signal — model_used == kModelUsedLoopThrewSentinel, a client-side
// mirror of ai-proxy/index.ts's exported MODEL_USED_LOOP_THREW_SENTINEL.
//
// This file has three jobs:
//   1. PARITY — each Dart string/sentinel is byte-identical to its TS
//      source (tool-loop.ts for the two apology texts, ai-proxy/index.ts
//      for the loop-threw sentinel).
//   2. BEHAVIOR — isKnownHardFailureApologyText and isRestoredHardFailureRow
//      (both pure) are mutation-tested directly, no Hive/network required.
//   3. WIRING — _restoreCoachInteractions actually calls
//      isRestoredHardFailureRow and writes its result into
//      'had_hard_failure' (source-grep, mirrors the established
//      test/sync/restore_keys_deterministic_test.dart pattern).
// The DOWNSTREAM consequence (a row so marked is excluded from replay) is
// pinned behaviorally in
// test/contracts/coach_chat_history_replay_writer_to_reader_test.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '_sync_service_source.dart';

/// Strips `//` line comments and `/* */` block comments so a source-seam
/// presence check can't be satisfied by a comment mentioning the token
/// (feedback_source_grep_strip_comments_first).
String _stripComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return noBlock
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');
}

void main() {
  group('parity — Dart mirror matches the TS source exactly', () {
    late String toolLoopSrc;
    late String aiProxySrc;

    setUpAll(() {
      toolLoopSrc =
          File('supabase/functions/_shared/tool-loop.ts').readAsStringSync();
      aiProxySrc =
          File('supabase/functions/ai-proxy/index.ts').readAsStringSync();
    });

    test('every known Dart apology text appears verbatim in tool-loop.ts',
        () {
      expect(kKnownHardFailureApologyTexts.length, 2,
          reason: 'this test enumerates exactly 2 — a new one added to the '
              'Dart set without a matching TS string would silently pass '
              'membership but fail this presence check, which is the point');
      for (final text in kKnownHardFailureApologyTexts) {
        // toolLoopSrc is the RAW SOURCE TEXT of the .ts file, not an
        // evaluated string — an embedded `"` inside a TS double-quoted
        // literal appears in that raw text as the two characters `\"`, while
        // [text] here is Dart's already-EVALUATED runtime string value (a
        // bare `"`). Re-escape before searching, or every string containing
        // an embedded double-quote silently "fails to drift-check" forever.
        final tsEscaped = text.replaceAll('"', '\\"');
        expect(toolLoopSrc.contains(tsEscaped), isTrue,
            reason: 'Dart mirror text not found verbatim in tool-loop.ts — '
                'drifted from the server string:\n$text');
      }
    });

    test('the 2 known TS export sites still exist and are exported', () {
      expect(toolLoopSrc.contains('export const HARD_FAILURE_APOLOGY_GEMINI_CALL_FAILED'),
          isTrue);
      expect(
          toolLoopSrc.contains('export const HARD_FAILURE_APOLOGY_ROUNDS_EXHAUSTED'),
          isTrue);
    });

    test(
        'kModelUsedLoopThrewSentinel matches ai-proxy/index.ts\'s exported '
        'MODEL_USED_LOOP_THREW_SENTINEL', () {
      // "failed" has no characters that TS string-literal-escapes
      // differently from Dart's evaluated form, so no re-escape is needed
      // here the way the apology texts above require — confirmed by
      // asserting the literal appears in the EXPORT STATEMENT itself, not
      // just anywhere in the file.
      expect(kModelUsedLoopThrewSentinel, 'failed');
      expect(
          aiProxySrc.contains(
              'export const MODEL_USED_LOOP_THREW_SENTINEL = "$kModelUsedLoopThrewSentinel"'),
          isTrue,
          reason: 'Dart kModelUsedLoopThrewSentinel drifted from '
              'ai-proxy/index.ts\'s exported MODEL_USED_LOOP_THREW_SENTINEL');
    });

    test('the runToolLoop-threw catch site actually writes the sentinel',
        () {
      final catchStart = aiProxySrc.indexOf('catch (loopErr)');
      expect(catchStart, greaterThan(0),
          reason: 'the runToolLoop-threw catch block must exist');
      final nextCatch =
          aiProxySrc.indexOf('\n    } catch', catchStart + 1);
      final body = aiProxySrc.substring(
          catchStart, nextCatch > catchStart ? nextCatch : aiProxySrc.length);
      expect(body.contains('model_used: MODEL_USED_LOOP_THREW_SENTINEL'),
          isTrue,
          reason: 'the catch block must write the named sentinel constant, '
              'not a raw re-typed string literal that could drift from it '
              'independently of the parity assertion above');
    });
  });

  group('isKnownHardFailureApologyText — pure, mutation-tested', () {
    test('true for each known text, exact', () {
      for (final text in kKnownHardFailureApologyTexts) {
        expect(isKnownHardFailureApologyText(text), isTrue);
      }
    });

    test('true for a known text with incidental leading/trailing whitespace',
        () {
      final first = kKnownHardFailureApologyTexts.first;
      expect(isKnownHardFailureApologyText('  $first  '), isTrue);
    });

    test('false for real model output', () {
      expect(
          isKnownHardFailureApologyText('Push day — bench, incline dumbbell, dips.'),
          isFalse);
    });

    test('false for null and empty', () {
      expect(isKnownHardFailureApologyText(null), isFalse);
      expect(isKnownHardFailureApologyText(''), isFalse);
    });

    test('false for a near-miss (one character short of a known text)', () {
      final truncated = kKnownHardFailureApologyTexts.first
          .substring(0, kKnownHardFailureApologyTexts.first.length - 1);
      expect(isKnownHardFailureApologyText(truncated), isFalse,
          reason: 'must be an exact match, not a prefix/contains check — a '
              'partial match on real model output that happens to start '
              'the same way must not be excluded from replay');
    });
  });

  group('isRestoredHardFailureRow — pure composition, mutation-tested', () {
    test('true when aiResponse matches a known apology text alone', () {
      expect(
          isRestoredHardFailureRow(
            aiResponse: kKnownHardFailureApologyTexts.first,
            modelUsed: 'Gemini 2.5 Flash',
          ),
          isTrue);
    });

    test('true when modelUsed matches the loop-threw sentinel alone', () {
      expect(
          isRestoredHardFailureRow(
            aiResponse: '[failed] runToolLoop threw',
            modelUsed: kModelUsedLoopThrewSentinel,
          ),
          isTrue);
    });

    test('true when BOTH signals fire (not mutually exclusive)', () {
      expect(
          isRestoredHardFailureRow(
            aiResponse: kKnownHardFailureApologyTexts.first,
            modelUsed: kModelUsedLoopThrewSentinel,
          ),
          isTrue);
    });

    test('false when neither signal fires — real model output', () {
      expect(
          isRestoredHardFailureRow(
            aiResponse: 'Push day — bench, incline dumbbell, dips.',
            modelUsed: 'Gemini 2.5 Flash',
          ),
          isFalse);
    });

    test('false for null aiResponse and a non-sentinel modelUsed', () {
      expect(
          isRestoredHardFailureRow(aiResponse: null, modelUsed: 'unknown'),
          isFalse);
    });

    test('false for a near-miss modelUsed (must be exact, not a substring)',
        () {
      expect(
          isRestoredHardFailureRow(
            aiResponse: 'real reply',
            modelUsed: 'failed_something_else',
          ),
          isFalse,
          reason: 'must be an exact sentinel match — a real model_used '
              'value that happens to contain "failed" as a substring must '
              'not be excluded from replay');
    });
  });

  group('wiring — _restoreCoachInteractions calls the recognizer', () {
    late String src;

    setUpAll(() {
      src = _stripComments(loadSyncServiceSource().readAsStringSync());
    });

    test('restore body writes had_hard_failure via isRestoredHardFailureRow',
        () {
      final start = src.indexOf('Future<void> _restoreCoachInteractions(');
      expect(start, greaterThan(0),
          reason: '_restoreCoachInteractions must exist');
      final next = src.indexOf('\n  Future<void> ', start + 1);
      final body = src.substring(start, next > start ? next : src.length);

      expect(body.contains("'had_hard_failure':"), isTrue,
          reason: 'restore must write the had_hard_failure key');
      expect(body.contains('isRestoredHardFailureRow('), isTrue,
          reason: 'restore must derive had_hard_failure from the composed '
              'recognizer (apology-text OR loop-threw-sentinel), not a '
              'hand-rolled comparison or a call to only the single-text '
              'recognizer — which would silently drop the round-2 fix\'s '
              'third failure case');
    });
  });
}
