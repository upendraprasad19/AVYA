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

/// Substring from [decl] to end-of-file, used as "this declaration's body".
///
/// Only valid when [decl] is the LAST top-level declaration in the file, so
/// this asserts exactly that rather than assuming it (round-2 review: the
/// numeric window it replaces could not bound anything, because the function
/// sits 3593 chars from EOF and the window was 6000).
String _bodyToEof(String stripped, String decl) {
  final i = stripped.indexOf(decl);
  expect(i, greaterThan(-1), reason: 'declaration not found: $decl');
  final body = stripped.substring(i);
  // Any further TOP-LEVEL declaration at column 0 means this is NOT the last
  // one and the substring spills into a sibling. B-pass finding 3: the first
  // version matched only `^Future<`, so a later non-Future helper (a `void`, a
  // `class`, a sync getter) that happened to mention the searched string would
  // have silently made this vacuous again — the same shape as the numeric
  // window this helper replaced. Match any top-level declaration start.
  final later = RegExp(
          r'^(Future<|void |class |enum |mixin |extension |String |int |bool |double |List<|Map<|Set<|final |const |@)',
          multiLine: true)
      .allMatches(body)
      .where((m) => m.start > 0)
      .toList();
  expect(later, isEmpty,
      reason: '$decl must remain the file\'s last top-level declaration for '
          'this body extraction to be sound — a new function was added after '
          'it, so re-scope this assertion instead of letting it silently span '
          'into the sibling');
  return body;
}

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
      // Unit B / OI-84 (2026-08-03): `phase_unlock_plan_generated` fires from
      // inside the generate block, which moved to runGraduationPhaseAdvance.
      // The EVENT SET is the contract, not which file emits it — so assert the
      // union across both halves of the unlock path rather than dropping the
      // one that moved. Same "follow the writer, not the literal" reasoning the
      // plan_generated_at test below already applies.
      final advanceStripped = _stripComments(
          File('lib/shared/services/pro_phase_advance.dart').readAsStringSync());
      final unlockPath = stripped + advanceStripped;
      const required = [
        'phase_unlock_initiated',
        'phase_unlock_gate_routed_pro',
        'phase_unlock_gate_routed_free',
        'phase_unlock_plan_generated',
        'phase_unlock_completed',
      ];
      for (final ev in required) {
        expect(
          unlockPath.contains("'$ev'"),
          isTrue,
          reason: 'must emit $ev telemetry — needed to debug the next '
              '"button did nothing" report.',
        );
      }
      // The three that are purely about the TAP must stay on the screen — if
      // they drifted into the shared advance they would stop firing on the
      // paywall branch, which never reaches it.
      for (final ev in [
        'phase_unlock_initiated',
        'phase_unlock_gate_routed_pro',
        'phase_unlock_gate_routed_free',
      ]) {
        expect(stripped.contains("'$ev'"), isTrue,
            reason: '$ev is a tap-time event and must stay in the screen');
      }
    });

    test('the unlock still stamps plan_generated_at — now via the shared '
        'monotonic writer', () {
      // ec4d27's original assertion was `stripped.contains("'plan_generated_at'")`
      // against THIS file. Unit 3c (c8f3d1) moved the progress write into the
      // one shared advance writer, so the literal no longer appears here — but
      // the guarantee ec4d27 exists to protect (the unlock stamps
      // plan_generated_at, which sync_profile.dart pushes to
      // user_progress.plan_generated_at) is unchanged. Following the writer
      // instead of the literal: assert graduation routes through
      // commitPhaseAdvance AND that commitPhaseAdvance stamps the field. A
      // location-pinning grep would have had to be deleted here; this one
      // survives the refactor and still fails if either half breaks.
      //
      // Unit B / OI-84 (2026-08-03): one more hop. The screen no longer calls
      // commitPhaseAdvance directly — it calls runGraduationPhaseAdvance, which
      // does. Chain BOTH links; asserting only the second would pass even if
      // the screen stopped invoking the advance entirely.
      final advanceSrc = _stripComments(
          File('lib/shared/services/pro_phase_advance.dart').readAsStringSync());
      expect(
        stripped.contains('runGraduationPhaseAdvance('),
        isTrue,
        reason: 'graduation unlock must go through the shared graduation '
            'advance (Unit B / OI-84).',
      );
      expect(
        // Round-1 review B4 asked for a bound; round-2 measured the first
        // attempt and showed `{0,6000}` bounds NOTHING — signature→EOF is only
        // 3593 chars, so any window ≥ that is unbounded in effect. A number
        // tuned to the real 2678-char distance would discriminate today and
        // become brittle the moment the function grows.
        //
        // Structural instead of numeric: take the substring from the signature
        // to EOF and assert the call is in it, AND separately assert this
        // function really is the file's LAST top-level declaration — which is
        // what makes "substring to EOF" equal "this function's body". The
        // second assertion is the one the magic number was standing in for, and
        // it cannot rot silently: reorder the file and it fails immediately.
        _bodyToEof(advanceSrc, 'Future<GraduationAdvanceResult> runGraduationPhaseAdvance')
            .contains('commitPhaseAdvance('),
        isTrue,
        reason: 'and that advance must commit through the shared monotonic '
            'writer (Unit 3c / c8f3d1).',
      );
      expect(
        advanceSrc.contains("'plan_generated_at': stamp"),
        isTrue,
        reason: 'commitPhaseAdvance must stamp plan_generated_at — cloud '
            'user_progress.plan_generated_at accepts it via sync_profile.dart '
            'and this is now the only advance path that writes it.',
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
