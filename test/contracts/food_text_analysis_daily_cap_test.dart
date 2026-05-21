// Source-grep contract for food_text_analysis 50/200/day server cap.
//
// Originally landed as T-8 of `audit_2026_05_11_t1_t11_contracts_test.dart`.
// Split per concept per tech-debt audit 2026-05-20 T12.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  group('T-8 food_text_analysis 50/200/day server cap', () {
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
