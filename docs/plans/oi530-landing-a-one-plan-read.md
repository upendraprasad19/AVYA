# OI-530 Landing A: a restore reads the plan bundle once

Status: plan, draft 1 of Landing A as its own unit (split out of `oi530-per-day-schedule-sync.md` after that
plan's review rounds 1-2 kept finding material issues in Landings B/C, CLAUDE.md §4.12.1: ship the smallest
converged piece). Landing A was reviewed inside rounds 1 and 2 (findings 8 of round 1; 6 and 8 of round 2), all
folded below. Tier L (Edge Function + restore path). Execution: inline, this worktree, never switched.
Base `main` `bde20648`. Founder go for the change itself: 2026-11-28 ("we will do this as well"); the EF deploy
needs its own go (§4.3).

## 1. What it fixes (measured)
`user_progress.plan_json` is 140-927 KB per account today (2.28 MB at two years). A sign-in restore sends it
more than once:
- **Single-call restore** (`restore-user-snapshot`, the normal path): `READS` in
  `supabase/functions/restore-user-snapshot/restore_reads.ts` reads `user_progress select("*")` (:54-55, key
  `user_progress`, carries `plan_json`) AND `user_progress select("plan_json")` (:68-70, key `workout_plan`).
  Both go into the response, so the bundle crosses the wire twice (plus the third projection `freezes`, :113-119,
  which does not carry it).
- **Legacy restore** (fallback when the single call faults, and `restoreFromCloud`): `_restoreWorkoutPlan(userId)`
  and `_restoreUserProgress(userId)` each do their own network `user_progress` read
  (`sync_service.dart:1941` + `:1958` in `restoreFromCloud`; `:2243` + `:2257` in `restoreFromCloudForUser`
  step A).
The per-launch `restoreLightweightAlways` already reads once (`:1786-1798`); it is out of scope (Landings B/C
make it incremental).

Readers of what changes (round 1 and round 2 grep, both confirmed): the client reads the single-call
`user_progress` row only through `_restoreUserProgress(preFetched: row('user_progress'))` (`sync_service.dart:
2448`), which copies the row and removes `plan_json` before use (`sync/sync_profile.dart:1105-1124`); the
client reads `workout_plan` only through `_restoreWorkoutPlan(preFetched: row('workout_plan'))` (`:2462`),
which reads `rows.first['plan_json']` (`sync_workout.dart:1556`). `_kSingleCallBundleKeys` (`sync_service.dart:
~2640`) requires the key `workout_plan` to be present (H-2). No other reader of either.

## 2. Edge Function change
- `READS` stays exactly as it is (29 tuples, same order: the "ONE source of key ORDER and SET" contract and the
  golden key-order test hold).
- `assembleTables(..., opts)` gains `opts.singlePlanRead: boolean`. When true:
  - the `workout_plan` thunk is NOT called (no request built); `run()` returns a placeholder for that slot, so
    `tables` keeps the key at its original position (round 2 #6: no key reordering);
  - after `tables` is built, the pure `deriveWorkoutPlan(tables)` sets `tables.workout_plan` = `[]` when
    `user_progress` is `[]`/absent, else `[{ plan_json: row.plan_json ?? null }]` (exactly what
    `select("plan_json").limit(1)` returns live), and deletes `plan_json` from that `user_progress` row;
  - `timings` has no `workout_plan_ms` (the timing line omits an unfinished read already, :216-235 tests).
- `index.ts` passes `singlePlanRead = Deno.env.get("RESTORE_SINGLE_PLAN_READ_OFF") !== "true"`, read per request
  (rollback without a redeploy: set the secret to exactly `true` and the next request runs today's code path
  verbatim). The deploy rollback is the saved payload in `backups/edge_function_payloads/restore-user-snapshot/`.
- Header comments updated: "The three user_progress reads stay three (freezes projection parity, H-1)" becomes
  "two by default (`*` and the freezes projection; `workout_plan` is derived from `*`), three with the rollback
  switch".

## 3. Client change (legacy paths only)
In `restoreFromCloud` and `restoreFromCloudForUser` step A, one strict fetch shared by both ops:
```dart
final progressRows = _fetchUserProgressRowStrict(userId); // a Future; throws on failure
await _safeRestoreOp('workout_plan',
    progressRows.then((r) => _restoreWorkoutPlan(userId, preFetched: r)));      // restoreFromCloud: awaited first (APK #12.9)
... _safeRestoreOp('user_progress',
    progressRows.then((r) => _restoreUserProgress(userId, preFetched: r))) ...  // inside the existing Future.wait
```
- `_fetchUserProgressRowStrict` = the same bare `.select().eq('user_id').limit(1)` with NO catch, so a fetch
  failure fails BOTH ops through `_safeRestoreOp`, which reports `restore_workout_plan` and
  `restore_user_progress` (`'restore_$label'`, `sync_service.dart:3037`), both in
  `kStreakCriticalRestoreOpTypes` (`sync/sync_restore_failure_collector.dart:32-41`). The streak-settled marker
  therefore stays closed on a failed fetch exactly as today (round 2 #8: the lightweight helper
  `_fetchUserProgressRowForRestore` swallows to `[]`, which here would have settled the marker over an
  unrestored progress row; it is deliberately NOT reused).
- Ordering kept: in `restoreFromCloud` `_restoreWorkoutPlan` is still awaited before the `Future.wait` that holds
  `_restoreScheduledWorkouts` (APK #12.9); in step A both ops sit in the same `Future.wait` as today and the
  step-B overlay still runs after step A.
- Sharing one row list is safe: `_restoreUserProgress` copies before `remove` (`Map.from(rows.first)`,
  `sync_profile.dart:1105`), `_restoreWorkoutPlan` only reads (round 2 #8).
- Switch: the existing `disable_restore_single_plan_fetch` (`kDisableRestoreSinglePlanFetchKey`,
  `sync_service.dart:~1720`), whose meaning is "each op does its own `user_progress` read". ON = today's two
  calls verbatim. The single-call path and `restoreLightweightAlways` are untouched by the client change.

## 4. Tests (each mutated once, rule 21)
- Deno `restore_reads_test.ts`:
  - rollback mode (`singlePlanRead: false`) = the existing golden, tables and calls, byte for byte (unchanged
    tests, now passing the flag);
  - default mode: tables = the golden with exactly two changes (`user_progress[0]` without `plan_json`;
    `workout_plan` = `[{plan_json: <that value>}]`), JSON-stringified in the golden's key order; calls = the
    golden's minus the one `select("plan_json")` chain on `user_progress`;
  - `deriveWorkoutPlan` unit cases: no row -> `[]`; row with `plan_json: null` -> `[{plan_json: null}]`; row
    without the key -> `[{plan_json: null}]`; other row keys untouched;
  - the timing line in default mode has no `workout_plan_ms`.
  - Mutations: call the thunk anyway (calls test reddens); skip the strip (tables test reddens); derive from the
    wrong table (tables test reddens).
- Dart (stub server, `test/sync/`): for each legacy path, count `user_progress` GETs = 1 (switch off) and 2
  (switch on); a stub 500 on that GET reports both `restore_workout_plan` and `restore_user_progress` and leaves
  the restore-settled marker unset; `_restoreWorkoutPlan`'s write lands before `_restoreScheduledWorkouts`'s
  (existing ordering test re-run). Mutation: swallow the fetch error -> the marker test reddens.
- Existing suites that must stay green: `paged_reads_test.ts`, `restore_user_snapshot_paged_reads_wiring_test.
  dart`, `restore_completeness_test.dart`, the single-call bundle key tests.

## 5. Process
§4.12.8 gate loop + CI before the round-3 review of the diff; B-pass before the merge; founder go before the EF
deploy (host-shell deploy, `deno check --node-modules-dir=none`, smoke with a real user token per the deploy
skill). Order: deploy the EF first (old clients are unaffected: same keys, same `workout_plan` shape), merge the
client half after. Not a bug fix: no diagnose doc; SoT registry `restore_user_snapshot_paged_reads` row and
`supabase/functions/CLAUDE.md` row updated (the "29 reads" wording); project retrospective at the end.

## 6. Review round 3 (narrow, on this file): converged, P2 folds
1. The strip never mutates the row in place (the fake returns shared row objects; `freezes` and
   `user_progress[0]` can be one object): read `plan_json`, build `{...row}`, delete from the copy, replace
   `tables.user_progress[0]`. A test pins that `freezes` is unchanged.
2. `assembleTables`'s `opts.singlePlanRead` defaults to `false` (today's behaviour), so every existing test runs
   the rollback mode unchanged; only `index.ts` passes the env-derived value; default-mode tests pass `true`.
3. The existing timing-line test stays in rollback mode; the new default-mode test asserts no `workout_plan_ms`.
4. Records: recompute `docs/sot_registry.yaml` `restore_reads.ts` `line_range` from anchors; reword the "29
   reads" sentence in `supabase/functions/CLAUDE.md` and the restore_reads.ts header.
5. Stated semantics change: one failed shared GET now marks BOTH `restore_workout_plan` and
   `restore_user_progress` (fail-closed, intended); a fetch failure's telemetry reason becomes the
   `_safeRestoreOp` one instead of `sync_service_if_17`.
6. `kDisableRestoreSinglePlanFetchKey`'s doc comment covers the legacy paths too; the switch is read once per
   restore call.
7. Tests: behavioural on `restoreFromCloudForUser` through `SyncHarness` (next to
   `restore_lightweight_single_plan_fetch_test.dart`, T7-style `readReplies['user_progress']` 500); a
   source-grep pin for `restoreFromCloud` (reachable only from `checkAndSync` with empty Hive, no harness).
