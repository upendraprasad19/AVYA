# Coach WRITE Tool Audit — 2026-04-28

Source of truth for the 16 WRITE tools per CLAUDE.md §11 + Plan C spec §5.3.

This audit was conducted as part of Task C-8 of `2026-04-28-apk-test-5-plan-C-coach-dispatch.md`. It builds on the C-1/C-2 trace doc (`2026-04-28-coach-dispatch-trace.md`) and the C-3 → C-6 fixes that landed in commits `db093c8` (explicit APPLY/DISMISS), `eee8feb` (Hive `intent_<id>_dispatched_at` marker), `056125e` (pausePlan wiring confirmation), `372a52f` (filter dispatched intents from chat thread).

## Scope

Audit each of the 16 WRITE tools across four columns:

| # | Column | What is being verified |
|---|---|---|
| (i) | Handler exists | A `case '<tool_type>':` branch in `tool_dispatcher.dart` calls a handler that performs the mutation. |
| (ii) | Apply/Dismiss buttons | The render path (`ToolConfirmCard` for trivial/reviewable, `ToolConfirmSheet` for destructive) presents an explicit Confirm + Cancel button pair (no chevron-only / tap-anywhere pattern). |
| (iii) | Sync fires | After a successful execute, the dispatcher fires `unawaited(SyncService.instance.syncWorkoutData())` OR `syncNutritionData()` (family-aware) AND `unawaited(SyncService.instance.pushSnapshot())` per CLAUDE.md §15. |
| (iv) | Auto-dismiss flag | The dispatcher writes `coachBox['intent_<id>_dispatched_at'] = ISO8601` so the chat thread filter (`ai_coach_screen.dart:680`) hides the card on subsequent rebuilds, including hot restart. |

## Verdict matrix

| # | Family | Tool (intent.type) | (i) Handler | (ii) Buttons | (iii) Sync | (iv) Marker |
|---|---|---|---|---|---|---|
| 1 | Workout | `swap_exercise` | OK | OK | OK | OK |
| 2 | Workout | `log_set` | OK | OK | OK | OK |
| 3 | Workout | `mark_workout_complete` | OK | OK | OK | OK |
| 4 | Workout | `shorten_workout` | OK | OK | OK | OK |
| 5 | Workout | `create_custom_exercise` | OK | OK | OK | OK |
| 6 | Workout | `modify_workout_for_injury` | OK | OK | OK | OK |
| 7 | Workout | `reschedule_week` | OK | OK | OK | OK |
| 8 | Workout | `generate_hotel_workout` | OK | OK | OK | OK |
| 9 | Nutrition | `log_meal_by_text` | OK | OK | OK | OK |
| 10 | Nutrition | `adjust_caloric_target` | OK | OK | OK | OK |
| 11 | Nutrition | `prelog` | OK | OK | OK | OK |
| 12 | Plan | `regenerate_plan_block` | OK | OK | OK | OK |
| 13 | Plan | `pause_plan` | OK | OK | OK | OK |
| 14 | Plan | `switch_goal` | OK | OK | OK | OK |
| 15 | Plan | `create_custom_template` | OK | OK | OK | OK |
| 16 | Plan | `schedule_template` | OK | OK | OK | OK |

**Summary:** 16/16 WRITE tools verified correctly wired across all 4 columns. **Zero fix-needed.**

## Evidence by column

### (i) Handler exists — `tool_dispatcher.dart` switch in `execute()` lines 91-141

Every tool type maps to a private `_execute<Tool>` handler:

| Tool | Switch line | Handler line |
|---|---|---|
| swap_exercise | 91 | `_executeSwapExercise` (205) |
| log_set | 94 | `_executeLogSet` (250) |
| mark_workout_complete | 97 | `_executeMarkWorkoutComplete` (319) |
| shorten_workout | 100 | `_executeShortenWorkout` (384) |
| create_custom_exercise | 103 | `_executeCreateCustomExercise` (345) |
| modify_workout_for_injury | 106 | `_executeModifyWorkoutForInjury` (404) |
| reschedule_week | 109 | `_executeRescheduleWeek` (461) |
| generate_hotel_workout | 112 | `_executeGenerateHotelWorkout` (562) |
| regenerate_plan_block | 115 | `_executeRegeneratePlanBlock` (621) |
| pause_plan | 118 | `_executePausePlan` (681) |
| switch_goal | 121 | `_executeSwitchGoal` (724) |
| create_custom_template | 124 | `_executeCreateCustomTemplate` (830) |
| schedule_template | 127 | `_executeScheduleTemplate` (892) |
| log_meal_by_text | 130 | `_executeLogMealByText` (954) |
| adjust_caloric_target | 133 | `_executeAdjustCaloricTarget` (1076) |
| prelog | 136 | `_executePrelog` (1012) |

Note: `log_pr` (line 139) is also wired but per CLAUDE.md §11 it lives in the Progress family (3 tools, including 2 read tools), not in the 16 WRITE tools we audit here. Logging it for completeness.

### (ii) Apply/Dismiss buttons — render dispatch by `ConfirmationClass`

The render path is selected by `intent.confirmationClass`:

- `trivial` → `ToolConfirmCard` with countdown auto-confirm + visible Confirm + Skip controls (`tool_confirm_card.dart:188` "Confirm" button; auto-cancel on timer expiry).
- `reviewable` → `ToolConfirmCard` without countdown — explicit Confirm + Skip.
- `destructive` → `ToolConfirmSheet` bottom sheet with Cancel + Confirm (`tool_confirm_sheet.dart:149`).

All three classes present a paired button surface — there is no chevron-only / tap-anywhere case left in the codebase post-C-3.

### (iii) Sync fires — dispatcher outer flow lines 154-175

```dart
if (_isNutritionIntent(intent.type)) {
  _invalidateNutritionProviders(ref);
  unawaited(SyncService.instance.syncNutritionData());
} else {
  _invalidateWorkoutProviders(ref);
  unawaited(SyncService.instance.syncWorkoutData());
}
// ...
unawaited(SyncService.instance.pushSnapshot());
```

`_isNutritionIntent` (line 1183) returns true for `log_meal_by_text`, `adjust_caloric_target`, and `prelog` — the 3 nutrition-family tools — and false for everything else (workout + plan tools both write schedule rows so they share `syncWorkoutData`). `pushSnapshot` fires unconditionally.

### (iv) Auto-dismiss marker — dispatcher outer flow lines 183-188

```dart
try {
  await HiveService.instance.coachBox.put(
    'intent_${intent.id}_dispatched_at',
    DateTime.now().toIso8601String(),
  );
} catch (_) {/* never block on telemetry */}
```

Read by `ai_coach_screen.dart:680`:

```dart
if (coachBox.get('intent_${i.id}_dispatched_at') != null) return false;
```

The marker survives hot restart and low-memory background kill — the in-memory `PendingToolIntentsNotifier` state is wiped on process death, but the Hive marker isn't, so a re-rendered chat thread post-restart still hides previously-dispatched cards.

## Pre-existing analyzer noise (NOT fixed in this batch)

None observed in `lib/features/ai_coach/`. Future agents: if `flutter analyze lib/features/ai_coach/` surfaces issues, they were introduced after this audit.

## Audit conclusion

The "tap does nothing" symptom that motivated Plan C was a UI perception bug:
the chevron-only pattern made testers think they had tapped APPLY when in
fact they had only opened the diff sheet, then hit Confirm with an
unpopulated planner cache. C-3 (explicit APPLY/DISMISS buttons), C-4/C-5
(verified handler wiring), C-6 (filter dispatched intents from chat
thread) collectively closed the perception gap by making the user-visible
flow deterministic.

**No additional WRITE tool dispatches need fixing.** C-9 is empty —
all 16 tools verified ✅ across all 4 columns. The plan's "one commit
per fix" instruction is moot since there are zero fixes to apply.

## Manual smoke results (C-11)

(filled during C-11 — pending on-device APK install)
