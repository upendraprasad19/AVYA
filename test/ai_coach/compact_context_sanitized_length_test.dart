// Behavioural — the client's snapshot budget must measure the same length
// the server measures (B-pass finding, 2026-09-26, on the Hermes L37-F2
// fix). `_shared/ai_proxy_input_limits.ts` now measures the snapshot AFTER
// `sanitizeJsonForPrompt`, which re-escapes every raw U+2028 / U+2029 /
// U+0085 as a 6-character sequence — a net +5 per occurrence. Before this
// fix, `_compactContext`'s `size()` measured the plain `json.encode(...)`
// length, so a snapshot near the 9500-char client ceiling carrying enough
// of those rare separator characters could pass the client's check and
// still be rejected server-side with "Snapshot too large".
//
// Every separator character below is built with String.fromCharCode
// and a bare hex literal, never a quoted escape sequence in source: a
// raw invisible character embedded in a file whose own subject is
// invisible characters is the exact trap CLAUDE.md's common-pitfalls
// table already documents for sanitize_for_prompt.ts (its own comment:
// every example there is spelled out in words, never eyeballed) — this
// test file hit that same trap once while being written (a raw code
// point ended up inside a comment) and was rewritten this way to close
// it for good.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/ai_service.dart';

/// U+2028 LINE SEPARATOR, U+2029 PARAGRAPH SEPARATOR, U+0085 NEL — built
/// from pure-ASCII hex so no raw non-ASCII byte is ever typed in this file.
String _separatorChars(int count, {List<int> codes = const [0x2028, 0x2029, 0x0085]}) {
  final buf = StringBuffer();
  for (var i = 0; i < count; i++) {
    buf.writeCharCode(codes[i % codes.length]);
  }
  return buf.toString();
}

void main() {
  group('AiService.sanitizedLengthForTest', () {
    test('plain ASCII: sanitised length equals the encoded length', () {
      const s = '{"k":"a plain value with no separators"}';
      expect(AiService.sanitizedLengthForTest(s), s.length);
    });

    test('each U+2028 / U+2029 / U+0085 adds 5 to the length', () {
      final withSeparators = '{"k":"${_separatorChars(30)}"}';
      expect(
        AiService.sanitizedLengthForTest(withSeparators),
        withSeparators.length + 5 * 30,
      );
    });
  });

  group('_compactContext trims against the sanitised length, not the plain one', () {
    test('a snapshot under the plain 9500-char ceiling but over it once '
        'sanitised is still trimmed', () {
      // Numbers verified with a throwaway probe script (not guessed):
      // plain length 8790, sanitised length 10040 — a clear margin on
      // both sides of the 9500 ceiling.
      final ctx = <String, dynamic>{
        'data_window_days': 8,
        'today_workout': {'type': 'PUSH A', 'status': 'pending'},
        'current_plan_summary': {'phase': 1, 'week': 2},
        'current_rank': {'code': 'SD2'},
        'subscription': {'tier': 'free'},
        'committed_at': null,
        'step_history_7d': 'a' * 8300,
        // 250 separator characters: +5 chars each once sanitised = +1250.
        'coach_notices': _separatorChars(250, codes: const [0x2028]),
      };
      final plainLength = json.encode(ctx).length;
      expect(plainLength, lessThan(9500),
          reason: 'fixture must sit under the ceiling BEFORE sanitising, '
              'or this test would pass for the wrong reason');
      expect(
        AiService.sanitizedLengthForTest(json.encode(ctx)),
        greaterThan(9500),
        reason: 'the 250 separator characters must push the sanitised '
            'length over the ceiling, or this test proves nothing');

      final trimmed = AiService.compactForTest(ctx);

      // step_history_7d is priority 1 to drop; coach_notices is priority 7.
      // Trimming step_history_7d alone removes 8300 chars, which is more
      // than enough to clear the +1250 sanitised overhead, so coach_notices
      // (and its separator burst) should survive.
      expect(trimmed.containsKey('step_history_7d'), isFalse,
          reason: 'the snapshot was over budget once measured correctly — '
              'it must have been trimmed');
    });

    test('the same snapshot with the separators stripped is NOT trimmed '
        '(control: proves the separators, not the padding, drive the '
        'decision)', () {
      final ctx = <String, dynamic>{
        'data_window_days': 8,
        'today_workout': {'type': 'PUSH A', 'status': 'pending'},
        'current_plan_summary': {'phase': 1, 'week': 2},
        'current_rank': {'code': 'SD2'},
        'subscription': {'tier': 'free'},
        'committed_at': null,
        'step_history_7d': 'a' * 8300,
        'coach_notices': 'a' * 250, // no separators this time
      };
      final trimmed = AiService.compactForTest(ctx);
      expect(trimmed.containsKey('step_history_7d'), isTrue,
          reason: 'without the separator inflation this snapshot is under '
              'budget and must not be trimmed at all');
    });
  });
}
