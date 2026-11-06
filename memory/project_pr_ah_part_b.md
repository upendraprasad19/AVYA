# PR AH — Part B (Wardroom Handoff Gap Closure, Round 2)

**Date:** 2026-04-20
**Branch:** feat/pr-ah-part-b
**Commits:** 6 sub-PRs
**Merge commit:** 895b2e2 (merged into main)

## Scope

Six sub-PRs closing the Part B gaps carried over from PR AG (see `project_pr_ag_handoff_gaps.md`). Plus a token-hygiene audit of the 8 non-handoff (Part C) screens.

## What Shipped

| Sub-PR | Commit | Area | Summary |
|---|---|---|---|
| AH.1 | 473158c | Home | `StreakWarningBanner.shouldShow` floor bumped 15h → **18h** (evening-only nudge per `daily.jsx`). `WeightSparkline` chips simplified from `7d/30d/3m/1y/All` → **`7D/30D/90D`** per spec. |
| AH.5 | 337f271 | Nutrition | New `dietPlanProvider` reads `configBox['saved_diet_plan']` and exposes per-slot `PlannedSlot` (summary, kcal, protein, firstFoodName). `TodaysMealsCard` renders **"FROM YOUR DIET PLAN"** hint on empty slots. `showFoodSearchSheet(initialQuery:)` plumbed through — tap `+ LOG` with a planned meal → food search **pre-filled**. `diet_plan_screen._savePlan` invalidates the provider on save. |
| AH.7 | 436bdf0 | Profile | New **"Rate App"** tile in SHARE & GROW. Opens Play Store listing (`com.icanbefitter.icanbefitter`) via `url_launcher` with `LaunchMode.externalApplication`. |
| AH.8 | 3681f2f | Weekly Report | `WeeklyReportCard` converted StatelessWidget → ConsumerWidget. KV rows replaced with **2×2 sparkline grid** (WEIGHT / CALORIES / PROTEIN / WORKOUTS). New `weeklyReportDataProvider` aggregates last-7-days from `healthBox` / `nutritionBox` / `workoutBox`. Weight series forward-filled across gaps; others default to 0. Empty-state copy when all series are zero. |
| AH.9 | e7bc656 | AI Coach | Greeting now reads **"Good morning, {firstName}."** Pulls `full_name` from `userProfileProvider`, splits on whitespace, takes first token. Falls back to generic form when name is missing or still the 'User' placeholder. |
| AH.C1 | ed737f2 | Token hygiene | 4 legacy `0xFF00D4FF` cyan literals swapped to `AppColors.accent`: `train_provider.supersetColor()` (superset A), `train_provider.RestTimerData.timerColor` (plus warn/bad swaps), `profile_provider` image_cropper AndroidUiSettings ×2. |

## Verify-Only (No Code Changes)

| Task | Finding |
|---|---|
| B.3 Train templates list | Already wired — `templatesProvider` scans `workoutBox` for `template_*` keys. |
| B.4 Create Custom Exercise CTA | Already wired — `_buildCreateCustomExerciseSection` + `WardDashedBorder`. |
| B.10 tabular-figures audit | Already applied globally via `_fraunces()` builder in `typography.dart`. |

## Part C Decision (AH.C1 context)

All 8 non-handoff screens audited — **zero `Color(0x...)` literals in any of them**:
- splash, sign-in, diet plan, template builder, graduation, progress photos, my submissions, onboarding chat.

No Tier-1 fixes needed on Part C screens themselves. The 4 legacy cyan refs caught were all in shared providers (train, profile), not in Part C screens.

**Deferred:**
- Tier 2 — `onboarding_chat` retirement pending PR AI.
- Tier 3 — no redesign work until JSX specs exist.

## What's Deferred (beyond PR AH)

- **PR AI** — stepped onboarding collection of 8 missing fields (`fitness_experience`, `days_per_week`, `equipment_access`, `lifestyle_activity`, `pace_preference`, `diet_preference`, `injuries`, target weight).
- AI Coach Suggested Actions / Patterns / Today's Insight CTAs — still static, waiting on structured Edge Function output.
- Video-share feature — post-launch.
- Push to origin — held until user asks.

## Business Logic Preserved

Subscription gate, `pushSnapshot` / `syncWorkoutData` / `syncNutritionData` fire-and-forget, completion pipeline, `WorkoutScheduleService`, plan generator, payment flow, Edge Function contracts — all untouched.

## Verification

`flutter analyze` on merged main: 4 issues — all pre-existing baseline warnings in `test/`. Zero new issues from PR AH.

## APK

Not yet built from the PR AH branch — user deferred testing. Can be rebuilt from the main worktree when needed:
```
flutter build apk --dart-define-from-file=.env --flavor prod --release -t lib/main.dart
```
