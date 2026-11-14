# Plan — streak decay persists after the restore settles, per user; a stale cloud row stops overwriting freeze state (v5)

Status: **v5 — converged** (round 1 on v1, round 2 on v2, round 3 on v3, round 4 delta-only on v4: ten context-blind reviewers in
all; **round 3: Unit 1 CONVERGED on mechanism, process slice CONVERGED, Unit 2 had ONE P1 — a test-observability gap (`syncFreezes` cannot
run under `SyncHarness`) with a one-line fix; round 4: two P1s, BOTH in additions I made in v4 (the optional symmetric grant carry, and the
owner guard's effect on two existing test files); no P0 anywhere in rounds 2-4**). v5 resolves both with the reviewer's OWN prescriptions and
ADDS NO NEW DESIGN: the symmetric carry is DROPPED (v5 is a net reduction), and the two fixture files are listed. No round 5: a round that
reviews a deletion plus a fixture list is mechanical (§4.12.8 `mechanical_only`), and the ≥platform B-pass reviews the implemented code. The
plan-review record says exactly this (`review_rounds: 4`). Every finding below was verified in code or live before being accepted. Founder request (chat, 2026-10-06):
"check and investigate" the Home streak (16 days / 2 freezes on the founder's own account `upendra`), then "ya proceed".
Branch/worktree: `claude/avya-streak-data-check-b506de` (worktree `food-logging-observations-126ab3`). Tier **L** (sync restore +
streak/freeze ledger). Blast radius: **platform** (`sync_service.dart` and `user_repository.dart` are platform; confirmed by a
`blast_radius_from_diff.dart -` stdin run). Edited files and their tiers: `user_repository.dart`, `sync_service.dart`,
`sync/sync_profile.dart`, `sync/sync_restore_completeness.dart`, new part file `sync/sync_restore_failure_collector.dart`
(under the `sync/**` platform glob) = platform; `auth_session_bootstrapper.dart`, `day_rollover_service.dart`,
`restoring/heal_after_restore.dart` = account; `workout_repository.dart`, `home_screen.dart` = feature. Platform demands
`regression_test`, `behavioral_test_path`, `code_review_b_pass`, `feature_flag` (the two kill switches). Execution mode
(§4.12.7): **inline, one coordinator**, Unit 2 first then Unit 1; reviewers and the B-pass are fresh Sonnet subagents (≤4 at once).
No migration, no Edge Function, no live write.

**Why the units stay together, and the split rule actually applied (§4.12.1).** Unit 2 alone does NOT fix the founder's symptom
(the chip showing 2 while the streak needs both freezes) — Unit 1 does; and **Unit 1 must never ship without Unit 2** (without
it, `restoreLightweightAlways` — a different zone, run on every cold start — can overwrite a just-persisted debit with the stale
cloud count; reviewer round 2). v2's header said "a P1 in Unit 1 splits it out"; round 2's single Unit-1 P1 was a missing
behavioral seam (the marker-setting wrapper was covered only by source pins), not a design defect, and every other finding is a
known cheap fix — splitting would have shipped the half that does not fix the report. **Round 3 outcome: Unit 1 has no P0/P1
(mechanism confirmed against the code by a context-blind reviewer), so it is NOT split.** The one Unit 2 P1 is fixed in place.
(Had Unit 1 been split, F1/F2/F5 would have left this batch's closure ledger and stayed on the OI board, the OI-294 precedent.)
**Liveness, stated up front (round-3 P2-3):** Unit 1 withholds the persisted debit for the whole process whenever ANY of seven
streak-critical restore ops REPORTED a failure (a 57014, a 45 s ceiling, a malformed row); the pre-fix tick was bumped on
`result.succeeded` regardless. On a bad-backend morning the founder's original symptom (chip 2, streak needs both) therefore recurs
until the next cold start whose restore settles cleanly (or a midnight/resume reckon after that). The failing op is already named in
`client_errors` by `_reportSyncFailure` (that is the only telemetry such a morning gets; the new LOW event is best-effort).

## 0. Observation and evidence

Founder, 2026-10-06 ~06:45 IST, phone: Home shows **streak 16, 2 freezes**. Live SQL (SELECT only, project
`dedsavbjuwgarrhphgnl`, user `d7a67a37…`), 06:50 IST; every row below re-verified by a reviewer:

- `user_progress`: `current_streak_days=16`, `streak_freezes_available=2`, `streak_freezes_used_dates={2026-09-16,
  2026-09-25}`, `streak_freezes_last_refill=2026-10-05`, `streak_freezes_first_pro_grant_done=true`, `last_workout_date=2026-10-02`,
  `streak_progress_version=121`, `updated_at` 2026-10-06 01:16:44 UTC (= the 06:46:44 IST refill push). Active yearly PRO since 2026-09-14.
- `scheduled_workouts`: 16 completed workout days 09-14…10-02 (09-25 planned = missed, covered by a spent freeze);
  **10-03 (Sat) and 10-05 (Mon) are `planned` with no `workout_logs` row**; 10-04 rest; 10-06 (today) planned.
- Home streak = `StreakNotifier.build` → `WorkoutRepository.currentStreak()` (`home_provider.dart:242-265`), a READ-ONLY walk
  that SIMULATES freeze spending: 16 only holds because 10-03 and 10-05 are counted as covered by two simulated freezes.
  The chip (`StreakFreezeNotifier`, `home_provider.dart:274-306`) shows the PERSISTED `streak_freezes_available` = 2.
  Truth = streak 16 with **0** freezes in reserve; skip today and the display falls to 0 tomorrow (reviewer C re-ran
  `_calculateStreak` on the live schedule: 16, available 2→0, `used_dates += {10-05,10-03}`).
- 2026-10-06 telemetry: `restore_started` 06:45:38 → `hive_session_opened` 06:46:20 → refill 06:46:25 → `restore_completed`
  06:48:26 (`total_ms=127281`). The cloud row above (available still 2, `used_dates` unchanged after the 06:46:44 push) is the
  evidence that no debit persisted; a missing `streak_freeze_consume_done` event is NOT used as evidence (LOW-priority events are
  dropped under client cooldown, `error_telemetry.dart:327,396`; the 09-21 `refill_done` is a live example of a dropped one).
  **Live F3 signature, found in round 4's follow-up (same read-only SELECT):** `streak_freeze_refill_done before=1 after=2
  monday=2026-10-05` at 06:46:25.07, then `streak_freeze_refill_check monday=2026-10-05 lastRefill=2026-09-28 willRefill=true` at
  06:46:26.68 — `last_refill` was back at the STALE cloud value 1.6 s after the refill stamped it; only at 06:48:25 does a check read
  `lastRefill=2026-10-05 willRefill=false`. (The visible loss was zero — a second refill from the stale `available=1` lands on 2 again — but
  the revert is the §0 F3 mechanism observed on the morning of the symptom; the 10-01 `refill_check lastRefill=2026-09-21` after the 09-28
  refill is the earlier instance.) **Consistent-with for Unit 1:** in 06:45-06:49 IST the ONLY failure rows are the two non-critical push
  timeouts above — no `restore_<critical op>` failure rows — and the restore ended `status=success`, so the Unit 1 marker would have settled
  and persisted the two debits on that morning (consistent-with, not proof: failure rows can be dropped under cooldown).
  **Timestamp caveat (round 3):** on the device `hive_session_opened` (`hive_user_session.dart:296`, inside `openForUser`) is emitted
  BEFORE the core's `restore_started` (`sync_service.dart:1903` → `:1919`), so server-receipt order in `client_errors` is delivery skew
  of fire-and-forget posts, not on-device order; only `total_ms=127281` is a measured duration.

### Findings

| # | Finding | Evidence | Confidence |
|---|---|---|---|
| F1 | A **cold start** never persists the idle-day freeze debit. The D2 reckon is gated on `restoreCompletedTick > 0`; for a returning user `runRolloverNow` (`restoring_screen.dart:322`) is awaited BEFORE the restore's `.then(heal)` is attached (`:332-334`), so the tick is 0 at that rollover even if the restore finished instantly; the only tick writer is `heal_after_restore.dart:74`; nothing re-runs the reckon after it. Three other triggers reckon once the tick is > 0: `completeWorkout` (`train_provider.dart:1950`), a resume across midnight (`day_rollover_service.dart:67-69`), the foreground midnight timer (`:314-329`), so "never persists" is exact for once-a-day cold-start usage (the founder's phone), not every session | code (reviewer A re-traced every caller; `runRolloverNow` is called only at `restoring_screen.dart:322,533` + dev panel); the cloud row above | code-proven; "ran gated" on 10-06 inferred from timing + the unchanged cloud row (the phone's Hive was not read) |
| F2 | The gate is a PROCESS-lifetime counter, not per user (`sync_service.dart:1844`; `_onUserChanged` `:187` never resets it); after an account switch a tick > 0 can be inherited and the reckon persists against the new user's PRE-restore local rows | 2026-09-17: `hive_session_closed userId=32819619` 07:47:37.7 → `auth_signed_in method=email d7a67a37` 07:47:44.1 → `streak_freeze_consume_done newly=2026-09-16` 07:47:44.20, 0.39 s BEFORE `restore_started` 07:47:44.59; cloud shows 09-16 completed (log 08:59 IST that day) yet 09-16 sits in the permanent `used_dates` ledger and a freeze was lost. The device swaps accounts routinely (09-26 07:12-07:13: this user's rows carry REST calls for another account `user_id=eq.32dbc86d…` and `queued sync_user_progress belongs to a different account`) | sequence high; "inherited tick > 0" is CONSISTENT WITH, not proven (no `client_errors` rows exist for the prior account); both guards cover either explanation |
| F3 | A full restore overwrites local freeze state with a STALE cloud row. `_restoreUserProgress` does `SELECT *` and `mergeCloudProgress` is cloud-non-null-wins for every key outside `monotonicProgressFields`, which includes `streak_freezes_available`, `streak_freezes_last_refill`, `streak_freezes_first_pro_grant_done` (same key names local and cloud). **Production restore order is `user_progress` THEN `freezes`** (`sync_service.dart:1970`→`:2027`, `:2159`→`:2244`), so `_restoreFreezes` only sees the already-clobbered local and cannot repair it. Two variants never run `_restoreFreezes`: `restoreLightweightAlways` (`:1596-1641`, `_restoreUserProgress` on every cold start via `checkAndSync`) and the empty-Hive `restoreFromCloud` (`:1797`); the sign-in hydrate (`auth_session_bootstrapper.dart:880-907`) is a third whole-row merge. On those paths the clobber is also, by accident, the ONLY cross-device pull of the freeze count | code: `user_repository.dart:426-428`, `sync_profile.dart:947-996`; the field doc `user_repository.dart:249-252` claims the family is merged only by `mergeFreezeProgress` | code-proven. Consistent with telemetry: 10-01 07:41:25 `refill_check lastRefill=2026-09-21` AFTER the 09-28 07:30 refill (a SECOND Monday-09-28 refill, +1), `sync_freezes` 57014 statement timeout 07:41:26, `sync_freezes_retry_dropped expected=92` 09-26 18:42:52 and `sync_user_progress_retry_dropped` 09-28/29/30 and 10-02 (cloud lagging local), `before=1` at the 10-06 refill |
| F4 | 2026-09-26 first-PRO grant 0→3 at 07:13:03, `before=1` at the 18:42 consume | **VERIFIED CLEAN (earlier "lost grant" hypothesis retracted).** 6 subscriptions rows since 2026-05-05 04:19 UTC; migration 095 (applied 2026-06-18 15:35 IST, `backups/applied_migrations.json:619`) backfills `…grant_done=true` for every user with ANY `subscriptions` row; 09-14 23:08:32 `subscription_state_written isPro=true` produced NO grant event. The 09-26 grant fired mid account-swap with an empty local progress box, i.e. a phantom grant before the restore carried the flag; which merge undid it is unverified, the 3→1 outcome is the by-design one | queries + migration + code | verified |
| F5 | Once F1 is fixed a debit can land on a MOUNTED Home with no notice: `_checkStreakFreezeUsed` runs only from `initTab` (mount, `home_screen.dart:121`). The cold-start clear of `streak_freeze_just_used` (`restoring_screen.dart:508-519`) is in `_ensureOwnershipBeforeHome`, reached only by the FOREGROUND branch, so on the background branch the flag set by the post-restore reckon survives to the next mount | code | code-proven |
| F6 | A 127 s restore on the morning of 10-06 (`restore_completed status=success path=singlecall total_ms=127281`). The earlier "40 s restore_started→session open" reading is DROPPED (delivery skew, timestamp caveat above). **Device-measured per-op durations in that window (`restore_op_done`, logged for ops ≥ 2 s):** `workout_plan` 10,142 ms, `user_profile` 9,743, `custom_foods` 9,511, `workout_templates` 21,091, `pull_nutrition` 30,837, `pull_weight` 30,281, `sync_user_progress` 26,748, `sync_workout_plan` 33,105, `sync_steps` 41,099, plus two 45 s ceilings (`restore_sync_weight`, `restore_sync_coach_interactions` — PUSH ops from `weeklyFullSync`, `sync_service.dart:1352,1366`); the same restore's single-call data ops then took `ms=0`–355. So the slowness is real and device-measured, but **whether it is the phone's network or Supabase is NOT separable from the repo** (read-only `client_errors` SELECT, project `dedsavbjuwgarrhphgnl`, 06:45-06:49 IST) | `client_errors` | upstream/external cause not isolated; **no OI tracks latency itself** (OI-279 is pull-on-resume) — one is minted (§5) |
| F8 | A freeze is spent when it saves nothing: `_calculateStreak` consumes a freeze for every fresh missed day while `freezesAvailable > 0` (`workout_repository.dart:406-413`, persisted at `:430-437`), even if the walk later breaks anyway; and `commitConsume`'s notice text for a multi-freeze debit reads "Streak Freeze used! 0 remaining this week." Unit 1 widens the exposure (the persist now runs on app open) | code | code-proven; whether to change the rule is a founder decision (§3 terminal states) |
| F7 | `auth_session_bootstrapper.dart:891-903` hands the RAW cloud row to `mergeCloudProgress` without stripping `user_id`, `plan_json`, `sync_epoch` (`sync_profile.dart:957-975` strips them, day-swapper Task 20), so a sign-in hydrate spreads the whole `plan_json` blob into `userBox['progress']` | code (reviewer B, re-read by the coordinator) | code-proven |

## 0a. What rounds 1-2 changed (all verified before accepting)

1. **R1 Unit 1 P0:** a "failed critical op" set read from `_safeRestoreOp`'s catch is blind — `_restoreWorkoutLogs`
   (`sync_workout.dart:844-852`), `_restoreScheduleCompletions` (`:1122-1130`), `_restoreWorkoutPlan` (`:1458-1466`),
   `_restoreScheduledWorkouts` (`:2617-2625`), `_restoreUserProgress` (`sync_profile.dart:999-1007`), `_restoreFreezes`
   (`sync_restore_completeness.dart:440-448`), `_restoreUserProfile` (`sync_profile.dart:852`) all catch, call
   `_reportSyncFailure(opType: 'restore_<x>')` and return normally; only the 45 s ceiling reaches the catch. v2/v3 record at
   the `_reportSyncFailure` funnel with a per-call Zone collector (reviewer R2-A proved the zone semantics with a probe: values
   survive `Future.wait`, `timeout`, timers, streams, microtasks; two concurrent runs are isolated).
   (v2's "live proof" mixed accounts: the 09-26 `restore_workout_logs Load failed` rows are the OTHER account's restore. The
   better live example is 09-21 `restore_freezes TimeoutException` 07:28:50/52 followed by `restore_completed status=success`
   07:29:14 — restores overlap that morning, so cite it as consistent-with. The code proof stands.)
2. **R1 Unit 2 P0:** v1's "local non-null wins" defeats the optimistic lock (a stale phone adopts the cloud version while keeping
   stale freeze state; `096_…sql:57-68` overwrites on a version match) and removes the only cross-device freeze pull on the
   lightweight path → v2/v3 delegate to the existing mutation-proven `mergeFreezeProgress`.
3. **R2 Unit 2 P1s:** (a) the leaf extraction rested on a false premise — import cycles already exist (`user_repository.dart:8`
   → `sync_service.dart` → `streak_progress_service.dart` (`sync_service.dart:17`) / `user_repository.dart` (`:58`), and
   `streak_progress_service.dart` imports both back (`:35`, `:38`); no cycle lint) — and would redden two
   source-grep contracts (`streak_freeze_refill_race_test.dart:42-77`, `streak_freeze_restore_clamps_test.dart:23-43`) and the
   derived platform-completeness test → **extraction DROPPED**: `user_repository.dart` imports `streak_progress_service.dart` and
   calls the static pure `mergeFreezeProgress`; (b) the cross-device first-PRO grant (web grants 3, pushes; phone local free
   `{1,'10-05'}` × cloud `{3,'10-05'}` → min = 1, or cloud `{3,'09-28'}` → pushes 1 over 3; the flag then also blocks the phone's
   own grant) regressed vs the clobber → **grant carry** (§3 U2.3).
4. **R2 Unit 1:** the marker-setting wrapper had no behavioral test → the core reads its uid through `_liveUserId` and the wrapper
   gets END-TO-END tests through `SyncHarness` + a forcing-function test; `GuardedBox.empty` writes THROW (`guarded_box.dart`
   `put`: `if (_isEmptyStub) throw`), they are not "dropped" — those throws land in the sink; empty-answer blind spots, the
   liveness trade-off, the not-freshness-bounded marker and the A→B→A residual are now disclosed (§3 U1.8).
5. **R2 process:** `background_restore_test.dart:166-175` asserts the heal contains `SyncService.instance.bumpRestoreCompleted()`
   (REPOINT it); `completed_title_follows_log_test.dart:344-379` pins the wrapper's shape (the literal
   `_restoreFromCloudForUserCore()` in the body, the exact non-negated `if (shouldHealAfterRestore(result)) { await
   healCompletedTitlesAfterRestore(); }` block, exactly two `_restoreFromCloudForUserCore(` references in `lib/`); the three
   "vacuous" ledger tests are NOT all given a set marker (two assert the gate is OFF); the "skewed ledger is verified clean"
   claim was wrong (§3 terminal states); `bpass_review:` + `docs/reviews/…` + the tuning-history entry; naming conventions;
   registry `line_range` parity; OI board labels.
6. **R3 (all verified against the code before accepting).** *Unit 2 P1:* `syncFreezes` begins `_supabase.currentUser?.id`
   (`sync_restore_completeness.dart:36`), which is null under `SyncHarness` (`SupabaseService` is never initialised there), so the
   "pushed RPC" assertion could never observe a push → `syncFreezes` reads `_liveUserId` instead (byte-identical in production,
   `sync_service.dart:643-646`), and the core restore (`:1884`) and single-call path (`:2140`) get the same one-token change. *Unit 2 P2s:*
   index-assignment only in `user_repository.dart` (the sole-writer contract regex, below); the "cannot refund a consume" overclaim
   reworded; a flag-only divergence now schedules a push, with a symmetric carry; a steady-state no-push mirror; an owner guard on the new
   push; the LOW event's "not invisible" claim dropped; mirror rows labelled. *Unit 1 P2s:* the forcing-function regex must tolerate the
   newline between `_safeRestoreOp(` and its label (15 such calls, `sync_service.dart`); a pure `shouldSettleRestoreMarker` so the settle
   clauses can be killed by a mutation; per-op `_reportSyncFailure` spelling pins; T7 drives the LEGACY fan-out only (the single-call
   path faults before the stub in the harness). *Process:* terminal-state wording the validator accepts, F8 into §0, F6 reworded to an
   external blocker, the value-semantics sweep widened, citations corrected, one diagnose-doc per commit.
7. **R4 (delta review of v4; two P1s, both verified in code).** *P1-A:* the SYMMETRIC grant carry is defeated on the default full-restore path
   — `_restoreFreezes` runs after `_restoreUserProgress` and merges local against the stale pre-fetched cloud row with the PLAIN rule
   (`sync_restore_completeness.dart:397-412`, version re-stamp `:432-435`), and the conflict-retry merge (`:124-256`, no flag in its select)
   cannot carry either; a correct version needs one shared helper at THREE merge sites. The reviewer's own prescription was "or drop it":
   **DROPPED** (it was an OPTIONAL round-3 suggestion). That also removes its refund hazards (`{3,W,T}×{0,W,F}` ⇒ 3 would refund another
   device's consume; a phantom local grant would inflate once). The ASYMMETRIC carry (cloud flag true, local not) is robust through all three
   sites (after the post-pass local already equals the cloud value, so `_restoreFreezes` and the retry are no-ops) and stays. The flag
   write-back stays `local || cloud` — it matches `_restoreFreezes`'s own documented intent ("never regress a local true back to cloud
   false", `:418-426`). *P1-B:* the owner guard makes two existing fixtures red (`test/sync/restore_write_if_changed_test.dart:108-133`
   leaves no uid resolver so the live id is null; `test/sync/restore_lightweight_single_plan_fetch_test.dart` passes `'test-user'` while
   `SyncHarness` pins `kTestUserId`) — both fixtures are made truthful (not loosened) and listed in §2. *P2s:* `scheduleFreezeSyncUp`
   compares against the ORIGINAL cloud values; null==null `last_refill` specified; boot-seeded row states the cloud flag; sole-writer
   regex also scans COMMENTS; `_deletedTemplateCloudIds` swallow fixed in-batch (a `note`) instead of disclosed; U1.8 residuals get a ledger
   row; F6 evidence now concrete (above).

## 1. Writer / reader map (file:line, read in this session)

**Reckon gate (F1, F2).** Reader of the gate: `WorkoutRepository.reckonStreakDecayAndPersist` `workout_repository.dart:242-262`
(tick `:246-247`, `_hasAnyScheduleRow()` `:248`). Callers: `day_rollover_service.dart:177` (`_doRolloverWithRef`, refill `:163`
first), `train_provider.dart:1950` (after `markCompleted` `:1929`, so today counts as completed; the ledger makes a re-walk
idempotent, `workout_repository.dart:393-405`). Writer of the tick: `bumpRestoreCompleted` `sync_service.dart:1847`, ONE call
site `heal_after_restore.dart:74` (background branch, only `if (result.succeeded)` `restoring_screen.dart:332-334`; the
foreground branch never bumps it). Other tick readers (UI refresh only): `hive_tab_scaffold.dart:158,215`,
`ai_coach/screens/ai_coach/screen.dart:184,282`. Persisted writers: `commitConsume` `streak_progress_service.dart:126-160`,
`commitRefill` `:61-102`, `refillIfNewWeek` `:169-196`; cloud push `syncFreezes` `sync_restore_completeness.dart:34-115`. Readers:
`home_provider.dart:242-306`; Home invalidates both providers on a tick (`home_screen.dart:143-175`) — Train (`plan_header.dart:119`)
and Nutrition (`nutrition_screen.dart:148-149`) watch the SAME global providers and refresh only because of that Home
invalidation. Consume notice: `commitConsume` sets `streak_freeze_just_used` (`:141`); reader `home_screen.dart:210-235` (mount only).

**Freeze-state restore (F3).** Writers of `progress[streak_freezes_available | …_last_refill | …_first_pro_grant_done]`:
`commitRefill`/`commitConsume`/`grantFirstProFreezes`/`resetToFreeCapOnLapse` (`streak_progress_service.dart`), `_restoreFreezes`
`sync_restore_completeness.dart:356-449`, `_retrySyncFreezesOnceAfterConflict` `:124-256`, `StreakFreezeClampMigrator`
`streak_freeze_clamp_migrator.dart:102`, the version stamp `sync_service.dart:2908`, and the two whole-row merges
`sync_profile.dart:996` / `auth_session_bootstrapper.dart:904` via `UserRepository.mergeCloudProgress` `user_repository.dart:385-`
(`:426-428`). No third cloud-row merge exists (reviewer B grepped every `put('progress'`/`saveProgress`/whole-map `updateProgress`).
Readers: `_calculateStreak` `workout_repository.dart:331-337`, `StreakFreezeNotifier`, `refillIfNewWeek` `:171-179`, `syncFreezes`
`:44-57`. The plural cloud column `streak_freezes_used_dates` has NO reader in the local map (cloud-row reads only:
`sync_restore_completeness.dart:133,179,363,396`). `current_streak_weeks` writers: `train_provider.dart:1978-1990` (increment-only),
onboarding/default/dev resets; readers: `badge_service.dart:115`, `train_provider.dart:2281`, the AI snapshot, `pattern_detector.dart:115`,
and the cloud EFs (`streak-guardian`, `weekly-report`, `proactive-coach-promotion`). `last_workout_date`: one writer
(`train_provider.dart:1989`), pushed only, no local reader.

## 2. Bug history (§4.1.5) — recurrence of a known class

Recurrence of `f9d2e7` (D2 reckon; text says it runs "on every app open" — true only when the tick is already > 0; its own
Deviation section records the tick is bumped only from the bg heal), `9c4a17` (Monday refill vs restore race), `a8f3d1` (restore
merge vs concurrent consume), `e9d4b7` (cloud streak stale after decay), `9c8958` (chip not invalidated). Founding symptom of the
class: "streak 1 / freeze 1 after two idle days". `user_repository.dart:249-252` says "two merge rules over one field is how
writer/reader drift starts" and leaves a second merge rule live. Open board items on the same class: **OI-293** (restore outcomes
unobservable — the Unit 1 collector gives the CALL-level outcome for the seven streak-critical ops, not the plan-only record
OI-293 asks for; its text is updated to say so), **OI-294** (success-only tick bump; its design requirement 2, "never reuse
`restoreCompletedTick`, it gates streak decay", becomes obsolete — text updated), **OI-279** (`:5530,5539,5543` relied on the tick
gating decay — text updated; `:5648`/`:5655` are inside OI-294/OI-295, not OI-279).

Value-semantics sweep (§4.1.5.3), `restoreCompletedTick` readers: `test/contracts/streak_decay_reckon_permanent_ledger_test.dart`
(the only test that OPENS the gate by the tick: `:41,45,152,167,177,212,226,238`), `completed_title_follows_log_test.dart`
(`:296-320` passes, comment `:313-314` becomes false; **`:344-379` pins the wrapper shape — see §3 U1.3**),
`background_restore_test.dart` (**`:166-175` asserts the heal contains `SyncService.instance.bumpRestoreCompleted()` — REPOINT**),
`test/features/ai_coach/coach_chat_restore_invalidation_test.dart` (unaffected). Comments/docs that say the tick gates decay
(corrected in the same commit): `sync_service.dart:1856-1857`, `workout_repository.dart:231-238`, `day_rollover_service.dart:170-175`,
`lib/features/dev/simulation_service.dart:492`, `lib/core/services/CLAUDE.md` (`completed_title_follows_log` row),
`lib/features/home/CLAUDE.md`, `.claude/skills/debugging/SKILL.md:247` (red flag) and `bug-classes.md:1528` (§2.88),
`docs/sot_registry.yaml:3522,4314,4439`, `docs/audit/open_issues.md` OI-279/OI-293/OI-294. Historical plans/diagnoses/reviews are
records, not edited.

**Value-semantics sweep for the UNIT 2 meaning change (round-3 P2-6 — "the freeze keys are cloud-non-null-wins" becomes false):**
`docs/sot_registry.yaml:3103,3111,4379,8380-8381` (`:8380` repeats the false "freeze family already merged"),
`lib/core/services/CLAUDE.md:101` ("cloud-non-null-wins on the rest"), `docs/architecture/services-detail.md:160`, stale comments in
`test/features/profile/profile_provider_single_source_test.dart:195` and `test/features/ai_coach/coach_chat_restore_invalidation_test.dart:163`,
and the field doc `user_repository.dart:249-252`. **Existing tests that are HAZARDS for the new code (must stay green; none is loosened):**
`test/safety/restore_after_session_open_test.dart:44-71` (un-stripped `indexOf`: the first `openForUser` must precede the first
`_safeRestoreOp(` after the wrapper signature, so NO comment between the wrapper and the core may contain `_safeRestoreOp(`);
`completed_title_follows_log_test.dart:365-379` (counts raw `_restoreFromCloudForUserCore(` — exactly 2, comments included, so the new
part file and every new comment must not spell it); `test/contracts/restore_progress_uses_shared_merge_test.dart:64-78` (both writers keep
`reportProgressDemotionsDeclined(`; every `put('progress', X)` ends `.merged`); `streak_progress_service_concurrency_test.dart:127-184`
(sole-writer regex, §3 U2.5b — it scans RAW source, comments included, so no comment in `user_repository.dart` may spell
`'streak_freezes_available':` either); **the owner guard's fixtures (round-4 P1-B; both are made TRUTHFUL, never loosened):**
`test/sync/restore_write_if_changed_test.dart:108-133` (`setUpHiveForTests` sets no uid resolver, so `_liveUserId` is null and the guard
would return before the `put` — its setUp/tearDown set `HiveUserSession.debugCurrentUidResolverForTests` to the uid the test uses) and
`test/sync/restore_lightweight_single_plan_fetch_test.dart` (passes `'test-user'` at `:60,80,110,178,202,238,267,294,313,334` while
`SyncHarness` pins the resolver to `kTestUserId`, `sync_domain_skip_harness.dart:24` — it passes `kTestUserId`); the other callers of
`restoreUserProgressForTest|restoreLightweightAlways|_restoreUserProgress` (`oi252_template_restore_migrator_wiring_test.dart`,
`audit_2026_06_07_batch5_regression_test.dart`, `progress_restore_monotonic_behavioral_test.dart`) are re-read at implementation and the
grep is re-run before the first test run; `sync_retry_controller_test.dart:642-654` (a 1,800-char window; measured 1,373 chars of headroom for a new
first statement in `_reportSyncFailure`). `last_workout_date` is also read by an Edge Function
(`supabase/functions/evaluate-rank-promotions/index.ts:175,236`); the sweep conclusion holds — the clobber copies cloud → local and cannot lower the cloud.

## 3. Design

### Unit 2 (first) — a stale cloud row no longer overwrites freeze state; it is MERGED by the one existing rule (F3, F7)

1. `UserRepository.mergeCloudProgress` (`user_repository.dart:385-`) imports `streak_progress_service.dart` and calls the static pure
   `StreakProgressService.mergeFreezeProgress` (`streak_progress_service.dart:285-335`) **unchanged** — no extraction, no new file,
   no edit to that rule or to the source-grep contracts that read it.
2. **Order-independent post-pass** (precedent: the OI-150 companion pass `user_repository.dart:503-532`; PostgREST key order is not
   ours). Active only when `!guardOff && !_freezeMergeDisabled`. The freeze family (`streak_freezes_available`,
   `streak_freezes_last_refill`, `streak_freezes_first_pro_grant_done`, plural `streak_freezes_used_dates`) is SKIPPED in the
   cloud-copy loop and merged after it. Inputs are built with `is`-tests, never the throwing `as num?` cast (this function's own
   comment `:430-434` records that bug): `cloudAvailable` = `cloud[available] is num` → `toInt()`, else the whole post-pass is skipped
   (the column is `INTEGER NOT NULL`, so the skip is defensive); `localAvailable` = `local[available] is num ? toInt() :
   cloudAvailable` (the same fallback `_restoreFreezes:398-400` uses; ignored on the cloud-wins branch); `localLastRefill` =
   `local[last_refill] is String ? … : null`; `cloudLastRefill` = `cloud[last_refill]?.toString()` (Postgres `date` →
   `YYYY-MM-DD`, as `_restoreFreezes:395-411`); used-date lists from `is List` → `toString()` (singular local key, plural cloud key).
3. **Grant carry (R2 P1b).** Before the call: if `cloud[grant_done] == true && local[grant_done] != true`, pass
   `localAvailable = max(localAvailable, cloudAvailable)`. Effect through the unchanged rule: same-week → cloud's value; cloud
   older → keep the larger and push; cloud newer → cloud. One-shot (the post-pass flips the local flag in the same merge).
   The carry applies whatever the two `last_refill` relation is — the unchanged rule decides which side's number survives (a null
   local `last_refill` takes the rule's cloud-wins branch, `streak_progress_service.dart:317-327`). Round 3/4's hand-run of the REAL rule
   (W = this Monday, P = last Monday; `{available, last_refill, flag}`): `{1,W,F}×{3,W,T}→3`, `{1,W,F}×{3,P,T}→3 pushed`,
   `{1,W,F}×{0,W,T}→0`, `{0,W,F}×{3,W,T}→3`, `{2,P,T}×{3,W,T}→3`, `{3,W,T}×{3,W,F}→3` with the flag kept true, `{1,null,F}×{3,W,T}→3`.
   **What it does NOT claim:** it does not stop the pre-fix refund of a real local consume — `{0,W,F}×{3,W,T}→3` is exactly what the old
   cloud-wins did (documented, not a regression). The reinstall case `{1,W}×{0,W}` stays 0 because the cloud flag is not set there.
   `grantFirstProFreezes` returns early on the flag (`streak_progress_service.dart:213-217`) and is fired only on an `!oldIsPro && isPro`
   transition (`subscription_service.dart:345`), so there is no double grant. **There is NO symmetric carry** (local flag true, cloud not):
   round 4 showed `_restoreFreezes`/the retry would undo it (§0a item 7); that edge — a first-PRO grant whose push was dropped, followed by
   a restore — therefore behaves exactly as before the fix (same-week LOWER; `available` clamps to the cloud's count), now with the flag
   kept true by `local || cloud` as `_restoreFreezes:418-426` already intended.
4. **Write-back.** `available` (clamped by the rule), the union into the SINGULAR `streak_freeze_used_dates`, `last_refill` when
   non-null, `grant_done` = `local || cloud` (written only when true). `streak_progress_version` stays cloud-always-wins (now
   consistent with `_restoreFreezes:432-435`). The plural key is not copied (existing installs keep the stray key already there).
5. **Push + visibility.** `ProgressMergeResult` gains `scheduleFreezeSyncUp` (a separate field — not `declinedFields`, whose length
   and event count are asserted by `progress_restore_monotonic_behavioral_test.dart:158,578-615`) = the rule's own
   `scheduleSyncUp` OR "the merged freeze state differs from the ORIGINAL cloud row" (round-4 P2-3: compared against the cloud values
   BEFORE any carry adjustment) — `available`, `last_refill`, the `used_dates` compared AS A SET (order/duplicates never count), OR the
   grant flag (local true / cloud not true; `syncFreezes` reads the flag at `:56-57` and upserts `{user_id, flag:true}` at `:100-105`,
   and the RPC has no flag parameter, migration 096:10-15, so the upsert is the only carrier — round 4 verified it converges) — so a
   same-week-lower consume or local-only `used_dates` that the old clobber silently refunded now converges after one push. **No push loop (round 3 traced it):** after a landed push cloud equals local (the RPC
   overwrites the array, `last_refill` and `available`, migration 096:62-66), the union always contains cloud's set, cloud `available` is
   `CHECK 0..3` so the clamp is a no-op, both-null `last_refill` is equal; a persistently failing push costs ≈3 RPCs (+1 retry GET and
   RPC each) per cold start, bounded.
   Both callers fire `unawaited(syncFreezes())` AFTER their `put` (`syncFreezes` reads the version synchronously at its start,
   `sync_restore_completeness.dart:38-64`) — in `_restoreUserProgress` regardless of the `unchanged` fingerprint skip (the push is
   owed to the CLOUD, not the local box). **Owner guard (round-3 P2-5):** `_restoreUserProgress` has no `ownerChangedSince` check today
   (unlike `_restoreUserPreferences`, `sync_profile.dart:1064`), so the new push after an A→B swap would send B's box, merged with A's
   row, to B's cloud row (the e5c2d1 class, window widened) — `if (ownerChangedSince(userId)) return;` goes immediately BEFORE the `put`
   and the push (the put guard is the pre-existing e5c2d1 hole, closed in the same place; the bootstrapper caller is the sign-in
   hydrate for the current user and needs none). In a full restore `_restoreFreezes` follows with the same pre-push snapshot and may
   push again: the second RPC returns NULL and takes the existing bounded `_retrySyncFreezesOnceAfterConflict` (idempotent; reviewer
   verified M(M(l,c),c)=M(l,c), carry included) — accepted, one wasted RPC, documented. One LOW event
   `progress_restore_freeze_merge_engaged` (`reportFreezeMergeEngaged`, beside `reportProgressDemotionsDeclined`, per-process latch,
   emitted only when `scheduleFreezeSyncUp`). **It is best-effort and its ABSENCE proves nothing** (LOW is dropped under client cooldown,
   `error_telemetry.dart:327,396`; promoting it to HIGH needs the `log-client-error` allowlist edit `index.ts:212-213` plus
   `high_priority_op_types_parity_test.dart`, which this batch's "no Edge Function" scope excludes). Engagement is observable by the
   RPC push itself and by the tests.
5a. **Test observability seam (round-3 P1).** `syncFreezes` begins `final userId = _supabase.currentUser?.id` (`sync_restore_completeness.dart:36`),
   null under `SyncHarness` (`SupabaseService` never initialised, `supabase_service.dart:89-92`) → it returns before any RPC, so no push
   assertion could ever pass. It becomes `final userId = _liveUserId;` — byte-identical in production (the resolver is null there,
   `sync_service.dart:643-646`); the same one-token change goes to the core restore (`:1884`) and the single-call path guard (`:2140`) so
   the whole restore runs under the harness. The wiring test pins only the RPC call shape (re-checked at implementation). Push
   assertions count `requests` to `/rest/v1/rpc/update_streak_progress`.
5b. **Sole-writer contract (round-3 P2-1).** `streak_progress_service_concurrency_test.dart:127-184` fails any `lib/**/*.dart` outside
   an allowlist (`user_repository.dart` is not on it) that matches `['"]streak_freezes_available['"]\s*:`. The post-pass therefore
   writes by INDEX ASSIGNMENT only (`merged['streak_freezes_available'] = …`, no map literal / const Map with that key); the test is
   added to the §2 sweep and stays unedited. (Its allowlist is NOT widened — that would weaken the contract.)
6. **F7.** Under the same `!guardOff && !_freezeMergeDisabled` condition `mergeCloudProgress` also ignores the control-plane keys
   `user_id`, `plan_json`, `sync_epoch` (idempotent with `sync_profile.dart`'s own pre-strip), so the bootstrapper path stops spreading
   the blob. ONE switch reverts all new Unit 2 behaviour.
7. **Kill switch** `configBox['disable_progress_freeze_merge']`, a static getter in the `:340-350` try/catch shape (with the box unopened the fix stays ON). The
   OI-83 switch stays the WIDER rollback (comment `:403-409`, code `:410`): when EITHER switch is set the freeze keys and the
   control-plane keys take the pre-fix cloud-non-null-wins branch verbatim. The doc at `:249-252` is corrected to say what is true
   (and its stale cite `sync_restore_completeness.dart:225` → the real call sites `:180,:237,:397`). If the cloud `available` is
   non-numeric the post-pass is skipped and local stays verbatim — stricter than pre-fix and safe against the hard `as int?` readers
   (`workout_repository.dart:331`); no telemetry is added for it (a LOW event would be dropped under cooldown, and the tests pin it).
8. **Documented trade-offs.** A first-PRO grant whose push was dropped, followed by a restore, loses its extra freezes exactly as it did
   pre-fix (no symmetric carry; §0a item 7) — the flag now survives (`local || cloud`), which cannot re-grant (a transition-only trigger).
   A boot-seeded `{1, thisMonday}` vs a cloud `{3, lastMonday}` takes the rule's "local newer: keep local, push up" branch that the
   clobber used to pre-empt — the result depends on the cloud flag (cloud `{3,lastMonday,T}`: the asymmetric grant carry lifts local to 3 and the rule keeps it and pushes;
   cloud flag false: local 1 is kept and pushed; the test states the
   flag in each row); reviewers could not construct a reachable production sequence (email sign-in hydrates cloud first; OAuth fresh
   install awaits the restore before the rollover); the test pins it. Round 4 also notes a phantom LOCAL grant (the F4 mechanism) over a
   cloud row with the flag false: with no symmetric carry it clamps to the cloud count, as before.
9. **Other streak keys the `SELECT *` still overwrites (terminal states, §3 below).** `current_streak_days` is re-stamped by Unit 1's
   post-restore reckon (`_persistCurrentStreakDays`, `workout_repository.dart:275-284`). `last_workout_date` is not freeze state and is not touched here; `current_streak_weeks` joined the monotonic set on 2026-10-06 (founder decision A, c9d2f6 item 8).

### Unit 1 — decay is persisted once the restore for THIS user settled (F1, F2, F5)

1. **Marker.** `SyncService` gains `String? _restoreSettledUserId`, a diagnostic-only `String? _lastRestoreWithheldReason`
   (overwritten per wrapper call), and the pure getter `restoreSettledForCurrentUser`: true iff the marker is non-null, equals
   `_liveUserId` (`:643`, honours `HiveUserSession.debugCurrentUidResolverForTests`) and equals `HiveUserSession.currentOwnerFullId`.
   The getter has no write, no telemetry, no writer-vocabulary call (the CQRS gate scans every `get`, `cqrs_query_naming_lib.dart:147,305-312`).
   `_onUserChanged` (`:187`) clears the marker. Seam: `@visibleForTesting void debugSetRestoreSettledUserIdForTest(String?)`.
   `day_rollover_service.dart` is another library, so the withheld reason is exposed by a PUBLIC `String? get lastRestoreWithheldReason`
   (a `String?` getter is not matched by the public-API snapshot regex, `sync_service_public_api_snapshot_test.dart:191-194`); every new
   member of the new part file is `static` or top-level for the same reason (a non-static `void`/`Future` member would grow
   `expectedPublicApi` beyond the two listed seams).
2. **Per-call failure collector at the funnel**, in a new `part` file `sync/sync_restore_failure_collector.dart` (under the `sync/**`
   platform glob; no new library, so no `blast_radius.yaml` / derived-completeness edit): `RestoreFailureCollector.run(Set<String>
   sink, Future<T> Function())` = `runZoned` with the sink as a zone value; `note(String opType)` adds `opType` to the zone's sink iff
   present AND `opType ∈ kStreakCriticalRestoreOpTypes` — an EXACT allowlist, never a `restore_` prefix (`weeklyFullSync` pushes through
   `_safeRestoreOp('sync_*')`, producing `restore_sync_*`): `restore_workout_plan`, `restore_workout_logs`, `restore_schedule_completions`,
   `restore_scheduled_workouts`, `restore_user_progress`, `restore_user_profile` (`_earliestUserAnchor` reads the profile's
   `onboarding_completed_at`, `workout_repository.dart:147-189`), `restore_freezes`, and **`restore_deleted_template_ids`** (round-4 P2-5,
   fixed in-batch: `_deletedTemplateCloudIds`, `sync_workout.dart:1765-1795`, fails EMPTY by design — the safe direction for its deletion
   filters — but inside `_restoreWorkoutPlan` (`:1432`) / `_restoreScheduledWorkouts` (`:2325`) an empty answer lets ghost days back in as
   past `planned` rows, and Unit 1 would make the resulting debit permanent; its catch therefore also calls
   `RestoreFailureCollector.note('restore_deleted_template_ids')` directly — a no-op outside a zone). **Corrected by the B-pass (reviewer B F1, verified):** the boot / foreground /
   background-heal `PlanIntegrityReconciler.reconcile` is NOT unaffected — it calls the public forwarder
   `deletedTemplateCloudIdsForUser` OUTSIDE any zone, after the marker settled and before the heal's reckon, and a fail-empty answer there
   wrote a deleted template's day back as a past `planned` row that the next reckon debited for good. The forwarder now returns `null` for
   "could not answer" (`{}` still means "none deleted") and `reconcile` skips every `tmpl_<uuid>` day on `null`
   (`filterGhostScheduleEntries`). The other seven are emitted through `_reportSyncFailure`. `_reportSyncFailure` (`sync_service.dart:2784`, the
   single funnel — in-op swallow AND `_safeRestoreOp:2711`) calls `RestoreFailureCollector.note(opType)` as its FIRST statement, before
   any await, and `note` is TOTAL (its body is in a try/catch — `_reportSyncFailure` is the app-wide failure funnel and must never
   throw because of this addition; the retry-controller test window `sync_retry_controller_test.dart:642-654` has 1,373 chars of
   headroom). A concurrent `restoreLightweightAlways` or push sweep runs in another zone and neither pollutes nor clears it.
   Pure `restoreSettlesStreak(Set<String> failures)` = `failures.isEmpty`. Round 3 verified each of the seven ops emits exactly
   `restore_<x>` in its own catch (`sync_workout.dart:850,1128,1464,2623`; `sync_profile.dart:852,1005`;
   `sync_restore_completeness.dart:446`) and the 45 s ceiling emits `restore_$label` (`sync_service.dart:2711`); the swallows that bypass
   the funnel (`_restoreUserProfile`'s inner `users` catch, `sync_profile.dart:740-747`; `_deletedTemplateCloudIds`,
   `sync_workout.dart:1785-1794`) are disclosed in U1.8(a).
3. **Wrapper shape (pinned by `completed_title_follows_log_test.dart:344-379`, so it keeps the literal and the exact `if` block):**
   ```
   Future<RestoreResult> restoreFromCloudForUser() async {
     final uid = _liveUserId;
     final failures = <String>{};
     final result = await RestoreFailureCollector.run(
         failures, () => _restoreFromCloudForUserCore());
     if (shouldHealAfterRestore(result)) {
       await healCompletedTitlesAfterRestore();
     }
     _settleRestoreMarker(uid, result, failures);   // AFTER the if block
     return result;
   }
   ```
   The core (`:1884`) and the single-call path's guard (`:2140`) read the uid through `_liveUserId` (identical in production: the
   resolver is null there) so the whole wrapper runs under `SyncHarness`. **The decision is a pure function (round-3 P2-2):**
   `@visibleForTesting static bool shouldSettleRestoreMarker({required String? uid, required String? liveUid, required String? ownerUid,
   required RestoreResult result, required Set<String> failures})` = `result.succeeded && restoreSettlesStreak(failures) && uid != null &&
   liveUid == uid && ownerUid == uid`, mirroring `shouldHealAfterRestore`; each clause is unit-tested and mutation-killable (an
   end-to-end swap becomes `cancelled` first, so the two uid clauses are reachable only from a swap landing inside the awaited title
   heal). `_settleRestoreMarker` calls it with `_liveUserId` / `HiveUserSession.currentOwnerFullId`, sets `_restoreSettledUserId = uid`
   when true, and otherwise records the reason (`failed=<opTypes> succeeded=<bool>`). The marker is never cleared by a later failed
   restore (an earlier success for the same user stays valid). No comment between the wrapper and the core may spell
   `_restoreFromCloudForUserCore(` or `_safeRestoreOp(` (hazard tests, §2).
4. **Gate.** `reckonStreakDecayAndPersist` replaces `restoreCompletedTick.value > 0` with `restoreSettledForCurrentUser`; the
   empty-schedule gate and the reentrancy guard stay. No telemetry on the cold-start gated path (gated on every returning-user cold
   start — that IS F1 — and would be the per-success flood class of `sync_service.dart:197-207`).
5. **Post-restore reckon, public and testable.** `DayRolloverObserver.reckonAndNotifyAfterRestore()` (it already imports
   `WorkoutRepository`, `day_rollover_service.dart:24`; `restoring_screen.dart` already imports `day_rollover_service.dart`, `:6`, so
   the head file stays 794/800): (a) `reckonStreakDecayAndPersist()` in try/catch (`reason: 'bg_heal_streak_reckon'`); (b) if the
   marker is false and `_lastRestoreWithheldReason != null`, ONE LOW `streak_reckon_withheld` event carrying it; (c)
   `SyncService.instance.bumpRestoreCompleted()` — always, last, so tick listeners repaint from the already-debited ledger.
   `_healAfterRestoreInBackground` replaces its final bump with this call, after `refillIfNewWeek()` (`heal_after_restore.dart:51`).
   Reviewer A traced every heal step before it (`PlanIntegrityReconciler:105,137-138` preserves completed rows; `CompletedTitleHealer`
   title-only; `PhaseProgressReconciler` read-only; the migrators never touch `schedule_`). The foreground branch needs no new call: it
   awaits the restore (marker set) before `runRolloverNow` (`restoring_screen.dart:339,533`). **Behaviour change, now tested:** on the
   foreground branch (fresh install, `disable_bg_restore`) the tick never bumps, so today even `completeWorkout`'s reckon is read-only
   for the whole process; with the marker it persists there.
6. **Home notice.** `home_screen.dart` overrides `invalidateOnBackgroundRestore(ref)` (plain overridable, `hive_tab_scaffold.dart:119`;
   Nutrition overrides it too) = `invalidateOnRetry(ref)` + `_checkStreakFreezeUsed()`. `commitConsume`'s Hive write is synchronous
   (`user_repository.dart:594-604`) and the check clears the flag before scheduling the snackbar, so `initTab` plus the tick listener
   cannot double-fire.
7. **Kill switch** `configBox['disable_streak_reckon_user_gate']` (opt-out polarity, `SyncFlags`; the fix stays ON when the box is unopened): set ⇒ the gate is the pre-fix
   `restoreCompletedTick.value > 0` verbatim and `reckonAndNotifyAfterRestore` only bumps (default = fix ON, the
   `disable_completed_title_heal` convention; so the FULL ×2 review applies, not the ship-dark tier).
8. **Disclosed residuals (stated, not hidden).** (a) *Empty-answer blind spots:* `_restoreUserProgress` `rows.isEmpty`
   (`sync_profile.dart:955`), `_restoreUserProfile` (`:749`), `_restoreWorkoutPlan` empty/null (`sync_workout.dart:1331-1333`),
   `_restoreFreezes` `rawRes == null` return silently; on the legacy path an RLS-filtered stale-token empty answer is
   indistinguishable from a legitimately empty table. The default single-call path is safe (service-role EF, fail-closed on any query
   error, `restore-user-snapshot/index.ts:116,132-139,329-334`); the legacy path is used only after an EF fault. Silent caps: the EF's
   `scheduled_workouts` is `.range(0, 999)` (`:256`) and `workout_schedule_completions` has no `.limit()` (`:207-209`). The marker
   therefore means "no streak-critical op REPORTED a failure", not "every row was fetched". Found in round 3 and FIXED in-batch (round-4
   P2-5, U1.2 above): the `_deletedTemplateCloudIds` fail-empty swallow. Still disclosed: `_restoreUserProfile`'s inner `users` catch
   (`sync_profile.dart:740-747`) bypasses the funnel (the profile is read by `_earliestUserAnchor` only for its `onboarding_completed_at`;
   its retry path re-reads once). (b) *A→B→A inside one restore step*
   (`restoreAbortedFor` only runs at step checkpoints, `sync_service.dart:594-603`): an A op re-resolving `_hive.workoutBox` can write
   A's rows into B's box with nothing reported — the existing e5c2d1 class (`:573-592`); the marker adds no exposure beyond the restore's
   own. (c) *Liveness:* one persistent critical-op failure (a malformed row, a 57014 on a heavy account) means no persist for the whole
   process, including `completeWorkout`; pre-fix the tick was bumped on `result.succeeded` regardless. The marker can also be set
   without the heal ever running (`_onContinueAnyway`, DestinationUnknown-without-evidence branch). **Closed by the B-pass (reviewer C
   F1):** `_onContinueAnyway` now attaches the same heal + reckon to the in-flight restore (`healAfterRestoreWhenSucceeded`, a failed or
   cancelled restore never heals), so that cohort no longer waits for `completeWorkout`, the midnight timer or a resume. (d) *Not freshness-bounded:* the marker is process-lifetime, exactly as the tick was; a resume days later can reckon against
   statuses completed on another device in between (OI-279 is the pull-on-resume fix; bounding by IST date would disable the
   midnight-resume reckon and regress today's behaviour). (e) *`restoreLightweightAlways`* is not covered by the marker (another zone)
   and re-runs the whole-row merge every cold start — durability depends on Unit 2 (above).

### Terminal states (§4.2; every item below is in the closure YAML)

> **B-pass note (2026-10-06):** the closure YAML `docs/audit/streak-freeze-restore-ownership.closure.yaml` is the AUTHORITY for terminal states. It now carries every verified finding of the three context-blind B-pass reviewers (27 entries); the table below is the plan-time list and is NOT updated entry by entry. In particular `LAST-WORKOUT-DATE` is `blocked_on_user` (not `verified_clean`), `LIVENESS` is `verified_clean` as a recorded designed property, and the old single `RESIDUAL-EMPTY-ANSWER-AND-CAPS` entry is split into `RESIDUAL-EMPTY-ANSWER` (upstream_blocked on OI-293) and `RESIDUAL-EF-CAPS` (blocked_on_user: an Edge Function deploy).

The closure YAML's `terminal_state:` is the bare token (the validator, `scripts/validate_audit_closure.dart:57-62,270`, does an exact match;
`closed_in_commit` needs `commit:` + `verification:|notes:` `:275-281`, `upstream_blocked` needs `blocker:` + `reopen_when:` `:282-288`,
`blocked_on_user` needs `reason:` `:289-293`, `verified_clean` needs `evidence:|notes:` `:294-297`); any CONDITION lives in `notes:`.
The `commit:` of a not-yet-made commit is a labelled branch placeholder until the commit exists (validator header `:25-26`; only
non-empty is checked) and is replaced at commit time. If Unit 1 were ever split out, F1/F2/F5 and `current_streak_days` leave this
ledger and stay on the board (OI-294 precedent).

| Item | State | Evidence / reason |
|---|---|---|
| F1, F2, F5 | `closed_in_commit` | Unit 1 |
| F3, F7 | `closed_in_commit` | Unit 2 |
| `current_streak_days` clobbered by `SELECT *` | `closed_in_commit` (`notes:` — repaired by Unit 1's post-restore reckon; same batch, same commit pair, never shipped without it) | Unit 1's post-restore reckon re-stamps it |
| `last_workout_date` clobbered by `SELECT *` | `verified_clean` | one writer `train_provider.dart:1989`, rewritten on every completion; local readers none (grep `lib/`); cloud readers `supabase/functions/evaluate-rank-promotions/index.ts:175,236` — the clobber copies cloud → local and cannot lower the cloud value |
| F4 | `verified_clean` | §0 F4 evidence (subscriptions, mig 095, 09-14 and 09-26 telemetry). Its premise "the by-design 3→1" rested on the clobber Unit 2 removes, so a MIRROR row pins it: phantom local `{3, flag true}` × cloud `{1, flag true}` ⇒ 1 (same-week LOWER), and `grantFirstProFreezes` stamps no `last_refill` (`streak_progress_service.dart:213-232`) |
| F6 latency (a 127 s restore, `total_ms=127281`; device-measured plain reads 9-41 s, two 45 s ceilings; the same restore's single-call data ops `ms=0`-355) | `upstream_blocked` | `blocker:` = network-or-backend latency in that window, EXTERNAL to this repo and not separable from it (the evidence is device-measured per-op durations; the phone's network and Supabase cannot be told apart after the fact, and `get_advisors` reports current, not 06:45 IST, state); `reopen_when:` a restore > 60 s recurs with `query_logs`/`get_advisors` evidence taken IN that window; the minted OI (restore latency; none tracks it — OI-279 is pull-on-resume) is cited on the entry |
| Unit 1 residual limits (§3 U1.8): (b) an A→B→A swap inside one restore step; (d) the marker is not freshness-bounded; the empty-answer / EF-cap blind spots (a) | `upstream_blocked` | `blocker:` = (b) the pre-existing e5c2d1 class — `restoreAbortedFor` runs only between steps (`sync_service.dart:594-603`), unchanged by this batch; (d) OI-279 (pull-on-resume); (a) the EF's `.range(0,999)` / no-`limit` caps and the legacy path's RLS-empty ambiguity; `reopen_when:` OI-279 lands / the restore step checkpoint design changes; ONE OI is minted for (a)+(b) at commit time and cited on the entry (a limitation of this design, stated, not a deferred fix) |
| F8 — a freeze is spent when it saves nothing (idle gap longer than the freezes) + snackbar wording "Streak Freeze used! 0 remaining this week." for a multi-freeze debit | `blocked_on_user` | `reason:` = the exact founder question: "should a freeze be consumed when the streak breaks anyway, and what should the multi-freeze notice say?" (product + Wardroom copy). The shipped behaviour is unchanged (spend; wording unchanged) — that is what was running before, not a deferral of a fix; if the answer is "no", the shape is: commit consumption only when a completed day is later found in the same walk. Unit 1 widens exposure (app-open path); a new OI is minted |
| `current_streak_weeks` clobbered by `SELECT *` | `closed_in_commit` (Unit 2 commit, diagnose c9d2f6 item 8) | Founder decision A, 2026-10-06 (chat, after the field was explained): a lifetime count of good weeks; it joins `monotonicProgressFields` (local-max-wins) so a stale cloud row cannot lower it. Original question kept for the record: the only writer increments (`train_provider.dart:1978-1990`) and nothing resets it, yet OI-83 excluded it on a "a streak resets" premise; this overrides that recorded decision. A reset-on-daily-break feature is a NEW feature (OI minted at commit time) and would remove the field from the list again. |
| The founder's own ledger is ONE freeze short | `verified_clean` (`notes:`: founder decision 2026-10-06, "leave it like that"; no production write) — original analysis kept below | v2's "verified clean by derivation" is RETRACTED: it started at "09-26 consume → 0", which already embeds the 09-17 debit that F2 shows was spurious. Re-derived (reviewer C, free cap 1 until PRO at 09-14 23:07; PRO cap 3): without the 09-16 spurious debit the account would hold 3 at the 10-06 refill and 1 after the two debits, not 0. Repair = a prod UPDATE (+1 on `user_progress.streak_freezes_available`) needing the founder's own explicit go. **Recipe constraint (round 3):** a cloud-only +1 is reverted by `mergeFreezeProgress`'s same-week LOWER rule on the next restore and by Unit 2's own push, so the repair must be applied on the cloud row AND on the phone's local progress (or follow a refill week), not as a bare cloud UPDATE. A new OI is minted |

## 4. Tests (each FAILS without the fix and PASSES with it; one mutation cycle per unit, rule 21)

`test/contracts/progress_restore_freeze_merge_behavioral_test.dart` (Unit 2; pure + Hive configBox; template
`progress_restore_monotonic_behavioral_test.dart`): local `{2,'09-28'}` × cloud `{1,'09-21'}` ⇒ `{2,'09-28'}` + flag (fails pre-fix);
cross-device consume (`{2,'09-28'}` × `{1,'09-28'}`) ⇒ 1; cross-device refill (`{1,'09-28'}` × `{3,'10-05'}`) ⇒ cloud 3, no flag;
fresh reinstall (no local) ⇒ cloud (+clamp); boot-seeded `{1,thisMonday,F}` × cloud `{3,lastMonday}` ⇒ 3 + push when the cloud flag is true, 1 + push when it is false (pins the trade-off);
**grant carry (the ASYMMETRIC one only — local flag false × cloud flag true)** (local `{1,'10-05'}` flag false × cloud `{3,'10-05'}` flag
true ⇒ 3; × cloud `{3,'09-28'}` ⇒ 3 + push; the reinstall no-refund case `{1,W}×{0,W}` ⇒ 0; the documented real-consume row
`{0,W,F}×{3,W,T}` ⇒ 3 "equals pre-fix"; the null row `{1,null,F}×{3,W,T}` ⇒ 3 via cloud-wins) **and the three-site robustness check:** after
the post-pass, `restoreFreezesForTest` against the same stale pre-fetched row leaves local unchanged (the production order), so the carry
is not undone by `_restoreFreezes`; **no symmetric carry — pinned as unchanged-from-pre-fix:** `{3,W,T}×{1,W,F}` ⇒ 1 with the flag kept
true (and NO flag-only surprise: the post-pass pushes it); the boot-seeded row states the cloud flag (`{1,thisMonday,F}×{3,lastMonday,T}` ⇒
3 + push; with the cloud flag false ⇒ local 1 kept + push); the F4 mirror (phantom `{3,flag true}` × cloud `{1,flag true}` same week ⇒ 1);
`grant_done` local true × cloud false ⇒ true AND a push is scheduled (flag-only divergence); plural key not copied; `used_dates` union into the singular
key; a non-numeric `streak_freezes_available` in the cloud row does not throw (the `is`-test); control-plane keys dropped (F7);
**steady-state no-push mirror (round-3 P2-4, the only anti-storm protection):** identical local and cloud ⇒ `scheduleFreezeSyncUp == false`;
unsorted/duplicated `used_dates` equal as a set ⇒ false; flag true on both sides ⇒ false; two consecutive `restoreUserProgressForTest`
runs ⇒ 0 RPCs in `requests`; **owner guard:** the resolver switched to another uid before the call ⇒ NO `put` and NO push;
**kill-switch mirrors, key by key** (assert each key, not `merged ==` over a fixture that happens to carry none): ONLY
`disable_progress_restore_monotonic_merge` set ⇒ freeze AND control-plane keys cloud-non-null-wins; ONLY `disable_progress_freeze_merge`
set ⇒ the same; the getter fails closed with the box unopened. Real code: `restoreUserProgressForTest` (exists,
`sync_profile.dart:1128`) for the lightweight shape; new `@visibleForTesting restoreFreezesForTest(userId, preFetched:)` for the
PRODUCTION order (progress then freezes, local `{2,'09-28'}` × cloud `{1,'09-21'}` ⇒ final `{2,'09-28'}`; pre-fix `{1,'09-21'}`),
and an assertion on `SyncStubServer.requests` for `/rest/v1/rpc/update_streak_progress` — exactly ONE call in the stale-cloud case, ZERO in
the steady state; this is OBSERVABLE only because of the §3 U2.5a `_liveUserId` seam (the stub answers an RPC with `null`, which routes into
the retry GET, `sync_stub_server.dart:189-191`; `readReplies` serves GETs only). The bootstrapper caller is source-pinned (network-bound,
labelled presence-only). **Mirror rows are labelled:** cross-device consume, cross-device refill, fresh reinstall, the non-numeric row and
the kill-switch mirrors already PASS pre-fix by design (they pin what the new code must NOT change). The mutation neuters the post-pass
(restores the loop copy) and the record says WHICH rows redden for WHICH mutation (stale-cloud row, grant-carry rows, F4/flag rows, the push
count, the owner guard each get their own mutation; a compile-error redden does not count). Hazard: the post-pass uses index assignment
only (§3 U2.5b).

`test/contracts/streak_reckon_restore_settled_behavioral_test.dart` (Unit 1; real Hive via `setUpHiveForTests`, which opens a
session for `kTestUserId` and sets `GuardedBox.testBypassOwnership`; uid via `HiveUserSession.debugCurrentUidResolverForTests`;
touch `SyncService.instance` first so its constructor registers `_onUserChanged`; not in a file that calls
`SingletonLifecycleRegistry.resetForTesting`):
T1 `RestoreFailureCollector` + `restoreSettlesStreak` (a note inside `run` records an allowlisted opType; ignores `restore_sync_weight`
and non-allowlisted; ignores a note OUTSIDE the zone; two concurrent `run`s are isolated; a note after the awaited body but before
return is recorded);
T2 marker = A = live uid, **tick pinned to 0**, missed day ⇒ the reckon PERSISTS (available, `used_dates`, `streak_freeze_just_used`)
— this is also the foreground-restored-process case (the old gate never opened there);
T3 marker = A, live uid = B, tick > 0 ⇒ NO persist (the F2 repro; fails pre-fix) — built WITHOUT `openForUser(B)`; T3b a separate test
calls `SingletonLifecycleRegistry.notifyUserChanged()` with marker set and uid unchanged ⇒ marker cleared (mutation: remove the clear
⇒ red); T3c tick > 0 and marker null ⇒ NO persist (the F1 cold-start repro);
T4 `reckonAndNotifyAfterRestore`: marker set, missed day, a tick listener records `streak_freezes_available` AT CALLBACK TIME ⇒ already
debited (mutation: bump-before-reckon ⇒ red); T4b marker false ⇒ no persist, tick still bumped, the withheld event carries the reason;
T5 a REAL op failure through the real funnel, per op family: `restoreFreezesForTest` with a malformed `preFetched` (a `String`, so
`rawRes as Map` throws inside the swallowing try) inside `RestoreFailureCollector.run` ⇒ the sink contains `restore_freezes` ⇒
`restoreSettlesStreak` false; the same with the existing seams `restoreUserProgressForTest`, `restoreWorkoutPlanForTest`,
`restoreUserProfileForTest`, `restoreScheduledWorkoutsForTest` and a malformed payload ⇒ `restore_user_progress`, `restore_workout_plan`,
`restore_user_profile`, `restore_scheduled_workouts` (the stub's `readReplies` is per TABLE, so one table cannot fail the three
`user_progress`-family ops separately — the seams do) (mutation: capture only in `_safeRestoreOp`'s catch ⇒ red; safe in unit tests —
`kDebugMode` skips Crashlytics, `ensureFreshToken` throws inside the funnel's try); T6 kill switch ⇒ pre-fix tick gate verbatim;
**T7 through the real `restoreFromCloudForUser()`, LEGACY FAN-OUT ONLY** under `SyncHarness` + `SyncStubServer` (round 3: the harness's
`SupabaseService` has no session, so `_attemptSingleCallRestore` faults at `supabase_service.dart:395-416` and the catch at
`sync_service.dart:2294-2304` falls to the legacy path; the stub's `/functions/` reply is never reached — the single-call path is covered
by T8's static enumeration and by the same funnel): (a) all reads OK ⇒ marker == uid (with the default `[]` replies every critical op
returns silently); (b) `readReplies['scheduled_workouts']` = 500 ⇒ marker null and the failures include `restore_scheduled_workouts`;
(c) a failing `weight_logs` read (non-allowlisted) ⇒ marker still set; (c2) a failing `workout_templates` read ⇒ marker null with
`restore_deleted_template_ids` in the failures (driven through the seam that reaches `sync_workout.dart:1432`/`:2325`; verified at
implementation); (e) a failed restore / cancelled ⇒ marker null (mutation: wrapper
never sets the marker ⇒ T7a red). **T7d is REPLACED by T10:** an end-to-end swap becomes `cancelled` first, so the two uid clauses of the
settle decision are not reachable from the stub;
**T10 `shouldSettleRestoreMarker` unit table** (pure, mirrors `shouldHealAfterRestore`): one row per clause — result not succeeded, a
non-empty `failures`, `uid == null`, `liveUid != uid`, `ownerUid != uid`, all true ⇒ true — and a mutation per clause (drop each ⇒ its row reddens; all FIVE conjuncts were mutated, N6a-e);
**T8 forcing function** (precedent `kNotSweptOpTypes`): enumerate every `_safeRestoreOp\(\s*'(\w+)'` — the regex MUST tolerate the
newline between the call and its label (15 calls in `sync_service.dart` put the label on the next line, among them four critical labels
that appear only in that form in `_attemptSingleCallRestore`: `user_profile` `:2154`, `scheduled_workouts` `:2217`, `schedule_completions`
`:2221`, `freezes` `:2243`) in BOTH `_restoreFromCloudForUserCore` and `_attemptSingleCallRestore`; require all seven critical labels to
be FOUND in both (a vacuous scan must fail), and `restore_<label>` ∈ `kStreakCriticalRestoreOpTypes` or an explicit non-critical set; plus
a per-op presence pin that `_reportSyncFailure(opType: 'restore_<x>'` exists under `lib/core/services/sync/**` for each of the seven, so
a future op that feeds the streak walk, or a renamed spelling, cannot silently not gate;
T9 source pins (PRESENCE only, labelled): `heal_after_restore.dart` calls `reckonAndNotifyAfterRestore` after `refillIfNewWeek` and no
longer calls `bumpRestoreCompleted` directly; `reckonAndNotifyAfterRestore` bumps last; `home_screen.dart` overrides
`invalidateOnBackgroundRestore` and calls `_checkStreakFreezeUsed`; `_reportSyncFailure`'s first statement is `RestoreFailureCollector.note`.

Existing tests repointed, never loosened: `streak_decay_reckon_permanent_ledger_test.dart` — the three tests that set the tick
(`:174-185`, `:193-219`, `:221-232`) open the NEW gate (marker + uid); `:149-159` and `:234-243` assert the gate is OFF, so they keep the
marker null and set tick = 1 (they now FAIL pre-fix); only `:161-172` (empty schedule) gets a set marker so its gate is the thing
under test; header `:10-13` and `setUp/tearDown` `:41,45` reset marker and uid. `background_restore_test.dart:166-175` repointed to
the new call and its order. `completed_title_follows_log_test.dart` `:313` comment, and its `:344-379` pins must keep passing against
the §3 U1.3 wrapper. `sync_service_public_api_snapshot_test.dart` `expectedPublicApi` gains the new `void`/`Future` members
(`debugSetRestoreSettledUserIdForTest`, `restoreFreezesForTest`; `restoreSettledForCurrentUser` is a `bool get`, excluded by its
regex). `profile_provider_single_source_test.dart:206-232` stays green with the Home override (it uses probe tabs). The `blast_radius_*`
platform tests are re-run — the new part file sits under `sync/**` (`blast_radius_sync_engine_platform_test.dart:396` enumerates
`sync/.+`; `:480-496` derives `part` files from `sync_service.dart`, so the `part '…collector.dart';` line is added there). Hazard tests
listed in §2 (`restore_after_session_open_test.dart`, the two-reference count, `restore_progress_uses_shared_merge_test.dart`, the
sole-writer contract, the retry-controller window) are re-run unedited.

## 5. Process gates (listed upfront)

Plan review ×2+ (record `docs/plan-reviews/claude-avya-streak-data-check-b506de.md`: `---` frontmatter with
`branch: claude/avya-streak-data-check-b506de`, `blast_radius: platform`, `review_rounds`, `ground_truth_verified: true`, bare
`verdict: converged`, `bpass: accepted` **and `bpass_review: docs/reviews/<id>-review.md`** — that file must exist in the commit and carry a
line-anchored `verdict: accepted`) → implement inline (Unit 2, then Unit 1) → `flutter analyze lib/` before every reviewer dispatch +
targeted tests → one mutation cycle per unit with a SCRATCH-COPY protocol (copy first, mutate, run, restore from the copy, `grep -c` the
mutation applied, compare file hashes to the copy — NOT `git diff`, which cannot be empty over uncommitted fixes) → full gate loop
(`flutter analyze lib/`, `flutter test` with `TZ=Asia/Kolkata`, `sh scripts/pre-commit.sh` or an attempted commit) → self-triggered
`/code-review` B-pass (two fresh reviewers) before any merge; **adding `docs/reviews/<x>-review.md` also requires a same-dated entry
in `.claude/skills/code-review/tuning-history.md`** (`check_skill_tuning_history`) → diagnose docs `b4e7a1` (Unit 1: F1, F2, F5) and
`c9d2f6` (Unit 2: F3, F7), each cited by `closes-diagnose:`, each with `touched_layers_checked` → SoT registry (`streaks` /
`streak_freeze_*`: marker + freeze merge rule, each with a `behavioral_test_path:`, Gate 42) and **re-check every cited `line_range`**
(stale ranges are an ERROR; numeric ranges exist for `sync_service.dart` (14), `sync_profile.dart` (7), `user_repository.dart` (5),
`auth_session_bootstrapper.dart` (5), `sync_restore_completeness.dart` (3), `day_rollover_service.dart` (3) — all of which this batch edits;
`streak_progress_service.dart` is NOT edited) → **one commit per unit** (Unit 2, then Unit 1), each with ONE `closes-diagnose:` trailer —
the `commit-msg` hook validates only the FIRST one (`commit-msg.sh:99`, `head -1`) — each commit self-consistent (Unit 2 alone is the safe
half; Unit 1 is never shipped without it) → `docs/naming_conventions.md` append (§4.7: restore-settled marker,
`RestoreFailureCollector`, `streak_reckon_withheld`, `progress_restore_freeze_merge_engaged`, the two kill switches) → closure YAML
`docs/audit/streak-freeze-restore-ownership.closure.yaml` (§3 table; ≥4 findings ⇒ Gate 40; commit shas only at commit time) →
**OIs minted with `sh scripts/mint_oi.sh` at commit time** (one ref-push each; the founder's explicit go for the commit/push step covers
it): restore latency (F6), freeze spend rule + notice wording (F8), the weeks-reset-on-daily-break feature idea (founder decision A made the weeks restore-safe; the one-freeze ledger refund was declined, so no OI for it) — and OI-279/OI-293/OI-294 text updated → skill update (§5.1: ONE index row in `SKILL.md` ≈ 400 B, body in the
git-tracked-but-unbudgeted `bug-classes.md`, the stale red flag at `SKILL.md:247` corrected IN PLACE; `SKILL.md` is 55,956 B against a
57,141 B soft ceiling, headroom 1,185 B) → context-artifact budget (`dart run scripts/check_context_artifact_budget.dart`, §5 row):
**`docs/audit/OPEN_INDEX.md` is 31,767 B against a 32,221 B soft ceiling (454 B headroom; hard 42,028)** — four minted OIs (~180-250 B
each) cross the SOFT band (WARN, silent locally), so re-baseline with `--record` after minting (it refuses over a hard breach without
`--force-record`); `lib/core/services/CLAUDE.md` (22,394 B, ceiling 24,619) and `open_issues.md` (504,008 B, ceiling 550,261) have
room; `lib/features/home/CLAUDE.md` and `bug-classes.md` are unbudgeted → the §5 checklist rows the batch-close hook asks about (memory retrospective, worktree retirement). **No commit, push, APK or
live apply** without the founder's explicit word (§4.3). Device verification is the founder's (§5 last row).

## 6. Review history and what round 4 already confirmed (so the implementation does not re-derive it)

Round 4 (delta-only, on v4) CONFIRMED, with file:line evidence: the asymmetric/grant-carry table reproduces against the real
`mergeFreezeProgress`; `grant_done = local || cloud` is safe with `grantFirstProFreezes` and its transition-only trigger; no push loop or
storm (the flag is pushed by `syncFreezes`'s upsert, the RPC has no flag parameter); `null ?? _supabase.currentUser?.id` is byte-identical to
the old expression in production and no test pins `sync_restore_completeness.dart:36` / `sync_service.dart:1884,:2140`; the wiring-test
regexes (`cross_device_progress_optimistic_lock_wiring_test.dart:64-65,77,94,117`) are unaffected; the CQRS getter gate, the public-API
snapshot regex (`bool get` / `String? get` / `static` excluded), `completed_title_follows_log_test.dart:344-379` and
`restore_after_session_open_test.dart:44-71` all hold for the planned wrapper; T8's newline-tolerant regex is right (15 next-line labels,
four critical ones only in that form); every terminal-state row passes the validator's token and key checks. It found two P1s (the
symmetric carry, the owner guard's fixtures) and six P2s — all resolved in v5 as §0a item 7 records.

v5 is therefore the plan of record. The ≥platform B-pass (two fresh reviewers on the implemented diff) is the next independent review.
