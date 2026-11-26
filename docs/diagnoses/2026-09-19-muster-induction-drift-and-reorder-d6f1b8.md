---
bug_id: d6f1b8
date: 2026-09-19
batch: web-onboarding-e2e-bug-batch
status: fixed
blast_radius: account
symptom: >
  Founder-flagged verbosity + a live writer/reader-drift bug found while
  investigating it. Muster asked 3 questions (injuries, wake/workout time,
  physique focus) AFTER the induction narrative's "I COMMIT" button — so a
  user's commitment moment was immediately followed by more forms, undercutting
  the intended closing beat. Two of the three questions were also flat
  duplicates: injuries was ALSO collected during onboarding's Details screen,
  and wake/workout-time has full self-service UI in Edit Profile. Tracing the
  injuries duplication surfaced a live bug, not just redundant UX: muster's
  per-answer profile bridge (`InductionService._bridgeToProfile`) has no
  "don't clobber" guard, and since muster always runs AFTER onboarding, its
  injuries answer silently OVERWROTE whatever the user told Details — the
  LAST answer wins, regardless of which was correct. Checking the remaining
  muster keys systematically (not just the two the founder asked about)
  surfaced a THIRD instance of the same pattern: physique focus
  (`body_part_priorities` in coachBox) vs `profile['physique_focus']` (Edit
  Profile) — the AI coach's snapshot read the coachBox mirror, which nothing
  ever updates after muster, so an Edit Profile change made AFTER muster left
  the AI coach's context permanently stale.
concept: muster_to_profile_bridge
sot_registry_entry: muster_to_profile_bridge
contract_test_path: test/contracts/muster_to_profile_bridge_behavioral_test.dart
writers: >
  lib/features/ai_coach/services/induction_service.dart — `_allowedMusterKeys`
  reduced to only `body_part_priorities` (known_injuries / typical_wake_time /
  preferred_workout_time / why_now / definition_of_winning all now rejected by
  `recordMusterAnswer`'s ArgumentError guard); `completeMuster()` renamed to
  `completeInduction()` and its call site moved from MusterScreen to
  InductionScreen's `_onCommit()`, since muster is no longer the last step.
  lib/features/ai_coach/screens/muster_screen.dart — rewritten from a
  3-question, index-dispatched flow to a single physique-focus question with
  no progress bar; on submit it navigates to `/coach/induction` instead of
  calling `completeMuster()` and going to `/home`.
  lib/features/ai_coach/screens/induction_screen.dart — `_onCommit()` now
  calls both `recordCommitment()` and `completeInduction()` before navigating
  to `/home` directly; msg3's copy rewritten (no longer promises a muster
  that already happened).
  lib/features/onboarding/screens/plan_screen.dart — both un-inducted routing
  destinations changed from `/coach/induction` to `/coach/muster`.
readers: >
  lib/features/ai_coach/services/ai_snapshot_builder.dart
  `_getInductionAndMusterKeys()` — known_injuries/typical_wake_time/
  preferred_workout_time/body_part_priorities now read `profile['injuries']`
  /`profile['wake_up_time']`/`profile['preferred_workout_time']`/
  `profile['physique_focus']` directly instead of the muster-only coachBox
  mirror, so the AI coach's context reflects whichever screen (onboarding,
  muster, or a later Edit Profile change) most recently set the value.
  lib/core/router/app_router.dart `_authRedirect`'s `isOnCoachInduction`
  guard is UNCHANGED — it gates on the single terminal `induction_completed_at`
  flag regardless of which sub-screen sets it, so the reorder needed no
  router changes.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: [syncCoachMemoryNow, syncProfileNow, pushSnapshot]
restore_methods: []
cloud_table: user_profile
cloud_columns: "injuries, wake_up_time, preferred_workout_time, physique_focus (all pre-existing columns — no schema change; only which in-process reader is consulted changed)"
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - "recordMusterAnswer must reject known_injuries/typical_wake_time/preferred_workout_time — a live caller sending them is a regression back to the double-ask/clobber bug. Pinned by test/contracts/muster_profile_bridge_test.dart and test/contracts/muster_to_profile_bridge_behavioral_test.dart (throwsArgumentError cases)."
  - "ai_snapshot_builder.dart must not read known_injuries/typical_wake_time/preferred_workout_time/body_part_priorities from coachBox for the snapshot — must read the profile fields instead. Pinned by test/ai_coach/snapshot_keys_test.dart's new 'coachBox-only write no longer reaches the snapshot' case, which proves the OLD behavior is gone, not just that the new one works."
  - "muster_screen.dart must not call showTimePicker — the wake/workout-time question is retired, not merely hidden. Pinned by test/contracts/responsive_picker_host_test.dart."
proposed_fix: >
  (1) Remove muster's injuries and wake/workout-time questions entirely —
  injuries stays Details screen's job (onboarding already collects it with no
  clobber risk), wake/workout-time stays Edit Profile's job (already has full
  UI). recordMusterAnswer rejects all three retired keys outright, closing the
  writer path rather than leaving it reachable-but-unused. (2) Repoint
  ai_snapshot_builder.dart's 4 affected keys at the PROFILE fields — the same
  fields Edit Profile itself writes — so the AI coach's context can never go
  stale relative to whichever screen last touched the data. (3) Reorder the
  post-Plan sequence: muster's one remaining question (physique focus) now
  runs BEFORE the induction narrative + I COMMIT, so nothing is asked after
  the user commits — I COMMIT becomes the true final action, going straight
  to /home. (4) Trim induction msg3's copy (no longer references a muster
  that already happened, no longer cites a stale question count).
regression_test_planned: >
  test/contracts/muster_question_count_test.dart — rewritten: pins the
  single-question contract (no progress bar, no Q3/Q4 remnants, completion
  navigates to /coach/induction not /home). test/contracts/
  muster_profile_bridge_test.dart — rewritten: the 3 retired keys now assert
  throwsArgumentError with no Hive write on either side; body_part_priorities
  bridge behavior unchanged. test/contracts/
  muster_to_profile_bridge_behavioral_test.dart — rewritten to pin the
  surviving body_part_priorities bridge with the same rigor previously given
  to injuries (direct Hive reads, additive-patch test), plus a new case
  proving the 3 retired keys throw and write nothing. test/onboarding/
  induction_idempotency_test.dart + muster_persistence_test.dart — updated
  for the completeMuster→completeInduction rename and the routing
  destination change. test/ai_coach/snapshot_keys_test.dart — new case
  proves a coachBox-only write (the old muster path) no longer reaches the
  snapshot for the 4 repointed keys — the actual regression proof, not just
  that profile writes now do.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "induction_service.dart, muster_screen.dart, induction_screen.dart, plan_screen.dart, ai_snapshot_builder.dart all updated; flutter analyze clean; 6 test files updated/rewritten, all asserting the NEW contract including explicit absence of the OLD behavior" }
  - { tier: 3, layer: postgres_schema, status: not_applicable, evidence: "no schema change — injuries/wake_up_time/preferred_workout_time/physique_focus columns on user_profile already existed and are unchanged; only the in-process READER of local Hive state changed" }
impact_analysis: >
  Account blast radius — touches the mandatory post-onboarding induction
  flow every new user goes through, plus the AI coach's context-building
  path used on every chat turn. The clobber bug (muster silently overwriting
  Details' injuries answer) was a live, currently-shipped correctness defect
  independent of the reorder — any user who answered injuries differently in
  muster than in Details was silently getting the WRONG one persisted. The
  reorder itself is UI/UX only (confirmed via the router's terminal-flag
  guard being order-agnostic) and carries no data-migration risk: existing
  users' pre-existing coachBox answers for the 3 retired keys are undisturbed
  and still migrate to profile via the unchanged one-shot
  backfillMusterToProfileIfNeeded for any user who hasn't already been
  backfilled.
---

# Muster/induction writer-drift + "nothing after commit" reorder (d6f1b8)

## What happened

Two threads converged from the same investigation. The founder's verbosity
complaint led to auditing whether muster's questions duplicated data
collected elsewhere. Tracing `known_injuries`'s readers (per the
writer/reader-drift discipline — name every reader before proposing a
removal) surfaced that `InductionService._bridgeToProfile` writes muster's
injuries answer into `profile['injuries']` on EVERY answer, with no check
for whether the user already gave a real answer during onboarding's Details
screen. Since muster always runs after onboarding, **muster's answer always
wins**, silently discarding whatever the user told Details — a live SoT
violation, not just double-asking.

The founder's separate question — "do we have to collect wake up and
workout time? People can set it from Edit Profile" — traced to: Edit
Profile already has full UI for both fields, onboarding's own stepped flow
never asks for them, and the one thing that DOES depend on `wake_up_time`
(the `morning-alert` cron) already degrades gracefully for a null value (a
07:00 IST fallback quarter, not silence — correcting an initial assumption
that it would go silent).

Checking the remaining muster keys systematically (not just the two
questions already in scope) surfaced a THIRD instance of the identical
pattern: `body_part_priorities` (muster, coachBox) vs
`profile['physique_focus']` (Edit Profile). Unlike the other two, physique
focus has no other collection point and no bridge running in the reverse
direction — so an Edit Profile change made AFTER muster left the AI coach
snapshot silently stale forever, with no way for it to self-correct.

Separately, the founder asked whether nothing should be asked after "I
COMMIT" — since muster's questions ran immediately after the commitment
narrative, the emotional close of "Contract sealed" was undercut by more
forms right after it.

## Fix

- Injuries and wake/workout-time removed from muster entirely —
  `recordMusterAnswer` now rejects them outright (not merely stops being
  called), closing the writer path rather than leaving unused capability.
- `ai_snapshot_builder.dart` repointed at the profile fields for all 4
  affected keys, so the AI coach's context is correct regardless of which
  screen most recently touched the data — fixing the staleness bug for
  physique_focus as a side effect of the same change.
- Muster (now just physique focus) moved to run BEFORE the induction
  narrative; I COMMIT is now the true last action, going straight home.
- Induction's msg3 copy rewritten to close rather than promise more
  questions.

## Why the reorder needed no router changes

`app_router.dart`'s redirect guard treats `/coach/induction` and
`/coach/muster` as one bucket, gated on a SINGLE terminal flag
(`induction_completed_at`) — it doesn't care which sub-screen sets that flag
or in what order the two screens run. Confirmed by reading the guard before
proposing the reorder, rather than assuming.

## See also

- `lib/features/ai_coach/services/induction_service.dart`
- `lib/features/ai_coach/screens/muster_screen.dart`
- `lib/features/ai_coach/screens/induction_screen.dart`
- `lib/features/ai_coach/services/ai_snapshot_builder.dart`
- `lib/features/onboarding/screens/plan_screen.dart`
- `docs/snapshot_contract.yaml`
- Companion diagnose (picker bugs, same batch):
  `docs/diagnoses/2026-09-19-onboarding-picker-textwrap-and-unresponsive-e2b8a4.md`
