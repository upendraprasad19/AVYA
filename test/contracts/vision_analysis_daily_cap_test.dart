// Source-grep contract for the combined scan_meal + cart_auditor 15/day cap.
//
// OI-46 (2026-07-29) — was worse than a TOCTOU: the interaction row was
// inserted AFTER Gemini succeeded, wrapped in a swallowed `catch (_) {}`,
// so even a capped user's request completed successfully with the
// row-insert failure silently discarded. Fixed with an insert-first
// reservation pattern (mirroring food_text_analysis), backed by the
// trg_vision_analysis_rate_limit Postgres trigger (migration 111).
// Behavioral proof lives in test/sql/oi46_daily_cap_triggers_live_verify.sql.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  group('OI-46 vision (scan_meal + cart_auditor) combined 15/day cap', () {
    test('migration 111 defines trg_vision_analysis_rate_limit as a '
        'combined-channel BEFORE INSERT trigger', () {
      final src = _src(
          'supabase/migrations/111_chat_vision_daily_cap_triggers.sql');
      expect(src.contains('enforce_vision_analysis_daily_limit'), isTrue);
      expect(
        src.contains("NEW.channel NOT IN ('scan_meal', 'cart_auditor')"),
        isTrue,
        reason: 'the cap must be a single shared budget across both '
            'channels, not two independent 15/day caps.',
      );
      expect(src.contains("USING ERRCODE = 'P0001'"), isTrue);
    });

    test('ai-proxy reserves a row before calling Gemini for scan_meal and '
        'cart_auditor, and updates (not inserts) on success', () {
      final src = _src('supabase/functions/ai-proxy/index.ts');
      expect(
        src.contains('vision_analysis_daily_limit_reached'),
        isTrue,
        reason: 'ai-proxy must detect the Postgres trigger\'s P0001 '
            'vision_analysis_daily_limit_reached message.',
      );
      expect(
        src.contains('visionReservationId'),
        isTrue,
        reason: 'ai-proxy must reserve a row before calling Gemini.',
      );
      // The old post-hoc insert-with-swallowed-catch pattern must be gone
      // for both handlers — no more `catch (_) {}` directly wrapping an
      // `ai_coach_interactions` insert for scan_meal/cart_auditor.
      expect(
        src.contains('channel: "scan_meal",\n            user_message: "[scan_meal] analysis"'),
        isFalse,
        reason: 'scan_meal must no longer INSERT a fresh row post-Gemini — '
            'it should UPDATE the pre-reserved row.',
      );
      expect(
        src.contains('channel: "cart_auditor",\n            user_message: "[cart_auditor] analysis"'),
        isFalse,
        reason: 'cart_auditor must no longer INSERT a fresh row post-Gemini.',
      );
    });

    test('supabase/functions/CLAUDE.md documents the combined cap, not two '
        'independent 15/day caps', () {
      final doc = _src('supabase/functions/CLAUDE.md');
      expect(
        doc.contains('COMBINED with'),
        isTrue,
        reason: 'the doc must state scan_meal and cart_auditor share one '
            '15/day budget (OI-46 correction), not two separate caps.',
      );
    });

    test('round-1 review fix: a missing/empty image is rejected BEFORE the '
        'reservation insert, not after', () {
      final src = _src('supabase/functions/ai-proxy/index.ts');
      // The vision block must reject imgB64.length === 0 (and the null/
      // undefined case) ahead of the `visionReserved = ... .insert(` call —
      // pre-fix, a missing image fell through to the reservation insert
      // and then neither the scan_meal nor cart_auditor handler ran
      // (both require `&& body.image`), orphaning a 'pending' row and
      // burning a cap slot on a malformed request.
      final capBlockStart = src.indexOf('Vision abuse cap');
      final reservationInsertIdx = src.indexOf('visionReserved = await supabaseClient', capBlockStart);
      final emptyCheckIdx = src.indexOf('imgB64.length === 0', capBlockStart);
      expect(emptyCheckIdx, greaterThan(-1),
          reason: 'must explicitly reject an empty-string image.');
      expect(emptyCheckIdx, lessThan(reservationInsertIdx),
          reason: 'the empty/missing image check must run BEFORE the '
              'reservation insert, not after.');
    });

    test('round-1 review fix: every exit path (success, Gemini failure, '
        'invalid JSON) resolves the reservation via resolveVisionPlaceholder', () {
      final src = _src('supabase/functions/ai-proxy/index.ts');
      expect(
        src.contains('resolveVisionPlaceholder'),
        isTrue,
        reason: 'a shared placeholder-resolution helper must exist so no '
            'exit path leaves the reserved row stuck at pending forever.',
      );
      // Count call sites: 1 declaration + at least 3 call sites per handler
      // (scan_meal !content, scan_meal parse-catch, scan_meal success) x2
      // handlers = at least 6 call sites total, plus the declaration.
      final callCount = 'resolveVisionPlaceholder'.allMatches(src).length;
      expect(callCount, greaterThanOrEqualTo(7),
          reason: 'expected the declaration plus >=6 call sites (3 exit '
              'paths x 2 handlers); found $callCount occurrences — a '
              'failure branch may have been left unresolved again.');
    });
  });
}
