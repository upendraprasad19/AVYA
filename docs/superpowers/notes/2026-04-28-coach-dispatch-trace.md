# Coach Dispatch Trace — APK Test #5 Plan C

**Date:** 2026-04-28  
**Bug:** OBS-4 — "Reshuffle week to 6 days" / "Pause 1 day" review cards in AI coach do nothing on tap; cards pile up in chat thread.

## C-1: Dispatcher path investigation

### File: `lib/features/ai_coach/services/tool_dispatcher.dart`

The dispatcher is **complete and correct**. Both `rescheduleWeek` and `pausePlan` have full implementations:

- `case 'reschedule_week'` → `_executeRescheduleWeek` (lines 448–547):
  - Reads cached `RescheduleWeekPlanner.instance.getCached(intent.id)` moves.
  - Two-phase apply (snapshot sources, then write destinations + delete sources).
  - Defensive completed/paused destination guard.
  - Re-stamps date + day_of_week + audit fields (`rescheduled_via`, `rescheduled_at`).
  - Clears planner cache after.

- `case 'pause_plan'` → `_executePausePlan` (lines 668–700):
  - Reads `start_date` + `days` + `reason` from payload.
  - Delegates to `WorkoutScheduleService.instance.pauseRange(...)`.
  - Clears `PausePlanPlanner.instance.cache`.

### Post-dispatch invalidation + sync (already working)

After every successful execute, `ToolDispatcher.execute` (lines 150–175):
1. Fires `_invalidateWorkoutProviders(ref)` — the §15 6-provider batch.
2. Fires `unawaited(SyncService.instance.syncWorkoutData())`.
3. Fires `unawaited(SyncService.instance.pushSnapshot())`.

So when the dispatcher *does* run successfully, schedules update, providers refresh, and the AI sees the change. **The dispatcher is NOT the problem.**

### `WorkoutScheduleService` API verification

- `regenerateForDays(days)` — **DOES NOT EXIST.** The dispatcher does not need it; `_executeRescheduleWeek` writes Hive directly via `box.put('schedule_<date>', updated)` after reading cached `RescheduleMove[]` from `RescheduleWeekPlanner`.
- `markRestDay(date)` — **DOES NOT EXIST.** Pause uses `WorkoutScheduleService.instance.pauseRange(startDate:, days:, reason:)` (verified at line 739 of `workout_schedule_service.dart`).

The plan's mention of these names was misleading — both flows are fully implemented via existing methods. **No new service methods required.**

## C-2: Review card render path

### File: `lib/features/ai_coach/screens/ai_coach_screen.dart`

- Line 669: `final visibleIntents = ref.watch(pendingToolIntentsProvider).where((i) {...}).toList();` — includes pending/executing/failed/executed/rejected/expired statuses.
- Line 739–745: For each intent in the chat list:
  - If `intent.confirmationClass == ConfirmationClass.destructive` → `_buildDestructiveIntentTile(context, intent)` (line 742).
  - Else → `ToolConfirmCard(intent: intent)` (line 744).
- Line 757–806: `_buildDestructiveIntentTile` renders a `Container` wrapping an `InkWell` whose `onTap: () => _openIntentSheet(context, intent)`. The trailing widget is a `chevron_right` icon — **NO explicit Apply/Dismiss buttons**, just an entire-card tap target with chevron affordance.
- Line 808–849: `_openIntentSheet` switches on `intent.type` to build the right `*Diff` widget, then calls `ToolConfirmSheet.show(context, intent: intent, diffPreview: diffPreview)`.

### `ToolConfirmSheet` (the destination)

`lib/features/ai_coach/widgets/tool_confirm_sheet.dart` already has explicit Cancel + Confirm buttons (lines 110–158). Confirm calls `ref.read(pendingToolIntentsProvider.notifier).confirm(intent.id)` which routes to `ToolDispatcher.execute`. Cancel calls `.reject(intent.id)`.

### Why cards "pile up" (the actual bug)

Two distinct root causes:

1. **`_buildDestructiveIntentTile` does not render terminal states.** When `intent.status == executed` or `rejected`, the tile still renders the same "Review: ..." card with chevron — there's no executed/rejected branch like `ToolConfirmCard._buildExecutedState`. So the card stays in the chat thread forever, looking unchanged. The user thinks nothing happened.

2. **Chevron-only tap target is non-discoverable.** Users do not realise the entire row is tappable, especially because the visible affordance is a small chevron icon at the right edge. They expect explicit buttons (matching the trivial/reviewable inline cards which DO show Confirm/Skip buttons).

### Fix scope (matching plan tasks)

- **C-3**: Add explicit `WardButton(label: 'APPLY', primary)` + `WardButton(label: 'DISMISS', ghost)` row to `_buildDestructiveIntentTile`. APPLY opens the sheet (same as the InkWell did); DISMISS calls `pendingToolIntentsProvider.notifier.reject(intent.id)`.
- **C-4**: No code change — dispatcher's `_executeRescheduleWeek` already wires the writes + sync. The "wiring" the plan asks for is already present. Will document in commit message.
- **C-5**: Same — `_executePausePlan` already wires the writes + sync via `pauseRange`.
- **C-6**: Add executed / rejected / expired terminal-state rendering to `_buildDestructiveIntentTile` so cards collapse to a small "Applied" / "Dismissed" pill after action — mirrors `ToolConfirmCard._buildExecutedState` / `_buildRejectedState`.

### Hive marker per plan C-4/C-6

The plan asks for `coachBox['intent_<id>_dispatched_at'] = DateTime.now()` to filter cards. **This is redundant** — `pendingToolIntentsProvider` already tracks status via `ToolIntent.status` and `_updateStatus` after execute. Filtering by `intent.status != executed && != rejected` in the screen's `where` clause is the cleaner equivalent. Will use status field, not new Hive key, to avoid duplicate-state-of-truth bugs.
