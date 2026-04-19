-- ─────────────────────────────────────────────────────────────────────
-- Task 11 — Layer 4 (Predictive Signals) nightly cron
-- ─────────────────────────────────────────────────────────────────────
-- Pure-SQL computation of three risk signals per active user:
--   • dropout_risk_score      — likelihood of churn in next 14 days
--   • plateau_risk_score      — weight + workout volume stagnation
--   • pro_upgrade_probability — engagement-based upgrade likelihood
--
-- All scores in [0, 1]. Higher = more concerning / more likely.
--
-- Two RPC functions are exposed:
--   1. public.active_users_for_signals()       → set of user_ids to process
--   2. public.compute_coach_signals_for_user() → scores for one user
--
-- The cron job invokes the `compute-coach-signals` Edge Function once
-- per day; the function then loops over active_users_for_signals() and
-- calls compute_coach_signals_for_user() for each, writing results into
-- coach_memory via the shared upsert helper.
--
-- Schedule: 21:00 UTC = 02:30 IST — runs ~30min after rolling-context.
-- ─────────────────────────────────────────────────────────────────────

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

create schema if not exists private;

-- ─────────────────────────────────────────────────────────────────────
-- 1. RPC: active users to process
--    Definition of "active" = not soft-deleted AND has been seen within
--    the last 60 days. Caps at 5000 rows for safety (matches per-user
--    SQL round-trip ceiling documented in the Edge Function).
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.active_users_for_signals()
returns table (user_id uuid)
language sql
security definer
set search_path = public
as $$
  select u.id as user_id
  from public.users u
  where u.is_deleted is not true
    and u.last_active_at is not null
    and u.last_active_at >= now() - interval '60 days'
  order by u.last_active_at desc
  limit 5000;
$$;

revoke all on function public.active_users_for_signals() from public;
grant execute on function public.active_users_for_signals() to service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 2. RPC: compute the three signals for one user
--
-- Formulas (v1 — deterministic, will be tuned with real data):
--
-- dropout_risk_score  (0..1, higher = more likely to churn):
--   • +0.40  if no workout logged in last 14 days
--   • +0.20  if no AI coach interaction in last 7 days
--   • +0.20  if last_active_at > 7 days ago
--   • +0.20  if no weight log in last 30 days
--   Capped at 1.0.
--
-- plateau_risk_score  (0..1, higher = more stuck):
--   • Weight component (+0.50): user has ≥3 weight logs in last 28d
--     AND |max - min| weight < 0.5kg.
--   • Volume component (+0.50): user has ≥6 workout logs in last 28d
--     AND total reps in last 14d ≤ total reps in 14d before that.
--   Capped at 1.0. Returns 0 if not enough data to judge.
--
-- pro_upgrade_probability  (0..1, higher = more likely to upgrade):
--   Only computed for free users (no active paid subscription).
--   • +0.30  if ≥4 workouts in last 14 days (engaged)
--   • +0.30  if ≥10 AI coach interactions in last 14 days (heavy chat)
--   • +0.20  if ≥3 weight logs in last 14 days (tracking)
--   • +0.20  if account ≥21 days old (past initial novelty)
--   Returns 0 for users who already have an active paid subscription.
--   Capped at 1.0.
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.compute_coach_signals_for_user(p_user_id uuid)
returns table (
  dropout_risk_score real,
  plateau_risk_score real,
  pro_upgrade_probability real
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_workouts_14d        int;
  v_workouts_28d        int;
  v_ai_chats_7d         int;
  v_ai_chats_14d        int;
  v_weight_logs_30d     int;
  v_weight_logs_14d     int;
  v_weight_logs_28d     int;
  v_weight_min_28d      numeric;
  v_weight_max_28d      numeric;
  v_reps_recent_14d     bigint;
  v_reps_prior_14d      bigint;
  v_last_active         timestamptz;
  v_account_created     timestamptz;
  v_has_paid_sub        boolean;
  v_dropout             real := 0;
  v_plateau             real := 0;
  v_upgrade             real := 0;
begin
  -- Pull all the counters we need in one go.
  select last_active_at, created_at
    into v_last_active, v_account_created
  from public.users
  where id = p_user_id;

  -- Account doesn't exist or is malformed → return all zeros.
  if v_account_created is null then
    return query select 0::real, 0::real, 0::real;
    return;
  end if;

  select count(*) into v_workouts_14d
    from public.workout_logs
    where user_id = p_user_id and date >= (current_date - 14);

  select count(*) into v_workouts_28d
    from public.workout_logs
    where user_id = p_user_id and date >= (current_date - 28);

  select count(*) into v_ai_chats_7d
    from public.ai_coach_interactions
    where user_id = p_user_id and created_at >= now() - interval '7 days';

  select count(*) into v_ai_chats_14d
    from public.ai_coach_interactions
    where user_id = p_user_id and created_at >= now() - interval '14 days';

  select count(*) into v_weight_logs_30d
    from public.weight_logs
    where user_id = p_user_id and date >= (current_date - 30);

  select count(*) into v_weight_logs_14d
    from public.weight_logs
    where user_id = p_user_id and date >= (current_date - 14);

  select count(*), min(weight_kg), max(weight_kg)
    into v_weight_logs_28d, v_weight_min_28d, v_weight_max_28d
  from public.weight_logs
  where user_id = p_user_id and date >= (current_date - 28);

  select coalesce(sum(reps_completed * sets_completed), 0)
    into v_reps_recent_14d
  from public.workout_logs
  where user_id = p_user_id
    and date >= (current_date - 14);

  select coalesce(sum(reps_completed * sets_completed), 0)
    into v_reps_prior_14d
  from public.workout_logs
  where user_id = p_user_id
    and date >= (current_date - 28)
    and date <  (current_date - 14);

  select exists (
    select 1
    from public.subscriptions
    where user_id = p_user_id
      and status = 'active'
      and end_date > now()
  ) into v_has_paid_sub;

  -- ───────────── Dropout risk ─────────────
  if v_workouts_14d = 0 then
    v_dropout := v_dropout + 0.40;
  end if;
  if v_ai_chats_7d = 0 then
    v_dropout := v_dropout + 0.20;
  end if;
  if v_last_active is null or v_last_active < now() - interval '7 days' then
    v_dropout := v_dropout + 0.20;
  end if;
  if v_weight_logs_30d = 0 then
    v_dropout := v_dropout + 0.20;
  end if;
  v_dropout := least(v_dropout, 1.0);

  -- ───────────── Plateau risk ─────────────
  -- Weight component
  if v_weight_logs_28d >= 3
     and v_weight_min_28d is not null
     and (v_weight_max_28d - v_weight_min_28d) < 0.5 then
    v_plateau := v_plateau + 0.50;
  end if;
  -- Volume component
  if v_workouts_28d >= 6
     and v_reps_prior_14d > 0
     and v_reps_recent_14d <= v_reps_prior_14d then
    v_plateau := v_plateau + 0.50;
  end if;
  v_plateau := least(v_plateau, 1.0);

  -- ───────────── Pro upgrade probability ─────────────
  if v_has_paid_sub then
    v_upgrade := 0;
  else
    if v_workouts_14d >= 4 then
      v_upgrade := v_upgrade + 0.30;
    end if;
    if v_ai_chats_14d >= 10 then
      v_upgrade := v_upgrade + 0.30;
    end if;
    if v_weight_logs_14d >= 3 then
      v_upgrade := v_upgrade + 0.20;
    end if;
    if v_account_created <= now() - interval '21 days' then
      v_upgrade := v_upgrade + 0.20;
    end if;
    v_upgrade := least(v_upgrade, 1.0);
  end if;

  return query select v_dropout, v_plateau, v_upgrade;
end;
$$;

revoke all on function public.compute_coach_signals_for_user(uuid) from public;
grant execute on function public.compute_coach_signals_for_user(uuid) to service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Helper: build the Edge Function URL for compute-coach-signals.
--    Mirrors the morning_alert pattern (vault-aware with hardcoded
--    fallback so cron keeps working if the vault entry is missing).
-- ─────────────────────────────────────────────────────────────────────
create or replace function private.compute_coach_signals_function_url()
returns text
language sql
security definer
as $$
  select coalesce(
    (select decrypted_secret from vault.decrypted_secrets where name = 'project_url' limit 1),
    'https://dedsavbjuwgarrhphgnl.supabase.co'
  ) || '/functions/v1/compute-coach-signals';
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 4. Idempotent cron schedule (21:00 UTC = 02:30 IST).
--    Reuses private.morning_alert_get_service_key() — same vault entry.
-- ─────────────────────────────────────────────────────────────────────
do $$
begin
  perform cron.unschedule('compute_coach_signals');
exception when others then null;
end $$;

select cron.schedule(
  'compute_coach_signals',
  '0 21 * * *',
  $job$
  select net.http_post(
    url := private.compute_coach_signals_function_url(),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || private.morning_alert_get_service_key()
    ),
    body := '{}'::jsonb
  );
  $job$
);

-- ─────────────────────────────────────────────────────────────────────
-- Verify (manual):
--   select * from public.active_users_for_signals() limit 5;
--   select * from public.compute_coach_signals_for_user('<some-uuid>');
--   select jobname, schedule, active from cron.job
--     where jobname = 'compute_coach_signals';
-- ─────────────────────────────────────────────────────────────────────
