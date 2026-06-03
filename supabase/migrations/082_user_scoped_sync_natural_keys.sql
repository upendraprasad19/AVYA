-- Intent: User-inclusive natural keys for per-user sync tables — add UNIQUE(user_id,date) on weight_logs/sleep_logs/body_measurements and replace the GLOBAL UNIQUE(workout_log_id,exercise_id,set_number) with UNIQUE(user_id,workout_log_id,exercise_id,set_number) on workout_log_exercises/workout_log_sets; widen wls_reps_realistic to <=1000 (the sibling wle was widened by migration 080). Closes the cross-user deterministic-id collision where two users acting on the same calendar date collided on the PK / overwrote each other's rows.
-- Destructive?: no   -- index + CHECK swaps only; NO rows lost or rewritten. Existing rows self-heal via their (unchanged) natural key on next sync — no historical re-key. DEPLOY-ORDERING: ship WITH the matching APK — an OLD client's onConflict (without user_id) would 42P10 once the old global indexes drop, until it updates (acceptable pre-launch / single device; founder signed off 2026-06-02 "sweep now").
-- Rollback strategy: inline   -- reverse DDL (recreate old global indexes, drop the user-inclusive ones, restore wls_reps<=60) commented at file end.
-- Linked diagnose-doc: d4b8e2
--
-- 082_user_scoped_sync_natural_keys.sql
--
-- Per-day sync rows used a user-INDEPENDENT identity (_deterministicId over a
-- date-only Hive key, no user_id), so two users on the same calendar date hit
-- the same uuid → PK collision (23505), or — for workout_log_exercises/_sets —
-- the global natural key (workout_log_id,exercise_id,set_number) lacked user_id
-- so onConflict DO UPDATE could overwrite ANOTHER user's row (cross-user
-- corruption). Cure (matching nutrition_logs/workout_templates/scheduled_workouts):
-- the client OMITS id (gen_random_uuid default) + upserts onConflict a
-- USER-INCLUSIVE natural key. This migration backs those keys. Verified live
-- 2026-06-02: all arbiter columns NOT NULL (no 42P10 — non-partial indexes) and
-- ZERO existing duplicates on every new key (clean create, no re-key).

-- ── weight_logs / sleep_logs / body_measurements: add the missing key (additive) ──
create unique index if not exists uniq_weight_logs_user_date
  on public.weight_logs (user_id, date);

create unique index if not exists uniq_sleep_logs_user_date
  on public.sleep_logs (user_id, date);

create unique index if not exists uniq_body_measurements_user_date
  on public.body_measurements (user_id, date);

-- ── workout_log_exercises: CREATE the user-inclusive index BEFORE dropping the
--    old global one, so the client's user-inclusive onConflict ALWAYS has an
--    arbiter (no arbiter-less window → no plain-INSERT duplicate risk). ──
create unique index if not exists uniq_wle_user_wlog_ex_set
  on public.workout_log_exercises (user_id, workout_log_id, exercise_id, set_number);
drop index if exists public.uniq_workout_log_exercises_wlog_ex_set;

-- ── workout_log_sets: same create-before-drop ordering (the non-unique
--    idx_workout_log_sets_log_exercise stays for query perf). ──
create unique index if not exists uniq_wls_user_wlog_ex_set
  on public.workout_log_sets (user_id, workout_log_id, exercise_id, set_number);
drop index if exists public.ux_workout_log_sets_natural_key;

-- ── workout_log_sets reps bound: widen to match the sibling wle_reps_realistic
--    (migration 080 widened workout_log_exercises to <=1000 but missed this
--    per-set table → 23514 on high-rep per-set rows). NOT VALID: new rows are
--    checked; existing rows (already <=60) are assumed valid without a scan. ──
alter table public.workout_log_sets drop constraint if exists wls_reps_realistic;
alter table public.workout_log_sets
  add constraint wls_reps_realistic
  check (reps is null or (reps >= 0 and reps <= 1000)) not valid;

-- ── Rollback (inline, emergency-only) ────────────────────────────────────────
-- NOTE: recreating the GLOBAL unique indexes below would FAIL once cross-user
-- duplicate rows exist (the very rows this fix enables). Rollback is an
-- emergency path only, before a follow-up migration can be authored.
-- begin;
--   drop index if exists public.uniq_weight_logs_user_date;
--   drop index if exists public.uniq_sleep_logs_user_date;
--   drop index if exists public.uniq_body_measurements_user_date;
--   create unique index if not exists uniq_workout_log_exercises_wlog_ex_set
--     on public.workout_log_exercises (workout_log_id, exercise_id, set_number);
--   drop index if exists public.uniq_wle_user_wlog_ex_set;
--   create unique index if not exists ux_workout_log_sets_natural_key
--     on public.workout_log_sets (workout_log_id, exercise_id, set_number);
--   drop index if exists public.uniq_wls_user_wlog_ex_set;
--   alter table public.workout_log_sets drop constraint if exists wls_reps_realistic;
--   alter table public.workout_log_sets
--     add constraint wls_reps_realistic
--     check (reps is null or (reps >= 0 and reps <= 60)) not valid;
-- commit;
