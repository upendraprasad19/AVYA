---
bug_id: b6d1f4
date: 2026-09-08
batch: regen-wave-alignment
status: fixed
blast_radius: account
related_bugs: [c5a8f3, e3b7d1]
recurrence: >
  Same family as c5a8f3 (Unit B), which made the deload lift a DUAL write — rows plus the
  `current_plan` blob — so the phase-arc strip could never contradict the rows. This is that fix's
  unclosed half: the pair is written correctly and then only one of them is pushed.
symptom: >
  A user whose week-4 deload is lifted, and who then logs nothing before reinstalling or moving
  device, restores a `current_plan` blob that still says `deload` while the restored rows say
  `working`. The phase-arc strip renders a deload node over a working week — the exact
  rows-vs-blob disagreement Unit B shipped to eliminate, arriving through the sync layer instead
  of through the writer.
concept: >
  `_liftWeekFour` writes the rows first (each `upsertScheduled` firing its own unawaited
  `syncWorkoutData()` at `workout_write_service.dart:566`) and the blob afterwards at
  `deload_evaluator.dart:264`. So every fan-out that ran had already snapshotted the PRE-lift
  blob, and the only call after the blob write was `pushSnapshot()`, which does not reach
  `_syncWorkoutPlan` — the method that actually builds `plan_json` from the blob. Its only two
  callers are `weeklyFullSync()` (`sync_service.dart:1143`) and
  `pushWorkoutPlanForSyncDomain()`.

  The post-lift blob therefore reached the cloud only on the next unrelated workout write, or on
  the weekly full sync. Self-healing for an active user; indefinitely stale for one who lifts a
  deload and then stops logging.

  ⚠ Review round 5 reported this as "the lifted blob NEVER reaches plan_json" and that overreached
  — the row writes' own fan-out does reach it. Verifying before acting changed the fix: the defect
  is ORDERING, not absence, and the correct repair is one narrow push after the blob write rather
  than a new fan-out.
sot_registry_entry: deload_working_base_stash
sot_registry_note: >
  No registry change. The writer/reader pair is unchanged; this batch fixes WHEN the already-
  registered blob write is propagated, not what it contains or who reads it.
writers:
  - { file: lib/core/services/deload_evaluator.dart, method: "_liftWeekFour — blob write (week_plans[3].week_character = 'working')", line: 264 }
  - { file: lib/core/services/deload_evaluator.dart, method: "_liftWeekFour — NEW narrow plan push after the blob write, unawaited", line: 287 }
readers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_syncWorkoutPlan — builds plan_json from the current_plan blob", line: 1045 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "currentWaveCharacters — what the phase-arc strip renders", line: 1301 }
hive_key_prefix: current_plan
hive_key_formula: "workoutBox['current_plan']['week_plans'][3]['week_character'] — 'working' after a lift; the value that must reach user_progress.plan_json."
sync_methods: >
  `pushWorkoutPlanForSyncDomain()` (`sync_workout.dart:2053`) → `_syncWorkoutPlan` → upsert into
  `user_progress.plan_json`. Chosen over a full domain sync to keep the added cost minimal on the
  path this runs on.
restore_methods: >
  `_restoreWorkoutPlan` re-applies `plan_json` wholesale. That is exactly why the stale blob was
  user-visible: the restore faithfully reproduced whatever the last successful push contained.
cloud_table: user_progress
cloud_columns: [plan_json]
contract_test_path: test/contracts/deload_eval_behavioral_test.dart
ist_handling:
  - { file: lib/core/services/deload_evaluator.dart, line: 287, fn: "The added call takes no date and builds no key. The surrounding lift already uses istDateStr(nowWall()) for its today-or-future row filter, unchanged by this batch." }
provider_invalidations: >
  None added. The lift's existing rollover path already refreshes the Train surface; this adds a
  network push, not a local state change.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  Preserved — `pushWorkoutPlanForSyncDomain` calls `_ensureSessionOpen()` first and returns early
  on a null user, the same guard every other sync-domain entry point uses.
forbidden_patterns_checked: >
  - UNAWAITED, deliberately. The comment at `deload_evaluator.dart:269-272` records that this runs
    on the cold-launch rollover path, awaited before `context.go`; blocking here would delay home
    navigation. The obvious fix — appending `await syncWorkoutData()` — would have re-created a
    problem that comment exists to prevent, so the OI-171 board entry says so explicitly.
  - No new `catch`. A failed push is already non-fatal by construction; the blob stays local and
    the next sync carries it.
proposed_fix: >
  Fire `unawaited(SyncService.instance.pushWorkoutPlanForSyncDomain())` immediately after the
  existing `pushSnapshot()`, i.e. after the blob write rather than before it.
regression_test_planned: >
  `test/contracts/deload_eval_behavioral_test.dart` — a 3-assertion `OI-171` group pinning that the
  narrow plan push EXISTS, is ORDERED AFTER the `current_plan` blob write, and stays UNAWAITED.
  Plus `plan_week_for_date_behavioral_test.dart` for the VALUE side (a lifted `working` week 4
  reads back as `working`).

  ⚠ THIS COVERAGE DID NOT EXIST WHEN THE FIX WAS FIRST WRITTEN, and this field said so in a way
  that was worse than useless: it disclosed the gap ("this fix's protection is weaker than the
  other two, and the honest reason is fixture cost") and shipped anyway, which is a §4.2 deferral
  wearing a confession. The B-pass caught it by DELETING the line — 60 tests across four
  deload/sync suites stayed green. A self-disclosed gap is still a gap.

  MUTATION-PROVEN, two legs, both leaving the file compiling:
  (A) MOVE the push ABOVE the blob write — the exact pre-fix defect — reddens 1 of 23: the
  ordering assertion, while presence and unawaited stay green. That is the leg that matters,
  because it proves the ORDERING assertion carries the weight rather than mere presence.
  (B) DELETE the line entirely — the reviewer's own scenario — reddens 3 of 23.

  Why a source pin and not a behavioral assertion, stated so nobody reads it as laziness:
  `SyncService.instance` is a live singleton that opens a session and talks to Supabase, and the
  defect is the ORDER of two fire-and-forget calls, which no Hive-level assertion can observe. The
  pin asserts POSITION — `indexOf(push) > indexOf(blobWrite)` — which is the defect itself.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze lib/ — 0 errors, 0 warnings." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "Unchanged — the blob write itself was already correct; 71/71 across the sync + schedule contract suites re-run." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change; user_progress.plan_json already exists." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "No migration. Existing stale plan_json rows are overwritten by the next push, which this fix now guarantees happens at lift time." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration in this batch." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "Client-only; no Edge Function touched." }
  - { tier: 7, name: cron_jobs, status: verified, evidence: "weeklyFullSync remains a backstop caller of _syncWorkoutPlan; unchanged." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy change; the push uses the existing user-scoped upsert." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No storage object touched." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret read or written." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: fixed_in_this_batch, evidence: "The blob now reaches user_progress.plan_json in the same operation that writes it, so a restore cannot reproduce a pre-lift blob beside post-lift rows." }
impact_analysis: >
  Narrow by construction: it bites only a user who has a week-4 deload LIFTED and then writes
  nothing before restoring on another device or after a reinstall. For everyone else the next
  workout write already carried the blob. Display-only — no workout, log or progression value
  changes; what changes is whether the phase-arc strip and its reason line agree with the rows
  beneath them after a restore.

  One added unawaited network call on the cold-launch rollover path. Chosen as the narrow plan
  push rather than a full domain sync precisely to keep that cost small, and left unawaited so it
  cannot delay home navigation.
---

# The deload lift wrote the blob after everything that would have pushed it

See the frontmatter. The lesson is about verifying a review finding before acting on it.

Round 5 reported that the lifted blob "never reaches `plan_json`". Acting on that directly would
have produced a fix for a bug that does not exist — the row writes' own fan-out does reach it.
Tracing the call graph instead showed the real defect: those fan-outs all fire BEFORE the blob is
written, and the one call that comes after it does not reach the plan push at all. Same symptom,
different mechanism, and a much smaller fix.
