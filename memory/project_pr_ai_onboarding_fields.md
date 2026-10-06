# PR AI — Stepped Onboarding Field Coverage

**Date:** 2026-04-20
**Branch:** feat/pr-ai-onboarding-fields
**Commits:** 3 sub-PRs
**Merge commit:** bdbd2f2 (merged into main)

## Scope

Closed the field-coverage gap in the Wardroom stepped onboarding flow. Previously the 4-screen Welcome → Goal → Stats → Plan flow silently inferred `fitness_experience`, `pace_preference`, `days_per_week`, and `equipment_access` via `switch` expressions over `goal` + `activity_level`, hardcoded `equipment_access = 'basic_gym'`, `diet_preference = 'balanced'`, `injuries = []`. Two users with identical goal + activity answers produced identical plans regardless of actual equipment or training schedule — a regression from the legacy chat flow's accuracy.

## What Shipped

| Sub-PR | Commit | Summary |
|---|---|---|
| AI.1 | `284f027` | Stats screen — new `TARGET` kg tile next to `WEIGHT` (both gold-highlighted). Goal-derived seed (lose_fat -5, recomp -2, build_muscle +3). Clamped 40–250. Progress meter `02 · 03 → 02 · 04`. |
| AI.2 | `65ae007` | New `/onboarding/details` screen (`03 · 04`). 4 `WardRadioRow` sections — Experience (3) / Pace (3) / Days/Week (4) / Equipment (4). Defaults pre-select old inferred values so CONTINUE without changes preserves old behaviour. Router registration, stats→details nav, goal/plan progress meter updates (`01 · 04` / `04 · 04`). |
| AI.3 | `b9c7d0c` | `plan_screen._onReportForDuty` reads real values from `widget.data`. Inference kept as fallback only. Defaults updated per user decision: `diet_preference` `'balanced' → 'veg'`, `injuries` `[] → ['none']`. |

## New Flow

```
Welcome  (unnumbered)
Goal     01 · 04       primary_goal
Stats    02 · 04       +target_weight_kg
Details  03 · 04       NEW — fitness_experience, pace_preference,
                             days_per_week, equipment_access
Plan     04 · 04       consumes real values
```

## What Stays Defaulted (user edits via Profile → Edit Profile)

| Field | Default | Rationale |
|---|---|---|
| `lifestyle_activity` | Inferred from `activity_level` | 1:1 mapping. No extra user question would improve fidelity. |
| `diet_preference` | `'veg'` | Indian-first default. User can change in Profile. |
| `injuries` | `['none']` | Matches `edit_profile_screen._injuries` default marker. |
| `start_date` | `'this_monday'` | Unchanged from legacy chat flow. |

## Business Logic Preserved

`OnboardingNotifier.completeOnboarding` pipeline + `_syncOnboardingToSupabase` column filter, `WorkoutScheduleService`, `plan_generator`, `BmrCalculator`, Edge Function contracts — all untouched. Pipeline just gets better inputs.

## What's Deferred (PR AJ)

- `/onboarding/chat` retirement + `onboarding_chat_screen.dart` deletion. Legacy path stays as rollback until AI is validated end-to-end.

## Verification

`flutter analyze` on merged main: 4 issues — all pre-existing baseline warnings in `test/`. Zero new issues from PR AI.

On-device smoke test: **deferred by user** — merge proceeded without APK validation. Can rebuild from main worktree when needed.

## APK

Not yet built from PR AI branch. Build command:
```
cd .claude/worktrees/pr-ai-onboarding-fields
flutter build apk --dart-define-from-file=.env --flavor prod --release -t lib/main.dart
```
