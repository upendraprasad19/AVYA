# CLAUDE.md — ICANBEFITTER Master Reference
> Single source of truth for all coding agents. Read this before touching any file.

---

## 1. PROJECT IDENTITY

**App:** ICANBEFITTER — personalised fitness & nutrition platform for young professionals (22-35) in India.
**Model:** Freemium. ₹349/month or ₹2,999/year for PRO.
**Architecture:** Offline-first. Hive = primary. Supabase = backup + AI + community growth.

---

## 2. TECH STACK

| Layer | Technology |
|---|---|
| Frontend | Flutter (Android + Web → iOS later) |
| State Management | Riverpod (with code generation) |
| Local Storage | Hive (offline-first, primary for all reads/writes) |
| Auth | Supabase Auth (Email + Google OAuth + Phone OTP) |
| Database | Supabase Postgres (21 tables — backup + AI + community) |
| Storage | Supabase Storage (exercise images, progress photos PRO) |
| AI Coach Free | Edge Function → Cerebras Llama 3.1 8B free tier (30-day trial, 15 msg/day) |
| AI Coach PRO | Cerebras gpt-oss-120B (direct via Edge Function, ~₹1.80/user/month) |
| AI Reasoning PRO | GLM-4.7 on Cerebras |
| Food AI | Gemini Flash (PRO only) |
| Plan Generator | Dart (local, queries Hive exercise_library, zero API cost) |
| Payments | Razorpay (WebView checkout → webhook → Supabase → poll → Hive) |
| Telegram Bot | Separate project (OpenClaw VPS, @ICanbeFitterBot) — NOT in this repo |
| Health | Google Fit / Health Connect / Samsung Health |

---

## 3. SCREENS (5 Tabs)

| Tab | Screen | Key Features |
|-----|--------|-------------|
| 🏠 Home | Dashboard | Streak, weekly calendar, quick actions, today's workout, nutrition snapshot, weight sparkline, PR snapshot |
| 🏋️ Train | Workouts | Phase plan, week selector, active workout mode, exercise swap, template builder, copy week |
| 🥗 Nutrition | Food Logging | BMR/TDEE, food search (5K DB), AI analysis (PRO), saved meals, water tracking, diet plan generator |
| 💬 AI Coach | Chat | In-app chat, Telegram toggle, quick prompt chips, reasoning tab (PRO), photo/video upload (PRO) |
| 👤 Profile | Settings | Bio stats, goal card, edit profile, health sync, reports, subscription, logout |

---

## 4. DATA ARCHITECTURE (OFFLINE-FIRST)

```
┌─────────────────────────────────────────────────────┐
│                    FLUTTER APP                       │
│                                                      │
│  ALL reads/writes → Hive (LOCAL-FIRST)               │
│  Zero latency. Works fully offline.                  │
│                                                      │
│  SEED DATA (bundled JSON in APK):                    │
│    assets/data/exercise_library.json (200+ exercises)│
│    assets/data/food_database.json (5,000 foods)      │
│    → Parsed into Hive on first launch                │
│                                                      │
│  SYNC TO SUPABASE:                                   │
│    Immediately: custom foods/exercises (community)    │
│    Daily (11PM IST): user_daily_snapshot for AI      │
│    Weekly (on app launch if >7d): full sync all logs │
│                                                      │
│  RESTORE (new device):                               │
│    Login → pull from Supabase → populate Hive        │
│    FREE: last 30 days | PRO: last 90 days            │
│                                                      │
│  SUPABASE ROLE (NOT primary DB):                     │
│    • Auth (Supabase Auth)                            │
│    • Backup + cross-device restore                   │
│    • AI training corpus (snapshots, conversations)   │
│    • Community DB growth (custom foods/exercises)     │
│    • Subscription verification                       │
└─────────────────────────────────────────────────────┘
```

### Hive Boxes
| Box | Contents |
|-----|----------|
| `userBox` | user profile, preferences, progress |
| `workoutBox` | workout_logs, scheduled_workouts, templates |
| `nutritionBox` | nutrition_logs, saved_meals |
| `healthBox` | weight_logs, measurements, streaks, sleep_logs |
| `exerciseBox` | exercise_library (seeded from bundled JSON) |
| `foodBox` | food_database (seeded from bundled JSON) |
| `customBox` | user_custom_exercises, user_custom_foods |
| `coachBox` | ai_coach_interactions, coaching_notes |
| `syncBox` | last_sync_timestamps, pending_sync_queue |
| `configBox` | subscription status, feature flags, app config |

---

## 5. DIRECTORY STRUCTURE

```
lib/
  main.dart
  app.dart                              # MaterialApp + theme + GoRouter
  core/
    theme/
      app_theme.dart                    # Dark ThemeData with all tokens
      colors.dart                       # AppColors static class
      typography.dart                   # AppTypography text styles
      spacing.dart                      # AppSpacing + AppRadius constants
    router/
      app_router.dart                   # GoRouter config + auth redirect
    constants/
      app_constants.dart                # API URLs, feature keys, limits
    services/
      supabase_service.dart             # Supabase client singleton
      ai_service.dart                   # OpenRouter fallback chain
      subscription_service.dart         # isPro(), gate(), openUpgrade()
      sync_service.dart                 # Daily snapshot, weekly full sync
      hive_service.dart                 # Box init, adapter registration
      seed_service.dart                 # First-launch: parse bundled JSON → Hive
    utils/
      bmr_calculator.dart               # Mifflin-St Jeor formula
      date_utils.dart
  features/
    auth/
      screens/sign_in_screen.dart
      providers/auth_provider.dart
    onboarding/
      screens/onboarding_chat_screen.dart
      providers/onboarding_provider.dart
    home/
      screens/home_screen.dart
      widgets/
      providers/home_provider.dart
    train/
      screens/train_screen.dart
      screens/active_workout_screen.dart
      screens/template_builder_screen.dart
      widgets/
      providers/train_provider.dart
      repositories/workout_repository.dart
      models/
    nutrition/
      screens/nutrition_screen.dart
      screens/diet_plan_screen.dart
      widgets/
      providers/nutrition_provider.dart
      repositories/nutrition_repository.dart
    ai_coach/
      screens/ai_coach_screen.dart
      widgets/
      providers/ai_coach_provider.dart
      repositories/ai_coach_repository.dart
    profile/
      screens/profile_screen.dart
      screens/edit_profile_screen.dart
      screens/reports_screen.dart
      widgets/
      providers/profile_provider.dart
  shared/
    widgets/
      paywall_sheet.dart                # Single reusable paywall UI
      pro_badge.dart                    # Champion Gold badge
      loading_skeleton.dart
      hydration_color_card.dart
    repositories/
      user_repository.dart
      exercise_repository.dart
      food_repository.dart
      plan_generator.dart               # Dart, local, queries Hive exerciseBox

assets/
  data/
    exercise_library.json               # 200+ exercises, bundled in APK
    food_database.json                  # 5,000 Indian-first foods, bundled in APK
  fonts/
    # DM Sans font loaded via google_fonts package (runtime download)

supabase/
  migrations/                           # SQL migration files
  functions/                            # Edge Functions (TypeScript)
    ai-proxy/index.ts                   # Free: 3-tier fallback. PRO: direct Cerebras 120B
    razorpay-webhook/index.ts           # HMAC verify → write subscriptions
    daily-snapshot/index.ts             # Nightly cron
    weekly-recalc/index.ts              # Experience level recalculation
```

---

## 6. CODING RULES (NON-NEGOTIABLE)

1. **Hive-first for ALL reads/writes.** Never block UI on Supabase response. Supabase writes are background/async.
2. **Riverpod only** for state management. No `setState` for shared state. Use `@riverpod` annotation + code generation.
3. **Hive boxes:** Register ALL adapters in `main.dart`. Open ALL boxes before `runApp()`.
4. **Repository pattern** for all data access. Never call Supabase or Hive directly from widgets.
5. **subscription.gate()** for ALL PRO features. Never use inline `isPro` checks in widgets.
6. **Phase 1 is ALWAYS free.** Never gate it, even if subscription check fails.
7. **PaywallSheet** is the ONLY paywall UI. Never create custom paywall modals.
8. **Plan generator = local Dart.** Queries Hive exerciseBox. Never calls any API.
9. **Never expose API keys client-side.** All AI calls go through Supabase Edge Functions.
10. **DM Sans font everywhere.** No system fonts. Use `GoogleFonts.getFont('DM Sans', ...)`.
11. **Electric Cyan #00D4FF** for all accent/CTA. Never use green (#00e5a0) — that's the old spec.
12. **Dark theme only.** Background hierarchy: `#07090e` (bg) > `#0e1219` (card) > `#161d28` (input).
13. **All screens must handle:** loading state (skeleton), error state (retry), empty state.
14. **Never modify `plan_generator.dart`** without explicit instruction.
15. **Import paths:** Use relative imports within features. Use `package:` imports for shared/ and core/.

---

## 7. DATABASE SCHEMA (21 Tables — Supabase Postgres)

### IDENTITY
```sql
users (id uuid PK, email text UNIQUE, phone text, full_name text,
  subscription_status text DEFAULT 'free', subscription_expires_at timestamptz,
  telegram_chat_id text, telegram_connected bool, ai_chat_started_at timestamptz,
  onboarding_completed bool, last_active_at timestamptz, created_at timestamptz)

user_profile (user_id uuid FK→users, date_of_birth date, gender text,
  height_cm numeric, current_weight_kg numeric, target_weight_kg numeric,
  primary_goal text, fitness_experience text, days_per_week int,
  equipment_access text, activity_level text, diet_preference text,
  injuries text, wake_up_time time, city text, bmr numeric, tdee numeric)

user_preferences (user_id uuid FK→users, motivational_style text,
  biggest_obstacle text, preferred_language text DEFAULT 'English',
  coaching_notes text)

user_progress (user_id uuid FK→users, current_phase int DEFAULT 1,
  current_week int DEFAULT 1, phase_started_at timestamptz,
  plan_generated_at timestamptz, total_workouts_done int DEFAULT 0,
  current_streak_weeks int DEFAULT 0, detected_experience_level text,
  experience_last_calculated timestamptz)
```

### FITNESS
```sql
exercise_library (id uuid PK, name text, name_aliases text[], category text,
  movement_pattern text, exercise_type text, primary_muscles text[],
  secondary_muscles text[], equipment_needed text[], logging_type text NOT NULL,
  difficulty_level text, suitable_for text[], instructions text,
  coaching_cues text[], common_mistakes text[], alternative_ids uuid[],
  regression_id uuid, progression_id uuid, default_sets int, default_reps text,
  default_rest_secs int, default_duration_secs int, source text,
  is_active bool, is_indian_context bool)

workout_templates (id uuid PK, user_id uuid FK, name text, description text,
  workout_type text, estimated_duration_mins int, source text,
  is_active bool, created_at timestamptz, last_used_at timestamptz)

template_exercises (id uuid PK, template_id uuid FK, exercise_id uuid FK,
  exercise_name text, order_index int, logging_type text,
  prescribed_sets int, prescribed_reps text, prescribed_weight text,
  prescribed_time_secs int, rest_seconds int, notes text)

scheduled_workouts (id uuid PK, user_id uuid FK, template_id uuid FK,
  scheduled_date date, week_number int, day_of_week int,
  status text DEFAULT 'planned', completed_at timestamptz)

workout_logs (id uuid PK, user_id uuid FK, scheduled_workout_id uuid FK,
  template_id uuid FK, exercise_id uuid FK, exercise_name text,
  logged_at timestamptz, date date, sets_completed int, reps_completed int,
  weight_kg numeric, duration_seconds int, distance_km numeric,
  rpe int, notes text, is_pr bool DEFAULT false)

user_custom_exercises (id uuid PK, user_id uuid FK, name text,
  logging_type text NOT NULL, category text, primary_muscles text[],
  equipment_needed text[], notes text, default_sets int, default_reps text,
  default_rest_secs int, default_duration_secs int,
  submitted_to_library bool, approved_for_library bool, times_used int)
```

### NUTRITION
```sql
food_database (id uuid PK, name text, category text, calories_per_100g numeric,
  protein_per_100g numeric, carbs_per_100g numeric, fat_per_100g numeric,
  fiber_per_100g numeric, standard_serving_desc text, standard_serving_g numeric,
  calories_std numeric, protein_std numeric, carbs_std numeric, fat_std numeric,
  common_additions text[], is_indian bool, source text)

nutrition_logs (id uuid PK, user_id uuid FK, date date,
  total_calories numeric, total_protein numeric, total_carbs numeric,
  total_fat numeric, meal_type text, created_at timestamptz)

nutrition_log_items (id uuid PK, log_id uuid FK, food_id uuid FK,
  food_name text, quantity_g numeric, calories numeric, protein numeric,
  carbs numeric, fat numeric)

user_saved_meals (id uuid PK, user_id uuid FK, name text,
  items jsonb, total_calories numeric, total_protein numeric,
  times_used int, created_at timestamptz)

user_custom_foods (id uuid PK, user_id uuid FK, name text,
  calories_per_100g numeric, protein_per_100g numeric,
  carbs_per_100g numeric, fat_per_100g numeric, fiber_per_100g numeric,
  standard_serving_desc text, standard_serving_g numeric,
  calories_std numeric, protein_std numeric, carbs_std numeric, fat_std numeric,
  times_logged int, submitted_to_db bool, approved bool, created_at timestamptz)
```

### HEALTH
```sql
weight_logs (id uuid PK, user_id uuid FK, date date, weight_kg numeric,
  notes text, created_at timestamptz)

body_measurements (id uuid PK, user_id uuid FK, date date,
  chest numeric, waist numeric, hips numeric, arms numeric,
  notes text, created_at timestamptz)

streaks (id uuid PK, user_id uuid FK, week_start date,
  workouts_planned int, workouts_completed int,
  is_streak_maintained bool, created_at timestamptz)

sleep_logs (id uuid PK, user_id uuid FK, date date,
  duration_hrs numeric, quality text, bed_time time,
  wake_time time, notes text, created_at timestamptz)
```

### AI & INTELLIGENCE
```sql
user_daily_snapshots (id uuid PK, user_id uuid FK, snapshot_date date,
  snapshot_json jsonb, created_at timestamptz)

ai_coach_interactions (id uuid PK, user_id uuid FK,
  snapshot_id uuid FK→user_daily_snapshots, channel text,
  user_message text, ai_response text, model_used text,
  tokens_used int, was_helpful bool, created_at timestamptz)
```

### MONETISATION
```sql
subscriptions (id uuid PK, user_id uuid FK, plan text,
  status text, start_date timestamptz, end_date timestamptz,
  razorpay_order_id text, razorpay_payment_id text,
  razorpay_signature text, created_at timestamptz)

food_corrections (id uuid PK, user_id uuid FK, food_id uuid FK,
  original_values jsonb, corrected_values jsonb, created_at timestamptz)

telegram_connections (id uuid PK, user_id uuid FK, phone text,
  chat_id text, connected_at timestamptz, is_active bool)
```

---

## 8. LOGGING TYPES (Drives Active Workout UI)

| logging_type | UI Shows |
|---|---|
| `weight_reps` | Weight (kg) + Reps + Sets |
| `bodyweight_reps` | Reps + Sets (no weight input) |
| `weighted_bodyweight` | Added Weight + Reps + Sets |
| `timed` | Sets + Duration (seconds) + rest timer |
| `cardio` | Duration (min) + Distance (km) |
| `distance` | Distance + load |

---

## 9. DESIGN SYSTEM

### Colors
```dart
class AppColors {
  static const bg          = Color(0xFF07090e);
  static const header      = Color(0xFF0a0f18);
  static const card        = Color(0xFF0e1219);
  static const input       = Color(0xFF161d28);
  static const border      = Color(0xFF1c2535);

  static const accent      = Color(0xFF00D4FF);  // Electric Cyan
  static const accentTint  = Color(0x1400D4FF);  // rgba(0,212,255,0.08)
  static const accentDark  = Color(0xFF00a8cc);

  static const proGold     = Color(0xFFF59E0B);  // Champion Gold
  static const proGoldTint = Color(0x1AF59E0B);

  static const textPrimary   = Color(0xFFeef2f7);
  static const textSecondary = Color(0xFF6b7a8d);
  static const textDisabled  = Color(0xFF2d3748);

  static const red    = Color(0xFFef4444);  // error, danger
  static const orange = Color(0xFFf97316);  // calories
  static const blue   = Color(0xFF38bdf8);  // water, cardio
  static const purple = Color(0xFFa855f7);  // sleep
  static const green  = Color(0xFF4ade80);  // success
}
```

### Typography (DM Sans via GoogleFonts)
```
Display XL    40px / w900 / tracking +1
Display L     32px / w900 / tracking +0.5
Display M     28px / w900
Title L       22px / w800
Title M       18px / w800
Title S       15px / w700
Body L        15px / w400
Body M        13px / w400
Body S        12px / w400
Label         10px / w700 / tracking +1.2
Micro          9px / w700 / tracking +0.5
```

### Spacing
```
Screen padding    18px
Card padding      16px
Section gap       14px
Grid gap           9px
Inline gap         8px
```

### Border Radius
```
Button (pill)    100px
Card L            22px
Card M            16px
Card S            14px
Row               12px
Badge            100px
```

### Component Patterns
```
PRIMARY BUTTON:   bg #00D4FF, text #000000 w900, radius 100, padding 14×28, shadow
SECONDARY BUTTON: bg rgba(0,212,255,0.08), border 1.5 rgba(0,212,255,0.3), text #00D4FF w800
CARD:             bg #0e1219, border 1 #1c2535, radius 16, padding 16
ACTIVE CARD:      border 1 rgba(0,212,255,0.2)
PRO LOCKED CARD:  blur(4), overlay rgba(7,9,14,0.85), gold lock, cyan CTA
STREAK BADGE:     bg rgba(0,212,255,0.08), text #00D4FF w900, border rgba(0,212,255,0.2)
PROGRESS BAR:     track #161d28, fill #00D4FF, height 6, radius 3
```

---

## 10. SUBSCRIPTION GATE PATTERN

### PRO Feature Keys
```
phases_2_to_12         → auto-generate new 4-week plan after Week 4
active_workout_mode    → active workout logging screen
ai_coach_unlimited     → unlimited AI messages (free = 15/day for 30 days)
reasoning_tab          → deep coaching tab (GLM-4.7 on Cerebras)
weekly_ai_report       → weekly nutrition report ongoing (free = first report only)
progress_photos        → full photo timeline
scan_meal_pro          → 3 scans/day (free = 3/month)
cart_auditor_pro       → 3 scans/day (free = 1/month)
ai_text_log_pro        → 10 text logs/day (free = 3/day)
voice_notes            → push-to-talk voice input to AI coach
morning_alert_pro      → AI-personalised morning message (free = generic push)
prediction_monthly     → fresh prediction card every month (free = once at onboarding)
adaptive_workouts      → AI workout adjustments from biometrics (Phase 2)
```

### Shareable Cards (ALL FREE — growth engine)
```
workout_receipt        → PNG after every completed workout
future_prediction      → AI forecast card (once free, monthly PRO)
beat_my_coach          → HIIT challenge card (1 per 2 weeks, all users)
```
All shareable cards include: ICANBEFITTER wordmark + QR code → www.icanbefitter.com
Packages: share_plus (native share sheet) + qr_flutter (client-side QR, zero server cost)

### Correct Usage (ALWAYS use this)
```dart
await subscriptionService.gate(
  'ai_food_analysis',
  onPro: () => analyseFood(),
  onFree: () => showPaywallSheet(context, feature: 'AI Food Analysis'),
);
```

### WRONG (never do this)
```dart
if (isPro) { analyseFood(); }  // ❌ NEVER
```

### isPro() Implementation
- Reads from Hive configBox: `{isPro: bool, expiresAt: DateTime, plan: String}`
- Checks local expiry date
- Refreshes from Supabase on app launch (if online)
- If expired and offline → downgrade to free immediately (no grace period)
- Downgrade = soft lock: keep all data, show paywall on PRO features, read-only on PRO content

---

## 11. AI ARCHITECTURE

### Free Users (30-day trial, 15 msg/day)
```
Client → Edge Function (ai-proxy)
  → Try Cerebras Llama 3.1 8B (free tier)
  → If fail → Groq Llama 4 (free tier)
  → If fail → Gemini 2.0 Flash Lite (pay-as-you-go)
  ← Response to client
Cost at 10K users: ~₹2,500/month
```

### PRO Users (unlimited)
```
Client → Edge Function (ai-proxy-pro)
  → Cerebras gpt-oss-120B (direct)
  ← Response to client
Cost per user/month: ~₹1.80
```

### Reasoning Tab (PRO)
- GLM-4.7 on Cerebras
- Full personalised coaching: photo/video upload, deep analysis
- Free users see it locked → PRO paywall

### coaching_notes
- Batch extraction daily (11PM IST with snapshot)
- Process that day's conversations → extract facts → append to Hive
- NOT per-message extraction (too expensive)

### Context Injection
- System prompt receives `user_daily_snapshot` JSON (~300 tokens)
- Contains: profile, this week's workouts, today's nutrition, weight, streak, PRs, detected experience, coaching_notes
- One Hive read. Complete context. Zero additional queries.

---

## 12. PLAN GENERATOR

**File:** `lib/shared/repositories/plan_generator.dart`
**Model:** Hybrid — fixed workout structure per combo, dynamic exercises from Hive.

### Inputs
- `goal`: build_muscle | lose_fat | general_fitness | strength
- `equipment`: bodyweight | home_dumbbells | basic_gym | full_gym
- `daysPerWeek`: 3 | 4 | 5 | 6

### Process
1. Select workout split structure (e.g., 4-day muscle = Push/Pull/Legs/Upper)
2. For each day, query Hive exerciseBox:
   ```
   WHERE category = target_category
   AND equipment_needed matches user equipment
   AND suitable_for includes user experience
   ORDER BY exercise_type = 'compound' DESC
   LIMIT 6
   ```
3. Build 4-week phase with progressive overload defaults
4. Output: phase object with weeks, days, exercises, sets, reps, rest

### Output Shape
```dart
Phase {
  int phase;           // 1-12
  String name;         // "Foundation"
  String focus;        // "Movement patterns & baseline strength"
  String weeks;        // "1-4"
  int dailyCalories;
  int proteinGrams;
  List<WorkoutDay> workouts;
}
```

**FREE:** Phase 1 only (4 weeks). **PRO:** Generate new phases 2-12.

---

## 13. HOME SCREEN LAYOUT (Priority Order)

```
1. Header (name + greeting + avatar + streak counter)
2. Weekly calendar strip (7 days, color-coded by completion)
3. Quick actions: Log Workout | Log Meal | Hydration | Sleep
4. Today's workout card → Start Workout
5. Nutrition snapshot (calories + protein vs target)
6. AI Coach insight
7. Weight sparkline (last 7 entries)
8. PR snapshot (bench, squat, deadlift)
9. Recent logged foods
10. Step counter (Health Connect)
```

---

## 14. BUSINESS RULES

### FREE Forever
- Phase 1 workout plan (4 weeks, auto-generated locally — workout + nutrition split)
- Workout template builder + copy week to week
- Food database logging (5,000 items, standard portions)
- Adjustable food portions
- AI food text analysis — 3 text logs/day
- Scan meal camera — 3 scans/month
- Cart Auditor (grocery screenshot) — 1 scan/month
- Weight + body measurements tracking
- Streak counter + water tracking
- Steps + sleep sync (Google Fit / Health Connect)
- AI Coach — 30 days free (15 msg/day, Cerebras Llama 3.1 8B)
- Telegram bot — 30 days free
- Morning alert — generic push notification
- Weekly nutrition report — first report free (after Week 1)
- Future Prediction card — one card post-onboarding
- Beat My Coach HIIT challenge — 1 per 2 weeks
- Diet plan PDF — preview + swap + download (generated from food DB, no AI)
- Exercise coaching cues, common mistakes, pro tips — all visible
- Workout Receipt PNG (shareable) — after every completed workout

### PRO — ₹349/month or ₹2,999/year
- Auto-generate new plans after Week 4 (phases 2-12)
- AI food text analysis — 10 text logs/day
- Scan meal camera — 3 scans/day (soft cap warning at 2/3)
- Cart Auditor — 3 scans/day (soft cap warning at 2/3)
- Weekly AI nutrition report + Telegram push (ongoing)
- Future Prediction card — fresh AI prediction every month
- Progress photos (full timeline)
- Unlimited AI coach (Cerebras gpt-oss-120B)
- Reasoning tab (deep personalised coaching — GLM-4.7 on Cerebras)
- Audio-First UI (voice notes to AI coach)
- Morning alert — AI-personalised message with yesterday's data
- Adaptive workout recommendations from biometric data (Phase 2)

### Phase Unlock Formula
```
canUnlock = completionRate >= 0.8 AND weeksElapsed >= 4
```

### Calorie Calculation
Mifflin-St Jeor BMR formula → adjusted by activity level = TDEE.

---

## 15. SYNC SCHEDULE

| When | What | Where |
|------|------|-------|
| Immediately | Custom foods/exercises added | → Supabase (community contribution) |
| Daily 11PM IST | user_daily_snapshot (AI context) + coaching_notes extraction | → Supabase |
| Weekly (app launch if >7d) | Full sync: all logs, progress, preferences | → Supabase |
| Periodically | Check for new approved community items | ← Supabase → Hive |
| On restore | Pull 30d (free) or 90d (PRO) of data | ← Supabase → Hive |

---

## 16. PAYMENT FLOW

```
User taps "Upgrade to PRO"
  → Opens Razorpay WebView checkout
  → User pays
  → Razorpay webhook → Edge Function (razorpay-webhook)
  → Verify HMAC-SHA256 signature (MANDATORY)
  → Write to Supabase subscriptions table
  → App polls Supabase for confirmation
  → Updates Hive configBox {isPro: true, expiresAt, plan}
  → PRO features unlock immediately
```

---

## 17. EXERCISE LIBRARY

200+ exercises seeded in bundled JSON. Categories:
- Push (~35), Pull (~35), Legs (~40), Core (~25)
- Cardio (~20), Flexibility (~30), Calisthenics (~10)
- Indian Traditional (5): Dand, Baithak, Surya Namaskar, Malkhamb, Hindu Warrior Flow

Every exercise has: coaching_cues, common_mistakes, breathing_cue, warmup_protocol, pro_tip, MET_value, logging_type, difficulty, suitable_for, regression/progression links, image URLs.

---

## 18. FOOD DATABASE

5,000 Indian-first foods bundled in JSON. Categories:
- Staples (~500), Street food (~200), Restaurant dishes (~300)
- Packaged/branded (~500), Fruits & veg (~300), Dairy (~200)
- Pulses (~200), Protein (~300), Supplements (~100)
- Global (~400), Beverages (~200), Nuts & seeds (~200)

Community growth: User adds custom food → Hive + Supabase. Admin approves → promoted to global DB. Other users get it via periodic sync + app updates.

---

## 19. AGENT TEAM

See `.claude/agents/` for full definitions:
- `manager-agent.md` — Autonomous orchestrator. Reads BUILD_ORDER, spawns agents, runs QA, advances phases.
- `database-agent.md` — Supabase migrations, RLS, seed data.
- `backend-agent.md` — Edge Functions (AI proxy, Razorpay, crons).
- `screen-agent.md` — Build any of the 5 screens (parameterized).
- `auth-agent.md` — Supabase Auth + onboarding flow.
- `qa-agent.md` — Read-only reviewer against this CLAUDE.md.

---

## 20. COMMON BUGS TO AVOID

| Bug | How to Avoid |
|---|---|
| Hive box not open | Open ALL boxes in main.dart before runApp() |
| Adapter not registered | Register ALL Hive adapters before openBox() |
| Null exercise data | Always null-check: `exercise?.name ?? 'Unknown'` |
| Plan crash on empty | Guard: `plan?.workouts?.isNotEmpty == true` |
| Wrong import path | Use relative within features, package: for shared/core |
| Accent color wrong | #00D4FF (Electric Cyan), NEVER #00e5a0 (old green) |
| isPro inline check | ALWAYS use subscription.gate() |
| API key in client | ALL AI calls through Edge Functions |
| Water not resetting | Check date on app launch, reset if new day |
| Font fallback | Always use GoogleFonts.getFont('DM Sans', ...), never default font |
