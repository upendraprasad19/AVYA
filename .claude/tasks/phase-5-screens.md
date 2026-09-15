# Phase 5: Core Screens (5x PARALLEL)

## Agent: @screen-agent (×5, run in parallel)
## Deps: Phase 3 (Auth), Phase 4 (Services)

## CRITICAL RULES (all screens)
- ALL data from Hive — zero hardcoded values
- Dark theme, DM Sans font (GoogleFonts), Electric Cyan #00D4FF accent
- PRO features gated via `subscriptionService.gate()` — NEVER inline `if (isPro)`
- Phase 1 ALWAYS free, even if subscription check fails
- Every screen: loading skeleton, error state (retry), empty state
- Left-aligned headings (never center-aligned)

---

## 5.1 Home Screen

### Layout (Priority Order)
1. Header (name + greeting + avatar + streak counter)
2. Weekly calendar strip — reads `scheduled_workouts` from Hive workoutBox
   - Dumbbell icon on planned days
   - Tick on completed days
   - Dash on rest days
   - Highlight today
   - Grey out past unlogged days
3. Quick actions: Log Workout | Log Meal | Hydration | Sleep
4. Today's workout card → "START" button (from workoutBox, today's date)
5. Nutrition snapshot — calories + protein vs target from BMR
   - **Stat widgets: value + unit on ONE LINE** ("0 kcal" not "0" then "kcal")
   - Compact height for Fuel, Protein, Steps widgets
6. AI Coach insight card
7. Weight sparkline (last 7 entries from healthBox)
8. PR snapshot (bench, squat, deadlift from workoutBox)
9. Recent logged foods (from nutritionBox)
10. Step counter (Health Connect — biometric sync)

### Data Sources
- Calendar strip → `workoutBox` (scheduled_workouts)
- Today's workout → `workoutBox` (scheduled_workouts WHERE date = today)
- Nutrition → `nutritionBox` (today's nutrition_logs)
- Weight → `healthBox` (weight_logs, last 7)
- PRs → `workoutBox` (workout_logs WHERE is_pr = true)
- Steps → Health Connect API
- Sleep → Health Connect API
- Morning alert → from configBox or push notification payload

---

## 5.2 Train Screen

### Layout
- **Heading: LEFT-ALIGNED** (not center)
- Phase indicator (Phase 1 · Foundation)
- Horizontal week selector (Week 1-4)
- 7-day workout map per week (synced to actual calendar dates)
- Exercise list per day (from workoutBox templates)

### Active Workout Mode
- logging_type drives UI:
  - `weight_reps`: Weight (kg) + Reps + Sets
  - `bodyweight_reps`: Reps + Sets (no weight input)
  - `weighted_bodyweight`: Added Weight + Reps + Sets
  - `timed`: Sets + Duration (seconds) + rest timer
  - `cardio`: Duration (min) + Distance (km)
  - `distance`: Distance + load
- Rest timer between sets (with notification)
- Auto-fill weight from last workout log
- PR detection: compare to best previous log, flag `is_pr = true`
- After completion: show Workout Receipt card → "Share Your Session" button

### Features
- [ ] Exercise swap (dropdown from exerciseBox, filtered by same category + equipment)
- [ ] Add custom exercise → save to customBox + Supabase
- [ ] Template builder (create custom workout from exerciseBox)
- [ ] Copy week to week
- [ ] PRO gate: `phases_2_to_12` — after Week 4, show Phase 2 locked with paywall
- [ ] All workout coaching cues, common mistakes, pro tips — FREE for all users

---

## 5.3 Nutrition Screen

### Layout
- Tabs: Meals | Water
- BMR/TDEE snapshot (from user_profile in userBox)
- Calorie ring + macro bars (from today's nutritionBox)
- Today's log — all meals listed with timestamps

### Features
- [ ] Food search — query foodBox (5,000 items)
- [ ] AI food text analysis: type "2 rotis with dal" → AI parses macros
  - FREE: 3 text logs/day (`AppConstants.freeAiTextLogsPerDay`)
  - PRO: 10 text logs/day (`AppConstants.proAiTextLogsPerDay`)
  - Gate: `ai_text_log_pro` for uses beyond free limit
  - Counter in Hive configBox, resets on new day
- [ ] Scan meal camera: point at plate → Gemini Vision → macros
  - FREE: 3 scans/month (`AppConstants.freeScanMealPerMonth`)
  - PRO: 3 scans/day (`AppConstants.proScanMealPerDay`)
  - Gate: `scan_meal_pro` for uses beyond free limit
  - Soft cap warning: "2 of 3 scans used today"
  - Counter in Hive configBox
- [ ] Cart Auditor: screenshot grocery cart → Gemini Vision → macro analysis + swap suggestions
  - FREE: 1 scan/month (`AppConstants.freeCartAuditorPerMonth`)
  - PRO: 3 scans/day (`AppConstants.proCartAuditorPerDay`)
  - Gate: `cart_auditor_pro`
  - Soft cap warning at 2/3
- [ ] Add custom food → save to customBox + Supabase
- [ ] Saved meals (one-tap re-log from nutritionBox)
- [ ] Hydration tracker + HydrationColorCard
- [ ] Diet plan generator (from food DB, zero API, FREE for everyone)
  - Preview → swap items → save → download as PDF (FREE)
- [ ] Adjustable food portions — FREE for all users

---

## 5.4 AI Coach Screen

### Layout
- Channel toggle: [In-App Chat] [Telegram]
- If Telegram not connected → connect prompt
- Chat interface with message bubbles

### Features
- [ ] In-app chat → calls Cerebras via Edge Function
  - FREE: 15 msg/day for 30 days (Cerebras Llama 3.1 8B)
  - PRO: unlimited (Cerebras gpt-oss-120B)
  - Gate: `ai_coach_unlimited`
  - Message counter + trial expiry in configBox
- [ ] Quick prompt chips: "How did I do?", "What to eat?", "Am I ready?", "Analyse progress"
- [ ] Reasoning tab: [Quick] [Deep Analyse]
  - Deep = PRO gate (`reasoning_tab`) → GLM-4.7 on Cerebras
  - Free users see Deep tab → tap → paywall
- [ ] Voice notes input (push-to-talk)
  - PRO only → gate: `voice_notes`
- [ ] Future Prediction card display
  - Shows post-onboarding prediction (all users)
  - PRO: "Get Updated Prediction" button (monthly refresh)
  - Gate: `prediction_monthly`
- [ ] Messages stored in Hive coachBox
- [ ] System prompt includes `user_daily_snapshot` JSON (~300 tokens)

---

## 5.5 Profile Screen

### Layout
- Bio stats (age, height, weight badges)
- Goal card
- Current phase + progress

### Features
- [ ] Edit profile form → save to Hive userBox + Supabase (background)
- [ ] Biometric sync:
  - Steps (Google Fit / Health Connect) — FREE
  - Sleep (Google Fit / Health Connect) — FREE
  - Display only for now. Adaptive workouts = Phase 2.
- [ ] Progress photos — PRO only (`progress_photos`)
  - Photo capture + secure storage in Supabase Storage
  - Side-by-side timeline view
- [ ] Weekly nutrition report:
  - First report free (after Week 1)
  - Weekly thereafter → PRO (`weekly_ai_report`)
- [ ] Subscription status card:
  - Free: show upgrade CTA with ₹349/month, ₹2,999/year
  - PRO: show plan + expiry date
- [ ] Logout → clear Hive → sign out → route to auth

---

## Completion Criteria
- All 5 screens render with REAL data from Hive (zero hardcoded values)
- Weekly calendar strip reads scheduled_workouts and shows correct status per day
- Train screen shows plan generated by PlanGenerator, not _sampleWeeks
- All usage counters (AI text, scan meal, cart auditor) tracked in Hive and reset correctly
- Soft cap warnings display at correct thresholds
- PRO features gated via subscription.gate() with keys from AppConstants
- Phase 1 always free under all conditions
- Loading skeleton, error state (retry), empty state on all screens
- Design system: dark theme, DM Sans, Electric Cyan, correct spacing/radius

## Reference
- `/CLAUDE.md` Sections 3, 6, 8, 9, 10, 13, 14
- `lib/core/constants/app_constants.dart` — all feature keys and limits
