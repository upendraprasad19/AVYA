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

### Gradle Configuration
`android/gradle.properties` controls JVM memory. Current safe defaults for 16GB system:
- `-Xmx4G` heap (NOT 8G — causes silent OOM crash)
- `-XX:MaxMetaspaceSize=2G`
- `-XX:ReservedCodeCacheSize=256m`
- `org.gradle.parallel=true` + `org.gradle.caching=true`

If build hangs silently with no output, check `android/hs_err_*.log` for JVM crash dumps. Use `/build-apk` skill for the full automated pipeline.

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

### Edge Functions — host-shell deploy (preferred for any function with nested `_shared/tools/...` or payloads >100KB)

```bash
cd "C:/Upendra/Claude Code/Fitness App"
node .claude/emit_payload.js <fn> --auto --functions-dir <worktree>/supabase/functions
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl <fn> .claude/_payload_<fn>.json <verify_jwt>
```

- **Token:** auto-resolved from `supabase/.supabase/supabase access token.txt` (gitignored). Generated 2026-04-20 against fitness-app account.
- **Byte-identical to git** (no MCP path-mangling, no hand-trim risk). First used Phase C.5 → ai-proxy v43; now standard for all redeploys.
- **Path scheme:** all shared imports MUST use `from "../_shared/..."` (parent dir), NOT `from "./_shared/..."`. The OLD MCP `deploy_edge_function` tool silently mangled the wrong path; the new flow doesn't. Audit your edits.

`mcp__ba7b5e8e__deploy_edge_function` (the legacy MCP path) still works for small single-file functions but is unsafe for the AI coach tools bundle. Do not use `supabase` CLI — it is logged into the wrong account (personal, not fitness app account). See §2a for account details.

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
| AI Coach (all tiers) | Single Edge Function `ai-proxy` → Gemini 2.5 Flash. Free: 30-day trial 15 msg/day. PRO: unlimited. Server-side gate. |
| Food AI | Gemini 2.5 Flash (text analysis) + Gemini 2.5 Flash Lite (scan meal, cart auditor) |
| Weekly AI Report | Gemini 2.5 Pro (PRO-only, deepest reasoning) |
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
│    assets/data/food_database.json (93 foods)          │
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
| `syncBox` | last_sync_timestamps (pending_sync_queue is **planned** — see `docs/superpowers/specs/2026-04-17-sync-reliability.md`, not yet implemented) |
| `configBox` | subscription status, feature flags, app config |

#### workoutBox Key Patterns
| Key Pattern | Value |
|-------------|-------|
| `schedule_YYYY-MM-DD` | Schedule entry (type, status, workout_name, exercises, week) |
| `exercise_log_index_YYYY-MM-DD` | List of exercise log IDs for that date |
| `exlog_<timestamp>_<hash>` | Exercise log: exercise_name, logging_type, weight_kg, reps_completed, sets_completed, volume_kg, is_pr |
| `wlog_<timestamp>` | Workout log: workout_name, date, duration_seconds, sets_completed |
| `tmpl_<timestamp>` | Workout template (single-day) — fields: id, name, exercises[], exercise_count, type:'template', assigned_days:[int], created_at. Multi-day AI templates (from `createCustomTemplate` tool) split into N rows tagged with `group_id`/`group_day_index`/`group_total_days` for cross-row identification. |

---

## 5. DIRECTORY STRUCTURE

> Full annotated tree → `docs/reference/directory-structure.md`. Quick orientation only here.

```
lib/
  core/{theme, router, constants, services, utils, copy}/   # singletons, GoRouter, theme tokens, BMR
      utils/exercise_display.dart    # Experience-aware exercise labels
      copy/wardroom_copy.dart        # Single source for literal Wardroom handoff strings
                                     #   (eyebrows, CTA labels, onboarding copy, notifications)
  features/{auth, onboarding, home, train, nutrition, ai_coach, profile}/
    each: screens/, widgets/, providers/, repositories/, models/
      onboarding/screens/
        welcome_screen.dart          # Stepped flow entry — / onboarding (NEW default)
        goal_screen.dart             # /onboarding/goal (NEW)
        stats_screen.dart            # /onboarding/stats (NEW)
        plan_screen.dart             # /onboarding/plan — "REPORT FOR DUTY" CTA (NEW)
        onboarding_chat_screen.dart  # LEGACY — now only at /onboarding/chat for rollback
      profile/screens/
        settings_screen.dart         # Wardroom refresh (PR AC)
        notifications_screen.dart    # Wardroom notifications inbox (PR AF)
      profile/providers/profile_completeness_provider.dart  # Tier 1/2 weighted calculation
      profile/widgets/profile_completeness_card.dart  # Progress bar + missing fields
      profile/widgets/slim_achievements_card.dart     # Single-line badges row
      profile/screens/submissions_screen.dart         # Tabbed MY SUBMISSIONS / COMMUNITY
                                                      #   REVIEW. Canonical route:
                                                      #   /profile/submissions (S1, APK
                                                      #   test #1 batch 2026-04-24).
      profile/screens/my_submissions_screen.dart      # LEGACY — kept only so old
                                                      #   deep-links to /profile/my-
                                                      #   submissions keep working. Do
                                                      #   not add new entry points;
                                                      #   route new callers at
                                                      #   /profile/submissions instead.
  shared/
    widgets/    paywall_sheet, pro_badge, streak_warning_banner, loading_skeleton
      wardroom/   # 28 primitives (up from 15) — see "Wardroom primitives" in §9.
                  # Barrel: wardroom.dart. New since PR R (2026-04-18..20):
                  #   ward_seal_badge.dart            — WardSealBadge + WardSealVariant
                  #   ward_dispatch_header.dart       — WardDispatchHeader (double gold rule eyebrow)
                  #   ward_insight_quote.dart         — WardInsightQuote + InsightSegment
                  #   ward_glass_grid.dart            — WardGlassGrid (8-cell hydration)
                  #   ward_achievement_strip.dart     — WardAchievementStrip (earned/locked circles)
                  #   ward_phase_dots.dart            — WardPhaseDots (12-phase row)
                  #   ward_phase_block.dart           — WardPhaseBlock (roman numeral + START chip)
                  #   ward_stat_tile.dart             — WardStatTile (mono label + Fraunces numeric)
                  #   ward_radio_row.dart             — WardRadioRow (gold left-border)
                  #   ward_toggle.dart                — WardToggle (pill, 150ms crossfade)
                  #   ward_unit_toggle.dart           — WardUnitToggle (KG/LBS pill)
                  #   ward_session_row.dart           — WardSessionRow + WardSessionTable
                  #   ward_category_sidebar.dart      — WardCategorySidebar (rotated mono label)
    repositories/  user, exercise, food, plan_generator (NEVER modify without approval)
      plan_generator.dart (re-export shim)
      plan_engine/             # V4 modular pipeline
        models.dart            # MuscleSlot, MuscleSlotDay, CSpec (legacy)
        split_resolver.dart    # Trainer-wisdom splits → MuscleSlotDay[]
        volume_filter.dart     # Stage 1.5: slots.take(targetCount(exp, daysPerWeek))
        exercise_selector.dart # 5-attempt cascading fallback
        plan_generator.dart    # Pipeline orchestrator (generateV4)
        periodization_engine.dart # DUP + exercise-specific rep_range
        sequencing_engine.dart # CNS ordering
        superset_engine.dart   # Pairing
        cardio_finisher.dart   # Cardio append
        warmup_cooldown_selector.dart # Warmup/cooldown inject

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
- `lib/shared/repositories/plan_engine/volume_filter.dart` — Stage 1.5 target-count trimming (`targetCount(experience, daysPerWeek)`)
- `lib/core/utils/exercise_display.dart` — Experience-level exercise label formatting
- `test/plan_generator/v4_diagnostic_test.dart` — pure-Dart V4 pipeline tracer. Run this when plan generator output looks wrong; emits `test/plan_generator/v4_diagnostic_output.md`. Mirrors `exercise_repository.queryV4` + `exercise_selector._cascadeFill`; any change to either production file requires an equivalent update to the mirror.
- `lib/features/nutrition/providers/diet_plan_provider.dart` — ONE reader of `configBox['saved_diet_plan']`. Returns `Map<String, PlannedSlot>` keyed by slot (breakfast/lunch/dinner/snack). Consumed by `TodaysMealsCard` to render "FROM YOUR DIET PLAN" hints on empty slots. `diet_plan_screen._savePlan` invalidates this provider after writing the plan (PR AH.5).
- `lib/features/profile/providers/weekly_report_data_provider.dart` — ONE source for Weekly Report 4-up sparklines. Reads last-7-days series from `healthBox` (weight, forward-filled), `nutritionBox` (calories + protein, zero-filled), `workoutBox` (0/1 per day). Consumed only by `WeeklyReportCard` (PR AH.8). Invalidate after any mutation if you want real-time refresh; the card is not watched elsewhere.

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
19. **Server-side subscription verification:** High-value features (`phases_2_to_12`, `ai_coach_unlimited`, `progress_photos`) must call `verifyFromServer()` in `gate()`. Local-only check is insufficient.

---

## 7. DATABASE SCHEMA (36 Tables — Supabase Postgres)

> Full DDL → `docs/reference/database-schema.md`. Authoritative source of truth: `supabase/migrations/`.

| Domain | Tables |
|---|---|
| Identity (4) | `users`, `user_profile`, `user_preferences`, `user_progress` |
| Fitness (8) | `exercise_library`, `workout_templates`, `template_exercises`, `scheduled_workouts`, `workout_logs`, `workout_log_exercises`, `workout_log_sets`, `user_custom_exercises` |
| Nutrition (5) | `food_database`, `nutrition_logs`, `nutrition_log_items`, `user_saved_meals`, `user_custom_foods` |
| Health (6) | `weight_logs`, `body_measurements`, `streaks`, `water_logs`, `sleep_logs`, `daily_steps` |
| Visual (1) | `progress_photos` |
| AI (3) | `user_daily_snapshots`, `ai_coach_interactions` (incl. `tool_calls` JSONB column from migration 029), `coach_memory` |
| Telemetry (1) | `client_errors` |
| Monetisation (6) | `subscriptions`, `promo_codes`, `promo_code_uses`, `food_corrections`, `telegram_connections`, `referral_codes` |
| Community (2) | `community_reviews`, `memory_embeddings` |

**FK direction quirk — `referral_codes` is the ONLY table with an FK to `auth.users(id)`.** Every other user-scoped table FKs to `public.users(id)` because those tables are populated only after the onboarding sync path has inserted the user into `public.users`. Referral-code generation fires on-demand from Profile → Invite Friends, which can happen BEFORE `public.users` has the user's row (fresh sign-up, onboarding not yet completed). Migration 035 (2026-04-24) repointed the FK to `auth.users` + added `UNIQUE(user_id)` after silent FK violations on new-account testers produced the "Failed to generate referral code" toast. Do not "normalize" this FK back to `public.users` without understanding that timing dependency.

**Critical UNIQUE constraints (required for safe re-sync dedup — never remove):**
- `streaks(user_id, week_start)` — prevents duplicate weeks on restore
- `water_logs(user_id, date)` — one row per user per day
- `scheduled_workouts(user_id, scheduled_date)` — one schedule per user per date
- `workout_log_sets(workout_log_id, exercise_id, set_number)` — idempotent per-set upsert
- `daily_steps(user_id, date)` — one step total per user per day
- `user_custom_exercises.id` and `user_custom_foods.id` — must be a deterministic v5 UUID computed from `(user_id, type, lower(name))` so cross-device upserts dedupe instead of duplicating. Generation namespace: `5a1f0b0c-9dad-11d1-80b4-00c04fd430c8`. Migration 020 dedupes legacy rows via `uuid_generate_v5`.

**Cloud `workout_log_exercises`** — per-exercise summary table written by the Flutter app. Key semantics: `set_number` = total completed sets (NOT "which set"); `weight_kg` = best across sets; `exercise_id` = exercise_name (stable identity for cross-week grouping). See §11 "Exercise Log Cloud Contract".

**Column-type notes (post-migration):**
- `user_profile.injuries` — `text[]` (migration 033, 2026-04-24). Previously `text` — client was syncing `List.toString()` → `"[none]"` and round-tripping to broken state. Now passes the List directly; default `ARRAY['none']::TEXT[]`. Legacy rows backfilled from stringified shapes.
- `users.terms_accepted_at` + `users.terms_version` — DPDP audit trail columns (migration 032, 2026-04-20). Stamped by `TermsModal` (Hive) and synced up on first post-auth users upsert in `_ensureLocalUser`. Bump `AppConstants.termsVersion` to force re-prompt.
- `nutrition_logs.total_fiber NUMERIC DEFAULT 0` (migration 034, 2026-04-24). Historical rows stay at 0 — `nutrition_log_items` has no fiber column, so no backfill source. New logs carry the value from the Hive `nlog_*` row via `_syncNutritionLogs`. Feeds the AI coach via `_getTodayNutrition.fiber_g` / `fiber_target_g: 30`.

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

### Colors — Wardroom palette (post-PR R reconciliation)

```dart
class AppColors {
  // Backgrounds (5-step depth hierarchy)
  static const bg        = Color(0xFF02070F);  // primary canvas
  static const bgDeep    = Color(0xFF01040A);  // deepest — rotated sidebars, modal scrim
  static const bgRaise   = Color(0xFF04111E);  // raised (active workout rest timer etc.)
  static const header    = Color(0xFF0A1020);  // app bar / letterhead band
  static const card      = Color(0xFF06101F);  // standard card
  static const cardHi    = Color(0xFF0A1828);  // elevated card (selected, insight)
  static const input     = Color(0xFF0E1E30);  // text fields, chips
  static const border    = Color(0xFF1A2C40);  // hairline borders
  static const line2     = Color(0x14FFFAE8);  // parchment 8% alpha — divider/grain accent

  // Accent — Campaign Gold (NOT cyan; the Wardroom handoff moved everything off Electric Cyan)
  static const accent     = Color(0xFFD4B270);  // Campaign Gold
  static const accentSoft = Color(0x1AD4B270);  // 10% alpha tint

  // Text (4-step ghost ladder)
  static const textPrimary = Color(0xFFF2EDE4);  // parchment
  static const textDim     = Color(0xFF8A9BAA);
  static const textMute    = Color(0xFF4D6070);
  static const textGhost   = Color(0xFF2A3848);  // placeholder, disabled

  // Semantic
  static const ok   = Color(0xFF7FB4A2);  // success, confirmed
  static const warn = Color(0xFFF0B23E);  // warnings, over-cap
  static const bad  = Color(0xFFD7604E);  // errors, destructive
  static const info = Color(0xFF6FA2C9);  // neutral info, water
}
```

> The handoff's `README.md` rounds the palette for print; the JSX `const W = {}` in
> `Knowledgebase/Avya App redesign/design_handoff_wardroom/src/wardroom-tokens.jsx` is the
> **source of truth** and is what `colors.dart` tracks. PRs K–Q used README hex values and
> were reconciled to the JSX map in PR R (commit `174ff21`).

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
- **Secondary button:** `accentSoft` bg, 1.5 `accent`-30% border, `accent` w800 text
- **Card:** `card` bg, 1 `border` border, radius-M, padding 16. Active variant uses `accent`-20% border.
- **PRO locked card:** blur(4) + `bg`-85% overlay, gold lock, gold CTA
- **Streak badge:** `accentSoft` bg, `accent` w900 text, `accent`-20% border
- **Progress bar:** `input` track, `accent` fill, height 6, radius 3

### Wardroom primitives (28 total)

Barrel: `lib/shared/widgets/wardroom/wardroom.dart`. Grouped by role:

| Primitive | File | Purpose |
|-----------|------|---------|
| **Shell** | | |
| WardFrame | ward_frame.dart | Root scaffold — grain overlay, padded content area |
| **Header** | | |
| WardLetterhead | ward_letterhead.dart | Section eyebrow + title + optional gold rule (`WardDivider` enum: `none`/`single`/`double`; legacy `divider: bool` still accepted) |
| WardDispatchHeader | ward_dispatch_header.dart | Double gold rule + eyebrow + italic-gold emphasis + context line (reports / coach dispatch) |
| WardEyebrow | ward_eyebrow.dart | Standalone mono eyebrow label |
| WardRule | ward_rule.dart | Gold rule with configurable weight / dash pattern |
| **Surface** | | |
| WardCard | ward_card.dart | Standard card — bg, border, radius variants |
| WardAvatar | ward_avatar.dart | Circular monogram or photo w/ gold ring |
| WardInsightQuote | ward_insight_quote.dart | Gradient card with gold quote watermark + `InsightSegment` list |
| WardGlassGrid | ward_glass_grid.dart | 8-cell hydration tracker grid |
| **Action** | | |
| WardButton | ward_button.dart | Primary/secondary/ghost button variants |
| WardChip | ward_chip.dart | Compact label / toggle chip |
| WardRadioRow | ward_radio_row.dart | 44px tap row with gold left-border when selected |
| WardToggle | ward_toggle.dart | 36×20 pill toggle, 150ms crossfade |
| WardUnitToggle | ward_unit_toggle.dart | KG/LBS 2-position inline pill |
| **Numeric** | | |
| WardBigNumber | ward_big_number.dart | Fraunces large numeric + unit caption |
| WardKvRow | ward_kv_row.dart | Label + value row with dotted leader |
| WardStatTile | ward_stat_tile.dart | Mono label + Fraunces numeric + unit |
| **Meter** | | |
| WardBar | ward_bar.dart | Progress bar — optional `trailingLabel` for gold "25%" mono numeral |
| WardSpark | ward_spark.dart | Sparkline with gold stroke |
| WardRing / WardMultiRing | ward_ring.dart | Single + concentric ring progress |
| **Structure** | | |
| WardAchievementStrip | ward_achievement_strip.dart | Horizontal scrollable earned/locked circles |
| WardPhaseDots | ward_phase_dots.dart | 12-phase progress row |
| WardPhaseBlock | ward_phase_block.dart | Roman numeral circle + title/weeks/description + START chip |
| WardSessionRow / WardSessionTable | ward_session_row.dart | Set-log row (set# / weight / reps / status) + table shell |
| WardCategorySidebar | ward_category_sidebar.dart | Vertical 46px `bgDeep` with rotated mono label |
| **Badge / Glyph** | | |
| WardSealBadge | ward_seal_badge.dart | Seal glyph in 4 `WardSealVariant` (report / subscription / phase / founder) |
| Glyph set (5) | ward_glyphs.dart | `AnchorGlyph`, `CompassRoseGlyph`, `TierChevronsGlyph`, `SealGlyph`, `RankBarGlyph` |

---

## 10. SUBSCRIPTION GATE PATTERN

### PRO Feature Keys
```
phases_2_to_12         → auto-generate new 4-week plan after Week 4
active_workout_mode    → active workout logging screen
ai_coach_unlimited     → unlimited AI messages (free = 15/day for 30 days)
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
- **Server-side verification:** `gate()` calls `verifyFromServer()` (5-min cache TTL) for high-value features (`phases_2_to_12`, `ai_coach_unlimited`, `progress_photos`). Other features use local check only for low latency.

### gate() High-Value Features
```dart
static const Set<String> _highValueFeatures = {
  AppConstants.featurePhases2To12,
  AppConstants.featureAiCoachUnlimited,
  AppConstants.featureProgressPhotos,  // photo writes to user-scoped Storage bucket
};
// gate() checks server for these features, local-only for others
```

**Why `progress_photos` is high-value:** It triggers Supabase Storage writes to a user-scoped bucket. Granting access via a spoofed local `isPro` flag would let a free user on a rooted device persist private photos onto infrastructure we pay for. Any feature that writes to Storage or spends cloud compute/storage on behalf of the user MUST be server-verified.

---

## 11. AI ARCHITECTURE

Single provider: **Google Gemini** (via `GEMINI_API_KEY`). Cerebras + OpenRouter were retired on 2026-04-18 — one key to rotate, one billing line, one source of truth.

### Semantic retrieval (since ai-proxy v46, 2026-04-24) — Phase B live

Every chat turn now embeds the user's message via `getEmbedding(text, "RETRIEVAL_QUERY")` and queries `match_memories(user_id, embedding, match_count=5, threshold=0.65)` for the top-5 most semantically similar past memories (source types: `conversation`, `daily_summary`, `coaching_note`, `pattern_insight`). Results are injected into the system prompt as a "Relevant context from earlier conversations" block between the snapshot and coaching_notes sections. `formatRetrievalBlock` caps each line at 200 chars (5 lines ≈ 1 KB prompt growth).

**Helper:** `supabase/functions/_shared/memory_retrieval.ts` — `retrieveRelevantMemories(supabaseClient, userId, query, options?)`. Never throws; all failure modes return `{ memories: [], source: <code> }`. Options: `matchCount`, `threshold`, `embeddingTimeoutMs` (default 3000), `getEmbeddingFn` (test injection seam).

**Fallback behavior:** when retrieval returns 0 matches, fails embedding, hits the 3s timeout, or errors on the RPC, the prompt falls back to the existing full-dump `coaching_notes` path. Zero regression risk. `[ai-proxy] memory_retrieval fallback: source=...` warnings are logged on any non-retrieval / non-empty outcome.

**Gating:** all users (free + PRO). Per-turn cost ~$0.00001 via Gemini embedding API — PRO-gating added complexity without meaningful savings. Retrieval latency: ~150 ms p50, hard-bound at 3 s.

**Phase A (accumulation)** has been running since 2026-03-31 (migration `20260331000001_add_pgvector_memory.sql`): `ai-proxy/index.ts:635` + `rolling-context/index.ts:210` embed every chat turn + nightly summary into `memory_embeddings`. No Phase B backfill needed — older coaching_notes reach the coach via the recent-N fallback. Retrieval hit rates become meaningful only after users accumulate ~10+ conversations.

### Tool-calling (since ai-proxy v44, 2026-04-20) — 20 AI coach tools

`ai-proxy` chat channel uses Gemini function-calling via `_shared/tool-loop.ts` (multi-round, max 3 rounds, validation feedback to model). 20 typed tools across 4 families, defined in `_shared/tools/<family>/<tool>.ts` and registered in `_shared/tools/registry.ts`. Tier filtering: free users see 6 FREE tools, PRO sees 20.

| Family | Tools |
|---|---|
| Workout (8) | `swapExercise`, `logSet`, `markWorkoutComplete`, `shortenWorkout`, `createCustomExercise`, `modifyWorkoutForInjury`, `rescheduleWeek`, `generateHotelWorkout` |
| Progress (3) | `getProgressSummary`, `getExerciseHistory`, `logPR` |
| Nutrition (4) | `logMealByText`, `adjustCaloricTarget`, `suggestMeal`, `prelog` |
| Plan (5) | `regeneratePlanBlock`, `pausePlan`, `switchGoal`, `createCustomTemplate`, `scheduleTemplate` |

**Hive-first hybrid architecture:** READ tools (e.g. `getProgressSummary`, `getExerciseHistory`, `suggestMeal`) execute server-side and feed Gemini results in same turn. WRITE tools emit typed `ToolIntent` to client; client confirms via card/sheet, then writes Hive + fire-and-forget syncs (matching the existing CLAUDE.md §6 rule 1 mutation pattern).

3 confirmation classes: trivial (5s auto-confirm card), reviewable (explicit inline card), destructive (bottom-sheet with diff preview). Per-intent dispatch in `lib/features/ai_coach/services/tool_dispatcher.dart`. 1-hour intent TTL + concurrent-edit guards on every dispatch.

Telemetry: per-tool-call records written to `ai_coach_interactions.tool_calls` JSONB column (migration 029), surfaced via `coach_tool_invocations_v` view.

### Proactive triggers (8 of 8 brainstorm §5 triggers, since 2026-04-20)

All 8 cron-driven Edge Functions in prod. Each uses `_shared/proactive_dedup.ts` (`shouldSendProactive` + `markProactiveSent`) to prevent same-type push twice per IST day, writing `coach_memory.last_proactive_type` after successful send.

| # | Trigger | Edge Function | Cron (UTC → IST) | Tier |
|---|---|---|---|---|
| 1 | Morning Brief | `morning-alert` | (existing 2-stage) → 7am IST | both |
| 2 | Workout Window Closing | `workout-window-closing` | `30 15 * * *` → 21:00 IST | both |
| 3 | Protein Gap Alert | `protein-gap-alert` | `30 14 * * *` → 20:00 IST | PRO |
| 4 | Streak Protection | `streak-guardian` | (existing) → 20:00 IST | both |
| 5 | PR Detection | `pr-detection` | `*/15 * * * *` → near-real-time | both |
| 6 | Plateau Alert | `plateau-alert` | `30 13 * * *` → 19:00 IST | PRO |
| 7 | Weekly Recap | `weekly-recap-ready` | (existing) → Sunday | both |
| 8 | Re-engagement | `re-engagement` | `30 06 * * *` → 12:00 IST | both |

**Plateau-alert** + **re-engagement** read scores from `coach_memory.{plateau_risk_score, dropout_risk_score}` (computed nightly by `compute-coach-signals` → `compute_coach_signals_for_user(user_id)` RPC). Re-engagement has a fallback path that scans `workout_logs/nutrition_logs/weight_logs` directly for users without `coach_memory` rows yet.

Cron registrations live in `supabase/migrations/031_proactive_triggers_cron.sql`. Each uses `private.morning_alert_get_service_key()` for the Bearer token (consistent with `compute_coach_signals` cron pattern).

### Model matrix
| Edge Function | Model | Purpose |
|---|---|---|
| `ai-proxy` (chat + food text + prediction) | `gemini-2.5-flash` | Free + PRO coach, food text analysis, prediction card |
| `ai-proxy` (scan_meal, cart_auditor) | `gemini-2.5-flash-lite` | Vision: nutrition JSON from photos |
| `ai-media-proxy` | `gemini-2.5-flash-lite` | PRO photo-upload chat |
| `assess-body-composition` | `gemini-2.5-flash-lite` | Body-fat % from photo |
| `daily-snapshot` (coaching notes) | `gemini-2.5-flash` | Extract facts from daily conversations |
| `morning-alert` | `gemini-2.5-flash` | Personalised morning push |
| `rolling-context` | `gemini-2.5-flash` | Nightly conversation summary |
| `future-prediction` | `gemini-2.5-flash` | 90-day forecast card |
| `weekly-report` | `gemini-2.5-pro` | Deepest reasoning, PRO-only weekly |
| `_shared/embeddings.ts` | `gemini-embedding-001` | Memory retrieval vectors |

### Shared helper: `_shared/gemini.ts`
`geminiChat({model, systemPrompt, userPrompt, maxTokens, temperature, imageBase64, jsonMode, fallbackToLite})` is the ONE interface for all Gemini calls. Handles:
- Message translation from OpenAI-style `{system, user}` to Gemini's `{systemInstruction, contents}`.
- Vision input via `inline_data` parts.
- `responseMimeType: application/json` when `jsonMode=true`.
- **Built-in fallback:** on 5xx / 429 / empty content, automatically retries once on `gemini-2.5-flash-lite`. Pass `fallbackToLite: false` when primary is already Flash-Lite.

### Single AI coach endpoint — no client-side routing
```
Client (free + PRO) → ai-proxy (Gemini 2.5 Flash)
  JWT → auth.getUser(token)
  isPro = SELECT 1 FROM subscriptions WHERE user_id AND active AND end_date > now()
  If !isPro: enforce 30-day trial window + 15/day cap via ai_coach_interactions
  If  isPro: no cap, no trial
  ← Response + model_used + tokens_used
```
The old separate `ai-proxy-pro` function returns **410 Gone** for any orphan clients still calling it.

### Cost estimates (Gemini pricing at 2026-04-18)
| Scale | Cost/month (coach + vision + weekly Pro) |
|---|---|
| 50 beta users | ~$3 |
| 1,000 users | ~$70 |
| 10,000 users | ~$700 |

Input $0.075/M · output $0.30/M for Flash; $1.25/M · $10/M for Pro; Flash-Lite is the cheapest tier.

### Input Validation (all AI Edge Functions)
- **Message length:** Max 5,000 chars. Enforced server-side on `ai-proxy`, `ai-media-proxy`.
- **Snapshot size:** Max 10,000 chars (stringified JSON). Enforced on `ai-proxy`.
- **Image size:** Max 5MB. Enforced on `ai-media-proxy` via content-length + arrayBuffer check.
- **SSRF protection:** `ai-media-proxy` only fetches from `${SUPABASE_URL}/storage/v1/object/` prefix. All other URLs rejected.

### Client-Side Context Compaction (`AiService._compactContext`)
- **Target:** <9,500 bytes (buffer under 10KB server limit for JSON overhead).
- **Trim order** (least load-bearing first): `step_history_7d` → `weight_trend` → `nutrition_trend` → `exercise_history` → `personal_records` → `coach_notices` → truncate `coaching_notes` (1,500 char cap) → drop `fitness_summary`.
- Applied on EVERY AI call (`chat`, `chatWithMedia`, `predict`, direct-HTTP fallbacks). Without this, historical queries that trigger `enrichContextForQuery` get rejected with a 400 from the server.

### Client-Side Error Extraction (`AiService._extractError`)
- Parses `{"error": "..."}` out of non-200 responses on all AI Edge Functions.
- Replaces generic "status X" with actionable messages at the provider level (`ai_coach_provider.dart`):
  - `Message too long` → "Your message is too long (max 5000 chars). Please shorten it and try again."
  - `Snapshot too large` → "Your coaching context is unusually large. Please try a shorter question."
  - `Image too large` → "That photo is too large (max 5 MB)."
  - `Only Supabase Storage URLs are allowed` → "Upload failed — please try picking the photo again."
  - `502`/`503`/`504` → "The AI model is temporarily unavailable. Please try again in a minute."
- **Never use "restart the app" copy.** It doesn't fix any of these root causes.

### Edge Function Auth
- `ai-proxy`: `verify_jwt: false` (Supabase gateway bug). Manual JWT validation via `auth.getUser()` + server-side `isPro` check for unlimited tier.
- `ai-media-proxy`: `verify_jwt: true` + manual JWT + PRO subscription check.
- `validate-promo`: `verify_jwt: true` + manual JWT validation (prevents unauthenticated promo enumeration).
- `future-prediction`: `verify_jwt: true` + manual JWT validation.

### Vision Features (ai-proxy — Gemini 2.5 Flash Lite)
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
- Applies to all 18 live Edge Functions: `ai-proxy`, `ai-media-proxy`, `razorpay-webhook`, `verify-payment`, `verify-subscription`, `validate-promo`, `assess-body-composition`, `beat-my-coach`, `daily-snapshot`, `expiry-reminder`, `future-prediction`, `morning-alert`, `redeem-referral`, `rolling-context`, `streak-guardian`, `weekly-recalc`, `weekly-recap-ready`, `weekly-report`. (`ai-proxy-pro` is a 410-Gone stub — retired 2026-04-18 — excluded.)

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

### V4 Pipeline (MuscleSlot Architecture)

**Key change:** CSpec (category-based) replaced by MuscleSlot (muscle-level targeting).

Pipeline stages:
1. **Split Resolver** → `MuscleSlotDay[]` with granular muscle slots per day (8-10 P1-P5 slots per day, ordered by priority)
2. **Volume Filter** → Trims slots to `targetCount(experience, daysPerWeek)` by `slots.take(N)` — depends on split_resolver ordering
3. **Exercise Selector** → 5-attempt cascade within movement patterns (NEVER crosses boundaries)
4. **Sequencing Engine** → Orders by priority, then compound-first
5. **Periodization Engine** → Uses exercise-specific `rep_range` + archetype-based wave
6. **Superset Pairer** → Unchanged
7. **Cardio Finisher** → Unchanged
8. **Warmup/Cooldown** → Now also auto-injects for custom templates

**Exercise count targets (per day):**

| Experience | 3-day | 4-day | 5-day | 6-day |
|---|---|---|---|---|
| Beginner | 6 | 5 | 4 | 4 |
| Intermediate | 8 | 7 | 6 | 6 |
| Advanced | 10 | 9 | 8 | 8 |

Inverse pattern: fewer training days → more exercises per session. More experience → more total volume. Defined in `VolumeFilter.targetCount(experience, daysPerWeek)`.

**Movement patterns (11):** horizontal_push, vertical_push, horizontal_pull, vertical_pull, knee_dominant, hip_dominant, core, elbow_flexion, elbow_extension, shoulder_isolation, hip_isolation

**Cascade attempts:**
1. `attempt1Exact` — all fields match (movement_pattern + target_focus + exercise_type + subFocus + suitable_for + foundational)
2. `attempt2DropSubFocus` — drop subFocus
3. `attempt3DropTypeAndTarget` — drop target_focus + exercise_type (keep movement_pattern only)
4. `attempt4DropEquipment` — drop equipment_tier
5. `universalPool` — hardcoded bodyweight fallback (`exercise_selector.dart:493-505`, mirrored in `cascade_tracer.dart`)

**Slot capacity rule:** No muscle/pattern/type triple should appear in more slots per week than its exercise library pool depth supports. E.g., Rear Delts/shoulder_isolation/isolation has 3 library exercises → max 3 slots/week. Over-allocation → `universalPool` picks (Pike Push Up for rear delt slots) or `(none)` failures.

**Beginner-foundational pool constraint:** For Phase 1, `queryV4` requires BOTH `suitable_for` contains "Beginner" AND `is_foundational: true`. When adding/removing exercises from these pools, audit with `dart run test/plan_generator/sample_plans_report.dart`.

**A/B variants:** slotsB alternates anterior/posterior emphasis weekly (e.g., A=chest-heavy push, B=shoulder-heavy push)

**Verification tools:**
- `test/plan_generator/sample_plans_report.dart` — generates all 12 combos (3×experience × 4×days) for build_muscle/full_gym, emits `sample_plans_output.md`. Target: 0 attempt3/universalPool/none.
- `test/plan_generator/v4_diagnostic_test.dart` — pure-Dart mirror of production cascade; run when changing `exercise_repository.queryV4` or `exercise_selector._cascadeFill`.

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
- Shows: DONE badge (green) + "View Card >" (gold) + best lift + total volume
- "View Card" opens `WorkoutReceiptSheet` with receipt reconstructed from Hive exercise logs
- Calendar day detail sheet also shows "View Workout Card" button for completed days

---

## 13a. ONBOARDING (stepped flow — default since PR Y–AB, expanded in PR AI 2026-04-20 → 5 steps on `feat/onboarding-train-nutrition` 2026-04-24)

**Current default flow (5 visible steps):**

```
Welcome       (/onboarding)            → sets no state, just CTA  (unnumbered)
   ↓
Identity      (/onboarding/identity)   → full_name, date_of_birth,
                                         sex                       (01 · 05)
   ↓
Goal          (/onboarding/goal)       → primary_goal              (02 · 05)
   ↓
Stats         (/onboarding/stats)      → current_weight_kg,
                                         target_weight_kg, height_cm,
                                         body_fat_pct,
                                         activity_level             (03 · 05)
   ↓
Details       (/onboarding/details)    → fitness_experience,
                                         pace_preference,
                                         days_per_week,
                                         equipment_access           (04 · 05)
   ↓
Plan          (/onboarding/plan)       → "REPORT FOR DUTY" — commits via
                                         OnboardingNotifier.completeOnboarding()
                                                                    (05 · 05)
```

- **State passing:** `GoRouter` `state.extra` (a `Map<String, dynamic>`) between screens —
  **no premature provider commits.** The notifier only runs once, on the final tap. Each
  screen spreads the incoming extras (`...widget.initial`) into its outgoing extras so
  every field captured upstream survives to Plan.
- **Sex moved from Stats to Identity.** Stats no longer shows the 3-pill sex selector.
- **Age dropped entirely.** `date_of_birth` (captured on Identity via date picker, min age
  13) is the canonical field. `plan_screen` computes `age` on the fly for `BmrCalculator`;
  `age` is never stored to Hive or Supabase.
- **Fields still defaulted by the stepped flow** (user can edit via Profile → Edit Profile):
  - `lifestyle_activity` — inferred from `activity_level` (1:1 mapping).
  - `diet_preference` — defaults to `'veg'` (Indian-first default).
  - `injuries` — defaults to `['none']` (matches `edit_profile_screen` convention).
  - `start_date` — hardcoded to `'this_monday'`.
  - `city` — optional, not collected during onboarding.
  These four **are now persisted** to Hive by `completeOnboarding` (pre-2026-04-24 bug: they
  were set via `setAnswer` in plan_screen but never copied into the final profile map → home
  completeness nudge falsely flagged "Injuries" for every new user).
- **Legacy chat fallback:** the pre-PR-Y chat-based flow is still reachable at
  `/onboarding/chat` (`onboarding_chat_screen.dart`). Retained for rollback only.
- **Auth redirect gotcha:** `GoRouter._authRedirect` uses
  `location.startsWith('/onboarding')` (NOT `location == '/onboarding'`), so taps on
  `/onboarding/identity` / `/goal` / `/stats` / `/details` / `/plan` aren't bounced back to
  Welcome. This was the nav bug fixed in commit `17faa86`.
- **Inference fallback:** `plan_screen._onReportForDuty` keeps the old switch-expression
  inference rules as fallback for fields missing from `widget.data` (legacy chat users,
  deep-links, corrupted route extras). Fallback must never become the default path. The
  DOB path falls back to `DateTime(now.year - age, ...)` when `date_of_birth` is missing
  and `age` happens to be present — only legacy chat users hit this.
- **Plan-screen preview uses canonical `BmrCalculator.calculateTargets`** (APK-test-1-batch,
  2026-04-24). `_computeTargets` in `plan_screen.dart` passes every real input from
  `widget.data` (weight, height, DOB-derived age, sex, activity_level, goal, pace_preference,
  target_weight_kg, body_fat_pct) and returns `targets.dailyCalories` + `targets.proteinGrams`
  verbatim. Weight delta is `target - current` rounded, with `HOLD` when abs(diff) < 0.5. The
  preview numbers now exactly match what `completeOnboarding` will write to the profile — no
  "plan screen shows X, saved profile gets Y" drift. Pre-2026-04-24 this used a reduced
  goal-only formula (`weight × 32 + 250` for build_muscle, `weight × 2` for protein) that
  ignored half the inputs.
- **Body fat is optional with blank default** (APK-test-1-batch). `stats_screen.dart`
  controller seeds to `''` (was `'18'`), label reads `BODY FAT % · OPT`, hint shows em-dash
  ghost when empty. When blank, `BmrCalculator` falls back to Mifflin-St Jeor (weight +
  height + age + sex) which is accurate enough for onboarding; the old "we'll estimate at
  18%" snackbar was misleading (no estimation happens — Mifflin-St Jeor doesn't use body
  fat at all) and has been rephrased to "Skipping body fat — using weight + height. Scan
  later from Profile to refine."
- **Details step CTA is `CONTINUE →`, not `CALIBRATE PLAN →`** (APK-test-1-batch). Pre-2026-
  04-24 the Stats → Details navigation button was labelled "CALIBRATE PLAN", misleading since
  plan calibration doesn't happen until REPORT FOR DUTY on step 05. Renamed to `CONTINUE →`;
  behavior unchanged.
- **Details screen layout uses equal-height sections with in-section fade**
  (APK-test-1-batch). Experience + Pace render as `_FadeRow` (3 compact rows each; unselected
  at 45% opacity + `textGhost` code). Days/Week + Equipment render as `_ChipRow` (single
  horizontal row of 4 pills). Defaults are pre-selected: Intermediate / Balanced / 4 days /
  Basic gym. Layout is tuned for 360×640 dp with a `SingleChildScrollView` safety net; if
  a future change adds a 5th section, it will scroll. Custom `_FadeRow`/`_ChipRow` widgets
  live in `details_screen.dart` (not Wardroom primitives) — if reused elsewhere, promote to
  `lib/shared/widgets/wardroom/`.
- **Identity screen name field auto-focuses with inline validation** (APK-test-1-batch).
  `autofocus: true` pops the keyboard immediately, `textCapitalization.words` title-cases as
  you type, `_nameError` state + `_nameAllowed` regex (letters/spaces/`.-'`) enforce min 2 /
  max 40 chars on CONTINUE tap. Error clears automatically when the user resumes typing.
  DOB still uses a snackbar for missing-field feedback (no inline error surface on the date
  tile).

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
- AI Coach — 30 days free (15 msg/day, Gemini 2.5 Flash)
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
- Unlimited AI coach (Gemini 2.5 Flash — no daily cap, no trial window)
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
- **Subscription status:** `SubscriptionService.isPro()` + `gate()` are the ONLY entry points. Never read `configBox.get('isPro')` directly from a widget. High-value features (`phases_2_to_12`, `ai_coach_unlimited`, `progress_photos`) go through `verifyFromServer()`.
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
4. **Two-tier polling with plan filter:** Client polls by exact `razorpay_payment_id` (attempts 0-11), then falls back to any active subscription for the SAME PLAN (monthly/yearly) created in last 5 minutes (attempts 12-14). The plan filter is the safety rail against a monthly→yearly upgrade matching the stale monthly row (audit H5, 2026-04-18). `razorpay_service.dart:374-384`.
5. **Webhook idempotency:** `razorpay-webhook` handles replay attempts safely:
   - **5-minute replay window (audit C4a, 2026-04-18):** After HMAC verification, the webhook rejects any event where `paymentEntity.created_at` is more than 5 minutes old with a 400. Razorpay's retry policy sends webhooks within seconds; anything older is either a replay attack or a lagging event we've already processed. `razorpay-webhook/index.ts:185-210`.
   - **Pre-SELECT** `subscriptions` table by `razorpay_payment_id` BEFORE the INSERT. If a row exists, return 200 immediately with `alreadyProcessed: true` and skip promo redemption.
   - **23505 race fallback:** If two webhook replays race past the pre-SELECT, the second INSERT hits the unique constraint on `razorpay_payment_id` → Postgres throws `23505`. The function catches this code specifically and returns 200 (treats as success).
   - **Promo redemption guard:** `increment_promo_used_count` RPC is ONLY called when `alreadyProcessed === false`. Prevents a replayed webhook from double-incrementing `used_count` and burning the promo for nobody.
   - Razorpay retries webhooks aggressively (up to 24h on non-200). Without idempotency, every retry would write a duplicate subscription row AND re-redeem the promo. Never remove the pre-SELECT or the 23505 catch.
6. **verify-payment rate limit (audit C4b, 2026-04-18):** 20 calls per user per 10 minutes, counted via `ai_coach_interactions` rows with `channel='verify_payment_attempt'`. Over-limit returns 429 with `Retry-After: 600`. Protects Razorpay API quota from a runaway client polling on every tick. `verify-payment/index.ts:178-225`.
7. **Promo codes use year-suffix for annual reuse:** `promo_code_uses` has `UNIQUE(code, user_id)` (migration 023, 2026-04-18). A user who redeems `INDEPENDENCEDAY2026` cannot re-redeem the same code the next year — marketing must generate new codes per campaign (`INDEPENDENCEDAY2027`, etc.). Keeps accounting clean and enables per-year attribution.

---

## 17. EXERCISE LIBRARY

250 exercises seeded in bundled JSON. Categories:
- Push (~35), Pull (~35), Legs (~40), Core (~25)
- Cardio (~20), Flexibility (~30), Calisthenics (~10)
- Indian Traditional (5): Dand, Baithak, Surya Namaskar, Malkhamb, Hindu Warrior Flow

Every exercise has: coaching_cues, common_mistakes, breathing_cue, warmup_protocol, pro_tip, MET_value, logging_type, difficulty, suitable_for, regression/progression links, image URLs.

### V4 Fields (on every exercise)
| Field | Type | Purpose |
|-------|------|---------|
| `movement_pattern` | string | One of 11 pipeline patterns (+ cardio/warmup/cooldown/flexibility for non-pipeline) |
| `target_focus` | string | Granular muscle target (e.g., "Lats (Width)", "Biceps (Short Head)") |
| `equipment_tier` | string[] | Subset of: bodyweight, home_dumbbells, basic_gym, full_gym |
| `rep_range` | string | Exercise-specific rep prescription (e.g., "5-8", "8-12", "12-15") |
| `priority_tier` | int | 1 (primary compound), 2 (secondary), 3 (accessory isolation) |

---

## 18. FOOD DATABASE

**93 Indian-first foods** bundled in `assets/data/food_database.json` (NOT 5,000 — earlier doc claim was aspirational; actual seed is 93). Same 93 rows are mirrored to Postgres `food_database` table (migration 030, 2026-04-20) so server-side tools like AI coach `suggestMeal` can query them.

Categories cover staples, street food, restaurant dishes, dairy, pulses, protein, fruits/veg, beverages.

Community growth: User adds custom food → Hive + Supabase. Admin approves → promoted to global DB. Other users get it via periodic sync + app updates.

**Re-seeding:** if the bundled JSON is updated, regenerate migration via `node scripts/seed_food_database.js` then apply. Idempotent (deterministic v5 UUID per CLAUDE.md §7 namespace).

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
| Stale "Chat/Reasoning" toggle in AI coach header | Removed 2026-04-18. If you see this pill in a fresh APK, the `_buildStatusPill` in `ai_coach_screen.dart` didn't ship — single-pill header is the current design. |
| SSRF via ai-media-proxy | Only allow `${SUPABASE_URL}/storage/v1/object/` prefix URLs. Never fetch arbitrary user-supplied URLs server-side. |
| Null expiry grants PRO | `isPro()` returns `kDebugMode` when `expiresAt` is null — release builds treat null as free. Never remove this guard. |
| Promo code enumeration | `validate-promo` requires JWT auth. Never expose promo discount_pct to unauthenticated callers. |
| Subscription bypass via Hive | `gate()` calls `verifyFromServer()` for high-value features (`phases_2_to_12`, `ai_coach_unlimited`, `progress_photos`). Never rely on local-only check for these. Any feature that writes to Storage or spends cloud resources on the user's behalf MUST be server-verified. |
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
| Fixed-delta kcal ignores user pace | `BmrCalculator.calculateTargets` requires `pacePreference` (slow/balanced/aggressive). Deficit/surplus back-computed from `current_kg × pace_rate × 7700 / 7`. Never reintroduce fixed `+300 / -500` deltas — they ignore the user's chosen pace. |
| Missing projection on MY TARGETS | Both `profile_screen._buildNutritionTargets` and `nutrition_screen._buildProjectionSubtitle` must read `current_weight_kg`, `target_weight_kg`, and `pace_preference` from the user profile. Projection only shown for `lose_fat`/`build_muscle` goals with non-zero gap. |
| Food log delete with no undo | `nutrition_screen._confirmAndDeleteFoodLog` is the ONLY delete surface. Stashes log before delete; `restoreFoodLog` writes back at deterministic key `flog_<loggedAt>_<foodNameHash>`. Never call `deleteFoodLog` directly from a widget. |
| Gradle build hangs silently | Check `android/gradle.properties` — `-Xmx` must be ≤4G on 16GB system. 8G causes OOM with no terminal output. Check for `android/hs_err_*.log` crash dumps. Also remove stale `flutter/bin/cache/lockfile` if Flutter commands hang on lock. Use `/build-apk` skill. |
| Plan generator picks wrong-target exercise | Cascade attempt3 drops `target_focus` + `exercise_type`, keeping only `movement_pattern` — results in a push instead of a chest-specific push. Root causes: (a) exercise library pool too shallow for the slot's triple, or (b) for Phase 1 beginners, `suitable_for` too restrictive (needs "Beginner" + `is_foundational: true`). Fix: either expand library `suitable_for` on the missing exercise OR adjust `split_resolver.dart` slot ordering so beginners don't hit the shallow pool at P1/P2. Verify with `dart run test/plan_generator/sample_plans_report.dart` (target: 0 attempt3/universalPool/none). |
| Plan generator returns wrong number of exercises | `VolumeFilter` uses `slots.take(targetCount(experience, daysPerWeek))` — depends on `split_resolver` emitting enough P1-P5 slots in priority order. If a split returns fewer slots than the advanced target (10 for 3-day), users get truncated output silently. When adding/reordering a split, count slots and confirm it covers the advanced case. |
| Pike Push Up assigned to rear delt slot | Sign that cascade exhausted `attempt1-4` and fell to `universalPool`. Indicates too many slots of the same muscle/pattern/type across the week — library pool depth insufficient. Cap rear delt slots to 3/week, lateral delt to 3/week, front delt to 1/week (current library depth). Fix in `split_resolver.dart`, NOT by editing the universal pool. |
| Free user stuck on day 29 with empty schedule | Check `WorkoutScheduleService.isPhaseExpired()` returns true AND `todayWorkoutProvider` is null → `home_screen._buildTodayRow` must render `PlanExpiredCard` (3 doors: Upgrade / Build custom / Re-do Week 4). PRO users auto-generate next Phase on splash via `splash_screen._autoGenerateNextPhaseForPro()` so they never land here. Added 2026-04-18 per audit H9. |
| Progress-photo upload fails with PhotoQuotaException | Daily cap exceeded. Free: 2/day, PRO: 5/day. Enforced at `ProgressPhotoRepository.capture` by counting today's `progress_photos` rows for the user BEFORE pick. UI should catch `PhotoQuotaException`, surface the paywall for free users (`feature: 'progress_photos'`) or a "come back tomorrow" snackbar for PRO. Image quality differs by tier too: 2048/85% free, 3000/95% PRO. |
| Cerebras/OpenRouter calls anywhere | ALL AI traffic moved to Gemini on 2026-04-18 (commit `7646200`). `_shared/openrouter.ts` is deleted; `_shared/gemini.ts` is the only helper. If you see `api.cerebras.ai` or `openrouter.ai` URLs in a new Edge Function, it's regression — route through `geminiChat(...)` instead. |
| `ai-proxy-pro` or `video-status` 410 Gone | Both retired (2026-04-18). `ai-proxy-pro` merged into `ai-proxy` (single Gemini endpoint with server-side `isPro` gate). `video-status` deferred with the video-share feature. Callers should not re-add either; if the video feature ever un-defers, rewrite `video-status` with JWT + user_id filter before deploying. |
| Hive file bloat over time | `HiveService` implements `WidgetsBindingObserver` and runs `box.compact()` on 7 mutation-heavy boxes (user / workout / nutrition / health / custom / coach / sync) every 7 days on `AppLifecycleState.paused`. Gated via `configBox['last_compact_at']`. If disk usage keeps climbing, confirm the observer is registered in `init()` and the gate is being checked. |
| food_text_analysis 429 when user is below daily cap | Trigger `trg_food_text_rate_limit` on `ai_coach_interactions` (migration 024, 2026-04-18) enforces the 50/day free / 200/day PRO cap atomically. Insert-first pattern — `ai-proxy` inserts a placeholder row BEFORE calling Gemini. If trigger raises `food_text_daily_limit_reached` (SQLSTATE P0001), return 429. Do NOT re-add a separate check-then-insert pre-check; the trigger is the single source of truth. |
| Stepped onboarding bounces back to Welcome on every tap | `GoRouter._authRedirect`'s `isOnOnboarding` check MUST use `location.startsWith('/onboarding')`, not `location == '/onboarding'`. Sub-routes (`/goal`, `/stats`, `/plan`) would otherwise be redirected back to Welcome on every navigation. Fixed in commit `17faa86`. |
| Worktree APK build fails with "Did not find .env" | `.env` is gitignored and not copied when creating a new git worktree. Before `flutter build apk` in a new worktree, copy from the main: `cp "C:/Upendra/Claude Code/Fitness App/.env" <worktree>/.env`. Without it `SUPABASE_URL` compiles to empty string and auth crashes at startup. |
| Fraunces title emphasis not italic-gold | Don't style an entire `Text` widget italic — the non-emphasized leading/trailing words become italic too. Use `RichText` with inline `TextSpan`s carrying `fontStyle: FontStyle.italic`, `color: AppColors.accent`, `fontWeight: FontWeight.w500` on the emphasised span only. Pattern baked into `WardDispatchHeader`. |
| Wardroom palette drift | PRs K–Q used README hex values (rounded for print); PR R (commit `174ff21`) reconciled `colors.dart` to the JSX `const W = {}` in `Knowledgebase/Avya App redesign/design_handoff_wardroom/src/wardroom-tokens.jsx`. The JSX is the truth. Never back-port README hex values into `colors.dart`. |
| Streak banner fires at 3 PM for a morning lifter | `StreakWarningBanner.shouldShow` (and mirror in `home_provider.StreakWarningEligibilityNotifier._evaluate`) clamps threshold to `[18, 23]`. Handoff is an **evening-only** nudge. Don't re-lower the floor to 15 — an early-riser (6 AM median → raw 9 AM) would surface the banner before dinnertime. Both callsites must stay in sync. |
| Diet-plan meals not visible on nutrition screen | `TodaysMealsCard` renders "FROM YOUR DIET PLAN" hint on empty slots via `dietPlanProvider` (reads `configBox['saved_diet_plan']`). If hints don't show after a user saves a plan, confirm `diet_plan_screen._savePlan` still calls `ref.invalidate(dietPlanProvider)` after `saveDietPlan`. Tap-to-log pre-fill depends on `showFoodSearchSheet(initialQuery: planned.firstFoodName)` — don't drop the initialQuery argument. |
| Weekly Report sparkline dips to 0 between weigh-ins | By design only for calories/protein/workouts (zero-fill = genuinely no activity). Weight series is **forward-filled** from last known — if you see it dropping to zero on un-weighed days, `weeklyReportDataProvider` has regressed. |
| AI coach greets "Good morning." with no name | `userProfileProvider['full_name']` is null or still the bootstrap 'User' placeholder. Greeting falls back silently; no bug. If a real name is in Hive but the greeting still reads generic, verify `userProfileProvider` is returning the latest map (should invalidate on profile edits). |
| Superset A / rest timer still shows cyan after palette rotation | `train_provider.supersetColor()` and `RestTimerData.timerColor` used hardcoded `Color(0xFF00D4FF)`. PR AH.C1 swapped to `AppColors.accent`/`warn`/`bad`. Any new hardcoded color literal in a shared provider is a token-hygiene regression — grep `0xFF00D4FF` / `0xFF07090e` / `0xFFeef2f7` periodically. |
| Profile completeness nudge stuck on "Injuries" for new users | `completeOnboarding` in `onboarding_provider.dart` MUST copy `injuries`, `diet_preference`, `body_fat_percent`, `start_date` (as `startDateKey` — don't collide with the DateTime-typed `startDate` used for scheduling), and `city` from `state.answers` into the saved profile map. Before 2026-04-24 these were set via `setAnswer` in `plan_screen` but never persisted → `userBox['profile']['injuries']` was null → `profileCompletenessProvider.val is List` check failed → "Injuries" flagged missing indefinitely. Fixed on `feat/onboarding-train-nutrition` 2026-04-24. |
| Injuries round-trips to cloud as `"[none]"` string | `onboarding_provider._syncOnboardingToSupabase` must pass `profile['injuries']` directly (a List<String>), NOT `.toString()` it. `supabase_flutter` serializes the List to a Postgres `text[]` literal. Pre-2026-04-24 code called `.toString()` → string `"[none]"` landed in the cloud `text` column → cross-device restore merged it back into Hive as a String → completeness check broke again. Paired with migration 033 which moved the column from `text` → `text[]`. |
| RECOMP / PERFORM wrap to 2 lines on Goal screen | `WardRadioRow` left-label column was fixed at 44 dp; with `AppTypography.mono` 10sp + 2px letter-spacing, 6+ char codes overflowed. Fixed 2026-04-24 by widening to 56 dp and adding `maxLines: 1, softWrap: false, overflow: clip`. If you add a new `rowKey` longer than 7 chars, either shorten it or bump the column width again. |
| Cross-account Hive leak on fresh sign-up | Android Auto Backup was default-enabled (no `allowBackup="false"` / `dataExtractionRules` in AndroidManifest), so Hive files survived reinstall on any device signed into the same Google account — prior user's templates / logs / coach memory showed up on a fresh account. Fixed 2026-04-24 with `data_extraction_rules.xml` excluding `app_flutter/` + `splash_screen._runDeferredInit` startup check that clears Hive + signs out when `userBox['profile']['id']` ≠ `currentUser.id`. Both layers required; removing either re-opens the leak. |
| Train screen week chips / "No stats yet" card narrow | Both had children sized to content because parents used `CrossAxisAlignment.start` or fixed-width scrollable chips. Fixed 2026-04-24: `week_selector.dart` swapped `ListView.separated` for `Row`+`Expanded`; `stats_grid.dart` parent Column flipped cross-axis to `stretch`. Any future similar "card sitting narrow on Train" regression will be the same class of bug. |
| Fiber invisible to AI coach | Hive has always stored `total_fiber` on `nlog_*` rows and the UI showed a fiber bar, but `nutrition_logs` had no `total_fiber` column (migration 003 omission) and `_getTodayNutrition()` only summed cal/P/C/F. AI coach couldn't reference fiber intake. Fixed 2026-04-24: migration 034 adds the column; `_syncNutritionLogs` projects it; `_getTodayNutrition` returns `fiber_g` + `fiber_target_g: 30` in the snapshot. Gemini picks up the keys automatically via JSON-stringified snapshot — no prompt edit needed. Historical rows default to 0 since `nutrition_log_items` has no fiber column to backfill from. |
| Nutrition page's "Search 5,000+ foods" is a lie | Actual seed is 93 per §18. Copy was trust-breaking. Corrected 2026-04-24 to `"Search foods"` in both `nutrition_screen.dart` and `food_search_sheet.dart` empty state. If the library ever grows past a few hundred items, revisit. |
| PRO + "renews <date>" visible on fresh free-tier account | Same Auto Backup leak class as the template/Hive bug: a previous PRO user's `configBox['isPro']=true` + `configBox['expiresAt']=<end_date>` survived via Google Drive backup onto a new sign-up. The Supabase `subscriptions` table had no row for the new user, but the UI read `subInfo.expiresAt` directly and showed the old account's renewal date. Fixed 2026-04-24 on three layers: (1) Auto Backup disabled via `data_extraction_rules.xml`; (2) `isPro()` now runs Hive-profile.id vs session.id check on every call and force-downgrades on mismatch; (3) `_downgradeLocally` wipes `_expiresAtKey`, `_planKey`, `localActivationAt`, `_lastVerifiedKey` — not just the `_isProKey` flag — so stale display data can't survive. All three layers required to close the class. |
| Built APK via `flutter build apk` directly | Always use the `/build-apk` skill. `flutter build apk` can hang silently on this machine (16 GB system, `-Xmx4G` Gradle heap) without emitting output. The skill does pre-flight cleanup (stale `flutter/bin/cache/lockfile`, Gradle caches, JVM crash dumps at `android/hs_err_*.log`) that prevents the hang. Direct Bash `flutter build apk` skips that and occasionally costs 30+ min of debug. See memory `feedback_use_build_apk_skill.md`. |
| Mutation writes Hive but skips sync — AI coach sees stale context | Every write path that crosses a synced domain MUST fire `unawaited(SyncService.instance.syncX())` + `unawaited(SyncService.instance.pushSnapshot())` after the Hive put + provider invalidation. Audited 2026-04-24 (PR-FIX-1, commit range `cee054a`..merged): 10 gaps closed — `completeWorkout`, `submitWorkoutDraft`, `DeleteNutritionLogNotifier.delete`, `edit_profile_screen._save`, `swap_sheet._onConfirm`, `_logSleep`/`_logMeasurement`, `BiometricNotifier.logSleep`, `saveMealPreset`/`deleteSavedMeal`, `addCustomFood`, `extractAndSaveCoachingNotes`, splash `checkAndSync`. Regex-based regression tests live in `test/sync/sync_gap_test.dart` — do not delete. |
| Raw `Hive.box('name')` in a cold-start-reachable path | Always use `HiveService.instance.<nameBox>`. Raw `Hive.box()` throws `HiveError: Box not found` if evaluated before `HiveService.init()` finishes (slow device, deep-link cold start). Closed 2026-04-24 (PR-FIX-2, merged) in `sign_in_screen`, `terms_modal`, `ai_coach_repository` (4 sites), `progression_resolver`. Regression tests in `test/safety/`. |
| `featureActiveWorkoutMode` is PRO on paper, free in practice | Both START WORKOUT entry points in `train_screen.dart` now route through `SubscriptionService.instance.gate(AppConstants.featureActiveWorkoutMode, ...)`. If you add a new entry point to the active workout flow, you MUST gate it — `test/subscription/active_workout_gate_test.dart` asserts at least 2 gate calls + zero direct `context.go('/train/active-workout')` without a gate. Closed 2026-04-24 (PR-FIX-3). |
| Onboarding "ADJUST PLAN" silently skipped Details screen | `plan_screen.dart` "ADJUST PLAN" now routes to `/onboarding/details` (was `/onboarding/stats`, bypassing the whole Details step). Stats BACK button now carries current controller values (`_weight`, `_targetWeight`, `_height`, `_bodyFat`, `_activity`) forward so edits survive round-trip. Plan targets card reads `days_per_week` from `widget.data` rather than hardcoding from goal. Closed 2026-04-24 (PR-FIX-4). |
| Force-unwrap `!` on map keys or `.first` on possibly-empty lists | Null-safe the map read (`(m['k'] as num?)?.toDouble() ?? 0.0`) and always guard `.first` with `isNotEmpty`. Closed 2026-04-24 (PR-FIX-2) in macros maps (home_provider + nutrition_provider), `exercise_type.first` (3 files), `sentences.last`, `options.keys.first`, `diet_plan_screen` shuffle result, `todayDay!` in train_screen. |
| "Failed to generate referral code" on fresh accounts | `referral_codes.user_id` FK pointed at `public.users(id)`, but the Invite-Friends flow fires before onboarding sync populates `public.users` — so new testers hit silent FK violations on all 5 insert retries. Migration 035 (2026-04-24, APK-test-1-batch) drops the FK and re-adds it against `auth.users(id)` + adds `UNIQUE(user_id)`. This is the ONLY user-scoped FK pointing at `auth.users` — do not normalize it. |
| Prediction card renders raw JSON | Gemini occasionally returns JSON-shaped responses (`{"predictions":[{...}]}`) even when the prompt asks for plain prose. Two-layer defense: (1) both prediction prompts in `prediction_service.dart` + `onboarding_provider.dart` carry explicit "DO NOT return JSON. DO NOT wrap in code fences. DO NOT include keys like predictions/timeframe/summary"; (2) `PredictionNotifier._sanitisePredictionText` in `ai_coach_provider.dart` detects `{`/`[`/` ``` ` prefixes, JSON-parses, extracts `summary`/`tagline`/`text`/`prediction`/`predictions[0].summary`, and WRITES the cleaned value back to Hive so the decode runs at most once per stored value. Fallback strips common JSON syntax. Never render `configBox['prediction_text']` without this guard. |
| Forgot-password link invisible on email sign-in screen | Pre-2026-04-24 the "Forgot password?" link lived only inside `_buildWelcomeView` (the pre-email, three-button landing view) in `sign_in_screen.dart`. Once a user tapped CONTINUE WITH EMAIL and committed to the email form, the link was gone — exactly when they'd realize they forgot the password. Fixed in APK-test-1-batch: duplicated the `GestureDetector → ForgotPasswordSheet.show` into `_buildEmailView` directly below the SIGN IN button, guarded by `if (!_isSignUp)` so it doesn't show during sign-up. Web redirect (to `icanbefitter.vercel.app/reset`) unchanged; in-app deep-link completion still deferred (F2). |
| Swap → "+ ADD EXERCISE" opens a picker instead of a create form | Pre-2026-04-24 the `__ADD_MODE__` sentinel in `active_workout_screen._showSwapSheet.onAdd` called `_showExercisePickerSheet` which opened the existing-exercise search sheet — user then had to pick/search and manually re-swap after. Fixed via `_openCreateAndAutoSwap`: on the sentinel, opens `CreateCustomExerciseSheet` directly. On save, auto-swaps the new exercise into the captured slot (preserves weight/rest from the original), invalidates `todayWorkoutProvider + currentPlanProvider + calendarWeekProvider`, and shows a 5s snackbar with UNDO that calls `swapExercise(index, original)` to restore. Do NOT revert to the picker path — it's a 2-tap vs 1-tap regression. |
| Custom exercise created but not visible in My Submissions | Two distinct failure modes: (a) `MySubmissionsScreen`/`_MySubmissionsBody` filters to `submitted_to_library=true`, so DRAFT exercises (user didn't tick "Share with AVYA community") never appear there — by design; (b) fire-and-forget `unawaited(SyncService.instance.syncCustomItemsNow())` can be interrupted by the user immediately backgrounding the app. The UX fix is D6 on Train: `_buildYourExercisesSection` uses `ValueListenableBuilder<customBox>` so the new exercise shows up instantly as a chip with `DRAFT`/`PENDING`/`APPROVED` badge regardless of submission state. The sync fix is observability: `_projectCustomExercise` already whitelists columns (since 2026-04-18), and `_syncCustomItems` now logs the payload in `kDebugMode` + the exercise name on errors. |
| Plan-screen preview numbers disagreed with saved profile | `_computeTargets` used to run a reduced goal-only formula (`weight × 32 + 250` for build_muscle, `weight × 2` for protein) that ignored body_fat, height, activity, and pace. Saved profile went through `BmrCalculator.calculateTargets` with all inputs → different numbers on preview vs DB. Fixed in APK-test-1-batch: preview calls the canonical `BmrCalculator.calculateTargets` with every input from `widget.data` (weight, height, DOB-derived age, sex, activity, goal, pace, target_weight, body_fat_pct). Weight delta is now `target - current` rounded, with a `HOLD` special case when abs(diff) < 0.5. Only `days_per_week` keeps a goal-based fallback (for legacy chat-flow deep-links). |
| Submissions entry confusing — two separate rows | Pre-APK-test-1-batch Profile showed "Review Community Items" (bottom sheet) + "My Submissions" (route) as two separate rows under SHARE & GROW. Testers kept tapping "Review Community Items" expecting to see their own submissions too. Consolidated into a single `Submissions` row at `/profile/submissions` which opens `SubmissionsScreen` with a 2-segment pill toggle: MY SUBMISSIONS + COMMUNITY REVIEW. Uses a handrolled pill (not Material `TabBar`) styled like `WardChip` since the old coach-screen `_buildStatusPill` primitive was deleted 2026-04-18. Legacy `/profile/my-submissions` route kept for deep-link safety — will be retired after one release cycle. |
