-- Intent: Fix migration 026's enforce_food_text_daily_limit trigger to use an
--   Asia/Kolkata day boundary instead of date_trunc('day', now()), which truncates
--   in the DB session's default timezone (UTC on this project) and so resets the
--   50/200-per-day food_text_analysis cap at 05:30 IST, not midnight IST. Found
--   while building migration 111's sibling triggers for OI-46, which mirror this
--   function's shape — copying the buggy boundary alongside a NEW correct one
--   would have shipped the H-4 bug class (pre-batch client-side fix:
--   istDayStartIso() in ai-proxy/index.ts's check-then-insert pre-checks,
--   removed by this same batch's reservation-pattern rewrite) a second time
--   server-side, in the exact same file family, having already diagnosed it
--   once.
-- Destructive?: no — CREATE OR REPLACE on an existing function; only the day-
--   boundary expression changes, cap values and channel gating are byte-identical
--   to migration 026. No data is touched; this only changes future daily_count
--   evaluation.
-- Rollback strategy: migration 026 — CREATE OR REPLACE back to
--   date_trunc('day', now()) restores the pre-fix (buggy) boundary.
-- Linked diagnose-doc: docs/diagnoses/2026-07-29-oi46-daily-cap-toctou-<id>.md

CREATE OR REPLACE FUNCTION enforce_food_text_daily_limit()
RETURNS TRIGGER AS $$
DECLARE
  daily_count int;
  is_pro      bool;
  daily_cap   int;
BEGIN
  IF NEW.channel IS DISTINCT FROM 'food_text_analysis' THEN
    RETURN NEW;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM subscriptions
    WHERE user_id = NEW.user_id
      AND status = 'active'
      AND end_date > now()
  ) INTO is_pro;

  daily_cap := CASE WHEN is_pro THEN 200 ELSE 50 END;

  -- IST day boundary (Asia/Kolkata) — see migration 111's identical comment for
  -- the full rationale. This is the only change from migration 026.
  SELECT count(*) INTO daily_count
  FROM ai_coach_interactions
  WHERE user_id = NEW.user_id
    AND channel = 'food_text_analysis'
    AND created_at >= (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata');

  IF daily_count >= daily_cap THEN
    RAISE EXCEPTION 'food_text_daily_limit_reached (cap=%, pro=%)', daily_cap, is_pro
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger itself (trg_food_text_rate_limit) is unchanged — CREATE OR REPLACE
-- FUNCTION above is sufficient; no DROP/CREATE TRIGGER needed since the
-- function signature and name are identical to migration 026.

-- Rollback (inline — restores migration 026's original UTC-anchored boundary):
-- CREATE OR REPLACE FUNCTION enforce_food_text_daily_limit()
-- RETURNS TRIGGER AS $$
-- DECLARE
--   daily_count int;
--   is_pro      bool;
--   daily_cap   int;
-- BEGIN
--   IF NEW.channel IS DISTINCT FROM 'food_text_analysis' THEN
--     RETURN NEW;
--   END IF;
--   SELECT EXISTS (
--     SELECT 1 FROM subscriptions
--     WHERE user_id = NEW.user_id AND status = 'active' AND end_date > now()
--   ) INTO is_pro;
--   daily_cap := CASE WHEN is_pro THEN 200 ELSE 50 END;
--   SELECT count(*) INTO daily_count
--   FROM ai_coach_interactions
--   WHERE user_id = NEW.user_id AND channel = 'food_text_analysis'
--     AND created_at >= date_trunc('day', now());
--   IF daily_count >= daily_cap THEN
--     RAISE EXCEPTION 'food_text_daily_limit_reached (cap=%, pro=%)', daily_cap, is_pro
--       USING ERRCODE = 'P0001';
--   END IF;
--   RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql;
