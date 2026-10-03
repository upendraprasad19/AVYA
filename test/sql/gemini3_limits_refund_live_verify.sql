-- test/sql/gemini3_limits_refund_live_verify.sql
--
-- Part B (gemini3-limits-caching, migration 153). Live-Postgres behavioural
-- verification of `refund_quota` and the tier-aware chat/vision caps. Wrapped in
-- BEGIN ... ROLLBACK: nothing persists. Run by the FOUNDER (or on the founder's
-- explicit go) after migration 153 is applied, via the MCP `execute_sql` or:
--
--   dart run scripts/check_onconflict_live_arbiter.dart \
--       --sql test/sql/gemini3_limits_refund_live_verify.sql
--
-- Agents never run this against production on their own: it inserts synthetic
-- rows (inside the rolled-back transaction) into live tables.
--
-- Why this file exists. The Deno tests prove ai-proxy CALLS `refund_quota` after
-- the right failures; the Dart parity tests prove the cap NUMBERS agree. Neither
-- can prove the SQL BEHAVES: that the latch lets exactly one caller refund, that
-- the 3/day budget stops the fourth, that the ledger never goes negative, that the
-- window is the IST day of the ROW, that PRO media rows burn no chat unit, and that
-- anon/authenticated cannot call it. Every assertion below is written so it is RED
-- against the pre-153 code (no refund_quota at all, or the 129 chat trigger that
-- counted every channel-'app' row and exempted PRO) and GREEN after it.
--
-- Discrimination, per case:
--   R1 latch        refund twice -> 2nd returns -1, used moved ONCE.
--   R2 budget       3 refunds succeed, 4th stamps the row but leaves used alone.
--   R3 used>0 guard a refund against an absent ledger row, AND (R3b) against an existing
--                   used=0 row, never goes negative and does NOT spend the refund budget.
--   R4 channel map  scan_meal/cart_auditor -> vision_analysis, food_text_analysis ->
--                   food_text, 'app' -> chat_app; an unmapped channel is latched but
--                   never touches a counter.
--   R5 not pending  a non-'pending' row (a PRO media row) is not refundable.
--   R6 row window   the unit is returned to the ROW's own IST day, not to today's counter
--                   (a yesterday-dated row therefore does not decrement today's window;
--                   the 23:59 -> 00:01 case itself cannot be tested: now() is frozen in a txn).
--   R7 PRO consumes chat 20/day, the 21st is refused; PRO media rows burn nothing.
--   R8 vision tier  free 4 / PRO 20 on one shared key.
--   R9 ACL          anon + authenticated cannot EXECUTE refund_quota; service_role can.

BEGIN;

CREATE TEMP TABLE _v_results (
  label    text PRIMARY KEY,
  status   text NOT NULL,        -- 'ok' | 'fail'
  sqlstate text,
  msg      text
) ON COMMIT DROP;

DO $g3$
DECLARE
  u_refund  uuid := '00000000-0000-0000-0000-0000000b53a1'::uuid;
  u_budget  uuid := '00000000-0000-0000-0000-0000000b53a2'::uuid;
  u_pro     uuid := '00000000-0000-0000-0000-0000000b53a3'::uuid;
  u_vfree   uuid := '00000000-0000-0000-0000-0000000b53a4'::uuid;
  u_vpro    uuid := '00000000-0000-0000-0000-0000000b53a5'::uuid;
  v_now     timestamptz := now();
  v_window  timestamptz := (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata');
  v_id      uuid;
  v_ids     uuid[] := '{}';
  v_ret     int;
  v_used    int;
  v_before_r6 int;
  v_budget_used int;
  v_label   text;
  i         int;
BEGIN
  -- Fixtures. The user seeds are best-effort (they may already exist); the PRO
  -- subscriptions are NOT, because a missing PRO row would make R7/R8 assert
  -- about a free user (the slice-2 lesson in oi46_daily_cap_triggers_live_verify.sql).
  BEGIN
    INSERT INTO auth.users (id, email, created_at) VALUES
      (u_refund, 'test+g3-refund@avya.local', v_now),
      (u_budget, 'test+g3-budget@avya.local', v_now),
      (u_pro,    'test+g3-pro@avya.local',    v_now),
      (u_vfree,  'test+g3-vfree@avya.local',  v_now),
      (u_vpro,   'test+g3-vpro@avya.local',   v_now)
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  BEGIN
    INSERT INTO public.users (id, email, full_name) VALUES
      (u_refund, 'test+g3-refund@avya.local', 'g3 refund'),
      (u_budget, 'test+g3-budget@avya.local', 'g3 budget'),
      (u_pro,    'test+g3-pro@avya.local',    'g3 pro'),
      (u_vfree,  'test+g3-vfree@avya.local',  'g3 vfree'),
      (u_vpro,   'test+g3-vpro@avya.local',   'g3 vpro')
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date) VALUES
    (u_pro,  'pro_monthly', 'active', v_now, v_now + interval '30 days'),
    (u_vpro, 'pro_monthly', 'active', v_now, v_now + interval '30 days');

  -- R1 — LATCH. Reserve one chat unit, refund it twice.
  BEGIN
    INSERT INTO public.ai_coach_interactions (user_id, channel, user_message, model_used)
    VALUES (u_refund, 'app', 'g3 r1', 'pending') RETURNING id INTO v_id;
    SELECT used INTO v_used FROM public.usage_counters
     WHERE user_id = u_refund AND quota_key = 'chat_app' AND window_start = v_window;
    IF v_used IS DISTINCT FROM 1 THEN
      INSERT INTO _v_results VALUES ('r1_fixture_reservation_consumed', 'fail', NULL,
        'expected used=1 after the reservation, got ' || coalesce(v_used::text, 'NO ROW'));
    END IF;

    v_ret := public.refund_quota(v_id, 'failed');
    SELECT used INTO v_used FROM public.usage_counters
     WHERE user_id = u_refund AND quota_key = 'chat_app' AND window_start = v_window;
    SELECT model_used INTO v_label FROM public.ai_coach_interactions WHERE id = v_id;
    IF v_ret IS DISTINCT FROM 0 OR v_used IS DISTINCT FROM 0 OR v_label IS DISTINCT FROM 'failed' THEN
      INSERT INTO _v_results VALUES ('r1_first_refund_returns_unit_and_latches', 'fail', NULL,
        'ret=' || coalesce(v_ret::text,'NULL') || ' used=' || coalesce(v_used::text,'NULL')
        || ' label=' || coalesce(v_label,'NULL') || ' (expected 0 / 0 / failed)');
    ELSE
      INSERT INTO _v_results VALUES ('r1_first_refund_returns_unit_and_latches', 'ok', NULL,
        'used 1 -> 0, row stamped failed');
    END IF;

    -- A second unit, so a wrongly-repeated refund would visibly move `used`.
    INSERT INTO public.ai_coach_interactions (user_id, channel, user_message, model_used)
    VALUES (u_refund, 'app', 'g3 r1b', 'pending');
    v_ret := public.refund_quota(v_id, 'failed');   -- same, already-latched row
    SELECT used INTO v_used FROM public.usage_counters
     WHERE user_id = u_refund AND quota_key = 'chat_app' AND window_start = v_window;
    IF v_ret IS DISTINCT FROM -1 OR v_used IS DISTINCT FROM 1 THEN
      INSERT INTO _v_results VALUES ('r1_second_refund_is_a_noop', 'fail', NULL,
        'ret=' || coalesce(v_ret::text,'NULL') || ' used=' || coalesce(v_used::text,'NULL')
        || ' (expected -1 / 1: the latch must stop a repeat)');
    ELSE
      INSERT INTO _v_results VALUES ('r1_second_refund_is_a_noop', 'ok', NULL,
        'second call returned -1, used unchanged at 1');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('r1_latch_block', 'fail', SQLSTATE, SQLERRM);
  END;

  -- R2 — BUDGET. Five reservations; refunds 1-3 return a unit, the 4th stamps the
  -- row but leaves `used` alone because refund_budget (3/day) is spent.
  BEGIN
    FOR i IN 1..5 LOOP
      INSERT INTO public.ai_coach_interactions (user_id, channel, user_message, model_used)
      VALUES (u_budget, 'app', 'g3 r2 ' || i, 'pending') RETURNING id INTO v_id;
      v_ids := v_ids || v_id;
    END LOOP;
    FOR i IN 1..3 LOOP
      v_ret := public.refund_quota(v_ids[i], 'failed');
    END LOOP;
    SELECT used INTO v_used FROM public.usage_counters
     WHERE user_id = u_budget AND quota_key = 'chat_app' AND window_start = v_window;
    IF v_used IS DISTINCT FROM 2 THEN
      INSERT INTO _v_results VALUES ('r2_three_refunds_return_three_units', 'fail', NULL,
        'expected used=2 (5 reserved - 3 refunded), got ' || coalesce(v_used::text,'NULL'));
    ELSE
      INSERT INTO _v_results VALUES ('r2_three_refunds_return_three_units', 'ok', NULL, 'used 5 -> 2');
    END IF;

    v_ret := public.refund_quota(v_ids[4], 'failed');
    SELECT used INTO v_used FROM public.usage_counters
     WHERE user_id = u_budget AND quota_key = 'chat_app' AND window_start = v_window;
    SELECT model_used INTO v_label FROM public.ai_coach_interactions WHERE id = v_ids[4];
    IF v_ret IS DISTINCT FROM -1 OR v_used IS DISTINCT FROM 2 OR v_label IS DISTINCT FROM 'failed' THEN
      INSERT INTO _v_results VALUES ('r2_fourth_refund_budget_spent', 'fail', NULL,
        'ret=' || coalesce(v_ret::text,'NULL') || ' used=' || coalesce(v_used::text,'NULL')
        || ' label=' || coalesce(v_label,'NULL') || ' (expected -1 / 2 / failed)');
    ELSE
      INSERT INTO _v_results VALUES ('r2_fourth_refund_budget_spent', 'ok', NULL,
        'row latched failed, used unchanged at 2, budget stopped the 4th');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('r2_budget_block', 'fail', SQLSTATE, SQLERRM);
  END;

  -- R3 — absent ledger row: no negative, no row created (the used>0 guard itself is R3b).
  BEGIN
    INSERT INTO public.ai_coach_interactions (user_id, channel, user_message, model_used)
    VALUES (u_vfree, 'scan_meal', 'g3 r3', 'pending') RETURNING id INTO v_id;
    DELETE FROM public.usage_counters
     WHERE user_id = u_vfree AND quota_key = 'vision_analysis';
    v_ret := public.refund_quota(v_id, 'failed_gemini');
    SELECT used INTO v_used FROM public.usage_counters
     WHERE user_id = u_vfree AND quota_key = 'vision_analysis' AND window_start = v_window;
    IF v_ret IS DISTINCT FROM -1 OR v_used IS NOT NULL THEN
      INSERT INTO _v_results VALUES ('r3_refund_never_goes_negative', 'fail', NULL,
        'ret=' || coalesce(v_ret::text,'NULL') || ' used=' || coalesce(v_used::text,'NULL')
        || ' (expected -1 and NO row)');
    ELSE
      INSERT INTO _v_results VALUES ('r3_refund_never_goes_negative', 'ok', NULL,
        'no ledger row -> -1, nothing created or decremented');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('r3_refund_never_goes_negative', 'fail', SQLSTATE, SQLERRM);
  END;

  -- R3b — the used>0 guard against an EXISTING zero row (R3 deleted the row, so it could
  -- not tell the guard from "no row"). A pending cart reservation, then the ledger row is
  -- forced to 0 by hand: the refund must return -1, leave used at 0 (not -1) and leave the
  -- refund budget unspent.
  BEGIN
    INSERT INTO public.ai_coach_interactions (user_id, channel, user_message, model_used)
    VALUES (u_vfree, 'cart_auditor', 'g3 r3b', 'pending') RETURNING id INTO v_id;
    UPDATE public.usage_counters SET used = 0
     WHERE user_id = u_vfree AND quota_key = 'vision_analysis' AND window_start = v_window;
    v_ret := public.refund_quota(v_id, 'failed_gemini');
    SELECT used INTO v_used FROM public.usage_counters
     WHERE user_id = u_vfree AND quota_key = 'vision_analysis' AND window_start = v_window;
    SELECT used INTO v_budget_used FROM public.usage_counters
     WHERE user_id = u_vfree AND quota_key = 'refund_budget' AND window_start = v_window;
    IF v_ret IS DISTINCT FROM -1 OR v_used IS DISTINCT FROM 0 OR coalesce(v_budget_used, 0) <> 0 THEN
      INSERT INTO _v_results VALUES ('r3b_zero_row_not_decremented_budget_kept', 'fail', NULL,
        'ret=' || coalesce(v_ret::text,'NULL') || ' used=' || coalesce(v_used::text,'NULL')
        || ' refund_budget used=' || coalesce(v_budget_used::text,'NULL')
        || ' (expected -1 / 0 / 0 or no row)');
    ELSE
      INSERT INTO _v_results VALUES ('r3b_zero_row_not_decremented_budget_kept', 'ok', NULL,
        'used stayed 0, return -1, refund budget not spent');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('r3b_zero_row_not_decremented_budget_kept', 'fail', SQLSTATE, SQLERRM);
  END;

  -- R4 — CHANNEL MAP + unmapped channel.
  BEGIN
    -- food_text_analysis -> food_text
    INSERT INTO public.ai_coach_interactions (user_id, channel, user_message, model_used)
    VALUES (u_vpro, 'food_text_analysis', 'g3 r4 food', 'pending') RETURNING id INTO v_id;
    v_ret := public.refund_quota(v_id, 'failed_gemini');
    SELECT used INTO v_used FROM public.usage_counters
     WHERE user_id = u_vpro AND quota_key = 'food_text' AND window_start = v_window;
    IF v_ret IS DISTINCT FROM 0 OR v_used IS DISTINCT FROM 0 THEN
      INSERT INTO _v_results VALUES ('r4_food_text_maps_to_food_text', 'fail', NULL,
        'ret=' || coalesce(v_ret::text,'NULL') || ' used=' || coalesce(v_used::text,'NULL'));
    ELSE
      INSERT INTO _v_results VALUES ('r4_food_text_maps_to_food_text', 'ok', NULL, 'food_text 1 -> 0');
    END IF;

    -- cart_auditor -> vision_analysis (shared with scan_meal)
    INSERT INTO public.ai_coach_interactions (user_id, channel, user_message, model_used)
    VALUES (u_vpro, 'scan_meal', 'g3 r4 scan', 'pending');
    INSERT INTO public.ai_coach_interactions (user_id, channel, user_message, model_used)
    VALUES (u_vpro, 'cart_auditor', 'g3 r4 cart', 'pending') RETURNING id INTO v_id;
    v_ret := public.refund_quota(v_id, 'failed_gemini');
    SELECT used INTO v_used FROM public.usage_counters
     WHERE user_id = u_vpro AND quota_key = 'vision_analysis' AND window_start = v_window;
    IF v_ret IS DISTINCT FROM 1 OR v_used IS DISTINCT FROM 1 THEN
      INSERT INTO _v_results VALUES ('r4_cart_maps_to_shared_vision_key', 'fail', NULL,
        'ret=' || coalesce(v_ret::text,'NULL') || ' used=' || coalesce(v_used::text,'NULL')
        || ' (expected 1 / 1: scan + cart on one key, cart refunded)');
    ELSE
      INSERT INTO _v_results VALUES ('r4_cart_maps_to_shared_vision_key', 'ok', NULL, 'vision_analysis 2 -> 1');
    END IF;

    -- unmapped channel: latched (terminal) but no counter touched
    INSERT INTO public.ai_coach_interactions (user_id, channel, user_message, model_used)
    VALUES (u_vpro, 'in_app_orphan', 'g3 r4 orphan', 'pending') RETURNING id INTO v_id;
    v_ret := public.refund_quota(v_id, 'failed');
    SELECT model_used INTO v_label FROM public.ai_coach_interactions WHERE id = v_id;
    IF v_ret IS DISTINCT FROM -1 OR v_label IS DISTINCT FROM 'failed' THEN
      INSERT INTO _v_results VALUES ('r4_unmapped_channel_latched_not_refunded', 'fail', NULL,
        'ret=' || coalesce(v_ret::text,'NULL') || ' label=' || coalesce(v_label,'NULL'));
    ELSE
      INSERT INTO _v_results VALUES ('r4_unmapped_channel_latched_not_refunded', 'ok', NULL,
        'row stamped failed, nothing refunded');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('r4_channel_map_block', 'fail', SQLSTATE, SQLERRM);
  END;

  -- R5 — a NON-pending row (a PRO media row) is not refundable.
  BEGIN
    INSERT INTO public.ai_coach_interactions (user_id, channel, user_message, model_used)
    VALUES (u_pro, 'app', 'g3 r5 media', 'Gemini 3.1 Flash Lite (Vision)') RETURNING id INTO v_id;
    v_ret := public.refund_quota(v_id, 'failed');
    SELECT model_used INTO v_label FROM public.ai_coach_interactions WHERE id = v_id;
    IF v_ret IS DISTINCT FROM -1 OR v_label IS DISTINCT FROM 'Gemini 3.1 Flash Lite (Vision)' THEN
      INSERT INTO _v_results VALUES ('r5_non_pending_row_not_refundable', 'fail', NULL,
        'ret=' || coalesce(v_ret::text,'NULL') || ' label=' || coalesce(v_label,'NULL'));
    ELSE
      INSERT INTO _v_results VALUES ('r5_non_pending_row_not_refundable', 'ok', NULL,
        'real-label row left untouched, -1');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('r5_non_pending_row_not_refundable', 'fail', SQLSTATE, SQLERRM);
  END;

  -- R6 — WINDOW = the IST day of the ROW's created_at. A reservation created
  -- "yesterday" charged TODAY's window (the trigger uses now()); refunding it
  -- targets YESTERDAY's window, which holds no row, so today's unit is NOT given
  -- back. This pins that the window comes from the ROW, not from now() (a mutation
  -- to now() would redden it). It does NOT exercise the 23:59 -> 00:01 case, which
  -- cannot be reproduced inside one transaction; there the unit goes back to the
  -- day it was charged in, which is no longer the cap in force (documented, harmless).
  BEGIN
    INSERT INTO public.ai_coach_interactions (user_id, channel, user_message, model_used, created_at)
    VALUES (u_vfree, 'cart_auditor', 'g3 r6 old', 'pending', v_now - interval '1 day') RETURNING id INTO v_id;
    SELECT used INTO v_before_r6 FROM public.usage_counters
     WHERE user_id = u_vfree AND quota_key = 'vision_analysis' AND window_start = v_window;
    v_ret := public.refund_quota(v_id, 'failed');
    SELECT used INTO v_used FROM public.usage_counters
     WHERE user_id = u_vfree AND quota_key = 'vision_analysis' AND window_start = v_window;
    IF v_ret IS DISTINCT FROM -1 OR v_used IS DISTINCT FROM v_before_r6 THEN
      INSERT INTO _v_results VALUES ('r6_refund_targets_the_rows_ist_day', 'fail', NULL,
        'ret=' || coalesce(v_ret::text,'NULL') || ' used today before/after='
        || coalesce(v_before_r6::text,'NULL') || '/' || coalesce(v_used::text,'NULL'));
    ELSE
      INSERT INTO _v_results VALUES ('r6_refund_targets_the_rows_ist_day', 'ok', NULL,
        'a yesterday-dated row did not decrement today''s window');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('r6_refund_targets_the_rows_ist_day', 'fail', SQLSTATE, SQLERRM);
  END;

  -- R7 — PRO consumes chat (20/day, 21st refused with pro=true); PRO media rows burn nothing.
  BEGIN
    FOR i IN 1..20 LOOP
      INSERT INTO public.ai_coach_interactions (user_id, channel, user_message, model_used)
      VALUES (u_pro, 'app', 'g3 r7 ' || i, 'pending');
    END LOOP;
    INSERT INTO public.ai_coach_interactions (user_id, channel, user_message, model_used)
    VALUES (u_pro, 'app', 'g3 r7 media', 'Gemini 3.1 Flash Lite (Vision)');   -- must NOT count
    SELECT used INTO v_used FROM public.usage_counters
     WHERE user_id = u_pro AND quota_key = 'chat_app' AND window_start = v_window;
    IF v_used IS DISTINCT FROM 20 THEN
      INSERT INTO _v_results VALUES ('r7_pro_chat_counts_reservations_only', 'fail', NULL,
        'expected used=20, got ' || coalesce(v_used::text,'NULL'));
    ELSE
      INSERT INTO _v_results VALUES ('r7_pro_chat_counts_reservations_only', 'ok', NULL,
        '20 PRO reservations counted; the PRO media row (non-pending) burned nothing');
    END IF;
    BEGIN
      INSERT INTO public.ai_coach_interactions (user_id, channel, user_message, model_used)
      VALUES (u_pro, 'app', 'g3 r7 21', 'pending');
      INSERT INTO _v_results VALUES ('r7_pro_21st_refused', 'fail', NULL, 'the 21st PRO reservation succeeded');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
      IF SQLERRM LIKE '%chat_app_daily_limit_reached%' AND SQLERRM LIKE '%cap=20%' AND SQLERRM LIKE '%pro=true%' THEN
        INSERT INTO _v_results VALUES ('r7_pro_21st_refused', 'ok', 'P0001', SQLERRM);
      ELSE
        INSERT INTO _v_results VALUES ('r7_pro_21st_refused', 'fail', 'P0001', SQLERRM);
      END IF;
    END;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('r7_pro_chat_block', 'fail', SQLSTATE, SQLERRM);
  END;

  -- R8 — PRO vision cap 20 on one shared key. u_vpro holds 1 unit from R4 (scan
  -- reserved, cart reserved then refunded); 19 more are accepted (20 total) and the
  -- next is refused. The FREE cap of 4 is asserted in oi46_daily_cap_triggers_live_verify.sql.
  BEGIN
    FOR i IN 1..19 LOOP
      INSERT INTO public.ai_coach_interactions (user_id, channel, user_message, model_used)
      VALUES (u_vpro, 'scan_meal', 'g3 r8 pro ' || i, 'pending');
    END LOOP;
    BEGIN
      INSERT INTO public.ai_coach_interactions (user_id, channel, user_message, model_used)
      VALUES (u_vpro, 'cart_auditor', 'g3 r8 pro 21', 'pending');
      INSERT INTO _v_results VALUES ('r8_vision_pro_cap_20', 'fail', NULL, 'PRO vision accepted past 20');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
      IF SQLERRM LIKE '%vision_analysis_daily_limit_reached%' AND SQLERRM LIKE '%cap=20%' AND SQLERRM LIKE '%pro=true%' THEN
        INSERT INTO _v_results VALUES ('r8_vision_pro_cap_20', 'ok', 'P0001', SQLERRM);
      ELSE
        INSERT INTO _v_results VALUES ('r8_vision_pro_cap_20', 'fail', 'P0001', SQLERRM);
      END IF;
    END;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('r8_vision_pro_cap_20', 'fail', SQLSTATE, SQLERRM);
  END;

  -- R9 — ACL: only service_role may call refund_quota.
  BEGIN
    IF has_function_privilege('anon', 'public.refund_quota(uuid,text)', 'execute')
       OR has_function_privilege('authenticated', 'public.refund_quota(uuid,text)', 'execute')
       OR NOT has_function_privilege('service_role', 'public.refund_quota(uuid,text)', 'execute') THEN
      INSERT INTO _v_results VALUES ('r9_refund_quota_acl_service_role_only', 'fail', NULL,
        'anon=' || has_function_privilege('anon', 'public.refund_quota(uuid,text)', 'execute')::text
        || ' authenticated=' || has_function_privilege('authenticated', 'public.refund_quota(uuid,text)', 'execute')::text
        || ' service_role=' || has_function_privilege('service_role', 'public.refund_quota(uuid,text)', 'execute')::text
        || ' (expected false / false / true; the default privileges grant anon+authenticated directly)');
    ELSE
      INSERT INTO _v_results VALUES ('r9_refund_quota_acl_service_role_only', 'ok', NULL, 'anon=f authenticated=f service_role=t');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('r9_refund_quota_acl_service_role_only', 'fail', SQLSTATE, SQLERRM);
  END;
END;
$g3$;

SELECT label, status, sqlstate, msg FROM _v_results ORDER BY label;

ROLLBACK;
