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
      // Window the method body (it grew to ~115 lines after Unit 3 added the
      // on-demand step/sleep/water re-add branches); assert its return re-trims.
      final body =
          src.substring(start, (start + 6000).clamp(0, src.length));
      expect(body.contains('return trimSnapshotToBudget('), isTrue,
          reason: 'enrichContextForQuery MUST re-trim its output via '
              'trimSnapshotToBudget before returning (a9c3e2 follow-up / Hermes '
              'L37). A bare `return context;` lets the 90-day weight/adherence '
              'trends re-breach the 10000-char server cap for power users.');
    });
  });

  group('week_lookahead / swaps_left join the keep set (day-swapper-sync-load, plan D7)', () {
    // DESIGN NOTE (re-derived during implementation, not per the brief's literal
    // fixture): the brief's own Step 2 flagged a real risk — a single giant
    // `personal_records` bloat field (3000 entries) is SO much bigger than
    // week_lookahead's ~940-byte encoding that the trim loop's "pick the
    // single biggest non-kept field" step never gets anywhere near
    // week_lookahead before the budget is satisfied, regardless of whether
    // week_lookahead is in the keep set. Running that exact fixture against
    // the REAL trimSnapshotToBudget (both with and without the keep-set
    // entries) confirmed it: 0 reds either way — a false-negative regression
    // pin (rule 21 requires investigating a zero-red mutation, not accepting
    // it). This fixture instead uses MANY decoy fields each individually
    // SMALLER than week_lookahead's own encoded size, so week_lookahead is
    // genuinely the single biggest non-kept field on iteration 1 when it is
    // not protected — matching the real-world scenario the source comment
    // describes ("a heavy user's 7-day lookahead... before genuinely bulky
    // fields").
    test('week_lookahead survives an over-budget trim untouched when many '
        'smaller fields are the real bloat', () {
      final weekLookahead = List.generate(
          7,
          (i) => {
                'day': 'Day$i',
                'date': '2026-09-2$i',
                'type': 'workout',
                'status': 'planned',
                'name': 'Pull + Core',
                'can_swap': true,
                'week_start': '2026-09-21',
              });
      const swapsLeft = {'2026-09-21': 3, '2026-09-28': 3};
      const decoyCount = 13;
      final decoy = 'x' * 600; // encodes to 602 chars incl. quotes
      final fixture = <String, dynamic>{
        'profile': {'name': 'Amar'},
        'week_lookahead': weekLookahead,
        'swaps_left': Map<String, int>.from(swapsLeft),
        for (var i = 0; i < decoyCount; i++) 'decoy_$i': decoy,
      };

      // Preconditions (self-verifying, per rule 21 — no hand-arithmetic).
      final wlLen = jsonEncode(weekLookahead).length;
      final decoyLen = jsonEncode(decoy).length;
      expect(wlLen, greaterThan(decoyLen),
          reason: 'precondition: week_lookahead must be the single BIGGEST '
              'non-kept field (bigger than any one decoy), or an unprotected '
              'trim loop would pick a decoy first and this fixture would not '
              'traceably exercise the keep-set addition');
      final totalLen = jsonEncode(fixture).length;
      expect(totalLen, greaterThan(8500),
          reason: 'precondition: the fixture must start oversized');

      final trimmed =
          AiSnapshotBuilder.trimSnapshotToBudget(fixture, budget: 8500);

      expect(jsonEncode(trimmed).length, lessThanOrEqualTo(8500));
      expect(trimmed['week_lookahead'], weekLookahead,
          reason: 'week_lookahead must survive the trim UNCHANGED (keep set) '
              'even though it is the single biggest non-kept field pre-fix');
      expect(trimmed['swaps_left'], swapsLeft,
          reason: 'swaps_left must survive the trim UNCHANGED (keep set)');
      // At least one decoy absorbed the shrink instead — proves the loop
      // actually ran (not merely "nothing needed trimming").
      final survivingDecoys =
          List.generate(decoyCount, (i) => 'decoy_$i').where(trimmed.containsKey).length;
      expect(survivingDecoys, lessThan(decoyCount),
          reason: 'a decoy field must be the one that shrank/was removed, '
              'not week_lookahead or swaps_left');
    });
  });
}
