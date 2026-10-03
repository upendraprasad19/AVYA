-- Intent: Atomic server-side daily caps for AI Coach chat (channel='app', free-tier
--   10/day) and vision analysis (channel IN ('scan_meal','cart_auditor'), combined
--   15/day) — closes OI-46's two real gaps (both were check-then-insert TOCTOU in
--   ai-proxy/index.ts, not the fabricated channel='in_app' claim the OI originally
--   named). Mirrors migration 026's enforce_food_text_daily_limit shape, but corrects
--   the day boundary to Asia/Kolkata rather than UTC — migration 026 itself has that
--   same bug (see migration 113, filed in the same batch after being found here).
-- Destructive?: no — adds two new trigger functions + two triggers; no existing data
--   is touched or read outside each new trigger's own SELECT count(*).
-- Rollback strategy: inline — DROP TRIGGER/FUNCTION block commented at end of file.
-- Linked diagnose-doc: docs/diagnoses/2026-07-29-oi46-daily-cap-toctou-<id>.md

CREATE OR REPLACE FUNCTION enforce_chat_app_daily_limit()
RETURNS TRIGGER AS $$
DECLARE
  daily_count int;
  is_pro      bool;
BEGIN
  -- Only gate the in-app chat channel; every other channel bypasses.
  IF NEW.channel IS DISTINCT FROM 'app' THEN
    RETURN NEW;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM subscriptions
    WHERE user_id = NEW.user_id
      AND status = 'active'
      AND end_date > now()
  ) INTO is_pro;

  -- PRO has no daily cap — ai-proxy/index.ts:597-598 ("isPro gate: PRO -> no daily
  -- cap. Free -> 10 msg/day forever"). Mirror that exemption here.
  IF is_pro THEN
    RETURN NEW;
  END IF;

  -- IST day boundary (Asia/Kolkata) — the app-wide "date keys + resets are IST"
  -- convention (root CLAUDE.md Sec 4.5), matching the idiom already established in
  -- migrations 093/101 (date_trunc(...) AT TIME ZONE 'Asia/Kolkata'). Deliberately
  -- NOT migration 026's date_trunc('day', now()), which truncates in the DB
  -- session's default timezone (UTC on this project — no migration sets a
  -- non-UTC session timezone) and so resets at 05:30 IST, not midnight IST — the
  -- exact H-4 bug class the client side of THIS SAME FILE already fixed once
  -- (pre-batch, via istDayStartIso() in the check-then-insert pre-checks this
  -- batch replaced with the reservation pattern — istDayStartIso() and those
  -- pre-checks no longer exist in ai-proxy/index.ts as of this same commit).
  SELECT count(*) INTO daily_count
  FROM ai_coach_interactions
  WHERE user_id = NEW.user_id
    AND channel = 'app'
    AND created_at >= (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata');

  IF daily_count >= 10 THEN
    RAISE EXCEPTION 'chat_app_daily_limit_reached (cap=10)'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_chat_app_rate_limit ON ai_coach_interactions;

CREATE TRIGGER trg_chat_app_rate_limit
  BEFORE INSERT ON ai_coach_interactions
  FOR EACH ROW EXECUTE FUNCTION enforce_chat_app_daily_limit();


CREATE OR REPLACE FUNCTION enforce_vision_analysis_daily_limit()
RETURNS TRIGGER AS $$
DECLARE
  daily_count int;
BEGIN
  -- Combined scan_meal + cart_auditor cap — ONE shared 15/day budget, mirroring
  -- ai-proxy/index.ts:438-443's `.in("channel", ["scan_meal","cart_auditor"])`
  -- pre-check exactly. Not two independent 15/day caps — supabase/functions/
  -- CLAUDE.md's table describing them as separate per-channel caps is corrected
  -- in the same commit as this migration. No PRO exemption: unlike chat, the
  -- client-side check applies this cap to every tier.
  IF NEW.channel NOT IN ('scan_meal', 'cart_auditor') THEN
    RETURN NEW;
  END IF;

  SELECT count(*) INTO daily_count
  FROM ai_coach_interactions
  WHERE user_id = NEW.user_id
    AND channel IN ('scan_meal', 'cart_auditor')
    AND created_at >= (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata');

  IF daily_count >= 15 THEN
    RAISE EXCEPTION 'vision_analysis_daily_limit_reached (cap=15)'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_vision_analysis_rate_limit ON ai_coach_interactions;

CREATE TRIGGER trg_vision_analysis_rate_limit
  BEFORE INSERT ON ai_coach_interactions
  FOR EACH ROW EXECUTE FUNCTION enforce_vision_analysis_daily_limit();

-- Rollback (inline):
-- DROP TRIGGER IF EXISTS trg_chat_app_rate_limit ON ai_coach_interactions;
-- DROP FUNCTION IF EXISTS enforce_chat_app_daily_limit();
-- DROP TRIGGER IF EXISTS trg_vision_analysis_rate_limit ON ai_coach_interactions;
-- DROP FUNCTION IF EXISTS enforce_vision_analysis_daily_limit();
