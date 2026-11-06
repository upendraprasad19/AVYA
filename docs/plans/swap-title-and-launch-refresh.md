# Plan — OI-284: a completed non-template row's title follows its own performed log (v3)

Status: **v3 — CONVERGED for OI-284 (round 1 on v1, round 2 on v2: U2 converged); OI-294 / U1 SPLIT OUT by round 2
(§4.12.1) and re-filed on the board.** Review rounds count only this lineage.
Founder decisions (chat): joint OI-284 + OI-294 plan (Option A, 2026-10-03); "let's plan this and start on this"
(2026-10-04); live repair + device check are the founder's, later.
Branch/worktree: `swap-title-and-launch-refresh` (base `origin/main` 4259d0ed). Tier **L** (sync restore).
Blast radius: measured at implementation with `scripts/blast_radius_from_diff.dart`. Round 1 measured every file
below as `account`; it becomes `platform` only if `lib/core/services/sync/sync_workout.dart` is edited — **v2 does not
edit it** (the heal lives in `SyncService`'s public restore entry, not inside `_restoreWorkoutPlan`), so expected
**account**; the review record carries `bpass` anyway if the measurement says otherwise. Execution mode (§4.12.7):
**inline, one coordinator**; reviewers and the B-pass are fresh subagents (≤4 at once). No migration, no Edge
Function, no live write.

## 0. What round 1 changed (all verified in code before accepting)

v1 bumped `restoreCompletedTick` from `restoreLightweightAlways`. Verified wrong on three counts:
1. **That tick also gates streak decay** (`workout_repository.dart:244-248`, `day_rollover_service.dart:174`):
   persisting freeze consumption only when `restoreCompletedTick > 0`, on the premise that a restore confirmed the
   completion history. The lightweight path restores no completions, so v1 would have opened the gate with history
   unrestored → spurious freeze consumption in exactly the swap scenario. v2 never touches that tick.
2. **OI-294's premise was half wrong.** Splash routes EVERY authenticated cold start to `/restoring`
   (`splash_screen.dart:312`); for a returning user the screen starts a FULL `restoreFromCloudForUser()` in the
   background and, only `if (result.succeeded)`, runs `_healAfterRestoreInBackground` which bumps the tick
   (`restoring_screen.dart:327-334`, `heal_after_restore.dart:74`). So a normal cold start already refreshes Home
   after a successful restore. The real gap: a restore that ends `failed` or `cancelled` AFTER writing rows
   (steps write incrementally; the plan merge is the first) bumps nothing — the founder's outage morning
   (`restore_started` 05:48Z and 06:24Z without `restore_completed`). Foreground restores (fresh install,
   `disable_bg_restore`) await the restore before navigating home, so home builds fresh providers.
3. **The heal hook was wrong:** `heal_after_restore` runs only in the background branch on success.

## 1. Observation and evidence (founder, 2026-10-01; live re-checked 2026-10-04)

Web swap Oct 1 ↔ Oct 2; web completed Oct 1 as Pull + Core (log `PULL + CORE`). Android: Train row title stayed
"Push + Core"; Home Today widget old name; completed card + calendar view correct (they read the LOG).

- O (live SQL, SELECT-only, project `dedsavbjuwgarrhphgnl`, user d7a67a37…): `scheduled_workouts` Oct 1/Oct 2
  `completed`, `template_id` NULL for every row Sep 29–Oct 4; cloud `plan_json` Oct 1 = "Pull + Core" `completed`,
  Oct 2 = "Push + Core" `planned` (correct content for Oct 2 after the swap; its status is simply behind);
  `scheduled_workouts` has no title column (`backups/live_schema_columns.json`), `workout_schedule_completions` does.
- C: the phone's completed row kept its title because `mergeScheduleEntry` returns a local `completed` row unchanged
  (`lib/core/services/plan_integrity_reconciler.dart:104-106`) and the status overlay spreads `...existingMap`,
  writing a title only from a cloud TEMPLATE (`lib/core/services/sync/sync_workout.dart:2562-2589`).
- **Unproven, stated:** which `source` the phone's `wlog_2026-10-01` carries (`cloud_restore` real name, no source =
  written locally, or `cloud_restore_completion` = synthetic from the completions name, which would say "Push +
  Core"). The heal repairs the first two; if the phone's slot is synthetic it will not fire and the optional live
  repair (founder's, later) is the path. The founder's device check settles which.

## 2. Bug-history (§4.1.5)

Recurrences: `a7d3f1`/`d9b2c5` (restore overwrite), `b6e1c8` (hybrid rows), `b3c9d4` (restore tick wiring, class
2.58), `f1c6b4`, `d5a1e7`, `e2b9d4`; classes 2.30, 2.51, 2.58, 2.74. Full diagnose template. Sweep BEFORE coding
(`git grep`, whole repo): `restoreFromCloudForUser`, `restoreFromCloud(`, `restoreCompletedTick`,
`bumpRestoreCompleted`, `_healAfterRestoreInBackground`, `markCompleted(`, `'Chat Workout'`, `completed_via`,
`wlog_` writers/readers; tests that source-grep `restoreFromCloudForUser` slices (round 1: `_methodSlice` /
`_extractMethod` helpers, `sync_service_public_api_snapshot_test.dart`, `restore_plan_json_authoritative_test.dart`,
`restoring_screen*` tests) — REPOINT, never loosen.

## 3. Design

### (OI-294 / former U1 — NOT in this batch)

Round 2 verified that a refresh bumped on a returned `!result.succeeded` is nearly unreachable: `_safeRestoreOp` swallows
every per-op error and timeout (`sync_service.dart:2681-2714`), the other `failed` returns are zero-write, and
`cancelInflightRestore` is called only for new/mid-onboarding users (`restoring_screen.dart:143,223`). The founder's
`restore_started`-without-`restore_completed` mornings were a restore that never RETURNED. OI-294 is rewritten on the
board with its design constraints (separate tick, step-boundary/`finally` refresh, owner-change guard, one generic
refresh listenable shared with Phase 1b, a real test seam). `restoreCompletedTick` is not touched by this batch.

### U2 — OI-284: a completed non-template row's title follows its own performed log

`lib/core/services/completed_title_healer.dart` — `CompletedTitleHealer.run()`, reading only local Hive (no network,
no bundle, no stash). Hooks (ONE place per path, all inside `SyncService`, none in a UI part file):
(i) the same `restoreFromCloudForUser()` wrapper — `if (r.succeeded) await CompletedTitleHealer.run()` BEFORE it
returns, so on the bg branch the heal runs before the existing `heal_after_restore` bump (which then refreshes the
UI) and on the foreground branch before home mounts; this covers multi-step, single-call and the ownership-fix
re-restore (`restoring_screen.dart:375`); (ii) the tail of `restoreFromCloud(userId)` (the no-local-logs
`_restoreIfNeeded` path, right after its `Future.wait` of logs/overlay); it triggers no UI refresh when it heals —
accepted: that path runs only when the device holds no local logs (a reinstall), before the tabs have read anything.
A failed or cancelled restore does NOT heal (stated; the heal is pure/idempotent and runs at the next success). `restoreLightweightAlways` is NOT hooked:
it restores no logs and every cold start also runs the full restore (§0.2). The `*ForSyncDomain` entry points are
flag-gated OFF (`SyncFlags.useDomainFor`, default false) and `sync_realtime.dart` touches no schedule/wlog rows —
neither is hooked; a code comment + the SoT row tell whoever flips them (or OI-279's resume-pull) to call
`CompletedTitleHealer.run()` after restoring logs.

| Guard (all must hold, else the row is left untouched, silently) | Why (verified) |
|---|---|
| `status == 'completed'` | planned rows belong to the merge |
| `template_id` absent/null | template rows are rewritten by the overlay from the cloud template (`sync_workout.dart:2589`) and converge on their own; a heal would fight it |
| `type != 'logged'` | `cloud_restore_completion` rows take their name from the completions table, not a log (`sync_workout.dart:1097`) — same divergence class, deliberately out of scope |
| `wlog_<date>` is a Map, `type == 'workout_log'`, `source != 'cloud_restore_completion'` | that source is synthetic (copies the completions name, circular). `source: 'cloud_restore'` wlogs hold REAL cloud names (`sync_workout.dart:826-841`) and ARE eligible |
| normalised wlog name (trim, lower-case) is non-empty and not in `kPlaceholderWorkoutNames` = {`workout`, `chat workout`} | `conversational_log_handler.dart:263-265` hard-codes "Chat Workout"; `?? 'Workout'` fallbacks at `tool_dispatcher.dart:469`, `ai_coach_provider.dart:405`, `train_provider.dart:1931`, `simulation_service.dart:482`, `sync_workout.dart:833` |
| normalised wlog name ≠ normalised row name | case-only variants (Train writes upper-case log names, `train_provider.dart:647/1931`; 16 founder dates) are equal ⇒ no write |

On a hit: set ONLY `workout_name` = the wlog's name (its own casing), via a fresh `HiveService.instance.workoutBox`
reference taken per iteration (never held across an `await`), re-read + `put` with no `await` between (atomic
against other Dart writers: single isolate; Hive 2.2.3 `BoxImpl.put` → `_writeFrames` calls `keystore.beginTransaction`
synchronously before its first await, and `GuardedBox.put` asserts ownership first); the whole pass in its own `try/catch` (a `HiveOwnershipException` after an
account switch is swallowed and counted as 0, never reported as a restore failure); one
`unawaited(ErrorTelemetry.logEvent('completed_title_healed', message: 'count=N'))` when N>0 (no names — PII; unawaited
so it never delays `RestoreResult`/navigation, like `restore_started`/`restore_completed`).

Stated semantics (each has a test):
- **Row title = the title the completed card/receipt shows (the single local `wlog_<date>` slot).** A date completed
  twice under different names leaves two cloud `workout_logs` rows; restore keeps the OLDEST per date
  (`_restoreWorkoutLogs` `orderBy created_at`, local-wins, `sync_workout.dart:790-841`), the card shows it, and the
  heal makes the row agree with the card. Whether that pick should be the newest is a separate restore question →
  new OI (minted before ship).
- Never touches status, completion metadata, markers/stamps, exercises, `workout_focus`, `type`, `week_*`; mints
  nothing. A healed row's exercise list is whatever it was (the completed card reads the logs); the Home insight
  would show the new title with the old row's exercise count — an existing row/log inconsistency class, not widened.
- `completeWorkout` can date a session today while naming a missed past day (`train_provider.dart:1829-1850`):
  today's completed row takes that name (what was performed). Intended.
- Casing: the stored name is the log's own casing (often upper-case from Train). The Home card, week strip and Train
  row upper-case it for display; the Home insight, day detail sheet and hold chip render it raw (reviewer-verified).
  Accepted explicitly — cosmetic; the alternative (title-casing) would invent a casing rule.
- Cloud completions name: `_syncScheduleCompletions` (`sync_workout.dart:685`) copies the ROW's name, so it follows
  at the NEXT normal `syncWorkoutData` (the heal itself fires no sync); NOT changed to read the wlog (that would push
  "Chat Workout" for chat days).
- No cross-device oscillation: the heal is a pure function of the device's own wlog and each device pushes only on
  fingerprint change. A restore writer that re-puts a stale title after the heal is re-healed at the next restore.
- Provenance: `kPlaceholderWorkoutNames` lives in `workout_write_service.dart` next to `markCompleted`;
  `conversational_log_handler.dart` imports it for its literal. A guard test scans the ENCLOSING FUNCTION BODY of each of the 5 production `markCompleted(` call sites
  (`tool_dispatcher.dart:469-472` and `ai_coach_provider.dart:405-406` bind `?? 'Workout'` to a local first;
  `train_provider.dart:1931`, `simulation_service.dart:482`, `conversational_log_handler.dart:265` are inline) and
  requires every string literal feeding `workoutName` to be in the set. It cannot see COMPUTED names
  (`state.workoutDay?.name` can be 'REST DAY' / 'NO PLAN', `train_provider.dart:841-842/860`) — stated in the guard's
  header; those would heal to the wlog's name, which is what was recorded.
- Kill switch `disable_completed_title_heal` (opt-out, `SyncFlags`-style getter; flag-closed ⇒ no heal ⇒ byte-identical).

## 4. Not in this batch (on the OI board)

OI-294 (rewritten: needs a step-boundary/`finally` refresh on its own tick, an owner-change guard, a shared refresh
listenable with Phase 1b, and a real harness seam) · OI-295 ref-less writers · OI-293 restore observability · OI-292
morning-alert · OI-285 merge lock · OI-286 notice · OI-287 allowance · OI-288 residual gate · OI-289 nutrition probe ·
OI-290 week_number · OI-261 displaced · OI-302 restore picks the oldest cloud `workout_logs` row for a
double-completed date · OI-279/280/281 (resilient-client session; the heal note is already on OI-279, item 7).

## 5. Kill switch (§4.6)

One flag, `disable_completed_title_heal`, default-LIVE (opt-out, repo-standard like `disable_bg_restore`): the
founder's device check can only run on an APK built from `main` after the merge, so a closed-by-default flag would
ship the fix dark. §4.12.4 (ship-dark) does not apply: full ×2 + a self-triggered `/code-review` before the merge.
The old path stays behind the flag until the founder's device check; its deletion is an OI **minted with
`scripts/mint_oi.sh` BEFORE the merge** and cited in the commit (§4.6.4) — **requires the founder's ratification
(§8)**. Names appended to `docs/naming_conventions.md` (`CompletedTitleHealer`, `kPlaceholderWorkoutNames`,
`completed_title_healed`, the flag).

## 6. Tests (rule 21; each MUTATED once, `grep -c` confirms the mutation applied, red count recorded)

Real Hive session pattern of `test/contracts/ai_insight_follows_today_row_test.dart`. The restore hooks are tested
through a `@visibleForTesting` seam on the hook (a pure "should heal for this result" decision + the heal call), NOT
through `restoreFromCloudForUser` in `SyncHarness`: round 2 verified that harness returns `failed('No authenticated
user')` at `sync_service.dart:1886` because its `SupabaseClient` has no session.
1. Heal, founder fixture: completed non-template "Push + Core" + `wlog` "PULL + CORE" (once with `source:
   'cloud_restore'`, once with no source) ⇒ row name "PULL + CORE", map minus `workout_name` byte-identical; second
   run 0 writes (counted via `box.watch`).
2. Guards, one test each, 0 writes: placeholder names; `cloud_restore_completion` wlog; template row; planned row;
   `logged` type; missing wlog; case-only difference.
3. Stale re-put after the heal: a restore writer re-puts the stale title, the next run re-heals; the assertion is on
   the re-healed value (non-vacuous).
4. Hook decision: success ⇒ heal runs; failed / cancelled ⇒ it does not; flag-closed ⇒ it does not; and the heal
   leaves `restoreCompletedTick` untouched (the decay gate is not opened).
5. Hook placement parity: every `RestoreResult.success()` / single-call success exit of `restoreFromCloudForUser` and
   the tail of `restoreFromCloud` reaches the heal; every production restore entry (`restoring_screen.dart:114,375`,
   `_restoreIfNeeded`) goes through one of them.
6. Account switch: the pass swallows a `HiveOwnershipException`/`StateError` and returns 0 (no restore-failure report).
7. Placeholder-set guard: scan the enclosing function body of each of the 5 production `markCompleted(` sites.
8. A double-completed date (two cloud names): the heal follows the single local slot, equal to what the completed
   card reads.
Mutations: drop each guard row; always/never heal in the decision; drop the flag check; drop the placeholder set;
heal before the restore steps (test 5 reddens).

## 7. Order, gates, artifacts

1. Plan review ×2 DONE: round 1 (v1, three reviewers) and round 2 (v2, two reviewers; U2 converged, U1 split).
   Record `docs/plan-reviews/swap-title-and-launch-refresh.md`: `review_rounds: 2`, `ground_truth_verified: true`,
   `verdict: converged`, `blast_radius` as measured (round 2: `account`; `bpass` only if ≥platform).
2. Tests first (watch RED), then the heal + hooks. 3. Full gate loop after the LAST edit (§4.12.8): `flutter analyze
   lib/`, `TZ=Asia/Kolkata flutter test`, `sh scripts/pre-commit.sh`. 4. Diagnose-doc (OI-284, full template,
   recurrence) with `closes-diagnose:`. **No `closes-oi: OI-284`** — the phone's wlog slot may be synthetic (§1
   "Unproven"), so OI-284 stays OPEN, re-worded "fix merged, closes after the founder's device check". 5. SoT registry
   (`workout_completion_status`; repoint `sync_service.dart` line ranges if shifted), `lib/core/services/CLAUDE.md`,
   `lib/features/home/CLAUDE.md`, `docs/naming_conventions.md`, bug-class entry. 6. No closure ledger (1 unit).
   7. Self-triggered `/code-review` before the `--no-ff` merge. 8. Commit/push/PR/merge only on the founder's ask; no
   APK/AAB without it.

## 8. Needs YOUR decision / authorization

1. **Ratify the old-path schedule:** the one kill switch stays until your device check, then a tracked OI (minted
   before merge) deletes the old path — yes/no.
2. **Scope change from what you asked:** OI-294 is NOT in this batch. Round 2 showed that, once corrected, it is
   almost unreachable as designed; it needs its own plan (OI-294 on the board has the constraints). OK?
3. Optional live repair of the Oct 1/2 `plan_json` rows (prod write, its own go) — yours, later. After this ships
   the phone's row should self-heal at its next successful restore IF its wlog slot holds the real name.
4. Nothing is committed, pushed, merged or built without your explicit ask.
