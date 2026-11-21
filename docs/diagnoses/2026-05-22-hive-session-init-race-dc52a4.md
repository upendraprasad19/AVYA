---
bug_id: dc52a4
date: 2026-05-22
batch: APK Test #16.2 +30 obs 5-12 batch (commit 1 / Theme A)
status: shipped
symptom: |
  Founder install of APK Test #16.2 +30 on 2026-05-20. Telemetry pulled
  2026-05-21 showed `day_rollover_streak_freeze_refill` failing with
  "Bad state: HiveUserSession not opened — cannot wrap user-scoped box
  'userBox'." on EVERY trigger since at least 2026-05-06. Three
  telemetry op_types that SHOULD fire as a result of that rollover were
  ZERO in the 7-day window: `streak_freeze_refill_check`,
  `streak_freeze_refill_done`, `streak_freeze_consume_done`. The Monday
  +1 streak freeze never executed — universally, every user, every cold
  start. Same race killed `splash_just_used_clear`. The earlier obs 1+2
  batch +28 shipped layers B3 (cold-start just_used clear) + B0b
  (post-restore refillIfNewWeek via splash._restoreSub listener) which
  BOTH were dead code: B3 failed the race; B0b never fired because
  splash disposes within ~3s of mount, long before the
  restoreFromCloudForUser future emits (~36s for founder).
concept: hive_session_init_race
sot_registry_entry: streaks
writers:
  - { file: lib/features/auth/screens/restoring_screen.dart, method_or_widget: _ensureOwnershipBeforeHome now owns the post-openForUser bootstrap (just_used clear + runRolloverNow + refillIfNewWeek), line: 145 }
  - { file: lib/core/services/streak_progress_service.dart, method_or_widget: StreakProgressService.refillIfNewWeek (idempotency gate unchanged), line: 115 }
readers:
  - { file: lib/features/home/screens/home_screen.dart, method_or_widget: _checkStreakFreezeUsed reads streak_freeze_just_used, line: 99 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: StreakFreezeNotifier.build reads streak_freezes_available, line: 252 }
hive_key_prefix: "user_progress (Hive map under userBox)"
hive_key_formula: "userBox['progress'] map keys streak_freezes_available, streak_freeze_used_dates, streak_freezes_last_refill, streak_freeze_just_used"
sync_methods: [syncFreezes]
restore_methods: [restoreFromCloudForUser]
cloud_table: user_progress
cloud_columns: [streak_freezes_available, streak_freezes_used_dates, streak_freezes_last_refill]
contract_test_path: test/contracts/splash_no_userbox_touch_test.dart
ist_handling:
  - { file: lib/core/services/streak_progress_service.dart, line: 116, source: mondayOfIst correctly used for refill boundary (unchanged) }
provider_invalidations: [streakFreezeProvider, streakProvider, allExercisePRsProvider, currentPlanProvider, workoutStatsProvider, calendarWeekProvider, todayWorkoutProvider]
telemetry_op_types:
  success: [streak_freeze_refill_check, streak_freeze_refill_done]
  failure: [restoring_just_used_clear, restoring_run_rollover_now, restoring_post_restore_refill, day_rollover_streak_freeze_refill]
cross_account_guard: HiveUserSession.openForUser called inside SyncService.restoreFromCloudForUser (sync_service.dart:804). The new bootstrap block runs AFTER that call, post-openForUser, so user-scoped boxes are guaranteed open.
forbidden_patterns_checked:
  - "Splash userBox reads via UserRepository.instance.getProgress / updateProgress — contract test test/contracts/splash_no_userbox_touch_test.dart enforces absence."
  - "Splash invocation of DayRolloverObserver.runRolloverNow or StreakProgressService.refillIfNewWeek — same contract test."
  - "Splash subscription to SyncService.onRestoreComplete — dead code, contract test pins absence."
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "splash_screen.dart: removed dead listener + just_used clear + rollover call (~40 lines); restoring_screen.dart: added 3-block bootstrap to _ensureOwnershipBeforeHome (~50 lines)" }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "no Hive contract change; the same userBox['progress'] keys are touched, just from the correct call site" }
  - { tier: 5, name: cloud_sync_outbound, status: verified, evidence: "refillIfNewWeek's fire-and-forget syncFreezes() unchanged" }
  - { tier: 6, name: cloud_sync_restore, status: verified, evidence: "max-merge _restoreFreezes (obs 1+2 batch +28) unchanged and remains canonical" }
  - { tier: 9, name: provider_invalidation, status: verified, evidence: "runRolloverNow inside the new block invalidates the canonical today-providers set" }
  - { tier: 11, name: ist_correctness, status: verified, evidence: "mondayOfIst usage in refillIfNewWeek unchanged" }
  - { tier: 12, name: end_to_end_contract, status: fixed_in_this_batch, evidence: "test/contracts/splash_no_userbox_touch_test.dart pins absence + presence on both files" }
impact_analysis:
  callers_audited:
    - lib/features/auth/screens/splash_screen.dart (deferred init)
    - lib/features/auth/screens/restoring_screen.dart (_kickoffRestore → _ensureOwnershipBeforeHome)
    - lib/core/services/day_rollover_service.dart (runRolloverNow)
    - lib/core/services/streak_progress_service.dart (refillIfNewWeek)
    - lib/core/services/sync_service.dart (restoreFromCloudForUser opens HiveUserSession at line 804)
  callers_updated_in_this_batch:
    - lib/features/auth/screens/splash_screen.dart (removed dead listener + just_used clear + rollover call)
    - lib/features/auth/screens/restoring_screen.dart (added the 3-block bootstrap)
  callers_unchanged:
    - lib/core/services/day_rollover_service.dart (semantics preserved; just moved the invocation site)
    - lib/core/services/streak_progress_service.dart (refillIfNewWeek logic untouched; now finally able to actually execute)
proposed_fix: |
  Move three userBox-touching pieces of bootstrap off splash and onto
  RestoringScreen._ensureOwnershipBeforeHome:

  (1) The `streak_freeze_just_used` cold-start clear.
  (2) `DayRolloverObserver.runRolloverNow(ref)`.
  (3) `StreakProgressService.refillIfNewWeek()` as defence-in-depth on
      top of the obs 1+2 max-merge _restoreFreezes fix.

  Plus delete the dead `_restoreSub` listener that lived in
  splash.initState — it subscribed to onRestoreComplete but splash
  always disposed before the future emitted, so it never fired.

  The natural landing zone is the end of
  `_ensureOwnershipBeforeHome`, just after the exlog + nlog migrator
  blocks. HiveUserSession.openForUser has already run (inside
  restoreFromCloudForUser called at line 63 of _kickoffRestore), so
  user-scoped boxes are guaranteed open.

  Splash retains: SupabaseService.initialize, SeedService.seedIfNeeded
  (writes only to user-scope-free boxes — exerciseBox, foodBox),
  HealthSyncService.syncToHive (its own session bootstrap),
  fire-and-forget checkAndSync / RankService / SubscriptionService
  refresh / SyncQueue drain / OneSignal init / notification inbox.
regression_test_planned:
  - test/contracts/splash_no_userbox_touch_test.dart — pins (a) absence of UserRepository.getProgress / updateProgress / DayRolloverObserver.runRolloverNow / StreakProgressService.refillIfNewWeek / onRestoreComplete.listen calls in splash_screen.dart, (b) presence of the same calls in restoring_screen.dart.
---
# Body

## Why splash was the wrong place

The C-6 comment at splash_screen.dart:127-134 ALREADY documented the
constraint:

> The cross-account guard previously lived here and was a no-op:
> `HiveService.instance.userBox` is a GuardedBox that throws
> `HiveUserSession not opened` at this point in cold start
> (no `openForUser` has run yet).

But over the subsequent months the team's code drifted. The B3
just_used clear (added 2026-05-19 in obs 1+2 batch +28) touched
userBox. The DayRolloverObserver.runRolloverNow call internally
touches userBox via StreakProgressService.refillIfNewWeek. Both
swallowed the resulting "HiveUserSession not opened" exception in
their try/catch — silently failing while looking healthy in normal
debug output.

The telemetry pulled 2026-05-21 surfaced the failure: every
`day_rollover_streak_freeze_refill` op_type fired with the exception,
and the three downstream op_types (refill_check / refill_done /
consume_done) were ZERO across a 7-day window.

## Why the obs 1+2 B0b layer was dead code

The "post-restore refillIfNewWeek via splash._restoreSub listener"
layer subscribed to SyncService.onRestoreComplete in splash.initState
and called `_restoreSub?.cancel()` in dispose. Splash navigates to
/restoring within ~3 seconds of mount; restoreFromCloudForUser takes
~36 seconds. By the time the broadcast stream emits, splash is gone
and its StreamSubscription is cancelled. The listener never fires.

The intent of B0b — re-invoking refillIfNewWeek post-restore as
defence-in-depth — was correct; the location was wrong. The new
RestoringScreen call site is the same code path post-openForUser,
running before /home navigation, so the same defence-in-depth lands.

## What's NOT changed

- `_restoreFreezes` max-merge logic from obs 1+2 / 9c4a17 is intact
  and remains canonical for cloud → Hive merge.
- `StreakProgressService.refillIfNewWeek` itself is byte-identical.
- `DayRolloverObserver.runRolloverNow` is byte-identical.
- The canonical "today provider" invalidation set inside runRolloverNow
  is unchanged.
- IST math is unchanged.

## Manual smoke proof point

After install of +31, the founder's `client_errors` should show a
`streak_freeze_refill_check` row on the first cold start (with
willRefill=true if it's the first Monday since install, or
willRefill=false otherwise — but emitted in both cases). This row's
existence is the proof Theme A landed.
