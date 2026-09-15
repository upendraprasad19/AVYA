# Phase 4: Core Services (Repositories, Providers, Services)

## Agent: general
## Deps: Phase 1 (Database tables must exist)

## Tasks

### 4.1 Hive Service
- [ ] `lib/core/services/hive_service.dart`
- [ ] Register ALL Hive adapters
- [ ] Open ALL 10 boxes (userBox, workoutBox, nutritionBox, healthBox, exerciseBox, foodBox, customBox, coachBox, syncBox, configBox)
- [ ] Called in main.dart before runApp()

### 4.2 Seed Service
- [ ] `lib/core/services/seed_service.dart`
- [ ] Parse `assets/data/exercise_library.json` → Hive exerciseBox
- [ ] Parse `assets/data/food_database.json` → Hive foodBox
- [ ] Check configBox for `seeded` flag to avoid re-seeding
- [ ] Run on first launch only

### 4.3 Supabase Service
- [ ] `lib/core/services/supabase_service.dart`
- [ ] Supabase client singleton
- [ ] Initialize in main.dart with URL + anon key from env

### 4.4 Subscription Service
- [ ] `lib/core/services/subscription_service.dart`
- [ ] `isPro()` — read from Hive configBox, check expiry
- [ ] `gate(feature, onPro, onFree)` — clean gate wrapper
- [ ] `refreshFromSupabase()` — poll subscription status on app launch
- [ ] Cache: {isPro, expiresAt, plan} in Hive configBox

### 4.5 Sync Service
- [ ] `lib/core/services/sync_service.dart`
- [ ] `compileDailySnapshot()` — build JSON blob from Hive data
- [ ] `pushSnapshot()` — send to Supabase user_daily_snapshots
- [ ] `weeklyFullSync()` — push all logs to Supabase
- [ ] `checkAndSync()` — called on app launch, check last_weekly_sync
- [ ] Pending sync queue in syncBox

### 4.6 AI Service
- [ ] `lib/core/services/ai_service.dart`
- [ ] `chat(message, context)` — call Edge Function ai-proxy
- [ ] `chatPro(message, context)` — call Edge Function ai-proxy-pro
- [ ] Handle errors gracefully

### 4.7 Shared Repositories
- [ ] `lib/shared/repositories/user_repository.dart` — user CRUD via Hive
- [ ] `lib/shared/repositories/exercise_repository.dart` — query exerciseBox
- [ ] `lib/shared/repositories/food_repository.dart` — query foodBox
- [ ] `lib/shared/repositories/plan_generator.dart` — Dart, local, queries exerciseBox

### 4.8 Shared Widgets
- [ ] `lib/shared/widgets/paywall_sheet.dart` — reusable paywall bottom sheet
- [ ] `lib/shared/widgets/pro_badge.dart` — Champion Gold badge
- [ ] `lib/shared/widgets/loading_skeleton.dart` — skeleton shimmer
- [ ] `lib/shared/widgets/hydration_color_card.dart` — urine color scale

### 4.9 BMR Calculator
- [ ] `lib/core/utils/bmr_calculator.dart` — Mifflin-St Jeor formula
- [ ] Input: gender, weight, height, age, activity_level → Output: BMR, TDEE

## Completion Criteria
- All services initialize without error
- Hive boxes open before runApp
- Seed service populates exerciseBox and foodBox from bundled JSON
- subscription.gate() works with Hive cache
- Plan generator outputs valid 4-week phase from exerciseBox data

## Logic Reference
- `Knowledgebase/brainstorm data _PROJECT/services/` — all patterns (rewrite in Dart)
