---
bug_id: e2d6b8
date: 2026-08-06
batch: deps-board-equipment (Unit 3 — the OI-53 equipment-exclusions flip)
status: fixed
blast_radius: platform
symptom: >
  A user opens Edit Profile, selects the equipment they do NOT have (e.g. cables),
  and saves. The selection persists and syncs to cloud. Their generated plan then
  prescribes exercises requiring exactly that equipment. The app collected a
  preference, stored it, synced it, and silently ignored it.
concept: equipment_exclusion_filter
sot_registry_entry: equipment_exclusion_filter
writers: >
  lib/features/profile/screens/edit_profile_screen.dart:1686 writes
  profile['equipment_exclusions'] (the ⑥ C1 Customize UI, shipped lit 2026-07-16).
  lib/core/services/sync/sync_profile.dart:200 projects it to the cloud column
  user_profile.equipment_exclusions text[].
readers: >
  lib/shared/repositories/plan_engine/plan_generator.dart:140-142 via
  TrainingHistoryAnalyzer.resolveEquipmentExclusions(flagEnabled:) and
  lib/shared/repositories/plan_engine/plan_generator.dart:298-308 (⑥ C2 WU-2
  hasGymOverride). BOTH readers were gated on
  PlanEngineFlags.equipmentExclusionsEnabled, which defaulted to FALSE, so both
  read an empty set regardless of what the writer stored.
hive_key_prefix: "userBox['profile'] (map key 'equipment_exclusions'); flag key in configBox"
hive_key_formula: >
  profile map key 'equipment_exclusions' -> List<String> of canonical equipment
  tokens. Flag key was configBox['enable_equipment_exclusions'] (absent = OFF);
  it is now configBox['disable_equipment_exclusions'] (absent = ON).
sync_methods: >
  SyncService.syncOnboarding / syncProfile fan-out — sync_profile.dart:200 already
  guarded by SyncService._hasValue, unchanged by this fix.
restore_methods: >
  _restoreUserProfile (sync_profile.dart) rehydrates the profile map including
  equipment_exclusions. Unchanged by this fix — the field already round-tripped;
  only its CONSUMPTION was dark.
cloud_table: user_profile
cloud_columns: equipment_exclusions text[]
contract_test_path: test/contracts/equipment_exclusion_filter_behavioral_test.dart
ist_handling: not_applicable — no date keys, counters or windows in this path.
provider_invalidations: >
  None added. The flip changes generation output only; existing Edit-Profile save
  already invalidates userProfileProvider + dietPlanProvider, and a plan is
  regenerated through the normal advance/regen paths.
telemetry_op_types: >
  No NEW op_type constant, but the flip makes an existing telemetry path REACHABLE
  for the first time, and the first draft of this doc wrongly said "None added"
  (corrected by round-1 review). training_history_analyzer.dart:187-189 calls
  ErrorTelemetry.recordNonFatal with reason
  'training_history_analyzer_equipment_exclusions' from the catch around the
  profile read. Pre-flip that try block was UNREACHABLE — flagEnabled:false
  returned `const {}` at :174 before it. Post-flip, production callers pass no
  param, so every generation now reads userBox and any StateError / corrupt
  profile emits a non-fatal. Observed live in the test harness, which has no open
  HiveUserSession ("Bad state: HiveUserSession not opened"). Production callers
  (onboarding plan tap, phase advance, coach regen, edit-profile) all run after
  HiveUserSession.openForUser, so the expected production rate is zero; the catch
  is deliberately NOT silenced because a StateError here would mean generation is
  running pre-session, which is a real signal worth seeing
  (feedback_observability_silent_drop.md).
cross_account_guard: >
  Unchanged and still enforced. resolveEquipmentExclusions reads the profile via
  the user-scoped box (wrapUserScopedBox); the test run shows the expected
  "HiveUserSession not opened" guard message when a harness generates without an
  open session, and it degrades to an empty exclusion set rather than leaking.
forbidden_patterns_checked: >
  No Container(color:+decoration:); no raw Hive.box in a widget; no new
  .functions.invoke; no unawaited without an error sink; no secrets; no new
  schema column refs (the cloud column already exists and is already in
  backups/live_schema_columns.json).
proposed_fix: >
  Flip PlanEngineFlags.equipmentExclusionsEnabled to DEFAULT ON, converting the
  gate from an opt-in `enable_equipment_exclusions` key to a
  `disable_equipment_exclusions` kill-switch — the same shape as the four sibling
  default-ON flags in the same file (disable_injury_universal_filter,
  disable_warmup_injury_filter, disable_detraining_decay,
  disable_cardio_goal_default). The pre-flip path stays fully reachable via the
  kill-switch, per §4.6.
regression_test_planned: >
  test/contracts/equipment_exclusion_filter_behavioral_test.dart — new case
  "DEFAULT (no config key at all): exclusions are HONOURED — the flip". It asserts
  behaviour with NO config key present (the state of every real install), which is
  the only condition that discriminates the flip: every pre-existing test in the
  file drives setFlag() explicitly and therefore passes both before and after.
  PROVEN by mutation: reverting the getter to the pre-flip default makes it fail
  with "Expected: false / Actual: <true>" — cables prescribed to a cables-excluding
  user. Includes a kill-switch negative control asserting the old path still works.
impact_analysis: >
  Two behaviours ride this single flag and the second is much wider than the first.
  (1) The exclusion filter itself — affects only users who set an exclusion; they
  stop being prescribed equipment they said they lack. (2) ⑥ C2's WU-2 gym-cardio
  gate — hasGymOverride stops being null, and per diagnose b7a4e2 the predicate it
  deferred to was ALWAYS FALSE on the generated path, so gym-cardio warmup/finisher
  pools (Treadmill/Bike) now activate for EVERY gym-tier user, including those who
  set no exclusions at all. Users on basic_gym/full_gym will see Treadmill/Bike
  appear in warmup and finisher where they previously got bodyweight cardio. That
  is the intended b7a4e2 fix finally taking effect, but it is a visible plan change
  for a large share of users and is the reason this flip is NOT "inert for anyone
  who ignores the feature".
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "plan_engine_flags.dart getter inverted to the disable_ kill-switch; 3 behavioral-test setFlag helpers inverted; flutter analyze = 0 errors / 0 warnings (240 infos, all pre-existing style + deprecation notices)" }
  - { tier: 2_hive_local_state, status: fixed_in_this_batch, evidence: "configBox key moved enable_equipment_exclusions -> disable_equipment_exclusions. NO migration needed: the old key was never set on any device (the flag was never flipped), so there is no stored value to carry and absent-key now correctly means ON" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "user_profile.equipment_exclusions text[] already exists (present in backups/live_schema_columns.json); no schema change in this batch" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no data migration — the column's already-stored values simply stop being ignored by the client reader" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration in this batch; backups/applied_migrations.json untouched" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "plan generation is local Dart per CLAUDE.md 4.4 rule 8 — no Edge Function reads this flag or this column" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron path reads equipmentExclusionsEnabled — grep of readers returned only the 2 plan_generator.dart sites" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no policy change; the column stays under the existing user_profile RLS" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage buckets or objects involved in plan generation" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret or API key involved — the generator makes no network call" }
  - { tier: 11_external_services, status: not_applicable, evidence: "no Razorpay / OneSignal / Firebase surface touched" }
  - { tier: 12_client_server_contract, status: verified, evidence: "the write->sync->restore chain for equipment_exclusions was already complete and is untouched by this fix; only the client-side consumption gate moved. Confirmed by reading edit_profile_screen.dart:1686 and sync_profile.dart:200 directly rather than inferring from the flag" }
---

# e2d6b8 — equipment exclusions were collected, stored, synced, and then ignored

## What the user saw

Edit Profile → Customize equipment → deselect the items you don't own → Save.
The chips persist across app restarts and across devices (the field syncs). Then
the plan generator hands you a cable fly.

## Root cause

This is not writer/reader field drift — the field name matched at every hop. It is
a **half-shipped flag**: the ⑥ C1 Customize UI (the *collection* half) shipped lit
on 2026-07-16, while the *consumption* half stayed behind
`enable_equipment_exclusions`, which defaulted to OFF and was never flipped.

`plan_generator.dart:140-142` calls
`TrainingHistoryAnalyzer.resolveEquipmentExclusions(equipmentExclusions, flagEnabled: PlanEngineFlags.equipmentExclusionsEnabled)`.
With the flag OFF that helper returns `{}` **without reading the profile at all**,
so every downstream `.isNotEmpty`-guarded drop (queryV4 att1-4, the att5 pool skip,
the L2 custom-append, the L6 demote-swap) was inert.

The reason it survived 3 weeks unnoticed is instructive: from inside the code
everything looked correct and intentional — the flag was *documented* as ship-dark,
the tests all passed, and the UI's own doc comment said in as many words that "the
exclusions only shape the plan once `enable_equipment_exclusions` flips." Nothing
was broken; a decision had simply never been taken. The defect only becomes visible
from the user's side, where "I told the app and it ignored me" is indistinguishable
from a bug.

## Why the existing tests could not catch it

Every test in `equipment_exclusion_filter_behavioral_test.dart` drives the flag
explicitly through a `setFlag(bool)` helper. That means all of them pass identically
before and after the flip — none of them ever exercises the **default**, which is
the only state a real device is ever in. This is the input-set-width failure mode:
the suite was wide on behaviour and blind on configuration.

The new case fixes exactly that by deleting every flag key and asserting on the
pristine default, and it was proven to discriminate by mutation rather than assumed
to.

## The fix

`PlanEngineFlags.equipmentExclusionsEnabled` now reads
`configBox['disable_equipment_exclusions'] != true` with a `catch` default of
`true`, matching the four sibling default-ON flags in the same file. The old
behaviour remains reachable by setting the kill-switch, satisfying §4.6's
"old path preserved verbatim, reachable when gate closed".

## Related

- `b7a4e2` — the WU-2 gym-cardio gate that rides this same flag. Its fix has been
  merged since 2026-07-17 but has been **inert in production ever since**, because
  its activation was gated on this flag. Flipping here is what finally lands it,
  and it is the wider half of this change's blast radius (see `impact_analysis`).
- **OI-53** — the other twelve workout-generator ship-dark flags. This one was
  separated out because it was a live broken promise rather than a dormant feature;
  the remaining twelve stay dark pending their own per-flag decisions.
- **OI-89** — the equipment *tier* is a soft preference (a bodyweight user can still
  be served gym exercises). This flip makes the item-level *exclusion* a HARD
  constraint while leaving the tier heuristic soft, which is precisely the
  distinction OI-89 exists to resolve. It does not close OI-89.
