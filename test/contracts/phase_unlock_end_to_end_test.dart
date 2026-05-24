// test/contracts/phase_unlock_end_to_end_test.dart
//
// Contract — Theme F + F-NEW (closes-diagnose ec4d27).
//
// Pins the end-to-end phase-unlock flow:
//   1. _GenerateNextPhaseButton extracted as ConsumerStatefulWidget so
//      we can drive _isGenerating loading state.
//   2. Four lifecycle telemetry events fired on the unlock path:
//      phase_unlock_initiated → phase_unlock_gate_routed_pro|free →
//      phase_unlock_plan_generated → phase_unlock_completed.
//   3. updateProgress write includes `plan_generated_at` (cloud column
//      sync_profile.dart:165 already accepts it).
//   4. Canonical provider invalidation batch after successful unlock:
//      currentPlanProvider, todayWorkoutProvider, calendarWeekProvider,
//      workoutStatsProvider, streakProvider, allExercisePRsProvider,
//      aiInsightProvider, graduationStatsProvider.
//   5. Success snackbar shown before navigation.
//   6. F-NEW root cause fix: UserRepository.updateProgress fires
//      `unawaited(SyncService.instance.syncProgressNow())` so cloud
//      user_progress catches up on every mutation (pre-fix only the
//      workout-completion path fired syncProgressNow → cloud was 20+
//      days stale on the founder's account).
//
// Source-grep with comment-stripping per
// `feedback_source_grep_strip_comments_first.md`.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('graduation_screen — _GenerateNextPhaseButton + telemetry + invalidations', () {
    final src = File('lib/features/train/screens/graduation_screen.dart')
        .readAsStringSync();
    final stripped = _stripComments(src);

    test('extracts CTA into ConsumerStatefulWidget _GenerateNextPhaseButton', () {
      expect(
        stripped.contains(
            'class _GenerateNextPhaseButton extends ConsumerStatefulWidget'),
        isTrue,
        reason: 'CTA must live in a ConsumerStatefulWidget so we can drive '
            '_isGenerating loading state. Pre-fix it was a stateless lambda; '
            'button looked dead during multi-second generation.',
      );
    });

    test('_isGenerating state drives button disabled + spinner', () {
      expect(
        stripped.contains('bool _isGenerating = false'),
        isTrue,
        reason: 'must declare _isGenerating state.',
      );
      expect(
        RegExp(r'onPressed:\s*_isGenerating\s*\?\s*null').hasMatch(stripped),
        isTrue,
        reason: 'button must be disabled while generating — onPressed: '
            '_isGenerating ? null : _onTap.',
      );
    });

    test('emits all 4 lifecycle telemetry events', () {
      const required = [
        'phase_unlock_initiated',
        'phase_unlock_gate_routed_pro',
        'phase_unlock_gate_routed_free',
        'phase_unlock_plan_generated',
        'phase_unlock_completed',
      ];
      for (final ev in required) {
        expect(
          stripped.contains("'$ev'"),
          isTrue,
          reason: 'must emit $ev telemetry — needed to debug the next '
              '"button did nothing" report.',
        );
      }
    });

    test('updateProgress write includes plan_generated_at', () {
      expect(
        stripped.contains("'plan_generated_at'"),
        isTrue,
        reason: 'graduation unlock must stamp plan_generated_at in the '
            'updateProgress call — cloud user_progress.plan_generated_at '
            'column already accepts it via sync_profile.dart:165 but the '
            'caller never wrote it.',
      );
    });

    test('invalidates the canonical provider set after successful unlock', () {
      const required = [
        'currentPlanProvider',
        'todayWorkoutProvider',
        'calendarWeekProvider',
        'workoutStatsProvider',
        'streakProvider',
        'allExercisePRsProvider',
        'aiInsightProvider',
        'graduationStatsProvider',
      ];
      for (final p in required) {
        expect(
          stripped.contains('ref.invalidate($p)'),
          isTrue,
          reason: 'must invalidate $p after phase unlock — matches the '
              'post-workout-completion canonical batch from '
              'train_provider.dart:1494-1500.',
        );
      }
    });

    test('shows success snackbar before navigation', () {
      // "Phase $nextPhase unlocked — opening your new plan…" with accent
      // color (not bad color). Pre-fix the user got no feedback on success.
      expect(
        stripped.contains('unlocked — opening your new plan'),
        isTrue,
        reason: 'success snackbar message must reassure the user the unlock '
            'fired — pre-fix only the error path had a snackbar.',
      );
    });

    test('navigates to /train AFTER success snackbar fires', () {
      // Both must be in the success branch; navigation guarded by mounted.
      final idx = stripped.indexOf('phase_unlock_completed');
      expect(idx, greaterThan(-1));
      final tail = stripped.substring(idx);
      // Snackbar comes BEFORE go('/train') in the same branch.
      final snackbarIdx = tail.indexOf('unlocked — opening your new plan');
      final goIdx = tail.indexOf("context.go('/train')");
      expect(snackbarIdx, greaterThan(-1));
      expect(goIdx, greaterThan(-1));
      expect(snackbarIdx < goIdx, isTrue,
          reason: 'success snackbar must render BEFORE context.go(/train)');
    });
  });

  group('UserRepository.updateProgress fires syncProgressNow (F-NEW)', () {
    final src = File('lib/shared/repositories/user_repository.dart')
        .readAsStringSync();
    final stripped = _stripComments(src);

    test('imports SyncService', () {
      expect(
        stripped.contains(
            "import 'package:icanbefitter/core/services/sync_service.dart'"),
        isTrue,
        reason: 'UserRepository must import SyncService — F-NEW root '
            'cause was no callsite firing syncProgressNow from the '
            'progress mutation surface.',
      );
    });

    test('updateProgress fires unawaited(syncProgressNow)', () {
      // Pin the actual call. Inside the method body.
      final idx = stripped.indexOf('Future<void> updateProgress');
      expect(idx, greaterThan(-1));
      // Take a window large enough to cover the body.
      final tail = stripped.substring(idx, idx + 1200);
      expect(
        RegExp(r'unawaited\s*\(\s*SyncService\.instance\.syncProgressNow\(\)')
            .hasMatch(tail),
        isTrue,
        reason: 'updateProgress must fire unawaited(SyncService.instance'
            '.syncProgressNow()) after saveProgress — pre-fix only '
            'train_provider.dart:1485 fired syncProgressNow, so phase '
            'unlock + edit profile + other paths accumulated in Hive '
            'without reaching cloud (20+ days stale on founder).',
      );
    });
  });
}
