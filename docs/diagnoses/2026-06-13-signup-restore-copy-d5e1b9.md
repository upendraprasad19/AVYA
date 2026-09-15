---
bug_id: d5e1b9
date: 2026-06-13
batch: e2e-obs-fixes
status: fixed
blast_radius: account
symptom: >
  Obs#1 (live web E2E, founder report): "when i created a new account (because
  i had clicked on signup) why was i shown 'loading your account'? it should say
  something like account creation in progress." RestoringScreen is the post-auth
  gate for EVERY authed user; its title is driven by
  SyncService.restoreProgressLabel ("Pulling your dispatch." → "Loading profile
  & plan" → …) and a fixed "Stand by, soldier." subtitle — restore-flavored from
  the first paint. A brand-new signup (StartMissionBrief) and a mid-onboarding
  user have NOTHING to restore, yet they saw the restore copy for the ~0.3-1s
  window before resolveDestination returned + navigation away.
concept: signup_aware_restore_copy
sot_registry_entry: not_applicable
contract_test_path: test/contracts/restoring_signup_copy_test.dart
writers: >
  lib/features/auth/screens/restoring_screen.dart — the title now reads a local
  `_statusLabel` (neutral "Getting you ready…", set to "Setting up your account…"
  for StartMissionBrief + mid-onboarding) UNLESS `_useRestoreLabel` is true, which
  only _goHome (the returning-user GoHome path) sets.
readers: >
  RestoringScreen's title Text (ValueListenableBuilder over
  SyncService.restoreProgressLabel) — now gated behind `_useRestoreLabel`.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: "not_applicable"
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - "Unconditional restore-label title in RestoringScreen — now gated on _useRestoreLabel (true only for the returning-user GoHome path). Pinned by test/contracts/restoring_signup_copy_test.dart."
proposed_fix: >
  Copy-only, no change to the (sensitive) parallel restore + bg-restore
  structure. Add `_statusLabel` (neutral "Getting you ready…") + `_useRestoreLabel`
  (default false). The title shows the live SyncService restore label ONLY when
  `_useRestoreLabel` is true; _goHome flips it true for returning users (real
  cloud data). StartMissionBrief + mid-onboarding ResumeOnboarding set
  `_statusLabel = "Setting up your account…"`. New/incomplete users never see the
  restore copy.
regression_test_planned: >
  test/contracts/restoring_signup_copy_test.dart — source-grep (comment-
  stripped): the restore-label ValueListenableBuilder is gated by _useRestoreLabel
  (not unconditional); StartMissionBrief sets a setup label; _goHome sets
  _useRestoreLabel = true.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "restoring_screen copy gated on _useRestoreLabel; flutter analyze clean; restoring_signup_copy_test green" }
impact_analysis: >
  Account/UX blast radius. First-impression copy for every new signup — the
  founder's exact complaint. The fix is purely which string renders; the parallel
  restore kickoff + bg-restore path (c5a1f2 / 4e8b1d) are untouched, so no
  slow-boot / cross-account risk. A returning user still sees the live restore
  progress labels (correct). Minor known inefficiency left as-is (a new signup
  still kicks off + cancels a no-op restore) — harmless, and removing it would
  perturb the sensitive parallel structure for no user-visible gain.
---

# New signup sees restore-flavored "loading" copy (d5e1b9)

## What happened
RestoringScreen's title is `SyncService.restoreProgressLabel` (restore-flavored)
from first paint. A brand-new signup has nothing to restore but saw "Pulling your
dispatch." / "Loading profile & plan" before navigating to Mission Brief.

## Fix
Title reads a neutral local `_statusLabel` ("Getting you ready…" → "Setting up
your account…" for new/mid-onboarding) unless `_useRestoreLabel` is true, which
only the returning-user `_goHome` path sets. Parallel-restore structure untouched.

## See also
- lib/features/auth/screens/restoring_screen.dart
- test/contracts/restoring_signup_copy_test.dart
