---
bug_id: 4018b3
date: 2026-09-28
batch: reps-secs-invalidation-fixes
status: fixed
blast_radius: account
symptom: |
  Found during plan-review round 2 of this same batch (context-blind,
  independent audit that started from a different angle than round 1:
  every top-level Provider/NotifierProvider under lib/features/*/providers/
  that computes from DateTime.now(), cross-checked against
  day_rollover_service.dart's invalidation list). Not founder-observed
  directly — confirmed present by code before being counted as a bug, per
  this repo's no-false-positive discipline.
concept: day_rollover_provider_invalidation
sot_registry_entry: |
  day_rollover_provider_invalidation — extends the EXISTING concept
  (docs/sot_registry.yaml:1390), same shape as bugs 9c8958/bae4dd/b1bfea
  found earlier in this same batch. referralEligibilityProvider is
  presence_only: true (see below) — a behavioral test is not feasible
  because its staleness driver is real wall-clock time against a
  Supabase-auth-sourced signup date, with no Hive-mutable proxy and no
  existing test seam for injecting a fake `SupabaseService.instance.currentUser`.
writers:
  - { file: lib/core/services/day_rollover_service.dart, method_or_widget: "_doRolloverWithRef — new invalidate call", line: 273 }
readers:
  - { file: lib/features/profile/providers/referral_eligibility_provider.dart, method_or_widget: "referralEligibilityProvider — FutureProvider body", line: 26 }
  - { file: lib/features/profile/screens/profile/profile_content.dart, method_or_widget: "Apply Referral Code CTA — ref.watch(referralEligibilityProvider)", line: 388 }
hive_key_prefix: "N/A — no Hive read; computes from SupabaseService.instance.currentUser.createdAt"
hive_key_formula: "N/A"
sync_methods:
  - "N/A — pure read, no writes of its own"
restore_methods:
  - "N/A"
cloud_table: "N/A — reads Supabase auth's createdAt directly, not a table row"
cloud_columns: []
ist_handling:
  - { file: lib/features/profile/providers/referral_eligibility_provider.dart, method_or_widget: "computeDaysRemaining — uses raw DateTime.now(), NOT the istDateStr/istMidnight seam (pre-existing, out of scope for this fix — a device-local vs IST skew of a few hours at the boundary is a much narrower issue than the missing invalidation itself)", line: 20 }
provider_invalidations:
  - referralEligibilityProvider
telemetry_op_types:
  success:
    - day_rollover_all_providers_invalidated
  failure: []
cross_account_guard: "ref.watch(authUserIdTokenProvider) inside the provider resets on auth change. Not affected by this fix."
forbidden_patterns_checked:
  - { pattern: "referralEligibilityProvider performing a write (write-on-read anti-pattern)", absent: true }
proposed_fix: |
  Add `ref.invalidate(referralEligibilityProvider);` to
  `DayRolloverObserver._doRolloverWithRef`. Unlike weeklyReportDataProvider
  (bug b1bfea, same batch), this provider already had a working write-time
  invalidation (on redemption success, `profile_content.dart:430`) — the
  ONLY gap was the day-boundary leg, a single clean addition with no
  fan-out complexity, so fixed directly rather than filed as an OI.
contract_test_path: test/contracts/day_rollover_provider_invalidation_writer_to_reader_test.dart
regression_test_planned: |
  - test/contracts/day_rollover_provider_invalidation_writer_to_reader_test.dart
    (source-grep, PRESENCE-ONLY — this concept's SOLE regression coverage,
    see presence_only_reason below): asserts the exact substring
    'ref.invalidate(referralEligibilityProvider)' appears in
    day_rollover_service.dart — deliberately checking the full CALL, not
    just the bare provider name, because this same file's explanatory
    comments mention several provider names in prose (a bare-name check
    would stay green even if the real call were deleted, as long as a
    comment nearby still named the provider).
  Mutated and run: DELETING the `ref.invalidate(referralEligibilityProvider);`
  line entirely (not merely commenting it out — a `//`-prefixed line still
  contains the checked substring, which a first attempt at this mutation
  incorrectly assumed would redden and did not) reddened the presence test
  with `Expected: true, Actual: <false>`.
presence_only: true
presence_only_reason: |
  A genuine write→stale→invalidate→fresh behavioral test (matching Tests
  D/E/F for streakFreezeProvider/weeklyNutritionProvider/weeklyReportDataProvider)
  is not feasible for this provider: `daysRemaining` is computed purely
  from `DateTime.now().difference(signupDate).inDays` where `signupDate`
  comes from `SupabaseService.instance.currentUser.createdAt` — a FIXED
  value from the real auth session, not a Hive-mutable value a test can
  write a new version of to simulate staleness. There is no existing
  mock/override seam for `SupabaseService.instance.currentUser` anywhere
  in this test suite (confirmed via `grep -rln "SupabaseService.instance.currentUser\s*=\|mockCurrentUser" lib/ test/`
  — zero results), and building one is a separate, larger effort than this
  single invalidation fix warrants. The presence test above is this
  concept's sole regression coverage, and its mutation-proof (delete, not
  comment-out) is why it can be trusted despite being presence-only.
impact_analysis: |
  Scoped to: the Profile screen's "Apply Referral Code — N DAYS LEFT" CTA
  staying pinned to whatever `daysRemaining` was cached at first Profile-tab
  visit, for the rest of the app session — since Profile lives under
  StatefulShellRoute.indexedStack (never disposed on tab switch, the same
  fact b1bfea's diagnose-doc cites for weeklyReportDataProvider), a user
  who opens Profile once and leaves the app running across the real
  7-day window's expiry would keep seeing an expired offer as if it were
  still live, until an auth change or a redemption attempt.

  No impact on:
  - The referral REDEMPTION logic itself — unaffected, already correct.
  - `ReferralRepository.hasRedeemed` — unaffected.
  - Any other provider in the invalidation list — untouched.

  Real-world severity: narrow window (the CTA showing slightly stale for
  users who never background the app across the exact day it should flip)
  and cosmetic (tapping an expired-looking-live CTA just re-shows the
  apply sheet, which would itself re-validate server-side — no double-grant
  risk). Included in this batch because it is the SAME confirmed bug class
  already fixed 3 times in this batch, found by the same audit process,
  per CLAUDE.md §4.2's no-deferrals policy.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "day_rollover_service.dart now invalidates referralEligibilityProvider in _doRolloverWithRef. Mutation-proven: deleting the line reddened the presence test." }
---

## Summary

`referralEligibilityProvider` (the Profile screen's "Apply Referral Code"
countdown CTA) had a working write-time invalidation but was never
invalidated on day-rollover. Found by plan-review round 2's independent
audit, applying the same rollover-invalidation lens this batch already
used 3 times.

## Root Cause

Writer: `referralEligibilityProvider`'s `FutureProvider` body
(`referral_eligibility_provider.dart:26`) computes `daysRemaining` fresh
from `DateTime.now()` on every rebuild — there is no stale-write
component; the underlying signup date never changes.

Reader-invalidation gap: `DayRolloverObserver._doRolloverWithRef`
(`day_rollover_service.dart`) never invalidated this provider — its ONLY
existing invalidation call site (`profile_content.dart:431`) fires on a
successful referral-code redemption, which is unrelated to the day
boundary the CTA's countdown itself depends on.

## Fix

`ref.invalidate(referralEligibilityProvider);` added to
`_doRolloverWithRef`, `day_rollover_service.dart:273`.

## Related

Fourth confirmed instance of the missing-day-rollover-invalidation class
in this batch (after 9c8958/streakFreezeProvider, bae4dd/weeklyNutritionProvider,
b1bfea/weeklyReportDataProvider), all found by the same founder-requested
audit (extended by two independent plan-review rounds) and fixed in the
same batch/commit. See bug ff3131 (usageWeeksProvider, same plan-review
round 2, same fix shape) for the fifth.
