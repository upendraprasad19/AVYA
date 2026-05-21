---
source: CLAUDE.md §4 + §15
migrated: 2026-05-18
status: scaffold
---

# Sync + Data Architecture — Reference

> Cross-cutting concern. Fetch via Read when working on sync, Hive contracts, or restore-completeness.
> Root CLAUDE.md contains pointers but not the full content.

## Overview — Offline-first architecture

```
┌─────────────────────────────────────────────────────┐
│                    FLUTTER APP                       │
│                                                      │
│  ALL reads/writes → Hive (LOCAL-FIRST)               │
│  Zero latency. Works fully offline.                  │
│                                                      │
│  SEED DATA (bundled JSON in APK):                    │
│    assets/data/exercise_library.json (200+ exercises)│
│    assets/data/food_database.json (1431 foods)        │
│    → Parsed into Hive on first launch                │
│                                                      │
│  SYNC TO SUPABASE:                                   │
│    Immediately: custom foods/exercises (community)    │
│    Every app launch: pushSnapshot() (AI context)     │
│    Daily (app launch if >1d): full sync all logs     │
│                                                      │
│  RESTORE (new device):                               │
│    Login → pull from Supabase → populate Hive        │
│    ALL users: full history (storage per user ~1-2MB)  │
│                                                      │
│  SUPABASE ROLE (NOT primary DB):                     │
│    • Auth (Supabase Auth)                            │
│    • Backup + cross-device restore                   │
│    • AI training corpus (snapshots, conversations)   │
│    • Community DB growth (custom foods/exercises)     │
│    • Subscription verification                       │
└─────────────────────────────────────────────────────┘
```

### Hive Boxes
| Box | Contents |
|-----|----------|
| `userBox` | user profile, preferences, progress |
| `workoutBox` | workout_logs, scheduled_workouts, templates, exercise_logs |
| `nutritionBox` | nutrition_logs, saved_meals |
| `healthBox` | weight_logs, measurements, streaks, sleep_logs |
| `exerciseBox` | exercise_library (seeded from bundled JSON) |
| `foodBox` | food_database (seeded from bundled JSON) |
| `customBox` | user_custom_exercises, user_custom_foods |
| `coachBox` | ai_coach_interactions, coaching_notes |
| `syncBox` | last_sync_timestamps (pending_sync_queue is **planned** — see `docs/superpowers/specs/2026-04-17-sync-reliability.md`, not yet implemented) |
| `configBox` | subscription status, feature flags, app config |

#### workoutBox Key Patterns
| Key Pattern | Value |
|-------------|-------|
| `schedule_YYYY-MM-DD` | Schedule entry (type, status, workout_name, exercises, week) |
| `exercise_log_index_YYYY-MM-DD` | List of exercise log IDs for that date |
| `exlog_<timestamp>_<hash>` | Exercise log: exercise_name, logging_type, weight_kg, reps_completed, sets_completed, volume_kg, is_pr |
| `wlog_<timestamp>` | Workout log: workout_name, date, duration_seconds, sets_completed |
| `tmpl_<timestamp>` | Workout template (single-day) — fields: id, name, exercises[], exercise_count, type:'template', assigned_days:[int], created_at. Multi-day AI templates (from `createCustomTemplate` tool) split into N rows tagged with `group_id`/`group_day_index`/`group_total_days` for cross-row identification. |

## Sync schedule + SoT rules

| When | What | Where |
|------|------|-------|
| Immediately | Custom foods/exercises added | → Supabase (community contribution) |
| Immediately (fire-and-forget) | Every nutrition mutation (log meal, water, urine, edit/delete food, scan meal save, barcode save, custom exercise create) fires `SyncService.syncNutritionData()` + `pushSnapshot()` | → Supabase + AI snapshot |
| Immediately (fire-and-forget) | Every workout mutation (complete, edit log, template save/delete, schedule change) fires `SyncService.syncWorkoutData()` + `pushSnapshot()` | → Supabase + AI snapshot |
| Every app launch | user_daily_snapshot (AI context) via pushSnapshot() | → Supabase |
| Daily 11PM IST | coaching_notes extraction from that day's conversations | → Hive + Supabase |
| Daily (app launch if >1d) | Full sync: all logs, progress, preferences | → Supabase |
| Periodically | Check for new approved community items | ← Supabase → Hive |
| On restore | Pull full history (all users) | ← Supabase → Hive |

### Fire-and-Forget Sync Pattern
All mutation paths use `unawaited()` from `dart:async` to push changes without blocking UI:

```dart
import 'dart:async';
import 'package:icanbefitter/core/services/sync_service.dart';

// In any mutation (logFood, addWater, saveMeal, completeWorkout, etc.):
await hiveBox.put(key, value);            // 1. Hive-first (blocking)
ref.invalidate(dependentProvider);        // 2. Refresh UI (blocking)
unawaited(SyncService.instance.syncNutritionData());  // 3. Push to Supabase (background)
unawaited(SyncService.instance.pushSnapshot());       // 4. Refresh AI context (background)
```

**Never `await` the sync calls** — they must not block the UI. Failures are logged via `debugPrint` inside the service and silently ignored; the local Hive write is the source of truth. Use `syncWorkoutData()` for workout mutations and `syncNutritionData()` for nutrition mutations (parallels the workout method, syncs `nutrition_logs` + `water_logs` in one batch).

### Sync Deduplication Rules
- **Streaks:** `onConflict: 'user_id,week_start'` (UNIQUE constraint in DB). Restore dedupes by `week_start` — cloud row replaces local if conflict found. Never dedup by cloud `id` alone (causes same-week duplicates).
- **Workout logs/exercises:** Upserted by deterministic UUID (`_deterministicId(localKey)`). Safe for re-sync.
- **Water logs:** `onConflict: 'user_id,date'` (UNIQUE constraint added migration 013). One row per user per day.
- **Scheduled workouts:** `onConflict: 'user_id,scheduled_date'` (UNIQUE constraint added migration 013). One schedule per user per date.

### Restore Pagination
- All restore queries use paginated fetch (1,000 rows per page, offset-based).
- Safety ceiling: 50,000 rows per table to prevent runaway fetches.
- No hardcoded `.limit(5000)` — truly full-history restore for all users.

### Source of Truth Rules (NON-NEGOTIABLE)
> Multiple-source bugs are the #1 cause of "UI says X but data says Y" issues. Establish ONE reader per derived concept.

- **Workout receipt:** `WorkoutReceiptData.fromExerciseLogs(date)` (in `workout_receipt_card.dart`) is the ONLY way to build receipt data after the fact. Reads from Hive `exlog_*` keys via `WorkoutRepository.getExerciseLogsForDate()`. Deduplicates by exercise name (sum sets, max weight). Never hand-build receipt data from a widget's in-memory state.
- **Workout log edit:** `EditWorkoutLogSheet` (in `lib/features/train/widgets/edit_workout_log_sheet.dart`) is the ONLY edit surface. Every entry point (receipt sheet Edit button, Home "View Card", calendar day detail, Train expanded view) routes through it. Save:
  1. Rewrites the Hive log map in place
  2. Recomputes `volume_kg = weight_kg × reps_completed`
  3. Chronologically rescans `is_pr` flags for the exercise (sorts by `date + created_at`, walks forward, strict `>` comparison)
  4. Invalidates: `currentPlanProvider`, `workoutStatsProvider`, `calendarWeekProvider`, `streakProvider`, `todayWorkoutProvider`, `allExercisePRsProvider`
  5. Fires `SyncService.instance.syncWorkoutData() + pushSnapshot()` (fire-and-forget)
- **Exercise logs:** `WorkoutRepository.getExerciseLogsForDate()` is the ONLY read path. Uses O(1) index `exercise_log_index_YYYY-MM-DD` with legacy full-scan fallback. Never iterate `workoutBox.keys` manually to find logs for a date.
- **Home "View Card" state:** `todayWorkoutProvider` is the single source for the "DONE + View Card" state on home. Always derived from Hive schedule + exercise logs — never cached in the widget.
- **Scheduled workouts:** `WorkoutScheduleService` owns all schedule mutations (generate, clean-sync on template edit, reschedule on days/week change). Never write `schedule_YYYY-MM-DD` keys directly from a widget or repository.
- **Nutrition total calories:** After a meal is logged, `total_calories` comes from summing `items[]` with per-item Atwater fallback (`raw > 0 ? raw : 4P+4C+9F`). Never read `result['total_calories']` at the top level of an AI response — it's routinely missing.
- **AI snapshot:** `AiCoachRepository.buildAiContext()` is the ONE builder. `AiService._compactContext()` is the ONE trimmer. Never construct ad-hoc snapshots in provider code.
- **Subscription status:** `SubscriptionService.isPro()` + `gate()` are the ONLY entry points. Never read `configBox.get('isPro')` directly from a widget. High-value features (`phases_2_to_12`, `ai_coach_unlimited`, `progress_photos`) go through `verifyFromServer()`.
- **User-scoped Hive keys (MigratedKey discipline):** Anything user-specific that previously lived in shared `configBox` now reads/writes through `MigratedKey` (in `lib/core/services/migrated_key.dart`). The 31-key migrated set is enumerated in `UserConfigMigrator.userScopedKeys` (Test #10.1 + #11.1). Two keys deliberately stay in shared `configBox` and are listed in `_intentionallyShared`: `pending_referral_code` and `logout_in_progress`. When adding a new user-specific key, append it to `userScopedKeys`, bump `_flagKey` (`_v2_done` → `_v3_done` etc.) so existing devices re-run, and add the contract test pin. Never write directly to `configBox` for user-specific data.
- **Water target:** `WaterTargetService.instance.currentTargetMl()` (in `lib/core/services/water_target_service.dart`) is the ONLY way to read the daily water goal. Never hardcode `3000`. Read precedence: user override (`userBox['water_target_override_ml']`) → computed (`weight × 35 + 500 if 4+ training days + 300 if active lifestyle`, clamped 2500–4000 ml per founder direction 2026-05-04) → 2500 floor. Widgets must `ref.watch(waterTargetProvider)` (in `nutrition_provider.dart`) so manual override changes trigger rebuilds. Onboarding seed routes through `WaterTargetService.computeFromProfile(profile)`.
- **Provider invalidation after mutation:** Any write that changes workout state (log, edit, delete, complete) MUST invalidate the full batch: `currentPlanProvider`, `workoutStatsProvider`, `calendarWeekProvider`, `streakProvider`, `todayWorkoutProvider`, `allExercisePRsProvider`. One missing invalidation = stale UI.
- **Muster answers:** `InductionService.recordMusterAnswer` (in `lib/features/ai_coach/services/induction_service.dart`) is the ONLY writer for the 6 muster keys in `coachBox` (`why_now`, `definition_of_winning`, `known_injuries`, `typical_wake_time`, `preferred_workout_time`, `body_part_priorities`). For 4 of those, it ALSO bridges into `userBox['profile']` via `_bridgeToProfile`: `known_injuries→injuries`, `typical_wake_time→wake_up_time`, `preferred_workout_time→preferred_workout_time`, `body_part_priorities[0]→physique_focus` (single-element only; legacy multi-select skipped). Never write any of these coachBox keys from anywhere else. Adding a new muster question that maps to a profile field requires updating both `_bridgeToProfile` AND `backfillMusterToProfileIfNeeded` (in the same class). Pinned by `test/contracts/muster_profile_bridge_test.dart` + `test/contracts/muster_bridge_backfill_test.dart`.
- **Auth/Hive owner agreement (cross-account guard):** `authUserIdTokenProvider` (in `lib/features/auth/providers/auth_invalidation_provider.dart`) returns `'<anon>'` whenever Supabase `currentUser.id` disagrees with `HiveUserSession.currentOwnerFullId` (the live signOut+signUp race window). The 56 user-scoped Riverpod providers from c4055a all watch this token — they automatically render empty during disagreement and rebuild when the listenable confirms `openForUser` completed. Belt-and-suspenders: `wrapUserScopedBox` (in `lib/core/services/guarded_box.dart`) ALSO checks the same agreement and returns `GuardedBox.empty(authUid)` on disagreement, so reads serve null/empty even if the token-rebuild loop is broken. Never read user-scoped Hive without going through `wrapUserScopedBox`. Pinned by `test/contracts/auth_invalidation_timing_test.dart` + `test/contracts/wrap_user_scoped_box_disagreement_test.dart`.
- **AI coach memory upward sync (audit-2026-05-16 F3-1.1):** `coach_memory.coach_notes` cloud column is populated by `SyncService.syncCoachMemoryNow` projecting Hive `coachBox['coaching_notes']` (Hive key intentionally singular, cloud column intentionally singular too but DIFFERENT word). Pre-fix the upward projection was missing → AI memory lost on every reinstall (9th writer/reader drift instance). Pinned by `test/contracts/coach_notes_upward_sync_test.dart`. Never rename either side without updating BOTH and the contract test.
- **AI coach `logPR` tool (audit-2026-05-16 F6-2):** Routes through `WorkoutWriteService.logExercise` (single-set ExerciseSet) — same canonical writer as the UI active-workout flow. PR detection happens inside the WriteService via `_rescanPrFor`. Never call the legacy `WorkoutRepository.logSetWithPrRescan` from the dispatcher; that path was one of Test #16.1 Bug A's rogue exlog_* key formulas and bypasses the WriteService mutex + telemetry. Pinned by `test/contracts/tool_dispatcher_log_pr_uses_writeservice_test.dart`.
- **WorkoutScheduleService (audit-2026-05-16 E.6):** All 9 schedule mutations (markCompleted, markSkipped, activateTravelMode, swapExerciseInDay, shortenDay, copy week × 2, assignTemplateToDate, unscheduleTemplateFromDate) route through `WorkoutWriteService.upsertScheduled` for mutex + fan-out. 3 non-schedule writes (2 `_planKey` plan upserts + 1 template `last_used_at` stamp) stay direct + fire explicit `unawaited(SyncService.instance.syncWorkoutData())` adjacent. 1 internal `displacedKey` backup stays direct (rollback state, no cloud sync needed). Pinned by `test/contracts/workout_schedule_service_uses_write_service_test.dart`.
- **HealthWriteService (audit-2026-05-16 E.7):** Canonical writer for the health domain (sleep, weight, measurement, water, urine, hydration) mirroring `WorkoutWriteService` + `NutritionWriteService`. Per-(kind, date) mutex via `_acquireLock`. Every key uses `istDateStr(date)` (closes the F2-R2 IST drift in `profile_provider.logSleep`). Sole writer for all UI-layer health mutations — `profile_provider.BiometricNotifier.logSleep`, `nutrition_provider.WaterIntakeNotifier`, `nutrition_provider.UrineColorNotifier`, `nutrition_provider.HydrationSaveNotifier`, `home_provider.WeightLogNotifier`, `onboarding_provider` initial weight, `conversational_log_handler._logMeasurement`. The list key `coachBox['sleep_logs']` write in `conversational_log_handler._logSleep` is intentionally direct (list-append semantics) — documented with audit comment. Pinned by `test/contracts/health_write_service_writer_to_reader_test.dart` (15 tests).

### Hive field-name contract

WriteService output keys are a contract with every consumer. Field renames must:

1. Update the writer.
2. Update every consumer in the same PR (grep for the old field name).
3. Update or add a round-trip test in `test/contracts/`.

Current contracts:

- **`exlog_*`** (`WorkoutWriteService`) — fields: `exercise_name`, `date`, `sets[]` (List of Map), `set_number`, `reps_completed`, `weight_kg`, `volume_kg`, `logging_type`, `is_pr`, `source`, `updated_at_ms`, optional `notes`.
  Consumers: `WorkoutReceiptData.fromExerciseLogs`, `WorkoutRepository.getExerciseLogsForDate`, `AiCoachRepository.buildAiContext` (recent_logs section), calendar week provider, `WorkoutWriteService._rescanAllPrsFor` PR detector, `SyncService.syncWorkoutData` cloud projection.

- **`nlog_*`** (`NutritionWriteService`) — fields: `log_key`, `date`, `meal_type`, `total_calories`, `total_protein`, `total_carbs`, `total_fat`, `total_fiber`, `items[]` (List of Map; per-item keys: `name`, `quantity_g`, `calories`, `protein`, `carbs`, `fat`, `fiber`), `source`, `logged_at`, `created_at`. Consumers: `TodaysMealsCard`, `NutritionRepository`, `home_provider` daily-completion ring, `AiCoachRepository.buildAiContext` (meals_today / nutrition_trend_7d), `SyncService.syncNutritionData`.

If you rename a field in a WriteService, the corresponding contract test in `test/contracts/<x>_write_to_read_contract_test.dart` must be updated in the same commit. The receipt-rendering bug in APK Test #7 (set_number vs sets_completed) is the canonical failure mode this contract prevents.

### Sync fan-out contract

Two domain entry points are the contract for "everything in the
{workout, nutrition} domain is now in cloud":

- `SyncService.syncWorkoutData()` MUST fan out to every workoutBox
  prefix and the workout-domain healthBox keys. Currently:
  `_syncWorkoutLogs`, `_syncExerciseLogs`, `_syncScheduleCompletions`,
  `_syncWorkoutTemplates`, `_syncScheduledWorkouts`, `_syncStreaks`.
- `SyncService.syncNutritionData()` MUST fan out to every nutritionBox
  prefix. Currently: `_syncNutritionLogs`, `_syncWaterLogs`,
  `_syncSavedMeals`.

Adding a new Hive prefix in either domain requires updating the matching
`syncX()` AND the contract test
(`test/contracts/sync_fanout_contract_test.dart`).

The 2026-05-03 sync gap (templates / schedules / streaks invisible to
cloud for >24h, **with `scheduled_workouts.template_id` and
`user_saved_meals.id` silently uuid-rejecting since 2026-04-18**) was the
canonical multi-failure-mode this contract prevents. `weeklyFullSync()`
remains the safety net but is no longer the only path for workout-domain
or nutrition-domain rows reaching cloud.

### Restore-completeness sync (Theme A — Test #11, 2026-05-04)

Three additional ad-hoc sync methods exist outside the workout/nutrition
domain fan-outs. These cover surfaces that were Hive-only before Test #11
and silently lost on reinstall:

- `SyncService.syncFreezes()` — pushes `streak_freezes_{available, used_dates, last_refill}` into `user_progress`. Called from `WorkoutRepository.calculateCurrentStreak` (consume freeze) + `home_provider.StreakFreezeNotifier._refillIfNewWeek` (weekly refill).
- `SyncService.syncNotificationsInboxEntry(Map entry)` — upserts a single inbox entry to `notifications_inbox`. Called from `NotificationInboxService.record` after every Hive write.
- `SyncService.syncSavedDietPlan(Map planJson)` — upserts to `saved_diet_plans` (one row per user). Called from `diet_plan_screen._savePlan` after `UserRepository.saveDietPlan`.

Restore (`SyncService.restoreFromCloudForUser`) pulls these 3 surfaces +
`rank_promotions` history (last 20) + `coaching_notes` from `coach_memory`
+ folds `SubscriptionService.verifyFromServer(force: true)` as the final
restore step (was previously a separate post-auth hook in
`auth_provider.dart` — that callsite is kept as a fast-path fallback).

The `_*` private helpers in `sync_service.dart` are: `_restoreFreezes`,
`_restoreNotificationsInbox`, `_restoreSavedDietPlan`,
`_restoreRankPromotions`, `_restoreCoachMemory` (extended in Test #11 to
also pull `coaching_notes`).

Adding a new Hive-only surface that paying users would lose on reinstall
requires (1) a cloud column/table, (2) a `syncX()` method on SyncService,
(3) a `_restoreX()` method called from `restoreFromCloudForUser`, AND
(4) a contract test in `test/contracts/restore_completeness_writes_test.dart`
(currently 7 tests).
