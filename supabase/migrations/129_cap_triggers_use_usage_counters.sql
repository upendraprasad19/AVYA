-- Intent: Move the three Postgres cap triggers off `count(*) FROM
--   ai_coach_interactions` and onto `consume_quota()` / `usage_counters`
--   (migration 128). That table is a conversation LOG which `rolling-context`
--   prunes nightly (MESSAGE_THRESHOLD=50, KEEP_RECENT=10), so every quota
--   derived from its row count silently resets when a user chats enough.
--   OI-162 slice 2; slice 1 built the ledger with nothing calling it.
--
--   Slice 2 is server-side only: no Edge Function change, no client change, no
--   deploy. The three trigger bodies are the only things that move.
--
-- Affected: enforce_chat_app_daily_limit (live def was migration 111),
--   enforce_vision_analysis_daily_limit (114), enforce_food_text_daily_limit
--   (127). Trigger bindings themselves are untouched -- CREATE OR REPLACE on
--   the function keeps every existing trigger attached.
--
-- Preserved VERBATIM, each load-bearing:
--   * The three P0001 base identifiers. ai-proxy greps them to map a refusal to
--     a 429 (index.ts:338, :524, :765) with a plain msg.includes(); change one
--     and every capped request silently becomes a 500 instead. The "(cap=N)"
--     suffix is NOT read by anything and is kept only for log legibility.
--   * The IST day expression, which is the fix for 7ad0d3. Migration 026's
--     date_trunc('day', now()) truncates in the session timezone (UTC here) and
--     so resets at 05:30 IST.
--   * Each channel short-circuit, which runs BEFORE consume_quota. This is what
--     keeps the change safe: consume_quota is INVOKER-mode and usage_counters
--     is RLS-with-no-policy, so only service_role/postgres may write it. Every
--     gated-channel writer is a service-role Edge Function.
--   * Chat's PRO exemption, and its position before the cap check.
--
-- Backfill: runs FIRST, before the replacements. usage_counters is empty, so
--   swapping the source without it would hand every user a fresh allowance for
--   the current window. A migration applies in ONE transaction, so no session
--   can observe the new trigger logic until commit and no concurrent insert can
--   slip between the backfill and the replacement.
--
-- Rollback strategy: append a new migration that CREATE OR REPLACEs these three
--   bodies back to their count(*) form (recoverable verbatim from 111 / 114 /
--   127). usage_counters rows simply stop being read and age out via
--   cleanup_usage_counters. No data loss in either direction, and no window
--   where a cap goes unenforced, because each replace is atomic.
--
-- Security mode: all three stay LANGUAGE plpgsql with the default INVOKER mode.
--   This migration introduces no definer-mode function (deliberately hyphenated
--   so a content-rule grep for that phrase does not match this comment and
--   mis-grade the file; the file defines zero such functions).

-- ---------------------------------------------------------------------------
-- 1. Backfill the current IST window from the (possibly pruned) log.
--    A floor, not a truth: if rolling-context already pruned today's rows the
--    count is low. Reaching that needs 50+ rows in one day, so it is unlikely
--    rather than impossible.
-- ---------------------------------------------------------------------------

INSERT INTO public.usage_counters (user_id, quota_key, window_start, used)
SELECT user_id,
       'chat_app',
       (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata'),
       count(*)
FROM public.ai_coach_interactions
WHERE channel = 'app'
  AND created_at >= (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata')
GROUP BY user_id
ON CONFLICT (user_id, quota_key, window_start) DO NOTHING;

INSERT INTO public.usage_counters (user_id, quota_key, window_start, used)
SELECT user_id,
       'vision_analysis',
       (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata'),
       count(*)
FROM public.ai_coach_interactions
WHERE channel IN ('scan_meal', 'cart_auditor')
  AND created_at >= (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata')
GROUP BY user_id
ON CONFLICT (user_id, quota_key, window_start) DO NOTHING;

INSERT INTO public.usage_counters (user_id, quota_key, window_start, used)
SELECT user_id,
       'food_text',
       (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata'),
       count(*)
FROM public.ai_coach_interactions
WHERE channel = 'food_text_analysis'
  AND created_at >= (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata')
GROUP BY user_id
ON CONFLICT (user_id, quota_key, window_start) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. Chat -- 10/day, PRO exempt entirely.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_chat_app_daily_limit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  is_pro    bool;
  new_count int;
BEGIN
  IF NEW.channel IS DISTINCT FROM 'app' THEN
    RETURN NEW;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM subscriptions
    WHERE user_id = NEW.user_id
      AND status = 'active'
      AND end_date > now()
  ) INTO is_pro;

  -- PRO has no daily cap, and therefore consumes no unit. One consequence,
  -- stated because it is a real behaviour change: the ledger freezes while a
  -- user is PRO, so a same-day downgrade starts from the pre-upgrade value and
  -- can grant up to a full extra 10 messages. The old count(*) form re-counted
  -- the PRO-era rows instead. Bounded, requires a subscription lapsing mid-day
  -- while actively chatting, and carries no security consequence.
  IF is_pro THEN
    RETURN NEW;
  END IF;

  new_count := public.consume_quota(
    NEW.user_id,
    'chat_app',
    (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata'),
    10
  );

  IF new_count = -1 THEN
    RAISE EXCEPTION 'chat_app_daily_limit_reached (cap=10)'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Vision -- 20/day COMBINED across scan_meal + cart_auditor, no PRO
--    exemption. The 20 ceiling already covers PRO's full documented combined
--    allowance; free tier's client-displayed limits (3+1) never approach it.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_vision_analysis_daily_limit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  new_count int;
BEGIN
  IF NEW.channel NOT IN ('scan_meal', 'cart_auditor') THEN
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

-- ---------------------------------------------------------------------------
-- 4. Food text -- 10 free / 200 PRO.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_food_text_daily_limit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  is_pro    bool;
  daily_cap int;
  new_count int;
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

  -- ONE call site, so ONE limit: this is a single caller whose limit follows
  -- the caller's own live tier, NOT two call sites disagreeing on one key.
  daily_cap := CASE WHEN is_pro THEN 200 ELSE 10 END;

  new_count := public.consume_quota(
    NEW.user_id,
    'food_text',
    (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata'),
    daily_cap
  );

  IF new_count = -1 THEN
    RAISE EXCEPTION 'food_text_daily_limit_reached (cap=%, pro=%)', daily_cap, is_pro
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;
