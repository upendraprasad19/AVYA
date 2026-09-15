# PR AG — Wardroom Handoff Gap Closure

**Date:** 2026-04-20
**Branch:** feat/pr-ag-handoff-gaps
**Commits:** 5 sub-PRs
**Merge commit:** 386f42e (merged into main)

## Scope

Five sub-PRs closing the Wardroom sweep's deferred list (see `project_wardroom_handoff_enforcement.md`).

## What Shipped

| Sub-PR | Area | Summary |
|---|---|---|
| AG.1 | Nutrition | `TodaysMealsCard` + `WardDashedBorder` primitive + 4 fixed BREAKFAST/LUNCH/DINNER/SNACK slots. Empty slots render a dashed `+ LOG` CTA that opens `showFoodSearchSheet(mealType: slot)`. |
| AG.2 | AI Coach | Insight stack: `CoachInsightSection` (TODAY'S INSIGHT), `CoachSuggestedActions` (3 static cards — TRAINING/SLEEP/MEAL), `CoachPatternsCard` (3 static patterns with confidence %), `CoachDeepAnalysisCard` (routes to `/profile/reports`, "READY · SUNDAY DD MMM"). Welcome-view rewrite. |
| AG.3 | Profile | Subscription Seal card — corner gold Seal + "Everything unlocked". |
| AG.4 | Onboarding | Stepped-flow `plan_screen.dart` smarter defaults inference instead of hardcoding. |
| AG.5 | Notifications | Inbox wired to real OneSignal + Hive `notificationsBox`. New model `AppNotification`, service `NotificationInboxService`, provider `notifications_inbox_provider.dart`. |

## New Primitives / Boxes

- `WardDashedBorder` — CustomPainter for rounded dashed borders. Shared across AG.1 and AH.C1 token hygiene.
- `notificationsBox` — new Hive box opened in `HiveService.init()`.

## What's Deferred (PR AH — done next)

- Home streak-warning evening floor bump
- Weight sparkline chip simplification
- Nutrition "From Your Diet Plan" wiring
- Profile Share & Grow section (Rate App tile)
- Weekly Report 4-up sparklines
- Coach dynamic first-name greeting

## What's Deferred (post-AH)

- AI Coach Suggested Actions / Patterns / Today's Insight CTAs → static placeholders until `ai-proxy` and `rolling-context` emit structured action/pattern objects.
- Onboarding chat retirement — blocked on PR AI collecting the 8 missing fields in the stepped flow.

## Business Logic Preserved

Subscription gate, `pushSnapshot` / `syncWorkoutData` / `syncNutritionData` fire-and-forget, completion pipeline, `WorkoutScheduleService`, plan generator, payment flow, Edge Function contracts — all untouched.

## APK

Built from worktree before merge:
`.claude/worktrees/pr-ag-handoff-gaps/build/app/outputs/flutter-apk/app-prod-release.apk` (129 MB).
