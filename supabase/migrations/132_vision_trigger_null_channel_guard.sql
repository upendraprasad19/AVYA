-- Intent: Make enforce_vision_analysis_daily_limit's channel short-circuit NULL-safe (`IS NULL OR … NOT IN`), matching its two siblings' `IS DISTINCT FROM` guards — a NULL channel no longer consumes a vision unit (OI-153 Unit F = OI-183; the residue OI-162 slice 4 parked).
-- Destructive?: no   -- CREATE OR REPLACE of one trigger function; no schema change, no row rewrite
-- Rollback strategy: inline   -- the migration-129 body, commented at the end of the file
-- Linked diagnose-doc: a9d4e7
--
-- 132_vision_trigger_null_channel_guard.sql
--
-- The defect, stated exactly. Migration 129 gave the three cap triggers a
-- channel short-circuit that runs BEFORE consume_quota:
--
--   chat_app   : IF NEW.channel IS DISTINCT FROM 'app' THEN RETURN NEW;
--   food_text  : IF NEW.channel IS DISTINCT FROM 'food_text_analysis' THEN RETURN NEW;
--   vision     : IF NEW.channel NOT IN ('scan_meal', 'cart_auditor') THEN RETURN NEW;
--
-- `IS DISTINCT FROM` treats NULL as a value, so a NULL channel returns early
-- in the first two. `NOT IN` does not: `NULL NOT IN (...)` is NULL, the IF
-- does not fire, and the row falls through to consume_quota — a NULL-channel
-- insert would spend one of the user's 20 daily vision units on a row that
-- is not a vision analysis at all.
--
-- Reachability today: NONE, and that is why this is three lines and not a
-- bug fix. Verified 2026-09-12 (OI-153 plan, ground truth): zero NULL
-- `channel` rows exist in ai_coach_interactions; all 12 writers pass a
-- guarded channel literal; and an authenticated NULL-channel insert fails
-- on RLS/grants (42501) BEFORE the trigger body runs. It is kept because it
-- closes the one residue OI-162 slice 4's channel enumeration left open
-- (docs/audit/oi162-slice4-channel-enumeration.md, filed as OI-183), it
-- ships in the same apply-go as 131, and the sibling asymmetry is exactly
-- the shape a future writer copies.
--
-- The body below is migration 129's vision function VERBATIM except for the
-- guard line, so `test/contracts/cap_triggers_use_usage_counters_test.dart`
-- (which resolves each trigger to its LATEST definer, >= 129) and the OI-153
-- T11 pin (`NEW.channel IS NULL OR`) both read this file.

CREATE OR REPLACE FUNCTION public.enforce_vision_analysis_daily_limit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  new_count int;
BEGIN
  IF NEW.channel IS NULL OR NEW.channel NOT IN ('scan_meal', 'cart_auditor') THEN
    RETURN NEW;
  END IF;

  -- ONE shared budget across both channels, so both map to ONE quota_key.
  new_count := public.consume_quota(
    NEW.user_id,
    'vision_analysis',
    (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata'),
    20
  );

  IF new_count = -1 THEN
    RAISE EXCEPTION 'vision_analysis_daily_limit_reached (cap=20)'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

-- Verify (manual):
--   SELECT pg_get_functiondef('public.enforce_vision_analysis_daily_limit()'::regprocedure);
--   -- expect the IS NULL OR guard; the trigger binding (trg_* on
--   -- ai_coach_interactions) is untouched by CREATE OR REPLACE.

-- ── Rollback (inline) ──────────────────────────────────────────────────────
-- Re-run migration 129's section 3 body, i.e. the same function with
--   IF NEW.channel NOT IN ('scan_meal', 'cart_auditor') THEN
-- as its guard line. Nothing else in this file needs reversing.
