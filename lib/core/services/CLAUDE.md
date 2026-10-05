---
scope: core_services
parent: ../../../CLAUDE.md
created: 2026-05-18
updated: 2026-08-30
status: active
---

# Core Services — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/core/services/`.
> Root CLAUDE.md (../../../CLAUDE.md) contains process invariants and a pointer index.

## What lives here

`lib/core/services/` is the **service layer between widgets and storage**. Every
write to Hive that participates in cloud sync goes through a *WriteService*
class (`WorkoutWriteService`, `NutritionWriteService`, `HealthWriteService`,
`ProfileWriteService`, `WaterTargetService`, etc.). Every read with a public
domain contract goes through a *ReadService* (`WorkoutReadService`,
`NutritionReadService`, `HealthReadService`). Widgets and Riverpod providers
**must never call `Hive.box(...)` directly** — the WriteService wires
provider invalidation + sync fan-out + telemetry as one atomic unit.

Also in this directory:

- `sync_service.dart` + `sync/sync_*.dart` — orchestrator + per-domain sync extensions.
- `hive_service.dart` — boot, lifecycle compaction, user-session swap.
- `hive_user_session.dart` — cross-account ownership lock (`auth_hive_owner_agreement`).
- `auth_session_bootstrapper.dart` — post-auth decision tree owner.
- `subscription_service.dart` — entitlement. **Three entry points (`a9c4e1`):** `isPro()` = DECISION path (may WRITE); `proStateSnapshot()` = PURE read, **required in every Riverpod build method**; `evaluateEntitlement()` = enforce at boot/account swap. Gate via `gateAndVerify()`. Kill-switch `disable_cqrs_pure_pro_read`; gate `scripts/check_cqrs_query_naming.dart`.
- `error_telemetry.dart` — `recordNonFatal` (the helper every catch block must use).
- `usage_counter_service.dart` — increment-at-API-call counters (post Test #11).
- Migrators: `exlog_key_migrator.dart`, `nlog_key_migrator.dart`, `hive_field_rename_migrator.dart`, `user_config_migrator.dart`, `body_fat_default_healer.dart` (nulls a legacy fabricated body-fat `18.0` where `body_fat_percent==18.0 && body_fat_assessed_at==null`; clears the CLOUD column FIRST, then local; idempotent; kill-switch `disable_bodyfat_heal`), etc.

## Single-source-of-truth contracts

Every WriteService here is the canonical writer for at least one SoT-registry
concept. Selected mappings (full list in `docs/sot_registry.yaml`):

| Concept | Writer (this dir) | Reader entry point |
|---|---|---|
| `exercise_logs_read_path` / `workout_receipt_rendering` | `workout_write_service.dart` `logExercise` — top-level `reps_completed`/`weight_kg`/`volume_kg` MUST be computed from `cleanedSets` (post logging-type normalization), never `mergedSets` (bug e8f95e) | `workout_read_service.dart` `exerciseLogsForIstDate` |
| `nutrition_total_calories` / `food_log_delete_with_undo` | `nutrition_write_service.dart` `logMeal` / `deleteLog(allowUndo:)` (audit-fixwave F12 — was mis-named `deleteWithUndo`) | `nutrition_read_service.dart` |
| `health_write_service` | `health_write_service.dart` (6 methods — water / weight / sleep / steps / mood / energy) | `health_read_service.dart` |
| `subscription_state` / `subscription_payment_grace_window` | `subscription_service.dart` `setPro` + Razorpay webhook handlers | `subscriptionInfoProvider`, `gate()` |
| `water_target` | `water_target_service.dart` | `waterTargetProvider` |
| `error_telemetry_helper` | `error_telemetry.dart` `recordNonFatal` | every catch block app-wide |
| `sync_fanout_workout_domain` / `sync_fanout_nutrition_domain` | `sync/sync_workout.dart` / `sync/sync_nutrition.dart` | callers fire `unawaited(syncWorkoutData())` after a mutation |
| `sync_exercise_log_payload_hash_index` | `sync/sync_workout.dart` `_syncExerciseLogs` | same method — sole writer AND reader (skip decision reads its own index; OI-204) |
| `sync_failure_retry_sweep` (e5b2a9) | `sync_service.dart` `_reportSyncFailure` → `sync_retry_controller.dart` `SyncRetryController.noteFailure` (+ the durable syncBox flag `sync_sweep_owed`); `weeklyFullSync` (serialised via `serial_slot.dart`) stamps `last_full_sync` and clears the flag only on a clean sweep | `sync_state_provider.dart` `_stateFor` (`SyncPaused`), `weeklyFullSync`, `checkAndSync` (`shouldRunFullSweep`) |
| `restoring_destination_read_timeout` (e5b2a9) | `auth_session_bootstrapper.dart` `resolveBounded` (incl. evidence-first: `GoHome` at once when the device holds local evidence) / `boundDestination` / `ExclusiveRun`; the background late answer: `settleLateAnswer` → `applyLateAnswer` behind `liveSessionOwnedBy` → `sessionOwnedBy`; the ONE Plan A stamp writer `stampOnboardingCompletedAt` | `restoring_screen.dart` `_kickoffRestore` + `_onContinueAnyway` |
| `sync_nutrition_log_payload_hash_index` | `sync/sync_nutrition.dart` `_syncNutritionLogs` | same method — sole writer AND reader (skip decision reads its own index; OI-204) |
| `restore_completeness` | `sync_service.dart` `restoreFromCloud` | `restoring_screen.dart` |
| `user_scoped_hive_keys` / `hive_deletion_and_session_helpers` | `hive_user_session.dart` + `hive_service.dart` | `wrapUserScopedBox` (helper used everywhere) |
| `auth_hive_owner_agreement` | `hive_user_session.dart` + `wrapUserScopedBox` | every WriteService + every Hive-touching Riverpod provider |
| `day_rollover_provider_invalidation` | `day_rollover_service.dart` — cold-launch (`runRolloverNow`), resume, and a foreground midnight `Timer` backstop | `splash_screen` + `home_screen` mount. The ~27-provider invalidation list is a miss-site for any NEW daily-scoped provider (audit every `DateTime.now()`-computing provider under `lib/features/*/providers/`). `weeklyReportDataProvider` write-time leg open on OI-267. |
| `singleton_lifecycle_registry` | `singleton_lifecycle_registry.dart` | hot-restart cleanup |
| `rank_monotonic_current_code` | `rank_service.dart` `evaluateAndPromote` (guarded by `shouldPromote(currentCode, qualified)` — monotonic-only; mirrored in the `evaluate-rank-promotions` cron EF) | `rank_service.dart` `getCurrentRank` (Hive `userBox['profile']`) → Profile chip + Home pending promotion; `ai_snapshot_builder.dart` routes through `getCurrentRank()` (OI-230/231) → snapshot `current_rank`/`next_rank`. |
| `day_swap_engine` | `swap_service.dart` `SwapService.swapDays` — the ONE entry point (Train drag, ⇅, Home long-press, coach); every check re-runs at confirm time under `WorkoutWriteService.swapScheduledDays`'s two-date lock, and the whole swap (allowance check → write → `recordSwap`) runs under `SwapService._withWeekLock` (one lock per IST Mon–Sun week; `e2b9d4`). Counted only after the write succeeds. | `day_swap_provider.dart`, `SwapPickerSheet`, `DaySwapRowTrailing`. |
| `day_swap_allowance` | `day_swap/day_swap_allowance.dart` `DaySwapAllowance.recordSwap` — phone copy at `userBox['day_swap_allowance']` (+1 on the phone immediately, then a background `consume-day-swap` call corrects it; server wins when it answers, no answer keeps the phone copy) | `DaySwapAllowance.current` → `daySwapAllowanceProvider`, the picker/confirm sheets' allowance line. |
| `schedule_arrangement_stamp` | `day_swap/day_swap_rules.dart` `buildSwap`/`landed` set `arranged_at_ms` inside the build function `SwapService.swapDays` passes to `swapScheduledDays` (which only writes it); `upsertScheduled`'s `carriesArrangement` carries it forward on a non-swap, non-restore rewrite | `plan_integrity_reconciler.dart` `snapshotArrangementWinsKeys` (restore-merge L3, `docs/architecture/sync.md`). |
| `completed_title_follows_log` (OI-284, diagnose d4a7e1) | `completed_title_healer.dart` `CompletedTitleHealer.run` — after a SUCCEEDED `restoreFromCloudForUser` (`SyncService.healCompletedTitlesAfterRestore`, wrapper before the core) and at the tail of `restoreFromCloud`: a completed non-template row's `workout_name` := its own `wlog_<date>` name (local Hive only; title ONLY; guards + placeholder set `kPlaceholderWorkoutNames`; kill switch `disable_completed_title_heal`). It must NOT bump `restoreCompletedTick` (that tick gates streak decay, `workout_repository.dart:244-248`). Not hooked on `restoreLightweightAlways` (restores no logs) or the `*ForSyncDomain` entry points (flag-gated off): whoever flips them, or OI-279's resume-pull, calls `CompletedTitleHealer.run()` after restoring logs. | Train row / Home Today widget title (`schedule_<date>.workout_name`); the completed card still reads `wlog_<date>`. Test `test/contracts/completed_title_follows_log_test.dart`. |
| `sync_epoch` | `user_progress.sync_epoch` (migration 149), operator-bumped via SQL (`docs/operations/SYNC_EPOCH_RESYNC.md`) | `sync_service.dart` `_applySyncEpochFromRestoreRow` compares against `workoutBox['sync_epoch_seen']` and calls `SyncSkipIndex.clearAll` on a strictly-greater cloud value. |

The WriteService pattern enforces three steps every write:

1. **Write to Hive first** (via `wrapUserScopedBox`).
2. **Invalidate the registered provider set** (see `provider_invalidation_set` in `docs/sot_registry.yaml`).
3. **Fire-and-forget `unawaited(syncDomain())`** — never block the UI on cloud.

Failures from step 3 are captured by `ErrorTelemetry.recordNonFatal` with an
`op_type` from `op_types_canonical.dart`; the catch block never bubbles up to
the user. Every WriteService method returns a `WriteResult` so the caller can
distinguish "Hive succeeded" from "cloud succeeded".

**Sync fan-out is COALESCED (Unit H).** `syncWorkoutData()` / `syncNutritionData()` / `pushSnapshot()` are fire-and-forget coalesced entries (`SyncCoalescer`, in-flight + dirty do-while): a burst of per-write calls collapses to 1–2 cloud passes (diagnoses c4f8d2 / b4f7e2 / e7c1a9). Rules:
- **Awaited / durability-critical callers MUST call the non-coalesced `*Now()` variant** (`syncWorkoutDataNow` / `syncNutritionDataNow` / `pushSnapshotNow`) — a coalesced call may only set `_dirty` and return. Current `*Now()` callers: resync migrator, sim harness, `checkAndSync`, onboarding first-context, `coach_memory_service`.
- **All three coalescers are reassigned in `_onUserChanged`.** Kill-switches `disable_sync_debounce` / `disable_sched_hash_skip` / `disable_snapshot_debounce`. `_syncScheduledWorkouts` skips unchanged rows (incl. `completed`) via `SyncSkipIndex` (domain `sched`); migration 149's completed-day guard is a HARD prerequisite for any build carrying that skip.

**`SyncSkipIndex` is the ONLY way a sync history step may skip a push** — Gate G1 (`scripts/check_sync_hash_skip_atomicity.dart`) fails any `.upsert(`/`.insert(` in a Hive-row loop under `lib/core/services/sync/**`/`sync_service.dart` outside a `pushIfChanged(` closure, and any `*_payload_hash_index` literal written outside `sync_skip_index.dart`. `SyncSkipIndex.clearAll` returns a `ClearAllResult`; only `allSucceeded` may advance `workoutBox['sync_epoch_seen']` (`a9d3f6`).

`swapScheduledDays` (`workout_write_service.dart`) is the day-swap engine's one atomic write (`WriteSource.daySwap`, two-date lock, all-four-keys-or-none); its `carriesArrangement` helper is the sole decider of when `upsertScheduled` carries an `arranged_at_ms` stamp forward. `ScheduleHybridRepairMigrator` is a ONE-TIME PER-USER repair gated by `workoutBox['hybrid_schedule_repair_v1_done']` (NOT `migrationBox`, which is one shared box per device).
repair gated by `workoutBox['hybrid_schedule_repair_v1_done']` — deliberately NOT `migrationBox`
(a single shared box opened once per device), because `workoutBox` is opened per-user via
`HiveUserSession.openForUser`, so a second account signing into the same device is repaired too.

Coalesced-entry audit (2026-09-21, A3-follow): every `unawaited(SyncService.instance.<sync|push>...)` call site across `lib/` calls the coalesced entry; the 5 raw `*Now()` sites match the documented exception list. Detail: `docs/architecture/services-detail.md`.

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Hive box not open | Open ALL boxes in main.dart before runApp(). | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Adapter not registered | Register ALL Hive adapters before openBox(). | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Hive file bloat over time | `HiveService` (a `WidgetsBindingObserver`) runs `box.compact()` on **8** mutation-heavy boxes every 7 days on `AppLifecycleState.paused`, gated via `configBox['last_compact_at']`; telemetry reasons `hive_service_maybe_compact_box` / `hive_service_maybe_compact`. User-scoped box switch is race-safe via `HiveUserSession._sessionLock`. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Force-unwrap `!` on map keys or `.first` on possibly-empty lists | Null-safe the map read (`(m['k'] as num?)?.toDouble() ?? 0.0`); guard `.first` with `isNotEmpty`. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Hive `path_provider` MissingPluginException in unit tests | In tests needing Hive boxes: `TestWidgetsFlutterBinding.ensureInitialized()` + mock `plugins.flutter.io/path_provider` (return `tempDir.path`) BEFORE `Hive.init(tempDir.path)` / `HiveService.instance.init()`. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Increment a usage counter at save time | Counters MUST increment at the API-call site, not at the save site. Pre-Test-#11 free-tier users saw "50 remaining" while the Postgres trigger had counted every Edge Function call. Counter callsites: `food_logger_section._analyse`, `ScanMealNotifier.scanImage`, `cart_auditor_section.analyseCart`, `tool_dispatcher._executeLogMealByText`. | (relocated 2026-05-18 — see `lib/features/nutrition/CLAUDE.md`) |
| Restore writer keyed differently from production writer | Test #12.8 root cause — 6 of 16 `_restoreXxx` methods used legacy keys. Always test restore→read round-trip in `test/sync/restore_completeness_test.dart`. | `feedback_writer_reader_field_drift_recurring.md` |
| Cloud→Hive restore merge lowers a monotonic field | Route `progress` through `UserRepository.mergeCloudProgress` (local-max-wins on `current_phase` / `deployments_complete` / `total_workouts_done`; cloud-non-null-wins on the rest). Pick the set by which direction is bad (`longest_gap_days` is NOT max-wins). Kill-switch `disable_progress_restore_monotonic_merge`. Diagnose `d1f6b3` / OI-83. | `feedback_monotonic_field_recompute_demotion.md` |
| Writer unconditionally overwrites a "lifetime / peak / earned" field with a recomputed value | Lifetime monotonic fields (rank, lifetime workouts, longest streak, peak weight, deployments_complete, badge unlock) MUST have an only-increment writer guard: extract a pure helper (`shouldPromote(...)`-style) and mirror it to every parallel writer (client + server crons). Diagnose 3a7b9f; debugging skill 2.19. | `feedback_monotonic_field_recompute_demotion.md` |
| Restore skips `plan_json` when a local plan already exists | `_restoreWorkoutPlan` must NOT early-return on `current_plan != null`; apply the cloud `plan_json` authoritatively via `PlanIntegrityReconciler.mergeScheduleEntry` (completed-day-preserving) — cloud `scheduled_workouts` has no exercises column. Boot heal `PlanIntegrityReconciler` (`needsHeal`, kill-switch `disable_plan_integrity_reconciler`). Diagnose a7d3f1. | `feedback_writer_reader_field_drift_recurring.md` |
| A sparse map is written into a jsonb COLUMN with a plain upsert | Assignment, not a merge: a writer with FEWER keys than the store DELETES. Per-key additive write: migration 123's `merge_notification_preferences` RPC; multi-writer `snapshot_json` uses `_shared/snapshot_merge.ts` `mergeSnapshotJson`, and the client push strips cron-owned keys (`SyncService.compileDailySnapshot()`). Never pad the map to the full key set. Diagnoses `e4a1b7`, `d8a2f6`. | `feedback_mistake_guard_without_its_mirror.md` (#17) |
| Restore overwrites a local row the user just logged | A loss-sensitive `_restoreXxx` that writes a LOG row (exlog/wlog/nutrition log/saved meal) MUST be **additive / local-wins**: `if (box.get(key) != null) continue;`. Background restore runs concurrently with logging (`disable_bg_restore`, c5a1f2). Reference: weight (`sync_health.dart`). `_restoreScheduledWorkouts` instead timestamp-merges (d9b2c5). | `restore_local_wins_additive_test.dart`, diagnose c5a1f2 |
| A restore-path Supabase SELECT with no retry silently drops a field on a stale token | `ensureFreshToken()` first; on null/empty retry ONCE behind a hard `auth.refreshSession()`. A PRE-FETCHED value (`preFetchedUsers`) bypasses the retry — log the injected-null case. Diagnose `d4e9a2`. | `test/contracts/restore_users_row_retry_test.dart` |
| Restore/reconcile merge refills a local rest row with stale workout content (L1) | `PlanIntegrityReconciler.mergeScheduleEntry` never refills a local `rest`-type/status row; kill switch `disable_rest_row_refill_guard` (the `_normalizeHybrid` normalizer stays live regardless). Diagnose `b6e1c8`. | `docs/architecture/sync.md` 'Sync skip pattern' point 6, `plan_integrity_reconciler_*_test.dart` |
| An older arrangement from another device overwrites a newer local swap on restore (L3) | `PlanIntegrityReconciler.snapshotArrangementWinsKeys` compares MAX `arranged_at_ms` per Mon–Sun IST week and lets the snapshot win only on a STRICT `>`. Kill switch `disable_swap_arrangement_merge`. A completed row is never a candidate. | `docs/architecture/sync.md` 'Sync skip pattern' point 6 |
| Restore re-downloads and re-writes an unchanged plan bundle every launch (L2) | Two skips, ONE kill switch (`disable_plan_merge_skip_when_known`): skip the whole merge only when the fingerprint matches AND every bundled `schedule_<date>` key still exists locally (an OI-252 ghost day whose `tmpl_<uuid>` key is also absent counts as present; `a3e7d9`); `mergeScheduleBundleIntoHive` writes only when the merged result differs. | `docs/architecture/sync.md` 'Sync skip pattern' point 6 |
| A per-launch restore writer rewrites an unchanged row every launch | `_restoreWorkoutTemplates`, `_restoreUserProgress`, `_restoreUserProfile` compare via `SyncFingerprint.canonicalJson` and skip an identical write (kill switch `disable_restore_write_if_changed`). If the write path STAMPS a field (`ProfileWriteService.updateProfile` sets `updated_at`), drop it from BOTH sides. Any new per-launch restore writer takes the same guard. Diagnose `f1c6b4`. | `test/sync/restore_write_if_changed_test.dart` |
| An error's text reaches telemetry with the user's row data in it | Postgres echoes the rejected row into its error and `PostgrestException.toString()` carries it. Every sink that ships error text off the device calls `ErrorTelemetry.redactRowValues` first (both `recordNonFatal` legs, `_reportSyncFailure`, retry queue, dead-letter post, `_logRefreshFailure`); a NEW direct `log-client-error` post owes the same call. Diagnose `e8c3a1`. | `test/core/error_telemetry_redact_row_values_test.dart`, `test/sync/sync_error_row_values_redacted_test.dart` |
| A caller's own `ErrorTelemetry.recordNonFatal` sits earlier in the same catch block as a `_reportSyncFailure`, so the SAME failure posts to `client_errors` TWICE | The audit-2026-05-11 H-42 "telemetry pair" idiom: both calls default to `skipServerPost: false` and both POST to `log-client-error`. Every caller-level `recordNonFatal` earlier in the same enclosing block as a `_reportSyncFailure` for the SAME caught error (not only an adjacent one — a ~570-580-char comment once separated a pair) passes `skipServerPost: true` (keeps the real stack for Crashlytics; `_reportSyncFailure` stays the sole `client_errors` writer). Grep ALL `part of sync_service.dart` files under `sync/`, not one file (a single-file `H-42` grep saw only ~13 hits; 87 existed at fix time, 75 are pinned now); the regression test concatenates them via `loadSyncServiceSource()`. Diagnose `f7b2c9`. | `test/sync/sync_telemetry_test.dart` |
| `_safeRestoreOp` once wrote one `client_errors` row per SUCCESS (57% of the table) | Never put a per-success `logEvent` in a path a retry re-runs; `restore_op_done` is now logged only for ops ≥ 2 s (`shouldLogRestoreOpDone`, kill-switch `disable_restore_op_done_filter`). | `restore_op_done_filter_test.dart` (e5b2a9, OI-151) |
| The push retry loops forever on a rejection, or fires on a restore/read failure, or arms on an op the sweep never re-sends | `SyncRetryController` accepts only OUTAGE-SHAPED failures (5xx/52x, 408/429, PGRST000-003, socket, TLS, timeout), classified from the error text BEFORE `, details:` (Postgres echoes the user's own row there), on PUSH opTypes the sweep re-sends (`kNotSweptOpTypes` lists the READS and own-writer pushes); never widen it to `SyncError.isTransient` (UnknownError is transient). A NEW `_reportSyncFailure(opType:)` literal needs a push/not-swept decision (the forcing-function test enumerates them). `weeklyFullSync` stamps `last_full_sync` and clears `sync_sweep_owed` only on a clean sweep and runs serialised (`SerialSlot`: release in `finally`). | `sync_retry_controller_test.dart`, `serial_slot_test.dart` (e5b2a9) |
| A "one tiny request" probe is really four | The supabase SDK retries a GET answered 503/520 — or that THROWS — three more times (1/2/4 s) and 503 is the PGRST002 outage shape — opt out with `.retry(enabled: false)` where it must be ONE request. The probe lives in `backend_probe.dart` (free of `SyncService`, so it is stub-server tested). | `backend_probe.dart`, `probe_backend_reachable_test.dart` (e5b2a9) |

## Tests pinning the rules here

- `test/contracts/`: `auth_hive_owner_agreement_behavioral_test` (Layer A+B), `progress_restore_monotonic_behavioral_test` (d1f6b3 / OI-83), `sync_fanout_workout_domain_writer_to_reader_test` (+ nutrition), `error_telemetry_helper_writer_to_reader_test`, `health_write_service_writer_to_reader_test`, `restore_completeness_writes_test`, `restore_local_wins_additive_test`, `workout_write_service_*_test`, `nutrition_write_service_*_test`, `subscription_state_*_test`.
- `test/sync/restore_completeness_test.dart` — every `_restoreXxx` round-trips.

## See also

- `lib/CLAUDE.md` — cross-feature rules.
- `docs/architecture/services-detail.md` — moved-out history, provenance and audit results for this file.
- `docs/architecture/sync.md` — sync schedule + restore-completeness + Hive field-name contracts.
- `docs/sot_registry.yaml` — full SoT registry.
