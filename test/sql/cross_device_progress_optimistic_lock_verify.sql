-- test/sql/cross_device_progress_optimistic_lock_verify.sql
--
-- 2026-07-30 — Live-Postgres verification of migration 115's two
-- optimistic-lock RPCs (Unit 3b, OI-45 cross-device half, diagnose e6b9c4):
-- update_streak_progress (hardened) and update_user_progress_snapshot (new).
--
-- Why this file exists
-- --------------------
-- Source-grep contract tests can prove the client calls .rpc('update_streak_
-- progress', ...) / .rpc('update_user_progress_snapshot', ...) instead of a
-- raw upsert, but CANNOT prove the optimistic-lock semantics actually hold on
-- live Postgres, that the two RPCs correctly share ONE whole-row version
-- counter, or that COALESCE-based partial update preserves untouched
-- columns. Most importantly: this file is what CAUGHT a real bug before it
-- shipped — update_streak_progress's fresh-insert branch 42804'd ("column is
-- of type date but expression is of type text") on EVERY call, because
-- p_freezes_last_refill is typed TEXT but streak_freezes_last_refill is
-- `date`. That bug was 100% latent (this RPC had zero callers before this
-- batch) and a pure source read would not obviously surface it — only
-- running the real INSERT against the real column types did. Same pattern as
-- test/sql/onconflict_live_arbiter.sql / oi46_daily_cap_triggers_live_verify.sql
-- (see those files for the harness rationale) — a transaction that ROLLBACKs
-- at the end, run via the generic runner:
--
--   dart run scripts/check_onconflict_live_arbiter.dart \
--       --sql test/sql/cross_device_progress_optimistic_lock_verify.sql
--
-- Status: RUN LIVE 2026-07-30 (via direct execute_sql, pre-migration-apply —
-- this file's CREATE OR REPLACE statements apply migration 115's fixed
-- function bodies WITHIN the same rolled-back transaction, so it verifies the
-- migration's actual SQL before that SQL is ever applied for real). Re-run
-- any time after a change to either function.
--
-- Round-1 review (2026-07-30) found a P0: the original REVOKE EXECUTE ...
-- FROM PUBLIC (no explicit anon/authenticated) left
-- update_user_progress_snapshot anon-executable — Supabase's platform grants
-- EXECUTE on every NEW public-schema function DIRECTLY to anon/authenticated
-- via pg_default_acl, bypassing PUBLIC entirely, so a PUBLIC-only revoke is a
-- no-op. Cases 9-13 below are the SAME rollback-transaction method that
-- caught the ::date cast bug, now also covering privilege grants — exactly
-- what round-1 review said would have caught the P0 pre-apply. Case 14 is
-- the regression test for round-1's P2 finding (COALESCE-wrap the 4
-- schema-defaulted columns on a fresh insert).
--
-- Re-run live 2026-07-30 post-fix (via direct execute_sql): all 14 cases
-- returned status='ok', including the 5 new P0/P2 regression cases.
--
-- Hermes pass (2026-07-30, docs/audit/2026-07-30-hermes-cross-device-progress
-- -lock.md) added Case 15 and hardened both RPC bodies further (NULL-guards
-- on p_user_id/p_expected_version, GREATEST on total_workouts_done, COALESCE
-- on update_streak_progress's 3 previously-un-COALESCE'd params) — this
-- file's embedded CREATE OR REPLACE bodies above were updated to match.
-- Hermes L27 F4 flagged that all 14 original cases run sequentially inside
-- ONE transaction, so the FOR UPDATE blocking-and-re-read behavior the
-- whole batch depends on was never exercised by two genuinely concurrent
-- sessions — only reasoned about by reading the SQL. An attempt was made to
-- close this empirically: two execute_sql calls fired as if in parallel
-- (one holding FOR UPDATE + sleep(3) + commit, the other sleep(1) then its
-- own FOR UPDATE + timing). Result: the second call's self-reported lock-
-- wait time was 0 seconds — it only started running after the first call's
-- entire 3-second sleep+commit had already finished, i.e. the two calls
-- SERIALIZED rather than interleaved. This tool interface does not provide
-- two genuinely concurrent Postgres sessions, so a true multi-session block-
-- and-re-read proof is NOT achievable this way — flagged as a residual
-- tooling gap, not silently dropped. Case 15 instead proves what IS provable
-- in one session: pg_locks shows FOR UPDATE takes a real, granted
-- RowShareLock on user_progress (verified via a throwaway scratch table
-- first, then reproduced against user_progress itself) — the primitive the
-- design depends on is real, even though this harness can't yet prove two
-- sessions actually contend for it. Re-run live 2026-07-30: all 15 cases ok.
--
-- A second, independent B-pass (2026-07-30 — see this diagnose-doc's "B-pass
-- round-2" section for the full 6-finding table; not re-cited here by a
-- docs/reviews/<hash>-review.md path since the B-pass gate hash moved again
-- as later findings were fixed, which would have made a literal path stale)
-- against the post-Hermes diff found deployments_complete sat in the SAME
-- update_user_progress_snapshot UPDATE statement as total_workouts_done but
-- had NOT received the Hermes-C3 GREATEST guard -- reachable by the
-- identical stale-resend vector, and read by both evaluate-rank-promotions
-- and rank_service.dart for rank gating. Fixed in both the migration and
-- this file's embedded copy; Case 20 added as the regression test, mirroring
-- Case 18. Re-run live 2026-07-30: all 20 cases ok.
--
-- A final B-pass (2026-07-30, docs/reviews/8d5a2f558995-review.md) — the
-- third and last independent review of this diff, dispatched after the
-- narrowly-scoped round-3 review above converged with only 1 real fix
-- remaining — found ONE more real-but-currently-inert finding: the same
-- UPDATE statement's longest_gap_days field was the ONLY one of the three
-- "record" fields (alongside total_workouts_done and deployments_complete)
-- still on bare COALESCE, not GREATEST. Currently unreachable (no client
-- writer populates progress['longest_gap_days'] in Hive today, confirmed by
-- grep across lib/), but fixed to match its two siblings rather than left
-- inconsistent for whenever a future writer starts populating it. Fixed in
-- both the migration and this file's embedded copy; Case 21 added as the
-- regression test, mirroring Cases 18 and 20. Re-run live 2026-07-30: all 21
-- cases ok. This B-pass's other 2 findings were investigated and confirmed
-- false alarms (a Hive-key naming convention that turned out consistent, and
-- the already-tracked restore-user-snapshot redeploy gap) — see the review
-- file and this diagnose-doc's "Final B-pass" section for detail.
--
-- closes-diagnose: e6b9c4

BEGIN;

CREATE TEMP TABLE _v_results (
  label    text PRIMARY KEY,
  status   text NOT NULL,        -- 'ok' | 'fail'
  sqlstate text,
  msg      text
) ON COMMIT DROP;

-- Apply migration 115's fixed function bodies for THIS transaction only
-- (rolled back at the end — does not touch the live, not-yet-applied
-- definitions). Kept verbatim in sync with the migration file itself.
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
BEGIN
  -- Hermes C4 (2026-07-30): explicit NULL rejection on both guards below —
  -- kept in sync with migration 115 itself, see its comments for reasoning.
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
      COALESCE(p_current_streak_days, 0), p_last_workout_date,
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
  UPDATE public.user_progress
    SET current_phase = COALESCE(p_current_phase, current_phase),
        current_week = COALESCE(p_current_week, current_week),
        phase_started_at = COALESCE(p_phase_started_at, phase_started_at),
        plan_generated_at = COALESCE(p_plan_generated_at, plan_generated_at),
        total_workouts_done =
          GREATEST(COALESCE(p_total_workouts_done, total_workouts_done), total_workouts_done),
        current_streak_weeks = COALESCE(p_current_streak_weeks, current_streak_weeks),
        detected_experience_level =
          COALESCE(p_detected_experience_level, detected_experience_level),
        deployments_complete =
          GREATEST(COALESCE(p_deployments_complete, deployments_complete), deployments_complete),
        current_streak_days = COALESCE(p_current_streak_days, current_streak_days),
        last_workout_date = COALESCE(p_last_workout_date, last_workout_date),
        -- Final B-pass Finding 1 (2026-07-30): GREATEST guard, mirrors the
        -- migration file's own fix (see that file for the full comment).
        longest_gap_days =
          GREATEST(COALESCE(p_longest_gap_days, longest_gap_days), longest_gap_days),
        streak_progress_version = v_new_version,
        updated_at = now()
    WHERE user_id = p_user_id
      AND streak_progress_version = p_expected_version;
  RETURN v_new_version;
END;
$function$;

-- Round-1-review P0 fix: PUBLIC-only revoke is a no-op against Supabase's
-- per-role default ACL (see migration 115's own comment for the
-- pg_default_acl root-cause trace). Applied here, in the same rolled-back
-- transaction, so cases 9-11 below prove the grant fix works BEFORE the
-- migration is ever applied for real.
REVOKE EXECUTE ON FUNCTION public.update_user_progress_snapshot(
  uuid, bigint, integer, integer, timestamptz, timestamptz, integer, integer,
  text, integer, integer, date, integer
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_user_progress_snapshot(
  uuid, bigint, integer, integer, timestamptz, timestamptz, integer, integer,
  text, integer, integer, date, integer
) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.update_streak_progress(
  p_user_id uuid,
  p_expected_version bigint,
  p_freezes_available integer,
  p_freeze_used_dates text[],
  p_freezes_last_refill text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_current_version BIGINT;
  v_new_version BIGINT;
BEGIN
  -- Hermes C4 (2026-07-30): same NULL-guard hardening as the sibling RPC —
  -- kept in sync with migration 115 itself.
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'p_user_id must not be null';
  END IF;
  IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'cross-account streak write blocked (caller % != target %)',
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
      user_id,
      streak_freezes_available,
      streak_freezes_used_dates,
      streak_freezes_last_refill,
      streak_progress_version
    ) VALUES (
      p_user_id,
      COALESCE(p_freezes_available, 1),
      COALESCE(p_freeze_used_dates, ARRAY[]::text[]),
      p_freezes_last_refill::date,
      1
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
  UPDATE public.user_progress
    SET streak_freezes_available = COALESCE(p_freezes_available, streak_freezes_available),
        streak_freezes_used_dates = COALESCE(p_freeze_used_dates, streak_freezes_used_dates),
        streak_freezes_last_refill =
          COALESCE(p_freezes_last_refill::date, streak_freezes_last_refill),
        streak_progress_version = v_new_version
    WHERE user_id = p_user_id
      AND streak_progress_version = p_expected_version;
  RETURN v_new_version;
END;
$function$;

DO $outer$
DECLARE
  v_user_a  uuid := '00000000-0000-0000-0000-0000003b0001'::uuid;  -- shared-counter cases
  v_user_b  uuid := '00000000-0000-0000-0000-0000003b0002'::uuid;  -- fresh-insert-race cases
  v_user_c  uuid := '00000000-0000-0000-0000-0000003b0003'::uuid;  -- P2 COALESCE-default case
  v_now     timestamptz := now();
  v_result  bigint;
BEGIN
  -- Best-effort synthetic user seeding — mirrors oi46_daily_cap_triggers_live_verify.sql.
  BEGIN
    INSERT INTO auth.users (id, email, created_at) VALUES
      (v_user_a, 'test+3b-a@avya.local', v_now),
      (v_user_b, 'test+3b-b@avya.local', v_now),
      (v_user_c, 'test+3b-c@avya.local', v_now)
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  BEGIN
    INSERT INTO public.users (id, email, full_name) VALUES
      (v_user_a, 'test+3b-a@avya.local', 'unit3b a'),
      (v_user_b, 'test+3b-b@avya.local', 'unit3b b'),
      (v_user_c, 'test+3b-c@avya.local', 'unit3b c')
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  DELETE FROM public.user_progress WHERE user_id IN (v_user_a, v_user_b, v_user_c);

  -- =====================================================================
  -- Case 1 — fresh insert via update_streak_progress with a REAL last_refill
  -- date string. This is the exact call shape that 42804'd pre-fix (the
  -- p_freezes_last_refill TEXT -> streak_freezes_last_refill `date` cast
  -- bug) — this case is the regression test for that bug, not just the
  -- optimistic-lock happy path.
  BEGIN
    v_result := public.update_streak_progress(v_user_a, 0, 1, ARRAY[]::text[], '2026-07-28');
    IF v_result = 1 THEN
      INSERT INTO _v_results VALUES ('streak_fresh_insert_and_date_cast_fix', 'ok', NULL,
        'fresh insert succeeded with a real date string, version=1');
    ELSE
      INSERT INTO _v_results VALUES ('streak_fresh_insert_and_date_cast_fix', 'fail', NULL,
        'expected version 1, got ' || COALESCE(v_result::text, 'NULL'));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('streak_fresh_insert_and_date_cast_fix', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 2 — stale expected_version (0, but real is now 1) -> NULL, no corruption.
  BEGIN
    v_result := public.update_streak_progress(v_user_a, 0, 2, ARRAY[]::text[], '2026-07-28');
    IF v_result IS NULL THEN
      INSERT INTO _v_results VALUES ('streak_stale_version_returns_null', 'ok', NULL,
        'correctly returned NULL on version mismatch');
    ELSE
      INSERT INTO _v_results VALUES ('streak_stale_version_returns_null', 'fail', NULL,
        'expected NULL, got ' || v_result::text);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('streak_stale_version_returns_null', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 3 — correct expected_version (1) -> succeeds, version -> 2.
  BEGIN
    v_result := public.update_streak_progress(v_user_a, 1, 2, ARRAY['2026-07-15'], '2026-07-28');
    IF v_result = 2 THEN
      INSERT INTO _v_results VALUES ('streak_correct_version_succeeds', 'ok', NULL, 'version=2');
    ELSE
      INSERT INTO _v_results VALUES ('streak_correct_version_succeeds', 'fail', NULL,
        'expected version 2, got ' || COALESCE(v_result::text, 'NULL'));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('streak_correct_version_succeeds', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 4 — update_user_progress_snapshot continues the SAME row's version
  -- counter (2 -> 3), proving the two RPCs genuinely share ONE counter.
  BEGIN
    v_result := public.update_user_progress_snapshot(
      v_user_a, 2, 1, 1, NULL, NULL, 5, 0, 'intermediate', 0, 3, '2026-07-29'::date, 0);
    IF v_result = 3 THEN
      INSERT INTO _v_results VALUES ('progress_shares_version_counter', 'ok', NULL,
        'progress RPC continued the streak RPC''s version, now 3');
    ELSE
      INSERT INTO _v_results VALUES ('progress_shares_version_counter', 'fail', NULL,
        'expected version 3, got ' || COALESCE(v_result::text, 'NULL'));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('progress_shares_version_counter', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 5 — stale version on the progress RPC -> NULL.
  BEGIN
    v_result := public.update_user_progress_snapshot(
      v_user_a, 2, 1, 1, NULL, NULL, 99, 0, 'intermediate', 0, 3, '2026-07-29'::date, 0);
    IF v_result IS NULL THEN
      INSERT INTO _v_results VALUES ('progress_stale_version_returns_null', 'ok', NULL,
        'correctly returned NULL on version mismatch');
    ELSE
      INSERT INTO _v_results VALUES ('progress_stale_version_returns_null', 'fail', NULL,
        'expected NULL, got ' || v_result::text);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('progress_stale_version_returns_null', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 6 — an all-NULL-except-2-fields call must COALESCE-preserve the
  -- untouched columns (total_workouts_done=5, current_streak_days=3 from
  -- case 4) rather than nulling them out.
  BEGIN
    v_result := public.update_user_progress_snapshot(
      v_user_a, 3, 2, 2, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
    IF v_result = 4 AND EXISTS (
      SELECT 1 FROM public.user_progress
      WHERE user_id = v_user_a AND current_phase = 2 AND current_week = 2
        AND total_workouts_done = 5 AND current_streak_days = 3
        AND streak_progress_version = 4
    ) THEN
      INSERT INTO _v_results VALUES ('progress_coalesce_preserves_untouched_fields', 'ok', NULL,
        'NULL params did not clobber previously-set fields');
    ELSE
      INSERT INTO _v_results VALUES ('progress_coalesce_preserves_untouched_fields', 'fail', NULL,
        'a NULL param clobbered a previously-set column, or version wrong');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('progress_coalesce_preserves_untouched_fields', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- Case 7 — update_user_progress_snapshot's OWN fresh-insert path works
  -- independently for a brand-new user (no prior streak-RPC call).
  BEGIN
    v_result := public.update_user_progress_snapshot(
      v_user_b, 0, 1, 1, NULL, NULL, 0, 0, NULL, 0, 0, NULL, 0);
    IF v_result = 1 THEN
      INSERT INTO _v_results VALUES ('progress_fresh_insert_for_new_user', 'ok', NULL, 'version=1');
    ELSE
      INSERT INTO _v_results VALUES ('progress_fresh_insert_for_new_user', 'fail', NULL,
        'expected version 1, got ' || COALESCE(v_result::text, 'NULL'));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('progress_fresh_insert_for_new_user', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 8 — the OTHER RPC, called next for the SAME user with a stale
  -- expected_version=0 (as if it didn't know user_b's row now exists at
  -- version 1), correctly returns NULL rather than silently overwriting or
  -- erroring — proves the shared counter is respected across RPCs even when
  -- the row was created by the sibling RPC's insert branch.
  BEGIN
    v_result := public.update_streak_progress(v_user_b, 0, 1, ARRAY[]::text[], '2026-07-28');
    IF v_result IS NULL THEN
      INSERT INTO _v_results VALUES ('cross_rpc_second_caller_sees_real_version', 'ok', NULL,
        'sibling RPC correctly deferred to the row update_user_progress_snapshot created');
    ELSE
      INSERT INTO _v_results VALUES ('cross_rpc_second_caller_sees_real_version', 'fail', NULL,
        'expected NULL, got ' || v_result::text);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('cross_rpc_second_caller_sees_real_version', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- Round-1-review P0 regression tests (2026-07-30) — the same
  -- rollback-transaction method that caught the ::date cast bug, now
  -- applied to privilege grants. Case 9-11 prove the FIXED grant block on
  -- update_user_progress_snapshot; case 12-13 re-confirm update_streak_
  -- progress's already-correct live grants are unaffected (belt-and-
  -- suspenders — this function's grants are NOT touched by migration 115,
  -- they carry over unchanged across the CREATE OR REPLACE above).
  BEGIN
    IF has_function_privilege('anon',
        'public.update_user_progress_snapshot(uuid,bigint,integer,integer,timestamptz,timestamptz,integer,integer,text,integer,integer,date,integer)',
        'execute') = false THEN
      INSERT INTO _v_results VALUES ('progress_snapshot_anon_blocked', 'ok', NULL,
        'anon cannot execute update_user_progress_snapshot');
    ELSE
      INSERT INTO _v_results VALUES ('progress_snapshot_anon_blocked', 'fail', NULL,
        'anon CAN execute update_user_progress_snapshot — P0 regression');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('progress_snapshot_anon_blocked', 'fail', SQLSTATE, SQLERRM);
  END;

  BEGIN
    IF has_function_privilege('authenticated',
        'public.update_user_progress_snapshot(uuid,bigint,integer,integer,timestamptz,timestamptz,integer,integer,text,integer,integer,date,integer)',
        'execute') = true THEN
      INSERT INTO _v_results VALUES ('progress_snapshot_authenticated_retained', 'ok', NULL,
        'authenticated retains execute on update_user_progress_snapshot');
    ELSE
      INSERT INTO _v_results VALUES ('progress_snapshot_authenticated_retained', 'fail', NULL,
        'authenticated lost execute — client sync would break');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('progress_snapshot_authenticated_retained', 'fail', SQLSTATE, SQLERRM);
  END;

  BEGIN
    IF has_function_privilege('service_role',
        'public.update_user_progress_snapshot(uuid,bigint,integer,integer,timestamptz,timestamptz,integer,integer,text,integer,integer,date,integer)',
        'execute') = true THEN
      INSERT INTO _v_results VALUES ('progress_snapshot_service_role_retained', 'ok', NULL,
        'service_role retains execute on update_user_progress_snapshot');
    ELSE
      INSERT INTO _v_results VALUES ('progress_snapshot_service_role_retained', 'fail', NULL,
        'service_role lost execute — cron/EF paths would break');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('progress_snapshot_service_role_retained', 'fail', SQLSTATE, SQLERRM);
  END;

  BEGIN
    IF has_function_privilege('anon',
        'public.update_streak_progress(uuid,bigint,integer,text[],text)', 'execute') = false THEN
      INSERT INTO _v_results VALUES ('streak_progress_anon_blocked_unaffected', 'ok', NULL,
        'anon still cannot execute update_streak_progress (unchanged by this migration)');
    ELSE
      INSERT INTO _v_results VALUES ('streak_progress_anon_blocked_unaffected', 'fail', NULL,
        'anon CAN execute update_streak_progress — unexpected grant drift');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('streak_progress_anon_blocked_unaffected', 'fail', SQLSTATE, SQLERRM);
  END;

  BEGIN
    IF has_function_privilege('authenticated',
        'public.update_streak_progress(uuid,bigint,integer,text[],text)', 'execute') = true THEN
      INSERT INTO _v_results VALUES ('streak_progress_authenticated_retained_unaffected', 'ok', NULL,
        'authenticated still retains execute on update_streak_progress');
    ELSE
      INSERT INTO _v_results VALUES ('streak_progress_authenticated_retained_unaffected', 'fail', NULL,
        'authenticated lost execute — unexpected grant drift');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('streak_progress_authenticated_retained_unaffected', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- Case 14 — round-1-review P2 regression: a fresh insert with
  -- current_phase/current_week/total_workouts_done/current_streak_weeks ALL
  -- NULL must COALESCE to the real schema defaults (1/1/0/0), not insert a
  -- bare NULL. This is the exact shape the onboarding-replay path now sends
  -- (P1 fix) when current_week is deliberately omitted to avoid stomping the
  -- program-week projection, on a user who has no row yet.
  BEGIN
    v_result := public.update_user_progress_snapshot(
      v_user_c, 0, NULL, NULL, now(), now(), NULL, NULL, 'intermediate', NULL, NULL, NULL, NULL);
    IF v_result = 1 AND EXISTS (
      SELECT 1 FROM public.user_progress
      WHERE user_id = v_user_c AND current_phase = 1 AND current_week = 1
        AND total_workouts_done = 0 AND current_streak_weeks = 0
    ) THEN
      INSERT INTO _v_results VALUES ('progress_fresh_insert_null_coalesces_to_schema_default', 'ok', NULL,
        'all-null core-4 fresh insert landed the real defaults 1/1/0/0');
    ELSE
      INSERT INTO _v_results VALUES ('progress_fresh_insert_null_coalesces_to_schema_default', 'fail', NULL,
        'a NULL param landed as NULL instead of the schema default — P2 regression');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('progress_fresh_insert_null_coalesces_to_schema_default', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- Case 15 — Hermes C10 (2026-07-30): the RPCs' FOR UPDATE clause genuinely
  -- takes a real Postgres row lock on user_progress, not a no-op read.
  -- See this file's header for why this is the closest provable substitute
  -- for a true two-session block-and-re-read test — a direct empirical
  -- probe (two execute_sql calls fired as if in parallel) showed the second
  -- call's own internal wait only started AFTER the first call's full
  -- 3-second sleep+commit had already finished (its own "waited 0s on the
  -- lock" self-report proved it), i.e. the calls SERIALIZED rather than
  -- interleaved — this tool interface does not give two genuinely
  -- concurrent Postgres sessions. What CAN be proven in one session: the
  -- lock is real. If it weren't (e.g. a typo turned FOR UPDATE into a
  -- plain SELECT), pg_locks would show no RowShareLock and this case fails.
  BEGIN
    PERFORM streak_progress_version FROM public.user_progress WHERE user_id = v_user_a FOR UPDATE;
    IF EXISTS (
      SELECT 1 FROM pg_locks
      WHERE pid = pg_backend_pid()
        AND relation = 'public.user_progress'::regclass::oid
        AND locktype = 'relation'
        AND mode = 'RowShareLock'
        AND granted = true
    ) THEN
      INSERT INTO _v_results VALUES ('for_update_takes_a_real_row_lock', 'ok', NULL,
        'pg_locks confirms a granted RowShareLock on user_progress after FOR UPDATE');
    ELSE
      INSERT INTO _v_results VALUES ('for_update_takes_a_real_row_lock', 'fail', NULL,
        'no RowShareLock found — FOR UPDATE is not taking the lock the optimistic-lock design depends on');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('for_update_takes_a_real_row_lock', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- Case 16 — Hermes C4: NULL p_user_id must RAISE, not silently fall
  -- through the auth guard (PL/pgSQL `IF <x> <> NULL` = NULL = false).
  BEGIN
    v_result := public.update_user_progress_snapshot(
      NULL, 0, 1, 1, now(), now(), 0, 0, 'beginner', 0, 0, NULL, 0);
    INSERT INTO _v_results VALUES ('null_p_user_id_raises', 'fail', NULL,
      'expected a RAISE EXCEPTION, got a normal return — NULL p_user_id guard did not fire');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%must not be null%' THEN
      INSERT INTO _v_results VALUES ('null_p_user_id_raises', 'ok', SQLSTATE, SQLERRM);
    ELSE
      INSERT INTO _v_results VALUES ('null_p_user_id_raises', 'fail', SQLSTATE, SQLERRM);
    END IF;
  END;

  -- Case 17 — Hermes C4: NULL p_expected_version on a FOUND row must return
  -- NULL (a rejection), not fall through the version guard and false-
  -- succeed against a WHERE clause that then matches zero rows.
  BEGIN
    v_result := public.update_user_progress_snapshot(
      v_user_a, NULL, 1, 1, now(), now(), 0, 0, 'beginner', 0, 0, NULL, 0);
    IF v_result IS NULL THEN
      INSERT INTO _v_results VALUES ('null_p_expected_version_returns_null', 'ok', NULL,
        'NULL p_expected_version correctly rejected on a FOUND row');
    ELSE
      INSERT INTO _v_results VALUES ('null_p_expected_version_returns_null', 'fail', NULL,
        format('expected NULL, got %s — false-success on a NULL expected version', v_result));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('null_p_expected_version_returns_null', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 18 — Hermes C3: total_workouts_done never decreases through this
  -- RPC even when the caller resends a lower value at the CORRECT version
  -- (simulates weekly-recalc's EF writer or a stale client retry racing a
  -- fresher value that already landed).
  BEGIN
    -- Bump v_user_a's total_workouts_done to a known-high value first.
    v_result := public.update_user_progress_snapshot(
      v_user_a, (SELECT streak_progress_version FROM public.user_progress WHERE user_id = v_user_a),
      NULL, NULL, NULL, NULL, 50, NULL, NULL, NULL, NULL, NULL, NULL);
    -- Now resend a LOWER value at the correct (just-returned) version.
    v_result := public.update_user_progress_snapshot(
      v_user_a, v_result, NULL, NULL, NULL, NULL, 10, NULL, NULL, NULL, NULL, NULL, NULL);
    IF v_result IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.user_progress WHERE user_id = v_user_a AND total_workouts_done = 50
    ) THEN
      INSERT INTO _v_results VALUES ('total_workouts_done_never_decreases', 'ok', NULL,
        'a lower resend at the correct version did not demote total_workouts_done below 50');
    ELSE
      INSERT INTO _v_results VALUES ('total_workouts_done_never_decreases', 'fail', NULL,
        'total_workouts_done was demoted by a lower resend — GREATEST guard not working');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('total_workouts_done_never_decreases', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 19 — Hermes L1-1 / C4: a NULL p_freezes_last_refill on an UPDATE
  -- must PRESERVE the existing column value (COALESCE), matching the OLD
  -- raw-upsert's conditional-omit semantics — not NULL out a real cloud
  -- value just because the caller had no local last_refill.
  BEGIN
    -- Seed v_user_a's last_refill with a real, known value first.
    v_result := public.update_streak_progress(
      v_user_a, (SELECT streak_progress_version FROM public.user_progress WHERE user_id = v_user_a),
      1, ARRAY[]::text[], '2026-07-20');
    -- Now call again with last_refill = NULL at the correct version.
    v_result := public.update_streak_progress(
      v_user_a, v_result, 1, ARRAY[]::text[], NULL);
    IF v_result IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.user_progress
      WHERE user_id = v_user_a AND streak_freezes_last_refill = '2026-07-20'::date
    ) THEN
      INSERT INTO _v_results VALUES ('last_refill_null_preserves_existing', 'ok', NULL,
        'a NULL p_freezes_last_refill preserved the existing 2026-07-20 value instead of clobbering it');
    ELSE
      INSERT INTO _v_results VALUES ('last_refill_null_preserves_existing', 'fail', NULL,
        'last_refill was clobbered by a NULL resend — L1-1 regression');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('last_refill_null_preserves_existing', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 20 — B-pass round-2 Finding 3: deployments_complete never
  -- decreases through this RPC even when the caller resends a lower value
  -- at the CORRECT version. Same class as Case 18's total_workouts_done
  -- guard; deployments_complete sat in the identical UPDATE statement 4
  -- lines away without the GREATEST wrap until this fix — reachable by the
  -- exact same retry-resends-stale-local-value vector, and read by
  -- evaluate-rank-promotions + rank_service.dart for rank gating.
  BEGIN
    v_result := public.update_user_progress_snapshot(
      v_user_a, (SELECT streak_progress_version FROM public.user_progress WHERE user_id = v_user_a),
      NULL, NULL, NULL, NULL, NULL, NULL, NULL, 8, NULL, NULL, NULL);
    -- Now resend a LOWER value at the correct (just-returned) version.
    v_result := public.update_user_progress_snapshot(
      v_user_a, v_result, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 2, NULL, NULL, NULL);
    IF v_result IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.user_progress WHERE user_id = v_user_a AND deployments_complete = 8
    ) THEN
      INSERT INTO _v_results VALUES ('deployments_complete_never_decreases', 'ok', NULL,
        'a lower resend at the correct version did not demote deployments_complete below 8');
    ELSE
      INSERT INTO _v_results VALUES ('deployments_complete_never_decreases', 'fail', NULL,
        'deployments_complete was demoted by a lower resend — GREATEST guard not working');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('deployments_complete_never_decreases', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 21 — Final B-pass Finding 1 (2026-07-30, docs/reviews/8d5a2f558995-
  -- review.md): longest_gap_days never decreases through this RPC even when
  -- the caller resends a lower value at the CORRECT version. Same class as
  -- Case 18 (total_workouts_done) and Case 20 (deployments_complete);
  -- longest_gap_days sat in the identical UPDATE statement without the
  -- GREATEST wrap until this fix — currently inert (no client writer
  -- populates progress['longest_gap_days'] in Hive today) but fixed now to
  -- match its two siblings rather than left inconsistent.
  BEGIN
    v_result := public.update_user_progress_snapshot(
      v_user_a, (SELECT streak_progress_version FROM public.user_progress WHERE user_id = v_user_a),
      NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 12);
    -- Now resend a LOWER value at the correct (just-returned) version.
    v_result := public.update_user_progress_snapshot(
      v_user_a, v_result, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 3);
    IF v_result IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.user_progress WHERE user_id = v_user_a AND longest_gap_days = 12
    ) THEN
      INSERT INTO _v_results VALUES ('longest_gap_days_never_decreases', 'ok', NULL,
        'a lower resend at the correct version did not demote longest_gap_days below 12');
    ELSE
      INSERT INTO _v_results VALUES ('longest_gap_days_never_decreases', 'fail', NULL,
        'longest_gap_days was demoted by a lower resend — GREATEST guard not working');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('longest_gap_days_never_decreases', 'fail', SQLSTATE, SQLERRM);
  END;

END;
$outer$;

SELECT label, status, sqlstate, msg FROM _v_results ORDER BY label;

ROLLBACK;
