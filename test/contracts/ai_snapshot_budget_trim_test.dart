// test/contracts/ai_snapshot_budget_trim_test.dart
//
// Diagnose a9c3e2 (2026-06-01) — found live driving the AI coach as amar
// (year-sim power user): every coach message failed with "Your coaching
// context is unusually large" because `buildAiContext` produced a snapshot
// over the server's 10000-char limit (CLAUDE.md §4.4 rule 18). Fields like
// `personal_records` (a year of unique exercises) are unbounded, so a heavy
// user's coach becomes 100% unusable.
//
// Fix: `AiSnapshotBuilder.trimSnapshotToBudget` iteratively shrinks the
// largest NON-critical field (halve list / halve map / drop scalar) until
// the serialized snapshot fits, always preserving the high-signal fields the
// coach reasons from. This test pins that contract.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/services/ai_snapshot_builder.dart';

void main() {
  group('AiSnapshotBuilder.trimSnapshotToBudget', () {
    test('caps an oversized snapshot under budget, keeps high-signal fields',
        () {
      // Realistic bloat: personal_records as a big Map (exercise -> best),
      // coaching_notes as a big List.
      final hugePrs = <String, dynamic>{
        for (var i = 0; i < 1500; i++) 'Exercise number $i': 100 + i,
      };
      final hugeNotes = List.generate(600, (i) => 'coaching note $i blah blah');
      final snapshot = <String, dynamic>{
        'profile': {'name': 'Amar', 'primary_goal': 'muscle_gain'},
        'progress': {'current_phase': 13, 'total_workouts_done': 300},
        'today_workout': {
          'name': 'Push',
          'exercises': ['Bench Press', 'Overhead Press'],
        },
        'today_nutrition': {'calories': 2200, 'protein': 180},
        'current_plan_summary': {'phase': 13, 'week': 1},
        'subscription': {'is_pro': true},
        'current_rank': {'code': 'Lt'},
        'personal_records': hugePrs, // bloat (Map branch)
        'coaching_notes': hugeNotes, // bloat (List branch)
      };
      expect(jsonEncode(snapshot).length, greaterThan(8500),
          reason: 'precondition: the snapshot must start oversized');

      final trimmed =
          AiSnapshotBuilder.trimSnapshotToBudget(snapshot, budget: 8500);

      expect(jsonEncode(trimmed).length, lessThanOrEqualTo(8500),
          reason: 'trimmed snapshot MUST fit under the budget');

      // High-signal fields preserved intact (never trimmed).
      expect((trimmed['profile'] as Map)['name'], 'Amar');
      expect((trimmed['today_workout'] as Map)['name'], 'Push');
      expect(trimmed['subscription'], isNotNull);
      expect(trimmed['progress'], isNotNull);
      expect(trimmed['current_plan_summary'], isNotNull);
    });

    test('leaves a small snapshot untouched (no trimming)', () {
      final small = <String, dynamic>{
        'profile': {'name': 'Amar'},
        'personal_records': {'Bench Press': 100},
      };
      final before = jsonEncode(small).length;
      final out = AiSnapshotBuilder.trimSnapshotToBudget(small, budget: 8500);
      expect(jsonEncode(out).length, before);
      expect(out['personal_records'], isNotNull);
    });

    test('always fits under the 10000-char server cap with the default budget',
        () {
      final huge = <String, dynamic>{
        'profile': {'name': 'Amar'},
        'personal_records': {
          for (var i = 0; i < 5000; i++) 'Lift variation number $i': i,
        },
      };
      final out = AiSnapshotBuilder.trimSnapshotToBudget(huge);
      expect(jsonEncode(out).length, lessThanOrEqualTo(10000));
    });

    test(
        're-trims an enriched payload (base + long trends) under the 9500 send '
        'budget — enrich keys are non-keep so they shrink, core survives',
        () {
      // Simulates enrichContextForQuery's output: base snapshot PLUS the
      // unbounded historical adds (weight_trend / workout_adherence /
      // nutrition_trend). These keys are NOT in the `keep` allowlist, so the
      // re-trim must shrink THEM (not the core) to fit. Pins the a9c3e2
      // follow-up (Hermes L37): without the post-enrich re-trim, a power user's
      // 90-day trends re-breach the 10000-char server cap and re-brick the coach.
      const trendCount = 250;
      final enriched = <String, dynamic>{
        'profile': {'name': 'Amar', 'primary_goal': 'muscle_gain'},
        'progress': {'current_phase': 13, 'total_workouts_done': 300},
        'today_workout': {'name': 'Push'},
        'subscription': {'is_pro': true},
        'current_rank': {'code': 'Lt'},
        'weight_trend': List.generate(trendCount,
            (i) => {'date': '2026-03-${(i % 28) + 1}', 'weight_kg': 70 + i * 0.1}),
        'workout_adherence': List.generate(
            trendCount, (i) => {'date': '2026-03-${(i % 28) + 1}', 'done': i.isEven}),
        'nutrition_trend': List.generate(
            12, (i) => {'week': i, 'avg_calories': 2200 + i, 'avg_protein': 180}),
      };
      expect(jsonEncode(enriched).length, greaterThan(9500),
          reason: 'precondition: enriched payload must start over the send budget');

      final out = AiSnapshotBuilder.trimSnapshotToBudget(enriched, budget: 9500);

      expect(jsonEncode(out).length, lessThanOrEqualTo(9500),
          reason: 'enriched payload MUST be re-trimmed under the send budget '
              '(below the 10000 server cap)');
      // Core high-signal fields survive intact.
      expect((out['profile'] as Map)['name'], 'Amar');
      expect(out['subscription'], isNotNull);
      expect(out['current_rank'], isNotNull);
      // The unbounded historical adds were shrunk (proves they are NON-keep).
      final wt = out['weight_trend'];
      expect(wt is List && wt.length < trendCount, isTrue,
          reason: 'weight_trend must be shrinkable (not in the keep allowlist)');
    });
  });

  group('enrichContextForQuery re-trim wiring (a9c3e2 follow-up / Hermes L37)', () {
    test('enrichContextForQuery routes its return through trimSnapshotToBudget',
        () {
      final src =
          File('lib/features/ai_coach/services/ai_snapshot_builder.dart')
              .readAsStringSync();
      final start = src.indexOf('enrichContextForQuery(');
      expect(start, greaterThan(0),
          reason: 'enrichContextForQuery must exist in the builder');
      // Window the method body (it is ~85 lines); assert its return re-trims.
      final body =
          src.substring(start, (start + 4000).clamp(0, src.length));
      expect(body.contains('return trimSnapshotToBudget('), isTrue,
          reason: 'enrichContextForQuery MUST re-trim its output via '
              'trimSnapshotToBudget before returning (a9c3e2 follow-up / Hermes '
              'L37). A bare `return context;` lets the 90-day weight/adherence '
              'trends re-breach the 10000-char server cap for power users.');
    });
  });
}
