# sync_service.dart Part-File Split — Design Spec

**Date:** 2026-05-13
**Branch:** `refactor/sync-service-part-split`
**Owner:** Upendra
**Audit origin:** `docs/audit/2026-05-11/cleanup-batch-triage.md` item B-5 (Hermes R2 — flagged as #1 refactor risk, deferred to batch with real APK ship cycle).
**Diagnose-doc:** N/A — refactor commits do not match CLAUDE.md rule 22's `^(fix|bug|regression):` regex.

---

## 1. Problem

`lib/core/services/sync_service.dart` is **5,104 lines** in a single class (`SyncService`) with ~95 methods spanning 10 distinct responsibilities. The file has grown +532 lines (4,572 → 5,104) since the audit two days ago. It is the most-frequently-edited file in the codebase per writer/reader-drift bug class incidents (Tests #6 → #15.4 every batch has touched it), and the canonical SoT for cross-device data correctness.

Concrete symptoms:

- **Cognitive overload during review.** Domain-mixed reads (workout sync at L1323 vs workout restore at L2762) force constant scroll-jumping. The Test #15.3 / Bug 4a fix touched two methods 1,500 lines apart in the same diff.
- **Bug-class concentration.** Writer/reader drift is the recurring failure mode (per `feedback_writer_reader_field_drift_recurring.md`); the existing structure puts the writer and reader in the same class but on opposite ends of the file, so review eyeballs rarely cross-check the pair.
- **Refactor freeze.** Hermes audit R2 declared further changes carry escalating risk because the file is dense enough that touching one method risks invisible regression in distant call paths.

Goal: split the file into per-domain part files so that the writer and reader for any one surface live side-by-side, and infrastructure / helper / orchestration concerns live in their own files. **Zero behavior change.** Public API and instance state are preserved exactly.

## 2. Non-goals

This refactor explicitly does NOT:

- Change any public method on `SyncService`. Every `SyncService.instance.X()` callsite continues to work unmodified.
- Change any sync semantics, idempotency rule, restore order, or error handling.
- Add or remove functionality. New tests are exclusively API-snapshot locks.
- Introduce new abstractions (no `SyncContext`, no per-domain repository classes, no dependency injection rewrite). Those are separate decisions for a future batch if needed.
- Migrate to constructor injection or break the singleton pattern.
- Touch any callsite outside `lib/core/services/sync_service.dart` and its new part files.

## 3. Locked decisions

| # | Decision | Choice |
|---|---|---|
| 1 | Split axis | **By domain**, writer + reader for each surface live in same file |
| 2 | Mechanism | **Dart `part` / `part of` directives** — single library, multiple files |
| 3 | API preservation | All public method names + signatures unchanged. Contract tests `sync_fanout_contract_test.dart` + `restore_completeness_writes_test.dart` stay green at every commit |
| 4 | State preservation | Singleton, all instance fields, all static helpers remain on `SyncService`. Parts access via library-privacy |
| 5 | Order | Lowest-risk pilot first, biggest + infrastructure last. 10 commits total. |
| 6 | Ship cadence | Single feature branch, all 10 commits land progressively, single `--no-ff` merge to `main`, single `/build-apk` ship cycle |
| 7 | Gate between commits | `flutter analyze` 0 errors/warnings + `flutter test` 1706/0/2 unchanged at every commit |
| 8 | API lock test | New `test/contracts/sync_service_public_api_snapshot_test.dart` lands as commit 0 before any extraction begins |

## 4. Target file layout

```
lib/core/services/
  sync_service.dart                    [LIBRARY ROOT — ~500-700 lines after refactor]
    - `RestoreResult` class (or moves to sync/ if cleanest)
    - top-level `_coerceInt` helper
    - `class SyncService` declaration + singleton + ALL instance fields
    - Orchestrator methods that fan out across domains:
        checkAndSync, pushSnapshot, weeklyFullSync,
        restoreFromCloud, restoreFromCloudForUser, _restoreIfNeeded,
        restoreLightweightAlways, _replayPendingOnboardingSync,
        _syncFitnessSummary, pullRecentCrossChannelLogs,
        _pullWeightLogs, _pullNutritionLogs, _pullMeasurements
    - `part 'sync/sync_<domain>.dart';` declarations (10 total)
  sync/
    sync_workout.dart                  [~1,200 lines]
    sync_nutrition.dart                [~600 lines]
    sync_health.dart                   [~500 lines]
    sync_profile.dart                  [~400 lines]
    sync_community.dart                [~500 lines]
    sync_coach.dart                    [~400 lines]
    sync_restore_completeness.dart     [~280 lines]
    sync_realtime.dart                 [~150 lines]
    sync_infrastructure.dart           [~600 lines]
    sync_helpers.dart                  [~50 lines]
```

Each part file starts with `part of '../sync_service.dart';` and contains its share of `SyncService` methods. Library-private state (`_realtimeSubscription`, `_restoreCompleteController`, queue state, JWT helpers) remains accessible because all files share one library.

### Per-domain contents

| Part file | Methods (sync / restore / helpers) |
|---|---|
| `sync_workout.dart` | `_syncWorkoutLogs`, `_syncExerciseLogs`, `_syncScheduleCompletions`, `_syncWorkoutTemplates`, `_syncScheduledWorkouts`, `_syncWorkoutPlan`, `_syncStreaks`, `_restoreWorkoutLogs`, `_restoreExerciseLogs`, `_restoreScheduleCompletions`, `_restoreStreaks`, `_restoreWorkoutPlan`, `_restoreWorkoutTemplates`, `_restoreScheduledWorkouts`, `syncWorkoutData`, plus `_resolveCompletedAt` + `_dateFromKey` helpers |
| `sync_nutrition.dart` | `_syncNutritionLogs`, `_syncWaterLogs`, `_syncSavedMeals`, `_restoreNutritionLogs`, `_restoreWaterLogs`, `_restoreSavedMeals`, `syncNutritionData`, `syncSavedMealsNow`, plus `_nlogKeyForRestore` helper |
| `sync_health.dart` | `syncWeightNow`, `syncSleepNow`, `syncMeasurementsNow`, `_syncWeightLogs`, `_syncMeasurements`, `_syncSleepLogs`, `_syncStepsLogs`, `_syncUrineColorLogs`, `_restoreWeightLogs`, `_restoreMeasurements`, `_restoreSleepLogs`, `_restoreStepsLogs` |
| `sync_profile.dart` | `syncProfileNow`, `_syncUserProfile`, `_syncUserPreferences`, `_syncUserProgress`, `syncProgressNow`, `_restoreUserProfile`, `_restoreUserProgress`, `_restoreUserPreferences` |
| `sync_community.dart` | `_syncCustomItems`, `syncCustomItemsNow`, `syncCommunityItems`, `_restoreCustomExercises`, `_restoreCustomFoods`, plus `_customEntityId` + `_backfillCustomEntityIds` helpers |
| `sync_coach.dart` | `syncCoachMemoryNow`, `_syncCoachInteractions`, `_restoreCoachInteractions`, `_restoreCoachMemory` |
| `sync_restore_completeness.dart` | `syncFreezes`, `syncNotificationsInboxEntry`, `syncSavedDietPlan`, `_restoreFreezes`, `_restoreNotificationsInbox`, `_restoreSavedDietPlan`, `_restoreRankPromotions` |
| `sync_realtime.dart` | `subscribeToRealtimeSync`, `_attachRealtimeStream`, `_reconnectRealtimeWithRefreshedJwt`, `unsubscribeRealtime` |
| `sync_infrastructure.dart` | `initQueue`, `_sendDeadLetterTelemetry`, `drainTelemetryQueue`, `_enqueueTelemetryFailure`, `_reportSyncFailure`, `reportSyncFailure`, `_safeRestoreOp`, `_currentPlatform`, `_currentClientVersion`, `_ensureSessionOpen`, `cancelInflightRestore`, `_setTimestamp`, `_getTimestamp` |
| `sync_helpers.dart` | `_deterministicId`, `_looksLikeUuid`, `_hasValue`, `_hasNumber` (all `static` on `SyncService`) |

## 5. Execution sequence

Each step is one commit. Each commit must pass `flutter analyze` (0/0) and `flutter test` (1706/0/2 unchanged) before the next begins. If a step fails, revert that commit and diagnose before continuing.

| Commit | Description | LOC moved | Risk |
|---|---|---|---|
| 0 | Add `test/contracts/sync_service_public_api_snapshot_test.dart` locking the exact sorted list of public method names on `SyncService` | +1 test | None — additive |
| 1 | Create `lib/core/services/sync/` directory + extract `sync_restore_completeness.dart` (PILOT — validates `part` mechanism) | ~280 | LOW |
| 2 | Extract `sync_realtime.dart` (validates parts can access stateful library-private fields like `_realtimeSubscription`) | ~150 | LOW |
| 3 | Extract `sync_coach.dart` | ~400 | LOW |
| 4 | Extract `sync_community.dart` + co-extract `_customEntityId`, `_backfillCustomEntityIds` | ~500 | LOW |
| 5 | Extract `sync_health.dart` | ~500 | LOW |
| 6 | Extract `sync_profile.dart` | ~400 | LOW |
| 7 | Extract `sync_nutrition.dart` + co-extract `_nlogKeyForRestore` | ~600 | MED |
| 8 | Extract `sync_workout.dart` + co-extract `_resolveCompletedAt`, `_dateFromKey` | ~1,200 | MED |
| 9 | Extract `sync_infrastructure.dart` (queue + telemetry + dead-letter + session) | ~600 | MED |
| 10 | Extract `sync_helpers.dart` (pure static helpers) + final cleanup | ~50 | LOW |

After commit 10, `sync_service.dart` is ~500-700 lines containing only: `RestoreResult`, the class declaration + state, the cross-domain orchestrators, the pull paths, and the 10 `part` declarations.

### Per-commit mechanical procedure

1. `flutter analyze` + `flutter test` BEFORE the commit (baseline).
2. Cut the target methods out of `sync_service.dart`.
3. Paste into `lib/core/services/sync/sync_<domain>.dart` with `part of '../sync_service.dart';` at the top.
4. Add `part 'sync/sync_<domain>.dart';` to `sync_service.dart` library root.
5. `flutter analyze` (expect 0/0).
6. `flutter test` (expect 1706/0/2 unchanged).
7. Stage + commit. Pre-commit hook re-runs analyze + test as the discipline gate.
8. Commit message format: `refactor(sync): extract <domain> to part file (commit N/10)`.

## 6. Test strategy

### Existing tests (regression net — must stay green throughout)

- `test/contracts/sync_fanout_contract_test.dart` — pins `syncWorkoutData()` + `syncNutritionData()` fan-out completeness.
- `test/contracts/restore_completeness_writes_test.dart` — pins the 7 surfaces (freezes, inbox, diet plan, rank promotions, coach memory) that `restoreFromCloudForUser` must cover.
- Full suite at 1706/0/2 — no regressions allowed.

### New tests added by this refactor

**`test/contracts/sync_service_public_api_snapshot_test.dart`** (commit 0):

- Parses `lib/core/services/sync_service.dart` AND every file in `lib/core/services/sync/` after extraction begins.
- Extracts the sorted list of public method names on `SyncService` (any name not starting with `_`).
- Asserts the set exactly matches a frozen list checked into the test file.
- If a method is renamed, removed, or made private during the refactor, this test fails.
- If a NEW public method is added (e.g. by a parallel batch landing mid-refactor), the test reminds us to consciously update the frozen list.

Implementation: simple regex over the source files (no AST dependency). Same shape as existing source-grep contract tests under `test/contracts/`.

### Out of scope for new tests

- No new behavioral tests. The refactor changes zero behavior; existing 1706 tests are sufficient.
- No new regression tests per CLAUDE.md rule 21 (rule applies to bug fixes, not refactors).

## 7. Risks + mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| `part` directive accidentally breaks IDE jump-to-definition or analyzer | LOW | Commit 1 pilots with 280 lines; if mechanism is broken, revert and pivot to mixins (Option 2) for ~2h sunk cost only |
| A method gets renamed during cut/paste | LOW-MED | API snapshot test (commit 0) catches this immediately |
| Library-private state becomes inaccessible from a part | VERY LOW | `part of` directives explicitly share library scope; this is the documented Dart mechanism |
| A `static` helper is accidentally moved without updating callers | LOW | Static helpers stay on `SyncService` class — call sites unchanged. Pure top-level helpers (rare, only `_coerceInt`) stay in sync_service.dart |
| Mid-refactor, a `fix:` commit lands on main and touches `sync_service.dart` requiring rebase | MED | Branch is short-lived (single sitting, ~10-14h). Rebase conflicts are mechanical. Don't start refactor during active bug-fix batch |
| APK ship reveals runtime regression that test suite missed | LOW | Standard `/build-apk` skill + manual smoke (login → sync → restore round-trip) before declaring done |
| `part`/`part of` is seen as out-of-fashion and a future contributor reverts it | LOW | Add comment block at top of `sync_service.dart` explaining the choice + linking to this spec |

## 8. Completion criteria

- [ ] All 11 commits (commit 0 + extraction commits 1-10) land on `refactor/sync-service-part-split`.
- [ ] `flutter analyze` → 0 errors, 0 warnings at HEAD.
- [ ] `flutter test` → 1706+/0/2 at HEAD (the +1 is the API snapshot test from commit 0).
- [ ] `sync_service.dart` ≤ 800 lines.
- [ ] No part file exceeds 1,300 lines (workout is the biggest).
- [ ] All 10 part files exist with `part of '../sync_service.dart';` header.
- [ ] `SyncService.instance.X()` API surface is byte-identical to pre-refactor (snapshot test green).
- [ ] Single `--no-ff` merge to `main` lands the refactor.
- [ ] `/build-apk` produces a green build from `main` tip.
- [ ] Manual smoke on installed APK: cold start → sign in → trigger a workout sync + nutrition sync + restore round-trip → no telemetry errors in `client_errors`.
- [ ] Update CLAUDE.md §5 "Single-source-of-truth files" entry for `sync_service.dart` to note the part-file structure.
- [ ] Update `docs/audit/2026-05-11/cleanup-batch-triage.md` item B-5 to mark closed.

## 9. Effort estimate

- Commit 0 (API snapshot test): 30 min
- Commits 1-2 (pilot + realtime): 1.5h (slow, validates mechanism)
- Commits 3-7 (mid-size domains): 4h (~45min each)
- Commit 8 (workout, biggest): 2h
- Commit 9 (infrastructure): 2h
- Commit 10 (cleanup): 1h
- APK ship + smoke: 1h

**Total: ~12h** — close to the audit's original 6-10h core + 4h tests estimate.

## 10. Out-of-scope follow-ups (do NOT bundle)

These are explicitly NOT part of this refactor. They can be considered as separate batches AFTER this lands:

- Splitting individual part files further if any grows past 1,500 lines.
- Migrating to per-domain repository classes with constructor injection (architectural change, not file split).
- Adding domain-level integration tests beyond the existing contract tests.
- Auditing `pushSnapshot` / `weeklyFullSync` callsites for unnecessary fire-and-forget invocations.
- Splitting `RestoreResult` into its own file.
- Rewriting the realtime resubscribe-with-JWT-refresh logic.

---

**End of spec.**
