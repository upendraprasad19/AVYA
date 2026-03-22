# Phase 5: Core Screens (5x PARALLEL)

## Agent: @screen-agent (×5, run in parallel)
## Deps: Phase 3 (Auth), Phase 4 (Services)

## 5.1 Home Screen (index)
- [ ] Header (name + greeting + avatar + streak counter)
- [ ] Weekly calendar strip (7 days, color-coded)
- [ ] Quick actions: Log Workout | Log Meal | Hydration | Sleep
- [ ] Today's workout card → Start Workout
- [ ] Nutrition snapshot (calories + protein vs target from BMR)
- [ ] AI Coach insight card
- [ ] Weight sparkline (last 7 entries from healthBox)
- [ ] PR snapshot (top 3 lifts from workoutBox)
- [ ] Recent logged foods
- [ ] Step counter (Health Connect)
- [ ] ALL data from Hive — zero hardcoded values

## 5.2 Train Screen
- [ ] Phase plan view (Phase 1 free, 2-12 PRO gated)
- [ ] Horizontal week selector (Week 1-4)
- [ ] 7-day workout map per week
- [ ] Exercise list per day (from templates in workoutBox)
- [ ] Active workout mode (PRO gate: `active_workout_mode`)
  - [ ] logging_type drives UI (weight_reps, bodyweight_reps, timed, cardio)
  - [ ] Rest timer between sets
  - [ ] Auto-fill weight from last log
  - [ ] PR detection on save (is_pr flag)
- [ ] Exercise swap (dropdown from exerciseBox)
- [ ] Add custom exercise → save to customBox + Supabase
- [ ] Template builder (create custom workout)
- [ ] Copy week to week
- [ ] Log workout → save to Hive workoutBox

## 5.3 Nutrition Screen
- [ ] Tabs: Meals | Water
- [ ] BMR/TDEE snapshot (from BMR calculator)
- [ ] Calorie ring + macro bars (from today's nutritionBox)
- [ ] Log Food → search foodBox (5,000 items)
- [ ] Add custom food → save to customBox + Supabase
- [ ] Free: standard portions
- [ ] PRO: adjustable quantities (`adjustable_portions`)
- [ ] PRO: AI food text analysis (`ai_food_analysis`)
- [ ] PRO: Scan meal with camera (`scan_meal`)
- [ ] Auto-suggest companions (dal → rice, ghee)
- [ ] Saved meals (one tap re-log from nutritionBox)
- [ ] Today's log → all meals listed
- [ ] Hydration tracker + HydrationColorCard
- [ ] Diet plan generator (from food DB, zero API)
- [ ] PRO: Download diet plan as PDF (`diet_plan_pdf`)

## 5.4 AI Coach Screen
- [ ] Channel toggle: [In-App Chat] [Telegram]
- [ ] If Telegram not connected → connect prompt
- [ ] In-app chat interface
- [ ] Quick prompt chips: "How did I do?", "What to eat?", "Am I ready?", "Analyse progress"
- [ ] Free: 30-day trial (15 msg/day) with counter
- [ ] PRO: Unlimited (`ai_coach_unlimited`)
- [ ] Reasoning tab toggle: [Quick] [Deep Analyse]
- [ ] Reasoning = PRO gate (`reasoning_tab`)
- [ ] Free users see Deep tab → tap → paywall
- [ ] PRO: photo/video upload for coaching
- [ ] Messages stored in Hive coachBox

## 5.5 Profile Screen
- [ ] Bio stats (age, height, weight badges)
- [ ] Goal card
- [ ] Edit profile form → save to Hive + Supabase
- [ ] Health sync (Google Fit / Samsung Health)
- [ ] REPORTS section:
  - [ ] Weekly report card (free: local, in-app)
  - [ ] PRO: AI-generated report + PDF download (`weekly_ai_report`)
  - [ ] Report history
- [ ] Subscription status + Upgrade button
- [ ] Settings rows
- [ ] Logout → clear Hive → sign out → route to auth

## Completion Criteria
- All 5 screens render with real data from Hive
- No hardcoded stats anywhere
- Dark theme, Switzer font, Electric Cyan accent
- PRO features gated via subscription.gate()
- Phase 1 always free
- Loading, error, empty states on all screens
