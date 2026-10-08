-- Intent: Lower the FREE food_text_analysis daily cap from 50 to 10, so the
--   server agrees with the client and the documented product. Every other
--   source of truth already said 10 — `AppConstants.freeAiTextLogsPerDay = 10`
--   (app_constants.dart:78, enforced at usage_counter_service.dart:127,
--   food_logger_section.dart:107, subscription_section.dart:174) and
--   docs/architecture/business-rules.md:17,36 ("AI food text analysis — 10 text
--   logs/day"). Only this trigger said 50, making it a 5x server-side bypass
--   reachable by calling ai-proxy directly rather than through the app.
--
--   RECURRENCE of f1a70c (2026-06-07), where the client declared the free
--   AI-coach cap as 15/day while the server enforced 10/day. That fix shipped
--   test/contracts/ai_message_limit_parity_test.dart to pin client == server
--   so it could not drift again — but the test covers the CHAT cap only, and
--   food text drifted the same way in the opposite direction. This migration's
--   companion commit widens that test to cover food text and the vision
--   ceiling, which is the half of f1a70c's fix that was missing.
--
--   PRO stays at 200/day (founder decision 2026-09-04). The client returns
--   999999 ("unlimited") for PRO; that divergence is accepted deliberately —
--   200 food logs in one IST day is an abuse ceiling, not a product limit.
--
-- Destructive?: no — CREATE OR REPLACE on an existing function. Only the free
--   arm of `daily_cap` changes (50 -> 10); channel gating, the PRO arm, the IST
--   day boundary and the raised exception are byte-identical to migration 113.
--   No data is touched; this only changes future daily_count evaluation.
--
--   No user loses access they have today: all three client read sites already
--   block at 10, so no in-app user can reach an 11th food-text log. This closes
--   a direct-API bypass rather than removing a capability.
--
-- Rollback strategy: migration 113 — CREATE OR REPLACE back with
--   `daily_cap := CASE WHEN is_pro THEN 200 ELSE 50 END;` restores the prior
--   (drifted) free cap. Note 113 also carries the IST boundary fix, so roll
--   back to 113's body, NOT to migration 026's.
--
-- ⚠ This is the FOURTH definition of enforce_food_text_daily_limit (026 -> 113
--   -> this). The LAST CREATE OR REPLACE wins; a citation into an earlier
--   migration's body is stale by construction. The same trap cost a wrong cap
--   value earlier in this batch's own planning, where migration 111's vision
--   cap (15) was cited as live after migration 114 had already replaced it
--   with 20.
--
-- Linked diagnose-doc: docs/diagnoses/2026-09-04-food-text-free-cap-server-client-drift-b8f4c2.md

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

  -- FREE arm lowered 50 -> 10 to match AppConstants.freeAiTextLogsPerDay and
  -- business-rules.md. Pinned by test/contracts/ai_message_limit_parity_test.dart.
  daily_cap := CASE WHEN is_pro THEN 200 ELSE 10 END;

  -- IST day boundary (Asia/Kolkata) — carried VERBATIM from migration 113.
  -- This expression is the fix for 7ad0d3 (UTC midnight resets the cap at
  -- 05:30 IST); do not re-derive it.
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

-- Rollback (migration 113's body):
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
--   WHERE user_id = NEW.user_id
--     AND channel = 'food_text_analysis'
--     AND created_at >= (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata');
--   IF daily_count >= daily_cap THEN
--     RAISE EXCEPTION 'food_text_daily_limit_reached (cap=%, pro=%)', daily_cap, is_pro
--       USING ERRCODE = 'P0001';
--   END IF;
--   RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql;
