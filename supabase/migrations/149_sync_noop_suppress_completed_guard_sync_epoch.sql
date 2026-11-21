-- Intent: Day-swapper + sync-load batch (OI-237), server half. Three
--   independent fixes on ONE file per plan Task 7 (day-swapper-sync-load
--   plan, spec Section 5.10): (1) a generic no-op-update suppression trigger
--   on every table the sync layer re-sends unconditionally today, using the
--   Postgres BUILT-IN suppress_redundant_updates_trigger() (no extension
--   required, ships in core Postgres, not SECURITY DEFINER) -- an identical
--   UPDATE payload then creates no new row version, closing the disk-IO
--   amplification measured live in spec Section 1.5 (e.g.
--   workout_schedule_completions ~29 rewrites/row, scheduled_workouts 1,377
--   updates vs 84 inserts, template_exercises ~33 rewrites/row on 23 live
--   rows). Limit: a table whose writer stamps a fresh sent-at column on
--   every push never matches OLD, so this trigger cannot suppress it; the
--   client skip index (whose fingerprint excludes that stamp) is its only
--   protection. Two such tables at the time of writing: water_logs
--   (`updated_at`, written by both SyncService._syncWaterLogs and
--   _syncUrineColorLogs) and daily_steps (`synced_at`, written by
--   _syncStepsLogs);
--   (2) a dedicated scheduled_workouts guard, SECURITY INVOKER, that
--   silently drops (never raises) any UPDATE that would demote a `completed`
--   row to another status, while still allowing a `completed_at` correction
--   on an otherwise-unchanged completed row -- this is the server backstop
--   the client-side day-swap engine and the existing cross-device-completion
--   contract (diagnose d9b2c5, A-fix-1 in `_syncScheduledWorkouts`) both
--   depend on, so a stale device's resync can never silently un-complete a
--   day another device already finished; (3) `user_progress.sync_epoch`, an
--   integer repair lever an operator can bump to force every device to clear
--   its local skip index and resend once (spec Section 5.10 point 3). It is
--   an ordinary column under the table's existing own-row RLS, not access-
--   restricted: a user can bump their own epoch, whose only effect is that
--   their own devices resend once.
--
--   `scheduled_workouts` deliberately gets ONLY the custom guard, not the
--   generic trigger too -- the guard's own no-op branch already subsumes
--   identical-row suppression, and two no-op triggers on one table would be
--   redundant (and BEFORE UPDATE trigger firing order across two triggers on
--   the same table is alphabetical by trigger name, which is exactly the
--   kind of implicit ordering dependency this migration avoids by not
--   creating it).
--
--   The 19-table list for the generic trigger is the plan's own gate-G1
--   enumeration (day-swapper-sync-load plan Section 13 row 6): workout_logs,
--   workout_log_exercises, workout_log_sets, workout_schedule_completions,
--   streaks, workout_templates, template_exercises, nutrition_logs,
--   nutrition_log_items, water_logs, user_saved_meals, readiness_daily,
--   sleep_logs, weight_logs, body_measurements, daily_steps,
--   user_custom_exercises, user_custom_foods, ai_coach_interactions.
--
--   `user_profile` is deliberately EXCLUDED (plan Section 13 row 7): its
--   writers (`sync_service.dart` `_executeUserProfileUpsert` and the legacy
--   path in `sync/sync_profile.dart`) chain
--   `.upsert(payload, onConflict: 'user_id').select()`, and a BEFORE UPDATE
--   trigger that RETURN NULLs makes Postgres skip that row entirely, so
--   PostgREST's RETURNING-backed `.select()` would see zero rows and a
--   downstream `.single()` would throw PGRST116. Re-grepped for this
--   migration (multiline `\.(update|upsert)\([\s\S]{0,200}?\.select\(` over
--   lib/ and supabase/functions/) across all 20 tables actually gaining a
--   trigger here, plus a grep for `UPDATE ... <table>` in
--   supabase/migrations/ to check for RPCs relying on RETURNING/FOUND after
--   an UPDATE on these tables: the only UPDATE-on-these-tables hits in
--   supabase/migrations/ are four one-off historical DDL/backfill scripts
--   (020_dedupe_custom_entities.sql, 050b_workout_templates_unique_user_name.sql,
--   064_fix_partial_unique_arbiter.sql, 083_nutrition_sync_natural_keys.sql)
--   that ran once and are never re-run, and none of the 20 tables has a live
--   RPC that reads RETURNING/FOUND after an UPDATE on it.
--
--   ONE chained `.update().select()` DID surface on ai_coach_interactions
--   that plan Section 13 row 7 did not name (`ai-proxy/index.ts`, the
--   `refreshed` update in the food-text dedup-slot refresh: sets `created_at` to
--   `new Date().toISOString()` then `.select("id").single()`). Flagged here
--   rather than silently accepted, because it contradicts row 7's claim that
--   user_profile is the ONLY such chain among the 20 tables. Risk assessed
--   LOW, not blocking this migration: the written value is a fresh
--   wall-clock timestamp on every call, so the generic trigger's row
--   equality check (`NEW IS NOT DISTINCT FROM OLD`) is false unless two
--   refreshes land on the exact same row within the same MILLISECOND (JS
--   `toISOString()` precision; the row's first `created_at` is the column
--   default `now()`, microsecond precision, which a millisecond value almost
--   never equals; precision corrected by Hermes L22 2026-09-28) -- see this
--   batch's diagnose-doc for a9d3f6 and the plan-review record for the
--   founder-visible flag. Not fixed here because the fix belongs in
--   `ai-proxy` (a separate deploy under its own founder go, spec Section 11
--   step 2), not in DDL, and is out of scope for a migration file.
-- Destructive?: no   -- adds triggers, one function and one NOT NULL column
--   with a DEFAULT; no DROP, no data rewrite, no constraint that discards an
--   existing value.
-- Rollback strategy: inline   -- DROP TRIGGER x19 + DROP TRIGGER/FUNCTION for
--   the scheduled_workouts guard + ALTER TABLE user_progress DROP COLUMN
--   sync_epoch, commented block at end of file.
-- Linked diagnose-doc: a9d3f6

-- === 1. Generic no-op-update suppression (19 tables) =======================
-- suppress_redundant_updates_trigger() is a Postgres BUILT-IN (no
-- CREATE EXTENSION required; documented under "Trigger Functions" in the
-- Postgres manual, ships in every install) that RETURN NULLs a BEFORE UPDATE
-- when NEW is not distinct from OLD, row-wise -- Postgres then skips the
-- UPDATE for that row entirely (no new tuple, no WAL for that row).
-- Idempotent (DROP IF EXISTS before CREATE) so a retried apply is safe.

DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.workout_logs;
CREATE TRIGGER trg_suppress_redundant_updates
  BEFORE UPDATE ON public.workout_logs
  FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();

DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.workout_log_exercises;
CREATE TRIGGER trg_suppress_redundant_updates
  BEFORE UPDATE ON public.workout_log_exercises
  FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();

DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.workout_log_sets;
CREATE TRIGGER trg_suppress_redundant_updates
  BEFORE UPDATE ON public.workout_log_sets
  FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();

DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.workout_schedule_completions;
CREATE TRIGGER trg_suppress_redundant_updates
  BEFORE UPDATE ON public.workout_schedule_completions
  FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();

DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.streaks;
CREATE TRIGGER trg_suppress_redundant_updates
  BEFORE UPDATE ON public.streaks
  FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();

DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.workout_templates;
CREATE TRIGGER trg_suppress_redundant_updates
  BEFORE UPDATE ON public.workout_templates
  FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();

DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.template_exercises;
CREATE TRIGGER trg_suppress_redundant_updates
  BEFORE UPDATE ON public.template_exercises
  FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();

DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.nutrition_logs;
CREATE TRIGGER trg_suppress_redundant_updates
  BEFORE UPDATE ON public.nutrition_logs
  FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();

DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.nutrition_log_items;
CREATE TRIGGER trg_suppress_redundant_updates
  BEFORE UPDATE ON public.nutrition_log_items
  FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();

DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.water_logs;
CREATE TRIGGER trg_suppress_redundant_updates
  BEFORE UPDATE ON public.water_logs
  FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();

DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.user_saved_meals;
CREATE TRIGGER trg_suppress_redundant_updates
  BEFORE UPDATE ON public.user_saved_meals
  FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();

DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.readiness_daily;
CREATE TRIGGER trg_suppress_redundant_updates
  BEFORE UPDATE ON public.readiness_daily
  FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();

DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.sleep_logs;
CREATE TRIGGER trg_suppress_redundant_updates
  BEFORE UPDATE ON public.sleep_logs
  FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();

DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.weight_logs;
CREATE TRIGGER trg_suppress_redundant_updates
  BEFORE UPDATE ON public.weight_logs
  FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();

DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.body_measurements;
CREATE TRIGGER trg_suppress_redundant_updates
  BEFORE UPDATE ON public.body_measurements
  FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();

DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.daily_steps;
CREATE TRIGGER trg_suppress_redundant_updates
  BEFORE UPDATE ON public.daily_steps
  FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();

DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.user_custom_exercises;
CREATE TRIGGER trg_suppress_redundant_updates
  BEFORE UPDATE ON public.user_custom_exercises
  FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();

DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.user_custom_foods;
CREATE TRIGGER trg_suppress_redundant_updates
  BEFORE UPDATE ON public.user_custom_foods
  FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();

DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.ai_coach_interactions;
CREATE TRIGGER trg_suppress_redundant_updates
  BEFORE UPDATE ON public.ai_coach_interactions
  FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger();

-- === 2. scheduled_workouts: never demote a completed day, never raise =====
-- SECURITY INVOKER (default) -- this must run with the calling role's own
-- privileges, exactly like the RLS-checked UPDATE it is gating, not with
-- elevated rights. RETURN NULL (never RAISE) in both branches: raising would
-- fail the caller's UPDATE outright, and a stale device's sync loop has no
-- retry backoff for a hard error -- it would fail the same write on every
-- subsequent pass forever. RETURN NULL instead makes Postgres silently skip
-- the row, which is exactly what the client-side skip-index helper
-- (plan Task 4, SyncSkipIndex.pushIfChanged) needs: push() still resolves
-- normally (no thrown error), so the row is recorded as sent and never
-- retried for no reason.
-- Lives in `private`, like 133/138's trigger functions: a public function is
-- anon-executable by this project's default privileges, and `private` keeps
-- it PostgREST-invisible (plan-review round 2, slice B F1). search_path is
-- pinned for the same reason 138 pins it.
CREATE OR REPLACE FUNCTION private.scheduled_workouts_completed_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $function$
BEGIN
  -- No-op suppression, folded into this same function rather than a second
  -- generic trigger on this table (see this file's header: two no-op
  -- triggers on one table would be redundant and order-dependent).
  IF NEW IS NOT DISTINCT FROM OLD THEN
    RETURN NULL;
  END IF;

  -- The completed-day guard (spec Section 5.10 point 2, verbatim): a
  -- `completed` row can never be moved to another status. This drops the
  -- WHOLE write, not just the status field -- a caller that tries to demote
  -- AND correct another column in the same statement gets neither; the
  -- spec's two RETURN-NULL conditions are independent, not merged. A
  -- completed_at-only correction on an otherwise-unchanged completed row
  -- does NOT hit this branch (NEW.status IS DISTINCT FROM OLD.status is
  -- false there), so it falls through to RETURN NEW below, exactly as spec
  -- Section 5.10 requires ("Corrections to a completed row's completed_at
  -- stay allowed").
  IF OLD.status = 'completed' AND NEW.status IS DISTINCT FROM OLD.status THEN
    RETURN NULL;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_scheduled_workouts_completed_guard ON public.scheduled_workouts;
CREATE TRIGGER trg_scheduled_workouts_completed_guard
  BEFORE UPDATE ON public.scheduled_workouts
  FOR EACH ROW EXECUTE FUNCTION private.scheduled_workouts_completed_guard();

-- === 3. sync_epoch: an operator-driven "resend everything once" lever =====
-- Confirmed by reading the live function body (migration 115,
-- update_user_progress_snapshot): both its fresh-INSERT and its UPDATE
-- branch name every column explicitly (no `SELECT *`, no whole-row
-- assignment), and sync_epoch is not among them -- a fresh INSERT gets the
-- column DEFAULT (0) and an UPDATE never touches it. The only other live
-- writer to user_progress is weekly-recalc's named-field PostgREST upsert
-- (`weekly-recalc/index.ts:361-368`: user_id / detected_experience_level /
-- experience_last_calculated / total_workouts_done only) -- also
-- column-scoped, also silent on sync_epoch. No writer anywhere selects `*`
-- from user_progress then writes the row back.
--
-- Ops runbook: `UPDATE user_progress SET sync_epoch = sync_epoch + 1
-- [WHERE user_id = ...];` makes that user's (or every user's) devices clear
-- their local skip index and resend once, next launch (spec Section 5.11).
--
-- backups/live_schema_columns.json is regenerated in the SAME commit as this
-- migration's apply (Task 34), per check_schema_column_refs.dart's own
-- header -- not by this file, since U1 hands this file over uncommitted.
ALTER TABLE public.user_progress
  ADD COLUMN IF NOT EXISTS sync_epoch integer NOT NULL DEFAULT 0;

-- Post-apply verification (read-only; run inside BEGIN...ROLLBACK per
-- supabase/migrations/CLAUDE.md's own pitfall row -- a verification snippet
-- copied out of a migration's own comments is not transaction-safe on its
-- own just because it looks read-only):
--
--   BEGIN;
--     SELECT count(*) FROM pg_trigger
--       WHERE tgname = 'trg_suppress_redundant_updates';          -- expect 19
--     SELECT tgname, tgrelid::regclass, tgenabled FROM pg_trigger
--       WHERE tgname = 'trg_scheduled_workouts_completed_guard';  -- expect 1 row, tgenabled='O'
--     SELECT column_name, column_default, is_nullable
--       FROM information_schema.columns
--      WHERE table_name = 'user_progress' AND column_name = 'sync_epoch';
--       -- expect one row: column_default like '0', is_nullable = 'NO'
--   ROLLBACK;
--
-- Then run test/sql/day_swap_sync_load_live_verify.sql for real against the
-- live database (it is its own BEGIN...ROLLBACK) and confirm every row in
-- _v_results has status='ok'.

-- =============================================================================
-- Rollback (commented -- apply as a NEW migration if ever needed; migrations
-- are immutable once applied, see supabase/migrations/CLAUDE.md):
-- =============================================================================
-- DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.workout_logs;
-- DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.workout_log_exercises;
-- DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.workout_log_sets;
-- DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.workout_schedule_completions;
-- DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.streaks;
-- DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.workout_templates;
-- DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.template_exercises;
-- DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.nutrition_logs;
-- DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.nutrition_log_items;
-- DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.water_logs;
-- DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.user_saved_meals;
-- DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.readiness_daily;
-- DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.sleep_logs;
-- DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.weight_logs;
-- DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.body_measurements;
-- DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.daily_steps;
-- DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.user_custom_exercises;
-- DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.user_custom_foods;
-- DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.ai_coach_interactions;
-- DROP TRIGGER IF EXISTS trg_scheduled_workouts_completed_guard ON public.scheduled_workouts;
-- DROP FUNCTION IF EXISTS private.scheduled_workouts_completed_guard();
-- ALTER TABLE public.user_progress DROP COLUMN IF EXISTS sync_epoch;
