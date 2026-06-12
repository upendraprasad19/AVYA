---
bug_id: f1b6d4
date: 2026-06-13
batch: e2e-obs-fixes
status: fixed
blast_radius: account
symptom: >
  Obs#6 (live web E2E): the onboarding plan-PREVIEW card (plan_screen step 05)
  showed "2867 KCAL" but the SAVED + home-displayed daily_calories was 3200 — the
  number the user commits to differed from the number they get. Root cause: the
  preview (plan_screen._computeTargets) and the commit
  (OnboardingNotifier.completeOnboarding) passed DIFFERENT inputs to the same
  BmrCalculator.calculateTargets:
  (1) activity — preview read widget.data['activity_level'] directly (default
  'moderate'); the commit IGNORES it and DERIVES activityLevel via
  resolveActivityLevel(lifestyle_activity, days/week) (the lifestyle-activity
  system). (2) body fat — the preview passed bodyFatPercent (→ Katch-McArdle BMR);
  the commit omits it (→ Mifflin-St Jeor). Both pushed the numbers apart. The goal
  arg already matched (both pass _mapGoal(widget.data['goal'])).
concept: onboarding_preview_commit_calc_parity
sot_registry_entry: not_applicable
contract_test_path: test/contracts/plan_screen_targets_match_completeOnboarding_test.dart
writers: >
  lib/features/onboarding/screens/plan_screen.dart (_computeTargets) — the
  preview now derives activityLevel via BmrCalculator.resolveActivityLevel and
  omits bodyFatPercent, exactly mirroring completeOnboarding's inputs.
readers: >
  The plan-screen preview card (daily_calories + protein); the saved profile's
  daily_calories (unchanged) is the source-of-truth they must now agree with.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: user_profile
cloud_columns: "daily_calories (read-parity only; the SAVED value is unchanged)"
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - "plan_screen preview passing a DIFFERENT named-arg set to calculateTargets than completeOnboarding (e.g. an extra bodyFatPercent, or activity_level read directly instead of resolveActivityLevel). Pinned by test/contracts/plan_screen_targets_match_completeOnboarding_test.dart (arg-set equality + resolveActivityLevel in both)."
proposed_fix: >
  CONSERVATIVE direction — align the PREVIEW to the COMMIT (which produces the
  saved value), so the preview shows the number the user actually gets, with ZERO
  change to any user's saved daily_calories. plan_screen._computeTargets now:
  derives activityLevel via resolveActivityLevel(lifestyle_activity, days/week)
  and does NOT pass bodyFatPercent. Created the parity test that onboarding/
  CLAUDE.md already referenced but that never actually existed (the reason the
  drift shipped undetected).
regression_test_planned: >
  test/contracts/plan_screen_targets_match_completeOnboarding_test.dart — the two
  calculateTargets calls must pass the IDENTICAL named-arg set, and both must
  derive activity via resolveActivityLevel. Catches the body-fat presence drift +
  the activity-derivation drift + any future arg drift.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "preview mirrors completeOnboarding's calculateTargets inputs; flutter analyze clean; plan_screen_targets_match_completeOnboarding_test green" }
impact_analysis: >
  Account/UX blast radius. Fixes the founder-reported drift (preview 2867 vs saved
  3200) completely + conservatively (no change to any saved target). SURFACED,
  NOT DEFERRED — an adjacent calc-ACCURACY question for founder decision (broad
  blast-radius, changes all NEW users' saved targets, so out of scope for this
  drift fix): the SAVED calc (completeOnboarding) currently (a) IGNORES the user's
  stats-screen activity_level pick (uses the lifestyle-activity system, with
  lifestyle_activity defaulting to 'desk_job' when unset) and (b) does NOT pass
  body_fat_pct to calculateTargets (Mifflin-St Jeor even when body fat is known).
  If the founder wants the saved target to honour those inputs (more accurate),
  that is a separate, founder-gated change that would alter every user's saved
  daily_calories. This diagnose flags it; the drift itself is fixed + pinned.
---

# Onboarding plan-preview calories drift from the saved value (f1b6d4)

## What happened
The step-05 preview showed 2867 kcal; the committed profile saved 3200. The
preview and commit fed different inputs to BmrCalculator.calculateTargets:
preview read activity_level directly + passed body fat; the commit derived
activity via the lifestyle-activity system + omitted body fat.

## Fix
Align the preview to the commit (the saved value): derive activity via
resolveActivityLevel, omit bodyFatPercent. No saved-data change. Created the
parity test onboarding/CLAUDE.md referenced but that never existed.

## Surfaced for founder (NOT deferred — the drift is fixed)
The saved calc ignores the stats activity_level pick + body_fat_pct. Making it
honour them is more accurate but changes every user's saved target — a separate,
founder-gated decision.

## Hermes correction (2026-06-13)
The first fix attempt had the preview read `widget.data['lifestyle_activity']` —
a key NO stepped screen writes, so it always fell back to `desk_job` and STILL
drifted for non-sedentary users (the Hermes E-pass caught this as P1). The
COMPLETE fix extracts the activity_level→lifestyle_activity switch to shared
`BmrCalculator.lifestyleFromActivityLevel`; the preview (`_computeTargets`) and
the commit-prep (`_onReportForDuty`) both derive via it → preview == saved by
construction. The parity test gained a behavioral value-level assertion (arg-NAME
parity alone couldn't catch the value drift — the reason it shipped).

## See also
- lib/features/onboarding/screens/plan_screen.dart (_computeTargets)
- lib/features/onboarding/providers/onboarding_provider.dart (completeOnboarding)
- test/contracts/plan_screen_targets_match_completeOnboarding_test.dart
