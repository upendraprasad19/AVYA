# OI-532: a stale schedule restore undoes an unpushed day swap

Status: plan (rounds 1-2 folded; round 3 narrow). Tier L (sync restore path). Execution: inline, one worktree
(`claude/compassionate-lalande-699432`), never switched.

## 1. Observation (from the OI-532 board entry, re-verified on main 9472de6f)

Swap Fri (workout) <-> Sat (rest) while offline, relaunch before the push lands. The launch restore
(`_restoreScheduledWorkouts`) reads the cloud's PRE-swap rows and overlays them:
- Sat (now a local workout): cloud status `rest` -> `type: 'rest'` (`sync_workout.dart:2810`) and the rest
  strip (`:2860-2871`) erases its exercises. The workout is lost.
- Fri (now local rest): cloud status `planned` + the cloud `template_id` -> `status planned`, and on a template
  day the cloud template is re-hydrated / `template_id` re-added (`:2808`, `:2819`).
Not new with the rescue (OI-348 3d): every swap has it.

## 2. Writers and readers (file:line, main 9472de6f)

| Role | Site |
|---|---|
| Local writer of the swap | `lib/core/services/workout_write_service.dart:842` `swapScheduledDays` (all-four-keys-or-none put loop `:901-928`), called only by `SwapService.swapDays` (`swap_service.dart:536`), incl. the rescue |
| Push (the only thing that makes the swap "pushed") | `lib/core/services/sync/sync_workout.dart:2263` `_syncScheduledWorkouts`, per row `index.pushIfChanged(date, ...)` `:2359`; returns true = row confirmed in the cloud (`sync_skip_index.dart:231-299`) |
| Reader that undoes it | `lib/core/services/sync/sync_workout.dart:2542` `_restoreScheduledWorkouts`: status merge `:2644-2684`, type `:2808-2815`, `template_id` overlay `:2819`, rest strip `:2860-2871`, put `:2872`. Called from `sync_service.dart:1962` (after `_restoreWorkoutPlan`, so it is the last writer), `:2280`, `:2512` |
| Downstream readers of `schedule_<date>` | Train week rows, Home today card (`WorkoutScheduleReadService`) — unchanged |

The cloud `scheduled_workouts` row has no timestamp column (`backups/live_schema_columns.json`), so the
restore cannot compare ages.

## 3. Bug history (§4.1.5)

Same class, third instance: "restore treats a stale cloud row as authoritative over a local change not yet
pushed". Prior: `d9b2c5` (local `completed` demoted by stale cloud `planned`; fix = completed arm), `e8f4a3`
(local terminal moved/dropped resurrected; fix = terminal arm), `a3e7d9`/F4 (completed vs cloud rest).
Each was fixed per STATUS. A swap changes content+status together, so a status arm cannot express it; this
fix keys on "this date carries a local swap the cloud has not confirmed" instead. Related: `b6e1c8`
(rest/template hybrid), `b4f7e2` (sched fingerprint index).

## 4. Rejected designs (do not re-explore)

- **Keep any local row with `arranged_at_ms`** (OI-348 3d plan 3.5, R2-1/R2-2): re-adds `template_id` on
  template days (the merge still ran), and is permanent because `upsertScheduled`'s `carriesArrangement`
  re-stamps `arranged_at_ms` on every later rewrite; after a CONFIRMED push the two devices diverge forever.
  Also wrong on a fresh device: `_restoreWorkoutPlan` lands rows WITH another device's `arranged_at_ms`.
- **"Local push fingerprint != stored `sched` fingerprint" as the guard**: a fresh device, a cleared index
  (`sync_epoch` `clearAll`) or `disable_sched_hash_skip` (index deleted at every commit) has NO stored
  fingerprint, so every arranged row on that device would read as unpushed and its stale bundle view would
  be pushed over newer cloud rows. Unpushed-ness must be a positive fact written by the swap, not an absence.
- **Comparing the row's `updated_at_ms` / `arranged_at_ms` to a marker**: both are re-stamped on any later
  rewrite of the row (`:767`, `:773`), so an edited-but-still-unpushed swapped row would lose its guard.

## 5. Design

### 5.1 The marker (`lib/core/services/sync/sched_unpushed_swaps.dart`)
Two parts.

**Persisted** (`workoutBox['sched_swap_unpushed']`, per-user box: sign-out / account swap / DPDP clear it):
`{IST date: token}` plus a reserved entry `'_seq'` (the last token ever issued; `read` excludes it). Every
token is `max(nowMs, _seq + 1)`, so a token is never reused, even after a clear or a clock step back (R2-5).
Each helper is one synchronous read-modify-`put` (Hive updates its in-memory keystore before the first await,
verified by both reviews in hive 2.2.3 `box_impl.dart` / `keystore.beginTransaction`).
- `markAll(box, dates)`, `tokenOf(box, date)`, `isPendingStored(box, date)`.
- `clearIfUnchanged(box, date, token)`: removes the date only if its stored token still equals `token` AND the
  date is not in flight (below).
- `prune(box)`: drops dates with no `schedule_<date>` row at prune time (and not in flight).
Malformed stored value -> treated as empty (fail OPEN: today's behaviour), reported once.

**Process-local** (statics, never persisted; reset by `resetForUser()` from `_onUserChanged` and in tests):
- `_inFlight`: dates of a swap between its first mark and its last (R2-4). `isPending` is true for them and
  `clearIfUnchanged` refuses them.
- `_seq` and `_touched[date]`: a process counter bumped by every mark AND every clear, recording the counter
  value on the date. `fetchMark()` returns the current counter. `touchedSince(date, mark)` = `_touched[date] >
  mark`. The race the restore must survive is in-process (a new process re-fetches), so memory is enough.

`isPending(box, date)` = stored mark OR in flight.

### 5.2 Writer: `swapScheduledDays`
Inside the two-date lock, after the build/completed checks: `beginSwap({a, b})` (adds to `_inFlight`, then
`markAll` = T1) BEFORE the four-key put loop (`:901`); after the loop succeeds, `markAll` again (T2 > T1); in a
`finally`, `endSwap({a, b})` removes the dates from `_inFlight`. The restore takes no date lock and every `put`
yields, so the mark exists before the first swapped row does. A rollback keeps the T1 mark: harmless (one
restore keeps the unchanged local row; the next push finds an equal fingerprint, skips, returns true, clears).
A marker write failure is caught + `recordNonFatal` and never fails the swap. Test seam
`debugAfterPreMarkForTests` (awaited between T1 and the rows) for T12.

### 5.3 Clearer: `_syncScheduledWorkouts`
Per row, `token = tokenOf(box, date)` in the same synchronous run as `workoutBox.get(key)` (`:2307`), captured
before the push await; the clear uses exactly that value.
- R2-2: Case 2's omitted-key fallback (`upsertOnce(null, false)`, `:2407`) leaves the cloud `template_id` at its
  pre-swap value. When `token != null` that branch still runs the upsert but returns `false` (unconfirmed:
  the fingerprint is dropped, the marker kept, the row re-pushed next pass) so no later skip-branch `true` can
  clear it. With no mark the branch is unchanged (byte-identical for every unswapped row).
- After `pushIfChanged` returns `true` and `token != null`: `clearIfUnchanged(box, date, token)`. The skip
  branch's `true` is a clear: the stored fingerprint equals this content, so the cloud holds it (a swap of
  two non-template `planned` days does not change the fingerprint; the cloud rows already agree).
- `false` keeps the marker. After the loop, next to `index.commit`: `prune(box)` unless `index.aborted`.

### 5.4 Race arguments (per date)
(a) Swap during a push pass. Swap = [inFlight+T1] [rows] [T2] [-inFlight]. Push = [token+row, sync] -> await
-> [CAS token].
- Token read before T1 (old/null): CAS fails against T1/T2, or is skipped -> kept. Correct.
- Token = T1: CAS refused while in flight, and fails against T2 after. Kept; next pass pushes the swapped row.
- Token = T2: the rows were put before T2 -> the pushed row is the swapped row -> CAS clears. Correct.
(b) Swap during a restore's MERGE. The guard runs synchronously right before the restore's `put`. A swap whose
rows that put could overwrite is in flight from before its first row put, so the guard sees it or the swap's
rows land after the restore's put. The restore's `existingMap` (read before the template awaits) may be
stale; harmless, a pending date is skipped.
(c) Anything that happened to the date after the restore's FETCH (R1-2, R2-1): a swap marked after the fetch
and possibly pushed and cleared since, or a mark that was pending at the fetch and cleared since. Both
bump `_touched`. The restore takes `fetchMark()` BEFORE its fetch (top of `_restoreScheduledWorkouts` for its
own read; in `_attemptSingleCallRestore` right before `callFunction('restore-user-snapshot')`,
`sync_service.dart:~2404`, passed in as `fetchMark:`) and guards `touchedSince(date, fetchMark)`. This replaces
round 1's `pendingAtFetch` snapshot (it subsumes it). Cost: that one restore skips the date; the cloud update
arrives with the next restore.
(d) Crash between T1 and the rows: a stale stored mark, cleared by the next push (equal fingerprint).

### 5.5 Guard in `_restoreScheduledWorkouts`
Right before `await _hive.workoutBox.put(key, merged)` (`:2872`), synchronously:
`SyncFlags.schedUnpushedSwapGuardEnabled && cloudStatus != 'completed' && box.get(key) is Map &&
(isPending(box, date) || touchedSince(date, fetchMark))` -> `continue`: the local row stays byte-identical (no
type, status, template_id, hydration, rest strip, `day_of_week`/`week` heal or `source` stamp; R1-8). The
`templateDeleted` block (`:2766-2781`) still runs first, unchanged.
- No local row -> no guard (R1-3).
- Cloud `completed` keeps the existing merge (spec I6; a swap never involves a completed day).
- `ErrorTelemetry.logEvent('sched_restore_kept_unpushed_swap', message: 'date=$date')` per guarded row.
(e) The plan-bundle restore is not marker-guarded: swapped rows carry a fresh `arranged_at_ms`
(`day_swap_rules.dart:249`), the snapshot wins a week only on a strictly greater stamp
(`snapshotArrangementWinsKeys`), and L1 keeps a local rest row. T8 proves the launch order. When L3 DOES let
another device's newer week win (R2-6), the local swap is discarded but its mark stays: the scheduled
restore then keeps the bundle rows (which are that newer arrangement) instead of overlaying cloud status for
those dates, and the next push sends them and clears the mark. Self-healing in one pass; accepted.

### 5.6 Kill switch
`configBox['disable_sched_unpushed_swap_guard'] = true` -> `SyncFlags.schedUnpushedSwapGuardEnabled` false:
the restore never consults the marker AND Case 2 keeps returning true (byte-identical to main on the restore
and push paths). The writer/clearer keep maintaining the key (invisible).

### 5.7 Deliverables
`SyncFlags.schedUnpushedSwapGuardEnabled` (`sync_flags.dart`); `SchedUnpushedSwaps.resetForUser()` from
`_onUserChanged`; `SimulationService.clearJourneyLocalState` deletes the key; `docs/naming_conventions.md` row;
SoT concept `sched_unpushed_swap_marker` (writer `swapScheduledDays`, clearer `_syncScheduledWorkouts`, reader
`_restoreScheduledWorkouts`, `behavioral_test_path`); `lib/core/services/CLAUDE.md` row;
`docs/architecture/sync.md` restore-merge text; `docs/blast_radius.yaml` checked for the new file; OI-532 to
closed; diagnose doc (FULL template: recurrence of d9b2c5 / e8f4a3).
**Sibling (split, R2-7):** `TemplateService.unscheduleTemplateFromDate` (`template_service.dart:242`) is the
same class through another writer: an unpushed template removal is re-templated by the restore (the cloud row
still carries the template), and a row DELETE is never pushed at all (the push walks existing rows only).
Different semantics (deletion), so it is filed as its own OI with this evidence (`scripts/mint_oi.sh`).
Template ASSIGN is covered today (the restore never overlays a null cloud `template_id`); move/drop are
covered by the terminal arm (e8f4a3).

## 6. Tests (`test/sync/sched_restore_unpushed_swap_test.dart`; real SyncService, `SyncHarness` stub server, real
`SwapService.swapDays` for swaps)
- T1 (bug, red on main): Fri template workout + Sat rest; confirmed push; swap Fri<->Sat with the
  scheduled_workouts write failing; restore with the PRE-swap rows -> Sat keeps workout/exercises/type, Fri
  stays rest with NO `template_id`.
- T2 (not permanent): then a successful push -> stored mark gone; a NEW process view (`resetForUser`) restore
  whose cloud rows show another device's swap-back -> the cloud wins.
- T3: cloud `completed` on a pending date lands.
- T4: a later `upsertScheduled` rewrite of the swapped row keeps the guard while unpushed.
- T5 (fresh device): rows with `arranged_at_ms`, no mark -> cloud wins.
- T6: kill switch -> main's result.
- T7 (push vs swap): a PRIOR mark exists; the stub's `scheduled_workouts` write hook lands a second swap of
  that date mid-flight (in-flight add, rows, mark, in-flight remove, synchronously) -> after the pass the mark
  is KEPT; the next pass pushes the swapped content and clears it.
- T8 (launch order): `restoreWorkoutPlanForTest` with the PRE-swap bundle, then the scheduled restore -> swap
  survives.
- T9 (R1-2/R2-1): fetchMark taken; THEN swap, push succeeds, mark cleared; restore with the pre-swap rows and
  that fetchMark -> guarded. Plus the single-call path: through `_attemptSingleCallRestore` with the stub's
  function reply doing swap+clear inside it -> guarded.
- T10 (R2-2): Case 2 omitted-key on a marked row -> two passes, mark kept both times.
- T11: stale mark, no local row -> cloud row restores.
- T12 (R1-1): restore run from `debugAfterPreMarkForTests` (after T1, before the rows) -> the date reads pending.
- U1-U4 helper units: CAS refuses a newer token and an in-flight date; tokens never reused (same ms, clear,
  clock back); malformed value; `_seq` excluded from `read`.
- Mutations: (a) drop the `continue` -> T1; (b) drop the clear -> T2; (c) clear without the token compare ->
  T7; (d) drop `cloudStatus != 'completed'` -> T3; (e) guard on `arranged_at_ms` -> T5; (f) ignore the switch
  -> T6; (g) drop `touchedSince` -> T9; (h) Case 2 returns true when marked -> T10; (i) drop `is Map` -> T11;
  (j) drop the pre-rows mark -> T12; (k) CAS ignores in-flight -> U1.

## 7. Risks
- A push that NEVER confirms a marked date (orphan template, persistent rejection) keeps local winning for
  that date and re-pushes it each pass. Correct semantics for unpushed local state.
- Gate G1 (`check_sync_hash_skip_atomicity.dart`) flags Supabase writes only; the marker uses `box.put` in
  its own file.
- The key exists with the switch on. Whole-box walkers over `workoutBox.values` with no key filter
  (`export_data.dart:18`, `daily_completion.dart:12`, `workout_repository.dart:810,1053`) tolerate it (a Map
  with no `type`/`date`/`status`), like the skip-index maps; the export lists it as it lists those.

## 8. Review dispositions
| Finding | Sev | Disposition |
|---|---|---|
| R1-1 restore in the gap between rows and marker; stale existingMap across template awaits | P1 | folded: mark before AND after the rows; guard checked synchronously right before the put (5.2, 5.4b, 5.5); T12 |
| R1-2 push clears during the restore's fetch | P2 | folded, then superseded by R2-1's `fetchMark` (5.4c); T9 |
| R1-3 guard without a local row | P2 | folded: `box.get(key) is Map`; T11 |
| R1-4 Case 2 omitted-key fallback returns true | P2 | folded: no clear on that branch; T10 |
| R1-5 mutation (c) vacuous; no push-vs-swap test | P2 | folded: new mutation (c), T7 |
| R1-6 launch order untested | P2 | folded: T8; bundle path reasoning 5.5(e) |
| R1-7 helper already drafted with `prune(box)` | P3 | folded (5.1) |
| R1-8 `continue` drops the dow/week heal + source stamp | P3 | accepted, listed in 5.5 and the diagnose doc |
| R1-9 kill switch leaves the key | P3 | accepted, 7 |
| R2-1 a swap made AND pushed after the restore's fetch is overwritten | P1 | folded: process-local touched counter + `fetchMark` (5.1, 5.4c); T9 incl. single-call path |
| R2-2 Case 2 fix only delays the clear by one pass | P2 | folded: marked rows return false on the omitted-key branch (5.3); T10 two passes |
| R2-3 T7/T9/T12 unbuildable or toothless as written | P2 | folded: seam `debugAfterPreMarkForTests`, T7 with a prior mark, T9 through `_attemptSingleCallRestore` |
| R2-4 CAS(T1) between rows and T2 | P3 | folded: in-flight set (5.1, 5.4a); U1/mutation k |
| R2-5 token ABA | P3 | folded: persisted `_seq` |
| R2-6 L3 discard leaves a mark | P3 | accepted, self-heals in one push (5.5e) |
| R2-7 logEvent signature; walker claim false; missing docs; sibling writers | P3 | folded (5.5, 5.7, 7); template unassign split to its own OI |
| R3-1 T9 single-call variant unbuildable (no function responder in the stub) | P2 | folded: stub gains an awaited `functionResponders` hook; T9b asserts the singlecall path ran |
| R3-2 T7/T9 need an AWAITED write hook | P2 | folded: stub gains `beforeWrite[table]` (awaited before the reply) |
| R3-3 mutation (j) ambiguous | P3 | folded: (j) removes the whole `beginSwap` call |
| R3-4 stuck in-flight if `beginSwap` throws; endSwap after the fan-out | P3 | folded: `beginSwap` inside try/finally `endSwap`; T2 mark + `endSwap` before the sync fan-out |
| R3-5 `resetForUser` zeroed the counter | P3 | folded: counter never reset; `resetForUser` first in `_onUserChanged` |
| R3-6 late clear/prune on a closed box | P3 | folded: try/catch + `recordNonFatal`; skipped when the pass aborted |
| R3-7 test seam takes the mark too late with preFetched | P3 | folded: `restoreScheduledWorkoutsForTest(fetchMark:)`; debug assert preFetched implies fetchMark |

Converged after round 3 (narrow).
