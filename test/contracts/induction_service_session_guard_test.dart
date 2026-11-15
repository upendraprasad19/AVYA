// Regression guard — diagnose 2026-05-30-induction-redirect-session-race.
//
// Bug: GoRouter._authRedirect (app_router.dart `isOnCoachInduction` branch)
// calls InductionService.instance.inductionCompleted during redirect. That
// getter reads the USER-SCOPED `coachBox`, which throws
//   "Bad state: HiveUserSession not opened — cannot wrap user-scoped box
//    coachBox"
// when the redirect fires at cold-start BEFORE HiveUserSession.openForUser
// has run (web reload / deep-link / process-death restore onto /coach/*).
// The exception escapes the redirect → GoRouter renders its error page
// ("Page Not Found").
//
// Fix: InductionService.inductionCompleted + hasCommitted short-circuit to
// `false` when no Hive session is open (HiveUserSession.currentOwnerFullId
// == null), BEFORE touching coachBox. "Session not open yet" is a safe
// not-completed default — the induction screen re-evaluates once the
// session opens.
//
// This test exercises the guard behaviorally: with NO session opened
// (currentOwnerFullId == null at process start), both getters return false
// instead of throwing. On `main` (pre-fix) the getters reach
// `HiveService.instance.coachBox` and throw — this test fails. With the fix
// they short-circuit and return false — this test passes.
//
// Run: flutter test test/contracts/induction_service_session_guard_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/ai_coach/services/induction_service.dart';

void main() {
  group('InductionService session-open guard (diagnose 2026-05-30 induction '
      'redirect session race)', () {
    test('no Hive session open → currentOwnerFullId is null (precondition)',
        () {
      // Fresh process: openForUser has never run.
      expect(HiveUserSession.currentOwnerFullId, isNull,
          reason: 'precondition — no user-scoped session opened in this test');
    });

    test('inductionCompleted returns false (no throw) when no session is open',
        () {
      // Pre-fix: this reaches HiveService.instance.coachBox and throws
      // "HiveUserSession not opened". Post-fix: short-circuits to false.
      expect(
        () => InductionService.instance.inductionCompleted,
        returnsNormally,
        reason:
            'inductionCompleted must not throw when the session is not open — '
            'the GoRouter redirect calls it at cold start before openForUser.',
      );
      expect(InductionService.instance.inductionCompleted, isFalse,
          reason:
              'with no session, induction state is unknown → safe default is '
              'not-completed (false), letting the induction flow re-evaluate.');
    });

    test('hasCommitted returns false (no throw) when no session is open', () {
      expect(
        () => InductionService.instance.hasCommitted,
        returnsNormally,
        reason:
            'hasCommitted must not throw when the session is not open — it '
            'reads the same user-scoped coachBox as inductionCompleted.',
      );
      expect(InductionService.instance.hasCommitted, isFalse);
    });
  });
}
