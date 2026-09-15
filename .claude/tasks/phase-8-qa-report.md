# QA REPORT — Phase 8

**Date:** 2026-03-24
**Auditor:** @qa-agent
**Spec Reference:** CLAUDE.md (Sections 6, 9, 10, 14)
**Files Scanned:** All 100+ `.dart` files under `lib/`

---

## VIOLATIONS (must fix before launch)

| # | File | Line(s) | Rule Violated | Description |
|---|------|---------|---------------|-------------|
| V1 | `lib/features/profile/screens/profile_screen.dart` | 37-38, 283-284 | Rule 4 (Repository pattern) | Direct `HiveService.instance.configBox.get('units_metric')` and `.put('units_metric')` calls from a screen widget. Should go through a repository or provider. |
| V2 | `lib/features/profile/screens/profile_screen.dart` | 457-464 | Rule 4 (Repository pattern) | Direct `HiveService.instance.*.clear()` calls on 8 Hive boxes from the logout handler in a screen widget. Should be a method on a repository/service (e.g., `UserRepository.clearAllData()`). |
| V3 | `lib/features/profile/screens/reports_screen.dart` | 133, 232, 309 | Rule 4 (Repository pattern) | Direct `HiveService.instance.workoutBox`, `.healthBox`, `.nutritionBox` reads from a screen. Data aggregation should live in a repository. |
| V4 | `lib/features/profile/widgets/weekly_report_card.dart` | 245, 281 | Rule 4 (Repository pattern) | Direct `HiveService.instance.nutritionBox` and `.userBox.get('profile')` reads from a widget. Should use a repository. |
| V5 | `lib/features/train/widgets/stats_grid.dart` | 144 | Rule 4 (Repository pattern) | Direct `HiveService.instance.workoutBox` read from a widget to load PR data. Should use `WorkoutRepository`. |
| V6 | `lib/features/train/widgets/exercise_swap_sheet.dart` | 62 | Rule 4 (Repository pattern) | Direct `HiveService.instance.customBox` read from a widget. Should use `ExerciseRepository`. |
| V7 | `lib/features/home/widgets/pr_snapshot.dart` | 80 | Rule 4 (Repository pattern) | Direct `HiveService.instance.workoutBox` read from a widget. Should use `WorkoutRepository`. |
| V8 | `lib/features/nutrition/screens/diet_plan_screen.dart` | 259 | Rule 4 (Repository pattern) | Direct `HiveService.instance.configBox.put('saved_diet_plan', ...)` write from a screen. Should use a repository. |
| V9 | `lib/features/home/screens/home_screen.dart` | all | Rule 13 (Screen states) | No loading state (skeleton), no error state (retry button), no empty state handling. Screen renders directly without guards. |
| V10 | `lib/features/nutrition/screens/nutrition_screen.dart` | all | Rule 13 (Screen states) | No loading state, no error state, no empty state handling. |
| V11 | `lib/features/train/screens/train_screen.dart` | all | Rule 13 (Screen states) | No loading state, no error state. Has partial empty handling (`if todayWorkout != null`) but no explicit empty-state UI. No error/retry. |
| V12 | `lib/features/profile/screens/profile_screen.dart` | all | Rule 13 (Screen states) | No loading skeleton. Reads providers but has no loading/error branch for `AsyncValue` states. |
| V13 | `lib/features/profile/screens/reports_screen.dart` | all | Rule 13 (Screen states) | No loading state or error state handling. Computes data synchronously from Hive but has no fallback if boxes are empty/corrupt. |
| V14 | `lib/core/constants/app_constants.dart` + `lib/core/services/subscription_service.dart` | 42, 40 | Rule 14 (Business rules) | `featureDietPlanPdf` is listed in `allProFeatures` but CLAUDE.md Section 14 says "Diet plan PDF -- preview + swap + download" is FREE. Either remove from PRO list or clarify the spec if only certain PDF features are PRO. |
| V15 | `lib/features/home/screens/home_screen.dart` | 37, 53, 61, 67, 73, 79, 85, 226 | Design system (Spacing) | Uses hardcoded `horizontal: 16` instead of `AppSpacing.screenPadding` (18px). Spec says screen padding = 18px. |
| V16 | `lib/features/ai_coach/screens/ai_coach_screen.dart` | 192, 290, 382, 500, 847 | Design system (Spacing) | Uses hardcoded `horizontal: 16` instead of `AppSpacing.screenPadding` (18px). |
| V17 | `lib/features/profile/screens/profile_screen.dart` | 301, 338, 365 | Design system (Spacing) | Uses hardcoded `horizontal: 16` instead of `AppSpacing.screenPadding` (18px). |
| V18 | `lib/features/onboarding/screens/onboarding_chat_screen.dart` | 200, 229, 314, 384 | Design system (Spacing) | Uses hardcoded `horizontal: 16` instead of `AppSpacing.screenPadding` (18px). |

---

## WARNINGS (non-blocking, fix later)

| # | File | Description |
|---|------|-------------|
| W1 | `lib/features/ai_coach/widgets/telegram_card.dart:72` | Bare `TextStyle(fontSize: 13)` without GoogleFonts — uses system font, not DM Sans. Only used for a phone number display; low visual impact but inconsistent. |
| W2 | `lib/features/profile/widgets/profile_row.dart:126` | Bare `TextStyle(fontSize: 18, ...)` for chevron character. Not using GoogleFonts. Minor since it is a single unicode character. |
| W3 | `lib/features/nutrition/widgets/saved_meals_section.dart:224` | Bare `TextStyle(fontSize: 18)` for emoji leading text in a dialog. Not using GoogleFonts. |
| W4 | `lib/features/home/widgets/recent_food_logs.dart:83` | Bare `TextStyle(fontSize: 13)` without GoogleFonts for food quantity text. |
| W5 | `lib/features/nutrition/widgets/todays_meals_card.dart:69` | Bare `TextStyle(fontSize: 13)` for emoji placeholder. |
| W6 | `lib/features/home/widgets/streak_badge.dart:26` | Bare `TextStyle(fontSize: 15)` for fire emoji. |
| W7 | `lib/shared/widgets/pro_locked_overlay.dart` | `ProLockedOverlay` widget is defined but never imported/used in any feature file. Dead code. |
| W8 | `lib/core/constants/app_constants.dart:8-9` | Supabase URL and anon key are hardcoded with a TODO comment. These are public values (anon key is safe client-side per Supabase design), but should move to environment variables before production as the TODO says. |
| W9 | Multiple screens | Many screens use hardcoded magic numbers for vertical padding/margins (e.g., `fromLTRB(16, 14, 16, 10)`) instead of `AppSpacing` constants. While horizontal is the main spec concern (18px), vertical consistency could improve. |

---

## PASSED CHECKS

- [x] **No inline `isPro` checks** — Grep for `isPro` outside of `subscription_service.dart` returned zero hits. All PRO gates use `SubscriptionService.instance.gate()`.
- [x] **No old green color (#00e5a0)** — Zero occurrences of `0xFF00e5a0` anywhere in the codebase.
- [x] **Electric Cyan #00D4FF used correctly** — `AppColors.accent` = `Color(0xFF00D4FF)`. Used consistently across all files.
- [x] **No API keys client-side** — No `sk-`, `OPENAI`, `ANTHROPIC`, `CEREBRAS`, `GROQ`, or `GEMINI` API key strings found in any Dart file. All AI calls route through Edge Functions.
- [x] **Dark theme only** — Background hierarchy correct: `bg = #07090e`, `card = #0e1219`, `input = #161d28`. No light theme definitions.
- [x] **Riverpod used for state management** — All `setState()` calls are local widget state (form toggles, animation flags, text controllers). No shared state managed via `setState`. All providers use `flutter_riverpod`.
- [x] **PaywallSheet is the ONLY paywall UI** — `showPaywallSheet()` is the sole paywall entry point. No custom paywall modals or dialogs found. Used in 10+ locations consistently.
- [x] **`subscription.gate()` pattern followed** — 17 gate calls found across screens. All use `SubscriptionService.instance.gate(featureKey, onPro: ..., onFree: ...)`. Feature keys sourced from `AppConstants`.
- [x] **Plan generator is local Dart** — `plan_generator.dart` contains no HTTP, API, or network calls. Queries only Hive `exerciseBox`.
- [x] **Import paths correct** — Features use relative imports (`../providers/`, `../widgets/`) within their feature. Cross-feature imports use `package:icanbefitter/`. No `package:icanbefitter/features/` imports from other features (proper isolation).
- [x] **Typography system correct** — `AppTypography` uses `GoogleFonts.getFont('DM Sans', ...)` via private `_font()` helper. All weights/sizes match CLAUDE.md spec exactly.
- [x] **Colors file matches spec** — All color values in `colors.dart` match CLAUDE.md Section 9 exactly.
- [x] **Spacing constants correct** — `AppSpacing` and `AppRadius` values match spec (screen=18, card=16, section=14, grid=9, inline=8; pill=100, cardL=22, cardM=16, cardS=14, row=12, badge=100).
- [x] **Border radii correct** — No non-standard radius values found. All `BorderRadius.circular()` calls use 100, 22, 16, 14, or 12.
- [x] **Shareable cards include branding** — `ShareableCard` wraps all shareable content with ICANBEFITTER wordmark + QR code pointing to `AppConstants.appUrl`. Used by `WorkoutReceiptCard`, `ChallengeCard` (Beat My Coach), and `PredictionCard`.
- [x] **Phase 1 is never gated** — No `gate()` call for Phase 1. The `featurePhases2To12` gate is only triggered when user tries to generate phases beyond Phase 1.
- [x] **No Supabase calls from widgets/screens** — Zero `supabase.` or `Supabase.` calls found in any screen or widget file. All Supabase interaction goes through services/repositories.
- [x] **Hive boxes defined in AppConstants** — All 10 box names match CLAUDE.md spec.
- [x] **Free tier limits match spec** — `freeAiMessagesPerDay=15`, `freeAiTrialDays=30`, `freeAiTextLogsPerDay=3`, `freeScanMealPerMonth=3`, `freeCartAuditorPerMonth=1`, `beatMyCoachIntervalDays=14` all match CLAUDE.md Section 14.
- [x] **PRO tier limits match spec** — `proAiTextLogsPerDay=10`, `proScanMealPerDay=3`, `proCartAuditorPerDay=3` all correct.
- [x] **Pricing correct** — `monthlyPriceInr=349`, `yearlyPriceInr=2999` match spec.
- [x] **Phase unlock formula correct** — `phaseUnlockCompletionRate=0.8`, `phaseUnlockMinWeeks=4` match spec.
- [x] **Sync intervals correct** — `fullSyncIntervalDays=7`, snapshot at 17:30 UTC (11 PM IST).

---

## Summary

**18 violations, 9 warnings.**

**Overall: FAIL** (violations V1-V8 break the repository pattern rule; V9-V13 break the screen states rule; V14 is a business logic conflict; V15-V18 break the design system spacing spec.)

### Priority Fix Order

1. **V9-V13 (Screen states)** — High severity. All 5 main tab screens lack loading/error/empty states. This will cause poor UX when data is loading or when Hive boxes are empty (fresh install before seed completes).

2. **V1-V8 (Repository pattern)** — Medium severity. 8 files make direct Hive calls from widgets/screens. Refactor data access into repositories to maintain clean architecture and testability.

3. **V15-V18 (Screen padding)** — Medium severity. 4 screens use `16px` horizontal padding instead of the spec's `18px` (`AppSpacing.screenPadding`). Easy find-and-replace fix.

4. **V14 (Diet plan PRO key)** — Low severity but needs clarification. Either remove `featureDietPlanPdf` from `allProFeatures` list (since diet plan is FREE per CLAUDE.md), or update CLAUDE.md to clarify that only PDF export is PRO while preview/swap is free. Currently the key exists but is never actually gated in `diet_plan_screen.dart`, so there is no user-facing bug — just a code/spec mismatch.
