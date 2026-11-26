---
bug_id: f5a2c8
date: 2026-11-27
batch: OI-532 (schedule restore vs an unpushed day swap)
status: fixed
tier: full
blast_radius: platform
symptom: |
  OI-532 (found planning OI-348 Landing 3d, verified in its plan reviews R1-2 / R2-1 / R2-2). Swap Fri (workout) with Sat (rest) while offline, relaunch before the push lands: the launch restore reads the cloud's PRE-swap scheduled_workouts rows and overlays them. Sat (now the local workout) is typed rest and its exercises are stripped (the workout is lost); Fri (now rest) gets status planned and, on a template day, its template back. Every day swap had this exposure, the missed-day rescue included.
concept: sched_unpushed_swap_marker
sot_registry_entry: sched_unpushed_swap_marker
writers:
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "swapScheduledDays: the swap's one atomic write (all four keys or none); called only by SwapService.swapDays (swap_service.dart:536), rescue included. Now marks both dates before and after the rows", line: 848 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_syncScheduledWorkouts: the only thing that makes a swap 'pushed' (pushIfChanged per row). Now clears a date's mark once the cloud holds that row", line: 2263 }
readers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreScheduledWorkouts: cloud status wins (status merge), type rest when the cloud says rest, cloud template_id overlaid, rest-content strip, then put. Runs after _restoreWorkoutPlan (sync_service.dart:1962), so it is the last writer of schedule_<date>", line: 2580 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "_attemptSingleCallRestore: fetches the bundle, then steps A/B, then calls _restoreScheduledWorkouts with the injected rows (preFetched)", line: 2391 }
hive_key_prefix: "workoutBox['sched_swap_unpushed'] (literal key; Map {IST date: token, '_seq': last token})"
hive_key_formula: "sched_swap_unpushed -> {'2026-09-25': 1790000000000, '_seq': 1790000000001}"
sync_methods: [_syncScheduledWorkouts]
restore_methods: [_restoreScheduledWorkouts, _attemptSingleCallRestore, restoreScheduledWorkoutsForSyncDomain]
cloud_table: scheduled_workouts
cloud_columns: [status, template_id, week_number, day_of_week, completed_at]
contract_test_path: test/sync/sched_restore_unpushed_swap_test.dart
ist_handling:
  - { file: lib/core/services/workout_write_service.dart, line: 854, fn: "istDateStr (the swap's two IST dates are the mark keys, same as schedule_<date>)" }
provider_invalidations: []
telemetry_op_types:
  success: [sched_restore_kept_unpushed_swap]
  failure: [workout_write_service_swap_mark, sched_swap_unpushed_clear, sched_swap_unpushed_prune, sched_swap_unpushed_read, sched_swap_unpushed_malformed]
cross_account_guard: "true: the persisted marks live in the user-scoped workoutBox (cleared with it on sign-out / account swap / DPDP); the process-local in-flight set and touched map are cleared by SyncService._onUserChanged (the counter is never reset, so a restore that took its fetch mark before the switch still compares against a counter that only grows); the push clears only after pushIfChanged's own owner re-check, and prune is skipped on an aborted pass or an owner change."
forbidden_patterns_checked:
  - { pattern: "a guard keyed on arranged_at_ms (re-stamped by upsertScheduled's carriesArrangement on every rewrite: permanent per row, and present on rows a fresh device restored from another device's bundle)", absent: true }
  - { pattern: "unpushed inferred from an ABSENT skip-index fingerprint (a fresh device, a sync_epoch clearAll or disable_sched_hash_skip has none)", absent: true }
  - { pattern: "the restore merge still running on a guarded row (re-adds template_id on the rest side, the b6e1c8 hybrid)", absent: true }
  - { pattern: "a mark cleared after a push that read an OLDER token (a swap that landed during the push)", absent: true }
  - { pattern: "a mark cleared by a skip-branch true after an omitted-template-key confirm", absent: true }
proposed_fix: |
  Plan docs/plans/oi532-sched-restore-unpushed-swap.md (3 review rounds, converged; record docs/plan-reviews/oi532-sched-restore-swap.md).
  A POSITIVE marker that a date carries a local swap the cloud has not confirmed (lib/core/services/sync/sched_unpushed_swaps.dart): persisted {date: token} with a never-reused token ('_seq'), plus process-local state (the dates of a swap being written; a counter bumped by every mark and clear).
  Writer: swapScheduledDays puts both dates in flight and marks them BEFORE the first row write (the restore takes no date lock and every put yields), marks them again after the last, and releases them in a finally. Never fails the swap.
  Clearer: _syncScheduledWorkouts reads the date's token in the same synchronous run as the row and, when pushIfChanged returns true, removes the mark only while it still holds that token and no swap of it is in flight. The Case 2 omitted-template-key confirm returns false for a marked row (the cloud keeps the pre-swap template_id). Marks of rows that are gone are pruned at the end of a pass.
  Reader: _restoreScheduledWorkouts leaves a date's local row byte-identical when it is pending, or was marked or cleared since the cloud rows were fetched (fetchMark taken before the fetch; the single-call restore takes it before callFunction('restore-user-snapshot') and passes it in). Checked synchronously right before the put. A cloud completed still lands; with no local row the cloud row restores.
  Kill switch configBox['disable_sched_unpushed_swap_guard'] (default ON): restore and push paths verbatim.
  What a guarded date gives up for that one restore: the cloud's day_of_week / week heal and the source: cloud_restore stamp (accepted; the next restore after the push brings them).
regression_test_planned: |
  test/sync/sched_restore_unpushed_swap_test.dart (18): real Hive, the real SwapService.swapDays, the real schedule push against the stub server (new awaited beforeWrite hook), the real restore merge. T1 the bug (red on main), T2 not permanent, T3 cloud completed lands, T4 a later rewrite keeps the guard, T5 fresh-device mirror, T6 kill switch, T7 a swap during its own push, T8 launch order (bundle restore then schedule restore), T9 rows fetched before a swap that was pushed and cleared, T10 omitted template key across two passes, T11 stale mark with no row, T12 marks before the first row, T13 a push answered after the swap ended, U1-U4 helper. The single-call wiring (fetchMark before callFunction, passed to _restoreScheduledWorkouts) is pinned by a source-order test in the same file, like restore_readiness_prefetch_test.dart: driving the whole single-call restore needs an authed session and the 29-table bundle (plan round-3 R3-1 asked for a behavioural run; the behaviour itself is T9).
mutation_proof: |
  Rule 21. scratchpad mut532.sh (+ b, c re-runs): exact-once literal replace (refused unless the old text matches exactly once; five multi-line patterns were refused on the first run and re-run with single-line anchors), the whole test file run, the source restored by copy + cmp after each mutant, md5 of the three mutated files equal before and after every run. 15 of 15 red, 0 compile errors:
  a no restore guard [T1, T4, T8, T9]; b no clear after a confirmed push [T2, T7, T9, T10]; c clear without the token compare [T7, T13, U1]; d guard ignores cloud completed [T3]; e guard on arranged_at_ms instead of the mark [T2, T5]; f guard ignores the kill switch [T6]; g no touchedSince [T9]; h marked Case 2 returns true [T10]; i no local-row clause [T11]; j no beginSwap [T12]; k clear ignores in-flight [U1]; m prune drops every mark [9 tests]; n no post-rows mark [T13]; o no endSwap [T2, T7, T9, T10, T12].
  Mutant k first SURVIVED: U1 asserted isPending, which also reads the in-flight set; U1 now asserts the stored token (then red).
impact_analysis: |
  Any user who swaps days (Train drag, the swap picker, Home long-press, the coach, the missed-day rescue) and whose push has not landed when a restore runs (offline, a relaunch, a background restore, the single-call restore on sign-in) keeps the swap. After the push lands the cloud's rows win again as before, so two devices still converge. No change for a day nobody swapped, for a fresh device, or with the kill switch set.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "sched_unpushed_swaps.dart (new), workout_write_service.dart, sync_workout.dart, sync_service.dart, sync_flags.dart, simulation_service.dart; flutter analyze no warnings." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "workoutBox['sched_swap_unpushed'] (new key, user-scoped); schedule_<date> rows unchanged in shape. Behavioural tests on real Hive." }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "scheduled_workouts has no timestamp column (backups/live_schema_columns.json), which is why the guard is local; no migration." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "No data repair." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "None." }
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "restore-user-snapshot unchanged; the client only takes a counter before calling it." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "None." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "None." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "None." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "None." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "None." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "The scheduled_workouts upsert payload is unchanged; a marked Case 2 row is re-sent each pass until its template link resolves (one upsert per pass, no failure report, no retry-sweep arm)." }
recurrence: "Recurrence of the class 'a restore treats a stale cloud row as authoritative over a local change not yet pushed': d9b2c5 (local completed demoted by cloud planned) and e8f4a3 (local moved/dropped resurrected), each fixed per STATUS. A swap moves content and status together, so this fix keys on a positive per-date 'unpushed local swap' marker instead of a status arm. Sibling through another writer, split to its own OI: TemplateService.unscheduleTemplateFromDate (an unpushed template removal is re-templated by the restore, and a deleted row is never pushed)."
related_bugs: [d9b2c5, e8f4a3, a3e7d9, b6e1c8, b4f7e2, b3f7d2]
---

# f5a2c8 - a stale schedule restore undoes an unpushed day swap

## What happened
A day swap rewrites two `schedule_<date>` rows locally and pushes them in the background. The schedule restore (`_restoreScheduledWorkouts`) treats the cloud row's status as authoritative per date, and the cloud row has no timestamp, so a restore that runs before the push lands reads the pre-swap arrangement and puts it back: the workout moved onto the rest day is typed rest and stripped, and the old workout day gets its status (and template) back.

## PROVEN
- From the code (main 9472de6f): status merge (`sync_workout.dart` ~2644-2684), `type: 'rest'` when the cloud says rest (~2810), cloud `template_id` overlay (~2819), rest strip (~2860), put (~2872). The restore runs after `_restoreWorkoutPlan` on every path, so it is the last writer.
- By test: T1 is red without the guard (mutation a): Sat comes back `type: rest` with no exercises.
- The plan-bundle merge does not undo a swap: swapped rows carry a fresh `arranged_at_ms`, the snapshot wins a week only on a strictly greater stamp, and L1 keeps a local rest row (T8 runs both restores in launch order).

## Why not the earlier guard (OI-348 3d plan 3.5, R2-1/R2-2)
Keeping any local row with `arranged_at_ms` re-added `template_id` on template days (the merge still ran) and was permanent, because `upsertScheduled` re-stamps `arranged_at_ms` on every rewrite; after a confirmed push two devices would diverge for good. Using "no stored skip-index fingerprint" as the signal fails on a fresh device or a cleared index. The fix is a positive marker written by the swap and removed by the confirmed push.

## Races closed (plan 5.4)
- A swap during a push pass: the push clears only the token it read with the row; a later swap re-marks with a greater token, and a mark is never cleared while its swap is being written (T7, T13, U1).
- A swap during a restore's merge: the swap marks before its first row write and the guard is checked synchronously right before the restore's put (T12).
- Anything that happened to the date after the restore's fetch (a swap marked, pushed and cleared since): the restore compares against a counter taken before the fetch (T9), including the single-call restore, whose fetch happens long before step B.

## Accepted residue
- A guarded date skips the cloud's `day_of_week` / `week` heal and the `source: cloud_restore` stamp for that one restore.
- A swap's first mark survives a rollback or a crash between the mark and the rows: one restore keeps the unchanged local row; the next push (equal fingerprint, skip branch) clears it.
- When restore-merge L3 lets another device's newer week win, the local swap is discarded but its mark stays until the next push sends the bundle rows and clears it (one pass).
- A marked row whose push never confirms (an orphan template) keeps local winning for that date and is re-sent each pass.
- The key exists with the switch on. Walkers over `workoutBox.values` with no key filter (`export_data.dart`, `daily_completion.dart`, `workout_repository.dart`) tolerate it like the skip-index maps (a Map with no type/date/status).

## Mutation proof
See `mutation_proof:` above: 15 of 15 mutants red after U1 was tightened (k had survived).
