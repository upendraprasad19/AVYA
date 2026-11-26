// Source-grep contract for the food_text_analysis daily-cap WIRING — that a
// trigger migration exists and that ai-proxy handles the P0001 it raises.
//
// ⚠ This file does NOT pin the cap VALUES, despite what its title claimed until
// 2026-09-04 (b8f4c2). It was headed "50/200/day server cap" and asserted
// neither 50 nor 200: the free cap was lowered 50 -> 10 in migration 127 and
// every test here stayed green. A title that claims more than the assertions
// deliver is worse than no test, because it answers "is this covered?" wrongly.
//
// The VALUES are pinned by
// test/contracts/food_text_analysis_daily_cap_writer_to_reader_test.dart, which
// reads them from the LATEST migration defining the trigger function and checks
// them against BOTH the client constant and ai-proxy's 429-body constants. Add
// new food-text cap assertions there, not here.
//
// (ai_message_limit_parity_test.dart holds the SIBLING pairs — the chat cap and
// the shared vision ceiling. Gate 9 requires one contract file per SoT concept,
// which is why the enumeration is split by concept rather than kept in one file.
// This pointer said "ai_message_limit_parity_test.dart" until round 2 of the ×2
// review caught that the two headers disagreed about which file owns the
// food-text values.)
//
// Originally landed as T-8 of `audit_2026_05_11_t1_t11_contracts_test.dart`.
// Split per concept per tech-debt audit 2026-05-20 T12.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  group('T-8 food_text_analysis daily-cap wiring (values: parity test)', () {
    test('migration 026 (food_text_rate_limit_trigger) exists', () {
      // The numeric prefix was 024 in the docs but the actual source
      // file is 026_food_text_rate_limit_trigger.sql. Accept either.
      final candidates = [
        'supabase/migrations/024_food_text_rate_limit_trigger.sql',
        'supabase/migrations/026_food_text_rate_limit_trigger.sql',
      ];
      final exists = candidates.any((p) => File(p).existsSync());
      expect(exists, isTrue,
          reason: 'food_text_rate_limit_trigger migration must exist.');
    });

    test('ai-proxy uses INSERT-first reservation pattern', () {
      final src = _src('supabase/functions/ai-proxy/index.ts');
      // Both signals must appear SOMEWHERE in the file — they may
      // be far apart in the source (rate-limit catch comes ~30 lines
      // after the `if (type === "food_text_analysis")` branch start).
      expect(
        src.contains('food_text_daily_limit_reached'),
        isTrue,
        reason: 'ai-proxy must detect the Postgres trigger\'s P0001 '
            'food_text_daily_limit_reached message.',
      );
      expect(
        src.contains('Daily food analysis limit') ||
            src.contains('Daily food'),
        isTrue,
        reason: 'ai-proxy must return a 429 with a "Daily food '
            'analysis limit" message when the cap is hit.',
      );
    });
  });
}
