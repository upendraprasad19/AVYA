# Agent 6 Findings — Clusters 7, 11, 12 (Cross-screen flow · Concurrency · Provider invalidation)

**Date:** 2026-05-16

## Cluster 7 — Data flow traces (5 canonical actions)

### Trace 1: Train — Complete Workout
- Entry: `train_provider.completeWorkout` not found by Agent's grep — actual path routes through `WorkoutWriteService.markCompleted` (L333). **Phase C: verify Agent's grep was correct or `completeWorkout` is named differently.**
- Hive: writes `wlog_<istDateStr>`
- Sync: `unawaited(SyncService.instance.syncWorkoutData())` + `pushSnapshot()` at L193
- Provider invalidations: via `onInvalidate` callback at L198, but callback is NULL in service initialization (L49). **CLAIM: no provider invalidations execute on completion.** Phase C must verify whether onInvalidate is wired by a caller after construction.

### Trace 2: Train — Edit Completed Log — PASS
- Entry: `EditWorkoutLogSheet._save` L88
- Routes correctly through `WorkoutWriteService.editLog` L232
- Explicit invalidation batch at L251-256: 6 of 8 required providers (see C12-1)

### Trace 3: Nutrition — Log Meal via AI Text — PASS
- Entry: `AiBreakdownNotifier.saveMeal` L883
- Routes through `NutritionWriteService.logMeal` L883
- Sync + invalidation via service internal `_invalidateNutritionProviders()` L133

### Trace 4: Nutrition — Scan Meal via Camera — PASS
- Entry: `ScanMealNotifier.scanImage` L1289
- Counter increments at API-call site (Test #11 M1 pattern) L1317-1320
- Save path delegates to `FoodLogNotifier.logFood` → `NutritionWriteService.logMeal` — same as Trace 3

### Trace 5: AI Coach `logMealByText` — PASS
- Entry: `tool_dispatcher._executeLogMealByText` L1108
- `_writeFoodLogFromIntent` calls `NutritionWriteService.logMeal` L1329
- Counter increment L1149 (matches UI pattern)
- **NO shadow tables.** AI coach writes via identical canonical service as UI.

**Cross-path verification:** UI and AI tool both call identical `NutritionWriteService.logMeal(items[], date, mealType)` → same Hive key computation → same cloud projection. ✅

## Cluster 11 — Concurrency findings

### C11-PASS: WorkoutWriteService mutex coverage
All 4 mutation methods (logExercise L85, editLog L603, deleteLog L742, markCompleted L348) acquire `_acquireLock(lockKey)`. Key shape `<istDateStr>::<exerciseName.toLowerCase()>` for logExercise/editLog/deleteLog; date-only for markCompleted (coarser, intentional).

### C11-PASS: HiveUserSession._sessionLock — POSSIBLY incomplete
- `openForUser` L136 wrapped in lock ✅
- `_closeAllLocked` exists as helper ✅
- Agent could not find `closeAll` or `clearAll` method — **Phase C must verify if these are required or renamed/removed.**

### C11-PASS: authUserIdTokenProvider — 63 references across `lib/features/`
Spot-check confirmed in `nutrition_provider.dart` L1076, L1451, L1499 and `train_provider.dart` L1528-1533. **Phase C should run a comprehensive grep against the 56 user-scoped providers list to verify full coverage.**

### C11-PASS: wrapUserScopedBox enforcement — clean
No raw `Hive.box(<userScopedName>)` calls outside the allowed wrapper.

### F11-C11-2 — CONFIRMED_BUG: WorkoutScheduleService bypasses WorkoutWriteService
- Evidence: `lib/core/services/workout_schedule_service.dart` writes directly via `workoutBox.put()` at L248, L412, L717, L844, L855, L1159, L1302, L1430 (8+ callsites) — for schedule mutations (generate, clean-sync, reschedule).
- CLAUDE.md §15 allowed direct-writers list: `WorkoutWriteService`, `NutritionWriteService`, `HiveService`, `SyncService`, `UserConfigMigrator`, `ExlogKeyMigrator`. `WorkoutScheduleService` is NOT on the list.
- **Why:** Schedule mutations don't fire `syncWorkoutData()` or provider invalidations from a canonical writer, so AI coach context goes stale after every schedule change. Same as Sleep/Measurements bypass class.
- **Remediation:** Either (a) add `WorkoutScheduleService` to the allowed list in CLAUDE.md §15 + ensure it explicitly fires sync + invalidations after every put, or (b) extract schedule writes into `WorkoutWriteService.upsertScheduled` (already exists L427) and route the service through it.

## Cluster 12 — Provider invalidation findings

### F12-C12-1 — CONFIRMED_BUG: Edit workout log sheet missing 2 invalidations
- Evidence: `edit_workout_log_sheet.dart:251-256` invalidates 6 providers (currentPlan, workoutStats, calendarWeek, streak, todayWorkout, allExercisePRs). MISSING: `aiInsightProvider` (required per CLAUDE.md §19 / APK Test #2 / F5) and `dietPlanProvider` if applicable.
- **Why:** AI insight card on Home will show stale insight after workout edit until day rollover or app restart.
- **Remediation:** Add `ref.invalidate(aiInsightProvider)` to the edit save handler.

### F12-C12-2 — CONFIRMED_BUG: NutritionWriteService doesn't invalidate aiInsightProvider
- Evidence: `_invalidateNutritionProviders()` at `nutrition_write_service.dart:133` doesn't include aiInsightProvider in its invalidation set. (Agent didn't fully read; Phase C verify.)
- **Why:** Same as F12-C12-1 but for nutrition mutations. AI insight stale.
- **Remediation:** Add to invalidation set.

### F12-C12-3 — CONFIRMED_BUG: WorkoutScheduleService has zero invalidations
- Evidence: All 8+ direct `workoutBox.put` callsites in `workout_schedule_service.dart` (per F11-C11-2) lack any subsequent provider invalidation.
- **Why:** Calendar UI, plan provider, today provider all serve stale data after schedule changes (template assignment, days/week change, regenerate).
- **Remediation:** Same fix as F11-C11-2 (route through WriteService) closes this automatically.

### F12-C7-1 — CLAIMED_BUG: WorkoutWriteService.onInvalidate callback null
- Evidence: `workout_write_service.dart:49` assigns `onInvalidate` callback field but Agent claims it's never wired. L198 invokes `onInvalidate?.call()` — if never set, every mutation invalidates nothing.
- **Phase C VERIFICATION REQUIRED:** Read `workout_write_service.dart` end-to-end + grep for `onInvalidate =` to find caller. If truly unwired, this is THE WORST bug found so far — every workout mutation since Test #6 would silently fail to invalidate. But editLog mutations DID work per Trace 2 (the widget itself invalidates), so the callback may be redundant/dead code, not a bug.

## Verification priorities for Phase C

1. **HIGH:** F12-C7-1 — verify `onInvalidate` truly unwired vs. dead-code-but-not-load-bearing
2. **HIGH:** F11-C11-2 — read `workout_schedule_service.dart` directly to confirm 8+ direct puts + verify they don't internally fire sync
3. **MEDIUM:** F12-C12-1/F12-C12-2 — verify aiInsightProvider is the only missing invalidation
4. **LOW:** Trace 1 — verify `completeWorkout` actual entry point name (Agent's grep returned nothing)
