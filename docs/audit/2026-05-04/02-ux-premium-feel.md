# Audit 2: UX / premium feel findings

Audit date 2026-05-04. Branch `main`. Scope per `CLAUDE.md` §9, §13, §13a, §17, §18, §19. Findings are read-only — no fixes applied.

## P0 (visible regression, lie in copy, data loss in onboarding)

### P0-1 Welcome hero copy lies about streaks
`lib/features/onboarding/screens/welcome_screen.dart:147-154` shows the first marketing line every new user reads:

> "Personalised coaching, disciplined programming, and an AI that remembers every lift. **No streaks, no gimmicks — just the log.**"

The entire app is built around streaks. CLAUDE.md §13 lists "streak counter" as priority 1 in the home header; §15 has a `streak-guardian` Edge Function on cron; §10 lists "streak protection" as a proactive trigger; the home screen has a `WardStatusStrip` streak pill in row 2 (`home_screen.dart:325`); `streak-warning-banner` fires on workout days; "streak freeze" is a visible affordance. The user is sold a product that doesn't exist. Either kill streaks (won't happen — they're load-bearing) or rewrite the line. Suggested: `"…remembers every lift. Disciplined programming, no gimmicks."`

### P0-2 Dynamic water target computed, saved, never read
`lib/features/onboarding/providers/onboarding_provider.dart:356` computes `water_target_ml = (currentWeightKg * 35).round()` and writes it to `userBox['profile']` AND syncs it to Supabase (`sync_service.dart:1828-1829`). It is **never read** by any UI surface:
- `lib/features/nutrition/widgets/hydration_card.dart:53` — `const waterTarget = 3000`
- `lib/features/nutrition/screens/nutrition_screen.dart:365` — `const waterTarget = 3000`
- `lib/features/home/screens/home_screen.dart:470` — `const waterGoalMl = 3000`
- `lib/features/home/widgets/water_quick_sheet.dart:31` — `const targetMl = 3000`

A 60 kg user hits the 3000 ml UI bar at 100% but their derived target is 2100 ml; a 95 kg user is told they're done at 3000 ml when their derived target is 3325 ml. The personalised plumbing exists end-to-end and the UI ignores it.

### P0-3 Release crash copy explicitly violates CLAUDE.md §11
`lib/app.dart:60-66` renders the global `ErrorWidget.builder` and shows:

> "Please restart the app. If this persists, contact support."

CLAUDE.md §19 ("Never use 'restart the app' copy") and the comment in `lib/shared/widgets/sync_banner.dart:7` ("Copy rules (CLAUDE.md §11): no 'restart the app'") explicitly forbid this. It's the single most-visible error string in the app and it points the user at an action that fixes none of the underlying causes (Hive corruption, network, Edge Function failure).

### P0-4 Onboarding sex defaults to "male" with no neutral
`lib/features/onboarding/screens/identity_screen.dart:62` initialises `_sex = 'male'` and renders all three pills with the male pill pre-filled gold (`identity_screen.dart:337-367`). Every female / non-binary user who hits CONTINUE without tapping the pill has their sex silently captured as male — flows straight into BMR calculation, calorie targets, protein targets, and Hive profile. No required-field validation fires (unlike DOB and name). This is a real data-correctness defect, not microcopy.

### P0-5 Step labelling inconsistent on Identity
`identity_screen.dart:134` shows progress as `01 · 05` (matching the §13a "Identity = step 01 of 05" spec) but `identity_screen.dart:171` shows the section eyebrow as `QUESTION 0` (zero-indexed). Pick one. Mission Brief is the only step the spec calls "step 00".

## P1 (premium-feel breaker)

### P1-1 Sign-in input hint is unreadable
`lib/features/auth/screens/sign_in_screen.dart:889-891` sets every field hint to `AppColors.textDisabled` (`#3F495A`) on `AppColors.input` (`#0A1423`). Approximate WCAG contrast ratio ≈ 1.5:1 — fails AA (4.5:1) and AAA (7:1) by a wide margin. Users with average eyesight on a phone in daylight can't see "Email", "Password", "Phone number" hints. `textMute` (`#5E6B80`, ratio ≈ 3.0:1) would still fail body-text AA but would be the right token for placeholder.

### P1-2 Unselected onboarding chips are de-facto disabled
`lib/features/onboarding/screens/details_screen.dart:471-491` renders every unselected Experience / Pace / Days / Equipment chip at `opacity: 0.55`. The chip text (`textDim` #B5BDCB at 0.55) on `bg` ≈ ratio 4.0:1 — borderline-fails WCAG AA. More importantly, perceived saturation tells the user "this is unavailable", not "this is not selected". Same screen has a PRE-SELECTED default (Intermediate / Balanced / 4 / Basic Gym per CLAUDE.md §13a), so most users tap CONTINUE on screens that look mostly-disabled. Drop opacity to 0.85 or 1.0 and rely on fill color alone for state.

### P1-3 Workout completion → receipt is a hard cut
`lib/features/train/widgets/workout_receipt_sheet.dart:19-26` opens the receipt as a default `showModalBottomSheet`. There is no `Hero` from the today-card "DONE" state to the receipt, no `AnimatedSwitcher` on the home today-card state change. The single most rewarding moment in the app — a finished workout — is a slide-up dialog. Compare to `paywall_sheet.dart:27-30` which at least has a 350 ms custom AnimationController. The receipt deserves more, not less.

### P1-4 Hardcoded color literals leak in profile / train / induction
`lib/features/profile/widgets/profile_identity.dart:124-126`, `subscription_card.dart:44-53`, `profile_banner.dart:31-33` — gradients of raw `Color(0xFF0a1628)` / `Color(0xFF0d2040)` / `Color(0xFF001a0a)`. These approximate but don't equal `AppColors.cardTop` (`#0F1E36`) / `cardHi` (`#0B172A`). Same drift in `lib/features/train/widgets/rest_timer_modal.dart:33,189`, `lib/features/train/providers/train_provider.dart:904-907` (4 superset colors), `lib/features/profile/widgets/badges_grid.dart:342-343` (legacy `#0e1219` / `#161d28`). `induction_screen.dart:187,227,271` and `muster_screen.dart:259,520` use `Color(0xFFD8D8D8)` / `#E8E8E8` for parchment text instead of `textPrimary`. Wardroom palette drift is exactly what PR R fixed; new drift is leaking back in.

### P1-5 SeedService + FoodRepository dartdoc still says "5,000 foods"
`lib/core/services/seed_service.dart:23` says "foods (5,000)"; `lib/shared/repositories/food_repository.dart:6` says "5,000 Indian-first foods"; `food_repository.dart:32` says "5K items"; `food_search_sheet.dart:13` says "5K items"; `conversational_log_handler.dart:78` says "5K database". Actual count is 1431 (CLAUDE.md §18, post APK Test #3 expansion). Not user-visible (dartdoc only) — but the `food_database.json` is 1431 and any future engineer reading these comments will trust them. Rename to "1,400+" or just "all bundled foods".

### P1-6 Paywall subtitle "AI" repeated 8 times in 13 lines
`lib/shared/widgets/paywall_sheet.dart:67-95`. Eight of nine `_proBenefits` and 6 of 12 subtitle branches lead with "AI" or "AI Coach". When a word appears that often, it stops registering. Variable phrasing: "Unlimited coaching with deep personalised insights" instead of "Unlimited AI Coach with deep personalised coaching" (also redundant — "coach" twice).

### P1-7 Paywall promo "Network error" copy
`paywall_sheet.dart:146` — `_promoError = 'Network error. Try again.'`. CLAUDE.md §11 has explicit error-mapping for network failure; this string bypasses that and reads generic. Should be "Couldn't reach the server — check your connection." Also non-actionable when the user is offline (Try again will fail again).

### P1-8 AI coach screen empty state for new users
`lib/features/ai_coach/screens/ai_coach_screen.dart:300-400` only handles the message-list / sending state. Verified at `ai_coach_screen.dart:251-300` — no first-time-user dedicated empty state with example prompts. New users land on a captain-cap avatar + "Aye Captain" header + empty message list with no scaffolding for what to ask. Compare to muster/induction screens which DO have copy. Coach is the highest-stakes entry point in the app — needs an empty state with 3-4 example chips.

## P2 (polish)

### P2-1 Identity DOB validation uses snackbar; name uses inline
`identity_screen.dart:421-454`. Name validation surfaces inline below the field with `_nameError` state. DOB validation surfaces as a red snackbar floated at the bottom of the screen. Two different validation languages on the same form. Move DOB to inline error under the date picker tile.

### P2-2 Hydration "Critical / See doctor" status pills
`hydration_card.dart:34-47` ladders urine status to `'Critical — Brown — consult a doctor'` and `'See doctor — Dark brown — medical attention'`. Health-app medical claims are a legal grey zone for an unregistered fitness app (especially with `body composition` AI features). Consider softer copy: "Heavy dehydration — drink water now and rest" / "Unusual color — check with a doctor if persistent."

### P2-3 `lib/shared/widgets/paywall_sheet_phase_variant.dart:120` TODO leaks
The phase-variant paywall has `// TODO: wire to direct checkout route once available.` next to a non-functional flow. If the route is missing, the upgrade button does nothing — silent broken affordance. Either remove the variant or wire it.

### P2-4 Splash 3000 ms hard delay
`lib/features/auth/screens/splash_screen.dart:99` includes `Future.delayed(const Duration(milliseconds: 3000))`. Three-second forced wait on every cold launch is anti-premium. Premium apps either show the splash for as long as init takes (no forced floor) or use a 600-1000 ms minimum.

### P2-5 Onboarding stat seed is "75.0 kg, 175 cm"
`stats_screen.dart:39-41,60-62`. Defaulting to a 75 kg / 175 cm body is fine demographics-wise but every Indian user has to clear and retype. Indian male average is closer to 65 kg / 170 cm; female 55 kg / 158 cm. Sex-aware seed if `sex` known from Identity step.

### P2-6 Welcome screen referral code field always visible
`welcome_screen.dart:243-291` shows the "Got a code? AVYA-XXXXXXXX" field above the privacy footer, always. 90%+ of organic signups have no code. Hide behind a "Got a referral code?" disclosure link.

### P2-7 Empty state for nutrition / weekly chart not verified
Couldn't deep-read all 5 main screens within budget. `nutrition_screen.dart:1-100` shows skeleton + retry path; the per-card empty states (TodaysMealsCard, WeeklyChartCard, YourFoodsSection) need an explicit pass — they showed up in the import list but not in this audit's read window.

## Water target — concrete recommendation

**Today:** dynamic target IS computed (`weight × 35 ml`, capped implicitly by the +500 ml glass grid showing 8 cells = 4000 ml UI ceiling), saved to Hive + cloud, and **completely ignored** by every reader. UI is hardcoded at 3000 ml everywhere.

**Recommendation:** wire what already exists. Read `userBox['profile']['water_target_ml']` at the four sites listed in P0-2. Fall back to 3000 if null (legacy users who onboarded before the field was added).

**Formula refinement (optional):** the prompt suggested `weight × 0.04 + 0.5L training day + 0.3L if active`. Current `weight × 35` is a reasonable baseline (35 ml/kg is the Mayo/EFSA midpoint for adults). For an Indian-first product with tropical climate + active lifters, my recommendation is:

```
base_ml = weight_kg * 35
if (lifestyle_activity in {'active','very_active'}) base_ml += 300
if (today is workout_day) base_ml += 500
target_ml = base_ml.clamp(2000, 4500)
```

This lands a 60 kg sedentary user on 2100 ml (down from the wrong 3000 ml UI), a 75 kg moderate user on 2625 ml, and a 90 kg active lifter on a training day at 3950 ml — matches ICMR + ACSM guidance and adjusts for context the user has already entered. Implementation is one helper in `BmrCalculator` and one read-site change.

**Don't** ship the formula change without first wiring the existing field. The formula is a P2 refinement; the read-path is the P0.

## Quick wins

1. Replace welcome line 149 — kills the streak lie. 5 min.
2. Wire `water_target_ml` reader in `hydration_card.dart`, `home_screen.dart`, `nutrition_screen.dart`, `water_quick_sheet.dart`. ~30 min, fixes P0-2 and surfaces feature already paid for.
3. Replace `app.dart:66` "Please restart" copy with "Tap to retry" + a retry button. 10 min.
4. Force `Identity._sex = null` and gate CONTINUE behind selection. 5 min, prevents P0-4 silent-default.
5. Bump unselected chip opacity to 0.85 in `details_screen.dart:473`. 1 min, lifts entire onboarding feel.
6. Sign-in hint color: `textDisabled` → `textMute`. 1 min, gains 2× contrast.

## Things checked and clean

- No occurrences of `0xFF00D4FF` (electric cyan) or `0xFF00e5a0` (legacy green) in `lib/` — palette migration clean.
- Notification copy across 4 proactive triggers (`re-engagement`, `workout-window-closing`, `protein-gap-alert`, `plateau-alert`) is human, name-personalised, and short. No "robot" voice. Examples: "haven't heard from you in a few days. Everything okay?" / "haven't seen Push Day logged yet. Still happening? Even 20 mins counts." Empathetic, on-brand for "drill instructor with empathy". Approved.
- Edit Profile sync gap (CLAUDE.md §19 "Edit Profile Save writes Hive but never user_profile") was fixed APK Test #3 / Bug B — sync fan-out tests in `test/sync/` lock it.
- Home screen priority order (`home_screen.dart:201-410`) matches CLAUDE.md §13 with the Test #10 redesign applied — no leftover deprecated cards.
- `RestoringScreen` post-auth gate (`restoring_screen.dart`) handles the three branches (onboarded / mid-flow / new user) cleanly with a 15s escape CTA — better than industry norm for re-sign-in.
- `paywall_sheet` is the single source of truth (CLAUDE.md §6 rule 7) — no custom paywall modals found in feature code.
- Motion: 25 files use `AnimatedContainer` / `AnimatedSwitcher` / `AnimationController` — broad coverage. The gaps are at the highest-stakes transitions (workout complete, P1-3) not at low-stakes ones.
- Active workout is no longer PRO-gated (Q6, Test #2 batch) — verified in `train_screen` entry points; `featureActiveWorkoutMode` is `@Deprecated`.
