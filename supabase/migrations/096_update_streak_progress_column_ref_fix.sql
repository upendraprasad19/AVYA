-- Intent: Fix update_streak_progress RPC column-ref streak_freeze_used_dates (singular, nonexistent) -> streak_freezes_used_dates (plural, the real user_progress column from migration 048) so the optimistic-lock cross-device streak write path is correct if/when invoked (currently dormant — never called by literal RPC name per mig 090). CREATE OR REPLACE keeps the identical signature, so mig 090's auth.uid() cross-account guard and mig 091's REVOKE-from-PUBLIC + GRANT-to-authenticated/service_role ACLs are preserved.
-- Destructive?: no   -- function body only; column-ref correction, no data change
-- Rollback strategy: inline   -- reverse = re-apply migration 090's body (singular column-ref); block at end of file
-- Linked diagnose-doc: f9d2e7
-- ============================================================
-- Phase 2 Unit D1 — permanent freeze ledger; RPC column-ref repair
-- (branch: discipline-overhaul, 2026-06-18)
-- ============================================================

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
  -- Security (audit 2026-06-11 / c9b3e2): an authenticated caller may only write
  -- its OWN streak. service_role / cron (auth.uid() IS NULL) pass through.
  IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'cross-account streak write blocked (caller % != target %)',
      auth.uid(), p_user_id;
  END IF;

  SELECT streak_progress_version INTO v_current_version
    FROM public.user_progress
    WHERE user_id = p_user_id
    FOR UPDATE;

  IF NOT FOUND THEN
    IF p_expected_version <> 0 THEN
      RETURN NULL;
    END IF;
    INSERT INTO public.user_progress (
      user_id,
      streak_freezes_available,
      streak_freezes_used_dates,        -- D1 fix (f9d2e7): was streak_freeze_used_dates (singular, nonexistent)
      streak_freezes_last_refill,
      streak_progress_version
    ) VALUES (
      p_user_id,
      p_freezes_available,
      p_freeze_used_dates,
      p_freezes_last_refill,
      1
    );
    RETURN 1;
  END IF;

  IF v_current_version <> p_expected_version THEN
    RETURN NULL;
  END IF;

  v_new_version := v_current_version + 1;
  UPDATE public.user_progress
    SET streak_freezes_available = p_freezes_available,
        streak_freezes_used_dates = p_freeze_used_dates,   -- D1 fix (f9d2e7): was streak_freeze_used_dates (singular)
        streak_freezes_last_refill = p_freezes_last_refill,
        streak_progress_version = v_new_version
    WHERE user_id = p_user_id
      AND streak_progress_version = p_expected_version;
  RETURN v_new_version;
END;
$function$;

-- ── Rollback (inline) ──────────────────────────────────────
-- Re-apply migration 090's function body verbatim (restores the singular,
-- broken streak_freeze_used_dates column-ref). The signature is unchanged so
-- the auth.uid() guard + mig 091 ACLs survive either way.
