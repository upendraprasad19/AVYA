# ICANBEFITTER

Personalised fitness and nutrition platform for young professionals (22-35) in India. Freemium — free forever tier + PRO at ₹349/month or ₹2,999/year.

---

## Features

### Free (forever)
- Phase 1 workout plan — 4 weeks, auto-generated locally (no API cost)
- Workout template builder + copy week
- Food database logging — 1,431 Indian-first foods (seeded from `assets/data/food_database.json`)
- AI food text analysis — 10 logs/day (server-side cap)
- Scan meal (camera) — 15 scans/day (server-side cap)
- Cart Auditor (grocery screenshot health audit) — 15 scans/day
- Weight, body measurements, streak, water tracking
- Steps + sleep sync via Google Fit / Health Connect / Samsung Health
- AI Coach — 10 messages/day forever (no time-limited trial — see CLAUDE.md §3 OQ-1)
- Workout Receipt PNG shareable card after every completed workout
- Weekly nutrition report — first report free

### PRO
- Auto-generate new plans after Week 4 (phases 2–12)
- Unlimited AI Coach (same Gemini 2.5 Flash backend, server-side `isPro` gate removes daily cap)
- Reasoning tab — deeper coaching via Gemini 2.5 Pro on weekly report
- Scan meal — 50 scans/day; Cart Auditor — 50 scans/day
- Progress photos (full timeline)
- Weekly AI nutrition report (ongoing) + Telegram push
- AI-personalised morning alerts
- Voice notes to AI coach
- Fresh Future Prediction card monthly

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter (Android + Web; iOS later) |
| State Management | Riverpod (flutter_riverpod, manual providers) |
| Local Storage | Hive (offline-first, primary for all reads/writes) |
| Auth | Supabase Auth (Email + Google OAuth + Phone OTP) |
| Database | Supabase Postgres (**46 tables** — see [`docs/architecture/database.md`](docs/architecture/database.md) for the canonical schema) |
| Storage | Supabase Storage (exercise images, progress photos PRO) |
| AI (all tiers) | Single Edge Function `ai-proxy` → Google Gemini 2.5 Flash. Server-side PRO gate (no daily cap for PRO; 10/day chat for free). |
| Food AI | Gemini 2.5 Flash (text analysis) + Gemini 2.5 Flash Lite (scan meal, cart auditor) |
| Weekly AI Report | Gemini 2.5 Pro (PRO-only, deepest reasoning) |
| Plan Generator | Local Dart engine (queries Hive `exerciseBox`, zero API cost) |
| Payments | Razorpay (WebView checkout → webhook → Supabase → poll → Hive) |
| Push Notifications | OneSignal + Firebase (AVYA project) |
| Telegram Bot | Separate project (OpenClaw VPS, @ICanbeFitterBot) — NOT in this repo |

> The previous OpenRouter (Gemma) + Cerebras (gpt-oss-120B / GLM-4.7) cascade was collapsed to a single Gemini provider on 2026-04-18 (see header comment in `supabase/functions/ai-proxy/index.ts`). Any doc still mentioning OpenRouter / Cerebras / GLM is stale — fix or flag it.

---

## First-time Setup

After `git clone`, every fresh checkout needs the following one-time setup. The detailed walkthrough lives in [`docs/onboarding/FRESH_CLONE.md`](docs/onboarding/FRESH_CLONE.md); the short version:

1. **Copy `.env.example` → `.env`** and fill in `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `RAZORPAY_KEY_ID`. The actual values for the fitness-app project are documented in [`docs/operations/SECRET_INVENTORY.md`](docs/operations/SECRET_INVENTORY.md) (gitignored references; never commit the values).
2. **Install root and `.claude/` Node dependencies:**
   ```bash
   npm install
   (cd .claude && npm install)
   ```
3. **Install the pre-commit hook** (gitignored — every clone must wire it up locally):
   ```bash
   sh scripts/setup-hooks.sh
   ```
4. **Drop the Supabase Personal Access Token** at `supabase/.supabase/supabase access token.txt` (gitignored). Used by `.claude/deploy_via_api.js` for host-shell Edge Function deploys. Token source + scope: see [`docs/operations/SECRET_INVENTORY.md`](docs/operations/SECRET_INVENTORY.md).
5. **Flutter packages:**
   ```bash
   flutter pub get
   ```
6. **Smoke test:**
   ```bash
   flutter analyze
   flutter test
   ```

---

## Getting Started

### Prerequisites
- Flutter SDK (stable channel)
- Android device or emulator (for Android builds)
- A `.env` file — see step 1 of First-time Setup above.

```
SUPABASE_URL=https://<project-id>.supabase.co
SUPABASE_ANON_KEY=<anon-key>
RAZORPAY_KEY_ID=rzp_test_<key>
```

> Environment variables are injected at **build time** via `--dart-define-from-file=.env`. The app does NOT use `flutter_dotenv`. Every run/build command must include this flag or auth will crash with "No host specified in URI".

### Install dependencies

```bash
flutter pub get
```

### Run (dev flavor)

```bash
flutter run --dart-define-from-file=.env --flavor dev -t lib/main.dart
```

### Run (prod flavor)

```bash
flutter run --dart-define-from-file=.env --flavor prod -t lib/main.dart
```

### Run on Web

```bash
flutter run --dart-define-from-file=.env -d chrome
```

---

## Project Structure

```
lib/
  core/
    theme/          # AppColors, spacing constants, typography
    router/         # GoRouter setup
    constants/      # AppConstants, feature keys
    services/       # SubscriptionService, SyncService, AiService, DayRolloverService
    utils/          # BmrCalculator, helpers, ist_date.dart
  features/
    auth/           # Login, signup, onboarding
    home/           # Dashboard, streak, weekly calendar
    train/          # Workout plan, active workout mode, exercise swap
    nutrition/      # Food logging, scan meal, cart auditor, diet plan
    ai_coach/       # Chat, reasoning tab, voice notes
    profile/        # Bio stats, goal card, subscription, health sync
  shared/
    widgets/        # PaywallSheet, ProBadge, LoadingSkeleton, StreakWarningBanner
    repositories/   # UserRepository, ExerciseRepository, FoodRepository, PlanGenerator

assets/
  data/
    exercise_library.json   # ~250 exercises, seeded into Hive on first launch
    food_database.json      # 1,431 foods, seeded into Hive on first launch

supabase/
  migrations/       # Postgres DDL (46 tables; see docs/architecture/database.md)
  functions/        # Edge Functions (TypeScript) — ai-proxy, razorpay-webhook, etc.
```

---

## Architecture

The app is **offline-first**. Hive is the primary data store; Supabase is backup + AI context + community growth.

```
┌─────────────────────────────────────────────────────┐
│                    FLUTTER APP                      │
│                                                     │
│  ALL reads/writes  →  Hive (LOCAL-FIRST)            │
│  Zero latency. Works fully offline.                 │
│                                                     │
│  SEED DATA (bundled in APK):                        │
│    exercise_library.json  (~250 exercises)          │
│    food_database.json     (1,431 foods)             │
│    → Parsed into Hive on first launch               │
│                                                     │
│  SYNC TO SUPABASE (background / fire-and-forget):   │
│    On every mutation   →  syncWorkoutData /         │
│                           syncNutritionData         │
│    Every app launch    →  pushSnapshot (AI context) │
│    Daily (if > 1 day)  →  full sync all logs        │
│    Immediately         →  custom foods/exercises    │
│                           (community contribution)  │
│                                                     │
│  RESTORE (new device):                              │
│    Login → pull from Supabase → populate Hive       │
│    Paginated fetch (1,000 rows/page, all history)   │
│                                                     │
│  SUPABASE ROLE (NOT primary DB):                    │
│    Auth / backup / AI context / community DB        │
│    Subscription verification                        │
└─────────────────────────────────────────────────────┘
```

### Hive Boxes

| Box | Contents |
|---|---|
| `userBox` | profile, preferences, progress |
| `workoutBox` | workout logs, schedules, templates, exercise logs |
| `nutritionBox` | nutrition logs, saved meals |
| `healthBox` | weight logs, measurements, streaks, sleep logs |
| `exerciseBox` | exercise library (seeded from bundled JSON) |
| `foodBox` | food database (seeded from bundled JSON) |
| `customBox` | user-created exercises and foods |
| `coachBox` | AI coach interactions, coaching notes |
| `syncBox` | last sync timestamps, pending sync queue |
| `configBox` | subscription status, feature flags |

---

## Plan Generator V4

**File:** `lib/shared/repositories/plan_generator.dart`

The plan generator runs entirely in Dart on-device — no API calls, no latency.

**MuscleSlot architecture:** Each workout day is defined as an ordered list of MuscleSlots. Each slot maps to one of 11 movement patterns (horizontal_push, vertical_pull, hip_hinge, knee_dominant, etc.) with a `targetFocus` (e.g., "chest", "lats") and `equipmentTier`.

**5-attempt cascading fallback per slot:**
1. Exact match: movement pattern + target focus + equipment tier + rep range
2. Relax rep range
3. Relax equipment tier (accept one tier up)
4. Relax both
5. Category-only fallback (any exercise in the right muscle group)

**Trainer-wisdom splits:** Push/Pull/Legs, Upper/Lower, Full Body — selected by goal + days/week combination. Beginner plans default to full-body regardless of split preference.

**Volume filter:** Compound-first ordering within each slot; isolation exercises only fill remaining capacity.

**Output:** A `Phase` object with 4 weeks of progressive overload built in. Free users get Phase 1 only; PRO users can generate phases 2–12 after completing each 4-week block.

---

## Tests

```bash
# All unit tests (no device required)
flutter test

# Single test file
flutter test test/bmr_calculator_test.dart

# All integration tests (requires connected Android device)
flutter test --dart-define-from-file=.env integration_test/app_test.dart --flavor dev

# Single integration flow
flutter test --dart-define-from-file=.env integration_test/flows/workout_log_flow_test.dart --flavor dev
```

---

## Build

```bash
# Release APK (prod)
flutter build apk --dart-define-from-file=.env --flavor prod --release -t lib/main.dart

# Release App Bundle (Play Store)
flutter build appbundle --dart-define-from-file=.env --flavor prod --release -t lib/main.dart

# Web
flutter build web --dart-define-from-file=.env
```

> Always invoke the `/build-apk` skill for APK builds; raw `flutter build apk` can hang silently on this machine without the skill's pre-flight cleanup (see CLAUDE.md §4.3).

---

## Lint

```bash
flutter analyze
```

---

## License

Private and proprietary. All rights reserved. Not open source.
