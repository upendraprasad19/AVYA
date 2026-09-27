---
bug_id: a9d3f6
date: 2026-09-26
batch: day-swapper-sync-load
status: in_progress
blast_radius: platform
symptom: |
  Of 21 push steps in lib/core/services/sync/, only 3 skip unchanged rows today; the other 18 push a
  single row (profile, progress, preferences) or re-send the user's WHOLE history on every pass (14
  history steps plus the plan backup). Live, read-only measurement cited from spec §1.5 (2026-09-26):
  the heaviest account costs about 143 requests per workout pass (5 template headers, 5 id SELECTs, 21
  template exercises and 5 DELETEs, plus 44 workout logs, 28 completions, 28 completed days and 7
  streak weeks), and each nutrition pass re-sends 32 water days. `pg_stat_user_tables` shows rewrites
  per live row of about 29 for workout_schedule_completions, 30 for workout_templates, 33 for
  template_exercises (764 updates against 23 live rows), 23 for streaks, 21 for workout_logs, 41 for
  water_logs, and scheduled_workouts at 1,377 updates versus 84 inserts — the OI-237 board filing
  (docs/audit/open_issues.md:5595, "Extreme update:insert ratios on scheduled_workouts (34:1) and
  template_exercises (39:1)"). Postgres writes a new row version on every UPDATE even when nothing
  changed, because none of the heavy tables has a user trigger (the only existing triggers are
  INSERT-only rate-limit triggers on ai_coach_interactions), so the built-in
  `suppress_redundant_updates_trigger()` applies cleanly. Separately, every launch downloads
  `plan_json` TWICE — `_restoreUserProgress` selects `*` (lib/core/services/sync/sync_profile.dart:931,
  verify at plan time) and `_restoreWorkoutPlan` selects only `plan_json`
  (lib/core/services/sync/sync_workout.dart:1183) — and `UserRepository.mergeCloudProgress` copies the
  whole blob into `userBox['progress']`, where nothing reads it, then the plan merge re-writes up to
  112 schedule rows to Hive on every launch regardless of whether anything changed.
concept: sync_skip_index
sot_registry_entry: sync_scheduled_payload_hash_index (interim until Task 29 registers sync_skip_index; Task 31 re-points this line to it — see docs/sot_registry.yaml; one skip mechanism,
  SyncSkipIndex.pushIfChanged, shared by every history push in lib/core/services/sync/)
writers:
  - { file: lib/core/services/sync/sync_workout.dart, method: "syncWorkoutDataNow (fires after every workout write, no time debounce beyond SyncCoalescer's in-flight merge)", line: 44 }
  - { file: lib/core/services/workout_write_service.dart, method: "logExercise (triggers syncWorkoutDataNow)", line: 210 }
readers:
  - { file: lib/core/services/sync/sync_workout.dart, method: "_restoreWorkoutPlan (plan_json select #2)", line: 1183 }
  - { file: lib/core/services/sync_service.dart, method: "restoreLightweightAlways (runs both plan_json selects on the same launch)", line: 1535 }
hive_key_prefix: "sync_<domain>_payload_hash_index (new, one per domain) and userBox['progress'] (the stale plan_json copy this fix deletes)"
hive_key_formula: "sync_<domain>_payload_hash_index — literal key per the existing pattern of the three domains that already skip (spec §5.9)"
sync_methods: [_syncWorkoutLogs, _syncScheduleCompletions, _syncStreaks, _syncWorkoutTemplates, _syncScheduledWorkouts, _syncWaterLogs, _syncSavedMeals, _syncStepsLogs, _syncUrineColorLogs, _syncSleepLogs, _syncWeightLogs, _syncMeasurements, _syncReadiness, _syncCustomItems, _syncWorkoutPlan]
restore_methods: [_restoreUserProgress, _restoreWorkoutPlan]
cloud_table: scheduled_workouts
cloud_columns: [updated_at]
contract_test_path: "must add: test/sync/sync_domain_skip_harness.dart (shared per-domain skip
  contract, coordinator Task 5) plus 14 x test/contracts/<concept>_writer_to_reader_test.dart (one
  per new hash-index concept, Tasks 14-20) plus test/sql/day_swap_sync_load_live_verify.sql
  (BEGIN...ROLLBACK discrimination test, Task 7)"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [sync_scheduled_workouts, sync_workout_templates, sync_water, sync_schedule_completions]
cross_account_guard: n/a for the skip mechanism itself — it fingerprints and pushes only the current
  session's own rows. The helper's commit(liveKeys:) step does add an ownerChangedSince(userId) guard
  uniformly across every domain, closing the nutrition-only asymmetry docs/architecture/sync.md notes
  (spec §5.9), which is itself a cross-account-adjacent hardening, not a new cross-account read.
forbidden_patterns_checked:
  - { pattern: "Recording a row as sent BEFORE its push confirms complete (the swallowing-catch class this repo has already hit)", absent: true }
  - { pattern: "A hand-counted enumeration of which history loops the skip mechanism covers, instead of a gate that fails on any loop it misses", absent: true }
  - { pattern: "A daily blind 7-day re-send safety net that could undo another device's change (rejected, spec §14)", absent: true }
proposed_fix: |
  One new helper, `SyncSkipIndex.pushIfChanged(rowKey, fingerprintThunk, push)`
  (lib/core/services/sync/sync_skip_index.dart), used by all 21 push steps. It fingerprints the exact
  payload minus "sent-at" stamps (updated_at on water/urine, synced_at on steps/plan) via UUID v5 over
  canonical JSON, and records "sent" only if `push()` returns normally — the helper owns the try/catch,
  so a swallowed exception cannot silently mark a row sent (the exact gap `docs/architecture/sync.md`
  already documents and OI-204's mutation proved reachable). A fingerprint exception fails open (push,
  don't store); a kill switch set means push and never store. A structural gate,
  `scripts/check_sync_hash_skip_atomicity.dart` (G1, extended), fails any `.upsert(`/`.insert(` inside
  a Hive-row loop in lib/core/services/sync/** that is not wrapped in a `pushIfChanged(` closure,
  except the allowlisted single-row steps and the coach loop's own cloud-id-stamped skip — replacing
  today's count-based swallow check with a rule the gate itself enforces rather than a hand
  enumeration. One migration (145, number verified at plan time since 144 was taken upstream) adds a
  `suppress_redundant_updates_trigger()` BEFORE UPDATE trigger to every table a history loop writes
  (the gate's own enumeration is authoritative, per plan-time verification #6), a
  `scheduled_workouts`-specific guard function that also blocks demoting a completed day, and a
  `sync_epoch` integer column as a manual repair lever (bumping it clears every skip index and forces
  one full re-send). `restoreLightweightAlways` is changed to run ONE `user_progress` select and hand
  the row to both `_restoreUserProgress` and `_restoreWorkoutPlan`; `_restoreUserProgress` strips
  `plan_json` before `mergeCloudProgress` so the stale copy in `userBox['progress']` stops being
  written, and the existing copy is deleted once by the same one-time migrator that repairs the hybrid
  rows (doc b6e1c8).
regression_test_planned: |
  Per-domain: an unchanged second pass sends 0 writes and a changed row sends exactly 1; a thrown push
  is retried on the next pass; a change only to a sent-at stamp sends nothing; templates skip as one
  bundle (header + exercises); resolveCloudTemplateId is not called for skipped rows; a sync_epoch bump
  re-sends everything once; launch makes one user_progress select and no plan_json reaches
  userBox['progress']; the existing three domains keep their stored index keys with no re-push burst.
  Live SQL (always BEGIN...ROLLBACK): an identical upsert creates no new row version (xmin unchanged)
  on every table in the trigger list; a completed row cannot be demoted but its completed_at can be
  corrected; sync_epoch defaults to 0. Discrimination (CLAUDE.md §4.9, this exact class failed once
  before: 5 of 7 new assertions passed against the OLD code): inside the same transaction, drop the new
  triggers and re-run every assertion — it must fail, proving the assertion measures the new trigger
  and not something else. Mutation proof planned: unwrap one domain's push from pushIfChanged and
  confirm G1 reddens; write a *_payload_hash_index key directly outside sync_skip_index.dart and
  confirm G1 reddens that too.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "SyncSkipIndex + the 14 domain migrations onto it (Tasks 4-5, 13-20) plus the single launch fetch (Task 20)." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "14 new sync_<domain>_payload_hash_index keys, plus deletion of the stale userBox['progress'] plan_json copy." }
  - { tier: 3, name: postgres_schema, status: fixed_in_this_batch, evidence: "Migration 145 adds the no-op-update trigger to the enumerated tables, the scheduled_workouts completed-day guard, and the sync_epoch column (Task 7, U1)." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Spec §1.5's own live, read-only pg_stat_user_tables measurement (2026-09-26) is cited directly above (rewrites-per-row table, the ~143-request heaviest-account figure). This drafting pass did not re-query the database." }
  - { tier: 5, name: migrations_applied, status: fixed_in_this_batch, evidence: "Migration 145 is applied at Task 34 with its own explicit founder go, paired with backups/applied_migrations.json in the same commit (CLAUDE.md §4.5)." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "The sync write-amplification fix itself (skip index, no-op trigger, sync_epoch) touches no Edge Function; the allowance EF (consume-day-swap) is a separate concept shared with docs d5a1e7/e2b9d4." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job is involved in the history-push skip mechanism or the no-op-suppression trigger." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No RLS policy changes; the new scheduled_workouts trigger function is SECURITY INVOKER, not a policy change, and does not widen or narrow row visibility." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No Storage bucket or object is involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret is involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "None involved." }
  - { tier: 12, name: client_to_server_contract, status: fixed_in_this_batch, evidence: "The skip index changes what the client actually sends; sync_epoch is a new explicit contract field between client and server for forcing a full re-send after a repair." }
impact_analysis: |
  Severity: P2, scaling with account age (OI-237). The heaviest measured account costs about 143
  requests per workout pass and the server writes a fresh row version on every one of them even when
  nothing changed, which is disk-IO cost that grows without bound as accounts accumulate history — the
  same class of risk this worktree's own session name ("supabase-outage-check") exists to watch for.
  The double plan_json download and the up-to-112-row Hive re-write on every launch cost battery and
  launch time for every user, not just heavy accounts. This fix closes OI-237
  (`closes-oi: OI-237` on the commit that lands §5.9/§5.10, per spec §8).
---

# Sync write amplification: only 3 of 21 push steps skip unchanged rows (OI-237)

## Why this is not a recurrence

`docs/diagnoses/INDEX.md` was grepped for `write amplification`, `no-op update`, `suppress_redundant`,
`OI-237` — no hits besides the OI-237 board filing itself
(`docs/audit/open_issues.md:5595`, "Extreme update:insert ratios on scheduled_workouts (34:1) and
template_exercises (39:1) — possible sync write-amplification..."). This is the first diagnose-doc for
that board item, so it is filed as new and closes OI-237 per spec §8.

## The gate, not a hand count, is the enumeration

Per spec §5.9: "Any history loop the table misses fails the commit." The extended
`scripts/check_sync_hash_skip_atomicity.dart` (G1) is what actually enumerates which
`.upsert(`/`.insert(` calls must sit inside `pushIfChanged(` — the table in spec §5.9 and the trigger
list in plan-time verification #6 are both DERIVED from that gate's own scan, not the other way round,
so a missed loop fails the commit rather than silently shipping unskipped.

## Fix ownership in the plan

- `SyncSkipIndex` helper: Task 4 (coordinator, Wave 0). Test seams + local PostgREST stub: Task 5.
- G1 (`check_sync_hash_skip_atomicity.dart` extension): Task 3 (coordinator, Wave 0, lands before any
  domain migration per CLAUDE.md §4.11).
- The 14 domain migrations onto the helper: Tasks 14-20 (coordinator, inline during Wave 1).
- Migration 145 (no-op trigger, completed-day guard, sync_epoch): Task 7 (U1) drafts it; Task 34
  applies it with its own founder go.
- The single launch fetch + plan_json double-download fix: Task 20 (coordinator).

## Mutation evidence

Recorded at Task 31: each mutation, the grep that confirmed it applied, and the red count.
