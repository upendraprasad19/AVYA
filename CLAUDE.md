# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

# ICANBEFITTER Master Reference
> Single source of truth for all coding agents. Read this before touching any file.

---

## 0. DEVELOPMENT COMMANDS

### Environment Setup
Copy `.env.example` → `.env` and fill in Supabase URL, anon key, and Razorpay key ID.
Environment variables are injected **at build time** via `--dart-define-from-file=.env` (NOT flutter_dotenv — the package was removed). Every `flutter run` / `flutter build` command **MUST** include this flag or the app will crash with "No host specified in URI".

```
SUPABASE_URL=https://dedsavbjuwgarrhphgnl.supabase.co
SUPABASE_ANON_KEY=<anon key>
RAZORPAY_KEY_ID=rzp_test_<key>   # use rzp_test_ for dev flavor
```

### Run / Build (two flavors: `dev` and `prod`)
> ⚠️ **CRITICAL**: Every command below includes `--dart-define-from-file=.env`. Without it, SUPABASE_URL compiles to an empty string and auth will crash.

```bash
# Run dev flavor on connected device
flutter run --dart-define-from-file=.env --flavor dev -t lib/main.dart

# Run prod flavor
flutter run --dart-define-from-file=.env --flavor prod -t lib/main.dart

# Release APK (prod)
flutter build apk --dart-define-from-file=.env --flavor prod --release -t lib/main.dart

# Release App Bundle (Play Store)
flutter build appbundle --dart-define-from-file=.env --flavor prod --release -t lib/main.dart

# Web (no flavor needed)
flutter run --dart-define-from-file=.env -d chrome
flutter build web --dart-define-from-file=.env
```

### Tests
```bash
# All unit tests (no device required)
flutter test

# Single test file
flutter test test/bmr_calculator_test.dart

# All integration tests (requires connected Android device + .env)
flutter test --dart-define-from-file=.env integration_test/app_test.dart --flavor dev

# Single integration flow
flutter test --dart-define-from-file=.env integration_test/flows/workout_log_flow_test.dart --flavor dev
```

Unit tests live in `test/`. Integration tests (require Hive + real device) live in `integration_test/flows/`.

### Lint & Analysis
```bash
flutter analyze
```

### Riverpod Code Generation
The project has `riverpod_generator` installed but providers are currently written manually using `flutter_riverpod` directly (no `.g.dart` files). If you add `@riverpod` annotations, run:
```bash
dart run build_runner build --delete-conflicting-outputs
dart run build_runner watch   # watch mode during development
```

### Edge Functions (Supabase MCP — preferred)
Use `mcp__ba7b5e8e__deploy_edge_function` to deploy. Do not use `supabase` CLI — it is logged into the wrong account (personal, not fitness app account). See §2a for account details.

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
| AI Coach Free | Edge Function → OpenRouter Gemma 4 27B cascade (text+image, 30-day trial, 15 msg/day) |
| AI Coach PRO | Cerebras gpt-oss-120B (direct via Edge Function, ~₹1.80/user/month) |
| AI Reasoning PRO | GLM-4.7 on Cerebras |
| Food AI | OpenRouter Gemma 4 cascade (free) → Gemini 2.5 Flash Lite (fallback) |
| Plan Generator | Dart (local, queries Hive exercise_library, zero API cost) |
| Payments | Razorpay (WebView checkout → webhook → Supabase → poll → Hive) |
| Telegram Bot | Separate project (OpenClaw VPS, @ICanbeFitterBot) — NOT in this repo |
| Health | Google Fit / Health Connect / Samsung Health |

---

## 2a. SUPABASE PROJECT — CONFIRMED IDENTITY

> ⚠️ CRITICAL: There are TWO Supabase projects on this account. ALWAYS use the one below. NEVER guess.

| Field | Value |
|---|---|
| **Project ID** | `dedsavbjuwgarrhphgnl` |
| **Project name** | myfitnessjourney1988@gmail.com's Project |
| **Region** | ap-southeast-1 |
| **DB host** | `db.dedsavbjuwgarrhphgnl.supabase.co` |
| **Confirmed by** | Querying actual tables — `users`, `exercise_library`, `food_database`, `workout_logs`, `ai_coach_interactions`, `subscriptions` etc. all present |

**The OTHER project** (`krcrkntuwutvnmdnkfqf`, named "icanbefitter") is a **different app entirely** (blog/content platform — `posts`, `members`, `media` tables). Never touch it.

**Rule: Before ANY Supabase operation, confirm project_id = `dedsavbjuwgarrhphgnl`.**

### Supabase Access — TWO SEPARATE ACCOUNTS

The user has **two Supabase accounts** with different logins. These are NOT the same account.

| Account | Org ID | Org Name | Projects | Access via |
|---|---|---|---|---|
| **myfitnessjourney1988@gmail.com** | `hwwukmntixflgbxkwavm` | (default) | `dedsavbjuwgarrhphgnl` ✅ FITNESS APP, `krcrkntuwutvnmdnkfqf` (blog) | **MCP only** (auto-authenticated) |
| **Upendra's personal account** | `dsvxqvpitnpumftnsnwe` | ICANBEFITTER Supabase | `tjjmtscmwzvlzpbvgtbv` (Upendra-Prasad's Project), `zvwepplqqflhgubwalee` (ICANBEFITTER AI V1) | **CLI only** (`supabase login`) |

⚠️ The Supabase CLI (`supabase` command) is logged into the **personal account**, NOT the fitness app account. CLI commands like `supabase secrets set` will NOT work against the fitness app project unless re-authenticated.

**For Edge Function secrets / admin operations:** Use MCP tools (auto-authenticated to the correct account) or the Supabase Dashboard logged in as `myfitnessjourney1988@gmail.com`.

### Credentials (Edge Function Secrets)

| Secret Key | Value | Status |
|---|---|---|
| `ONESIGNAL_APP_ID` | `fd37a411-121e-4022-9929-2af68c2371f5` | ✅ Set |
| `ONESIGNAL_REST_API_KEY` | *(set in dashboard, not committed to code)* | ✅ Set |
| `GEMINI_API_KEY` | *(set in dashboard, not committed to code)* | ✅ Set |
| `CEREBRAS_API_KEY_1` | *(already set)* | ✅ |
| `CEREBRAS_API_KEY_2` | *(already set)* | ✅ |
| `CEREBRAS_API_KEY_3` | *(already set)* | ✅ |
| `RAZORPAY_KEY_SECRET` | *(already set)* | ✅ |

### Firebase / OneSignal

| Field | Value |
|---|---|
| Firebase project | AVYA |
| Firebase Sender ID | `194342788570` |
| OneSignal App ID | `fd37a411-121e-4022-9929-2af68c2371f5` |
| `google-services.json` | ✅ In `android/app/google-services.json` |
| Google Services Gradle plugin | ✅ Configured in `settings.gradle.kts` + `app/build.gradle.kts` |

---

## 3. SCREENS (5 Tabs)

| Tab | Screen | Key Features |
|-----|--------|-------------|
| 🏠 Home | Dashboard | Streak, weekly calendar, quick actions, today's workout, nutrition snapshot, weight sparkline, PR snapshot |
| 🏋️ Train | Workouts | Phase plan, week selector, active workout mode, exercise swap, template builder, copy week |
| 🥗 Nutrition | Food Logging | BMR/TDEE, 2-tab Log Food (AI + Scan), food search (5K DB), AI analysis (PRO), saved meals, water tracking, diet plan generator + PDF export |
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
│    Every app launch: pushSnapshot() (AI context)     │
│    Daily (app launch if >1d): full sync all logs     │
│                                                      │
│  RESTORE (new device):                               │
│    Login → pull from Supabase → populate Hive        │
│    ALL users: full history (storage per user ~1-2MB)  │
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
| `workoutBox` | workout_logs, scheduled_workouts, templates, exercise_logs |
| `nutritionBox` | nutrition_logs, saved_meals |
| `healthBox` | weight_logs, measurements, streaks, sleep_logs |
| `exerciseBox` | exercise_library (seeded from bundled JSON) |
| `foodBox` | food_database (seeded from bundled JSON) |
| `customBox` | user_custom_exercises, user_custom_foods |
| `coachBox` | ai_coach_interactions, coaching_notes |
| `syncBox` | last_sync_timestamps, pending_sync_queue |
| `configBox` | subscription status, feature flags, app config |

#### workoutBox Key Patterns
| Key Pattern | Value |
|-------------|-------|
| `schedule_YYYY-MM-DD` | Schedule entry (type, status, workout_name, exercises, week) |
| `exercise_log_index_YYYY-MM-DD` | List of exercise log IDs for that date |
| `exlog_<timestamp>_<hash>` | Exercise log: exercise_name, logging_type, weight_kg, reps_completed, sets_completed, volume_kg, is_pr |
| `wlog_<timestamp>` | Workout log: workout_name, date, duration_seconds, sets_completed |
| `template_<id>` | Workout template with exercises |

---

## 5. DIRECTORY STRUCTURE

> Full annotated tree → `docs/reference/directory-structure.md`. Quick orientation only here.

```
lib/
  core/{theme, router, constants, services, utils}/   # singletons, GoRouter, theme tokens, BMR
  features/{auth, onboarding, home, train, nutrition, ai_coach, profile}/
    each: screens/, widgets/, providers/, repositories/, models/
  shared/
    widgets/    paywall_sheet, pro_badge, streak_warning_banner, loading_skeleton
    repositories/  user, exercise, food, plan_generator (NEVER modify without approval)

assets/data/{exercise_library, food_database}.json    # bundled, seeded into Hive on first launch
supabase/{migrations, functions}/                     # SQL + Edge Functions (TS)
```

**Single-source-of-truth files (don't fork these):**
- `lib/features/train/widgets/workout_receipt_card.dart` — `WorkoutReceiptData.fromExerciseLogs()` (the only receipt builder)
- `lib/features/train/widgets/edit_workout_log_sheet.dart` — the only completed-workout edit surface (4 entry points route through it)
- `lib/core/services/day_rollover_service.dart` — `runRolloverNow()` (canonical "today" provider invalidation list)
- `lib/core/services/subscription_service.dart` — `isPro()` + `gate()` (never read `configBox.get('isPro')` directly)
- `lib/core/services/ai_service.dart` — `_compactContext()` (the only snapshot trimmer)
- `lib/shared/repositories/plan_generator.dart` — workout plan generation (CLAUDE rule #14: untouchable without explicit approval)

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
16. **Edge Function SSRF:** Never fetch arbitrary user-supplied URLs server-side. Allowlist Supabase Storage prefix only.
17. **Release error handling:** Use `kDebugMode` guard — show detailed errors only in debug, generic message in release.
18. **Edge Function input limits:** Enforce message (5K chars) and snapshot (10K chars) limits server-side on ALL AI endpoints.
19. **Server-side subscription verification:** High-value features (`phases_2_to_12`, `ai_coach_unlimited`, `reasoning_tab`) must call `verifyFromServer()` in `gate()`. Local-only check is insufficient.

---

## 7. DATABASE SCHEMA (21 Tables — Supabase Postgres)

> Full DDL → `docs/reference/database-schema.md`. Authoritative source of truth: `supabase/migrations/`.

| Domain | Tables |
|---|---|
| Identity (4) | `users`, `user_profile`, `user_preferences`, `user_progress` |
| Fitness (6) | `exercise_library`, `workout_templates`, `template_exercises`, `scheduled_workouts`, `workout_logs`, `user_custom_exercises` |
| Nutrition (5) | `food_database`, `nutrition_logs`, `nutrition_log_items`, `user_saved_meals`, `user_custom_foods` |
| Health (5) | `weight_logs`, `body_measurements`, `streaks`, `water_logs`, `sleep_logs` |
| AI (2) | `user_daily_snapshots`, `ai_coach_interactions` |
| Monetisation (5) | `subscriptions`, `promo_codes`, `promo_code_uses`, `food_corrections`, `telegram_connections` |

**Critical UNIQUE constraints (required for safe re-sync dedup — never remove):**
- `streaks(user_id, week_start)` — prevents duplicate weeks on restore
- `water_logs(user_id, date)` — one row per user per day
- `scheduled_workouts(user_id, scheduled_date)` — one schedule per user per date

**Cloud `workout_log_exercises`** — per-exercise summary table written by the Flutter app. Key semantics: `set_number` = total completed sets (NOT "which set"); `weight_kg` = best across sets; `exercise_id` = exercise_name (stable identity for cross-week grouping). See §11 "Exercise Log Cloud Contract".

**RPC:** `increment_promo_used_count(p_code text)` — atomically increments `promo_codes.used_count`. Called from `razorpay-webhook` after subscription insert (only when `alreadyProcessed === false`).

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

### Spacing & Radius (constants live in `lib/core/theme/spacing.dart`)
```
Spacing:   screen 18 / card 16 / section 14 / grid 9 / inline 8
Radius:    pill 100 / card-L 22 / card-M 16 / card-S 14 / row 12
```

### Component Patterns
- **Primary button:** `accent` bg, black w900 text, pill radius, shadow
- **Secondary button:** `accentTint` bg, 1.5 `accent`-30% border, `accent` w800 text
- **Card:** `card` bg, 1 `border` border, radius-M, padding 16. Active variant uses `accent`-20% border.
- **PRO locked card:** blur(4) + `bg`-85% overlay, gold lock, cyan CTA
- **Streak badge:** `accentTint` bg, `accent` w900 text, `accent`-20% border
- **Progress bar:** `input` track, `accent` fill, height 6, radius 3

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
workout_receipt        → PNG after every completed workout + viewable later via "View Card"
future_prediction      → AI forecast card (once free, monthly PRO)
beat_my_coach          → HIIT challenge card (1 per 2 weeks, all users)
video_share            → Remotion/Lambda video render (DEFERRED — hidden until post-launch)
```
All shareable cards include: ICANBEFITTER wordmark + QR code → www.icanbefitter.com
Packages: share_plus (native share sheet) + qr_flutter (client-side QR, zero server cost)

**Workout Receipt — View Past Cards:**
- Receipt data reconstructed on-the-fly from Hive exercise logs (`exercise_log_index_YYYY-MM-DD`)
- `WorkoutReceiptData.fromExerciseLogs(date)` — static factory, returns null if no logs
- `WorkoutReceiptSheet` — reusable bottom sheet (`lib/features/train/widgets/workout_receipt_sheet.dart`)
- Access points: Home screen completed card "View Card" button, Calendar day detail "View Workout Card" button
- Exercise logs store `volume_kg` field for exact volume reconstruction (falls back to `weight_kg × reps` for old logs)

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
- **kDebugMode guard:** If `expiresAt` is null, returns `true` only in debug mode (`kDebugMode`). In release builds, null expiry = free. Prevents rooted-device Hive tampering from granting PRO.
- Refreshes from Supabase on app launch (if online)
- If expired and offline → downgrade to free immediately (no grace period)
- Downgrade = soft lock: keep all data, show paywall on PRO features, read-only on PRO content
- **Phantom PRO fix:** `localActivationAt` is force-cleared after grace period expires on network error. Prevents stale local timestamp from keeping users in PRO after subscription lapses.
- **JWT refresh:** `razorpay_service` refreshes JWT before each verify-payment retry to prevent 401 errors during polling.
- **Server-side verification:** `gate()` calls `verifyFromServer()` (5-min cache TTL) for high-value features (`phases_2_to_12`, `ai_coach_unlimited`, `reasoning_tab`, `progress_photos`). Other features use local check only for low latency.

### gate() High-Value Features
```dart
static const Set<String> _highValueFeatures = {
  AppConstants.featurePhases2To12,
  AppConstants.featureAiCoachUnlimited,
  AppConstants.featureReasoningTab,
  AppConstants.featureProgressPhotos,  // photo writes to user-scoped Storage bucket
};
// gate() checks server for these features, local-only for others
```

**Why `progress_photos` is high-value:** It triggers Supabase Storage writes to a user-scoped bucket. Granting access via a spoofed local `isPro` flag would let a free user on a rooted device persist private photos onto infrastructure we pay for. Any feature that writes to Storage or spends cloud compute/storage on behalf of the user MUST be server-verified.

---

## 11. AI ARCHITECTURE

### Free Users (30-day trial, 15 msg/day)
```
Client → Edge Function (ai-proxy)
  → Try OpenRouter Gemma 4 27B cascade (text + image):
      google/gemma-4-27b-it:free → gemma-4-31b-it:free → gemma-4-26b-a4b-it:free
  → If all fail → Cerebras Llama 3.1 8B (text-only fallback)
  ← Response to client
  JWT auto-retry: on 401/session error, refresh token + single inline retry
Cost at 10K users: ~₹0 (all free-tier models)
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

### Input Validation (all AI Edge Functions)
- **Message length:** Max 5,000 chars. Enforced server-side on `ai-proxy`, `ai-proxy-pro`, `ai-media-proxy`.
- **Snapshot size:** Max 10,000 chars (stringified JSON). Enforced on `ai-proxy`, `ai-proxy-pro`.
- **Image size:** Max 5MB. Enforced on `ai-media-proxy` via content-length + arrayBuffer check.
- **SSRF protection:** `ai-media-proxy` only fetches from `${SUPABASE_URL}/storage/v1/object/` prefix. All other URLs rejected.

### Client-Side Context Compaction (`AiService._compactContext`)
- **Target:** <9,500 bytes (buffer under 10KB server limit for JSON overhead).
- **Trim order** (least load-bearing first): `step_history_7d` → `weight_trend` → `nutrition_trend` → `exercise_history` → `personal_records` → `coach_notices` → truncate `coaching_notes` (1,500 char cap) → drop `fitness_summary`.
- Applied on EVERY AI call (`chat`, `chatPro`, `chatWithMedia`, `reason`, `predict`, both direct-HTTP fallbacks). Without this, historical queries that trigger `enrichContextForQuery` get rejected with a 400 from the server.

### Client-Side Error Extraction (`AiService._extractError`)
- Parses `{"error": "..."}` out of non-200 responses on all AI Edge Functions.
- Replaces generic "status X" with actionable messages at the provider level (`ai_coach_provider.dart`):
  - `Message too long` → "Your message is too long (max 5000 chars). Please shorten it and try again."
  - `Snapshot too large` → "Your coaching context is unusually large. Please try a shorter question."
  - `Image too large` → "That photo is too large (max 5 MB)."
  - `Only Supabase Storage URLs are allowed` → "Upload failed — please try picking the photo again."
  - `PRO subscription required` → "This feature requires PRO."
  - `502`/`503`/`504` → "The AI model is temporarily unavailable. Please try again in a minute."
- **Never use "restart the app" copy.** It doesn't fix any of these root causes.

### Edge Function Auth
- `ai-proxy`: `verify_jwt: false` (Supabase gateway bug). Manual JWT validation via `auth.getUser()`.
- `ai-proxy-pro`: `verify_jwt: false` (same bug). Manual JWT + subscription check.
- `ai-media-proxy`: `verify_jwt: true` + manual JWT + PRO subscription check.
- `validate-promo`: `verify_jwt: true` + manual JWT validation (prevents unauthenticated promo enumeration).
- `future-prediction`: `verify_jwt: true` + manual JWT validation.

### Vision Features (ai-proxy — OpenRouter Gemma 4 + Gemini 2.5 Flash Lite)
- `food_text_analysis`: Text → nutrition JSON. **Rate limited: 50/day free, 200/day PRO** (server-side abuse cap; client has no hard limit — server is source of truth). Counted via `ai_coach_interactions` rows with `channel='food_text_analysis'`.
- `scan_meal`: Photo → nutrition JSON. Client: 3 free / 10 PRO per day. Server: 15/day abuse cap.
- `cart_auditor`: Grocery screenshot → health audit JSON (items, health_score, suggestions). Client: 1 free / 10 PRO per day. Server: 15/day abuse cap.
- Server-side rate limit: scan_meal + cart_auditor combined counted via `ai_coach_interactions` rows with `channel IN ('scan_meal', 'cart_auditor')`. Client-side limits handle exact free/PRO tiers.

### Edge Function Error Sanitization (ALL functions)
- **Never leak raw exceptions, stack traces, or database error strings to the client.** Every Edge Function catch block follows this shape:
  ```ts
  } catch (err) {
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[function-name] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
  ```
- Short request IDs (8 hex chars) are logged server-side AND returned to the client so support can grep logs for the exact failure. The client sees a generic message; the logs retain full detail.
- **Validation errors** (400 responses like "Message too long", "Image too large", "PRO subscription required") ARE safe to return verbatim — they're user-actionable and don't leak internals.
- Applies to all 19 Edge Functions: `ai-proxy`, `ai-proxy-pro`, `ai-media-proxy`, `razorpay-webhook`, `verify-payment`, `verify-subscription`, `validate-promo`, `assess-body-composition`, `beat-my-coach`, `daily-snapshot`, `expiry-reminder`, `future-prediction`, `morning-alert`, `redeem-referral`, `rolling-context`, `streak-guardian`, `weekly-recalc`, `weekly-recap-ready`, `weekly-report`.

### Server-Side Workout Analytics
- `weekly-recalc`: Reads exercise-level data from `workout_log_exercises` (NOT `workout_logs`). Derives date from `completed_at`. Groups exercises by `exercise_id` (= exercise_name) for weight progression tracking. `total_workouts_done` counts distinct dates, not exercise rows.
- `weekly-report`: Two-query approach — exercise data from `workout_log_exercises`, workout metadata (duration, RPE) from `workout_logs`. `sets_completed` reads actual `set_number` from per-exercise summary (not hardcoded 1). RPE guarded against zero-denominator (returns "N/A" when no RPE data).

### Exercise Log Cloud Contract (workout_log_exercises)
Each row is a **per-exercise summary** (NOT per-set), matching the Hive exlog_* shape:
- `exercise_id` = exercise_name (stable identity for cross-week grouping)
- `workout_log_id` = deterministic ID from date (groups all exercises in same workout)
- `set_number` = total completed sets for this exercise (NOT "which set number")
- `reps` = cumulative reps across all sets
- `weight_kg` = best (max) weight across sets
- RPE: NOT stored per exercise. Workout-level RPE column exists in `workout_logs` but is currently never written by the Flutter app (no UI for it).

### coaching_notes
- Batch extraction daily (11PM IST with snapshot)
- Process that day's conversations → extract facts → append to Hive
- NOT per-message extraction (too expensive)

### Context Injection
- System prompt receives `user_daily_snapshot` JSON (~300 tokens)
- Contains: profile (incl. city), this week's workouts, today's nutrition (incl. urine status), weight, streak, PRs, detected experience, coaching_notes
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
4. Today's workout card → Start Workout (or DONE + View Card + stats if completed)
5. Nutrition snapshot (calories + protein vs target)
6. AI Coach insight (computed from local schedule data — next workout, consistency tips)
7. Weight sparkline (last 7 entries)
8. PR snapshot (dynamic — top 4 exercises by volume when key lifts empty)
9. Recent logged foods
10. Step counter (Health Connect)
```

**Today's Workout Card — Completed State:**
- Shows: DONE badge (green) + "View Card >" (cyan) + best lift + total volume
- "View Card" opens `WorkoutReceiptSheet` with receipt reconstructed from Hive exercise logs
- Calendar day detail sheet also shows "View Workout Card" button for completed days

---

## 14. BUSINESS RULES

### FREE Forever
- Phase 1 workout plan (4 weeks, auto-generated locally — workout + nutrition split)
- Workout template builder + copy week to week
- Food database logging (5,000 items, standard portions)
- Adjustable food portions
- AI food text analysis — 10 text logs/day
- Scan meal camera — 3 scans/day
- Cart Auditor (grocery screenshot) — 1 scan/day
- Weight + body measurements tracking
- Streak counter + water tracking
- Steps + sleep sync (Google Fit / Health Connect)
- AI Coach — 30 days free (15 msg/day, OpenRouter Gemma 4 27B)
- Telegram bot — 30 days free
- Morning alert — generic push notification
- Weekly nutrition report — first report free (after Week 1)
- Future Prediction card — one card post-onboarding
- Beat My Coach HIIT challenge — 1 per 2 weeks
- Diet plan — preview + swap + save to device + share as PDF (generated from food DB, no AI). Saved plans loadable on re-entry.
- Exercise coaching cues, common mistakes, pro tips — all visible
- Workout Receipt PNG (shareable) — after every completed workout

### PRO — ₹349/month or ₹2,999/year
- Auto-generate new plans after Week 4 (phases 2-12)
- AI food text analysis — 10 text logs/day
- Scan meal camera — 10 scans/day (soft cap warning at 7/10)
- Cart Auditor — 10 scans/day (soft cap warning at 7/10)
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
Hybrid BMR: Katch-McArdle when body fat % available (`370 + 21.6 × lean_mass_kg`), Mifflin-St Jeor fallback. Both apply -50 BMR offset and -100 TDEE offset. Activity level derived from lifestyle + training days → TDEE.

---

## 15. SYNC SCHEDULE

| When | What | Where |
|------|------|-------|
| Immediately | Custom foods/exercises added | → Supabase (community contribution) |
| Immediately (fire-and-forget) | Every nutrition mutation (log meal, water, urine, edit/delete food, scan meal save, barcode save, custom exercise create) fires `SyncService.syncNutritionData()` + `pushSnapshot()` | → Supabase + AI snapshot |
| Immediately (fire-and-forget) | Every workout mutation (complete, edit log, template save/delete, schedule change) fires `SyncService.syncWorkoutData()` + `pushSnapshot()` | → Supabase + AI snapshot |
| Every app launch | user_daily_snapshot (AI context) via pushSnapshot() | → Supabase |
| Daily 11PM IST | coaching_notes extraction from that day's conversations | → Hive + Supabase |
| Daily (app launch if >1d) | Full sync: all logs, progress, preferences | → Supabase |
| Periodically | Check for new approved community items | ← Supabase → Hive |
| On restore | Pull full history (all users) | ← Supabase → Hive |

### Fire-and-Forget Sync Pattern
All mutation paths use `unawaited()` from `dart:async` to push changes without blocking UI:

```dart
import 'dart:async';
import 'package:icanbefitter/core/services/sync_service.dart';

// In any mutation (logFood, addWater, saveMeal, completeWorkout, etc.):
await hiveBox.put(key, value);            // 1. Hive-first (blocking)
ref.invalidate(dependentProvider);        // 2. Refresh UI (blocking)
unawaited(SyncService.instance.syncNutritionData());  // 3. Push to Supabase (background)
unawaited(SyncService.instance.pushSnapshot());       // 4. Refresh AI context (background)
```

**Never `await` the sync calls** — they must not block the UI. Failures are logged via `debugPrint` inside the service and silently ignored; the local Hive write is the source of truth. Use `syncWorkoutData()` for workout mutations and `syncNutritionData()` for nutrition mutations (parallels the workout method, syncs `nutrition_logs` + `water_logs` in one batch).

### Sync Deduplication Rules
- **Streaks:** `onConflict: 'user_id,week_start'` (UNIQUE constraint in DB). Restore dedupes by `week_start` — cloud row replaces local if conflict found. Never dedup by cloud `id` alone (causes same-week duplicates).
- **Workout logs/exercises:** Upserted by deterministic UUID (`_deterministicId(localKey)`). Safe for re-sync.
- **Water logs:** `onConflict: 'user_id,date'` (UNIQUE constraint added migration 013). One row per user per day.
- **Scheduled workouts:** `onConflict: 'user_id,scheduled_date'` (UNIQUE constraint added migration 013). One schedule per user per date.

### Restore Pagination
- All restore queries use paginated fetch (1,000 rows per page, offset-based).
- Safety ceiling: 50,000 rows per table to prevent runaway fetches.
- No hardcoded `.limit(5000)` — truly full-history restore for all users.

### Source of Truth Rules (NON-NEGOTIABLE)
> Multiple-source bugs are the #1 cause of "UI says X but data says Y" issues. Establish ONE reader per derived concept.

- **Workout receipt:** `WorkoutReceiptData.fromExerciseLogs(date)` (in `workout_receipt_card.dart`) is the ONLY way to build receipt data after the fact. Reads from Hive `exlog_*` keys via `WorkoutRepository.getExerciseLogsForDate()`. Deduplicates by exercise name (sum sets, max weight). Never hand-build receipt data from a widget's in-memory state.
- **Workout log edit:** `EditWorkoutLogSheet` (in `lib/features/train/widgets/edit_workout_log_sheet.dart`) is the ONLY edit surface. Every entry point (receipt sheet Edit button, Home "View Card", calendar day detail, Train expanded view) routes through it. Save:
  1. Rewrites the Hive log map in place
  2. Recomputes `volume_kg = weight_kg × reps_completed`
  3. Chronologically rescans `is_pr` flags for the exercise (sorts by `date + created_at`, walks forward, strict `>` comparison)
  4. Invalidates: `currentPlanProvider`, `workoutStatsProvider`, `calendarWeekProvider`, `streakProvider`, `todayWorkoutProvider`, `allExercisePRsProvider`
  5. Fires `SyncService.instance.syncWorkoutData() + pushSnapshot()` (fire-and-forget)
- **Exercise logs:** `WorkoutRepository.getExerciseLogsForDate()` is the ONLY read path. Uses O(1) index `exercise_log_index_YYYY-MM-DD` with legacy full-scan fallback. Never iterate `workoutBox.keys` manually to find logs for a date.
- **Home "View Card" state:** `todayWorkoutProvider` is the single source for the "DONE + View Card" state on home. Always derived from Hive schedule + exercise logs — never cached in the widget.
- **Scheduled workouts:** `WorkoutScheduleService` owns all schedule mutations (generate, clean-sync on template edit, reschedule on days/week change). Never write `schedule_YYYY-MM-DD` keys directly from a widget or repository.
- **Nutrition total calories:** After a meal is logged, `total_calories` comes from summing `items[]` with per-item Atwater fallback (`raw > 0 ? raw : 4P+4C+9F`). Never read `result['total_calories']` at the top level of an AI response — it's routinely missing.
- **AI snapshot:** `AiCoachRepository.buildAiContext()` is the ONE builder. `AiService._compactContext()` is the ONE trimmer. Never construct ad-hoc snapshots in provider code.
- **Subscription status:** `SubscriptionService.isPro()` + `gate()` are the ONLY entry points. Never read `configBox.get('isPro')` directly from a widget. High-value features (`phases_2_to_12`, `ai_coach_unlimited`, `reasoning_tab`) go through `verifyFromServer()`.
- **Provider invalidation after mutation:** Any write that changes workout state (log, edit, delete, complete) MUST invalidate the full batch: `currentPlanProvider`, `workoutStatsProvider`, `calendarWeekProvider`, `streakProvider`, `todayWorkoutProvider`, `allExercisePRsProvider`. One missing invalidation = stale UI.

---

## 16. PAYMENT FLOW

```
User taps "Upgrade to PRO"
  → Opens Razorpay WebView checkout (amount adjusted for promo if applied)
  → User pays
  → Razorpay webhook → Edge Function (razorpay-webhook)
  → Verify HMAC-SHA256 signature (MANDATORY)
  → Derive plan from payment amount (promo-aware)
  → Write to Supabase subscriptions table
  → Redeem promo code (increment used_count + audit trail)
  → App polls Supabase for confirmation (exact payment_id match)
  → Falls back to verify-payment Edge Function if webhook slow
  → Updates Hive configBox {isPro: true, expiresAt, plan}
  → PRO features unlock immediately
```

### Payment Security Rules (NON-NEGOTIABLE)
1. **Plan derived from amount, NEVER from client:** Both `razorpay-webhook` and `verify-payment` derive the plan (monthly/yearly) from `payment.amount` in paise. Client-supplied `body.plan` is ignored for entitlement. Prevents a ₹349 monthly payment from getting yearly (365-day) entitlement.
2. **Promo-aware amount validation (tolerant):** If `notes.promo_code` exists, Edge Functions look up the promo in `promo_codes` table and compute discounted expected amount from `discount_pct`. **Tolerant:** accepts the discounted amount even if the promo has since expired or exhausted — the promo was valid when checkout opened, and Razorpay capture can take minutes. Only rejects if the promo code doesn't exist at all or the discount math doesn't match. Logs a warning for race-condition cases.
3. **Promo redemption on success:** After subscription insert, `increment_promo_used_count` RPC atomically increments `used_count`. Audit row written to `promo_code_uses`. This is non-fatal — subscription is already created.
4. **Two-tier polling:** Client polls by exact `razorpay_payment_id` (attempts 0-11), then falls back to any active subscription created in last 5 minutes (attempts 12-14). Prevents upgrades (monthly→yearly) from resolving against the old stale row.
5. **Webhook idempotency:** `razorpay-webhook` handles replay attempts safely:
   - **Pre-SELECT** `subscriptions` table by `razorpay_payment_id` BEFORE the INSERT. If a row exists, return 200 immediately with `alreadyProcessed: true` and skip promo redemption.
   - **23505 race fallback:** If two webhook replays race past the pre-SELECT, the second INSERT hits the unique constraint on `razorpay_payment_id` → Postgres throws `23505`. The function catches this code specifically and returns 200 (treats as success).
   - **Promo redemption guard:** `increment_promo_used_count` RPC is ONLY called when `alreadyProcessed === false`. Prevents a replayed webhook from double-incrementing `used_count` and burning the promo for nobody.
   - Razorpay retries webhooks aggressively (up to 24h on non-200). Without idempotency, every retry would write a duplicate subscription row AND re-redeem the promo. Never remove the pre-SELECT or the 23505 catch.

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

## 19. COMMON BUGS TO AVOID

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
| Phantom PRO status | Force-clear localActivationAt after grace period on network error |
| Steps/sleep showing stale data | Filter health data by BOTH date AND type (`step_log`, `sleep_log`). Legacy `steps_today` guarded by `stepsToday == null && steps_date == todayStr`. Chat-logged sleep read from `sleep_logs` list as fallback. |
| AI insight from old chat | Compute insights from local schedule data, not last AI message |
| Stats grid empty | Fall back to top 4 exercises from allExercisePRs when key lifts (bench/squat/deadlift/OHP) have no data. Unit derived from loggingType (kg/reps/s/km). Adaptive layout: 1→full, 2→row, 3→2+1, 4→2+2. |
| Prediction card truncated | Home: maxLines 4 + "Read More →" opens full bottom sheet. Shareable: capped at 500 chars. |
| JWT expired during payment poll | Refresh JWT before each verify-payment retry |
| Onboarding sync fails silently | Retry sync with JWT refresh on failure |
| Daily snapshot not pushing | pushSnapshot() must be wired into checkAndSync(), fires on every app launch |
| AI chat "Session refreshed" error | JWT auto-retry: on auth error, refresh token + single inline retry (NOT recursive — old recursive caused 30+ duplicates) |
| Days/week change not rescheduling | `generateAndScheduleFromDate()` in WorkoutScheduleService — deletes future non-completed entries, preserves completed, regenerates from today |
| Image upload RLS violation | Storage path must be `$userId/$timestamp.jpg`, NOT `chat-media/$userId/...` — bucket name is already set by `.from('chat-media')` |
| Mic stops after 2-3 seconds | `pauseFor: 5s`, `listenFor: 60s`, `ListenMode.dictation`, `partialResults: true` via `SpeechListenOptions` |
| PRO chat "Session error" | `ai-proxy-pro` must have `verify_jwt: false` — Supabase gateway bug rejects valid JWTs when `true` |
| SSRF via ai-media-proxy | Only allow `${SUPABASE_URL}/storage/v1/object/` prefix URLs. Never fetch arbitrary user-supplied URLs server-side. |
| Null expiry grants PRO | `isPro()` returns `kDebugMode` when `expiresAt` is null — release builds treat null as free. Never remove this guard. |
| Promo code enumeration | `validate-promo` requires JWT auth. Never expose promo discount_pct to unauthenticated callers. |
| Subscription bypass via Hive | `gate()` calls `verifyFromServer()` for high-value features (`phases_2_to_12`, `ai_coach_unlimited`, `reasoning_tab`, `progress_photos`). Never rely on local-only check for these. Any feature that writes to Storage or spends cloud resources on the user's behalf MUST be server-verified. |
| Oversized AI payload abuse | All AI Edge Functions enforce message (5K chars) + snapshot (10K chars) limits server-side. Client limits are advisory only. |
| Error widget leaks stack trace | `ErrorWidget.builder` shows generic message in release (`kDebugMode` guard). Never show `exceptionAsString()` to production users. |
| future-prediction broken import | Import shared modules as `../_shared/openrouter.ts` in source, but deploy with `./_shared/openrouter.ts` (MCP places files in source/ subdirectory). |
| Warm-up sets counted in completedSets | `completedSets` getter filters out `warmUpSets` keys. Exercise name matching uses exact-first, fuzzy only for names >= 6 chars. |
| WarmupCooldownSection RangeError | `didUpdateWidget` resets `_checked` list when `widget.exercises.length` changes. Always guard list length on rebuild. |
| Workout receipt shows stale/wrong data | `WorkoutReceiptData.fromExerciseLogs(date)` is the SINGLE source of truth. Deduplicates exercises by name, sums sets, takes max weight. Never hand-build receipt data from a widget's local state. |
| Workout log edit path missing | `EditWorkoutLogSheet` is the single edit surface. Exposed from 4 places: WorkoutReceiptSheet Edit button, Home "View Card", calendar day detail, Train expanded view. Save recomputes `volume_kg`, chronologically rescans PR flags for that exercise, fires `pushSnapshot()` + `syncWorkoutData()`, invalidates all workout/home providers. Never build a second edit path — it will drift from this one. |
| Scan meal saves 0 kcal | `_ScanResultEditor` always computes `total_calories` from live item sum with per-item Atwater fallback (`kcal > 0 ? kcal : 4P+4C+9F`). Never read `result['total_calories']` directly — AI responses often omit it while per-item kcal is populated. |
| Scan meal result not editable | `_ScanResultEditor` replaces the old read-only `_buildResult`. All scan results are mutable: editable meal name, per-item name/kcal/P/C/F/Fi, +Add Item, X Delete. Total recomputes on every keystroke via `onChanged: (_) => setState(...)`. |
| Hidden tap-to-edit targets | Any row that responds to tap-to-edit MUST show a visual affordance (e.g., pencil icon at 14px, `textSecondary.withValues(alpha: 0.7)`). Invisible tap targets will not be discovered. |
| AI "temporarily unavailable" masks real error | `AiService._extractError()` pulls `{"error": "..."}` from non-200 Edge Function responses. Never throw raw "status X" — the server-side error body contains the actionable reason (message too long, snapshot too large, PRO required). |
| AI snapshot exceeds 10KB server limit | `AiService._compactContext()` trims in priority order: `step_history_7d` → `weight_trend` → `nutrition_trend` → `exercise_history` → `personal_records` → `coach_notices` → truncate `coaching_notes` → drop `fitness_summary`. Target <9500 bytes for JSON overhead buffer. Historical queries routinely blow past 10KB without this. |
| "Restart the app" error copy | Never use. Map server errors to actionable user messages in `ai_coach_provider.dart`: `Message too long` → "shorten it", `Snapshot too large` → "try a shorter question", `Image too large` → "max 5 MB", `502/503/504` → "model temporarily unavailable, try in a minute". |
| Edge Function leaks stack trace | Every catch block MUST return `{error: "Internal server error", request_id: <8-char hex>}` and log `console.error("[fn-name] request_id=X", err)` server-side. Never `JSON.stringify(err)` into the response body. Validation errors (400s) are the only exception — they ARE user-actionable and safe to return verbatim. |
| Webhook double-processes payment | `razorpay-webhook` MUST pre-SELECT by `razorpay_payment_id` before INSERT and catch Postgres 23505 (unique_violation) as success. Promo redemption runs ONLY when `alreadyProcessed === false`. Razorpay retries webhooks for 24h — without this, every retry duplicates the subscription row and burns a promo use. |
| Nutrition changes don't reach AI coach | Every nutrition mutation (logFood, addWater, decrement, urine color, updateFoodLog, deleteFoodLog, relogSavedMeal, AI breakdown, scan meal save, barcode save) MUST call `unawaited(SyncService.instance.syncNutritionData()) + unawaited(SyncService.instance.pushSnapshot())`. Missing either = AI coach gives advice based on stale/missing meals until next app launch. |
| Custom exercise invisible to AI coach | `CreateCustomExerciseSheet._save` fires `unawaited(SyncService.instance.pushSnapshot())` after `customBox.put`. Without this, the AI coach doesn't learn about the new exercise until app restart. Same pattern applies to any write that creates a new entity the AI should know about. |
| food_text_analysis unlimited abuse | `ai-proxy` enforces per-day rate limit on `food_text_analysis` channel (50/day free, 200/day PRO) counted via `ai_coach_interactions` rows. Server is the source of truth; client has no enforcement. Never rely on "it's just text" to skip rate limiting — text calls hit the same Gemini quota as vision. |
