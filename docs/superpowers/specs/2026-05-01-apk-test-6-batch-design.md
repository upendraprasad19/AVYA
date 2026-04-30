# APK Test #6 Batch — Workout + Nutrition Data Integrity, Coach Intelligence, Profile Restructure, Onboarding Fixes, Starting Stats, Rank Ladder Rebalance

**Status:** Spec — awaiting user review.
**Date:** 2026-05-01.
**Branch (planned):** `feat/apk-test-6-batch` off `feat/apk-test-5-batch` HEAD `42c4a35` (after Test #5 verifies on device + merges to main, this branch starts off main).
**Predecessor:** APK Test #5 batch shipped (+5 APK, 110.4 MB, prod release; built 2026-04-29). User installed and reported 21 observations across 4 batches; one full brainstorm session with the user converged on the 7 themes captured below.

---

## 1. Goals

1. **Workout data integrity is structural, not best-effort.** Every workout-touching code path (AI coach `logSet`, Active Workout save, Edit Sheet, plan generator, schedule swap, etc.) routes through one canonical `WorkoutWriteService`. One row per exercise per workout per CLAUDE.md §11 contract — duplicates become structurally impossible.
2. **Nutrition data integrity** mirrors workout's architecture. `NutritionWriteService` is the only writer for `nutrition_logs` + `nutrition_log_items`. Per-item cloud sync works end-to-end. Save / scan / AI-coach / cart / barcode / saved-meal-relog all share one validation + sync path.
3. **AI coach is grounded.** Coach reads today's nutrition from snapshot directly (no fictional READ-tool call); historical nutrition via new `getNutritionHistory` tool; multi-intent messages dispatch correctly; tool confirmation cards gate writes.
4. **Profile screen reorganized** around the user's mental model. Rank gets prominence (replaces Edit Profile button at top, with inline accordion expansion showing Service Record), Edit Profile moves to SETTINGS, Predictions moves to REPORTS, streak/freeze removed from Profile (lives on Home + Train + Nutrition + Coach status strips per Plan D).
5. **Mission Brief lands.** Copy rewritten in user's voice; founder photo bundled correctly.
6. **Onboarding edge cases fixed.** Mid-week joiners aren't punished by phase backdating; plan screen reads actual `days_per_week`; weight graph seeds from onboarding entry; streak freeze chip duplicate eliminated.
7. **Starting stats system** captures user transformation over time — auto on rank promotion + manual any time + tiered (minimal at onboarding, deepen later with measurements/photos). Promotion-day celebration overlay (navy style) makes rank advancement memorable.
8. **Rank ladder rebalanced** for realism. Hybrid sailor (streak-primary) / officer (completion-rate primary). New Lt rank inserted between SubLt and LtCdr. Numbers reflect achievable consistency, not punishing absolutism.

## 2. Source observations (21 total from 2026-04-30 to 2026-05-01 device install)

| # | Observation | Theme |
|---|---|---|
| 1 | Mission Brief founder photo missing (empty circle) | E |
| 2 | Mission Brief copy too "AI slob" | E |
| 3 | `scheduled_workouts = 0` in cloud (plan generated locally, never synced) | A |
| 4 | Plan screen "FOUNDATION · 4 days/week" hardcoded despite user selecting 6 | F |
| 5 | Onboarding weight should appear as first point on home weight graph | F |
| 6 | Capture starting-stats snapshot for year-1 transformation comparison | F |
| 7 | Calendar shows wasted Mon/Tue when user joined Wed | F |
| 8 | Roadmap math (LT CDR W156, CDR W208) — sanity check | G |
| 9 | Streak freeze chip rendered twice (one inline + one separate) | F |
| 10 | AI coach replied wrong to "move today's workout to Friday" — interpreted swap as log | B |
| 11 | Confirm cards persist; "Logged" pills don't dismiss + writes happen without explicit Apply | B |
| 12 | After AI coach log, workout screen still shows old workout (no provider invalidation) | A |
| 13 | "How do we save meals?" — Save Meals path not discoverable | C |
| 14 | AI coach said "I don't have ability to look up past food logs" | B |
| 15 | Free message counter doesn't decrement after food logging via AI text mode | B |
| 16 | Multiple `logSet` calls created 6 duplicate Lat Pulldown rows in cloud (instead of 1) | A |
| 17 | Edit Profile option should be repositioned as a tab under Settings (remove from top) | D |
| 18 | Predictions card should move under Reports section | D |
| 19 | Rank pill should replace Edit Profile at top of Profile, with dropdown popup | D |
| 20 | Edit Sheet "Review sets" shows duplicate Lat Pulldown summary row | A |
| 21 | Need delete-logged-food UX with calorie reflection | C |
| 22 | AI text analysis counter (Log Food sheet) doesn't decrement after successful analysis | C |
| 23 | Scan-meal save: server has top-level row but ZERO `nutrition_log_items`; UI doesn't refresh | C |

(observations 22 + 23 surfaced during the brainstorm Supabase verification step)

---

## 3. Architectural principles (cross-cutting)

These rules apply across all themes — implementations must respect them.

### 3.1 IST throughout

All date/time logic in the app derives "today" from IST (Asia/Kolkata, UTC+5:30):
- `WorkoutWriteService.logExercise(date)` — `date` parameter is IST-derived
- `nutrition_logs.date` field — derived from device IST
- `phase_started_at` stamp — IST date of onboarding completion
- Calendar week starts Monday IST
- AI snapshot's `meals_today` window — IST midnight to IST now
- Streak calculation crosses calendar boundaries via IST
- Daily counter resets (`UsageCounterService.checkAndResetCounters`) trigger at IST midnight

Server-side queries that use `CURRENT_DATE` must be IST-aware (set session timezone OR pass IST date as parameter).

### 3.2 Single canonical source of truth per concept

- **Rank:** `user_profile.current_rank_code` (denormalized; written by `RankService.evaluateAndPromote`)
- **Workout exercise summary:** `WorkoutWriteService` (only writer)
- **Nutrition meal log:** `NutritionWriteService` (only writer)
- **Streak count:** `WorkoutRepository.calculateCurrentStreak()` (schedule-aware, rest-day-invisible)
- **Plan parameters:** `user_profile.{primary_goal, fitness_experience, days_per_week, equipment_access, session_duration_minutes, physique_focus, injuries, pace_preference}`
- **Today's nutrition:** snapshot's `meals_today` field — coach reads directly from snapshot, no tool call

### 3.3 Fire-and-forget sync (CLAUDE.md §15 enforced)

Every `WorkoutWriteService` and `NutritionWriteService` method internally fires:
```dart
unawaited(SyncService.instance.syncWorkoutData());  // or syncNutritionData()
unawaited(SyncService.instance.pushSnapshot());
```
Hive write succeeds → return success even if cloud sync deferred. Cloud catches up on next snapshot push.

### 3.4 Provider invalidation as a canonical batch

Each service method invalidates the same canonical provider list. No callsite should manually invalidate; the service does it.

**Workout invalidation batch:** `currentPlanProvider`, `todayWorkoutProvider`, `calendarWeekProvider`, `streakProvider`, `allExercisePRsProvider`, `workoutStatsProvider`, `aiInsightProvider`.

**Nutrition invalidation batch:** `dailyNutritionProvider`, `nutritionSummaryProvider`, `recentFoodLogsProvider`, `macroTargetsProvider`, `aiInsightProvider`.

---

## 4. Theme A — Workout Data Integrity (4 obs)

### 4.1 Goals

- Bug class extinction: duplicate `workout_log_exercises` rows from multi-call `logSet` (#16) become structurally impossible.
- Plan generator's `scheduled_workouts` actually reach cloud (#3).
- Workout screen reflects AI coach actions immediately (#12).
- Edit Sheet shows one row per exercise, not per `logSet` call (#20).

### 4.2 New service: `lib/core/services/workout_write_service.dart`

```dart
class WorkoutWriteService {
  WorkoutWriteService._();
  static final instance = WorkoutWriteService._();

  /// Per-(date, exerciseName) mutex for concurrency safety.
  final Map<String, Lock> _exerciseLocks = {};

  /// Upserts a single exercise log on (date, exerciseName).
  /// MERGES sets[] into existing entry if present (per CLAUDE.md §11 contract).
  /// Per-set dedup: if a (weight, reps) tuple already exists in sets[] within
  /// last 60 seconds, drop as duplicate restatement.
  Future<WriteResult> logExercise({
    required DateTime date,                 // IST-derived
    required String exerciseName,
    required List<ExerciseSet> sets,        // (weightKg, reps, durationSec?)
    String? notes,
    required WriteSource source,            // active_workout|ai_coach|edit_sheet|...
  });

  /// Marks a workout as complete + writes wlog_*. Updates schedule status.
  Future<WriteResult> markCompleted({
    required DateTime date,
    required String workoutName,
    required int durationSec,
    int? rpe,
  });

  /// Writes/upserts a schedule_<date> entry (plan generator path).
  Future<WriteResult> upsertScheduled({
    required DateTime date,
    required ScheduleEntry entry,
  });

  /// Atomically moves one day's schedule from→to (used by rescheduleDay tool).
  Future<WriteResult> rescheduleDay({
    required DateTime fromDate,
    required DateTime toDate,
  });

  /// Regenerates an entire week (used by edit_profile + AI coach `regenerateWeek`).
  Future<WriteResult> regenerateWeek({
    required DateTime fromDate,
    required PlanParams params,
  });

  /// Edits an existing log atomically. Used by Edit Sheet + AI coach editLog.
  Future<WriteResult> editLog({
    required String logKey,
    required Map<String, dynamic> updates,
  });

  /// Soft-deletes with optional undo (matches Nutrition delete pattern).
  Future<WriteResult> deleteLog({
    required String logKey,
    bool allowUndo = true,
  });
}

class WriteResult {
  final bool success;
  final String? logKey;
  final String? errorMessage;
  WriteResult({required this.success, this.logKey, this.errorMessage});
}

enum WriteSource { activeWorkout, aiCoach, editSheet, planGenerator, schedSwap, restore }
```

### 4.3 Internal contract per method

Each method does:

1. **Validate input** — reps > 0, weight ≥ 0, exerciseName non-empty, etc.
2. **Acquire mutex** for `(date, exerciseName)` (or `date` for schedule-only methods).
3. **Compute deterministic Hive key** — e.g., `exlog_<istDateStr>_<hash(exerciseName)>` for exercise logs (NOT timestamp-based — this is the dedup mechanism).
4. **Read existing Hive entry** (if upsert).
5. **Merge logic for `logExercise`:**
   - If existing entry exists, append new sets to existing `sets[]` array.
   - **Per-set dedup:** if a `(weightKg, reps)` tuple already exists in current `sets[]` AND was logged within last 60 seconds, drop as duplicate restatement (defends against AI coach re-emission).
   - Recompute aggregate fields: `set_number = sets.length`, `reps_completed = sum`, `weight_kg = max`, `volume_kg = sum(weight × reps)`.
   - Recompute `is_pr` by chronologically rescanning all logs of this exercise (existing pattern from `EditWorkoutLogSheet`).
6. **Write Hive** (single `put`).
7. **Fire fire-and-forget cloud sync** (`syncWorkoutData` + `pushSnapshot`).
8. **Invalidate canonical provider batch** (workout invalidation list).
9. **Return WriteResult.**
10. **Release mutex.**

### 4.4 Cloud schema upgrade — 3-tier

`nutrition_log_sets` table is currently empty (per CLAUDE.md §11 "not used by current Flutter logger"). Plan A turns it on:

- `WorkoutWriteService._syncToCloud(exlogKey)` writes:
  - 1 row to `workout_logs` (workout-level)
  - 1 row to `workout_log_exercises` (exercise summary — `set_number=4, reps=37, weight_kg=100`)
  - **N rows to `workout_log_sets`** (per-set detail — one row per `ExerciseSet`)

- Per-set rows preserve granularity for cloud restore + AI coach historical queries ("you did 100×7 last Tuesday — try 105 today").

- Sync uses upsert: `ON CONFLICT (workout_log_id, exercise_id, set_number) DO UPDATE` for `workout_log_sets`.

### 4.5 Migration of all 7+ callsites

| Callsite | Old pattern | New pattern |
|---|---|---|
| AI coach `logSet` (tool dispatcher) | direct `workoutBox.put(exlog_<ts>_<hash>, ...)` per-set | `WorkoutWriteService.instance.logExercise(date: today, exerciseName: ..., sets: [all sets at once])` |
| AI coach `markWorkoutComplete` | direct writes | `WorkoutWriteService.instance.markCompleted(...)` |
| AI coach `swapExercise` / `rescheduleWeek` / `pausePlan` | direct schedule writes | `WorkoutWriteService.instance.rescheduleDay(...) / regenerateWeek(...)` |
| Active Workout screen Save button | manual writes via `train_provider` | `WorkoutWriteService.instance.logExercise + markCompleted` |
| Edit Sheet "Save changes" | rewrites Hive log map in place | `WorkoutWriteService.instance.editLog(...)` |
| Plan generator (REPORT FOR DUTY) | `WorkoutScheduleService.generateAndScheduleFromDate` writes schedule_* keys, **no sync call** | Wraps each schedule_* write in `WorkoutWriteService.instance.upsertScheduled(...)` so sync fires (closes #3) |
| Edit Profile regen path | `generateAndScheduleFromDate` | Same — routes through new service |
| Schedule swap UI (manual day swap on Train tab) | `WorkoutScheduleService.swapDay` | `WorkoutWriteService.instance.rescheduleDay(...)` |
| Delete log (Edit Sheet trash icon) | `workoutBox.delete(exlogKey)` | `WorkoutWriteService.instance.deleteLog(...)` |

**Hive `exlog_*` key scheme changes:** from `exlog_<timestamp>_<hash(name)>` to `exlog_<istDateStr>_<hash(name)>`. Key is now deterministic per `(date, exerciseName)`. Migration: on first launch with new APK, walk all `exlog_*` keys, re-hash to new key scheme, dedupe entries with same new key (merge sets, keep latest data).

### 4.6 Tests

`test/workout_write_service/`:
- `logExercise_dedups_sets_within_60s_test.dart` — same (weight, reps) twice within 60s → 1 entry in sets[]
- `logExercise_appends_sets_across_calls_test.dart` — multiple calls same day same exercise → one row, sets[] grows
- `logExercise_new_day_creates_new_entry_test.dart` — same exercise next day → new row
- `logExercise_concurrency_test.dart` — two simultaneous logExercise calls for same exercise → mutex serializes; final state has both sets merged
- `markCompleted_updates_schedule_status_test.dart` — marks schedule_<date> status='completed' + invalidates providers
- `upsertScheduled_fires_sync_test.dart` — closes #3 (verify `unawaited(syncWorkoutData)` invoked)
- `editLog_recomputes_pr_chronologically_test.dart` — edit a past log → re-scan PRs
- `deleteLog_invalidates_providers_test.dart` — delete → all providers refresh
- `migration_old_exlog_keys_test.dart` — old timestamp keys re-hash to deterministic keys + dedup

### 4.7 Estimate

~17-24h (4-6h design + service core + tests; 4-6h migration of Active Workout + Edit Sheet; 2-3h AI coach tools migration; 2h plan generator + edit profile regen; 2-3h schedule swap; 2-3h regression buffer).

---

## 5. Theme B — AI Coach Intelligence (4 obs)

### 5.1 Goals

- Multi-intent messages dispatch correctly (#10 — "I did back today + move workout to Friday" should fire BOTH log and reschedule, not interpret as single ambiguous intent).
- Confirm cards gate writes (#11 — Apply tap required before Hive write; cards auto-dismiss after dispatch; no stale Logged pills).
- Coach reads today's nutrition from snapshot directly (#14 — no fictional tool call); historical nutrition via new `getNutritionHistory` tool.
- Free message counter increments correctly across all entry points (#15 — `food_text_analysis` channel writes count toward visible counter).

### 5.2 #10 Tool selection — system prompt hardening

`_shared/captain_manual.ts` Section X (tool selection) gets a new subsection:

```markdown
## Multi-intent messages

When a user message contains MULTIPLE intents (e.g., "I did X today" AND "move
Y to Z"), dispatch BOTH tool calls in the same turn. Do NOT collapse them into
a single intent.

Examples:
- "I did back today. Move Friday's pull workout to today and today's pull to
  Friday."
  → emit two intents:
    1. `logSet` for back exercises (parse the workout description)
    2. `rescheduleDay` from Friday to today + Today to Friday

- "Mark today as rest. I went on a long walk instead."
  → emit two intents:
    1. `pausePlan` for today (mark rest)
    2. `logActivity` (cardio walk) — if user provides duration

DO NOT default to "asking for clarification" when intents are clearly
separable. Only ambiguous messages need clarification.
```

Plus tool descriptions in `_shared/tools/registry.ts` get explicit `selection_hints`:
- `logSet.selection_hints`: "Use when user describes completed sets (with weight/reps). Don't use when user is asking to reschedule."
- `rescheduleDay.selection_hints`: "Use when user wants to MOVE a workout to a different day. Distinct from logging."
- `pausePlan.selection_hints`: "Use when user wants today (or a future day) marked as rest."

### 5.3 #11 Tool dispatcher confirmation gate

Modify `lib/features/ai_coach/services/tool_dispatcher.dart`:

- All "reviewable" class tool intents render a confirm card with explicit `[APPLY] [DISMISS]` buttons (no chevron-only pattern).
- `dispatch(intent)` fires ONLY after Apply tap (Hive marker `intent_<id>_dispatched_at` written immediately).
- After successful dispatch, the chat-thread filter hides cards with `dispatched_at != null`.
- Stale cards (`createdAt > 1h ago without dispatch`) auto-mark as expired and grey out.
- Visual terminal state pill: ✓ "Applied" (gold) / ✗ "Dismissed" (grey) / ⏰ "Expired" (grey-italic).

### 5.4 #14 Coach grounding for nutrition

**Today's food** — coach reads `snapshot.meals_today` directly. System prompt instructs:

```markdown
## Today's nutrition

Today's food, calories, and macros are PROVIDED IN YOUR SNAPSHOT under
`meals_today`, `calories_consumed_today`, `protein_today`, `carbs_today`,
`fat_today`. When the user asks about today's food, respond directly from
this data. DO NOT call any tool — the data is already in your context.
```

**Historical food** — new READ tool `getNutritionHistory` in `_shared/tools/nutrition/`:

```typescript
{
  name: "getNutritionHistory",
  description: "Returns aggregated nutrition data for a past date range. Use when user asks about food on past dates (e.g., 'what did I eat last Tuesday', 'protein average last week').",
  parameters: {
    date_from: { type: "string", format: "YYYY-MM-DD" },
    date_to: { type: "string", format: "YYYY-MM-DD" },
    aggregation: { type: "string", enum: ["per_day", "total"] }
  }
}
```

Server-side handler queries `nutrition_logs` + `nutrition_log_items` for the user/date range, returns aggregated data. Tool registered for both free + PRO users.

### 5.5 #15 Counter wiring across entry points

The `Log Food sheet` AI tab counter (`ai_text_log_count_today` Hive key, decremented via `UsageCounterService.increment(featureAiTextLogPro)`) currently only increments from `food_logger_section.dart::_handleAnalyse`. AI coach chat path (`logMealByText` tool dispatcher) does NOT increment.

Fix: AI coach `logMealByText` tool's success handler in dispatcher calls `UsageCounterService.instance.increment(AppConstants.featureAiTextLogPro, isPro)`. Same for `scan_meal` (when AI coach can scan via tool) and `cart_auditor`.

User-visible behavior: chat-based food log decrements the same counter as Log Food sheet AI tab. Both caps still enforced server-side via migration 024 trigger.

### 5.6 Tests

`test/ai_coach/`:
- `multi_intent_dispatch_test.dart` — "I did X + move Y" emits 2 ToolIntents
- `confirm_gate_no_double_tap_test.dart` — Apply fires once even on rapid taps
- `dismiss_card_terminal_state_test.dart` — Dismiss flips status; card visually changes
- `dispatched_card_filter_test.dart` — chat thread hides cards with `dispatched_at != null`
- `today_nutrition_no_tool_call_test.dart` — coach answers "what did I eat today" without tool call
- `get_nutrition_history_tool_test.dart` — tool returns expected aggregate for date range
- `food_log_counter_increments_from_chat_test.dart` — chat-based food log → counter -1

### 5.7 Estimate

~7-10h (1-2h system prompt + tool descriptions; 2-3h dispatcher gate; 1-2h getNutritionHistory tool; 1h counter wiring; 2-3h tests).

---

## 6. Theme C — Nutrition Data Integrity (5 obs)

### 6.1 Goals

- Nutrition writes follow same architectural pattern as workouts (#22, #23 both rooted in fragmented sync paths).
- Per-item rows (`nutrition_log_items`) sync to cloud reliably (root cause of #23).
- UI providers refresh after every save (root cause of #23 + #22 perception).
- Counter increments work across all 8 entry points (#15 cross-cut + #22 nutrition path).
- Empty-row prevention (no more 0-cal "snacks" rows in cloud).
- Delete-logged-food UX with calorie reflection (#21).
- Save Meals path discoverable + functional (#13).

### 6.2 New service: `lib/core/services/nutrition_write_service.dart`

```dart
class NutritionWriteService {
  NutritionWriteService._();
  static final instance = NutritionWriteService._();

  /// Creates a nutrition_logs row + N nutrition_log_items rows atomically.
  /// Validates input (cal >= 0, items non-empty, mealType in valid set).
  /// Increments the right counter based on source.
  Future<WriteResult> logMeal({
    required DateTime date,                    // IST-derived
    required String mealType,                  // breakfast|lunch|dinner|snacks
    required List<FoodItem> items,
    int? overrideTotalCals,                    // optional (Atwater fallback if null)
    int? overrideTotalProtein,
    required NutritionWriteSource source,      // ai_text|scan|cart|manual_search|...
  });

  /// Appends items to an existing meal slot.
  Future<WriteResult> appendItemsToMeal({
    required String existingLogKey,
    required List<FoodItem> additionalItems,
  });

  /// Edits an existing log (used by edit-meal sheet).
  Future<WriteResult> editLog({
    required String logKey,
    required Map<String, dynamic> updates,
  });

  /// Soft-deletes with undo (matches DeleteNutritionLogNotifier pattern).
  Future<WriteResult> deleteLog({
    required String logKey,
    bool allowUndo = true,
  });

  /// Water log atomic write.
  Future<WriteResult> logWater({
    required DateTime date,
    required int ml,
    int? urineColor,
  });

  /// Re-log a saved meal (template) into a new log entry.
  Future<WriteResult> relogSavedMeal({
    required String savedMealKey,
    required DateTime date,
    required String mealType,
  });

  /// Promote an existing log to a saved meal template.
  Future<WriteResult> saveMealAsTemplate({
    required String sourceLogKey,
    String? customName,
  });
}

enum NutritionWriteSource {
  manualSearch,
  aiText,
  scan,
  cart,
  barcode,
  savedMealRelog,
  aiCoachTool,
  prelog,
}
```

### 6.3 Internal contract

Each method:
1. Validate (cals ≥ 0, items.isNotEmpty for `logMeal`, mealType in allowed set, etc.).
2. Compute deterministic Hive key (`nlog_<istDateStr>_<mealType>_<hash(items)>` for `logMeal`).
3. **CRITICAL: Reject empty saves.** If items is empty AND no override totals, fail validation. Closes the "0-cal ghost row" bug (4 of 6 rows in cloud were ghosts).
4. Hive write `nlog_<key>` with full payload (top-level totals + items array).
5. **Cloud sync writes BOTH tables in one transaction:**
   - `nutrition_logs` row (top-level totals) — UPSERT on deterministic UUID
   - N `nutrition_log_items` rows (per-food) — INSERT (or upsert if existing)
6. **Counter increment per source:**
   - `aiText` / `aiCoachTool` (text mode) → `UsageCounterService.increment(featureAiTextLogPro)`
   - `scan` → `featureScanMealPro`
   - `cart` → `featureCartAuditorPro`
   - `manualSearch` / `barcode` / `savedMealRelog` / `prelog` → no counter (free unlimited)
7. **Provider invalidation batch.**
8. Fire-and-forget cloud sync.
9. Return WriteResult.

### 6.4 Migration of all 8 callsites

| Callsite | New pattern |
|---|---|
| Manual search → add (in `food_search_sheet.dart`) | `NutritionWriteService.instance.logMeal(source: manualSearch, ...)` |
| AI text mode (`food_logger_section.dart`) | `logMeal(source: aiText, ...)` |
| Scan mode save (`scan_meal_section._ScanResultEditor.save`) | `logMeal(source: scan, ...)` — fixes #23 per-item sync gap |
| Cart auditor save | `logMeal(source: cart, ...)` |
| Barcode save | `logMeal(source: barcode, ...)` |
| Saved meal re-log | `relogSavedMeal(...)` |
| AI coach `logMealByText` tool | `logMeal(source: aiCoachTool, ...)` |
| AI coach `prelog` tool | `logMeal(source: prelog, ...)` |
| Edit sheet save | `editLog(...)` |
| Delete UI (NEW for #21) | `deleteLog(...)` with undo snackbar |

### 6.5 Delete UX (#21) + calorie reflection

- **Long-press on a logged meal row** in nutrition screen → context menu with "Delete" + "Edit" + "Save as template."
- **Delete tap** → confirm sheet showing the meal preview + "Delete this meal" / "Cancel."
- On Delete: `NutritionWriteService.deleteLog(logKey)` runs:
  - Stash the log entry (for undo)
  - Remove `nlog_<key>` from Hive
  - Cascade-delete `nutrition_logs` + `nutrition_log_items` from cloud
  - Invalidate provider batch → daily macro card immediately reflects updated calories/protein/etc.
  - Show snackbar with "UNDO" button (10s timeout)
- Undo restores via `restoreFoodLog` (existing pattern in `nutrition_provider.dart`).

### 6.6 Save Meals UX (#13)

- Each logged meal row gets a long-press menu option "Save as template."
- Tapping fires `NutritionWriteService.saveMealAsTemplate(sourceLogKey)`.
- Template appears in the SAVED MEALS tab of LogFood sheet next time user opens.
- Each saved meal renders: meal name (editable), item list, total cals/protein, "Re-log" CTA.

### 6.7 Tests

`test/nutrition_write_service/`:
- `logMeal_creates_logs_and_items_atomically_test.dart`
- `logMeal_rejects_empty_items_test.dart` — closes the 0-cal ghost row bug
- `logMeal_increments_counter_per_source_test.dart` (8 sources × counter check)
- `deleteLog_with_undo_test.dart`
- `saveMealAsTemplate_creates_saved_meal_test.dart`
- `relogSavedMeal_creates_new_log_test.dart`
- Migration test: existing `flog_*` / old-pattern Hive keys re-key correctly

### 6.8 Estimate

~12-16h (4-5h service core; 2h tests; 4-6h migration of 8 callsites; 1-2h delete UX; 1h saved meals; 1-2h regression buffer).

---

## 7. Theme D — Profile Restructure (3 obs + 1 cross-cut)

### 7.1 Goals

- Rank takes prominent position at top of Profile, replacing current Edit Profile button (#19).
- Edit Profile moves to first row of existing SETTINGS section (#17).
- Predictions moves to REPORTS as a list row with preview text + bottom-sheet on tap (#18).
- Streak/freeze chips removed from Profile (live on Home/Train/Nutrition/Coach status strips per Plan D, Profile is special).
- Indian Navy rank insignia rendered via Flutter `CustomPaint` for all 11 ranks (incl. new Lt).

### 7.2 New widget: `lib/shared/widgets/wardroom/ward_rank_pill.dart`

```dart
/// Rank pill at top of Profile screen. Displays insignia + short-caps rank
/// name + chevron. Tap toggles inline accordion expansion below the pill.
class WardRankPill extends StatefulWidget {
  final String rankCode;            // e.g., 'SD2', 'LS', 'Cdr'
  final String shortCapsName;       // e.g., 'SEAMAN 2', 'LEADING SEAMAN', 'CDR'
  final Widget Function(BuildContext) expandedContentBuilder;

  const WardRankPill({
    required this.rankCode,
    required this.shortCapsName,
    required this.expandedContentBuilder,
    super.key,
  });

  // Internal state: bool _expanded; AnimationController for accordion
  // Tapping pill toggles expansion. Expanded content slides down.
}
```

**Pill content (collapsed):** `[insignia 24dp] [shortCapsName] [▾ chevron]`
**Expanded content (Service Record dropdown):** glanceable ladder (current rank highlighted + next 2-3 ranks below) + days/weeks to next promotion + "View full roadmap →" button routes to `/train/roadmap`. NO streak/freeze (those moved off Profile per Plan D).

Animation: 200ms ease-out vertical expand. Page below pill shifts down to make room.

### 7.3 New widget: `lib/shared/widgets/wardroom/ward_rank_insignia.dart`

```dart
/// Renders Indian Navy rank insignia via CustomPaint.
/// Themable via AppColors.accent (Campaign Gold), responsive to size param.
class WardRankInsignia extends StatelessWidget {
  final String rankCode;
  final double size;        // 16dp (chip) | 24dp (pill) | 48dp (popup)
  final Color? color;       // default: AppColors.accent
}
```

**Insignia mapping (via `CustomPaint`):**

| Rank | Painter |
|---|---|
| SD2 | empty circle (or text-only "SD2" centered) |
| SD1 | single chevron |
| LS | single anchor |
| PO | anchor + crown above |
| CPO | crossed anchors |
| MCPO | crown + crossed anchors + star above |
| Sub-Lt | 1 thin gold stripe + curl |
| Lt (NEW) | 2 thick gold stripes |
| Lt Cdr | 2½ stripes (2 thick + 1 thin) |
| Cdr | 3 thick stripes |
| Capt | 4 thick stripes |

**Stripe painter:** parametrized by stripe count + curl flag. Officer ranks paint horizontal stripes inside a rounded rectangle with `AppColors.accent` fill.

**Anchor / chevron / crown painters:** path-based geometric shapes inspired by Indian Navy regulations. Detail level scales with rank `size`.

### 7.4 Profile screen restructure

`lib/features/profile/screens/profile_screen.dart` ListView body order (top-to-bottom):

```
[ProfileIdentity widget]
  ├─ Banner (110dp) with floating "DOSSIER · OFFICER" eyebrow @ 65% alpha
  ├─ 80dp avatar overlapping banner
  ├─ Name (Fraunces 28sp)
  ├─ [Gold rule] (60dp wide)
  └─ NEW: WardRankPill at the position previously occupied by EDIT PROFILE button
       └─ Inline accordion expansion shows Service Record content

[NO status strip — streak/freeze removed from Profile]

[ProfileCompletenessCard]
[SlimAchievementsCard]
[Daily Completion]

SectionHeader('REPORTS')
├─ Predictions (list row, with preview line, bottom-sheet on tap)
└─ Progress Photos (list row, existing)

SectionHeader('SHARE & GROW')
└─ (existing rows: Invite Friends, Submissions)

SectionHeader('SETTINGS')
├─ Edit Profile (NEW first row)  ← moved from top
├─ Notifications
├─ Units
├─ Health Sync
├─ Privacy & Permissions
└─ Export My Data

SectionHeader('SUBSCRIPTION')
└─ (existing rows: Manage, Restore, etc.)
```

**Removed:**
- `YOUR PREDICTION` section header (Predictions moves to REPORTS)
- `Service Record` section (now lives inside WardRankPill expansion)
- Edit Profile button at top of ProfileIdentity
- Streak/freeze chips anywhere on Profile

### 7.5 Predictions row in REPORTS

```dart
ListTile(
  leading: Icon(Icons.auto_awesome_outlined, color: AppColors.accent),
  title: Text('Predictions'),
  subtitle: Text(
    _truncatedPredictionPreview(prediction, maxChars: 50),  // first 50 chars + "…"
    style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
  ),
  trailing: Icon(Icons.chevron_right),
  onTap: () => _showPredictionBottomSheet(context),
);
```

`_truncatedPredictionPreview` reads from `predictionProvider`. Bottom-sheet shows full prediction with "Read More" → existing prediction sheet UI.

### 7.6 Tests

`test/wardroom/ward_rank_insignia_test.dart` — golden tests for all 11 insignia at 24dp + 48dp.
`test/wardroom/ward_rank_pill_test.dart` — pill collapsed + expanded states.
`test/profile/profile_screen_layout_test.dart` — section order, no Edit Profile at top, Predictions in REPORTS.

### 7.7 Estimate

~5-7h (3-4h CustomPaint insignia for 11 ranks; 1h pill widget + animation; 1h Profile reorganization; 1h tests).

---

## 8. Theme E — Mission Brief Polish (2 obs)

### 8.1 #1 founder photo asset

- Verify `assets/founder/upendra.jpg` exists in repo (likely missing or path mismatch).
- Verify `pubspec.yaml` flutter.assets section includes `assets/founder/`.
- Test render in `MissionBriefScreen` widget.
- If asset is the wrong path, fix path in widget OR move asset to expected location.

### 8.2 #2 copy locked

`MissionBriefScreen` body copy replaced with the locked version (95 words):

```
Welcome aboard.

You're not joining an app. You're reporting in.

For 14 years I trained men in the Indian Navy. Discipline isn't motivation
— it's structure. A plan you can follow when you don't feel like it.

That's what AVYA is. The discipline of military training. The science of
certified coaching. Built for the long haul.

You do the work. AVYA holds the discipline.

Show up. Earn promotions. Become the man who lasts.

The AI runs the drills. The playbook is mine.

*Jai Hind.*
— Upendra
```

**Visual treatment:**
- Italic-gold for emphasis: "isn't motivation," "AVYA holds the discipline," "Show up. Earn promotions. Become the man who lasts," "The playbook is mine"
- "Jai Hind." rendered as italic Fraunces 14sp gold
- Signature "— Upendra" right-aligned at bottom
- Founder photo + "Upendra Prasad / Ex-Indian Navy · 14 Years / Certified Fitness + Nutrition Coach" header above body (existing layout)
- Subtle Instagram link below signature: `Daily wins on Instagram → @icanbefitter` (gold underline)

### 8.3 Estimate

~1-2h.

---

## 9. Theme F — Onboarding/Plan/Calendar + Starting Stats (5 obs)

### 9.1 #4 hardcoded "4 days/week"

`lib/features/onboarding/screens/plan_screen.dart` PhaseDescription text reads `widget.data['days_per_week']` (or fallback to user_profile) instead of hardcoded "4 days/week."

Same fix for any other hardcoded references discovered during audit (e.g., the FOUNDATION description on Plan screen Image 2).

### 9.2 #5 onboarding weight on home graph

Audit `lib/features/home/providers/home_provider.dart::weightHistoryProvider`:
- Confirm it reads from `weight_logs` Hive entries.
- Confirm onboarding writes a weight_logs entry (via `OnboardingNotifier.completeOnboarding`).
- If entry is written but provider doesn't read → fix provider.
- If provider reads correctly → fix onboarding to write the entry.

### 9.3 #9 streak freeze chip duplicate

Audit `WardStatusStrip` + `StreakBadge`:
- Identify whether `StreakBadge` already includes inline freeze count AND we're rendering a separate `WardFreezeBadge` next to it.
- Remove the duplicate (likely keep WardFreezeBadge as the primary; strip the inline count from StreakBadge).
- Verify on all 4 tabs that have the strip (Home, Train, Nutrition, Coach).

### 9.4 #7 phase mid-week join handling

Modify `lib/core/services/workout_schedule_service.dart::generateAndScheduleFromDate`:

**New rule: phase_started_at = onboarding date (IST), no Monday backdating.**

```dart
final phaseStartedAt = DateTime.now().toUtc();  // store as UTC; display as IST
final localDate = istDateOf(now);

// Calendar week containing onboarding day:
final weekStart = mondayOf(localDate);  // Mon of this week, for calendar display
final weekEnd = sundayOf(localDate);    // Sun of this week

// Auto-mark days BEFORE onboarding as 'rest' status (not 'missed'):
for (var d = weekStart; d.isBefore(localDate); d = d.add(Duration(days: 1))) {
  workoutBox.put('schedule_${dateStr(d)}', {
    'status': 'rest',
    'reason': 'pre_onboarding',
    'date': dateStr(d),
  });
}

// Distribute user's planned workouts across remaining days:
final remainingWorkoutDays = workoutDaysIn(localDate, weekEnd);  // M-Sat = workout, Sun = rest
final pendingWorkouts = remainingWorkoutDays;
// Generate schedule entries for remaining workout days only, using
// the user's selected days_per_week pattern (defaulting to M-Sat with Sun rest).
```

**Calendar display (Home tab + Train tab):**
- Always renders Mon-Sun (calendar consistency).
- Pre-onboarding days render with status='rest' + visual cue: light grey "Joined later" tag (not red "missed" / not normal "rest").
- Pending workouts count = scheduled days from today onwards.

**Promotion gate math (`_qualifies` in RankService):**
- `weeksSinceSignup` derives from `phase_started_at` (= onboarding date) NOT from week start.
- Streak counts from first scheduled workout day after onboarding.

**User experience:**
- Wed-joiner with 6/week plan → "Pending: 4 workouts" (W/Th/F/Sat). Sun rest day stays.
- Mon-joiner → "Pending: 6 workouts."
- No "missed" workouts for pre-onboarding days.

### 9.5 #6 starting stats system

#### 9.5.1 New table: migration `044_user_stat_snapshots.sql`

```sql
CREATE TABLE public.user_stat_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  snapshot_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  source TEXT NOT NULL CHECK (source IN ('onboarding', 'promotion', 'manual')),
  rank_at_snapshot TEXT,                    -- e.g., 'SD1' if source='promotion' to LS
  weight_kg NUMERIC,
  body_fat_pct NUMERIC,
  height_cm NUMERIC,                        -- snapshot-time (rare to change)
  age_years INT,
  measurements JSONB,                       -- {chest, waist, arms_l, arms_r, thighs_l, thighs_r}
  photos JSONB,                             -- [{url, taken_at, angle}]
  avg_calories_7d INT,
  avg_protein_7d INT,
  avg_steps_7d INT,
  avg_sleep_hours_7d NUMERIC,
  plan_phase INT,
  plan_week INT,
  primary_goal TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_uss_user_snapshot_at ON public.user_stat_snapshots(user_id, snapshot_at DESC);
```

#### 9.5.2 Service: `lib/core/services/stat_snapshot_service.dart`

```dart
class StatSnapshotService {
  /// Auto-snapshot on onboarding (zero-friction; uses user_profile data).
  Future<WriteResult> snapshotOnboarding();

  /// Auto-snapshot on rank promotion (called by RankService.evaluateAndPromote).
  Future<WriteResult> snapshotOnPromotion(String newRankCode);

  /// Manual snapshot triggered by user from Profile → "Take Snapshot Now" button.
  /// Optionally accepts measurements + photos.
  Future<WriteResult> snapshotManual({
    Map<String, double>? measurements,
    List<String>? photoUrls,
  });

  /// Returns all snapshots ordered by snapshot_at DESC.
  Future<List<UserStatSnapshot>> listAll();

  /// Returns oldest (onboarding) snapshot.
  Future<UserStatSnapshot?> baseline();

  /// Compares two snapshots (default: latest vs baseline) and returns diff.
  StatSnapshotDiff diff(UserStatSnapshot a, UserStatSnapshot b);
}
```

#### 9.5.3 UI surfaces

**Reports section row** (in Profile):

```dart
ListTile(
  leading: Icon(Icons.trending_up, color: AppColors.accent),
  title: Text('Progress Comparison'),
  subtitle: Text(
    _shortDiff(),  // e.g., "76.9 kg → 73.5 kg · 12 weeks"
    style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
  ),
  trailing: Icon(Icons.chevron_right),
  onTap: () => Navigator.push(... ProgressComparisonScreen ...),
);
```

`ProgressComparisonScreen` — full-screen view with:
- "Take Snapshot Now" button (top-right)
- List of snapshots (newest first)
- Tap any snapshot → diff view comparing to baseline (or to immediate prior)
- Side-by-side stats: weight then/now, body fat then/now, calories then/now, etc.

**Promotion-day celebration overlay** (mid-scope per Q22):

When `RankService.evaluateAndPromote` detects a new promotion:
1. Take auto-snapshot via `StatSnapshotService.snapshotOnPromotion`.
2. Push a navy-style full-screen overlay (`PromotionCelebrationScreen`):
   - **Animation:** insignia of new rank paints on (CustomPaint stripe-by-stripe over 1.5s).
   - **Header:** "PROMOTION DAY" in mono caps gold + horizontal gold rule.
   - **Ceremonial line:** "By order of the Captain — you are promoted to <rank.displayName>."
   - **Side-by-side stats:** baseline → today (weight, BF%, calories, protein, streak peak).
   - **Tap:** dismiss overlay → return to whatever screen user was on.
   - **Share button:** "Share this moment" → uses share_plus + qr_flutter to render an image with rank insignia + stats card → share to WhatsApp/IG.
3. Overlay shown ONCE per promotion (idempotent — `rank_promotions` UNIQUE(user_id, rank_code) prevents re-show).

#### 9.5.4 Tests

- `stat_snapshot_service/snapshotOnboarding_uses_profile_data_test.dart`
- `stat_snapshot_service/snapshotOnPromotion_called_after_rank_change_test.dart`
- `stat_snapshot_service/diff_baseline_vs_latest_test.dart`
- `promotion_celebration/overlay_renders_once_per_promotion_test.dart`
- `promotion_celebration/share_button_renders_image_test.dart` (golden)

### 9.6 Estimate

~12-18h (4-6h starting stats system: migration + service + UI; 5-7h promotion-day celebration overlay incl. CustomPaint stripe animation + share image gen; 1h #4 hardcoded fix; 1h #5 weight graph; 1h #9 streak freeze dedup; 1-2h #7 phase scheduling).

---

## 10. Theme G — Rank Ladder Rebalance (1 obs)

### 10.1 New ladder (11 rungs, with Lt added)

`lib/core/services/rank_ladder_data.dart::kRankLadder` — append new entry at ordinal 7 (Lt) and shift downstream ordinals:

| Ordinal | Code | Display name | Short caps | Min weeks | Insignia |
|---|---|---|---|---|---|
| 0 | SD2 | Seaman 2nd Class | SEAMAN 2 | 0 | (text) |
| 1 | SD1 | Seaman 1st Class | SEAMAN 1 | 1 | 1 chevron |
| 2 | LS | Leading Seaman | LEADING SEAMAN | 4 | 1 anchor |
| 3 | PO | Petty Officer | PETTY OFFICER | 12 | anchor + crown |
| 4 | CPO | Chief Petty Officer | CHIEF PO | 26 | crossed anchors |
| 5 | MCPO | Master Chief Petty Officer | MASTER CHIEF | 52 | crown + crossed anchors + star |
| 6 | SubLt | Sub Lieutenant | SUB LT | 104 | 1 thin stripe + curl |
| **7** | **Lt** | **Lieutenant** | **LIEUTENANT** | **130** | **2 thick stripes** |
| 8 | LtCdr | Lieutenant Commander | LT CDR | 156 | 2½ stripes |
| 9 | Cdr | Commander | CDR | 208 | 3 stripes |
| 10 | Capt | Captain | CAPTAIN | 260 | 4 stripes |

### 10.2 New gates

`kRankGates` rewrites:

```dart
const Map<String, RankGate> kRankGates = {
  'SD2': RankGate(),
  // SD1: STRICT 7-day streak (per Q27 = α). 1 week elapsed clock starts ticking
  // from onboarding date (phase_started_at, IST).
  'SD1': RankGate(streakAtLeast: 7, minWeeksSinceSignup: 1),

  // Sailor track — streak primary, re-balanced for realism
  'LS': RankGate(streakAtLeast: 14, minWeeksSinceSignup: 4),                          // was 16
  'PO': RankGate(streakAtLeast: 30, minWeeksSinceSignup: 12, deploymentsCompleteAtLeast: 2),  // was 60+1
  'CPO': RankGate(streakAtLeast: 50, minWeeksSinceSignup: 26, deploymentsCompleteAtLeast: 3), // was 100+2

  // MCPO transition rank — completion-rate primary (smooths sailor → officer)
  'MCPO': RankGate(
    minWeeksSinceSignup: 52,
    completionRateMinimum: 0.80,
    completionRateWindowWeeks: 12,
    maxGapDays: 14,
  ),

  // Officer track — completion-rate primary, no streak requirement
  'SubLt': RankGate(
    minWeeksSinceSignup: 104,
    completionRateMinimum: 0.80,
    completionRateWindowWeeks: 26,
  ),
  'Lt': RankGate(
    minWeeksSinceSignup: 130,
    completionRateMinimum: 0.80,
    completionRateWindowWeeks: 26,
  ),
  'LtCdr': RankGate(
    minWeeksSinceSignup: 156,
    completionRateMinimum: 0.80,
    completionRateWindowWeeks: 52,
  ),
  'Cdr': RankGate(
    minWeeksSinceSignup: 208,
    completionRateMinimum: 0.80,
    completionRateWindowWeeks: 52,
  ),
  'Capt': RankGate(
    minWeeksSinceSignup: 260,
    completionRateMinimum: 0.85,
    completionRateWindowWeeks: 104,
  ),
};
```

Add `RankGate` fields:
```dart
class RankGate {
  final int? streakAtLeast;
  final int? totalWorkoutsAtLeast;
  final int? deploymentsCompleteAtLeast;
  final int? minWeeksSinceSignup;
  final int? maxGapDays;
  final double? completionRateMinimum;        // NEW: 0.0-1.0
  final int? completionRateWindowWeeks;       // NEW: lookback window
  // ...
}
```

### 10.3 Streak definition (locked Q26 = a)

`WorkoutRepository.calculateCurrentStreak()`:
- Returns count of consecutive completed scheduled-workout days (rest days invisible, neither count nor break).
- Resets to 0 if any scheduled workout day is missed (status != 'completed').
- Counts from earliest user anchor (`phase_started_at` IST) — no pre-onboarding days included.

### 10.4 Completion rate calculation (new)

`WorkoutRepository.completionRateOverWindow(int windowWeeks)`:

```dart
double completionRateOverWindow(int windowWeeks) {
  final now = DateTime.now().toUtc();
  final windowStart = now.subtract(Duration(days: windowWeeks * 7));
  int scheduled = 0;
  int completed = 0;
  for (var d = windowStart; d.isBefore(now); d = d.add(Duration(days: 1))) {
    final entry = workoutBox.get('schedule_${istDateStr(d)}');
    if (entry == null) continue;
    if (entry['status'] == 'rest' || entry['reason'] == 'pre_onboarding') continue;
    scheduled++;
    if (entry['status'] == 'completed') completed++;
  }
  return scheduled == 0 ? 0.0 : completed / scheduled;
}
```

Used by `RankService._qualifies()` for ranks with `completionRateMinimum`.

### 10.5 Server-side mirror

`supabase/functions/_shared/rank_engine.ts` — same gate logic ported. Mirror `kRankLadder` table seed (migration 045 — add Lt + update gate metadata).

### 10.6 Roadmap label clarity (#8)

`lib/features/train/widgets/roadmap_screen.dart` (or wherever) — change rank gate labels from `W156` to `WEEK 156` or `156 WEEKS`. Eliminates the "is this workouts or weeks?" confusion.

### 10.7 Tests

- `rank_service/sd1_strict_streak_test.dart` — 7-streak required
- `rank_service/sd1_wed_joiner_unlocks_day_8_test.dart` — Wed joiner with 6/week plan unlocks SD1 on Wed of week 2
- `rank_service/cpo_50_streak_with_2_phases_test.dart` — re-balanced threshold
- `rank_service/officer_completion_rate_test.dart` — SubLt requires ≥80% over last 26 weeks
- `rank_service/lt_inserted_at_ordinal_7_test.dart` — Lt rank lookup
- `workout_repository/completion_rate_calculation_test.dart` — windowed % math
- `rank_engine_ts/server_client_parity_test.ts` — server engine matches client

### 10.8 Estimate

~4-6h (1h ladder + gates code; 1h completion rate calc; 1-2h server mirror + migration; 1-2h tests).

---

## 11. Sequencing + risks

### 11.1 Order (most foundational first)

1. **Theme A** (WorkoutWriteService) — biggest architectural change; everything else can layer on top
2. **Theme C** (NutritionWriteService) — same pattern, different domain
3. **Theme G** (Rank ladder) — used by Theme F's promotion celebration; small but foundational
4. **Theme F** (Onboarding/calendar/starting stats) — depends on G (promotion trigger) + A (workout completion → rank evaluation)
5. **Theme B** (AI coach intelligence) — depends on A + C (services routing)
6. **Theme D** (Profile restructure) — independent; depends only on G (rank insignia)
7. **Theme E** (Mission Brief) — independent; smallest scope, ship anytime

### 11.2 Risk register

| Risk | Theme | Mitigation |
|---|---|---|
| Service migration breaks Active Workout flow | A, C | Migrate AI coach paths first (worst offenders); Active Workout last (works today; lowest urgency); golden test before/after |
| 60s per-set dedup window too aggressive (rejects legitimate same-(weight, reps) sets logged quickly) | A | Test with real workout log (e.g., 5×5 squat with same weight+reps each set); if false positives, raise to longer window or use Hive write timestamp |
| Per-item cloud sync schema breaks restore (existing `nutrition_log_items` orphans) | C | Migration cleanup script: delete items where log_id has no matching log (one-time) |
| Rank promotion celebration overlay blocks user navigation if buggy | F | Tap-to-dismiss is always available; overlay has 30s auto-dismiss safety; logged via debugPrint for fail-soft |
| Completion-rate calculation expensive (loops over weeks of schedule) | G | Cache result in `user_progress.completion_rate_cache` + recompute on workout completion event only |
| IST timezone migration has edge cases at midnight | All | Use `intl` package for IST conversion; explicit unit tests for date boundary cases |
| 11-rank ladder + Lt insertion breaks existing user `current_rank_code` | G | Test #5 already wiped — no live users at risk; migration safe-by-construction |

### 11.3 Total estimate

| Theme | Hours |
|---|---|
| A | 17-24 |
| B | 7-10 |
| C | 12-16 |
| D | 5-7 |
| E | 1-2 |
| F | 12-18 |
| G | 4-6 |
| **Total** | **58-83** ≈ **7-10 working days** |

---

## 12. Test-prep + verification criteria

### 12.1 Test-prep before next APK install

```sql
DELETE FROM auth.users
WHERE email IN ('upendra.prasad@thinkingcode.com', 'avyaaanshfit@gmail.com');
```

(per migration 039 cascade chain)

### 12.2 Success criteria (on-device)

| # | Criterion | Source obs |
|---|---|---|
| **C1** | Sign up fresh → use AI coach to log a workout (e.g., "lat pulldown 4 sets 40×10 60×10 80×10 100×7") → cloud `workout_log_exercises` shows ONE row, not multiple. `set_number=4`, `weight_kg=100`, `reps=37`. | A (#16, #20) |
| **C2** | Same workout — query cloud `workout_log_sets` → 4 rows (per-set granularity intact). | A |
| **C3** | Onboard mid-week (Wed) → REPORT FOR DUTY → cloud `scheduled_workouts` has 4 rows for remaining workout days; pre-Wed days have status='rest' with reason='pre_onboarding'. | A (#3), F (#7) |
| **C4** | After AI coach logs a workout → tab to Workout screen → today's session shows status='completed', not the pre-completion state. | A (#12) |
| **C5** | Log food via AI text mode → counter decrements from 10 → 9 visibly. | C (#22), B (#15) |
| **C6** | Scan a meal → save → cloud has BOTH `nutrition_logs` row AND N `nutrition_log_items` rows. UI nutrition macro card refreshes immediately to reflect new calories. | C (#23) |
| **C7** | Long-press a logged meal → "Delete" → meal disappears + UNDO snackbar appears + macro card recalculates. | C (#21) |
| **C8** | Log food → "Save as template" → tab to Saved Meals → template appears with re-log CTA. | C (#13) |
| **C9** | AI coach: ask "what did I eat today?" → coach answers from snapshot data without calling a tool. | B (#14) |
| **C10** | AI coach: ask "what did I eat last Tuesday?" → coach uses `getNutritionHistory` tool. | B (#14) |
| **C11** | AI coach: send "I did back today + move Friday's pull workout to today" → coach emits BOTH log AND reschedule intents (2 confirm cards). | B (#10) |
| **C12** | Confirm card: tap APPLY → write happens → card transitions to terminal pill ✓ "Applied" + auto-dismisses from active list. | B (#11) |
| **C13** | Profile: rank pill at top with Indian Navy insignia. Tap → inline accordion expands showing Service Record. NO streak/freeze chips on Profile. | D (#19) |
| **C14** | Profile → SETTINGS section → first row is "Edit Profile". | D (#17) |
| **C15** | Profile → REPORTS section → first row is "Predictions" with preview line + bottom sheet on tap. | D (#18) |
| **C16** | Mission Brief: founder photo loads + locked copy renders. | E (#1, #2) |
| **C17** | Plan screen: phase description reads actual `days_per_week` (no hardcoded "4 days/week"). | F (#4) |
| **C18** | Home weight graph: onboarding weight is the first data point. | F (#5) |
| **C19** | Streak freeze chip rendered ONCE per status strip (not duplicated). | F (#9) |
| **C20** | Onboarding (synthetic): trigger SD1 → SD2 promotion → promotion-day celebration overlay appears with insignia animation + before/after stats + share button. | F (#6) |
| **C21** | Roadmap: rank gate labels read "WEEK 156" or similar — no ambiguous "W156". | G (#8) |
| **C22** | Add Lt rank between SubLt and LtCdr at ordinal 7. Insignia (2 thick stripes) renders correctly. | G |
| **C23** | SD2 → SD1 promotion: requires 7 consecutive completed scheduled workouts AND ≥1 week elapsed. | G (Q26+Q27) |
| **C24** | All dates/times across app derive from IST. Midnight reset for daily counters fires at IST 00:00. | All |

---

## 13. Open questions deferred to Test #7+

- **AI coach `applyTone` / `MotivationTone` restoration** — Captain's Manual personalization that regressed during Test #4 deploy chain. Worth restoring but not in this batch.
- **Nutrition slot aggregation** (one logical entry per slot per day, vs. current "one row per logged event"). Nice-to-have UX simplification.
- **Per-user box namespacing extension** — Plan A (Test #5) namespaced 7 user-scoped boxes. Other shared boxes (configBox, syncBox) remain global. Audit if anything stored in those should also be per-user.
- **iOS Auto Backup parity** — Android-first; iOS comes later.
- **Hive box encryption-at-rest** — separate brainstorm.
- **WorkoutWriteService delete-with-cascade-undo** — currently only soft-delete. Cascade undo for full workout sessions is more complex.
- **Promotion celebration sound/animation upgrade to "full ceremony" (option c from Q22)** — boatswain's call audio + ribbon hoisting animation.
- **AiCoachRepository._getCurrentRankFromLadder vs RankService.getCurrentRank** — two client read paths exist; consolidate to one in Test #7.
