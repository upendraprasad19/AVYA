-- Intent: Raise the combined scan_meal+cart_auditor daily cap from 15 to 20,
--   matching the documented PRO product promise (docs/architecture/business-rules.md:
--   "Scan meal camera — 10 scans/day" + "Cart Auditor — 10 scans/day", independently,
--   for PRO). The 15/day combined value in migration 111 was inherited verbatim from
--   a pre-existing ai-proxy/index.ts check-then-insert pre-check (itself pre-dating
--   this batch) without cross-checking it against the client's documented per-feature
--   PRO limits (AppConstants.proScanMealPerDay=10 + proCartAuditorPerDay=10=20). Once
--   migration 111 turned that pre-check into a real, always-enforced trigger, a
--   compliant PRO client using both features up to their documented independent
--   limits could hit a live 429 well within its own displayed "remaining" counts —
--   confirmed live-discoverable, not hypothetical. Founder decision (2026-07-29,
--   usage-counter-race batch): raise the server to match the documented client
--   promise, not lower the client promise to match the server.
-- Destructive?: no — CREATE OR REPLACE on an existing function; only the numeric
--   threshold and the RAISE EXCEPTION message text change; free-tier chat's separate
--   trg_chat_app_rate_limit function/trigger is untouched.
-- Rollback strategy: inline — CREATE OR REPLACE back to cap=15 (commented at end).
-- Linked diagnose-doc: docs/diagnoses/2026-07-29-usage-counter-race-c9e3b1.md

CREATE OR REPLACE FUNCTION enforce_vision_analysis_daily_limit()
RETURNS TRIGGER AS $$
DECLARE
  daily_count int;
BEGIN
  -- Combined scan_meal + cart_auditor cap — ONE shared 20/day budget, raised from
  -- migration 111's 15 (c9e3b1, 2026-07-29) to match the documented PRO product
  -- promise of 10 scan-meals/day + 10 cart-audits/day INDEPENDENTLY
  -- (docs/architecture/business-rules.md). Still no PRO exemption on the cap
  -- itself — the 20 ceiling already accounts for PRO's full documented combined
  -- allowance; free tier's much lower client-displayed limits (3+1=4) never
  -- approach it.
  IF NEW.channel NOT IN ('scan_meal', 'cart_auditor') THEN
    RETURN NEW;
  END IF;

  SELECT count(*) INTO daily_count
  FROM ai_coach_interactions
  WHERE user_id = NEW.user_id
    AND channel IN ('scan_meal', 'cart_auditor')
    AND created_at >= (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata');

  IF daily_count >= 20 THEN
    RAISE EXCEPTION 'vision_analysis_daily_limit_reached (cap=20)'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Rollback (inline — restores migration 111's cap=15 behavior verbatim):
-- CREATE OR REPLACE FUNCTION enforce_vision_analysis_daily_limit()
-- RETURNS TRIGGER AS $$
-- DECLARE
--   daily_count int;
-- BEGIN
--   IF NEW.channel NOT IN ('scan_meal', 'cart_auditor') THEN
--     RETURN NEW;
--   END IF;
--   SELECT count(*) INTO daily_count
--   FROM ai_coach_interactions
--   WHERE user_id = NEW.user_id
--     AND channel IN ('scan_meal', 'cart_auditor')
--     AND created_at >= (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata');
--   IF daily_count >= 15 THEN
--     RAISE EXCEPTION 'vision_analysis_daily_limit_reached (cap=15)'
--       USING ERRCODE = 'P0001';
--   END IF;
--   RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql;
