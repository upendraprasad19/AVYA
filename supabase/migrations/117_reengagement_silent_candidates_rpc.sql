-- Intent: Add find_reengagement_silent_candidates RPC (anti-join across workout_logs/
--   nutrition_logs/weight_logs) so re-engagement's Path B computes its silent-user
--   candidate set in one Postgres round-trip instead of a per-user 3-query loop; also
--   close a live over-broad EXECUTE grant on the sibling find_orphan_chat_media RPC,
--   found while designing this migration against that RPC as the pattern to mirror.
-- Destructive?: no -- adds a new function; the find_orphan_chat_media grant change only
--   NARROWS existing over-broad access (anon/authenticated/service_role -> service_role
--   only), matching its always-documented service-role-only intent. Does not touch any
--   table, row, or the function's own body/behavior for its one real (service_role)
--   caller (clean-orphan-media/index.ts -- confirmed the ONLY caller repo-wide by grep).
-- Rollback strategy: inline -- see commented block at end of file
-- Linked diagnose-doc: docs/diagnoses/2026-07-31-reengagement-prefilter-a4e1c9.md

-- ============================================================================
-- Part 1 -- new RPC. Mirrors find_orphan_chat_media's shape (migration 071:
-- one SQL-language STABLE function expressing the filter as NOT EXISTS
-- anti-joins) adapted for re-engagement's 3-table absence check instead of
-- 071's single-table + 2-table-exists check.
-- ============================================================================

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
  --
  -- p_cutoff_date / p_cutoff_ts are deliberately NOT COALESCE-guarded, and
  -- the asymmetry is intentional (Hermes L37): their degenerate paths fail
  -- LOUD, the exclude array's fails SILENT. A NULL/NaN cutoff cannot reach
  -- this function -- `new Date(NaN).toISOString()` throws RangeError at the
  -- call site before the RPC is invoked, and an omitted key makes PostgREST
  -- find no matching signature (-> a tagged path_b error). A silent-wrong
  -- guard is only worth adding where the failure would otherwise be silent.
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

-- Explicit REVOKE FROM PUBLIC, anon, authenticated + narrow GRANT -- the
-- actually-effective pattern (migrations 090/091's finding: Supabase grants
-- EXECUTE to anon/authenticated DIRECTLY via pg_default_acl on every new
-- public-schema function, bypassing PUBLIC entirely, so a PUBLIC-only revoke
-- -- or the bare `GRANT ... TO service_role` migration 071 used for the
-- sibling find_orphan_chat_media below -- is NOT sufficient on its own).
REVOKE EXECUTE ON FUNCTION public.find_reengagement_silent_candidates(date, timestamptz, uuid[])
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.find_reengagement_silent_candidates(date, timestamptz, uuid[])
  TO service_role;

-- ============================================================================
-- Part 2 -- close the SAME gap on the sibling find_orphan_chat_media RPC,
-- found live while designing Part 1 above against it as the reference
-- pattern. Live-verified 2026-07-31 (has_function_privilege against
-- dedsavbjuwgarrhphgnl): anon=true, authenticated=true, service_role=true --
-- migration 071 only ever `GRANT`ed to service_role, never revoked the
-- PUBLIC-default grant, so anon/authenticated inherited it exactly like
-- migration 090's original 9 findings did (090/091 fixed 9 SECURITY
-- DEFINER functions on 2026-06-11, live-verified prosecdef=true;
-- find_orphan_chat_media is plain SQL/STABLE, not SECURITY DEFINER, and
-- its creating migration 071 predates 090/091 by ~25 days -- the gap is
-- SCOPE, not timing: 090/091's REVOKE pass targeted SECURITY DEFINER
-- functions specifically, so find_orphan_chat_media was categorically
-- outside it regardless of creation order).
--
-- Not a live data leak: RLS is enabled (relrowsecurity=true, live-verified)
-- on all three tables this function reads (storage.objects, public.users,
-- public.subscriptions). Some policies there ARE roles={public} (which
-- includes anon), but none expose rows to an anon caller through THIS
-- function: users_select_own/subscriptions_select_own qualify on
-- auth.uid()=id|user_id (NULL for an anon caller, no session -> no match),
-- and storage.objects' two {public} policies are bucket-scoped to
-- avatars/banners, disjoint from the chat-media bucket this function
-- actually queries (all live-verified via pg_policies) -- an anon RPC call
-- would return zero rows, not real data. But it is unwanted attack surface
-- inconsistent with the function's always-documented service-role-only
-- intent, and the exact gap Part 1 above is designed not to replicate.
-- Confirmed by repo-wide grep: clean-orphan-media/index.ts (service_role)
-- is the function's ONLY caller.
REVOKE EXECUTE ON FUNCTION public.find_orphan_chat_media(timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.find_orphan_chat_media(timestamptz)
  TO service_role;

-- Rollback (inline, commented):
-- DROP FUNCTION IF EXISTS public.find_reengagement_silent_candidates(date, timestamptz, uuid[]);
-- -- Re-opening find_orphan_chat_media to anon/authenticated is never a valid
-- -- rollback target (that is the bug this migration closes). If a genuine
-- -- future caller needs it, GRANT EXECUTE ... TO authenticated explicitly --
-- -- never re-add anon.
-- --
-- -- COUPLING WARNING (B-pass finding, round-2): re-engagement/index.ts's
-- -- Path B has an UNCONDITIONAL runtime dependency on
-- -- find_reengagement_silent_candidates -- the old per-user-loop fallback
-- -- was deleted, not preserved behind a flag. Rolling back ONLY this
-- -- migration (DROP FUNCTION above) while the deployed Edge Function still
-- -- calls .rpc('find_reengagement_silent_candidates', ...) will 500 every
-- -- re-engagement cron tick from that point forward. A real rollback of
-- -- this migration MUST happen together with reverting the Edge Function
-- -- deploy to the pre-Unit-5 index.ts in the SAME operation, not as two
-- -- independently-timed steps.
