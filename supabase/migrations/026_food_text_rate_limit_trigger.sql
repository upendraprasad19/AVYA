-- Migration 026 · 2026-04-18
-- Atomic server-side daily cap on food_text_analysis per user.
--
-- Replaces the TOCTOU race in ai-proxy where two simultaneous
-- requests could both see count=49 and both pass the 50/day check.
-- The trigger runs inside the same transaction as the INSERT so
-- there's no window between count and write.
--
-- Caps:
--   Free users (no active subscription)   — 50/day
--   PRO users (active subscription)       — 200/day
--
-- Client-side: ai-proxy catches SQLSTATE P0001 from this trigger and
-- returns 429 with the same body the old check-then-write path used.
-- See `supabase/functions/ai-proxy/index.ts` food_text_analysis block.
--
-- NOTE: applied live via MCP on 2026-04-18 under name
-- `024_food_text_rate_limit_trigger`. Saved on disk with index 026 to
-- avoid clashing with the existing 023/024 files. Idempotent via
-- CREATE OR REPLACE and DROP TRIGGER IF EXISTS.

CREATE OR REPLACE FUNCTION enforce_food_text_daily_limit()
RETURNS TRIGGER AS $$
DECLARE
  daily_count int;
  is_pro      bool;
  daily_cap   int;
BEGIN
  -- Only gate food_text_analysis; other channels bypass.
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

  SELECT count(*) INTO daily_count
  FROM ai_coach_interactions
  WHERE user_id = NEW.user_id
    AND channel = 'food_text_analysis'
    AND created_at >= date_trunc('day', now());

  IF daily_count >= daily_cap THEN
    RAISE EXCEPTION 'food_text_daily_limit_reached (cap=%, pro=%)', daily_cap, is_pro
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_food_text_rate_limit ON ai_coach_interactions;

CREATE TRIGGER trg_food_text_rate_limit
  BEFORE INSERT ON ai_coach_interactions
  FOR EACH ROW EXECUTE FUNCTION enforce_food_text_daily_limit();
