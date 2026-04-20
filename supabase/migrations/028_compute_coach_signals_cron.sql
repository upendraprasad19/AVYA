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
-- Formulas (v1 — aligned with plan §"Predictive Signal Formulas"):
--
-- dropout_risk_score  (0..1, higher = more likely to churn):
--   Weighted continuous formula (NOT bucket sums):
--     0.4 * greatest(0, (w_avg - w_now) / nullif(w_avg, 0))
--   + 0.3 * least(1.0, days_silent / 7.0)
--   + 0.2 * least(1.0, days_no_weigh / 14.0)
--   + 0.1 * greatest(0, (6.0 - coalesce(sleep_avg, 7)) / 6.0)
--   where:
--     w_now        = workouts in last 7 days
--     w_avg        = avg workouts/wk in trailing 4-week window (days 7-35)
--     days_silent  = days since last ai_coach_interactions row
--     days_no_weigh= days since last weight_logs row
--     sleep_avg    = avg sleep_logs.duration_hrs in last 7 days
--   Capped at 1.0.
--
-- plateau_risk_score  (0..1, higher = more stuck):
--   • Weight unchanged: |max - min| weight_kg in last 10d < 0.3 (need ≥2 logs)
--   • Caloric surplus: avg daily total_calories (last 10d) > daily_target+100
--   Score: 1.0 if both true, 0.5 if one true, 0.0 if neither / undeterminable.
--   Default daily_target = 2200 kcal if user_profile.daily_calories is null.
--
-- pro_upgrade_probability  (0..1, higher = more likely to upgrade):
--   Discrete buckets (no fancy math at v1). Only for free users.
--   Three gates:
--     • trial_days_remaining < 8  (using created_at proxy: 30 - days_since_signup)
--     • msg_volume > 10/day       (ai_coach_interactions last 7d / 7 > 10)
--     • current_streak > 15 days  (proxied via user_progress.current_streak_weeks > 2)
--   Score: 1.0 if 3/3, 0.66 if 2/3, 0.33 if 1/3, 0.0 if 0/3.
--   Returns 0 for users with active paid subscription.
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
  -- Dropout inputs
  v_w_now               numeric;
  v_w_avg               numeric;
  v_days_silent         numeric;
  v_days_no_weigh       numeric;
  v_sleep_avg           numeric;
  -- Plateau inputs
  v_weight_min_10d      numeric;
  v_weight_max_10d      numeric;
  v_weight_logs_10d     int;
  v_avg_calories_10d    numeric;
  v_daily_calorie_target int;
  v_weight_unchanged    boolean := false;
  v_calorie_surplus     boolean := false;
  v_plateau_components  int := 0;
  -- Pro upgrade inputs
  v_account_created     timestamptz;
  v_trial_days_remaining numeric;
  v_msgs_per_day_7d     numeric;
  v_current_streak_weeks int;
  v_has_paid_sub        boolean;
  v_pro_gates_met       int := 0;
  -- Outputs
  v_dropout             real := 0;
  v_plateau             real := 0;
  v_upgrade             real := 0;
begin
  -- Account anchor.
  select created_at
    into v_account_created
  from public.users
  where id = p_user_id;

  if v_account_created is null then
    return query select 0::real, 0::real, 0::real;
    return;
  end if;

  -- ───────────── Dropout risk inputs ─────────────
  select count(*)::numeric
    into v_w_now
  from public.workout_logs
  where user_id = p_user_id
    and date >= (now() - interval '7 days')::date;

  -- Trailing 4-week average (days 7-35), normalized per week (÷4).
  select count(*)::numeric / 4.0
    into v_w_avg
  from public.workout_logs
  where user_id = p_user_id
    and date >= (now() - interval '35 days')::date
    and date <  (now() - interval '7 days')::date;

  select extract(epoch from now() - max(created_at)) / 86400.0
    into v_days_silent
  from public.ai_coach_interactions
  where user_id = p_user_id;

  select extract(epoch from now() - max(date::timestamptz)) / 86400.0
    into v_days_no_weigh
  from public.weight_logs
  where user_id = p_user_id;

  -- sleep_logs uses `duration_hrs` (NOT `hours` as the plan SQL assumes).
  select avg(duration_hrs)
    into v_sleep_avg
  from public.sleep_logs
  where user_id = p_user_id
    and date >= (now() - interval '7 days')::date;

  -- Weighted continuous formula (plan spec).
  -- Null-handle days_silent / days_no_weigh: treat "never logged" as max risk
  -- by clamping to the 7d / 14d ceiling respectively.
  v_dropout := least(1.0,
      0.4 * greatest(0, (coalesce(v_w_avg, 0) - coalesce(v_w_now, 0)) / nullif(v_w_avg, 0))
    + 0.3 * least(1.0, coalesce(v_days_silent, 7) / 7.0)
    + 0.2 * least(1.0, coalesce(v_days_no_weigh, 14) / 14.0)
    + 0.1 * greatest(0, (6.0 - coalesce(v_sleep_avg, 7)) / 6.0)
  );
  -- The arithmetic above can also be NaN if w_avg is null AND w_now is 0
  -- (greatest(0, x/null) returns null). Coalesce the final score to be safe.
  v_dropout := coalesce(v_dropout, 0)::real;

  -- ───────────── Plateau risk ─────────────
  -- Weight component: weight delta < 0.3kg over last 10 days, ≥2 logs.
  select count(*), min(weight_kg), max(weight_kg)
    into v_weight_logs_10d, v_weight_min_10d, v_weight_max_10d
  from public.weight_logs
  where user_id = p_user_id
    and date >= (now() - interval '10 days')::date;

  if v_weight_logs_10d >= 2
     and v_weight_min_10d is not null
     and (v_weight_max_10d - v_weight_min_10d) < 0.3 then
    v_weight_unchanged := true;
  end if;

  -- Calorie target: prefer user_profile.daily_calories, fall back to 2200.
  -- (Schema gap: plan referenced `daily_calorie_target` which doesn't exist;
  --  `daily_calories` is the actual computed-target column on user_profile.
  --  user_progress has no calorie-target column either.)
  select coalesce(daily_calories, 2200)
    into v_daily_calorie_target
  from public.user_profile
  where user_id = p_user_id
  limit 1;
  v_daily_calorie_target := coalesce(v_daily_calorie_target, 2200);

  -- Avg daily calories over last 10 days (sum-per-day then average).
  select avg(daily_total)
    into v_avg_calories_10d
  from (
    select date, sum(total_calories) as daily_total
    from public.nutrition_logs
    where user_id = p_user_id
      and date >= (now() - interval '10 days')::date
    group by date
  ) d;

  if v_avg_calories_10d is not null
     and v_avg_calories_10d > (v_daily_calorie_target + 100) then
    v_calorie_surplus := true;
  end if;

  v_plateau_components := (case when v_weight_unchanged then 1 else 0 end)
                       + (case when v_calorie_surplus  then 1 else 0 end);
  v_plateau := (case
    when v_plateau_components = 2 then 1.0
    when v_plateau_components = 1 then 0.5
    else 0.0
  end)::real;

  -- ───────────── Pro upgrade probability ─────────────
  select exists (
    select 1
    from public.subscriptions
    where user_id = p_user_id
      and status = 'active'
      and end_date > now()
  ) into v_has_paid_sub;

  if v_has_paid_sub then
    v_upgrade := 0;
  else
    -- trial_days_remaining proxy (no users.current_period_end column):
    -- 30-day trial window from signup.
    v_trial_days_remaining := greatest(
      0,
      30 - extract(epoch from now() - v_account_created) / 86400.0
    );

    -- msg volume per day over last 7 days.
    select count(*)::numeric / 7.0
      into v_msgs_per_day_7d
    from public.ai_coach_interactions
    where user_id = p_user_id
      and created_at >= now() - interval '7 days';

    -- Streak proxy: 15-day streak ≈ >2 consecutive weeks of streak maintained.
    -- (No daily streak in Postgres — Hive holds that. user_progress is closest.)
    select coalesce(current_streak_weeks, 0)
      into v_current_streak_weeks
    from public.user_progress
    where user_id = p_user_id
    limit 1;
    v_current_streak_weeks := coalesce(v_current_streak_weeks, 0);

    if v_trial_days_remaining < 8 then
      v_pro_gates_met := v_pro_gates_met + 1;
    end if;
    if coalesce(v_msgs_per_day_7d, 0) > 10 then
      v_pro_gates_met := v_pro_gates_met + 1;
    end if;
    if v_current_streak_weeks > 2 then
      v_pro_gates_met := v_pro_gates_met + 1;
    end if;

    v_upgrade := (case
      when v_pro_gates_met = 3 then 1.0
      when v_pro_gates_met = 2 then 0.66
      when v_pro_gates_met = 1 then 0.33
      else 0.0
    end)::real;
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
