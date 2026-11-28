---
bug_id: c7b4d2
date: 2026-09-26
batch: reuse-audit-fixes (founder-requested reuse audit)
status: fixed
blast_radius: account
symptom: |
  Found by the reuse audit (two separate referral redeem paths). The sign-up
  step's REFERRAL CODE field was redeemed only by the sign-in screen's
  `AuthStatus.success` listener, reading its own `_referralController`. With
  email confirmation on, `signUpWithEmail` ends with `AuthStatus.info` (no
  session), so the listener never fired; the user then confirms by email and
  signs in on a fresh screen whose field is empty. The code was silently
  dropped. Even with confirmation off, that redeem ran BEFORE onboarding had
  upserted the `users` row the redeem-referral EF reads. The code was also
  written to configBox `pending_referral_code` "for retry on next launch", but
  nothing ever read that key (user_config_migrator's comment claimed a reader
  that did not exist).
  Live check 2026-09-26: 3 redemptions in total, the latest on 26 June.
concept: referral_redemption
sot_registry_entry: referral_redemption
related_bugs:
  - d2b9e6 — welcome-stash redeem path fixed at onboarding (the correct redeem point this fix reuses)
  - 2d1c8a — referral readers/writers bypassing the repository
recurrence: no — first instance of a sign-up field redeemed on the wrong auth transition.
writers:
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "AuthNotifier.signUpWithEmail(referralCode:) — stores the trimmed code in auth user metadata `referral_code` via signUp(data:)", line: 416 }
  - { file: lib/features/auth/screens/sign_in_screen.dart, method_or_widget: "CREATE ACCOUNT passes _referralController.text; the success-listener redeem + pending_referral_code writes REMOVED", line: 1115 }
readers:
  - { file: lib/features/onboarding/providers/onboarding_provider.dart, method_or_widget: "resolveReferralCode(stash, userMetadata) — Welcome stash wins, else the sign-up metadata", line: 190 }
  - { file: lib/features/onboarding/providers/onboarding_provider.dart, method_or_widget: "_syncOnboardingAndPostActions — redeem-referral AFTER the users upsert (unchanged)", line: 734 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: "auth.users raw_user_meta_data (referral_code key); redeem-referral EF unchanged"
cloud_columns: []
contract_test_path: test/contracts/referral_signup_metadata_behavioral_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Metadata belongs to the auth user, so it cannot follow a
  different account on the same device — unlike a configBox stash would.
forbidden_patterns_checked:
  - "a configBox pending key read at onboarding — rejected (plan-review R1-6): device-local, lost if the user confirms on another device, and shared across accounts on one device."
  - "deleting pending_referral_code from _intentionallyShared — rejected: that list is documentation-only; devices from before this fix may still hold the key, and it must stay out of the user-scoped migration. Its false comment is corrected instead."
proposed_fix: |
  signUpWithEmail gains referralCode and passes data: {'referral_code': code}
  when non-empty. The sign-in listener no longer redeems. Onboarding redeems
  resolveReferralCode(stash, currentUser.userMetadata) after the users upsert.
  Replay is bounded: completeOnboarding refuses to run for an onboarded user,
  and the EF rejects a second redemption per referee.
regression_test_planned:
  - test/contracts/referral_signup_metadata_behavioral_test.dart (new, 7) — pure resolveReferralCode table (stash wins, metadata fallback, blank/non-string → '') + wiring pins (signUp data:, CREATE ACCOUNT passes the field, sign-in has no redeem-referral / pending_referral_code, onboarding reads userMetadata).
mutation_proven: |
  resolveReferralCode ignoring metadata → 1 of 7 red (fallback). Priority
  inverted (metadata before stash) → 1 of 7 red (stash wins). Both compiled.
impact_analysis: |
  A code typed at email sign-up now reaches redemption whether or not email
  confirmation is on and on whichever device the user finishes onboarding.
  Residual, unchanged: redeem-referral enforces a 7-day signup window
  (redeem-referral/index.ts:32,93-94), so onboarding finished more than 7 days
  after sign-up is refused — same as Profile → Apply Referral.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze clean; 50/50 test/auth + 23 referral/config tests green." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "2026-09-26 read-only query: 3 referral redemptions total, latest 26 June." }
  - { tier: 12, name: "Client → server contract", status: verified, evidence: "supabase_flutter signUp(data:) writes raw_user_meta_data; the EF reads only the code in the body, unchanged." }
---

## Summary

A referral code typed at email sign-up was lost whenever email confirmation
was on, because it was redeemed on a sign-in success that never came. It now
travels in the auth user's metadata and onboarding redeems it at the same
point the Welcome-screen code already is.

## Device check owed

Sign up with email and a referral code, confirm by email, sign in and finish
onboarding. Profile should show the +7 days PRO.
