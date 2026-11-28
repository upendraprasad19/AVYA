# OI-530: schedule sync by week row (Option C) + one download per restore

Status: plan, draft 8, CONVERGED at round 8 (rounds 1-8 folded; acceptance rule 5.0; Landing A split out to `oi530-landing-a-one-plan-read.md` under
§4.12.1 and is NOT governed by this file any more; B/C may now be built, ship-dark, per section 5). Tier L (sync, schema, Edge Functions). Execution:
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

Landings (5.7): A = one download per restore (split out, own plan); B = schema + dual write + new read paths behind
default-OFF switches (ship dark); C = backfill, flip, old paths and the bundle removed.

### 5.0 The acceptance rule: same behaviour as today, smaller unit (draft 5)
Founder goal (2026-11-28): cost and app speed. Rounds 1-4 kept finding issues in designs that ALSO changed
conflict behaviour (per-day rows, tombstones, a server-side merge that copied the client's merge rules into SQL,
two copies of one rule being this repo's top recurrence class, `a7d3f1`/`d9b2c5`). Draft 5 changes only the UNIT
of transfer, from the whole history to one IST Mon-Sun week, and keeps today's semantics:
- **Today:** a push sends the device's FULL local copy (`schedules` = every local `schedule_*` key) and it
  replaces the cloud copy; a pull merges the cloud copy into local rows through `mergeScheduleBundleIntoHive`
  (merge only, never delete); a key the device no longer has is absent from its push, so the cloud loses it.
- **Draft 5:** a push sends the device's full local copy of each CHANGED week, which replaces that cloud week,
  plus a manifest of which weeks the device has; a pull merges whole weeks through the same merge; a week the
  device no longer has is absent from its manifest, so readers ignore the cloud week.
- **Review criterion:** for every scenario, draft 5's outcome equals today's, or is narrower (one week instead of
  the whole history). A behaviour identical to today is a stated residue (5.8), not a finding. Improving
  cross-device conflict resolution is a separate product decision, not part of OI-530.

### 5.1 Week rows (migration, Landing B)
`public.user_schedule_weeks (user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE, week_start date
NOT NULL, days jsonb NOT NULL DEFAULT '{}', updated_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY (user_id,
week_start))`.
- `days` = `{'schedule_<date>': <the full local row>}` for that week's local keys, exactly the per-key content the
  bundle carries today.
- RLS own-row select/insert/update (`(select auth.uid()) = user_id`), no delete policy; `REVOKE ALL` from `anon`;
  FK cascade for DPDP `delete-account` (`delete-account/index.ts:411-419`).
- BEFORE UPDATE trigger `private.user_schedule_weeks_touch()` (SECURITY INVOKER, `SET search_path = public,
  pg_temp`): `IF NEW IS NOT DISTINCT FROM OLD THEN RETURN NULL; END IF; NEW.updated_at := now(); RETURN NEW;`.
  The client never sends `updated_at`, so ON CONFLICT DO UPDATE leaves it out of SET and the no-op check holds.
- `CREATE INDEX ON user_schedule_weeks (user_id, updated_at, week_start)` for the launch pull.
- The client writes with a plain upsert `onConflict: 'user_id,week_start'` (no RPC, no server merge rule).

### 5.2 The plan row and the week manifest (migration, Landing B)
`public.user_workout_plan (user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE, plan jsonb,
plan_start_date text, plan_end_date text, weeks jsonb NOT NULL DEFAULT '[]', updated_at timestamptz NOT NULL
DEFAULT now())`, same RLS / REVOKE / touch trigger.
- `weeks` = the sorted list of `week_start` dates for which the device holds at least one `schedule_*` key: the
  week-level image of today's bundle key set. It is what makes a removed week behave as today (absent from the
  device's copy) without any per-site deletion record (drafts 2-4's chokepoint, touched set and RPC are gone).
- `_syncWorkoutPlan` (switch ON) upserts `{plan, plan_start_date, plan_end_date, weeks}` through a new
  `SyncSkipDomain.planRow` index; fingerprint over exactly those four keys (no sent-at field). The bundle keeps
  being written verbatim while dark (dual write).

### 5.3 Push (Landing B, switch `enable_sched_week_push`)
**WHEN = exactly today's plan push, never anywhere else (round 5 P0).** The weeks, the manifest and the plan row
are sent ONLY from inside `_syncWorkoutPlan`, i.e. from the same three callers that push the bundle today
(`pushWorkoutPlanForSyncDomain` :2997 with its `pausedForSimulation` guard, `weeklyFullSync`
`sync_service.dart:1430` with the fresh-device first-sweep postponement, `WorkoutsSyncDomain.push`). Nothing is
added to the `syncWorkoutData` fan-out: OI-189 (`b9e4d1`, sync.md "plan_json push is NOT part of the workout
fan-out") stays true, so a fresh device that generates a local plan before its restore
(`workout_schedule_read_service.dart:277`, `:498` fire `syncWorkoutData`) still cannot overwrite the real cloud
copy. A pin runs `generateAndSchedule` on an empty Hive then `syncWorkoutDataNow` and asserts zero
`user_schedule_weeks` / `user_workout_plan` writes (mutant: call the week step from the fan-out). A completed day
therefore reaches the week row when today's bundle would carry it (the next plan push or daily sweep), not sooner.
Inside `_syncWorkoutPlan` (switch ON), in this order:
- Group local `schedule_*` keys by `DaySwapRules.mondayOf(date)`. A key is used only if its date round-trips
  exactly (`YYYY-MM-DD` parse then format equals the key; `schedule_2026-02-30` is skipped and reported once,
  round 4 #4); the same rule builds the manifest.
- Per week: `SyncSkipIndex(domain: SyncSkipDomain.schedWeek).pushIfChanged(weekStart, fp(days), upsert)`,
  `fp` = `SyncFingerprint.of(days)` over exactly the map sent; Gate G1 holds (upsert inside the closure).
- `commit(liveKeys: weeksWithLocalRows)`. A week that lost all its local keys is not pushed; it leaves the
  manifest, which is what removes it for readers (today: its keys leave the bundle).
- Then the plan row (`plan`, window, `weeks`) through `SyncSkipDomain.planRow`, ONLY when every changed week of
  this pass confirmed (round 5 #3): a week failure skips the plan row this pass, so the manifest never lists a
  week the cloud does not hold in its new form; the next pass retries both. A reader that finds a listed week with
  no row merges nothing for it (keeps local, no error); tested.
- Owner checks are `SyncSkipIndex`'s own; `pausedForSimulation` returns early.
- Latency once: the first ON run's push is ~32 sequential week requests (two-year user ~105), behind
  `generateAndSchedule`'s `planPushTimeout` (20 s) on that path; a timeout does not cancel the pass, which
  completes in the background and confirms per week (round 6 #4).
- Cost: first ON run pushes every week once (founder ~32 weeks x ~30 KB ≈ 1 MB, once). Then one week (typ.
  25-35 KB, worst case ~72 KB: live max row 10.3 KB) per changed week, plus the plan row (70-150 KB) ONLY when
  the plan, the window or the manifest changes (today: the whole history every time).
- A day removed inside a week that still has other days: the next push of that week omits it, so the cloud
  week loses it (today: same, the bundle omits it).

### 5.4 Restore: weeks feed the SAME merge (Landing B, switch `enable_sched_week_restore`)
- Fetch the plan row and the week rows; keep only weeks listed in the plan row's `weeks` (a week the pushing
  device no longer has is ignored, exactly as a key absent from today's bundle is never seen). Flatten: `schedules
  = ⋃ days`. That map goes through the unchanged tail of `_restoreWorkoutPlan` (ghost filter ->
  `mergeScheduleBundleIntoHive` -> L1/L3/completed rules) and `PlanIntegrityReconciler.reconcile` (same source
  switch). Each call is handed whole weeks (2.2); a swap (always inside one week) arrives atomically.
- **Skip and echo, per week (today's L2, unit changed):** `downloaded = SyncFingerprint.of(days)`; skip the week
  when it equals the stored `schedWeek` fingerprint AND every key of `days` exists locally (the
  `bundledRowAccountedFor` rule incl. the OI-252 ghost exception, `sync_workout.dart:1634-1641`); otherwise merge
  and `recordConfirmed(schedWeek, weekStart, downloaded)`, as `:1687` does for the bundle. The plan row's
  fingerprint is recorded the same way. A merge that reproduced the cloud week makes the next push send nothing;
  a merge that kept local work differs and pushes (today: the same, for the whole bundle).
- Full restore order (APK #12.9): step A runs this where `_restoreWorkoutPlan` runs today; step B's
  `_restoreScheduledWorkouts` overlay is unchanged and still last (its OI-533 interaction is unchanged, 5.8).
- Merge only, never delete, as today.
- `enable_sched_week_restore` turns on only after the Landing C backfill (5.7); no per-day fallback to the bundle
  when ON. OFF = today's bundle path verbatim.

### 5.5 Launch pull with a watermark (Landing B, switch `enable_sched_week_restore`)
`restoreLightweightAlways` (ON) replaces today's per-launch bundle download with:
1. The plan row with `gte('updated_at', planLowerBound)`; empty = unchanged. When it comes, today's
   `current_plan` seed / `PlanWindowReanchor` code runs on it and its `weeks` list replaces the stored manifest.
2. `user_schedule_weeks` with `gte('updated_at', weeksLowerBound)` ordered `updated_at, week_start`,
   `limit(1000)`; exactly 1000 rows switches to a full pull paged by `week_start` (unique per user, c7e2a9)
   through `paginateAll`. Lower bound = stored watermark minus 2 minutes, sent as a UTC `...Z` string;
   comparisons on `DateTime.parse(raw).toUtc()`; the raw max string is stored. The overlap re-fetches the newest
   week, which the per-week skip makes a no-op (a no-change launch writes nothing: tested). Weeks not in the
   manifest are ignored.
   **Manifest catch-up (rounds 6-7), stateless:** a week row can be written before the manifest that lists it
   (weeks are pushed first; a plan-row push can fail and retry), so the watermark may already be past a row this
   reader ignored. So on EVERY launch pull, AFTER step 2, every week in the stored manifest that has no
   `sched_week_keys_index` entry is fetched by `week_start` (one `in('week_start', [...])` read, chunked at 100),
   whatever the watermark, and merged. No "the manifest changed" trigger exists, so an interrupted catch-up is
   simply retried next launch (round 7 #1). A listed week the cloud has no row for gets an EMPTY index entry, so it
   is not refetched every launch; a later row for it arrives through the watermark (its `updated_at` is newer).
   After a confirmed plan-row push the device stores the manifest it sent as its local manifest, so its own echo
   is not new. Cost: a week is fetched at most once more than today's bundle would carry it, then recorded.
   Index bookkeeping (round 8 #1): the keys index is pruned ONLY against the stored manifest (an entry for a week
   the manifest no longer lists is dropped), never against local live keys, so an empty entry survives a push
   pass; a week whose keys are all ghost days writes an empty entry at its confirm; the catch-up writes empty
   entries for rowless weeks directly and never touches a watermark. An interrupted FULL pull (first run, after
   sign-out or `clearAll`) is retried whole next launch, and the catch-up is skipped while a full pull is pending,
   so no week is fetched twice (round 8 #2).
3. **Today's incidental self-heal, kept:** today the launch re-merges the whole bundle whenever any bundled key is
   absent locally (`:1634-1649`). Draft 5 keeps that per week: `workoutBox['sched_week_keys_index']`
   (`{weekStart: [keys]}`, written next to every `schedWeek` confirm, pruned with it) lists each confirmed
   week's keys AS THEY EXIST LOCALLY after that confirm: for a pushed week, the keys sent; for a restored week,
   the keys the merge was handed after the ghost filter (a ghost day is never listed, so it never triggers a
   fetch: round 5 #2; tested with a ghost day, second launch makes zero requests); a listed key absent locally (ghost exception as above) fetches that week by `week_start` and
   merges it. Like today, this also puts back a row deleted locally whose removal has not been pushed yet (5.8).
- Watermarks `workoutBox['sched_week_pull_wm']`, `['plan_row_pull_wm']` and the keys index are per-user-box
  keys, written only after every page merged AND `!ownerChangedSince(userId)`, reset by `sync_epoch` `clearAll`
  (explicit deletes: `clearAll` loops `SyncSkipDomain.values`) and by the simulation reset. Sign-out clears the
  per-user box. First run: full pull.
- `user_progress` keeps its bare `.select()` (sync_epoch, progress); it shrinks only at Landing C step 4.

### 5.8 Residues identical to today (stated, not findings)
| Scenario | Today (whole bundle) | Draft 5 (week + manifest) |
|---|---|---|
| A stale device pushes its copy | replaces the whole cloud history | replaces only the weeks it changed |
| Two devices keep different versions of a day (both non-empty, or both completed) | each launch's push/pull alternates the bundle | alternates that one week |
| Day removed on A, still on B | B's next bundle push brings it back | B's next push of that week brings it back |
| A removal not yet pushed, then a launch pull | today's L2 re-merge can put the row back | the week self-heal can put it back |
| A partial local copy pushed (Hive loss, partial restore) | cloud loses the missing rows | cloud loses them in the weeks pushed |
| `_restoreScheduledWorkouts` recreates a removed day from its `scheduled_workouts` row (OI-533) | yes | yes; OI-533 keeps its own fix |
| A completed day vs a stale planned copy | client merge keeps local completed; cloud may hold the stale copy | same |
| A device removes a whole week | its keys leave the bundle (gone from cloud) | it leaves the manifest; the cloud row stays as an orphan readers ignore (round 5 #4); Landing C step 4 deletes week rows not in their user's manifest |
| A device drops a whole week after Landing C's cleanup | n/a | the cloud row stays as an orphan readers ignore; no periodic cleanup (bounded, a few rows per regenerate) |
| Old-build devices during the switch-over | n/a | an old build keeps writing only the bundle; a new build that restores in that window reads week rows from the backfill, possibly older than the bundle (pre-launch, testing accounts only; round 5 #6) |

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
  `user_schedule_weeks` `days->schedule_<todayIST>` for `week_start = <IST Monday of today>` per user. The
  Monday is a NEW pure `istMondayDateStr(now)` in `_shared/ist_date.ts` (`YYYY-MM-DD`; the existing
  `istWeekStartIso` returns a `+05:30` timestamp that would reach PostgREST unencoded, round 3 #7), with a Deno
  test across Sunday 18:30 UTC to Monday 00:00 IST; the select string stays a template literal
  (`check_schema_column_refs.dart` rule); the ids
  with no week row fall back to today's bundle read for those ids only (per-user, round-1 #15). After Landing C
  the fallback goes.
- The 7 status readers of `scheduled_workouts` (2.2 of draft 1) are untouched: that table does not change.

### 5.7 Landings
**Landing A:** see `docs/plans/oi530-landing-a-one-plan-read.md` (split out; its own review and records).

**Landing B, dark (one PR):** migration (5.1, 5.2), push (5.3), restore + launch pull (5.4, 5.5), EF changes
(5.6). Client switches in `configBox`, default OFF: `enable_sched_week_push` (weeks + plan row + manifest),
`enable_sched_week_restore`. EF: request flag `week_rows`, env `PARTIAL_DAY_WEEK_ROWS`. OFF = byte-identical
requests and Hive state (behavioural test per switch). §4.12.4 ship-dark: `review_rounds: 1` at build + B-pass;
full ×2 at the flip. Each switch logged in `docs/ship_dark_pending_review.yaml`.

**Landing C, flip + backfill + removal (full ×2 review; founder go per live step):**
1. Backfill SQL (live, go; rehearsed in local docker first), run BEFORE any device has the push switch on (a
   precondition: the switches flip in the same release as this step, so no week row exists yet): from each bundle
   whose `schedules` is a JSON object, one `user_schedule_weeks` row per (user, ISO week of the key's date,
   `date_trunc('week', d)::date`, equal to Dart `mondayOf`, verified live round 4) over keys matching
   `^schedule_\d{4}-\d{2}-\d{2}$` AND `pg_input_is_valid(substr(key, 10), 'date')` (a regex-valid
   `2026-02-30` must not abort the statement); one `user_workout_plan` row per bundle with `weeks` = those week
   starts. `ON CONFLICT DO NOTHING` on both (a row there already came from a device's own push, which is newer
   than its bundle; no union, so no stale bundle day can override or resurrect anything, round 4 #8). The check
   query compares KEY SETS: every valid bundle key is in its week row's `days` (this covers the 23 days with no
   `scheduled_workouts` row, round 1 #3); 0 missing.
2. Flip the switches ON in code (defaults), EF env on, device check on the phone and the web app.
3. Same batch as the flip (§4.6 step 4): delete the old bundle paths (`_syncWorkoutPlan`'s bundle write, the L2
   bundle skip, `workout_plan` in the EF, the bundle fallback in `partial_day_loader`), keep the strippers until
   the column is gone.
4. Live cleanup (go, gated on the step-1 check re-run): `UPDATE user_progress SET plan_json = NULL`, and delete
   `user_schedule_weeks` rows whose `week_start` is not in their user's `user_workout_plan.weeks` (orphans):
   only for users that HAVE a plan row (`NOT EXISTS` over `jsonb_array_elements_text(weeks)`; a user with week rows
   and no plan row keeps all of them), run while no new-build push is in flight (founder's devices idle). Orphans a
   device creates after this step (it drops a whole week) are not cleaned again: bounded (a few rows per
   regenerate), readers ignore them; stated in 5.8. Only from
   here does the per-launch download shrink (until then the launch `user_progress` read still carries the bundle,
   round 2 #7). An old build still upserts `plan_json` and would refill it, so the column is dropped (migration +
   strippers removed in the same commit, L7) only after the founder confirms every test device runs the new build
   (pre-launch: an old APK's plan push would then fail, which is acceptable only before the store launch).

## 6. Round-1 findings: disposition
| # | Finding | Disposition |
|---|---|---|
| 1 | Half a swap arrives; L3 tie sticks | Removed: week rows (swap = one row) |
| 2 | Tombstone RPC: RLS, completed rows, fresh-row delete | Removed: no tombstones (the `{}` row of draft 2 is itself superseded by draft 5's manifest) |
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

### Round 8 (narrow): converged
| # | Finding | Disposition |
|---|---|---|
| 1 | Empty-entry write and prune rule unspecified | Folded: prune against the stored manifest only; whole-ghost week writes an empty entry; catch-up writes empties, no watermark |
| 2 | First-pull double fetch | Folded: catch-up skipped while a full pull is pending |
| 3 | Three tests | Folded into section 7 |

### Round 7 (narrow) disposition
| # | Finding | Disposition |
|---|---|---|
| 1 | Catch-up trigger lost after an interrupted fetch | Folded: stateless catch-up every launch after step 2; empty entry for a rowless listed week; pushed manifest stored locally |
| 2-5 | Orderings, cost, fresh device, tests | Folded: tests added; catch-up after step 2 so a first run does not fetch twice |
| 6 | Later orphans residue | Folded: 5.8 row |
| 7 | Contradiction sweep | Clean |

### Round 6 (narrow) disposition
| # | Finding | Disposition |
|---|---|---|
| 1 | Week written before its manifest can be skipped past the watermark | Folded: manifest catch-up fetch by `week_start` (5.5) + test |
| 2 | Section 7 stale | Folded: section 7 rewritten for draft 5; round-1 row 2 marked superseded |
| 3 | Orphan delete under-specified | Folded: only users with a plan row, `NOT EXISTS`, devices idle; later orphans stated |
| 4 | First-run latency | Folded: stated in 5.3 |

### Round 5 (draft 5) disposition
| # | Finding | Disposition |
|---|---|---|
| 1 (P0) | Weeks in the fan-out break OI-189 (fresh device overwrites the cloud) | Folded: weeks and plan row only inside `_syncWorkoutPlan` (today's callers and guards); pin + mutant |
| 2 | Keys index cannot honour the ghost exception | Folded: index holds the keys as they exist locally after the confirm |
| 3 | Partial week failure vs manifest | Folded: plan row only when every changed week confirmed; listed-but-missing week = no merge |
| 4 | Orphan week rows | Stated (5.8); deleted at Landing C step 4 |
| 5 | EF readers audit; sim flush | Folded into 8 (audit: no EF reads `plan_json` but the loader and restore-user-snapshot); the week step is inside `_syncWorkoutPlan`, so the sim's end-of-run plan flush covers it |
| 6 | Backfill window | Stated (5.8) |

### Round 4 (draft 4) disposition
| # | Finding | Disposition |
|---|---|---|
| 1 | Server per-day merge is push-order wins and diverges from L3 | Removed: no server merge (5.0); whole-week upsert, the client merge decides as today |
| 2 | Completed guard misses moved/dropped; status ping-pong | Removed with the server merge; the remaining ping-pong is today's, per week (5.8) |
| 3 | Cross-device removal text wrong | Corrected: 5.8 states today's behaviour per week |
| 4 | Regex-valid invalid date blocks a week; RPC hardening | Folded: strict round-trip on the client, `pg_input_is_valid` in the backfill; no RPC |
| 5 | Fingerprint after a removal causes a spurious push | Removed: no `removed` field |
| 6 | Two-device ping-pong | Stated as today's residue (5.8) |
| 7 | Removal edge cases | Removed: no removal record; a removed week leaves the manifest |
| 8 | Backfill union applies no guard | Folded: `DO NOTHING`, backfill before any push switch |
| 9 | Keys index cleared on sign-out? | Folded: per-user box (5.5) |
| 10 | Export path | Checked in round 5 |

### Round 3 (draft 3) disposition (rows 1-3 superseded by draft 5: the record/RPC they fold no longer exists; 5.8 states the behaviour)
| # | Finding | Disposition |
|---|---|---|
| 1 | Self-heal resurrects a removed day | Folded: self-heal and every week merge skip `sched_week_removed` keys; chokepoint prunes the keys index |
| 2 | A partial local week overwrites a fuller cloud week | Removed: the server merges per day (`merge_schedule_week`); a push can only add, replace or name removals |
| 3 | Removal record never expires; forcePushKeys timing | Folded: 14-day prune + one report; force set read before the index |
| 4 | Watermark parse | Folded: compare parsed UTC values |
| 5 | EF test/registry list | Folded into 8 |
| 6 | Backfill guards; subset rows | Folded: object/regex guards; `DO UPDATE` union, existing wins per key; key-set check |
| 7 | Monday helper | Folded: `istMondayDateStr` + Deno test |
| 8 | Registries; OFF writes no new key | Folded: 5.3 (no Hive key while dark) and 8 |
| 9 | Cross-device removal | Stated (5.3 residue) |

### Round 2 (draft 2) disposition (rows 2-3 superseded by draft 5's manifest)
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
  - A swap inside a week on device A, pulled on device B: both days change together (one row).
  - Merge rules on week input: L1 rest guard, L3 arrangement, completed preserve, ghost filter, OI-532 mark; a
    week whose `days` carries `completed` / `rest` against a local `planned` row with exercises: the expected
    result is TODAY's (`mergeScheduleEntry` keeps the local row with exercises; round 4 #2), asserted equal to the
    bundle path's result on the same input.
  - Push: a one-day change sends that one week and, only if the plan / window / manifest changed, the plan row; an
    unchanged pass sends nothing; a week that lost all its local keys is not pushed and leaves the manifest.
  - **Timing pin (round 5 P0):** `generateAndSchedule` on an empty Hive, then `syncWorkoutDataNow`: zero
    `user_schedule_weeks` / `user_workout_plan` writes; and the `pushPlanWindow: true` path pushes through
    `_syncWorkoutPlan` only. Mutant: call the week step from the fan-out.
  - **Partial failure (round 5 #3):** one week upsert fails -> no plan-row push this pass, both retried next pass;
    a reader that finds a listed week with no row merges nothing and reports nothing.
  - **Ghost day (round 5 #2):** a restored week containing a ghost day: the second launch makes zero requests.
  - **Manifest catch-up (rounds 6-7):** a week row written before the manifest lists it is fetched on the next
    launch after the manifest arrives; a catch-up interrupted midway (stub fails the `in` read) is retried and the
    week arrives on the following launch; a week re-added with identical content (no `updated_at` move) still
    arrives; a listed week with no cloud row is fetched once and then never again (empty index entry); a no-change
    launch makes no catch-up request.
  - A week whose keys are all ghost days: the second launch makes zero requests; a push followed by a launch makes
    zero catch-up requests (stored sent manifest); an empty entry survives a push pass (mutant: prune the index by
    local live keys).
  - Watermark: shared `updated_at` (backfill-stamped) across the 1000-row fallback (no row skipped); the 2-minute
    overlap; owner change mid-pull writes no watermark; `sync_epoch` bump and sim reset re-pull.
  - Self-heal: delete one local row of a confirmed week, the launch pull refetches that week only.
  - Echo: a pure restore pushes nothing; a merge that kept a local completion pushes that week.
  - Each switch OFF: stub-server requests and Hive state (no new key) byte-identical to today.
- Landing C: the orphan delete (step 4) on a local-docker copy: only users that have a plan row, `NOT EXISTS` on the
  manifest's date strings, a user with week rows and no plan row keeps all of them; the backfill key-set check.
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
existing `days` row is a different concept, `naming_conventions.md:575`). Round 3 additions: `test/contracts/sync_noop_trigger_tables_test.dart`
(both new tables carry a no-op-suppressing touch trigger); the `SyncSkipDomain.values` count test,
`sim_reset_clears_all_sync_skip_indexes_test.dart` and Gate G1's hash-index literal rule for the new
`schedWeek`/`planRow` values; the EF tests that pin the READS name count (`restore_reads_test.ts:72-75`), the
paged-name sets (`:40`, `:81`, `:181-211`), `rowCountLogLine` (`paged_reads.ts:337-346`: the new paged read is
kept OUT of the iterated `PAGED_READ_NAMES` set so the log line stays byte-identical with the flag off),
`fake_restore_db.ts` and `old_chains.fixture.json`; one named test per switch asserting no new Hive key and no new
request while OFF; `test/sql/` local-docker cases for the week and plan tables (touch trigger no-op, RLS another user's row
unreachable, FK cascade) and the backfill (`pg_input_is_valid` guard, key-set check, `DO NOTHING`).

## 9. Open questions for the founder (none block Landing A)
- Q1: is the web app (app.icanbefitter.com) deployed automatically from `main`? Landing C's cleanup waits until
  every client runs the new build.
