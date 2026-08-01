-- test/sql/reengagement_silent_candidates_verify.sql
--
-- 2026-07-31 — Live-Postgres verification of migration 117's new RPC
-- (Unit 5, OI-48, diagnose a4e1c9): find_reengagement_silent_candidates,
-- plus the sibling privilege-hardening fix on find_orphan_chat_media.
--
-- Why this file exists
-- --------------------
-- A source-grep contract test can prove re-engagement/index.ts calls
-- .rpc('find_reengagement_silent_candidates', ...) instead of a per-user
-- query loop, but CANNOT prove the anti-join semantics actually pick the
-- right candidate set on live Postgres, that an empty exclude array doesn't
-- accidentally exclude everyone, or that the EXECUTE grants land where
-- intended. Same pattern as test/sql/cross_device_progress_optimistic_lock
-- _verify.sql / oi46_daily_cap_triggers_live_verify.sql — a transaction that
-- ROLLBACKs at the end, run via the generic runner:
--
--   dart run scripts/check_onconflict_live_arbiter.dart \
--       --sql test/sql/reengagement_silent_candidates_verify.sql
--
-- Status: RUN LIVE 2026-07-31 (via direct execute_sql, pre-migration-apply —
-- this file's CREATE OR REPLACE + REVOKE/GRANT statements apply migration
-- 117's actual SQL WITHIN the same rolled-back transaction, so it verifies
-- the migration's real DDL before that DDL is ever applied for real).
--
-- First run found a genuine bug — but in the TEST, not the RPC: an initial
-- draft asserted an empty p_exclude_user_ids array should return ONLY the
-- fully-silent seeded user, and failed with an extra row ("Excluded User")
-- in the result. That's correct RPC behavior, not a bug — with nothing
-- excluded, the seeded "Excluded User" fixture (silent, but only used to
-- exercise the exclude-array mechanism) is legitimately ALSO a candidate.
-- Case 2 below asserts the corrected expectation.
--
-- Round-1 review (Unit 5) extended the first 9 cases: a last_active_at IS
-- NULL fixture (the single most drift-prone clause — the old JS
-- `if (lastActiveRaw)` control flow made "NULL counts as silent"
-- non-obvious, and no fixture pinned it) folded into the existing Case 1,
-- 2, and 3 assertions, plus one genuinely new Case 3b for a NULL (not
-- merely empty) p_exclude_user_ids, which is what the migration's
-- COALESCE(p_exclude_user_ids, ARRAY[]::uuid[]) guard exists to make safe
-- — `NOT (id = ANY(NULL::uuid[]))` is NULL, not false, so without the
-- guard this case would silently return zero candidates instead of the
-- full set. All 11 cases pass as written here (re-run live 2026-08-01 after the
-- search_path + saturation-detection changes).
--
-- closes-diagnose: a4e1c9

BEGIN;

CREATE TEMP TABLE _v_results (
  label  text PRIMARY KEY,
  status text NOT NULL,        -- 'ok' | 'fail'
  detail text
) ON COMMIT DROP;

-- Apply migration 117's actual DDL for THIS transaction only (rolled back
-- at the end). Kept verbatim in sync with the migration file itself.
CREATE OR REPLACE FUNCTION public.find_reengagement_silent_candidates(
  p_cutoff_date date,
  p_cutoff_ts timestamptz,
  p_exclude_user_ids uuid[]
)
RETURNS TABLE (user_id uuid, full_name text)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  -- COALESCE guards against p_exclude_user_ids arriving NULL (not merely
  -- empty): `NOT (id = ANY(NULL::uuid[]))` evaluates to NULL, not false,
  -- which would silently zero the WHERE clause for every row -- a candidate
  -- set of zero, 200 OK, no error. The one real caller always passes
  -- Array.from(aSet) (never null), so this isn't reachable today, but it's
  -- a one-line guard against a silent-wrong failure mode with zero cost.
  -- (The migration file additionally documents why p_cutoff_date/_ts are
  -- deliberately NOT guarded — their degenerate paths fail loud. Comment
  -- text may differ between the two files; the executable SQL must not.)
  SELECT u.id, u.full_name
  FROM public.users u
  WHERE (u.is_deleted IS NULL OR u.is_deleted = false)
    AND NOT (u.id = ANY(COALESCE(p_exclude_user_ids, ARRAY[]::uuid[])))
    AND (u.last_active_at IS NULL OR u.last_active_at < p_cutoff_ts)
    AND NOT EXISTS (
      SELECT 1 FROM public.workout_logs w
      WHERE w.user_id = u.id AND w.date >= p_cutoff_date
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.nutrition_logs n
      WHERE n.user_id = u.id AND n.date >= p_cutoff_date
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.weight_logs wt
      WHERE wt.user_id = u.id AND wt.date >= p_cutoff_date
    );
$$;

REVOKE EXECUTE ON FUNCTION public.find_reengagement_silent_candidates(date, timestamptz, uuid[])
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.find_reengagement_silent_candidates(date, timestamptz, uuid[])
  TO service_role;

-- Migration 117 Part 2 — the sibling grant fix on find_orphan_chat_media,
-- applied here too so cases 7-9 prove it BEFORE the migration is ever
-- applied for real (same method as cross_device_progress_optimistic_lock
-- _verify.sql's cases 9-13 for update_user_progress_snapshot).
REVOKE EXECUTE ON FUNCTION public.find_orphan_chat_media(timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.find_orphan_chat_media(timestamptz)
  TO service_role;

DO $outer$
DECLARE
  v_silent    uuid := '00000000-0000-0000-0000-000000050001'::uuid;
  v_workout   uuid := '00000000-0000-0000-0000-000000050002'::uuid;
  v_nutrition uuid := '00000000-0000-0000-0000-000000050003'::uuid;
  v_weight    uuid := '00000000-0000-0000-0000-000000050004'::uuid;
  v_recent    uuid := '00000000-0000-0000-0000-000000050005'::uuid;
  v_deleted   uuid := '00000000-0000-0000-0000-000000050006'::uuid;
  v_excluded  uuid := '00000000-0000-0000-0000-000000050007'::uuid;
  v_nullactive uuid := '00000000-0000-0000-0000-000000050008'::uuid;
  v_now       timestamptz := now();
  v_old       timestamptz := now() - interval '10 days';
  v_names     text;
BEGIN
  -- Best-effort synthetic user seeding — mirrors oi46_daily_cap_triggers
  -- _live_verify.sql / cross_device_progress_optimistic_lock_verify.sql.
  INSERT INTO auth.users (id, email, created_at) VALUES
    (v_silent, 'test+u5-silent@avya.local', v_now),
    (v_workout, 'test+u5-workout@avya.local', v_now),
    (v_nutrition, 'test+u5-nutrition@avya.local', v_now),
    (v_weight, 'test+u5-weight@avya.local', v_now),
    (v_recent, 'test+u5-recent@avya.local', v_now),
    (v_deleted, 'test+u5-deleted@avya.local', v_now),
    (v_excluded, 'test+u5-excluded@avya.local', v_now),
    (v_nullactive, 'test+u5-nullactive@avya.local', v_now)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.users (id, email, full_name, last_active_at, is_deleted) VALUES
    (v_silent, 'test+u5-silent@avya.local', 'Silent User', v_old, false),
    (v_workout, 'test+u5-workout@avya.local', 'Workout User', v_old, false),
    (v_nutrition, 'test+u5-nutrition@avya.local', 'Nutrition User', v_old, false),
    (v_weight, 'test+u5-weight@avya.local', 'Weight User', v_old, false),
    (v_recent, 'test+u5-recent@avya.local', 'Recent User', v_now, false),
    (v_deleted, 'test+u5-deleted@avya.local', 'Deleted User', v_old, true),
    (v_excluded, 'test+u5-excluded@avya.local', 'Excluded User', v_old, false),
    (v_nullactive, 'test+u5-nullactive@avya.local', 'Null Active User', NULL, false)
  ON CONFLICT (id) DO UPDATE SET
    last_active_at = EXCLUDED.last_active_at,
    is_deleted = EXCLUDED.is_deleted,
    full_name = EXCLUDED.full_name;

  INSERT INTO public.workout_logs (user_id, date, workout_name)
    VALUES (v_workout, CURRENT_DATE, 'Test Day');
  INSERT INTO public.nutrition_logs (user_id, date, meal_type)
    VALUES (v_nutrition, CURRENT_DATE, 'lunch');
  INSERT INTO public.weight_logs (user_id, date, weight_kg)
    VALUES (v_weight, CURRENT_DATE, 75.0);

  -- =====================================================================
  -- Case 1 — full candidate-set correctness. Silent User and Null Active
  -- User are the only candidates: Workout/Nutrition/Weight User each have
  -- one row inside the cutoff window in their respective table; Recent
  -- User's last_active_at is fresh; Deleted User is soft-deleted; Excluded
  -- User is in the exclude array (simulating Path A already covering
  -- them); Null Active User has last_active_at = NULL and zero activity
  -- rows — pins the single most drift-prone clause (the OLD JS code's
  -- `if (lastActiveRaw)` guard let NULL fall through to the per-table
  -- checks too, so NULL must count as "potentially silent", not "recently
  -- active" or excluded outright).
  BEGIN
    SELECT string_agg(full_name, ', ' ORDER BY full_name) INTO v_names
    FROM public.find_reengagement_silent_candidates(
      (v_now - interval '3 days')::date, v_now - interval '3 days', ARRAY[v_excluded]
    ) WHERE full_name LIKE '%User';
    IF v_names = 'Null Active User, Silent User' THEN
      INSERT INTO _v_results VALUES ('candidate_set_correct', 'ok', v_names);
    ELSE
      INSERT INTO _v_results VALUES ('candidate_set_correct', 'fail',
        'expected Null Active User, Silent User, got: ' || COALESCE(v_names, '<empty>'));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('candidate_set_correct', 'fail', SQLSTATE || ': ' || SQLERRM);
  END;

  -- Case 2 — an EMPTY exclude array (Path A found zero candidates that run)
  -- must not exclude everyone via a NOT (id = ANY('{}')) miscomputation.
  -- Correct result here is Excluded User, Null Active User, and Silent
  -- User (Excluded User has zero real activity of its own — it is only
  -- "excluded" via the array mechanism Case 1 exercises, not via any
  -- activity signal).
  BEGIN
    SELECT string_agg(full_name, ', ' ORDER BY full_name) INTO v_names
    FROM public.find_reengagement_silent_candidates(
      (v_now - interval '3 days')::date, v_now - interval '3 days', ARRAY[]::uuid[]
    ) WHERE full_name LIKE '%User';
    IF v_names = 'Excluded User, Null Active User, Silent User' THEN
      INSERT INTO _v_results VALUES ('empty_exclude_array_ok', 'ok', v_names);
    ELSE
      INSERT INTO _v_results VALUES ('empty_exclude_array_ok', 'fail',
        'expected Excluded User, Null Active User, Silent User, got: ' || COALESCE(v_names, '<empty>'));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('empty_exclude_array_ok', 'fail', SQLSTATE || ': ' || SQLERRM);
  END;

  -- Case 3 — excluding every genuinely-silent fixture (Silent, Excluded,
  -- Null Active) empties the set entirely.
  BEGIN
    SELECT string_agg(full_name, ', ' ORDER BY full_name) INTO v_names
    FROM public.find_reengagement_silent_candidates(
      (v_now - interval '3 days')::date, v_now - interval '3 days',
      ARRAY[v_silent, v_excluded, v_nullactive]
    ) WHERE full_name LIKE '%User';
    IF v_names IS NULL THEN
      INSERT INTO _v_results VALUES ('exclude_silent_user_empties_set', 'ok', 'correctly empty');
    ELSE
      INSERT INTO _v_results VALUES ('exclude_silent_user_empties_set', 'fail',
        'expected empty, got: ' || v_names);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('exclude_silent_user_empties_set', 'fail', SQLSTATE || ': ' || SQLERRM);
  END;

  -- Case 3b — a NULL (not merely empty) p_exclude_user_ids must not zero
  -- the candidate set. Without the migration's COALESCE(p_exclude_user_ids,
  -- ARRAY[]::uuid[]) guard, `NOT (id = ANY(NULL::uuid[]))` evaluates to
  -- NULL (not false/true) for every row, so the WHERE clause is NULL
  -- everywhere and the RPC would silently return zero rows, 200 OK, no
  -- error — exactly the silent-wrong failure mode this codebase treats as
  -- worse than a loud one. Not reachable via the one real caller today
  -- (it always passes Array.from(aSet)), but cheap to guard and pin.
  BEGIN
    SELECT string_agg(full_name, ', ' ORDER BY full_name) INTO v_names
    FROM public.find_reengagement_silent_candidates(
      (v_now - interval '3 days')::date, v_now - interval '3 days', NULL::uuid[]
    ) WHERE full_name LIKE '%User';
    IF v_names = 'Excluded User, Null Active User, Silent User' THEN
      INSERT INTO _v_results VALUES ('null_exclude_array_ok', 'ok', v_names);
    ELSE
      INSERT INTO _v_results VALUES ('null_exclude_array_ok', 'fail',
        'expected Excluded User, Null Active User, Silent User, got: ' || COALESCE(v_names, '<empty>'));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('null_exclude_array_ok', 'fail', SQLSTATE || ': ' || SQLERRM);
  END;

  -- =====================================================================
  -- Cases 4-6 — the new RPC's own privilege grants.
  BEGIN
    IF has_function_privilege('anon',
        'public.find_reengagement_silent_candidates(date,timestamptz,uuid[])', 'execute') = false THEN
      INSERT INTO _v_results VALUES ('new_rpc_anon_blocked', 'ok', 'anon cannot execute');
    ELSE
      INSERT INTO _v_results VALUES ('new_rpc_anon_blocked', 'fail', 'anon CAN execute — privilege gap');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('new_rpc_anon_blocked', 'fail', SQLSTATE || ': ' || SQLERRM);
  END;

  BEGIN
    IF has_function_privilege('authenticated',
        'public.find_reengagement_silent_candidates(date,timestamptz,uuid[])', 'execute') = false THEN
      INSERT INTO _v_results VALUES ('new_rpc_authenticated_blocked', 'ok', 'authenticated cannot execute');
    ELSE
      INSERT INTO _v_results VALUES ('new_rpc_authenticated_blocked', 'fail',
        'authenticated CAN execute — privilege gap');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('new_rpc_authenticated_blocked', 'fail', SQLSTATE || ': ' || SQLERRM);
  END;

  BEGIN
    IF has_function_privilege('service_role',
        'public.find_reengagement_silent_candidates(date,timestamptz,uuid[])', 'execute') = true THEN
      INSERT INTO _v_results VALUES ('new_rpc_service_role_retained', 'ok', 'service_role can execute');
    ELSE
      INSERT INTO _v_results VALUES ('new_rpc_service_role_retained', 'fail',
        'service_role CANNOT execute — cron path would break');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('new_rpc_service_role_retained', 'fail', SQLSTATE || ': ' || SQLERRM);
  END;

  -- Case 6b — search_path must be set (Hermes round-2 N2). Every other
  -- directly-callable public RPC on this project sets it, including the
  -- sibling this migration mirrors; omitting it would have made this the
  -- first to regress the function_search_path_mutable lint category the
  -- 2026-06-11 audit closed 9/9.
  BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='find_reengagement_silent_candidates'
                 AND p.proconfig IS NOT NULL
                 AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%')) THEN
      INSERT INTO _v_results VALUES ('new_rpc_search_path_set', 'ok', 'search_path is set');
    ELSE
      INSERT INTO _v_results VALUES ('new_rpc_search_path_set', 'fail', 'search_path NOT set — lint regression');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('new_rpc_search_path_set', 'fail', SQLSTATE || ': ' || SQLERRM);
  END;

  -- =====================================================================
  -- Cases 7-9 — find_orphan_chat_media's narrowed grants (migration 117
  -- Part 2). Pre-fix, live-verified 2026-07-31: anon=true, authenticated=
  -- true, service_role=true (migration 071 only ever GRANTed to
  -- service_role, never revoked the PUBLIC-default grant).
  BEGIN
    IF has_function_privilege('anon', 'public.find_orphan_chat_media(timestamptz)', 'execute') = false THEN
      INSERT INTO _v_results VALUES ('orphan_media_anon_now_blocked', 'ok',
        'anon no longer executes (was true pre-fix)');
    ELSE
      INSERT INTO _v_results VALUES ('orphan_media_anon_now_blocked', 'fail',
        'anon still CAN execute — fix did not apply');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('orphan_media_anon_now_blocked', 'fail', SQLSTATE || ': ' || SQLERRM);
  END;

  BEGIN
    IF has_function_privilege('authenticated', 'public.find_orphan_chat_media(timestamptz)', 'execute') = false THEN
      INSERT INTO _v_results VALUES ('orphan_media_authenticated_now_blocked', 'ok',
        'authenticated no longer executes (was true pre-fix)');
    ELSE
      INSERT INTO _v_results VALUES ('orphan_media_authenticated_now_blocked', 'fail',
        'authenticated still CAN execute — fix did not apply');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('orphan_media_authenticated_now_blocked', 'fail', SQLSTATE || ': ' || SQLERRM);
  END;

  BEGIN
    IF has_function_privilege('service_role', 'public.find_orphan_chat_media(timestamptz)', 'execute') = true THEN
      INSERT INTO _v_results VALUES ('orphan_media_service_role_retained', 'ok',
        'service_role still executes — clean-orphan-media cron unaffected');
    ELSE
      INSERT INTO _v_results VALUES ('orphan_media_service_role_retained', 'fail',
        'service_role lost execute — clean-orphan-media cron would break');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('orphan_media_service_role_retained', 'fail', SQLSTATE || ': ' || SQLERRM);
  END;
END;
$outer$;

SELECT label, status, detail FROM _v_results ORDER BY label;

ROLLBACK;
