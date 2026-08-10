// audit-2026-05-11 Phase 7 — full sign-up + onboarding traverse.
//
// Critical untested flow: cold launch → Welcome → email sign-up →
// terms accept → Mission Brief → Identity → Goal → Stats → Details
// → Plan REPORT FOR DUTY → home. The 6-screen stepped onboarding
// flow (lib/features/onboarding/CLAUDE.md) has no end-to-end coverage; each screen has
// widget tests but the inter-screen state-passing (via GoRouter
// state.extra) is exercised only by manual smoke testing.
//
// Run:
//   flutter test --dart-define-from-file=.env \
//     integration_test/flows/signup_onboarding_traverse_test.dart \
//     --flavor dev

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Sign-up + onboarding 6-screen traverse', () {
    test('T1 — Welcome → BEGIN ENLISTMENT routes to /restoring then /onboarding/mission-brief',
        () {
      // Per lib/features/onboarding/CLAUDE.md: new users (no user_profile row) route
      // through RestoringScreen → MissionBriefScreen, not directly
      // to /onboarding.
    }, skip: 'Phase 7 scaffold — needs Supabase Auth test mode.');

    test('T2 — Mission Brief CONTINUE preserves no state to Identity',
        () {
      // Mission Brief is read-only — no answers collected. Identity
      // is step 01 · 05.
    }, skip: 'Phase 7 scaffold — needs Supabase Auth test mode.');

    test('T3 — Identity captures full_name + DOB + sex, propagates to /goal extras',
        () {
      // Verify GoRouter state.extra carries the 3 fields forward.
    }, skip: 'Phase 7 scaffold — needs Supabase Auth test mode.');

    test('T4 — Goal → Stats → Details state-passing preserves all answers',
        () {
      // Each step spreads `...widget.initial` into outgoing extras.
      // Test that REPORT FOR DUTY on Plan has all 14 fields collected.
    }, skip: 'Phase 7 scaffold — needs Supabase Auth test mode.');

    test('T5 — REPORT FOR DUTY writes user_profile + sets onboarding_completed_at',
        () {
      // OnboardingNotifier.completeOnboarding does the upsert +
      // stamps onboarding_completed_at. Verify cloud row exists +
      // routing lands at /home.
    }, skip: 'Phase 7 scaffold — needs Supabase Auth test mode.');

    test('T6 — H-3 full_name self-heal: email-signup user with real local name',
        () {
      // Verify post-onboarding the cloud users.full_name reflects the
      // value entered on Identity, NOT email.split("@").first.
    }, skip: 'Phase 7 scaffold — needs Supabase Auth test mode.');

    test('T7 — abandoned mid-onboarding user resumes at first missing step',
        () {
      // Sign out after Identity, sign back in: RestoringScreen
      // detects user_profile row exists + onboarding_completed_at
      // NULL, routes to /onboarding/goal.
    }, skip: 'Phase 7 scaffold — needs Supabase Auth test mode.');
  });
}
