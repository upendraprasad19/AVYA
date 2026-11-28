# OI-530: schedule sync by week row (Option C) + one download per restore

Status: plan, draft 3 (rounds 1-2 folded; Landing A split out to `oi530-landing-a-one-plan-read.md` under
§4.12.1 and is NOT governed by this file any more; B/C need further review rounds before code). Tier L (sync, schema, Edge Functions). Execution:
inline, one worktree (`.claude/worktrees/oi530-plan-json-measure`, branch `oi530-plan-json-measure`), never
switched. Base: `main` `bde20648`. Founder decision 2026-11-28: Option C (history out of the one bundle into
small rows, the industry pattern) plus the quick win (a restore downloads the bundle once, not two or three
times). Task board: https://claude.ai/artifact/NfiqxVkztjEKAhzkzSRH1C

**Draft 2 change of unit.** Draft 1 used one row per DAY on `scheduled_workouts`. Round 1 found a P0 (a day
swap arrives half-done on another device and the L3 week-level arrangement merge then sticks on a tie for
ever, written back to the cloud) and a P0 in the per-day tombstone RPC (RLS, completed days, a fresh row
deleted). Both come from splitting a WEEK-level invariant across day rows. Draft 2 syncs one row per user per
IST Mon-Sun WEEK. A swap never crosses a week (`DaySwapRules.pairRefusal`, `day_swap_rules.dart:78-84`,
`DaySwapRefusal.differentWeek`), so a swap is one row, one upsert, atomic; L3 sees whole weeks by
construction; and a removed day simply is not in its week's new row, so no tombstone table or RPC exists.
Round-1 findings 1, 2, 11, 12 are removed by the change (not patched); 3-10 and 13-17 are folded (6).

## 1. Observation and measurement (OI-530, measured 2026-11-28)

`user_progress.plan_json` holds `{plan, plan_start_date, plan_end_date, schedules{schedule_<date>: full row},
synced_at}`: every `schedule_*` row of the user's whole history, each with its exercise list.

- Live (read-only SQL): 25 bundles; founder account 927 KB text (168 rows), others 140-420 KB; the `plan`
  object alone is 70-152 KB per account. `scheduled_workouts`: 1,466 rows; 1,011 of the 1,034 bundle days
  have a matching row (23 do not).
- Synthetic two-year account through the REAL `_syncWorkoutPlan` / `_restoreWorkoutPlan`
  (`test/sync/zz_oi530_plan_json_measure_test.dart`, uncommitted harness): 247 KB / 691 KB / 1.22 MB / 2.28 MB
  per upload at 1 / 6 / 12 / 24 months, the same after a one-day change (48x-448x the changed row).
- Live logs 27 Nov: the founder account uploaded the whole bundle 4 times in about 70 minutes.
- **Every app launch downloads the whole bundle once**: `splash_screen.dart:203` `checkAndSync()` ->
  `sync_service.dart:1108` `_restoreIfNeeded` -> `:1710` `restoreLightweightAlways` -> `:1822`
  `_fetchUserProgressRowForRestore` (a bare `.select()`, so `plan_json` comes with it).
- **A full restore downloads it two or three times**: `restore-user-snapshot` reads `user_progress
  select("*")` (`restore_reads.ts:54`) AND `select("plan_json")` (`:69`, key `workout_plan`) and returns both;
  the legacy paths run `_restoreWorkoutPlan(userId)` and `_restoreUserProgress(userId)` with their own
  network reads (`sync_service.dart:1941` + `:1958`; `:2243` + `:2257`).

## 2. Writers and readers (file:line on `bde20648`)

### 2.1 The bundle
| Role | Site |
|---|---|
| Writer | `sync/sync_workout.dart:1461` `_syncWorkoutPlan` (collect `schedule_*` :1471-1480, bundle :1483-1489, `pushIfChanged(kPlanBundleRowKey)` :1499, upsert :1508). Runs from `pushWorkoutPlanForSyncDomain` (:2997), `weeklyFullSync` (`sync_service.dart:1430`), `WorkoutsSyncDomain.push` (`sync_domains/workouts_sync_domain.dart:55`) |
| Reader 1 | `sync/sync_workout.dart:1543` `_restoreWorkoutPlan` (plan seed :1567, `PlanWindowReanchor` :1577, L2 skip :1614-1649, ghost filter :1662-1675, `mergeScheduleBundleIntoHive` :1677, `recordConfirmed` :1687) |
| Reader 2 | `plan_integrity_reconciler.dart:~528-590` `reconcile` (symptom-gated boot heal from `restoring_screen`): `select('plan_json')`, reanchor, ghost filter, `mergeScheduleBundleIntoHive` |
| Reader 3 | `supabase/functions/_shared/partial_day_loader.ts:93-106` (`plan_json->schedules->schedule_<todayIST>`, or `->schedules` on the fallback; template literals on purpose, `check_schema_column_refs.dart`), used by `streak-guardian` and `workout-window-closing` |
| Reader 4 | `restore-user-snapshot/restore_reads.ts:54` (`select *`) and `:69` (`select plan_json`); client parser `sync_service.dart:2448` (`user_progress`) / `:2462` (`workout_plan`) |
| Strippers | `sync/sync_profile.dart:~1124` and `user_repository.dart:585` (`_restoreUserProgress` drops `plan_json`), `schedule_hybrid_repair_migrator.dart:177-179` |
| SQL | none: no function, view, trigger or cron reads `plan_json` (only migration 011 adds it) |

### 2.2 The merge every reader shares
`PlanIntegrityReconciler.mergeScheduleBundleIntoHive(schedules)` (`plan_integrity_reconciler.dart:242-314`):
local rows vs the given snapshot rows; L3 `snapshotArrangementWinsKeys` (:186-232) takes per-week MAX
`arranged_at_ms` over the rows IT IS HANDED (week = `DaySwapRules.mondayOf`), strictly-newer snapshot wins
the week's stamped keys; per key `mergeScheduleEntry` (:102, completed-preserving, L1 rest guard); write only
when the merged row differs. **Invariant this plan relies on: every call is handed whole weeks.**

### 2.3 Local writers and deleters of `schedule_*`
All product writers go through `WorkoutWriteService.upsertScheduled` (`workout_write_service.dart:718`,
fires `syncWorkoutData`) or `swapScheduledDays` (:848, one week, atomic four keys) or `markCompleted` (:592);
raw puts only in restore/migrator paths (`plan_integrity_reconciler.dart:306`, `sync_workout.dart:1265/1286/
2930`, `schedule_hybrid_repair_migrator.dart:160`, `template_identity_migrator.dart:140`). Deleters:
`workout_schedule_read_service.dart:430` and `:1860`, `workout_schedule_write_service.dart:454` and `:472`,
`template_service.dart:267` (also reached from restore via `cleanSyncTemplateSchedule`), `swapScheduledDays`
:935/:948. A week row is built from whatever `schedule_*` keys of that week exist at push time, so every
writer and deleter is covered by the push with no per-site change.

## 3. Bug history (§4.1.5)

Read: `a7d3f1` (restore must always apply `plan_json`: the only cloud copy of each day's exercises), `a9d3f6`
(write amplification; SyncSkipIndex), `b9e4d1` (OI-189: every window move must push the plan), `b6e1c8`
(rest/template hybrid; L1), `d9b2c5` / `e8f4a3` (status merge arms), `f5a2c8` (OI-532 unpushed-swap guard),
`5c8e2a` (past-phase strip reads `schedule_*`), `b9e4d7` (restored device re-sends history), `c7e2a9`
(restore paging, unique tie-break), OI-533 (a deleted day is never pushed to `scheduled_workouts`). Not a
recurrence: a storage-shape change. It is in the "restore treats stale cloud state as authoritative" class, so
no merge rule is rewritten (5.4) and the unit is chosen so the merge keeps seeing whole weeks (2.2).
OI-533 is NOT folded in: its subject is the separate `scheduled_workouts` status table (a deleted day's status
row is never removed, and `_restoreScheduledWorkouts` recreates a bare row from it). Week rows neither fix nor
worsen that; it keeps its own board entry and fix shape.

## 4. Rejected designs (do not re-explore)

- **Option B, horizon-pruned bundle**: still re-sends 250-400 KB for a one-day change; two-device whole-history
  overwrite remains. Founder chose C.
- **One row per DAY (draft 1)**: splits the week-level L3 invariant across rows (round-1 P0 #1: half a swap
  arrives, the tie rule then keeps the stale half for ever); needs per-day tombstones (round-1 P0 #2). A batch
  upsert of a swap's two rows would fix the push but not a pull that pages or overlaps mid-swap.
- **Soft delete / tombstone table on `scheduled_workouts`**: 7 server readers would need a filter; RLS and
  completed-day traps (round 1). Not needed with week rows.
- **Deletions inferred from the skip index**: absence-based (OI-532 lesson).
- **JSON Patch into the bundle**: complex; keeps one large value.
- **An explicit `user_progress` column list to leave `plan_json` behind**: drifts when a column is added. Moving
  the plan to its own row (5.2) removes the reason.

## 5. Design

Landings (5.7): A = one download per restore (standalone, ships first); B = schema + dual write + new read paths
behind default-OFF switches (ship dark); C = backfill, flip, old paths and the bundle removed.

### 5.1 Week rows (migration, Landing B)
`public.user_schedule_weeks (user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE, week_start date
NOT NULL, days jsonb NOT NULL DEFAULT '{}', updated_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY (user_id,
week_start))`.
- `days` = `{'schedule_<date>': <the full local row>}` for the `schedule_*` keys of that IST Mon-Sun week, the
  exact per-key content the bundle carries today. An empty `{}` = "this week has no rows" (a positive record: a
  regenerate that removed a whole week pushes `{}`, never a DELETE).
- RLS own-row select/insert/update (`(select auth.uid()) = user_id`), no delete policy (the client never
  deletes); `REVOKE` from `anon`; FK cascade so DPDP `delete-account` (which relies on the `users` cascade,
  `delete-account/index.ts:411-419`) removes it.
- BEFORE UPDATE trigger `private.user_schedule_weeks_touch()` (SECURITY INVOKER, pinned `search_path`):
  `IF NEW IS NOT DISTINCT FROM OLD THEN RETURN NULL; END IF; NEW.updated_at := now(); RETURN NEW;`. The client
  never sends `updated_at`, so ON CONFLICT DO UPDATE leaves it out of SET and the no-op check holds (round-1 #14
  confirmed the same shape on the live guard). INSERT takes the default.
- Index: `CREATE INDEX ON user_schedule_weeks (user_id, updated_at, week_start)` for the launch pull's
  keyset (5.5); the PK serves the by-`week_start` reads.

### 5.2 The plan object in its own row (migration, Landing B)
`public.user_workout_plan (user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE, plan jsonb,
plan_start_date text, plan_end_date text, updated_at timestamptz NOT NULL DEFAULT now())`, same RLS / REVOKE /
touch trigger. `_syncWorkoutPlan` (switch ON) upserts `{plan, plan_start_date, plan_end_date}` here through a
new `SyncSkipDomain.planRow` fingerprint that excludes schedules, so a day change no longer re-sends the plan.
While dark, the bundle keeps being written verbatim (dual write).

### 5.3 Push (Landing B, switch `enable_sched_week_push`)
New step `_syncScheduleWeeks` in the `syncWorkoutData` fan-out, right after `_syncScheduledWorkouts`, and at
the start of `_syncWorkoutPlan` (weeks before the window, so a reader that sees the new window also finds the
weeks; one-time order rule):
- Group local `schedule_*` keys by `DaySwapRules.mondayOf(date)`; malformed keys are skipped and reported once.
- Per week, `SyncSkipIndex(domain: SyncSkipDomain.schedWeek).pushIfChanged(weekStart, fp(days), upsert)` where
  `fp` = `SyncFingerprint.of(days)` over the exact `days` map sent (canonical JSON; no sent-at field exists).
  Gate G1 holds (upsert inside the closure).
- **Removed days need a positive record (round 2 #2/#3).** An absence is never read. One local chokepoint
  `WorkoutWriteService.deleteScheduledRows(dates, {required String reason})` does the Hive deletes and adds each
  date's week to `workoutBox['sched_week_touched']` (`{weekStart: token}`, monotonic tokens as in
  `SchedUnpushedSwaps`), in one synchronous read-modify-put before the first delete. Callers: the five product
  deleters of 2.3 (`workout_schedule_read_service.dart:430`, `:1860`; `workout_schedule_write_service.dart:454`,
  `:472`; `template_service.dart:267`, incl. its restore-driven `cleanSyncTemplateSchedule` path, which is a
  deliberate removal of a ghost day the cloud week also holds) and the `swapScheduledDays` null write (not its
  rollback). A source test fails on any `.delete(`/`.deleteAll(` of a `schedule_` key under `lib/` outside the
  chokepoint and an allowlist (swap rollback, sim reset, `clear()`); round 1 #11 confirmed the deleter list.
- A touched week is pushed even when its fingerprint matches (`forcePushKeys`), and when it has NO local rows it
  pushes `{}`. Its `sched_week_touched` entry is removed only after a confirmed push AND only if the token is
  unchanged (`clearIfUnchanged`), so a failed push keeps it for the next pass (round 2 #3) and a newer touch is
  never cleared by an older push. A week with no local rows and no touch entry is never pushed.
- `commit(liveKeys: weeksWithLocalRows)`; an emptied week drops out of the index after its `{}` is confirmed
  (the cloud then holds `{}`; nothing local remains to compare).
- Owner checks are `SyncSkipIndex`'s own (`ownerChangedNow`). `pausedForSimulation` returns early, like
  `pushWorkoutPlanForSyncDomain`.
- First run after the switch: every local week pushes once (founder: ~32 weeks x ~30 KB ≈ 1 MB, once; a
  two-year user ~105 weeks ≈ 3 MB, once). Later: one week per changed week, typically 25-35 KB; the live
  maximum row is 10.3 KB, so a worst-case week is ~72 KB (round 2).
- **Accepted residues (stated, round 2 #9-#11):** a bulk writer that changes many weeks (regenerate, phase
  advance, hold clean-up) pushes them one request each, so a kill mid-pass leaves the cloud part new, part old
  until the next pass (no merge rule spans weeks; the plan row is pushed after the weeks, so a reader never sees
  a new window with old weeks, only old window with some new weeks). Per week, the last full write wins: a device
  pushing a week with a stale copy of another device's edit of a different day in that week overwrites it in the
  cloud (today the same happens to the whole history). A removed day is not removed on another device that still
  holds it, and that device's next push of the week brings it back (today's bundle has the same ping-pong).
- **Order at launch:** `checkAndSync` runs `_restoreIfNeeded` (the pull) before the sync passes; the plan keeps
  that order and a test pins it for the new pull.

### 5.4 Restore: weeks feed the SAME merge (Landing B, switch `enable_sched_week_restore`)
The week rows are flattened back into the bundle shape the merge already takes:
`schedules = ⋃ days` over the fetched weeks. That map goes through the unchanged tail of `_restoreWorkoutPlan`
(ghost filter -> `mergeScheduleBundleIntoHive` -> L1/L3/completed rules) and `PlanIntegrityReconciler.reconcile`
(same source switch, weeks of the heal window). Every call hands whole weeks (2.2), and a swap inside a week
arrives atomically.
- **Skip and echo, per week (today's L2 mechanism, unit changed):** for each fetched week, `downloaded =
  SyncFingerprint.of(days)`; if it equals the stored `schedWeek` fingerprint AND every key of `days` is present
  locally (the `bundledRowAccountedFor` rule incl. the OI-252 ghost-day exception, `sync_workout.dart:1634-1641`)
  the week is skipped; otherwise merged, then `SyncSkipIndex.recordConfirmed(schedWeek, weekStart, downloaded)`
  exactly as `:1687` does for the bundle. The next push compares the local week against the downloaded
  fingerprint: a merge that reproduced the cloud week sends nothing (no echo); a merge that kept local work
  differs and pushes (correct). Same shape on both sides (raw row maps), so no cloud-vs-local field mismatch
  (round-1 #10).
- **Full restore order (APK #12.9):** step A fetches the week rows (and the plan row) and runs the flattened
  merge where `_restoreWorkoutPlan` runs today; step B's `_restoreScheduledWorkouts` status/template overlay is
  unchanged and still last. Single-call restore: the EF returns `user_schedule_weeks` + `user_workout_plan`
  when the request asks (5.6).
- **Merge only, never delete (today's behaviour kept):** a key absent from a downloaded week is not removed
  locally, exactly as a key absent from today's bundle is not (`_restoreWorkoutPlan` and the merge only put).
  Cross-device propagation of a removed day is out of this plan's scope and unchanged from today.
- **Switch rule:** `enable_sched_week_restore` turns on only after the Landing C backfill (5.7); with it ON
  there is no per-day fallback to the bundle (round-1 #4). OFF = today's bundle path verbatim.

### 5.5 Launch pull with a watermark (Landing B, switch `enable_sched_week_restore`)
`restoreLightweightAlways` (ON) replaces the bundle download with:
1. `user_workout_plan` with `gt('updated_at', planWm)` (empty answer = unchanged). The current `current_plan`
   seed / `PlanWindowReanchor` code runs on the row when it comes.
2. `user_schedule_weeks` with `gte('updated_at', lowerBound)` ordered `updated_at, week_start`, `limit(1000)`,
   where `lowerBound` = the stored watermark minus 2 minutes, sent as a UTC `...Z` string (no `+`, round 2 #4).
   No keyset `or()`: a user has ~52 week rows a year, so one page covers it; a page that returns exactly 1000
   rows switches to a full pull paged by `week_start` (unique per user, the c7e2a9 rule) through
   `paginateAll`. A shared `updated_at` (the backfill stamps every row with one `now()`) cannot skip a row,
   because nothing pages on it. Millisecond precision loss on web only lowers the bound (more overlap). The
   2-minute overlap covers a transaction that committed after a later one; the merge is idempotent.
3. **Self-heal for a locally lost row** (round 1 #5): a second Hive key `workoutBox['sched_week_keys_index']`
   (`{weekStart: [schedule keys]}`, written next to every `schedWeek` confirm and pruned with it; the skip index
   itself only stores String fingerprints, `sync_skip_index.dart:~396-401`, round 2 #1) lists each confirmed
   week's keys. At launch, any listed key absent locally (except an OI-252 ghost day, the
   `bundledRowAccountedFor` rule) fetches that week by `week_start` and merges it.
- Watermarks `workoutBox['sched_week_pull_wm']` / `['plan_row_pull_wm']` (per-user box) store the MAX server
  `updated_at` STRING seen (never re-formatted); written only after every page merged AND
  `!ownerChangedSince(userId)`. Reset together with `sched_week_keys_index` by `sync_epoch` `clearAll`
  (`sync_service.dart:~1883`; `clearAll` loops `SyncSkipDomain.values`, so these keys get explicit deletes) and by
  the simulation reset (`simulation_service.dart:171-187`, `sim_reset_clears_all_sync_skip_indexes_test.dart`).
  First run: a full pull.
- The launch path still runs NO `_restoreScheduledWorkouts` overlay (same as today: it runs `_restoreWorkoutPlan`
  only). `user_progress` keeps its bare `.select()` (sync_epoch, progress); it is small once Landing C empties
  `plan_json`.

### 5.6 Edge Functions
- `restore-user-snapshot` (Landing B): today it parses no body and the client sends none
  (`index.ts:98-155`, `sync_service.dart:2411`, round 2 #5). Added: a tolerant body read (empty, non-JSON or
  over 1 KB = no flags; only the boolean `week_rows` is read), and two new READS tuples appended at the END,
  `user_schedule_weeks` (a `PagedReadSpec`, order `week_start`, unique per user) and `user_workout_plan`. They use
  Landing A's placeholder mechanism: without `week_rows: true` their thunks are not called and the post-step
  removes their keys, so the response is byte-identical to Landing A's (golden; `PAGED_READS` /
  `rowCountLogLine` tests updated for the new name). With the flag, the bundle read is skipped and
  `workout_plan` is `[]`. The new client sends the flag only with the restore switch ON.
- `partial_day_loader.ts` (Landing B, env switch `PARTIAL_DAY_WEEK_ROWS` exactly `"true"`): read
  `user_schedule_weeks` `days->schedule_<todayIST>` for `week_start = <IST Monday of today>` per user; the ids
  with no week row fall back to today's bundle read for those ids only (per-user, round-1 #15). After Landing C
  the fallback goes.
- The 7 status readers of `scheduled_workouts` (2.2 of draft 1) are untouched: that table does not change.

### 5.7 Landings
**Landing A:** see `docs/plans/oi530-landing-a-one-plan-read.md` (split out; its own review and records).

**Landing B, dark (one PR):** migration (5.1, 5.2), push (5.3), restore + launch pull (5.4, 5.5), EF changes
(5.6). Client switches in `configBox`, default OFF: `enable_sched_week_push`, `enable_plan_row_push`,
`enable_sched_week_restore`. EF: request flag `week_rows`, env `PARTIAL_DAY_WEEK_ROWS`. OFF = byte-identical
requests and Hive state (behavioural test per switch). §4.12.4 ship-dark: `review_rounds: 1` at build + B-pass;
full ×2 at the flip. Each switch logged in `docs/ship_dark_pending_review.yaml`.

**Landing C, flip + backfill + removal (full ×2 review; founder go per live step):**
1. Backfill SQL (live, go; rehearsed in local docker first): one `user_schedule_weeks` row per (user, IST week)
   built from `plan_json->'schedules'` (grouping by the IST Monday of each key's date, in SQL:
   `date_trunc('week', d)::date`, ISO weeks start Monday; every key's date is already an IST date string) and one
   `user_workout_plan` row per bundle, `ON CONFLICT DO NOTHING` (a week already pushed by a switched-on device
   is newer). Check query: every `schedules` key of every bundle appears in some week row's `days`; 0 missing
   (this covers the 23 days with no `scheduled_workouts` row, round-1 #3).
2. Flip the switches ON in code (defaults), EF env on, device check on the phone and the web app.
3. Same batch as the flip (§4.6 step 4): delete the old bundle paths (`_syncWorkoutPlan`'s bundle write, the L2
   bundle skip, `workout_plan` in the EF, the bundle fallback in `partial_day_loader`), keep the strippers until
   the column is gone.
4. Live cleanup (go, gated on the step-1 check re-run): `UPDATE user_progress SET plan_json = NULL`. Only from
   here does the per-launch download shrink (until then the launch `user_progress` read still carries the bundle,
   round 2 #7). An old build still upserts `plan_json` and would refill it, so the column is dropped (migration +
   strippers removed in the same commit, L7) only after the founder confirms every test device runs the new build
   (pre-launch: an old APK's plan push would then fail, which is acceptable only before the store launch).

## 6. Round-1 findings: disposition
| # | Finding | Disposition |
|---|---|---|
| 1 | Half a swap arrives; L3 tie sticks | Removed: week rows (swap = one row) |
| 2 | Tombstone RPC: RLS, completed rows, fresh-row delete | Removed: no tombstones; emptied week = `{}` row |
| 3 | Backfill loses 23 days | Folded: backfill from the bundle, not `scheduled_workouts`; check query gates cleanup |
| 4 | Launch pull vs bundle fallback contradiction | Folded: restore switch requires the backfill; no fallback when ON |
| 5 | Lost local row never re-fetched | Folded: index stores keys per week; local check fetches that week |
| 6 | Paging / watermark / epoch | Folded: keyset `(updated_at, week_start)`, watermark after last page, epoch resets it |
| 7 | DPDP + REVOKE | Folded: FK cascade on both tables, REVOKE anon |
| 8 | EF change shape; dual-write restore size | Folded: post-step `deriveWorkoutPlan`; week tables only on request flag |
| 9 | Merge input freshness; reconciler | Folded: tests with fresher statuses (7); reconciler on the same switch |
| 10 | Order; echo field mismatch | Folded: order stated; echo uses the same raw-map shape both sides |
| 11 | Deleter list / restore calls chokepoint | Removed: no chokepoint |
| 12 | Drain queue tokens | Removed: no queue |
| 13 | First push cost | Folded: stated in 5.3 |
| 14 | Guard tests pin the function | Not touched: `scheduled_workouts` and its guard are unchanged |
| 15 | partial_day per-user fallback | Folded: 5.6 |
| 16 | Registry / docs | Folded: 8 |
| 17 | Line accuracy | Folded: re-cited |

### Round 2 (draft 2) disposition
| # | Finding | Disposition |
|---|---|---|
| 1 | `{fingerprint, keys}` cannot live in SyncSkipIndex | Folded: separate `sched_week_keys_index` key, reset with epoch + sim |
| 2 | `{}` push inferred from absence | Folded: positive `sched_week_touched` record from one delete chokepoint + gate |
| 3 | `{}` push loses its retry | Folded: touched entry cleared only on confirmed push, token-checked |
| 4 | Keyset precision / `+` encoding | Folded: no keyset; `gte` lower bound as `Z` string; raw watermark string |
| 5 | EF parses no body; READS contract | Folded: tolerant body read; tuples appended, placeholder mechanism |
| 6 | Landing A key order / H-1 | Moved to the Landing A plan (placeholder keeps the slot) |
| 7 | Per-launch saving only after C4; old builds vs column drop | Folded: stated in C4 |
| 8 | Landing A strict fetch | Moved to the Landing A plan (strict fetch, op names kept) |
| 9-11 | Multi-week non-atomic, merge-only ping-pong, per-week LWW | Stated as accepted residues (5.3) |
| 12 | Flattening a subset | Confirmed fine |
| 13-14 | Gates and registry lists | Folded into 8 |

## 7. Tests (each mutated once, rule 21)
- Landing A: Deno `restore_reads_test.ts` golden for the one-read bundle (`workout_plan` derived, `plan_json`
  absent from `user_progress`), the no-row case, and the env rollback = old golden; a Dart stub test counting
  `user_progress` requests in both legacy restore paths (1; 2 with the switch on), and that `_restoreWorkoutPlan`
  still runs before `_restoreScheduledWorkouts`.
- Landing B:
  - Two-year fixture (515 rows, ~105 weeks) pushed by week, restored on an empty device through the week path:
    every `schedule_*` key equal to the bundle path's result (same fixture through both paths, byte-compared).
  - A swap inside a week on device A, pulled on device B: both days change together; the half-swap case cannot
    be constructed (one row).
  - Merge rules on week input: L1 rest guard, L3 arrangement, completed preserve, ghost filter, OI-532 mark,
    and a week whose `days` carries `completed` / `rest` against a local `planned` row (round-1 #9).
  - One-day change sends one week; an unchanged pass sends nothing; an emptied week sends `{}`; a cleared index
    sends no `{}`.
  - Watermark: shared `updated_at` across a page boundary (no row skipped); the 2-minute overlap; owner change
    mid-pull writes no watermark; `sync_epoch` bump re-pulls.
  - Self-heal: delete one local row of a confirmed week, launch pull refetches that week only.
  - Echo: a pure restore pushes nothing; a merge that kept a local completion pushes that week.
  - Each switch OFF: stub-server requests and Hive state byte-identical to today.
- SQL (local docker): touch trigger (no-op stays a no-op and keeps `updated_at`; a real change moves it), RLS
  (another user's row invisible and unwritable), FK cascade on user delete, backfill + check query on a copy of
  the live shape.
- Deno: `partial_day_loader_test.ts` week read + per-user fallback; `restore_reads_test.ts` with `week_rows`.

## 8. Process and records
Plan review ×2 (context-blind) before code; the §4.12.8 gate loop and CI before each review that has a diff;
B-pass before each merge; separate founder go for: Landing A EF deploy, Landing B migration apply, Landing C
backfill, each later live step. Migration number from `sh scripts/mint_migration.sh <slug>`; same commit:
`backups/applied_migrations.json` (on apply), `backups/live_schema_columns.json` regen. SoT registry: new
concepts `schedule_week_rows`, `schedule_week_payload_hash_index` (SyncSkipDomain `schedWeek`),
`schedule_week_pull_watermark`, `workout_plan_row`; update the existing plan-bundle entries
(`sot_registry.yaml` plan_json rows, `:580`, `:3243`) at Landing C. Docs: `docs/architecture/sync.md` (new
section; the `plan_json` section rewritten at C), `lib/core/services/CLAUDE.md` row, `docs/naming_conventions.md`
(new tables/keys), `docs/ship_dark_pending_review.yaml`. Landing A is not a bug fix (a cost change): no diagnose
doc; it gets a `project_*` retrospective. Also (round 2 #13-#14): `test/sql/onconflict_live_arbiter.sql` +
`scripts/check_onconflict_live_arbiter.dart` for the new `onConflict` targets (`user_id,week_start`, `user_id`);
`test/sql/rls_initplan_ab_verify.sql` cases for both tables; a
`sync_schedule_week_payload_hash_index_writer_to_reader_test.dart` and a Gate G1 pass for the new loop;
`scripts/check_hive_map_field_drift.dart:408-412` (plan-bundle field list) at Landing C; naming rows for
`user_schedule_weeks`, `user_workout_plan`, `schedWeek`, `week_start`, and the `days` column (the glossary's
existing `days` row is a different concept, `naming_conventions.md:575`).

## 9. Open questions for the founder (none block Landing A)
- Q1: is the web app (app.icanbefitter.com) deployed automatically from `main`? Landing C's cleanup waits until
  every client runs the new build.
