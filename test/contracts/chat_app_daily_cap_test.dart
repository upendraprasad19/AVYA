// Source-grep contract for the chat 'app' channel 10/day free-tier cap.
//
// OI-46 (2026-07-29) — was a check-then-insert TOCTOU (SELECT count() then
// insert unconditionally at the end of the handler with no re-check). Fixed
// with an insert-first reservation pattern mirroring food_text_analysis,
// backed by the trg_chat_app_rate_limit Postgres trigger (migration 111).
// Behavioral proof of the trigger's actual live behavior lives in
// test/sql/oi46_daily_cap_triggers_live_verify.sql (source-grep here proves
// presence only, per feedback_source_grep_false_confidence.md).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  group('OI-46 chat app 10/day free-tier cap', () {
    test('migration 111 (chat_vision_daily_cap_triggers) exists', () {
      expect(
        File('supabase/migrations/111_chat_vision_daily_cap_triggers.sql')
            .existsSync(),
        isTrue,
        reason: 'chat_vision_daily_cap_triggers migration must exist.',
      );
    });

    test('migration 111 defines trg_chat_app_rate_limit as an '
        'insert-first BEFORE INSERT trigger, not a check-then-insert', () {
      final src = _src(
          'supabase/migrations/111_chat_vision_daily_cap_triggers.sql');
      expect(src.contains('enforce_chat_app_daily_limit'), isTrue);
      expect(src.contains('BEFORE INSERT ON ai_coach_interactions'), isTrue);
      expect(src.contains("USING ERRCODE = 'P0001'"), isTrue);
    });

    test('migration 111 exempts PRO users from the chat cap', () {
      final src = _src(
          'supabase/migrations/111_chat_vision_daily_cap_triggers.sql');
      // The PRO short-circuit must appear inside the chat function body,
      // before the daily_count SELECT — a textual proxy for "PRO returns
      // early", verified precisely by the live SQL test's Case 2.
      final fnStart = src.indexOf('enforce_chat_app_daily_limit');
      final fnBody = src.substring(fnStart, src.indexOf('\$\$ LANGUAGE plpgsql', fnStart));
      expect(fnBody.contains('is_pro'), isTrue,
          reason: 'chat trigger must check subscriptions.status for a PRO exemption');
    });

    test('ai-proxy uses INSERT-first reservation pattern for chat, not a '
        'post-hoc insert with no cap re-check', () {
      final src = _src('supabase/functions/ai-proxy/index.ts');
      expect(
        src.contains('chat_app_daily_limit_reached'),
        isTrue,
        reason: 'ai-proxy must detect the Postgres trigger\'s P0001 '
            'chat_app_daily_limit_reached message.',
      );
      expect(
        src.contains('chatReservationId'),
        isTrue,
        reason: 'ai-proxy must reserve a row before calling Gemini and '
            'UPDATE it afterward, not INSERT unconditionally post-response.',
      );
      // The old check-then-insert SELECT must be gone.
      expect(
        src.contains('const { count: msgCount'),
        isFalse,
        reason: 'the old racy SELECT-count pre-check must be removed — '
            'the trigger is the single source of truth now.',
      );
    });
  });
}
