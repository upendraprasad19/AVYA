# Audit 3: code quality + SoT findings

Audit performed 2026-05-04 against `main` head (post APK Test #10 merge `31b966e`+`f9acbce`). Scope per audit prompt §1–10. No fixes applied — observations only.

## P0 (correctness / silent drift / data corruption risk)

### P0-1 — Plan generator V4 cascade is missing the "0 attempt3/4" target
`test/plan_generator/v4_diagnostic_output.md` (regenerated in current working tree) contains **32 `attempt3DropTypeAndTarget` picks + 6 `attempt4DropEquipment` picks = 38 deep-fallback selections** across the 12 sample plans. CLAUDE.md §12 explicitly states the verification target: "0 attempt3/universalPool/none". Examples:
- `Pike Push Up (attempt3DropTypeAndTarget)` at v4_diagnostic_output.md:1117 / 1176 — same canonical bug class flagged in CLAUDE.md §19 ("Pike Push Up assigned to rear delt slot").
- `Lat Pulldown (attempt4DropEquipment)` at v4_diagnostic_output.md:1237 / 1296 — equipment-tier downgrade still firing for full_gym users.
- Library shallowness confirmed at v4_diagnostic_output.md:39 — `vertical_push × bodyweight × advanced × foundational=true` count = **0** (and false=0). Any 5-day or 6-day advanced bodyweight split that allocates a vertical push P1 slot has no exercise to pick.

Universal pool tables at `lib/shared/repositories/plan_engine/exercise_selector.dart:27-32` and `:494-496` still embed `['Pike Push Up', 'Handstand Hold', 'Dand (Hindu Pushup)']` for `vertical_push`. Either the library needs `vertical_push × bodyweight × advanced` exercises, or `split_resolver.dart` should not allocate that triple as P1 for those users.

Working-tree diff on `test/plan_generator/v4_diagnostic_output.md` is unreviewed — last `flutter analyze`-style run is reflected in modified file. Investigate whether prior commits regressed the cascade depth or whether the report has always been at 38.

### P0-2 — `test/sync/sync_gap_test.dart` line 73-87 still searches for inline sync calls that moved into `NutritionWriteService`
`DeleteNutritionLogNotifier.delete` (`lib/features/nutrition/providers/nutrition_provider.dart:1416-1431`) now delegates to `NutritionWriteService.instance.deleteLog`, which fires `unawaited(SyncService.instance.syncNutritionData()) + pushSnapshot()` internally (`lib/core/services/nutrition_write_service.dart:236-237`). The contract test still greps for `unawaited(SyncService.instance.syncNutritionData())` in the notifier source and fails. Failing test is one of the four "pre-existing fails" carried since Test #6. The architectural intent is correct (sync is fired); the test is stale.

### P0-3 — `test/services/rank_service_test.dart` static gate mirrors are stale
Tests `LS needs streak 16 + 4 weeks`, `PO needs streak 60 + 12 weeks + deployment 1`, `SubLt needs 100 total workouts AND 104 weeks` (lines 24–45) are pure static-mirror assertions of constants. Test #6 added Lt at ordinal 7 + Test #6 hybrid sailor/officer gate model — these mirrors were never updated. Three of the four "pre-existing fails" sit here. CLAUDE.md says "deferred to Test #7"; #7, #8, #10 all shipped without fixing. Keeping a known-failing test green-listed in CI is a "boy who cried wolf" risk — real regressions get ignored.

### P0-4 — Three Profile screens query Supabase tables directly (rule #4 violation)
CLAUDE.md §6 rule 4: "Repository pattern for all data access. Never call Supabase or Hive directly from widgets."
- `lib/features/profile/screens/submissions_screen.dart:157,163,338,347,356` queries `user_custom_foods`, `user_custom_exercises`, `community_reviews` directly.
- `lib/features/profile/screens/my_submissions_screen.dart:46,52` queries `user_custom_foods`, `user_custom_exercises`.
- `lib/features/profile/screens/profile_screen.dart:2242` performs `supabase.from('users').update(...)` from a widget context.

These should route through repositories (e.g., a new `SubmissionsRepository`, or extend `UserRepository`). Drift risk: cloud schema changes in any of these tables now require touching three screens.

## P1 (consistency / maintainability)

### P1-1 — User identifier name drift across the codebase
Same concept (`auth.users.id` UUID) shows up under at least 4 names: `userId` (most common, 70+ sites), `supaUserId` (`edit_profile_screen.dart:1552-1554`), `uid` (15 occurrences in `sync_service.dart`), inline `currentUser?.id`. Particularly painful in `sync_service.dart` where `userId` is the public method param convention but local helpers shorten it to `uid`. Recommend choosing **`userId`** (matches DB column `user_id` snake_case → camelCase conversion) and renaming the rest in a one-shot sweep.

### P1-2 — `WorkoutReceiptData.fromExerciseLogs` re-implements index lookup
`lib/features/train/widgets/workout_receipt_card.dart:253-259` opens `HiveService.instance.workoutBox`, builds `'exercise_log_index_$dateKey'`, and reads the index list itself. CLAUDE.md §15 designates `WorkoutRepository.getExerciseLogsForDate` as the ONE read path. The receipt currently implements a parallel reader that bypasses the repository — works today because the field-name contract is identical, but every key-name change has to be applied in two places. Same bug class as the Test #8 receipt-rendering regression.

### P1-3 — `nlog_*` empty `items[]` array bug deferred from Test #10
MEMORY.md `project_apk_test_10_batch.md` records: "legacy `nlog_*` saves don't write `items[]` array → cloud `nutrition_log_items` empty for those rows; `AiBreakdownNotifier.saveMeal` early-returns silently on empty state." Bug deferred to Test #11; not yet ticketed in code. AI coach `_getMealsToday` reads per-item data via `items[]` → silent loss of meal context for any user who logs via the legacy path.

### P1-4 — Direct Supabase auth calls scattered across non-auth features
`SupabaseService.instance.client.auth` is called from `nutrition_provider.dart:673` (`refreshSession()`), `edit_profile_screen.dart:1552`, `profile_screen.dart:2176/2181/2254`. Auth is a cross-cutting concern; centralising token-refresh in one place (`AuthProvider` or `SupabaseService`) would prevent token-expiry race conditions specific to one feature.

### P1-5 — Edit profile invokes Edge Function directly from screen
`lib/features/profile/screens/edit_profile_screen.dart:1368` calls `client.functions.invoke(...)` from inside the widget. Belongs in a repository or service class.

## P2 (cleanup)

### P2-1 — `featureActiveWorkoutMode` deprecation is clean
`@Deprecated` annotation present at `lib/core/constants/app_constants.dart:38-42`, no live `gate(featureActiveWorkoutMode, ...)` callsites remain in `lib/`. Lock-down test `test/subscription/high_value_features_test.dart:31-48` confirms. Constant could ultimately be deleted after one more APK cycle, but keeping it deprecated-not-removed is fine.

### P2-2 — Ad-hoc `kcal` vs `calories` field naming in UI tile components
UI labels use `'kcal'` literal (`barcode_scan_sheet.dart:459`, `diet_plan_screen.dart:508/510/513`, `custom_food_sheet.dart:123`, `scan_meal_section.dart:649`); data field on map is `total_calories` (logs) or `calories` (per-item). Acceptable but worth documenting in CLAUDE.md §15: "kcal = display unit; calories/total_calories = data field; never mix in JSON keys."

### P2-3 — `lib/features/profile/screens/my_submissions_screen.dart` is documented legacy
CLAUDE.md §5 marks this as legacy; "do not add new entry points; route new callers at `/profile/submissions`". Also has direct Supabase queries (P0-4). Slated for removal "after one release cycle" per `project_apk_test_1_batch.md` — that cycle has now elapsed (Tests #2–#10 shipped). Safe to delete.

## Test coverage gaps

Cross-checking `test/contracts/` against `lib/core/services/`:

| WriteService field | Consumer covered? | Notes |
|---|---|---|
| `WorkoutWriteService` `set_number`/`sets`/`reps_completed`/`weight_kg`/`volume_kg`/`is_pr` | `workout_write_to_read_contract_test.dart` exists | ✅ Test #8 |
| `NutritionWriteService` per-item `name`/`quantity_g`/`calories`/`protein`/`carbs`/`fat`/`fiber` | `nutrition_write_to_read_contract_test.dart` exists | ✅ Test #8 |
| `SyncService.syncWorkoutData` fanout | `sync_fanout_contract_test.dart` exists | ✅ |
| `NutritionWriteService` `items[]` round-trip to `_getMealsToday` (AI coach) | **MISSING** | P1-3 references this gap; would have caught the Test #10 deferred bug |
| `WorkoutWriteService` round-trip to `AiCoachRepository._getThisWeekWorkouts` / `_getPersonalRecords` | **PARTIAL** | Only Hive contract tested; the AI coach `box.values` filter regression isn't covered |
| `nlog_*` legacy save path → cloud `nutrition_log_items` items projection | **MISSING** | Per Test #10 deferral |
| `_pendingOnboardingSync` queue → cloud `user_profile` upsert | **MISSING** | Restoring screen depends on it |
| Receipt `fromExerciseLogs` parallel index reader (P1-2) | **MISSING** | Won't catch index-key rename in `workout_repository.dart` only |

## Quick wins

1. Fix or delete the four pre-existing failing tests (P0-2, P0-3) — at minimum, mark them `@Skip` with a comment so the suite stays green and the failures don't mask new regressions.
2. Refactor `WorkoutReceiptData.fromExerciseLogs` to call `WorkoutRepository.getExerciseLogsForDate` (P1-2). One-line repository extraction; caller signatures unchanged.
3. Move `submissions_screen` direct Supabase queries into a `SubmissionsRepository` and delete `my_submissions_screen.dart` (P0-4 + P2-3 in one PR).
4. Add an `_getMealsToday` round-trip contract test that writes via `NutritionWriteService.logMeal` and reads via `AiCoachRepository.buildAiContext` — would have caught the Test #10 bug class before deferral.
5. Triage `attempt3/attempt4` cascade picks in `v4_diagnostic_output.md` (P0-1) — at minimum, add the missing `vertical_push × bodyweight × advanced` exercises to `assets/data/exercise_library.json`.
6. Pick a single user-id name (`userId`) and run a sed sweep on `supaUserId` + local `uid` aliases (P1-1).

## Things checked and clean

- **Direct `Hive.box(` access in widgets/screens**: zero hits in `lib/features/**`. All access goes through `HiveService` getters or repositories. (Grep result confirms.)
- **`configBox.get('isPro')` outside `SubscriptionService`**: zero hits. Only readers are `subscription_service.dart:86` and `:363` (canonical).
- **`featureActiveWorkoutMode` deprecation**: clean — see P2-1.
- **Diet plan macro band tests**: `test/nutrition/diet_plan_generator_test.dart:153-186` still asserts `[95%, 115%]` band on protein for all 4 archetypes (cut/maintain/build/vegan). Anchor-in-every-meal assertion at line 186. Tests are present and structurally intact; whether they currently pass requires a `flutter test` run (out of scope).
- **`unawaited(...)` discipline in `sync_service.dart`**: every catch block at least `debugPrint`s (`sync_service.dart:646/700/812/...`). No swallow-all empty `catch {}` blocks found in the file.
- **Single-source files in CLAUDE.md §15**: `subscription_service.gate()`, `ai_service._compactContext()`, `day_rollover_service.runRolloverNow()`, `weekly_report_data_provider`, `diet_plan_provider` all show single-reader patterns in their respective files. No drift detected.
- **WriteServices are sole writers**: `nutrition_write_service.dart:20` doc comment is enforced — no `nutrition.put('nlog_*', ...)` direct calls outside the service. Same for `workout_write_service.dart`.
