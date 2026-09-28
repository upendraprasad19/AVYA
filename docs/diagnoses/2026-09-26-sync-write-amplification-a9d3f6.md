---
bug_id: a9d3f6
date: 2026-09-26
batch: day-swapper-sync-load
status: fixed_pending_live_apply
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
sot_registry_entry: sync_skip_index (re-pointed by Task 31 — Task 29 registered the concept at
  docs/sot_registry.yaml:12045; one skip mechanism, SyncSkipIndex.pushIfChanged, shared by every
  history push in lib/core/services/sync/, with the 15 per-domain `sync_<domain>_payload_hash_index`
  concepts — including `sync_scheduled_payload_hash_index` — as its sibling instances)
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
contract_test_path: "test/sync/sync_domain_skip_harness.dart (shared per-domain skip contract,
  coordinator Task 5) plus 14 x test/contracts/<concept>_writer_to_reader_test.dart (one per new
  hash-index concept, Tasks 14-20) plus test/sql/day_swap_sync_load_live_verify.sql (BEGIN...ROLLBACK
  discrimination test, Task 7) — that SQL file and migration 148 are held out of the tree until the
  Task 34 live apply and land in that commit; until then neither exists at these paths (B-pass
  2026-09-28)."
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
  enumeration. One migration (`148_sync_noop_suppress_completed_guard_sync_epoch.sql` — numbered 145
  at plan time since 144 was taken upstream, renumbered to 147 then 148 as other batches landed on
  `main` first; ruling 2026-09-28, wave3-carry.md) adds a
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
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "SyncSkipIndex (Task 4, commit 458b98bc) + test seams (Task 5, commit 61c0bb5e/d0186537) + G1 gate (Task 3, commit 52585f04/a5e491d7) + the 14 domain migrations onto it (Tasks 13-20: 6d26a177/094648df, ebddb44c, 3c376f77, 875c8f3e/b22592ed, 0a1a0548.../745fdb98, 865d891d, 70f1922b) plus the single launch fetch + epoch-after-clearAll fix (Task 20, commit 083b82a9 + a53f3305)." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "15 new sync_<domain>_payload_hash_index keys (14 domains + sync_skip_index's own storage), plus deletion of the stale userBox['progress'] plan_json copy (Task 20, commit 083b82a9)." }
  - { tier: 3, name: postgres_schema, status: fixed_pending_live_apply, evidence: "Migration 148_sync_noop_suppress_completed_guard_sync_epoch.sql adds the no-op-update trigger to the 19 enumerated tables, the scheduled_workouts completed-day guard, and the sync_epoch column (Task 7, U1, drafted and handed over uncommitted per plan design — see u1-handover/). NOT yet applied to any live database; live information_schema/pg_trigger state is unchanged until Task 34's founder-approved apply." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Spec §1.5's own live, read-only pg_stat_user_tables measurement (2026-09-26) is cited directly above (rewrites-per-row table, the ~143-request heaviest-account figure). This drafting pass did not re-query the database." }
  - { tier: 5, name: migrations_applied, status: fixed_pending_live_apply, evidence: "Migration 148 is drafted (Task 7) and blast-radius classified `catastrophic` (Task 31 — the content rule matches SECURITY DEFINER inside a header sentence that says the guard is NOT SECURITY DEFINER; accepted as-is, not reworded to dodge the classifier). Applied at Task 34 with its own explicit founder go, paired with backups/applied_migrations.json in the same commit (CLAUDE.md §4.5)." }
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

- `SyncSkipIndex` helper: Task 4 (coordinator, Wave 0). Landed `458b98bc`. Test seams + local
  PostgREST stub: Task 5, landed `61c0bb5e` (coordinator commit `d0186537` for the public-API-snapshot
  scope fix and the two teardown-never-throws wraps).
- G1 (`check_sync_hash_skip_atomicity.dart` extension): Task 3 (coordinator, Wave 0, lands before any
  domain migration per CLAUDE.md §4.11). Landed `52585f04` + fix round `a5e491d7`
  (`aliased_query_builder` kind).
- The 14 domain migrations onto the helper: Tasks 13-20 (coordinator, inline during Wave 1). Task 13
  `6d26a177`/`094648df` (nlog/exlog); Task 14 `ebddb44c` (schedule completions); Task 15 `3c376f77`
  (scheduled workouts, template_id null fix); Task 16 `875c8f3e`/`b22592ed` (templates); Task 17
  `0a1a0548`/`b1c3ddc2`/`ea33eacb` + fix round `b503bcd6` (integrated `53a177e0`/`745fdb98`, saved
  meals + custom items + per-distinct-opType report mirror); Task 18 `865d891d` (5 health domains);
  Task 19 `70f1922b` (coach/onboarding/notifications); Task 20 `083b82a9` (plan/streak launch path) +
  fix `a53f3305` (sync_epoch stored only after `clearAll` `allSucceeded`, diagnosed the same day as
  this doc — see "Skipped-then-found fixes" below).
- Migration 148 (no-op trigger, completed-day guard, sync_epoch, renumbered from 145→147→148 per
  wave3-carry.md ruling 2026-09-28): Task 7 (U1) drafts it, handed over uncommitted; Task 34 applies
  it with its own founder go.
- The single launch fetch + plan_json double-download fix: Task 20 (coordinator), commit `083b82a9`.

## Skipped-then-found fixes (wave3-carry.md, Task 31 carry list)

- **`a53f3305`** (Task 20 review finding, integrated same day): `sync_epoch_seen` was stored even when
  `clearAll` failed partway, permanently losing the repair lever's retry. Fixed by only advancing the
  stored epoch when `ClearAllResult.allSucceeded` is true. Mutation: the guard reverted to
  unconditional store → 1 red (expected 1, got 2 — the guard test's own assertion), restored clean.
  test/sync + G1/G2 lib 228/228, parity PASS. Coordinator-reviewed (no separate reviewer dispatch —
  4-file single-guard fix per the ruling in progress.md).
- **`5c0c00ff`** (Task 21 review Minors, not this doc's own fix but recorded here since it landed
  alongside the sync-load work): `_mondayOfIsoWeek` now delegates to `DaySwapRules.mondayOf` instead
  of a duplicate helper — a duplicate justified by "the other unit has not landed yet" that expired at
  integration (code-review red-flag class, see the skill entry below).

## Commits

`458b98bc`, `61c0bb5e`/`d0186537`, `52585f04`/`a5e491d7`, `6d26a177`/`094648df`, `ebddb44c`,
`3c376f77`, `875c8f3e`/`b22592ed`, `0a1a0548`/`b1c3ddc2`/`ea33eacb`/`b503bcd6`/`53a177e0`/`745fdb98`,
`865d891d`, `70f1922b`, `083b82a9`/`a53f3305`. Migration `148_sync_noop_suppress_completed_guard_sync_epoch.sql`
uncommitted, applied at Task 34.

## Mutation evidence

Gate G1 (`52585f04`/`a5e491d7`): 41/41 targeted; mutation-1 (aliased query builder evading the
statement-scoped `.from(` match) → 1 red, confirmed by the new `aliased_query_builder` kind; recount
after fix 28 unwrapped_write / 3 index_literal / 0, exit 0.

Task 4 (`458b98bc`, SyncSkipIndex): 4 mutations, sched/exlog/nlog index + kill-switch keys verified
byte-identical to the pre-batch sync_service.dart line numbers.

Task 5 (`61c0bb5e`): 2 mutations against the stub/harness seams; teardown-never-throws wraps added by
the coordinator (`d0186537`) per the Task 5 review's Minor (CLAUDE.md §4.9 socket-teardown row).

Task 13 (`6d26a177`, fix `094648df`): the fix round restored a dropped `unawaited(_reportSyncFailure(...))`
in two catches (the only path to server-side `client_errors`); test: stub-server asserts the
log-client-error invoke plus exactly-one call for nlog, mutation per line. `hasLength(2)` is the
no-op-flood invariant (removed=0 / correct=2 / per-item-flood=4).

Task 14 (`ebddb44c`): 31/31 targeted; the implementer independently caught and restored a dropped
`upsert_schedule_completion` `_reportSyncFailure` call the plan's own draft had omitted.

Task 17 fix round (`b503bcd6`, integrated `745fdb98`): F1 (per-table opTypes collapsed into one
generic string, 4th instance of the code-review lens-5 refactor-drops-per-site-extras class) — 2
mutations (1 red each) confirm `upsert_custom_exercise`/`upsert_custom_food` are reported under their
own opType again; the coordinator's own self-review then found a MIRROR gap (the fix's `if (failed ==
1)` reports only the first failure per pass, so two different tables failing in one pass under a
shared index would report only one) — closed at integration with a `Set<String> _reportedOpTypes`
(distinct-opType-once) plus 2 new tests (both-tables-fail-once, two-rows-same-table-once), each
mutation reddening exactly its own test.

Task 20 (`083b82a9`): 9 mutations; launch path verified 8→7 Supabase calls (the bare `.select()` on
`user_progress` is a real IO win — the old code fetched it twice with two different projections, one
of which the shared select now subsumes; independently confirmed by the reviewer, correcting this
doc's own drafting-time claim in `regression_test_planned` about which projection was doubled).
Fix `a53f3305`: see "Skipped-then-found fixes" above.

## B-pass remediation (2026-09-28, review `docs/reviews/day-swapper-sync-load-bpass.md`)

- **R1-F1 (P1) — the skip index defeated the scheduled_workouts FK self-heal.** Writer: the
  recovery call in `_syncScheduledWorkouts` (`sync_workout.dart`, the `templatesResynced` block)
  re-runs `_syncWorkoutTemplates`; reader: that function's `SyncSkipIndex` (domain `template`),
  which still held the template's confirmed fingerprint, so the re-run SKIPPED the one template the
  cloud had lost. The row fell to the orphan fallback and, being unconfirmed by design (spec D4),
  repeated the dead-end recovery (2 SELECTs + 2 upserts + a telemetry post) on every pass — a flood
  for as long as the template stays missing. Fix: `SyncSkipIndex.forcePushKeys` (push + record a
  fingerprint-matched row; deliberately NOT `disabled`, which deletes the whole index at commit and
  would re-push every template next pass), threaded as `_syncWorkoutTemplates(forceKeys:)`; the
  recovery forces exactly `{rawTemplateId}`. Test: `test/sync/sched_template_fk_recovery_test.dart`
  (real SyncService against the stub; the cloud loses the template after pass 1). Mutation —
  restore the old `await _syncWorkoutTemplates(userId);` → 1 red ("the recovery re-pushes the lost
  template": expected ['Push A'], got []).
- **R1-F2 (P2) — the unconfirmed branch's `_forget` had no test.** Removing it left 18/18 green.
  Added "unconfirmed push DROPS the previously confirmed fingerprint (no false skip later)" and a
  `forcePushKeys` unit test to `test/sync/sync_skip_index_test.dart`. Mutation — delete
  `_forget(rowKey)` on `!confirmed` → 1 red (expected empty index, got {'d': 'fp1'}).
- **R4-F2 (P1) — gate G1 accepted an unreachable `rethrow`.** `_rethrowOrFalse` matched the token
  anywhere in a catch block, so `catch (e) { if (false) { rethrow; } }` passed. Now
  `endsInUnconditionalExit`: the block's LAST top-level statement must be `rethrow;` or
  `return false;`. Live tree still 0 violations. Tests in `test/scripts/sync_write_structure_lib_test.dart`
  (3 new). Mutation — restore the anywhere-token match → 2 red. Residue stated in the lib: still a
  text scan; the behavioural guard is the per-domain skip contract (failed push retried next pass).

## Hermes remediation (2026-09-28, report `docs/audit/2026-09-28-hermes-day-swapper-sync-load.md`)

- **L11/L15 — `sync_epoch_seen` was per-DEVICE, the lever is per-ACCOUNT.** Writer + reader
  `sync_service.dart` `_applySyncEpochFromRestoreRow` read and wrote `configBox['sync_epoch_seen']`
  (the shared, never user-scoped box) while the 17 skip indexes it clears live in the per-user
  workoutBox/nutritionBox/healthBox/customBox. On a shared device, account A's high-water mark (3)
  made account B's operator bump (1 → 2) a silent no-op. Fix: the key moves to the per-user
  `workoutBox` beside the indexes. Test: `test/sync/restore_lightweight_single_plan_fetch_test.dart`
  "sync_epoch_seen is PER USER" — red before the fix (`Expected: false Actual: <true>`, B's index
  not cleared), green after; the 5 existing epoch tests repointed to workoutBox.
- **L39 — cross-device convergence was unproven.** `_syncWorkoutPlan` upserts the whole bundle
  with no read-before-write, so a stale device can overwrite a newer arrangement. It converges
  because `_restoreWorkoutPlan` records the DOWNLOADED bundle's fingerprint after a merge, so the
  device holding the newer week no longer matches it and re-pushes on its next plan pass. New
  test `test/sync/sync_workout_plan_skip_test.dart` "two devices converge"; mutation: the restore
  side `recordConfirmed` commented out → `Expected: an object with length of <1> Actual: []` (no
  re-push), restored → green. Residue, stated: if the device with the newer week never runs again,
  the stale arrangement stays — last-writer-wins at week granularity (spec §5.7 L3).
- **L22 — migration 148 handover:** the paired `sync_noop_trigger_tables_test.dart` still read the
  pre-renumber `147_…` path (would throw at apply) and the stale `147_…` copy sat beside `148_…`;
  repointed, stale copy deleted, run against the real `148_…` file: 4/4 green. Header's
  "same microsecond" corrected to millisecond (JS `toISOString`) and its `ai-proxy` cite re-derived.
