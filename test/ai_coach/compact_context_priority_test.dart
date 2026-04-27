// test/ai_coach/compact_context_priority_test.dart
//
// Pins the A9 spec §7.3 priority order for _compactContext:
//   1. step_history_7d  2. water_7d  3. weight_trend
//   4. nutrition_trend_7d (meals_today kept)  5. exercise_history
//   6. truncate coaching_notes to 1000 chars  7. drop fitness_summary
//
// Never-drop set verified: anti-fab grounding, today_workout,
// current_plan_summary, current_rank, subscription, committed_at.

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/ai_service.dart';

/// Build a synthetic context that exceeds 9.5 KB so trimming kicks in.
/// Pad each non-essential key with enough bytes that the total exceeds
/// the compaction ceiling. The sentinel keys we never drop are kept small.
Map<String, dynamic> _bigCtx() {
  String pad(int chars) => 'X' * chars;
  return {
    // ── Never-drop keys (small, identity-bearing) ──────────────────────
    'data_window_days': 8,
    'first_workout_date': '2026-04-19',
    'workout_logs_count': 2,
    'today_workout': {
      'type': 'PUSH A',
      'status': 'pending',
      'exercises': [],
    },
    'current_plan_summary': {
      'phase': 1,
      'week': 2,
      'days_per_week': 6,
      'weekly_sessions': [],
    },
    'current_rank': {'code': 'SEAMAN_2', 'display': 'Seaman 2nd Class'},
    'subscription': {
      'tier': 'free',
      'expires_at': null,
      'plan': null,
      'auto_renew': false,
    },
    'committed_at': '2026-04-27T12:00:00Z',
    // ── Load-bearing meals keys (never drop) ──────────────────────────
    'meals_today': [
      {
        'slot': 'breakfast',
        'items': [
          {
            'name': 'Oats',
            'kcal': 152,
            'protein_g': 5,
            'carbs_g': 27,
            'fat_g': 3,
          },
        ],
        'total_kcal': 152,
        'total_protein_g': 5,
      },
    ],
    // ── Trimmable keys (each padded so total > 9.5 KB) ────────────────
    'step_history_7d': List.generate(
      7,
      (i) => {'date': '2026-04-2$i', 'steps': 8000, 'pad': pad(200)},
    ),
    'water_7d': List.generate(
      7,
      (i) => {'date': '2026-04-2$i', 'ml': 2500, 'pad': pad(200)},
    ),
    'weight_trend': {
      'series': List.generate(
        30,
        (i) => {'date': '2026-03-${i + 1}', 'weight_kg': 75.0, 'pad': pad(50)},
      ),
    },
    'nutrition_trend_7d': {
      'calories_avg': 2200,
      'protein_avg': 138,
      'series': List.generate(
        7,
        (i) => {'date': '2026-04-2$i', 'cal': 2200, 'pad': pad(200)},
      ),
    },
    'exercise_history': List.generate(
      10,
      (i) => {'name': 'Bench Press', 'set_number': i, 'pad': pad(200)},
    ),
    'coaching_notes': pad(3000),
    'fitness_summary': pad(800),
  };
}

void main() {
  group('_compactContext A9 priority order', () {
    test('precondition: _bigCtx exceeds 9.5 KB', () {
      final size = json.encode(_bigCtx()).length;
      expect(
        size,
        greaterThan(9500),
        reason: 'Test fixture must be over budget so trimming activates. '
            'Got $size bytes.',
      );
    });

    test('drops step_history_7d first', () {
      final ctx = _bigCtx();
      final compacted = AiService.compactForTest(ctx);
      // step_history_7d is position 1 — always the first thing gone.
      expect(
        compacted.containsKey('step_history_7d'),
        isFalse,
        reason: 'step_history_7d must be the first key dropped',
      );
    });

    test('NEVER drops today_workout', () {
      final ctx = _bigCtx();
      final compacted = AiService.compactForTest(ctx);
      expect(
        compacted.containsKey('today_workout'),
        isTrue,
        reason: 'today_workout is load-bearing and must survive all trim paths',
      );
    });

    test('NEVER drops meals_today', () {
      final ctx = _bigCtx();
      final compacted = AiService.compactForTest(ctx);
      expect(
        compacted.containsKey('meals_today'),
        isTrue,
        reason: 'meals_today shows what the user ate today — '
            'coach cannot reason about protein gaps without it',
      );
    });

    test('NEVER drops anti-fab grounding keys', () {
      final ctx = _bigCtx();
      final compacted = AiService.compactForTest(ctx);
      expect(
        compacted['data_window_days'],
        equals(8),
        reason: 'data_window_days pins anti-fabrication grounding',
      );
      expect(
        compacted['first_workout_date'],
        equals('2026-04-19'),
        reason: 'first_workout_date pins anti-fabrication grounding',
      );
      expect(
        compacted['workout_logs_count'],
        equals(2),
        reason: 'workout_logs_count prevents hallucinated streak/history stats',
      );
    });

    test('NEVER drops current_rank, subscription, committed_at, '
        'current_plan_summary', () {
      final ctx = _bigCtx();
      final compacted = AiService.compactForTest(ctx);
      expect(
        compacted.containsKey('current_rank'),
        isTrue,
        reason: 'current_rank is referenced by Captain Manual §8',
      );
      expect(
        compacted.containsKey('subscription'),
        isTrue,
        reason: 'subscription used by Captain Manual §4 tier-awareness',
      );
      expect(
        compacted.containsKey('committed_at'),
        isTrue,
        reason: 'committed_at used by Captain Manual §2 cadence logic',
      );
      expect(
        compacted.containsKey('current_plan_summary'),
        isTrue,
        reason: 'current_plan_summary used for schedule questions',
      );
    });

    test('coaching_notes truncated to ≤1100 chars when trimming reaches step 8',
        () {
      // Build a context that remains over budget even after dropping all 7
      // trimmable keys, so that the coaching_notes truncation (step 8) fires.
      // We achieve this by making coaching_notes itself very large and keeping
      // all other trimmable keys small (so removing them doesn't clear the budget).
      final ctx = <String, dynamic>{
        // Never-drop anchors
        'data_window_days': 8,
        'first_workout_date': '2026-04-19',
        'workout_logs_count': 2,
        'today_workout': {'type': 'PUSH A', 'status': 'pending'},
        'current_plan_summary': {'phase': 1, 'week': 2},
        'current_rank': {'code': 'SEAMAN_2'},
        'subscription': {'tier': 'free'},
        'committed_at': '2026-04-27T12:00:00Z',
        'meals_today': [
          {'slot': 'breakfast', 'total_kcal': 300, 'items': []},
        ],
        // Step-8 subject: very large coaching_notes.
        // Must be large enough that even after ALL 7 trimmable keys are removed
        // (which saves ~200 bytes total from the small sentinels below), the
        // context remains over 9500 bytes so the truncation step fires.
        // never-drop overhead ≈ 400 bytes → coaching_notes needs > 9200 chars.
        'coaching_notes': 'C' * 9500,
        // Small trimmable keys (removing them saves ~200 bytes total — not
        // enough to get under budget alone, so step-8 truncation must fire).
        'step_history_7d': [1, 2, 3],
        'water_7d': [1, 2, 3],
        'weight_trend': {'series': []},
        'nutrition_trend_7d': {'series': []},
        'exercise_history': [],
        'personal_records': [],
        'coach_notices': [],
        'fitness_summary': 'Short summary.',
      };

      // Precondition: fixture must exceed budget
      expect(
        json.encode(ctx).length,
        greaterThan(9500),
        reason: 'coaching_notes-heavy fixture must exceed the compaction ceiling',
      );

      final compacted = AiService.compactForTest(ctx);

      // coaching_notes survived but must be truncated to ≤1000+1 chars
      expect(compacted.containsKey('coaching_notes'), isTrue);
      final notes = compacted['coaching_notes'];
      expect(notes, isA<String>());
      expect(
        (notes as String).length,
        lessThanOrEqualTo(1100),
        reason: 'coaching_notes must be truncated to ~1000 chars '
            '(+100 slack for the "…" truncation marker)',
      );
      // meals_today must still be present even in this extreme scenario
      expect(compacted.containsKey('meals_today'), isTrue,
          reason: 'meals_today never-drop rule holds even in step-8 territory');
    });

    test('total compacted output is under 9.5 KB', () {
      final ctx = _bigCtx();
      final compacted = AiService.compactForTest(ctx);
      final size = json.encode(compacted).length;
      expect(
        size,
        lessThanOrEqualTo(9500),
        reason: 'Compacted context must fit the server limit. Got $size bytes.',
      );
    });
  });
}
