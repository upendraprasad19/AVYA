-- Intent: Make user_progress.current_streak_weeks and user_progress.last_workout_date monotonic on the server, so a stale
--   restore can no longer push an OLDER value over a newer one (both were a bare COALESCE: any non-null resend won), and
--   clamp last_workout_date to IST-today + 1 so a device with a clock set ahead cannot store a future date that nothing
--   can lower. Body-only change to update_user_progress_snapshot: the SIGNATURE IS UNCHANGED (13 parameters), so no
--   overload, no DROP, no ACL reset (CREATE OR REPLACE preserves the existing grants and the function comment) and every
--   shipped client keeps working untouched.
-- Destructive?: no   -- CREATE OR REPLACE of a function with an unchanged signature; no row, column or grant is touched.
-- Rollback strategy: inline   -- reverse block at end of file. An APPLIED migration file is immutable, so a rollback is a
--   NEW minted migration number that re-creates the function with migration 115's body (the literal block below).
-- Linked diagnose-doc: 47de4f

CREATE OR REPLACE FUNCTION public.update_user_progress_snapshot(
  p_user_id uuid,
  p_expected_version bigint,
  p_current_phase integer,
  p_current_week integer,
  p_phase_started_at timestamptz,
  p_plan_generated_at timestamptz,
  p_total_workouts_done integer,
  p_current_streak_weeks integer,
  p_detected_experience_level text,
  p_deployments_complete integer,
  p_current_streak_days integer,
  p_last_workout_date date,
  p_longest_gap_days integer
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_current_version BIGINT;
  v_new_version BIGINT;
  -- The NULL branch is explicit and lives HERE so the fresh-INSERT branch and the UPDATE branch both use it:
  -- LEAST(NULL, x) is x, so an unguarded clamp would turn every NULL date (the onboarding replay sends NULL) into
  -- IST-tomorrow, and GREATEST would then pin it there.
  v_date DATE := CASE
    WHEN p_last_workout_date IS NULL THEN NULL
    ELSE LEAST(p_last_workout_date, ((now() AT TIME ZONE 'Asia/Kolkata')::date + 1))
  END;
BEGIN
  -- Security (mirrors update_streak_progress / mig 090): an authenticated caller may only write its OWN progress.
  -- service_role / cron (auth.uid() IS NULL) pass through.
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'p_user_id must not be null';
  END IF;
  IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'cross-account progress write blocked (caller % != target %)',
      auth.uid(), p_user_id;
  END IF;

  SELECT streak_progress_version INTO v_current_version
    FROM public.user_progress
    WHERE user_id = p_user_id
    FOR UPDATE;

  IF NOT FOUND THEN
    IF p_expected_version IS NULL OR p_expected_version <> 0 THEN
      RETURN NULL;
    END IF;

    INSERT INTO public.user_progress (
      user_id, current_phase, current_week, phase_started_at,
      plan_generated_at, total_workouts_done, current_streak_weeks,
      detected_experience_level, deployments_complete, current_streak_days,
      last_workout_date, longest_gap_days, streak_progress_version, updated_at
    ) VALUES (
      p_user_id, COALESCE(p_current_phase, 1), COALESCE(p_current_week, 1),
      p_phase_started_at, p_plan_generated_at,
      COALESCE(p_total_workouts_done, 0), COALESCE(p_current_streak_weeks, 0),
      p_detected_experience_level, COALESCE(p_deployments_complete, 0),
      COALESCE(p_current_streak_days, 0), v_date,
      COALESCE(p_longest_gap_days, 0), 1, now()
    )
    ON CONFLICT (user_id) DO NOTHING;

    IF NOT FOUND THEN
      RETURN NULL;
    END IF;
    RETURN 1;
  END IF;

  IF p_expected_version IS NULL OR v_current_version <> p_expected_version THEN
    RETURN NULL;
  END IF;

  v_new_version := v_current_version + 1;
  -- Every right-hand side below reads the OLD row (a Postgres UPDATE evaluates all of them against the pre-update row).
  UPDATE public.user_progress
    SET current_phase = COALESCE(p_current_phase, current_phase),
        current_week = COALESCE(p_current_week, current_week),
        phase_started_at = COALESCE(p_phase_started_at, phase_started_at),
        plan_generated_at = COALESCE(p_plan_generated_at, plan_generated_at),
        total_workouts_done =
          GREATEST(COALESCE(p_total_workouts_done, total_workouts_done), total_workouts_done),
        -- NEW: GREATEST, the three siblings' shape (the client's restore already treats this field as monotonic).
        current_streak_weeks =
          GREATEST(COALESCE(p_current_streak_weeks, current_streak_weeks), current_streak_weeks),
        detected_experience_level =
          COALESCE(p_detected_experience_level, detected_experience_level),
        deployments_complete =
          GREATEST(COALESCE(p_deployments_complete, deployments_complete), deployments_complete),
        current_streak_days = COALESCE(p_current_streak_days, current_streak_days),
        -- NEW: latest date wins (GREATEST ignores NULL on either side), clamped to IST-today + 1 in v_date.
        last_workout_date = GREATEST(v_date, last_workout_date),
        longest_gap_days =
          GREATEST(COALESCE(p_longest_gap_days, longest_gap_days), longest_gap_days),
        streak_progress_version = v_new_version,
        updated_at = now()
    WHERE user_id = p_user_id
      AND streak_progress_version = p_expected_version;
  RETURN v_new_version;
END;
$function$;

-- Closing assertions (they run inside the migration's own transaction: a failure aborts and rolls back the whole file).
-- CREATE OR REPLACE preserves the grants, so this PROVES nothing moved: exactly ONE function of that name, the exact
-- EXECUTE grantee SET (compared with aclexplode, not as text), the search_path, SECURITY DEFINER, 13 parameters.
DO $assert_fn$
DECLARE
  v_count integer;
  v_grantees text[];
  v_cfg text[];
  v_secdef boolean;
  v_nargs integer;
BEGIN
  SELECT count(*) INTO v_count
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'update_user_progress_snapshot';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'expected exactly one update_user_progress_snapshot, found %', v_count;
  END IF;

  SELECT array_agg(g ORDER BY g) INTO v_grantees FROM (
    SELECT DISTINCT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE r.rolname END AS g
      FROM pg_proc p
      CROSS JOIN LATERAL aclexplode(p.proacl) a
      LEFT JOIN pg_roles r ON r.oid = a.grantee
     WHERE p.oid = 'public.update_user_progress_snapshot(uuid, bigint, integer, integer, timestamptz, timestamptz, integer, integer, text, integer, integer, date, integer)'::regprocedure
       AND a.privilege_type = 'EXECUTE'
  ) s;
  IF v_grantees IS DISTINCT FROM ARRAY['authenticated', 'postgres', 'service_role']::text[] THEN
    RAISE EXCEPTION 'unexpected EXECUTE grantees: %', v_grantees;
  END IF;

  SELECT p.proconfig, p.prosecdef, p.pronargs INTO v_cfg, v_secdef, v_nargs
    FROM pg_proc p
   WHERE p.oid = 'public.update_user_progress_snapshot(uuid, bigint, integer, integer, timestamptz, timestamptz, integer, integer, text, integer, integer, date, integer)'::regprocedure;
  IF v_secdef IS NOT TRUE OR v_cfg IS DISTINCT FROM ARRAY['search_path=public']::text[] OR v_nargs <> 13 THEN
    RAISE EXCEPTION 'SECURITY DEFINER / search_path / arity not as designed: % / % / %', v_secdef, v_cfg, v_nargs;
  END IF;
END
$assert_fn$;

-- ROLLBACK (inline, commented, LITERAL). A rollback is a NEW minted migration number. Run it inside your OWN transaction.
-- It re-creates the SAME 13-parameter signature with migration 115's semantics (bare COALESCE for current_streak_weeks and
-- last_workout_date, no clamp). The grants and the comment are preserved by CREATE OR REPLACE. A test un-comments this
-- block and compares its function body, comments stripped, with migration 115's.
--
-- CREATE OR REPLACE FUNCTION public.update_user_progress_snapshot(
--   p_user_id uuid,
--   p_expected_version bigint,
--   p_current_phase integer,
--   p_current_week integer,
--   p_phase_started_at timestamptz,
--   p_plan_generated_at timestamptz,
--   p_total_workouts_done integer,
--   p_current_streak_weeks integer,
--   p_detected_experience_level text,
--   p_deployments_complete integer,
--   p_current_streak_days integer,
--   p_last_workout_date date,
--   p_longest_gap_days integer
-- )
-- RETURNS bigint
-- LANGUAGE plpgsql
-- SECURITY DEFINER
-- SET search_path = public
-- AS $function$
-- DECLARE
--   v_current_version BIGINT;
--   v_new_version BIGINT;
-- BEGIN
--   IF p_user_id IS NULL THEN
--     RAISE EXCEPTION 'p_user_id must not be null';
--   END IF;
--   IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
--     RAISE EXCEPTION 'cross-account progress write blocked (caller % != target %)',
--       auth.uid(), p_user_id;
--   END IF;
--
--   SELECT streak_progress_version INTO v_current_version
--     FROM public.user_progress
--     WHERE user_id = p_user_id
--     FOR UPDATE;
--
--   IF NOT FOUND THEN
--     IF p_expected_version IS NULL OR p_expected_version <> 0 THEN
--       RETURN NULL;
--     END IF;
--
--     INSERT INTO public.user_progress (
--       user_id, current_phase, current_week, phase_started_at,
--       plan_generated_at, total_workouts_done, current_streak_weeks,
--       detected_experience_level, deployments_complete, current_streak_days,
--       last_workout_date, longest_gap_days, streak_progress_version, updated_at
--     ) VALUES (
--       p_user_id, COALESCE(p_current_phase, 1), COALESCE(p_current_week, 1),
--       p_phase_started_at, p_plan_generated_at,
--       COALESCE(p_total_workouts_done, 0), COALESCE(p_current_streak_weeks, 0),
--       p_detected_experience_level, COALESCE(p_deployments_complete, 0),
--       COALESCE(p_current_streak_days, 0), p_last_workout_date,
--       COALESCE(p_longest_gap_days, 0), 1, now()
--     )
--     ON CONFLICT (user_id) DO NOTHING;
--
--     IF NOT FOUND THEN
--       RETURN NULL;
--     END IF;
--     RETURN 1;
--   END IF;
--
--   IF p_expected_version IS NULL OR v_current_version <> p_expected_version THEN
--     RETURN NULL;
--   END IF;
--
--   v_new_version := v_current_version + 1;
--   UPDATE public.user_progress
--     SET current_phase = COALESCE(p_current_phase, current_phase),
--         current_week = COALESCE(p_current_week, current_week),
--         phase_started_at = COALESCE(p_phase_started_at, phase_started_at),
--         plan_generated_at = COALESCE(p_plan_generated_at, plan_generated_at),
--         total_workouts_done =
--           GREATEST(COALESCE(p_total_workouts_done, total_workouts_done), total_workouts_done),
--         current_streak_weeks = COALESCE(p_current_streak_weeks, current_streak_weeks),
--         detected_experience_level =
--           COALESCE(p_detected_experience_level, detected_experience_level),
--         deployments_complete =
--           GREATEST(COALESCE(p_deployments_complete, deployments_complete), deployments_complete),
--         current_streak_days = COALESCE(p_current_streak_days, current_streak_days),
--         last_workout_date = COALESCE(p_last_workout_date, last_workout_date),
--         longest_gap_days =
--           GREATEST(COALESCE(p_longest_gap_days, longest_gap_days), longest_gap_days),
--         streak_progress_version = v_new_version,
--         updated_at = now()
--     WHERE user_id = p_user_id
--       AND streak_progress_version = p_expected_version;
--   RETURN v_new_version;
-- END;
-- $function$;
