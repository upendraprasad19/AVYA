---
source: CLAUDE.md §7
migrated: 2026-05-18
status: scaffold
---

# Database Schema — Reference

> 46-table inventory + FK direction quirks + UNIQUE/CHECK constraints + column notes.
> Fetch via Read when working on schema or sync.

## 46 Tables — Supabase Postgres

> Full DDL → `docs/reference/database-schema.md`. Authoritative source of truth: `supabase/migrations/`. Count verified live on prod 2026-05-11 (`information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'`).

| Domain | Tables |
|---|---|
| Identity (4) | `users`, `user_profile`, `user_preferences`, `user_progress` |
| Fitness (9) | `exercise_library`, `workout_templates`, `template_exercises`, `scheduled_workouts`, `workout_logs`, `workout_log_exercises`, `workout_log_sets`, `workout_schedule_completions`, `user_custom_exercises` |
| Nutrition (6) | `food_database`, `nutrition_logs`, `nutrition_log_items`, `user_saved_meals`, `user_custom_foods`, `saved_diet_plans` |
| Health (6) | `weight_logs`, `body_measurements`, `streaks`, `water_logs`, `sleep_logs`, `daily_steps` |
| Visual (1) | `progress_photos` |
| AI (4) | `user_daily_snapshots`, `ai_coach_interactions` (incl. `tool_calls` JSONB column from migration 029), `coach_memory`, `memory_embeddings` |
| Telemetry (1) | `client_errors` |
| Monetisation (7) | `subscriptions`, `promo_codes`, `promo_code_uses`, `food_corrections`, `telegram_connections`, `referral_codes`, `referral_redemptions` |
| Community (1) | `community_reviews` |
| Ranking (3) | `rank_ladder` (reference — 11 ranks), `rank_promotions` (events, UNIQUE `(user_id, rank_code)`), `user_stat_snapshots` (onboarding + per-promotion lifetime totals) |
| Notifications (1) | `notifications_inbox` |
| DPDP / Audit (1) | `account_deletion_log` (no FK, survives `auth.users` cascade — DPDP §17 erasure record; RLS enabled with ZERO policies by design — service-role-only writes via `delete-account` Edge Function; verified intentional 2026-05-12 audit P1-H) |
| Deferred / Inactive (2) | `daily_quotes` (Test #9 morning-quote experiment, not wired), `video_renders` (Remotion/Lambda render queue, video-share feature deferred) |

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
- `users.terms_accepted_at` + `users.terms_version` — DPDP audit trail columns (migration 032, 2026-04-20). Stamped by `TermsModal` (Hive) and synced up on first post-auth users upsert in `_ensureLocalUser`. Bump `AppConstants.termsVersion` to force re-prompt. **APK Test #2 batch (2026-04-25):** also synced DOWN from `users.terms_accepted_at`/`terms_version` to Hive on `_ensureLocalUser` so returning users skip the standalone `TermsModal` after logout.
- `nutrition_logs.total_fiber NUMERIC DEFAULT 0` (migration 034, 2026-04-24). Historical rows stay at 0 — `nutrition_log_items` has no fiber column, so no backfill source. New logs carry the value from the Hive `nlog_*` row via `_syncNutritionLogs`. Feeds the AI coach via `_getTodayNutrition.fiber_g` / `fiber_target_g: 30`.
- `user_profile.onboarding_completed_at TIMESTAMPTZ` (migration 036, 2026-04-25). Set by `OnboardingNotifier.completeOnboarding` on successful upsert. Read by `RestoringScreen` (post-auth gate) to decide between `/home` (onboarded) vs `/onboarding/mission-brief` (new user) vs resume-onboarding (mid-flow). Backfilled from existing rows where `primary_goal IS NOT NULL` (3/3 onboarded users at migration time).
- `referral_codes.expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '7 days')` (migration 037, 2026-04-25). Codes expire 7 days after generation. `getOrCreateReferralCode()` filters by `expires_at > now()`; expired codes show REGENERATE button in InviteFriendsSheet. Pre-existing codes were given fresh 7-day windows starting from migration time (not retroactively expired).
- `referral_redemptions` table (migration 037, 2026-04-25). Audit row per redemption: `code, referrer_id, referee_id, redeemed_at, days_granted_each`. UNIQUE on `referee_id` (one code per receiver, ever) — canonical constraint name is `unique_referee_redemption` after audit 2026-05-12 P3-B dropped the duplicate `referral_redemptions_referee_id_key`. **FKs point at `public.users(id)`** for both referrer and referee (NOT `auth.users` — corrected 2026-05-12 P3-A after verifying via `pg_constraint`; `referral_codes` remains the ONLY user-scoped table FK'd to `auth.users(id)` per the "FK direction quirk" note above). CHECK constraint `no_self_referral` blocks `referrer_id = referee_id`.
- `user_profile.preferred_workout_time TEXT` (migration 063, 2026-05-13). Captures muster Q4 "preferred workout time" answer. `"HH:MM"` 24-hour. NULL when not collected. Written by `InductionService._bridgeToProfile` (muster bridge, APK Test #15.4 / B2c) and Edit Profile picker tile; read by AI context (rolling-context Edge Function reads via `user_profile`) and Edit Profile.

**RPC:**
- `increment_promo_used_count(p_code text)` — atomically increments `promo_codes.used_count`. Called from `razorpay-webhook` after subscription insert (only when `alreadyProcessed === false`).
- `redeem_referral_atomic(p_code, p_referrer_id, p_referee_id, p_days)` — migration 038, 2026-04-25. Atomic both-side reward write: inserts audit row + extends both subscriptions in a single transaction. Used by `redeem-referral` Edge Function v10. Note: `subscriptions` column adapted to `status='active'` (not `active=true` boolean); `source` column not present in this project's `subscriptions` schema.
