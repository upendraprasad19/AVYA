-- Intent: Add the four rank-evaluation columns the evaluate-rank-promotions cron already SELECTs but which never existed on user_progress (deployments_complete, current_streak_days, last_workout_date, longest_gap_days). Backfill deployments_complete = GREATEST(0, current_phase - 1) for existing rows. Unblocks the deployment-driven, no-skip rank ladder (PO/CPO gates) + repairs the silently-inert server cron.
-- Destructive?: no   -- adds nullable/defaulted columns + forward-only backfill; no rows rewritten, no data loss.
-- Rollback strategy: inline   -- reverse DDL (drop the four columns) commented at file end.
-- Linked diagnose-doc: b9f4d2
--
-- 081_user_progress_rank_eval_columns.sql
--
-- BUG (surfaced by the 2026-05-31 year-sim follow-up): evaluate-rank-promotions/index.ts:107
--   .select("current_streak_days, deployments_complete, longest_gap_days, last_workout_date")
-- targets columns that DO NOT EXIST on public.user_progress (live schema confirmed:
-- only current_phase / current_week / total_workouts_done / current_streak_weeks /
-- phase_started_at / streak_freezes_* ...). PostgREST returns a 400 → the cron's
-- `const { data: progressRow }` is null → streak/deployments/gap all default to 0 →
-- highestQualified() can only ever return SD2. The server-side rank cron is inert for
-- the entire sailor + officer ladder.
--
-- FEATURE: deployments_complete is also the F18-deferred counter the CLIENT rank engine
-- reads (rank_service.dart:445). 1 deployment = 1 completed phase = current_phase - 1.
-- The client now writes it to Hive + syncs it here; PO needs >=2, CPO needs >=3.
--
-- These four columns are the client's source-of-truth values synced upward (the
-- schedule-aware streak walk lives client-side; re-implementing it server-side is the
-- recurring writer/reader-drift bug source, so we sync rather than recompute).

ALTER TABLE public.user_progress
  ADD COLUMN IF NOT EXISTS deployments_complete  integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS current_streak_days   integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_workout_date     date,
  ADD COLUMN IF NOT EXISTS longest_gap_days      integer NOT NULL DEFAULT 0;

-- Forward-only backfill so existing users get a correct deployment count immediately
-- (= completed-phase count). current_streak_days / last_workout_date / longest_gap_days
-- populate on the next client sync (they originate from the client's Hive progress map).
UPDATE public.user_progress
  SET deployments_complete = GREATEST(0, COALESCE(current_phase, 1) - 1)
  WHERE deployments_complete = 0;

-- Rollback (inline):
-- ALTER TABLE public.user_progress
--   DROP COLUMN IF EXISTS deployments_complete,
--   DROP COLUMN IF EXISTS current_streak_days,
--   DROP COLUMN IF EXISTS last_workout_date,
--   DROP COLUMN IF EXISTS longest_gap_days;
