// Batch 5 regression guard — 2026-06-07 comprehensive-audit remediation.
//
// Source-presence guards (comments stripped) for the honest-surface / dead-code /
// restore / UX-flow fixes whose regression shape is "a specific string must (not)
// appear in a specific file". The DATA writer→reader contracts have their own
// behavioural files:
//   F2  → test/contracts/deployments_complete_writer_to_reader_test.dart
//   F5  → test/contracts/weight_logs_writer_to_reader_test.dart
//
// Diagnose-docs:
//   docs/diagnoses/2026-06-07-honest-surface-integrity-e2a1f7.md      (F10, F21, F26)
//   docs/diagnoses/2026-06-07-rank-deadcode-restore-drift-c4d9b2.md   (F18, F39)
//   docs/diagnoses/2026-06-07-ux-flow-restore-correctness-a8e3c5.md   (F3,F14,F25,F29,F37,F38,F40,F42)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strip /* */ and // comments so prose can't satisfy (or break) a `.contains`.
String _strip(String s) {
  final noBlock = s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return noBlock
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');
}

String _read(String path) => _strip(File(path).readAsStringSync());

void main() {
  group('Honest surface — no fabricated/misleading UI (F10, F21, F26)', () {
    test('F10: AI-insight rail is an honest static cheat-sheet, not a fake AI "quick win"', () {
      final s = _read('lib/features/home/widgets/ai_insight_card.dart');
      expect(s.contains('PROTEIN CHEAT SHEET'), isTrue,
          reason: 'the static rail must be labelled honestly as a fixed reference');
      expect(s.contains('QUICK WINS'), isFalse,
          reason: 'F10: "QUICK WINS" under the live-AI eyebrow implied per-user AI personalisation');
    });

    test('F21: sign-in carries no fabricated head-count', () {
      final s = _read('lib/features/auth/screens/sign_in_screen.dart');
      expect(s.contains('18,866'), isFalse,
          reason: 'F21: pre-launch app — the "18,866 sailors active" count was invented');
      expect(s.contains('SAILORS ACTIVE'), isFalse);
      expect(s.contains('FOUNDING COHORT'), isTrue,
          reason: 'honest belonging cue replaces the fabricated number');
    });

    test('F26: today-workout card shows no fake kcal + no PUSH-DAY mislabel default', () {
      final s = _read('lib/features/train/widgets/today_workout_card.dart');
      expect(s.contains('340'), isFalse,
          reason: 'F26: "~340 kcal" was a static fake shown for every workout');
      expect(s.contains("'PUSH DAY'"), isFalse,
          reason: 'F26: default dayType "PUSH DAY" mislabelled any non-keyword workout');
      expect(s.contains("'TRAINING DAY'"), isTrue, reason: 'neutral default label');
    });
  });

  group('Dead-code + writer/reader drift removed (F18, F39)', () {
    test('F18: dead next-rank "workoutsRemaining" path removed from both rank surfaces', () {
      final rank = _read('lib/core/services/rank_service.dart');
      final record = _read('lib/features/profile/widgets/service_record_section.dart');
      expect(rank.contains('workoutsRemaining'), isFalse,
          reason: 'F18: no kRankGates entry sets totalWorkoutsAtLeast → the field was always null');
      expect(record.contains('workoutsRemaining'), isFalse,
          reason: 'F18: the "in ~N workouts" branch was dead (input always null)');
    });

    test('F39: workout-log restore no longer writes the dropped sets_completed column', () {
      final s = _read('lib/core/services/sync/sync_workout.dart');
      expect(s.contains("'sets_completed': map['sets_completed']"), isFalse,
          reason: 'F39: migration 067 dropped workout_logs.sets_completed (cloud 100% NULL)');
    });
  });

  group('Restore completeness (F37, F38)', () {
    test('F37: sleep-log restore paginates via _fetchAllRows (no 1000-row truncation)', () {
      final s = _read('lib/core/services/sync/sync_health.dart');
      expect(RegExp(r"_fetchAllRows\(\s*'sleep_logs'").hasMatch(s), isTrue,
          reason: 'F37: a bare .from(sleep_logs).select() truncated at the PostgREST 1000-row cap');
    });

    test('F38: every-launch lightweight restore re-anchors the workout plan', () {
      final s = _read('lib/core/services/sync_service.dart');
      final start = s.indexOf('restoreLightweightAlways(String userId)');
      expect(start, greaterThan(-1), reason: 'restoreLightweightAlways must exist');
      final nextFut = s.indexOf('Future<', start + 30);
      final body = s.substring(start, nextFut > start ? nextFut : s.length);
      expect(body.contains('_restoreWorkoutPlan'), isTrue,
          reason: 'F38: plan_start drift from another device was never re-anchored on a normal launch');
    });
  });

  group('UX flow correctness (F3, F14, F25, F29, F40, F42)', () {
    test('F3: streak explainer describes the real per-day algorithm, not weekly-80%', () {
      final s = _read('lib/features/home/widgets/streak_explainer_sheet.dart');
      expect(s.contains('80%'), isFalse,
          reason: 'F3: the streak is +1 per completed scheduled day, never weekly-80%');
    });

    test('F14: profile nudge yields the <80% band to the top CompletenessNudge', () {
      final s = _read('lib/features/home/widgets/profile_nudge_card.dart');
      expect(s.contains('percentage < 80'), isTrue,
          reason: 'F14: below 80% ProfileNudgeCard must hide so the user sees only one nudge');
    });

    test('F25: plan-expired paywall passes the display token, not the gate key', () {
      final s = _read('lib/features/train/widgets/plan_expired_card.dart');
      expect(s.contains("feature: 'Phases 2-12'"), isTrue,
          reason: 'F25: PaywallSheet switches on the display token; the gate key fell to the generic subtitle');
      expect(s.contains('featurePhases2To12'), isFalse,
          reason: 'F25: must not pass the gate KEY as the paywall feature arg');
    });

    test('F42: plan-expired copy is Wardroom voice (no generic-wellness emoji)', () {
      final s = _read('lib/features/train/widgets/plan_expired_card.dart');
      expect(s.contains('\u{1F389}'), isFalse, reason: 'F42: 🎉 is generic-wellness drift');
      expect(s.contains('secured, Recruit'), isTrue, reason: 'endowed-progress Wardroom lead');
    });

    test('F29: cart-auditor usage chip uses the USED convention like its siblings', () {
      final s = _read('lib/features/nutrition/widgets/cart_auditor_section.dart');
      expect(s.contains('USED'), isTrue,
          reason: 'F29: cart_auditor showed REMAINING while scan + food-logger showed USED');
    });

    test('F40: progress-photo capture handles PhotoQuotaException (paywall / snackbar)', () {
      final s = _read('lib/features/profile/screens/progress_photos_screen.dart');
      expect(s.contains('on PhotoQuotaException'), isTrue,
          reason: 'F40: an uncaught quota throw stuck the _uploading spinner forever');
      expect(s.contains('showPaywallSheet'), isTrue,
          reason: 'F40: a free user who hits the cap must be shown the paywall');
    });
  });
}
