-- Intent: ai_messages_today counted EVERY ai_coach_interactions row (analytics, food AI, ceremonies and stuck rows included) — a 5.3x overcount; restrict it to real coach turns, and add hold-week telemetry columns so the free-tier hold mechanic stops being unobservable.
-- Destructive?: no   -- DROP + recreate of ONE read-only SECURITY DEFINER function inside a single transaction; no table, column, row or user grant is touched, and no data is readable-then-lost. The DROP is REQUIRED, not incidental: Postgres refuses CREATE OR REPLACE when the return type changes (42P13), and this adds three columns to the `returns table` list.
-- Rollback strategy: inline   -- reverse DDL (the verbatim pre-120 body) is at the end of this file
-- Linked diagnose-doc: c7a3b9

-- ─────────────────────────────────────────────────────────────────────
-- FOB-5 of OI-60 (docs/ship_dark_pending_review.yaml).
--
-- TWO defects in one function, one of them LIVE for the founder dashboard today.
--
-- (1) ai_messages_today had NO channel predicate. AppEventsService
--     (lib/core/services/app_events_service.dart:28,44) writes analytics rows
--     into ai_coach_interactions with channel='app_event', so every UI event
--     counted as an "AI message". Measured live 2026-08-20: 116 rows all-time,
--     of which only 22 are real coach turns — a 5.3x overcount.
--
--     ⚠ FOB-5 prescribed `where channel = 'app'`. That is WRONG and was NOT
--     applied: channel='app' is 7 rows of 116, so it would have replaced the
--     overcount with an ~89% UNDERCOUNT. The repo's own canonical definition is
--     `_coachChatChannels = {'app','chat','in_app_orphan'}`
--     (lib/features/ai_coach/repositories/coach_interaction_repository.dart:282,
--     SoT concept coach_chat_history_replay) and that is what this mirrors, so
--     the dashboard and the app agree on what a coach message IS.
--
--     The content predicate is the second half and FOB-5 does not mention it:
--     38 of the 53 in_app_orphan rows carry no ai_response or model_used
--     'pending' (the stuck-row class of the 2026-05-16 ai-proxy placeholder
--     diagnose). A channel filter alone still counts all 38.
--
--     Measured effect, all-time: 116 -> 22.
--       app_event ............ 22 rows, 0 real turns   (analytics)
--       food_text_analysis ... 24 rows                 (food AI, not coach chat)
--       promotion_ceremony .... 5 rows, 0 real turns   (templated)
--       in_app ................ 5 rows, 0 real turns   (not in the SoT set)
--       in_app_orphan ........ 53 rows, 15 real turns  (38 stuck/pending)
--       app ................... 7 rows,  7 real turns
--
-- (2) Hold weeks were unobservable. The five phase_1_day_29_* events have ZERO
--     consumers repo-wide, so holds-taken / hold->convert / hold->churn are all
--     unmeasurable — and the retention thesis rests on that mechanic. The three
--     hold_* columns below are that consumer.
--
--     They ride on founder_metrics_engagement() DELIBERATELY, rather than a new
--     founder_metrics_holds() RPC: admin-dashboard-data/index.ts:255 spreads
--     this function's row wholesale (`...(engagementRes.data ?? {})`), so new
--     COLUMNS reach the dashboard with NO Edge Function redeploy, while a new
--     RPC would need one (its own §4.3 authorization) and would otherwise sit
--     dormant — the exact "shipped but nothing calls it" failure OI-101 records.
--
--     The rows are matched on user_message LIKE '%hold_week_started%' because
--     AppEventsService serializes `{event: ..., ...metadata}` with Dart's
--     Map.toString() into user_message (app_events_service.dart:39-52). Not
--     elegant; it is the existing storage contract and this migration does not
--     change it.
--
--     Expect 0 until enable_hold_weeks flips — that is correct, not a bug.
-- ─────────────────────────────────────────────────────────────────────

-- Return type gains three columns, so CREATE OR REPLACE alone raises
-- 42P13 ("cannot change return type of existing function"). Drop first.
-- apply_migration wraps this in a transaction, so the function is never
-- observably absent to a concurrent admin-dashboard-data call.
drop function if exists public.founder_metrics_engagement();

create function public.founder_metrics_engagement()
returns table (
  workouts_logged_today          bigint,
  food_logs_today                bigint,
  ai_messages_today              bigint,
  streak_maintained_current_week bigint,
  holds_started_today            bigint,
  holds_started_7d               bigint,
  holders_total                  bigint,
  generated_at                   timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    (select count(*) from public.workout_logs
       where date = (now() at time zone 'Asia/Kolkata')::date)::bigint,
    (select count(*) from public.nutrition_logs
       where date = (now() at time zone 'Asia/Kolkata')::date)::bigint,
    -- Real coach turns only. Mirrors _coachChatChannels + drops stuck rows.
    (select count(*) from public.ai_coach_interactions
       where created_at >= (date_trunc('day', now() at time zone 'Asia/Kolkata')
                            at time zone 'Asia/Kolkata')
         and channel in ('app', 'chat', 'in_app_orphan')
         and coalesce(user_message, '') <> ''
         and coalesce(ai_response, '')  <> '')::bigint,
    (select count(*) from (
       select distinct on (user_id) user_id, is_streak_maintained
       from public.streaks
       order by user_id, week_start desc
     ) latest
     where latest.is_streak_maintained is true)::bigint,
    -- ── FOB-5 hold telemetry ────────────────────────────────────────
    (select count(*) from public.ai_coach_interactions
       where channel = 'app_event'
         and user_message like '%hold_week_started%'
         and created_at >= (date_trunc('day', now() at time zone 'Asia/Kolkata')
                            at time zone 'Asia/Kolkata'))::bigint,
    (select count(*) from public.ai_coach_interactions
       where channel = 'app_event'
         and user_message like '%hold_week_started%'
         and created_at >= now() - interval '7 days')::bigint,
    (select count(distinct user_id) from public.ai_coach_interactions
       where channel = 'app_event'
         and user_message like '%hold_week_started%')::bigint,
    now();
$$;

-- ⚠ GRANTS — the DROP above makes this materially different from a
-- CREATE OR REPLACE, and getting it wrong ships an anon-executable
-- SECURITY DEFINER function.
--
-- CREATE OR REPLACE preserves the existing ACL. A DROP + CREATE does NOT: the
-- new function is created fresh, and Supabase's DEFAULT PRIVILEGES on schema
-- public re-grant EXECUTE to `anon` and `authenticated`. `revoke all ... from
-- public` does NOT remove those — PUBLIC and an explicit role grant are
-- different things — so migration 101's two grant lines, copied verbatim, are
-- NOT sufficient here.
--
-- This was not theoretical: the first live apply of this migration (2026-08-20)
-- left the function with acl {postgres=X,anon=X,authenticated=X,service_role=X}
-- while its two siblings (founder_metrics_ops, founder_metrics_for_admin_api)
-- carry only {postgres=X,service_role=X}. Caught by the tier-8 grant check in
-- the diagnose-doc's touched_layers_checked and revoked minutes later.
--
-- Verify after ANY replay:
--   select proacl::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--    where n.nspname='public' and p.proname='founder_metrics_engagement';
--   -- expect exactly: {postgres=X/postgres,service_role=X/postgres}
revoke all on function public.founder_metrics_engagement() from public;
revoke execute on function public.founder_metrics_engagement() from anon, authenticated;
grant execute on function public.founder_metrics_engagement() to service_role;

-- Verification (run after apply):
--   select * from public.founder_metrics_engagement();
--   select has_function_privilege('anon',          'public.founder_metrics_engagement()', 'execute');  -- expect false
--   select has_function_privilege('authenticated', 'public.founder_metrics_engagement()', 'execute');  -- expect false
--   select has_function_privilege('service_role',  'public.founder_metrics_engagement()', 'execute');  -- expect true

-- ── ROLLBACK (inline) ────────────────────────────────────────────────
-- Restores the verbatim pre-120 body. NOTE the return signature shrinks back to
-- 5 columns, so admin-dashboard-data simply stops receiving the hold_* keys —
-- it spreads the row and never names them, so no redeploy is needed to revert.
--
-- drop function if exists public.founder_metrics_engagement();
-- create function public.founder_metrics_engagement()
-- returns table (
--   workouts_logged_today          bigint,
--   food_logs_today                bigint,
--   ai_messages_today              bigint,
--   streak_maintained_current_week bigint,
--   generated_at                   timestamptz
-- )
-- language sql security definer set search_path = public
-- as $$
--   select
--     (select count(*) from public.workout_logs
--        where date = (now() at time zone 'Asia/Kolkata')::date)::bigint,
--     (select count(*) from public.nutrition_logs
--        where date = (now() at time zone 'Asia/Kolkata')::date)::bigint,
--     (select count(*) from public.ai_coach_interactions
--        where created_at >= (date_trunc('day', now() at time zone 'Asia/Kolkata')
--                             at time zone 'Asia/Kolkata'))::bigint,
--     (select count(*) from (
--        select distinct on (user_id) user_id, is_streak_maintained
--        from public.streaks order by user_id, week_start desc
--      ) latest where latest.is_streak_maintained is true)::bigint,
--     now();
-- $$;
