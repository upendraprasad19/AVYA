# Naming Conventions & Reserved Domain Glossary

> **Read this before introducing any new feature name, Hive key prefix, cloud column, provider, or domain term.**
> Companion: `docs/sot_registry.yaml` (machine-readable single-source-of-truth registry).

---

## 1. Why this doc exists

Naming collisions and silent renames have been the single largest class of recurring bugs on this codebase. Examples:

- **APK Test #11 / L1 (2026-05-04):** Founder reported "AI breakdown card said the meal didn't log." Root cause turned out to be UI-only (no save toast), but the investigation surfaced that consumers were referring to a **`meal_name`** field on `nutrition_logs` rows that **does not exist** — the canonical label field is **`meal_type`** (breakfast / lunch / dinner / snack). Rendering code that read `row['meal_name']` showed "Unknown" silently.
- **APK Test #8 (2026-05-03):** Receipt rendered "0 sets · 26 reps" because the WriteService wrote `set_number` but the receipt reader (and 4 separate `ai_coach_repository` consumers) read the legacy `sets_completed` field. ~10 days of silent AI-snapshot regression.
- **APK Test #12 / Theme A:** `formatDateKey` produced UTC dates; WriteServices wrote IST dates. Receipt for May 4 contained May 5 exercises until the helper was rerouted through `istDateStr`.

Every one of those bugs would have been caught at PR review if writers and readers had been written against a shared, enumerated naming contract. **This doc IS that contract.** New features that introduce a name not listed here either:

1. Add the name to the appropriate registry below in the same PR, AND
2. Update `docs/sot_registry.yaml` if the new name is consumed in more than one place.

---

## 2. File + class naming

### Files

- **All source files: `snake_case.dart`.** No camelCase, no kebab-case.
- Test files mirror `lib/` layout under `test/` and end with `_test.dart`. Example: `lib/core/services/sync_service.dart` → `test/core/services/sync_service_test.dart`.
- Contract tests (writer↔reader pinning) live under `test/contracts/<x>_test.dart`.
- Edge Function source: `supabase/functions/<kebab-case-fn>/index.ts`. Shared helpers under `supabase/functions/_shared/<snake_or_camel>.ts`.
- Migrations: `supabase/migrations/NNN_short_description.sql`. NNN is a zero-padded sequence number; new migrations get the next free number. (Phase-B and a handful of date-stamped legacy ones use `YYYYMMDD000001_*.sql` — do not introduce more of that style.)

### Classes

- **PascalCase**. No abbreviations except the established acronyms below.
- **Reserved acronyms** (always uppercase even when embedded mid-name):
  `AI`, `API`, `APK`, `BMR`, `BMI`, `CTA`, `CNS`, `CRUD`, `DOB`, `DPDP`,
  `DUP`, `ICANBEFITTER` (legal name; `AVYA` is the brand), `IST`, `JWT`,
  `MET`, `OTP`, `PNG`, `PR` (personal record), `PRO` (subscription tier),
  `RPC`, `RPE`, `SoT` (Source of Truth), `SSRF`, `TDEE`, `TTL`, `UUID`,
  `XHR`. Examples: `JwtRefresher`, `BmrCalculator`, `PrDetectionService`.
- Riverpod state classes: `<Concept>Data` (e.g. `SubscriptionInfoData`, `ActiveWorkoutData`, `WeightEntryData`).
- Riverpod notifiers: `<Concept>Notifier` (e.g. `ChatHistoryNotifier`, `StreakFreezeNotifier`, `SendMessageNotifier`).
- Service singletons: `<Concept>Service` (e.g. `SyncService`, `WaterTargetService`, `WorkoutWriteService`, `RankService`).
- Repositories: `<Concept>Repository` (e.g. `UserRepository`, `SubmissionsRepository`, `WorkoutRepository`).
- Wardroom UI primitives: `Ward<Concept>` (see §6).

---

## 3. Hive

### 3.1 Boxes

Box constants live in `lib/core/services/hive_service.dart` as `static const String <name>BoxName = '<name>Box'`. **The current closed set:**

| Constant            | Box name           | Purpose                                                 |
|---------------------|--------------------|---------------------------------------------------------|
| `userBoxName`       | `userBox`          | User profile, preferences, progress (per-user scope)    |
| `workoutBoxName`    | `workoutBox`       | Workout logs, schedules, templates, exercise logs       |
| `nutritionBoxName`  | `nutritionBox`     | Nutrition logs, saved meals                             |
| `healthBoxName`     | `healthBox`        | Weight, measurements, streaks, sleep, water, urine, steps |
| `exerciseBoxName`   | `exerciseBox`      | Seeded exercise library (read-mostly)                   |
| `foodBoxName`       | `foodBox`          | Seeded food database (read-mostly)                      |
| `customBoxName`     | `customBox`        | User custom exercises + foods                           |
| `coachBoxName`      | `coachBox`         | AI coach interactions, coaching notes, induction state  |
| `syncBoxName`       | `syncBox`          | Last-sync timestamps, pending sync queue                |
| `configBoxName`     | `configBox`        | Subscription + feature flags + small shared config      |
| `notificationsBoxName` | `notificationsBox` | Notification inbox entries                            |
| `migrationBoxName`  | `migrationBox`     | One-shot migration completion flags (private)           |

**Naming rule for new boxes:** snake_case + `Box` suffix on the constant; the box name string matches. No abbreviations.

### 3.2 Per-user vs shared

Since APK Test #11.1 (2026-05-05), most user-specific boxes open **per-user** via `HiveUserSession` (boxes named `<base>_<userId>` on disk; the constant still reads as the base name in code). User-scoped data MUST go through `MigratedKey.read/write/delete` (in `lib/core/services/migrated_key.dart`) — never write directly to the shared `configBox` for anything user-specific. See docs/architecture/sync.md "User-scoped Hive keys" for the 31-key migrated set and the two intentionally-shared exceptions (`pending_referral_code`, `logout_in_progress`).

### 3.3 Hive key prefix registry (CLOSED SET)

Every Hive key composed from a prefix lives here. **Never reuse a prefix for a different concept. Never abbreviate. Never invent a new prefix without adding it to this table AND `docs/sot_registry.yaml`.**

| Prefix                        | Format                              | Box           | Concept                                    |
|-------------------------------|-------------------------------------|---------------|--------------------------------------------|
| `exlog_`                      | `exlog_<istdate>_<exerciseHash>`    | workoutBox    | Exercise log per (date, exerciseName)      |
| `exercise_log_index_`         | `exercise_log_index_<istdate>`      | workoutBox    | List of exlog keys for that date (O(1) lookup) |
| `wlog_`                       | `wlog_<istdate>`                    | workoutBox    | Workout-level summary                      |
| `schedule_`                   | `schedule_<istdate>`                | workoutBox    | Schedule entry (status, exercises)         |
| `tmpl_`                       | `tmpl_<timestamp>`                  | workoutBox    | Workout template (single or multi-day)     |
| `undo_`                       | `undo_<logKey>`                     | workoutBox    | Undo stash for completed workout           |
| `nlog_`                       | `nlog_<timestamp>_<hash>`           | nutritionBox  | Nutrition log (meal)                       |
| `flog_`                       | `flog_<loggedAt>_<foodNameHash>`    | nutritionBox  | Single food log entry (delete-undo stash)  |
| `target_override_`            | `target_override_<istdate>`         | nutritionBox  | Per-day calorie target override            |
| `weight_`                     | `weight_<istdate>`                  | healthBox     | Weight log entry                           |
| `sleep_log_`                  | `sleep_log_<istdate>`               | healthBox     | Sleep log entry (one per day)              |
| `water_ml_`                   | `water_ml_<istdate>`                | healthBox     | Daily water total in ml                    |
| `urine_color_`                | `urine_color_<istdate>`             | healthBox     | Urine color self-report                    |
| `hydration_`                  | `hydration_<istdate>`               | healthBox     | Hydration aggregate snapshot               |
| `steps_today` / `steps_date`  | (literal keys, not prefixed)        | healthBox     | Today's step count + the IST date it covers |
| `streak_freezes_*`            | `streak_freezes_available` / `streak_freezes_used_dates` / `streak_freezes_last_refill` | userBox (via `user_progress`) | Streak-freeze state |
| `streak_progress_version` (literal) | `streak_progress_version` | userBox (via `user_progress`) | Unit 3b (e6b9c4) — whole-row optimistic-lock counter shared by BOTH `update_streak_progress` and `update_user_progress_snapshot` RPCs (one row per user). Written by `SyncService._stampProgressVersion` after either RPC succeeds; read as `expected_version` on the next call. |
| `coach_`                      | `coach_<DateTime.now().millisecondsSinceEpoch>` | coachBox | AI coach chat interaction row (backfilled here 2026-07-30, Unit 8 — the prefix predates this table). Fields include `user_message`, `ai_response`, `mode`, `pending`, `failed`, `media_url`, `media_type`, plus two Unit 8 (coach-media-consent, OI-25) additions: `media_storage_path` (raw `chat-media` Storage path, stable beyond `media_url`'s 600s signed-URL TTL) and `media_save_state` (`null` \| `'saved'` \| `'declined'` — the user's save-consent decision). Canonical writer `CoachInteractionRepository`. Both new fields are LOCAL-ONLY — `_syncCoachInteractions` pushes a fixed column subset that excludes them, so they never reach cloud `ai_coach_interactions`. |
| `pending_sync_`               | `pending_sync_<opId>`               | syncBox       | Outbox row in pending sync queue           |
| `last_*` (literal)            | `last_community_sync` etc.          | syncBox       | Last-sync timestamps per surface           |
| `coach_memory` (literal)      | `coach_memory`                      | coachBox      | Single-row coach memory blob               |
| `coaching_notes` (literal)    | `coaching_notes`                    | coachBox      | Server-extracted facts                     |
| `committed_at` / `committed_to_lt_cdr` / `induction_completed_at` | (literal) | coachBox | Induction-pledge state |
| `fitness_summary` (literal)   | `fitness_summary`                   | coachBox      | Pre-computed AI snapshot section           |
| `current_plan` (literal)      | `current_plan`                      | workoutBox    | Active phase plan map                      |
| `recent_deletes` (literal)    | `recent_deletes`                    | nutritionBox  | Tombstones for cross-device dedup          |
| `custom_exercises` / `custom_foods` (literal lists) | — | customBox | Legacy list-keys; new writes go to per-id keys |
| `rank_promotions_history` (literal) | `rank_promotions_history`     | userBox       | Last 20 rank promotions (mirror of cloud)  |

`<istdate>` is always `YYYY-MM-DD` formatted via `istDateStr(...)` from `lib/core/utils/ist_date.dart` (NEVER `DateTime.now().toIso8601String().substring(0,10)` — that's UTC). See the IST contract test at `test/contracts/format_date_key_ist_test.dart` and the feedback memory `feedback_use_ist_throughout.md`.

`<timestamp>` is `DateTime.now().millisecondsSinceEpoch` (UTC instant — fine for IDs since they're never compared as dates).

**Adding a new prefix:**
1. Append a row above with prefix, format, box, concept.
2. Add a write entry to `docs/sot_registry.yaml` if more than one reader exists.
3. If a writer field maps 1:1 to a cloud column, add the mapping to §4.4 below.

### 3.4 Hive field names (within a row Map)

Rows stored under prefixed keys are `Map<String, dynamic>`. The field name contract for the two highest-traffic prefixes is enumerated in docs/architecture/sync.md "Hive field-name contract". Quick reference:

- **`exlog_*`:** `exercise_name`, `date`, `sets[]` (List of Map), `set_number`, `reps_completed`, `weight_kg`, `volume_kg`, `logging_type`, `is_pr`, `source`, `updated_at_ms`, optional `notes`, optional `workout_log_id`.
- **`nlog_*`:** `log_key`, `date`, `meal_type`, `total_calories`, `total_protein`, `total_carbs`, `total_fat`, `total_fiber`, `items[]` (per-item: `name`, `quantity_g`, `calories`, `protein`, `carbs`, `fat`, `fiber`), `source`, `logged_at`, `created_at`.

**Renaming a field:** update the writer + every consumer in the same PR + update or add a contract test in `test/contracts/<x>_write_to_read_contract_test.dart`. The 2026-05-03 receipt-rendering bug (set_number vs sets_completed) is the canonical failure mode this contract prevents.

---

## 4. Cloud (Supabase Postgres)

### 4.1 Tables

- **snake_case plural noun** (`workout_logs`, `nutrition_logs`, `weight_logs`, `body_measurements`).
- One-row-per-user "summary" tables stay singular (`user_profile`, `user_progress`, `user_preferences`).
- Junction tables read naturally: `workout_log_exercises`, `workout_log_sets`, `nutrition_log_items`, `template_exercises`, `referral_redemptions`.

Full DDL: `docs/reference/database-schema.md`. Authoritative source: `supabase/migrations/`.

### 4.2 Columns

- **snake_case singular** (`weight_kg`, `total_calories`, `meal_type`, `created_at`, `updated_at_ms`, `is_pr`).
- Booleans prefixed `is_` or `has_`.
- Timestamps: `_at` for absolute UTC instants (`completed_at`, `created_at`), `_at_ms` for client-side millisecond epochs synced as integers (`updated_at_ms`).
- Unit-bearing numerics carry the unit: `weight_kg`, `height_cm`, `quantity_g`, `duration_secs`, `distance_km`, `volume_kg`.
- **Cloud column names MUST match Hive field names where the data round-trips.** Divergence = contract bug. The canonical mapping is §4.4 below.

### 4.3 Migration filenames

`NNN_short_description.sql` — three-digit sequence + `_` + lower_snake_case description. Examples: `019_workout_log_sets.sql`, `036_onboarding_completed_at.sql`, `046_morning_alert_personalized_delivery_cron.sql`.

Phase-B / pgvector / video-render / promo-codes used a date-stamped style (`YYYYMMDDNNNNNN_*.sql`) for historical reasons — **do not introduce more of that style.**

### 4.4 Canonical Hive ↔ Cloud field mapping

| Concept         | Hive prefix / box | Hive field        | Cloud table            | Cloud column     |
|-----------------|-------------------|-------------------|------------------------|------------------|
| Exercise log    | `exlog_*` (workoutBox) | `weight_kg`     | `workout_log_exercises`| `weight_kg`      |
| Exercise log    | `exlog_*`         | `set_number`      | `workout_log_exercises`| `set_number`     |
| Exercise log    | `exlog_*`         | `reps_completed`  | `workout_log_sets`     | `reps`           |
| Exercise log    | `exlog_*`         | `volume_kg`       | `workout_log_exercises`| (derived; not stored — recomputed on read) |
| Workout summary | `wlog_*`          | `duration_seconds`| `workout_logs`         | `duration_seconds` |
| Schedule        | `schedule_*`      | `status`          | `workout_schedule_completions` | `status` |
| Nutrition log   | `nlog_*` (nutritionBox) | `meal_type`  | `nutrition_logs`       | `meal_type`      |
| Nutrition log   | `nlog_*`          | `total_calories`  | `nutrition_logs`       | `total_calories` |
| Nutrition log   | `nlog_*`          | `total_fiber`     | `nutrition_logs`       | `total_fiber`    |
| Nutrition item  | `nlog_*` `items[]`| `quantity_g`      | `nutrition_log_items`  | `quantity_g`     |
| Weight log      | `weight_*` (healthBox) | `weight_kg` | `weight_logs`          | `weight_kg`      |
| Sleep log       | `sleep_log_*` (healthBox) | `hours`   | `sleep_logs`           | `duration_hours` |
| Water log       | `water_ml_*` (healthBox) | (int)      | `water_logs`           | `total_ml`       |
| Streak          | `streak_freezes_*` (userBox) | `available` | `user_progress`     | `streak_freezes_available` |
| Streak/progress version | `progress` map (userBox) | `streak_progress_version` | `user_progress` | `streak_progress_version` |
| Subscription    | `configBox['isPro']` | (bool)         | `subscriptions`        | `status` (active/cancelled) |
| Profile         | `userBox['profile']` | `full_name`    | `user_profile`         | `full_name`      |
| Profile         | `userBox['profile']` | `injuries`     | `user_profile`         | `injuries` (text[]) |

**Notable non-fields (do not introduce these):**
- ❌ `meal_name` on `nutrition_logs` — does not exist; use `meal_type`.
- ❌ `sets_completed` on `exlog_*` — legacy; use `set_number` (total sets) + `sets[]` (per-set detail).
- ❌ `name` on `nutrition_logs` (top-level) — meals are labelled by `meal_type` only; per-item names live in `items[].name`.

---

## 5. Riverpod

- **Provider variables: `camelCase + Provider` suffix.** Examples: `subscriptionInfoProvider`, `streakFreezeProvider`, `todayWorkoutProvider`, `aiInsightProvider`.
- **Notifier classes: `<Concept>Notifier`.** Examples: `ChatHistoryNotifier`, `WeightHistoryNotifier`, `OnboardingNotifier`.
- **State data classes: `<Concept>Data`.** Examples: `SubscriptionInfoData`, `ActiveWorkoutData`, `RestTimerData`, `CalendarDayData`.
- One provider per concept. Providers consumed by ≥2 widgets get a name short enough to type comfortably (`streakProvider`, not `currentLifetimeStreakDayCountProvider`).
- Do not suffix the Notifier with `Provider` (the variable holds the Provider; the class is the Notifier).
- Build-method callsites in widgets MUST `ref.watch(...)`. Service-layer / async / callback callsites may use `SubscriptionService.instance.isPro()` directly when reactivity isn't needed (see CLAUDE.md "Test #12 / Themes Critical C-1..C-4").

---

## 6. UI primitives (Wardroom)

- **All primitives in `lib/shared/widgets/wardroom/` use the `Ward` prefix.** Barrel-export via `lib/shared/widgets/wardroom/wardroom.dart`.
- File names follow `ward_<concept>.dart`. Class names `Ward<Concept>` (PascalCase).
- Every new primitive MUST be exported from `wardroom.dart` so consumers can do `import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';` and get everything.

**Current primitive set** (verified by `grep class Ward\w+ lib/shared/widgets/wardroom/`):

Shell: `WardFrame`.
Header: `WardLetterhead`, `WardDispatchHeader`, `WardEyebrow`, `WardRule`, `WardTabHeader`.
Surface: `WardCard`, `WardAvatar`, `WardInsightQuote`, `WardGlassGrid`, `WardDashedBorder`.
Action: `WardButton`, `WardChip`, `WardRadioRow`, `WardToggle`, `WardUnitToggle`.
Numeric: `WardBigNumber`, `WardKvRow`, `WardStatTile`.
Meter: `WardBar`, `WardSpark`, `WardRing`, `WardMultiRing`, `WardRingData`.
Structure: `WardAchievementStrip`, `WardAchievement`, `WardPhaseDots`, `WardPhaseBlock`, `WardSessionRow`, `WardSessionTable`, `WardCategorySidebar`, `WardSetChips`, `WardSetChip`, `WardStatusStrip`.
Badge / Glyph: `WardSealBadge`, `WardRankInsignia`, `WardRankPill`, `WardFreezeBadge`, plus the 5 glyph painters from `ward_glyphs.dart` (`AnchorGlyph`, `CompassRoseGlyph`, `TierChevronsGlyph`, `SealGlyph`, `RankBarGlyph`).

Two non-`Ward`-prefixed exports (legacy, scheduled for rename): `RankChip` and `RankInsignia` from `rank_chip.dart`/`rank_insignia.dart` — exported via the barrel for back-compat. New code should prefer `WardRankPill` / `WardRankInsignia`.

---

## 7. Edge Functions

- **Folder name: kebab-case.** Examples: `ai-proxy`, `verify-payment`, `redeem-referral`, `pr-detection`, `i-see-you-callout`, `morning-alert`, `delete-account`.
- Entrypoint: `supabase/functions/<fn>/index.ts` (literal filename, never `<fn>.ts`).
- Shared modules: `supabase/functions/_shared/<module>.ts` (e.g. `_shared/gemini.ts`, `_shared/captain_manual.ts`, `_shared/proactive_dedup.ts`, `_shared/ist_date.ts`). Imports MUST use `from "../_shared/..."` (parent dir). The legacy MCP tool silently mangled the path; the new `deploy_via_api.js` flow does not — see CLAUDE.md "Edge Functions — host-shell deploy" for the audit.
- Cron registrations live in the `NNN_*_cron.sql` migration that owns the function's schedule.
- Retired functions (do not call): `ai-proxy-pro`, `video-status` — both return 410 Gone.

---

## 8. Reserved domain glossary

Every term that has SPECIFIC meaning in this app. New features that use any of these terms must use them with the meaning below — never overload.

| Term | Meaning | What it is NOT |
|---|---|---|
| **equipment_access** | The user's equipment TIER — one of `bodyweight` / `home_dumbbells` / `basic_gym` / `full_gym`. A single string on `user_profile` and in `userBox['profile']`. When absent it resolves to `bodyweight` through `equipmentAccessOf()` (`lib/core/constants/equipment_defaults.dart`) — the fail-safe direction, since a bodyweight plan is performable by a gym user and the reverse is not. | NOT a capability set — a tier is a LABEL, and what the label contains is `tierItems`. NOT a permission/PRO gate. Never default it per-site: 14 sites once disagreed across four values, and because the hard floor is scoped to the bodyweight tier, a wrong default did not merely pick wrong exercises — it turned the floor OFF. |
| **equipment_owned** | Extra canonical tokens the user told us they HAVE, beyond their tier's baseline — `List<String>` on `user_profile.equipment_owned`, written by the Profile "I also have…" picker. Widens capability. | NOT the tier. NOT a wishlist — every token must be canonical (`EquipmentVocab.canonicalTokens`); an unmappable string widens nothing. |
| **equipment_exclusions** | Canonical tokens the user says they CANNOT or will not use — `List<String>`, written by the Profile "Customize" picker. Narrows capability. Floor-sanitized (`EquipmentVocab.floorSanitizedExclusions` strips `none` / `bodyweight` / `wall`) so the bodyweight floor is never excludable. | NOT injuries (a separate field with a separate filter). NOT a dislike list (that is swap history — see `demotedExercises`). |
| **effective** (equipment) | THE derived set the user can actually use: `tierItems[tier] ∪ equipment_owned − equipment_exclusions`, from `EquipmentVocab.effectiveItems`. Every equipment decision in the app — generator, warm-up, finisher, swap sheet, picker, template builder, AI snapshot (`equipment_effective`) — constrains on this and on `equipment_needed`. | **NOT `equipment_tier`.** That column is a CURATION hint ("reasonable at this tier") and is over-tagged in the library, which is the whole of OI-89: a row tagged `bodyweight` may still need a barbell. Never use a second name for this concept — `equipment_available` / `equipment_capability` are the same thing and must not appear. |
| **rank** | One of 11 rungs on the Indian Navy ladder (SD2 → … → Capt). Stored as `current_rank_code` on `user_profile`; promotion history in `rank_promotions`. | NOT a workout PR ranking. NOT a search-result rank. |
| **PR** | Workout personal record — max weight on a given exercise, detected by `WorkoutWriteService._rescanAllPrsFor`. | NOT public relations. NOT pull request — say "PR" only in code/data contexts; for git PRs say "pull request" or use the link. |
| **phase** | A 4-week training block, numbered 1-12. Phase 1 is free; 2-12 are PRO. A phase may be EXTENDED past 4 weeks by holds (see **hold**) — `plan_end` moves, `plan_start` never does. | NOT app launch phase / dev cycle phase — say "release" or "test #N" instead. |
| **hold** (a.k.a. "Hold the Line") | A free-tier repeat week that EXTENDS the current phase rather than advancing it. Written by `WorkoutScheduleWriteService.holdWeek()` (ship-dark `enable_hold_weeks`): copies the phase's canonical **Peak** week — or the **deload** week every 4th hold — at FLAT loads, Monday-backdated, stamping `is_hold` + `hold_ordinal` on each `schedule_*` row and extending `plan_end`. Displayed as `H n` chips. Unlimited: progression, not repetition, is the PRO differentiator. | NOT a pause (that's `pauseRange`, which blanks days). NOT a deload by itself (a deload is one *kind* of hold, every 4th). NOT "redo week 4" — the legacy `redoWeek4` copied the trailing week; a hold sources Peak BY DATE. |
| **hold_ordinal** | 1-based hold number (H1, H2, …) row-stamped by `holdWeek()`, computed gap-proof as `max(existing) + 1` so a late return counts holds TAKEN, not calendar span. Whether a hold is a deload is DERIVED (`ordinal % 4 == 0`), never stored. | NOT a week number — hold rows separately carry `week = 4 + hold_ordinal`, which no display reads (`CurrentPlanData.weeks` stops at the phase's 4). |
| **session** | One workout instance. One `wlog_<istdate>` row. A multi-session day stamps `workout_log_id` per session and gets `sessionLabel: "SESSION N"` on the receipt. | NOT auth session — call that "auth session" explicitly. |
| **split** | Workout type assigned to a day (PUSH A, PULL B, LEG DAY A, etc.). The plan generator's `split_resolver.dart` emits a sequence of splits per phase. | NOT "divide into parts". |
| **titration** | W2.7 phase-boundary VOLUME titration — at a fresh phase advance, each major muscle group's weekly direct-set count is nudged ±1 (clamped MEV 8 – MRV 20) from the prior phase's e1RM trend + readiness recovery evidence. Ship-dark `enable_volume_titration`; opt-in per fresh advance (`pins == null`). `VolumeTitration` in `plan_engine/`. | NOT a chemistry titration. NOT a mid-phase weekly re-adjust (it fires once, at the boundary). NOT the deload wave (a separate week-4 mechanic). |
| **meal_type** | The canonical label field on `nutrition_logs`. Enum: `breakfast` / `lunch` / `dinner` / `snack`. | **There is NO `meal_name` or `name` on `nutrition_logs`. Per-item names live on `items[].name`.** |
| **logging_type** | Exercise input shape. Enum: `weight_reps` / `bodyweight_reps` / `weighted_bodyweight` / `timed` / `cardio` / `distance`. Drives the active-workout UI columns. Resolved through `LoggingTypeResolver` on swap. | NOT log-level (debug/info). |
| **ward** | Prefix for every Wardroom design-system primitive (§6). | NOT hospital ward. |
| **wardroom** | The design system itself. Reconciled palette + DM Sans + Fraunces, gold accent `#D4B270`. Source of truth: `Knowledgebase/Avya App redesign/design_handoff_wardroom/src/wardroom-tokens.jsx`. | NOT "common room". |
| **captain** | The AI coach voice persona. Used in proactive triggers as `captainPrompt('proactive')` from `_shared/captain_manual.ts`. | NOT a rank label (the highest rank is Capt; the voice is captain-of-the-ship). |
| **dispatch** | A proactive coach push sent to a user (one of the 8 server-cron triggers; see docs/architecture/ai.md). UI verb: "deliver dispatch". | NOT git/CI deployment dispatch. |
| **ProactiveType** | THE canonical vocabulary for a notification kind, declared in `supabase/functions/_shared/proactive_dedup.ts`. Every new notification key — dedup slot, preference key, telemetry label — uses these strings: `morning_brief`, `workout_window`, `protein_gap`, `streak_protection`, `pr_celebration`, `plateau_alert`, `weekly_recap`, `re_engagement`, `subscription_expiry`. | NOT a second vocabulary. **Known drift (2026-07-26):** the 5 user-facing preference keys predate this rule and use different spellings for the same concepts (`morning_checkin`, `workout_reminders`, `streak_alerts`, `subscription_reminders`, `protein_alerts`) — only `weekly_recap` agrees. Nine concepts, two names each. Aligning them is a scheduled unit; until it lands, `ProactiveType` is authoritative and NEW keys must conform. |
| **PRO (as a predicate)** | `subscriptions.status = 'active' AND end_date > now()`, via `fetchProUserIds()` / `isProUser()` in `supabase/functions/_shared/subscription.ts`. BOTH terms are required. | NOT `users.subscription_status` — that column has no expiry term and nothing writes it back to `'free'`, so it marks lapsed users PRO forever (live 2026-07-26: it claimed 6 PRO users; the correct predicate returned 0). NOT `status='active'` alone — `status` is never reconciled to expired. Writing the column as a cache is fine; reading it as truth is the bug. |
| **gate** | A `scripts/check_*.dart` (or the one `validate_audit_closure.dart`) that BLOCKS a commit / push / build when an invariant is violated. Its identity is its **filename** — that is what `pre-commit.sh`, `test.yml` and Gate 33 all key on. A gate **number** is an OPTIONAL alias: 49 of 86 have one, the rest do not and do not need one. Registry: `docs/audit/GATE_INDEX.md` (generated by `scripts/build_gate_index.dart`). | NOT a feature gate — that is `subscription.gate()` for PRO features (rule 5), an unrelated sense. NOT a CI job. |
| **`// Gate: N`** | The ONE canonical, machine-readable way a gate declares its number: on its own line, in the first 10 lines, nothing after the number. `scripts/build_gate_index.dart` reads only this form and hard-fails on duplicates. Freeform prose (`// Gate 44 — title`, `// Mirrors Gate 17`) is deliberately NOT matched. | NOT a general comment convention — the exact form is load-bearing. Before it existed, five surveys of "which script claims gate N" returned five different answers. |
| **grandfathered (gate test)** | A gate present on 2026-08-10 that predates the mutation-proof rule (24), enumerated BY NAME in `scripts/check_gate_test_ledger.dart`. The list is closed. | NOT a backlog and NOT a deferral (§4.2) — an enumerated exemption is terminal; "backfill later" would not be. |
| **seal** | A Wardroom badge primitive (`WardSealBadge` in 4 variants: report / subscription / phase / founder). | NOT Indian Navy SEAL ranks (which we don't model). NOT a sealed/locked record. |
| **freeze** | Streak-freeze credit — a "skip day" the user can spend so a missed workout doesn't break the streak. State at `user_progress.streak_freezes_*`. | NOT cold storage. NOT UI freeze (use "loading"). |
| **restore** | The cloud → Hive direction. One-shot on session start via `SyncService.restoreFromCloudForUser`. | NOT undo. Undo lives at `undo_<logKey>` in workoutBox. |
| **sync** | The Hive → cloud direction. Continuous, fire-and-forget, via `SyncService.syncWorkoutData()` / `syncNutritionData()` / per-domain helpers. | NOT bidirectional — use "restore" for the opposite direction. |
| **gate** | A feature-flag PRO check via `SubscriptionService.instance.gate(featureKey, onPro: ..., onFree: ...)`. The ONLY way to PRO-gate a feature in widget code. | NOT a routing guard (those live in `app_router.dart`). |
| **paywall** | The bottom-sheet UI shown when `gate` denies. Single implementation: `PaywallSheet`. | NOT a hard route block. |
| **plan generator** | The LOCAL Dart V4 pipeline at `lib/shared/repositories/plan_engine/`. Read-only without explicit user approval per CLAUDE.md rule #14. | NOT an AI/LLM call — zero API cost. |
| **proactive trigger** | A server-side cron Edge Function that fires a Captain push (8 of them; see docs/architecture/ai.md "Proactive triggers"). | NOT a client-side notification scheduler. |
| **isPaymentInFlight** | The 10-min grace window after a Razorpay success. `verifyFromServer` suppresses downgrade while open. Set by `SubscriptionService.markPaymentInFlight()`. | NOT the Razorpay polling window (that's separate). |
| **localActivationAt** | The 10-min optimistic local PRO activation timestamp written by the success handler. | NOT subscription start date (that's `subscriptions.start_date`). |
| **dossier** | The Profile screen. UI-name only; the route is `/profile`. | NOT a separate report. |
| **muster** | Daily check-in concept used in induction copy. UI-name only; no Hive/cloud surface yet. | NOT to be confused with "must" (modal verb). |
| **induction pledge** | The first-time onboarding commitment. State in `coachBox` (`committed_at`, `committed_to_lt_cdr`, `induction_completed_at`). | NOT a separate onboarding screen — it's woven into Mission Brief / Plan. |
| **roadmap** | The 12-phase `/train/roadmap` view, plus the `/profile/rank-ladder` rank roadmap. Two distinct surfaces; never collapse them. | — |
| **dispatch / brief / muster / roll call** | Captain-voice proactive copy variants. Distinct from "notification" which is the OS-level push. | — |
| **wardroom / mission brief / report for duty** | Onboarding copy ladder (locked). Source: `lib/core/copy/wardroom_copy.dart`. | — |
| **receipt** | The post-workout shareable PNG card. Built by `WorkoutReceiptData.fromExerciseLogs(date, workoutLogId?)`. Per-session scoped since Test #12. | NOT a payment receipt (that's a Razorpay invoice). |
| **prediction card** | The 90-day forecast card from `future-prediction` Edge Function. Free: one card post-onboarding. PRO: monthly. | NOT the AI coach inline prediction. |
| **water target** | The daily water goal. Read ONLY through `WaterTargetService.instance.currentTargetMl()` or `ref.watch(waterTargetProvider)`. Floor 2.5 L, ceiling 4.0 L. Manual override at `userBox['water_target_override_ml']`. | **NEVER hardcode `3000`** (that's the bug-class fixed in Test #11). |
| **submission** | A user-contributed custom food or exercise that's been opted-in for community sharing (`submitted_to_library: true`). DRAFT means not yet submitted. PENDING means awaiting moderator. APPROVED means promoted to global DB. | NOT a workout log. |
| **deletion (DPDP §17)** | Hard erasure via `delete-account` Edge Function. Razorpay sub cancel + OneSignal unsub + Storage purge + audit row in `account_deletion_log`. Five community surfaces are pseudonymized via `ON DELETE SET NULL` (see docs/architecture/payment.md, "DPDP delete-account"). | NOT soft-delete. The `softDeleteAccount` path is `@Deprecated`. |

---

## 9. Rules for new features

Before introducing a new name:

1. **Read `docs/sot_registry.yaml`** and the relevant section of this doc.
2. **Grep the codebase for the proposed name** before committing. Collisions are easier to find at design time than after a contract test fails.
3. **If the name is a new domain term**, add it to §8 in the same PR.
4. **If the name is a new Hive key prefix**, add it to §3.3 in the same PR + update `docs/sot_registry.yaml`.
5. **If the name maps Hive ↔ cloud**, add the mapping to §4.4 in the same PR.
6. **If the name is a new Wardroom primitive**, export it from `wardroom.dart` in the same PR.
7. **If you rename an existing Hive field**, update the writer + every consumer in the same PR + update or add a contract test in `test/contracts/<x>_test.dart`. See docs/architecture/sync.md "Hive field-name contracts".

When two writers exist for the same concept (rare; should never be the goal), one MUST be the canonical writer and the other MUST delegate. The 2026-05-06 EditWorkoutLogSheet vs WorkoutWriteService drift (memory file `feedback_source_of_truth_audit.md`) is the cautionary tale.

---

## 10. Cross-references

- **`docs/architecture/sync.md`** + **`docs/sot_registry.yaml`** — Source of Truth rules (NON-NEGOTIABLE), Hive field-name contract, sync fan-out contract, restore-completeness.
- **`CLAUDE.md` §4.4** — the 23 coding rules (Hive-first, Riverpod-only, gate() for all PRO features, etc.). NOTE: root §6 is MULTI-TIER COVERAGE, not the coding rules.
- **`lib/shared/widgets/wardroom/CLAUDE.md`** — Wardroom palette / typography / spacing tokens.
- **`docs/sot_registry.yaml`** — Machine-readable registry of every concept with multiple readers (consumed by automated audit tooling).
- **`lib/core/utils/ist_date.dart`** — Date helpers. All date keys + cloud `date` columns + counter resets MUST go through `istDateStr(...)`. See feedback memory `feedback_use_ist_throughout.md`.
- **`docs/reference/database-schema.md`** — Full DDL for all 37 cloud tables.
- **`docs/reference/directory-structure.md`** — Annotated `lib/` tree.
