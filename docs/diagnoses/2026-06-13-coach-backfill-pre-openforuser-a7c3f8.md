---
bug_id: a7c3f8
date: 2026-06-13
batch: e2e-obs-fixes
status: fixed
blast_radius: account
recurrence: true
related_bugs: [dc52a4]
symptom: >
  Web boot console (Obs#3, live web E2E): "[main] coach_memory backfill failed:
  Bad state: HiveUserSession not opened — cannot wrap user-scoped box
  \"coachBox\". Call HiveUserSession.openForUser(userId) after sign-in." main()
  dispatched AiCoachRepository.backfillCoachMemoryIfNeeded() at boot — which
  reads the user-scoped coachBox + userBox — BEFORE HiveUserSession.openForUser
  ever runs (openForUser happens later, inside the post-auth restore). So the
  backfill threw and was swallowed every launch: coach_memory was never
  backfilled from legacy coaching_notes for any user.
concept: user_scoped_box_before_openForUser
sot_registry_entry: not_applicable
contract_test_path: test/contracts/coach_backfill_after_openforuser_test.dart
writers: >
  lib/features/auth/screens/restoring_screen.dart — backfill now runs inside
  _ensureOwnershipBeforeHome (foreground path) AND _healAfterRestoreInBackground
  (background-restore path), both AFTER HiveUserSession.openForUser. Removed from
  lib/main.dart.
readers: >
  AiCoachRepository.backfillCoachMemoryIfNeeded → coach_memory_service reads/
  writes the user-scoped coachBox + userBox.
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
  failure: [restoring_coach_memory_backfill, bg_heal_coach_memory]
cross_account_guard: true
forbidden_patterns_checked:
  - "main.dart calling backfillCoachMemoryIfNeeded() (a user-scoped-box op) before HiveUserSession.openForUser — REMOVED; relocated to restoring_screen post-openForUser. Pinned by test/contracts/coach_backfill_after_openforuser_test.dart."
proposed_fix: >
  Remove the main.dart boot dispatch (+ its now-unused AiCoachRepository import);
  call backfillCoachMemoryIfNeeded inside restoring_screen, alongside the dc52a4
  streak/rollover/refill relocations, in BOTH the foreground
  (_ensureOwnershipBeforeHome) and background-restore (_healAfterRestoreInBackground)
  paths — each after openForUser, each wrapped in a non-fatal try/catch with
  ErrorTelemetry.recordNonFatal.
regression_test_planned: >
  test/contracts/coach_backfill_after_openforuser_test.dart — source-grep
  (comment-stripped): main.dart does NOT call backfillCoachMemoryIfNeeded;
  restoring_screen calls it (>=2 times) and references openForUser.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "relocated to restoring_screen post-openForUser (2 paths); main.dart import removed; flutter analyze clean; coach_backfill_after_openforuser_test green" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "the backfill now runs when coachBox/userBox are open (openForUser ran above) — no more Bad-state throw; the dc52a4 relocations in the same method are the proven pattern" }
impact_analysis: >
  Account/boot blast radius. RECURRENCE of §2.21 / dc52a4 (the splash
  pre-openForUser race that killed streak_freeze_refill on every cold start);
  the coach_memory backfill was a sibling dispatch that the dc52a4 sweep did not
  relocate. Effect: coach_memory was never backfilled from legacy coaching_notes,
  so the AI coach lost that historical context for any user upgrading across the
  coaching_notes→coach_memory rename. The relocation mirrors the dc52a4 fix
  exactly (same method, same guarded pattern).
---

# coach_memory backfill ran before openForUser → silent fail every boot (a7c3f8)

## What happened
`main()` called `backfillCoachMemoryIfNeeded()` (reads user-scoped coachBox +
userBox) before `HiveUserSession.openForUser` → `Bad state: HiveUserSession not
opened` → swallowed by the boot try/catch. The backfill never ran.

## Fix
Relocated into `restoring_screen` (foreground `_ensureOwnershipBeforeHome` +
background `_healAfterRestoreInBackground`), after `openForUser` — the same place
dc52a4 moved the streak/rollover/refill backfills. Removed from main.dart.

## See also
- docs/diagnoses/...-dc52a4... (the §2.21 founding incident this recurs from)
- lib/features/auth/screens/restoring_screen.dart (the relocation target)
- test/contracts/coach_backfill_after_openforuser_test.dart
