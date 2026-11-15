# PR AH — Part B (Wardroom Handoff Follow-Up, Round 2)

**Date:** 2026-04-20
**Branch:** `feat/pr-ah-part-b` → main
**Merge commit:** `895b2e2`
**Parent merge (PR AG):** `386f42e`
**Main tip before:** `b201255`
**Main tip after:** `895b2e2`
**Sub-PRs:** 6
**Part C token hygiene:** included as AH.C1

---

## 1. Scope & timeline

Between PR AG merge (`386f42e`) and PR AH merge (`895b2e2`) — same day, 2026-04-20. Six sub-PRs closing the "Part B" gaps enumerated at the end of the Wardroom sweep report, plus an audit of the 8 "Part C" screens for token drift.

---

## 2. What shipped

| Sub-PR | Commit | Area | One-line summary |
|---|---|---|---|
| AH.1 | `473158c` | Home | Streak-banner threshold floor 15 → 18 (`daily.jsx` evening-only nudge); weight sparkline chips simplified from `7d/30d/3m/1y/All` → `7D/30D/90D`. |
| AH.5 | `337f271` | Nutrition | New `dietPlanProvider` + `PlannedSlot` model; `TodaysMealsCard` renders "FROM YOUR DIET PLAN" hint on empty slots; `showFoodSearchSheet(initialQuery:)` pre-fills search with planned food name; `_savePlan` invalidates the provider. |
| AH.7 | `436bdf0` | Profile | New "Rate App" tile in SHARE & GROW (Play Store URL via `url_launcher` `externalApplication`). |
| AH.9 | `e7bc656` | AI Coach | Greeting includes user's first name ("Good morning, Upendra."). Pulls `userProfileProvider.full_name`, first-token split, graceful fallback. |
| AH.8 | `3681f2f` | Weekly Report | `WeeklyReportCard` converted StatelessWidget → ConsumerWidget; KV rows replaced with 2×2 `WardSpark` grid (Weight/Calories/Protein/Workouts). New `weeklyReportDataProvider` aggregates last-7-days from Hive. |
| AH.C1 | `ed737f2` | Token hygiene | 4 legacy `0xFF00D4FF` cyan literals in `train_provider` + `profile_provider` swapped to `AppColors.accent`/`warn`/`bad`/`bg`/`textPrimary`. |

Total: **6 commits**, **+917 / −104 lines** across 14 files, 2 new files.

---

## 3. Verify-only items (no code changes)

| Task | Why no change | Evidence |
|---|---|---|
| B.3 Train templates list | Already wired to real data. | `templatesProvider` (`train_provider.dart:1678`) scans `workoutBox` for `type == 'template'`. |
| B.4 `+ Create Custom Exercise` dashed CTA | Already wired. | `_buildCreateCustomExerciseSection` in `train_screen.dart` opens `CreateCustomExerciseSheet`; `WardDashedBorder` lives at `lib/shared/widgets/wardroom/ward_dashed_border.dart`. |
| B.10 Tabular-nums global audit | Already applied globally. | `_fraunces()` in `typography.dart` sets `fontFeatures: [FontFeature.tabularFigures()]` on every Fraunces style. |

---

## 4. Part C audit result

All 8 non-handoff screens checked for `Color(0x...)` literals and legacy palette drift:

| Screen | Path | Drift? |
|---|---|---|
| Splash | `lib/features/auth/screens/splash_screen.dart` | 0 literals |
| Sign-in | `lib/features/auth/screens/sign_in_screen.dart` | 0 literals |
| Diet Plan | `lib/features/nutrition/screens/diet_plan_screen.dart` | 0 literals |
| Template Builder | `lib/features/train/screens/template_builder_screen.dart` | 0 literals |
| Graduation | `lib/features/train/screens/graduation_screen.dart` | 0 literals |
| Progress Photos | `lib/features/profile/screens/progress_photos_screen.dart` | 0 literals |
| My Submissions | `lib/features/profile/screens/my_submissions_screen.dart` | 0 literals |
| Onboarding Chat | `lib/features/onboarding/screens/onboarding_chat_screen.dart` | 0 literals |

**Conclusion:** zero Part C drift. No Tier-1 fixes needed. The 4 cyan legacy refs AH.C1 caught were in **shared providers** (train, profile), not in Part C screens themselves.

**Tier 2 (onboarding_chat retirement):** scheduled behind PR AI (see §9).
**Tier 3 (Splash / Sign-in / DietPlan / TemplateBuilder / Graduation / ProgressPhotos / MySubmissions redesigns):** held indefinitely — no JSX spec exists; do not invent one.

---

## 5. New files

| File | Purpose |
|---|---|
| `lib/features/nutrition/providers/diet_plan_provider.dart` | Single source for per-slot planned-meal hints. `Map<String, PlannedSlot>` keyed by `breakfast`/`lunch`/`dinner`/`snack`. Reads `configBox['saved_diet_plan']` and aggregates items. |
| `lib/features/profile/providers/weekly_report_data_provider.dart` | 7-day aggregation for Weekly Report sparklines. Four `List<double>` series (weight forward-filled, others zero-filled) sourced from `healthBox` / `nutritionBox` / `workoutBox`. |

---

## 6. Business-logic preservation audit

Every sub-PR's commit message includes this block; consolidated here:

- Subscription gate (`subscription_service.gate()`, `verifyFromServer()` for high-value features) — **untouched**.
- Fire-and-forget sync rules (`pushSnapshot()`, `syncWorkoutData()`, `syncNutritionData()`) — **untouched** on every mutation path.
- Completion pipeline (`OnboardingNotifier.completeOnboarding`) — **untouched**.
- `WorkoutScheduleService` — **untouched**.
- Plan generator (`plan_engine/*`, CLAUDE rule #14) — **untouched**.
- Payment flow (Razorpay webhook, verify-payment, promo redemption, idempotency) — **untouched**.
- Edge Function contracts (18 live functions) — **untouched**.

---

## 7. Verification performed

- `flutter analyze` (PR AH worktree, each commit): 0 new issues on each. Final main post-merge: 4 issues, all pre-existing baseline warnings in `test/plan_engine_v3_test.dart` and `test/plan_generator/v4_diagnostic/*.dart`.
- On-device smoke test: **deferred by user** — merge proceeded without APK validation. Re-run against current main when desired.
- Integration tests: not run (no affected flows under `integration_test/`).

---

## 8. Branch & APK locations

- **PR AH worktree:** `.claude/worktrees/pr-ah-part-b` (branch `feat/pr-ah-part-b`, now merged). Keep as reference for post-merge sanity.
- **PR AG worktree:** `.claude/worktrees/pr-ag-handoff-gaps` (branch `feat/pr-ag-handoff-gaps`, merged). Contains the 129-MB pre-merge APK; no new APK built for AH.
- **Main worktree:** `C:\Upendra\Claude Code\Fitness App\`. No APK built from main post-merge (user deferred).

---

## 9. Recommended next steps

| # | Item | Notes |
|---|---|---|
| 1 | **PR AI — stepped onboarding field coverage** | Collect `fitness_experience`, `days_per_week`, `equipment_access`, `lifestyle_activity`, `pace_preference`, `diet_preference`, `injuries`, target weight. Unlocks Part C Tier 2 (delete `onboarding_chat_screen.dart`). |
| 2 | Wire **Coach Suggested Actions / Patterns / Today's Insight CTAs** to real data | Blocked on `ai-proxy` + `rolling-context` emitting structured objects with confidence, apply/skip tool-calls. |
| 3 | Push to origin | `git push origin main` (126+ commits ahead). Held pending user go-ahead. |
| 4 | Worktree cleanup | Prune `.claude/worktrees/agent-*` stale worktrees (~14 of them). |

---

## 10. One-liner for changelogs

> PR AH ships 6 sub-PRs closing the Wardroom Part B gaps (streak banner evening-only floor, weight sparkline chips, nutrition "From Your Diet Plan" hints with tap-to-log pre-fill, profile Rate App tile, weekly report 4-up sparklines from real Hive data, coach dynamic first-name greeting) plus a Part C token-hygiene audit that swept 4 legacy `0xFF00D4FF` cyan refs to the current `AppColors.accent`. Zero new `flutter analyze` issues. Merge `895b2e2`.
