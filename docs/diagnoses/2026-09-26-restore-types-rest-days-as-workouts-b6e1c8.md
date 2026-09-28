---
bug_id: b6e1c8
date: 2026-09-26
batch: day-swapper-sync-load
status: fixed
blast_radius: platform
symptom: |
  `_restoreScheduledWorkouts` (lib/core/services/sync/sync_workout.dart:1904-2135, the reinstall
  restore path) derives the local `type` field as "template resolved -> custom_template, else the
  existing local type, else template_id present ? custom_template : workout" (:2097-2100). It IGNORES
  the cloud `status` column entirely, so a cloud rest day restored onto a fresh install becomes
  `type: workout` + `status: rest` with no exercises, stamped `source: 'cloud_restore'` (:2132). Live,
  read-only check cited from spec §1.4 (2026-09-26): 28 such rows exist across 3 users' `plan_json`
  backups, dated 2026-05-31 through 2026-08-16; all 28 have `source = cloud_restore`, 27 of 28 have no
  exercises, and the matching `scheduled_workouts` cloud row says `rest` in every one of the 28 cases.
  The daily plan push (`weeklyFullSync`) then copies these hybrids into the `plan_json` backup, so they
  persist there independent of the local device. `PlanIntegrityReconciler.needsHeal`
  (lib/core/services/plan_integrity_reconciler.dart:96-107) treats such a row as a planned workout
  that lost its exercises — the exact shape the `a7d3f1` repair targets — so the plan-heal path (called
  from `restoring_screen.dart:492` and `heal_after_restore.dart:44`, verify at plan time) fires on
  these rows and can never fix them, because healing re-derives exercises for a "workout" day that
  should never have been typed `workout` at all.
concept: restore_type_derivation
sot_registry_entry: restore_type_derivation (re-pointed by Task 31 — Task 29 registered the concept
  at docs/sot_registry.yaml:13036; this is the reader-side half of schedule_arrangement_stamp's
  writer/reader pair — `_restoreScheduledWorkouts` is a second, independent writer of the same hybrid
  shape that d5a1e7's restore-merge fix does not cover, because d5a1e7 fixes `_restoreWorkoutPlan`'s
  merge, not this separate reinstall-only restore path)
writers:
  - { file: lib/core/services/sync/sync_workout.dart, method: "_restoreScheduledWorkouts (type derivation ignores cloud status)", line: 1904 }
  - { file: lib/core/services/sync_service.dart, method: "weeklyFullSync (copies the hybrid into the plan_json backup on every daily push)", line: 1343 }
readers:
  - { file: lib/core/services/plan_integrity_reconciler.dart, method: "needsHeal (misreads the hybrid as a workout that lost its exercises)", line: 96 }
  - { file: lib/shared/repositories/plan_engine/plan_engine_flags.dart, method: isRestDayConsideringLogged, line: 499 }
hive_key_prefix: "schedule_ — the per-date row _restoreScheduledWorkouts writes and every rest/workout-type reader reads"
hive_key_formula: "schedule_${formatDateKey(date)}"
sync_methods: [weeklyFullSync]
restore_methods: [_restoreScheduledWorkouts]
cloud_table: scheduled_workouts
cloud_columns: [status, type, template_id]
contract_test_path: "must add: test/services/schedule_hybrid_repair_migrator_test.dart (one-time
  per-user repair of hybrid rows, D10: gated on a workoutBox flag so a second account on the same
  device is also repaired) plus a case in test/sync/restore_merge_invariants_test.dart
  for invariant I8 (no merge path produces a type:workout + status:rest row)"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a for the writer/reader fix itself (it operates on the current session's own
  restored rows); the repair migrator is explicitly per-account rather than per-device (plan deviation
  D10), gated on a workoutBox flag rather than the device-scoped migrationBox other migrators use, so
  a second account signing into the same device is also repaired."
forbidden_patterns_checked:
  - { pattern: "Guessing which of type or status is authoritative for the single live hybrid that DOES have exercises, instead of leaving it alone with telemetry", absent: true }
  - { pattern: "Repairing only the 28 live rows in the cloud backup without also fixing the writer, which would let new hybrids keep appearing on every future reinstall", absent: true }
proposed_fix: |
  `_restoreScheduledWorkouts` derives `type: rest` when the cloud `status` is `rest` and no template
  resolves for that date (sync_workout.dart:2097-2100), instead of falling through to `workout`/
  `custom_template`. A one-time Hive migrator with the same shape as the other `*_migrator.dart` files
  (`lib/core/services/schedule_hybrid_repair_migrator.dart`, new) turns existing local rows matching
  `status: rest` + a workout type + no exercises into `type: rest`, covering the 28 hybrids already in
  live backups once they reach a device running the fixed client; the next plan push then carries the
  fix into the backup itself. The single live hybrid that DOES have exercises is left alone, with a
  telemetry event, because it is ambiguous and in the past — choosing a winner would be a guess, not a
  fix. Every merge output additionally passes through a normalizer (plan deviation D5:
  `mergeScheduleEntry(null, snapshot)` currently copies a hybrid snapshot row as-is, so without this
  step the 28 hybrids would re-enter through a fresh restore even after the writer fix) that converts
  `status: rest` + workout type + no exercises to `type: rest` at merge time too, so both the reinstall
  path and the lightweight-restore merge path are covered.
regression_test_planned: |
  A behavioral test drives `_restoreScheduledWorkouts` with a fixture cloud row shaped exactly like the
  28 live hybrids (status: rest, no template resolves, no local existing type) and asserts the restored
  local row is `type: rest`, not `workout`. `schedule_hybrid_repair_migrator_test.dart` seeds a
  pre-existing hybrid row in Hive, runs the migrator, and asserts it becomes `type: rest`; a second
  case seeds the one ambiguous hybrid WITH exercises and asserts the migrator leaves it untouched and
  emits the documented telemetry event. Invariant I8 in
  `test/sync/restore_merge_invariants_test.dart` asserts no combination of merge inputs
  (L1/L2/L3 plus the new normalizer) can produce a `type: workout` + `status: rest` row. Mutation proof
  planned: reverting the `:2097-2100` derivation to the pre-fix fallthrough order must redden the
  behavioral restore test; disabling the normalizer must redden I8.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "The type-derivation fix at sync_workout.dart's _restoreScheduledWorkouts and the merge-output normalizer (D5) landed in Task 21 (commit 82bd604e, fix1 5c0c00ff); the one-time repair migrator (ScheduleHybridRepairMigrator) landed in Task 23 (commit 9ffb48a1). test/services/schedule_hybrid_repair_migrator_test.dart green; test/sync/ 246/246 at Task 23 integration." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "The repair migrator (commit 9ffb48a1) rewrites existing local schedule_<date> rows from the hybrid shape to type: rest, gated on a workoutBox flag per D10 (per-account, not device-scoped migrationBox, so a second account on the same device is also repaired); also deletes the two dead swaps_this_week/swap_week_start keys and strips the stale userBox['progress'] plan_json copy in the same pass." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL is needed; the fix corrects how the client derives a local field from an existing cloud column." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Spec §1.4's own live, read-only investigation (2026-09-26) found 28 hybrid rows across 3 users' plan_json backups, all source=cloud_restore, 27 of 28 with no exercises, all matching a scheduled_workouts row of status=rest. This drafting pass cites that evidence and did not re-query the database." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration is needed; this is a pure client-side type-derivation and local-repair fix." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function reads or derives the schedule row's type field." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job is involved in the restore or repair path." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No RLS policy change; the existing own-rows read of scheduled_workouts and user_progress is unchanged." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No Storage bucket or object is involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret is involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "None involved." }
  - { tier: 12, name: client_to_server_contract, status: fixed_in_this_batch, evidence: "commit 82bd604e: the restore reader now derives the local type from the cloud status the writer actually encodes, instead of ignoring it — the writer/reader agreement this whole diagnose-doc concept is named for." }
impact_analysis: |
  Severity: P2, latent but real. 28 confirmed live rows across 3 users show a genuinely scheduled rest
  day rendering as a workout with no exercises after a reinstall, and `needsHeal` cannot self-correct
  it because it misclassifies the row as a workout that needs its exercises re-derived rather than as a
  rest day that was mistyped. Every affected user sees a broken "workout" card with nothing in it on
  what should be a rest day, and the daily plan push keeps re-persisting the wrong shape into the
  backup until this fix and its one-time repair land.
related_bugs: [a7d3f1]
---

# Restore types a cloud rest day as a workout (28 live rows, spec §1.4)

## Relationship to a7d3f1 and to d5a1e7 (this batch's own restore-merge fix)

`a7d3f1` (2026-06-06) fixed the reconciler's merge repairing a planned workout row that lost its
exercises. `d5a1e7` (this batch) fixes the SAME `mergeScheduleEntry` merge over-applying that repair
to rest rows during `_restoreWorkoutPlan`. This diagnose-doc (`b6e1c8`) is a DIFFERENT, independent
writer of the identical hybrid shape: `_restoreScheduledWorkouts`, the reinstall path that populates
schedule rows from `scheduled_workouts` directly rather than from the `plan_json` merge. Fixing d5a1e7
alone would not close this bug, because `_restoreScheduledWorkouts` never calls `mergeScheduleEntry` —
it has its own independent type-derivation logic. Both writers are fixed in this one batch (spec
§5.7's "Repair of existing hybrids" and D5).

## Why this is not a recurrence

`docs/diagnoses/INDEX.md` grepped for `hybrid`, `status: rest`, `restore` alongside `a7d3f1` found only
the a7d3f1 entry itself (the related-but-distinct precedent noted above) and no prior diagnose for a
cloud rest day being restored as a workout. Filed as new, with `a7d3f1` recorded under `related_bugs`
for the shared mechanism.

## Fix ownership in the plan

- The `_restoreScheduledWorkouts` type-derivation fix and the merge-output normalizer (D5): Task 21
  (coordinator, Wave 2) — bundled with d5a1e7's L1/L3 merge work since both touch the same restore
  code paths. Landed `82bd604e`; review Minors fixed in `5c0c00ff`.
- The one-time repair migrator (`schedule_hybrid_repair_migrator.dart`), gated per-account per D10:
  Task 23 (coordinator, Wave 2). Landed `9ffb48a1`.

## Commits

`82bd604e`, `5c0c00ff`, `9ffb48a1`.

## Mutation evidence

Task 21's normalizer/type-derivation mutations are recorded in
docs/diagnoses/2026-09-26-day-swap-reverts-after-restart-d5a1e7.md's Mutation evidence section
(mutation 7, "delete `cloudStatus == 'rest' ? 'rest' :` clause" → 1 red, exact match — that IS this
bug's type-derivation fix; both diagnose-docs cite the same commit `82bd604e` for the same lines).

Task 23 (`9ffb48a1`, `ScheduleHybridRepairMigrator`), 6 legs, restored via backup-and-diff (never
`git checkout --`):

| # | Mutation | Confirm-applied | Reds | Failure reason |
|---|---|---|---|---|
| 1 | `hasExercisesLeaveAlone` branch → `needsTypeFix` | count 1→0 | 2 | non-empty-exercises classify test + "leaves a with-exercises hybrid alone" behavioral assertion |
| 2 | Delete the first `isRestHybrid(row)` check | count 1→0 | 5 (brief predicted 3) | the two `needsTypeFix` classify tests + the first behavioral test, PLUS the flag-gating and D10 tests — both also seed a no-exercise hybrid and assert `repaired == 1`, which the brief's estimate didn't trace through; all 5 verified genuine (no compile errors) |
| 3 | Delete the `hasRun()` short-circuit block | 2→1 (brief's baseline of 1 was wrong — `hasRun()` shares the same literal) | 1 | "the flag genuinely gates re-runs": the row is repaired again on the second call |
| 4 | Delete `await MigratedKey.delete('swaps_this_week')` | count 1→0 | 1 | first behavioral test's `isNull` assertion on the migrated key fails (key survives) |
| 5 | Delete the `plan_json` strip block | `progress.containsKey('plan_json')` count 1→0 | 1 | first behavioral test's `isFalse` assertion fails |
| 6 | Delete the `schedule_hybrid_left_alone` telemetry line | count 1→0 | 1 | first behavioral test's telemetry-events assertion fails; the row-left-alone assertion itself stays green |

All 6 compiled and ran (no compile-error-as-proof); mutation 2's actual red count (5) exceeding the
brief's estimate (3) was investigated and explained, not accepted at face value (rule 21).
