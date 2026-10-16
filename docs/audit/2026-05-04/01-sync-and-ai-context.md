# Audit 1: sync + AI context findings

Audit date: 2026-05-04. Scope: `lib/core/services/sync_service.dart`, `lib/features/ai_coach/repositories/ai_coach_repository.dart`, write services, all proactive Edge Functions, `supabase/migrations/`, `test/contracts/`.

CLAUDE.md and Test #8 retro claim several things "fixed" — I verified each by reading the file. Specific drifts confirmed below.

---

## P0 (data loss / silent broken)

- **[lib/features/nutrition/providers/nutrition_provider.dart:810-826]** — `logFood()` still writes nutritionBox WITHOUT an `items[]` array (single food → top-level `food_id`/`food_name`/`quantity_g`/totals). `_syncNutritionLogs` (sync_service.dart:1257) only emits `nutrition_log_items` rows when `log['items'] is List`. Result: every food logged via the search-mode path writes `nutrition_logs` parent only — `nutrition_log_items` cloud row never created. AI coach `_getMealsToday` reads from local Hive and works, but cloud-side `weekly-report`, `protein-gap-alert`, `rolling-context` etc. that join `nutrition_log_items` see zero items for these rows. Test #10 retro flagged this as deferred — still present. Same path used by `lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart:304`.

- **[lib/core/services/sync_service.dart:2266]** — Restore path writes Hive exlog entry with `'sets_completed': map['set_number']` (note key name). Per Test #8 contract test (`test/contracts/workout_write_to_read_contract_test.dart:90,201`), the writer-canonical key is `set_number`. Receipt has dual-read fallback (`workout_receipt_card.dart:276-277`), but `WorkoutWriteService._rescanPrFor`, `getExerciseLogsForDate` consumers, and `AiCoachRepository._getThisWeekWorkouts` (today_exercises feed) read `set_number` first/only. After cross-device restore, exlog rows look "0 sets" to the writer's PR rescan and to any consumer that hasn't been retrofitted with the legacy fallback. Same drift at sync_service.dart:2275 reconstructing `sets_detail` (writer uses `sets`).

- **[lib/features/train/repositories/workout_repository.dart:358-364, 1079-1093]** — `WorkoutRepository.logExercise` and `updateExerciseLog` still write `sets_completed` + `reps_completed` (legacy schema) directly to `workoutBox` while `WorkoutWriteService` writes `set_number` + `sets[]`. Two writers, two schemas — one without contract test coverage. CLAUDE.md §15 says all workout writes should funnel through `WorkoutWriteService`, but `WorkoutRepository` is still called from edit-log paths and AI coach `conversational_log_handler.dart:204,247,259`. New mutations land with the wrong field shape.

- **[lib/core/services/sync_service.dart:377]** — `compileDailySnapshot` builds the cloud snapshot date with `DateTime.now().toIso8601String().substring(0,10)` (UTC, NOT IST). For a user in IST 00:00–05:30, `snapshot_date` is the previous day. `morning-alert/index.ts:469`'s wake-time RPC joins on `snapshot_date = todayIST` — the snapshot is filed under the wrong day, the RPC misses it, and the user gets the generic fallback ("Good morning {firstName}!"). CLAUDE.md feedback memory `feedback_use_ist_throughout.md` exists for exactly this; rule never propagated to the snapshot writer.

- **[lib/features/ai_coach/repositories/ai_coach_repository.dart:791-800, 850-858, 874-878]** — `_getThisWeekWorkouts`, `_getStepHistory`, `_getTodaySteps`, `_getMealsToday`, `_getCurrentPlanSummary` all build "today" / "weekStart" via `DateTime.now()` device-local, NOT IST. After 18:30 UTC (00:00 IST) device-local diverges from IST and the AI snapshot's "today" ≠ Hive key date prefix `istDateStr(...)` written by `WorkoutWriteService`. The AI sees today's set as "yesterday" or vice-versa for the 5h30 window, which is exactly when a user in IST is asking the coach about their morning workout.

- **[lib/features/ai_coach/repositories/ai_coach_repository.dart:1683-1716]** — `_getPRTimelineSummary` reads `reps_completed` only — works for legacy `WorkoutRepository`-written rows but NOT for `WorkoutWriteService`-written exlog entries (writer canonical names verified: writer uses `reps_completed` too, so safe — but) — verify: at workout_write_service.dart:135 writer writes both `reps_completed` AND `set_number`. So PR timeline is OK on reps. Skip this one.

## P1 (premium-feel breaker / inconsistency)

- **Coach persona inconsistency across proactive triggers.** Only `ai-proxy/index.ts:588` and `weekly-report/index.ts:360` import `_shared/captain_manual.ts`. `morning-alert/index.ts:235` writes its own short prompt ("You are ICANBEFITTER's morning coach"). `streak-guardian/index.ts:138-156`, `re-engagement/index.ts:224`, `workout-window-closing/index.ts:220`, `protein-gap-alert`, `plateau-alert`, `pr-detection` all use **hardcoded English notification copy** — friendly tone like "Don't break your streak!", "Triple digits. You're officially unstoppable.". Captain persona is briefing-style, period-heavy, 24h time, occasional Hinglish ("Shabaash"). Push notifications are off-brand vs in-app chat. User reads "Triple digits. You're officially unstoppable!" then taps in and the Captain says "Affirmative. Sailor — your watch is current." — feels like two different products.

- **[lib/features/ai_coach/repositories/ai_coach_repository.dart:851-872]** — `_getStepHistory` filters by `log['type'] == 'step_log'` but iterates `healthBox.get('step_$dateStr')` keys directly. Works because HealthSyncService writes both. However `_getTodaySteps` (line 881) iterates `healthBox.values` and re-filters by type — drift risk same class as Test #8 silent regressions. Should use key-prefix scan for symmetry.

- **[supabase/migrations/041_chunks/]** — orphan directory present alongside `041_food_database_seed_v2.sql`. CLAUDE.md says chunks were applied separately. `list_migrations` (server) likely shows the parent .sql but the chunks directory is checked into git as plain files — risk of `supabase db push` re-applying or new dev confusion. No README inside.

- **AI snapshot omits "today_workout exercises with completed reps".** `_getTodayWorkout` returns the schedule entry; `_getThisWeekWorkouts.today_exercises` returns names of completed exlog_*. There's no "exercises_planned_today_with_completion" stitched view, so the coach asking "How did your bench go today?" must cross-reference 2 fields and the model often gets the join wrong (hallucinates either schedule list or empty completion).

- **[lib/features/ai_coach/repositories/ai_coach_repository.dart:32]** — `buildAiContext` does NOT include: water_today (only `water_7d` aggregate), mood notes, custom foods (only custom exercises), notification preferences, last 5 AI tool invocations (telemetry exists in DB but not surfaced to model). Custom foods are particularly load-bearing — user adds "Mom's dal recipe" via Add Custom Food, asks coach about protein, coach can't see it.

- **[supabase/functions/morning-alert/index.ts:178]** — `dayOfWeek = new Date().getDay()` is server-local (UTC). For a 02:00 IST cron tick (still Monday IST), `getDay()` returns 0 (Sunday UTC) — wrong day inference for any logic gated on day of week.

- **[lib/core/services/sync_service.dart:586,625,627,1352,1402,1431,1460,1491,1519,1544,1653]** — 11 separate `DateTime.now().toIso8601String()` writes for `last_active_at`, `phase_started_at`, `created_at`, `synced_at`, `updated_at`. These are TIMESTAMPTZ columns so absolute instant is fine, BUT `'last_active_at'` is read by `re-engagement` via `lastActiveMs = new Date(lastActiveRaw).getTime()` — UTC vs device-local mismatch when the device clock is off (common on rooted devices).

- **[lib/features/train/providers/train_provider.dart:1571,1588]** — Template `created_at` / `updated_at` in device-local time. Same class as above — read by cloud cron jobs that filter by date.

## P2 (nice-to-have)

- **`ai-proxy/index.ts:602-607`** — day-of-week injection IS present (CLAUDE.md claim verified). Uses IST. Good.

- **`_sanitisePredictionText`** at `ai_coach_provider.dart:697` — JSON + YAML key:value guards present per Test #2 / F4. Good.

- **76 `box.put` callsites outside of WriteServices** — many are config / preferences / health (not workout/nutrition domain) so technically fine, but it's a maintenance smell. Adding one more direct `workoutBox.put` to a feature widget is one PR away from a sync gap. Lint rule banning direct user-scoped puts in `lib/features/` would close the door.

- **`_getInductionAndMusterKeys` (line 190)** — uses `DateTime.now()` for `daysSinceCommitment`. Device-local; same IST drift.

- **Migration 041 `_chunks/` directory** — should be deleted post-apply or moved to `archive/` to prevent reuse confusion.

- **[supabase/functions/_shared/send_notification.ts]** — assumed standard wrapper; not verified persona-aware. Could become injection point for unified Captain voice.

## Quick wins (low effort, high value)

1. **Replace `DateTime.now().toIso8601String().substring(0,10)` with `istDateStr(DateTime.now())`** at sync_service.dart:377, ai_coach_repository.dart `_getThisWeekWorkouts/_getStepHistory/_getTodaySteps/_getCurrentPlanSummary/_getMealsToday/_getYesterdayWorkout`. ~10 grep-replace edits, blocks Bug #6 + retest #4 audit A4.

2. **Fix sync_service.dart:2266 restore path** to write `set_number` + `sets` (writer-canonical) instead of `sets_completed` + `sets_detail`. 4-line change.

3. **Backfill `items[]` on nutrition_provider.dart:810 single-food log**: wrap the food into a 1-element list, write `items: [{ name, quantity_g, calories, protein, carbs, fat, fiber }]` alongside the totals. Closes Test #10 deferral + restores cloud reports for the most common log path.

4. **Wrap proactive notification copy in a shared `composePersonaPush(title, body, rank)` helper** that prepends a 1-token Captain-voice signature. Even if the body stays English, having the title rotate through ("Watch update.", "Status, sailor.", "Brief.") would re-anchor the persona.

5. **Lint or test: ban direct `workoutBox.put` / `nutritionBox.put` outside `lib/core/services/{workout,nutrition}_write_service.dart`.** Source-grep test similar to `sync_fanout_contract_test.dart`. ~20 lines.

6. **Delete or move `supabase/migrations/041_chunks/` after confirming applied.** Reduces apply-by-mistake risk.

## Things checked and clean

- ai-proxy v48+ day-of-week injection: present at index.ts:602-607, uses IST. ✅
- Anti-fabrication rules in CAPTAIN_MANUAL: present, persona is sourced from one shared module for in-app chat + weekly report.
- Prediction parse guards (`_sanitisePredictionText`): JSON + YAML branches both present.
- `syncWorkoutData` fans out to all 6 workout-domain helpers + `syncNutritionData` to all 3 — sync_fanout_contract_test.dart locks this.
- `WorkoutWriteService` callsites all fire `unawaited(SyncService.instance.syncWorkoutData()) + pushSnapshot()` after writes (verified 7/7).
- `NutritionWriteService` same pattern verified 7/7.
- Test #4 audit "yesterday's workout / sleep / streak freezes / active workout" snapshot keys all present in `buildAiContext` (lines 115-152). ✅
- Migration 042 (induction muster), 044 (stat snapshots), 045 (Lt rank), 046 (morning-alert split) all applied per index — schema and client read paths line up.
- Hive IST helpers (`ist_date.dart`) exist and are used in 27 places. Adoption is partial (gap with §P0 #4-5), not absent.
- `ai_coach_repository._readCustomExercises` (line 226) handles both per-key + legacy list-key formats. ✅
- `_replayPendingOnboardingSync` (sync_service.dart:561) is the documented safety net for onboarding profile sync. ✅
- Captain Manual is the single shared persona module — `ai-proxy` and `weekly-report` import it. Drift risk is the proactive triggers (P1), not the in-app chat.

---

## Recommended ordering for Test #11 batch

P0 #1 (items[] backfill) + P0 #2 (restore field rename) + P0 #4-5 (IST in sync + AI repo) are the cluster: ~4h, closes 4 silent-data-loss class bugs.

P1 coach-persona unification is a 1-day effort but biggest premium-feel lift — every proactive push currently breaks the "naval briefing" voice.

P0 #3 (WorkoutRepository legacy schema) is the architectural debt — 6h+ to retire `WorkoutRepository.logExercise` in favor of `WorkoutWriteService` everywhere, but every day it stays open we accumulate field-shape drift.
