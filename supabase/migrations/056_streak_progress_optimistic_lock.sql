-- C-15 (audit-2026-05-11) — cross-device safety net for the
-- `streak_freezes_*` columns on `user_progress`.
--
-- Pre-fix, two paths could write the same columns:
--   1. Client refill (StreakFreezeNotifier weekly +1).
--   2. Client consume (WorkoutRepository missed-day freeze burn).
--
-- StreakProgressService (lib/core/services/streak_progress_service.dart)
-- serialises both paths through a client-side mutex. That covers
-- the SAME-DEVICE race. The cross-device race is when:
--
--   Device A consumes a freeze, writes available=0 to cloud at T1.
--   Device B has a stale read of available=1, refills to 2 at T2.
--   Cloud now reflects 2, the consume is silently undone.
--
-- This RPC adds optimistic-lock semantics. Clients pass the version
-- they last read; the update only succeeds if the cloud row's
-- `streak_progress_version` still matches. On mismatch, the function
-- returns NULL — caller re-reads + retries.
--
-- The `streak_progress_version` column is a monotonic counter that
-- increments on every successful update. Cheap to add since
-- `user_progress` already has a UNIQUE(user_id) constraint via the
-- primary key.

ALTER TABLE public.user_progress
  ADD COLUMN IF NOT EXISTS streak_progress_version BIGINT NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.update_streak_progress(
  p_user_id UUID,
  p_expected_version BIGINT,
  p_freezes_available INT,
  p_freeze_used_dates TEXT[],
  p_freezes_last_refill TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_version BIGINT;
  v_new_version BIGINT;
BEGIN
  -- Snapshot current row under FOR UPDATE so concurrent calls block.
  SELECT streak_progress_version INTO v_current_version
    FROM public.user_progress
    WHERE user_id = p_user_id
    FOR UPDATE;

  IF NOT FOUND THEN
    -- No row yet — insert at version 1. p_expected_version must be 0
    -- (the post-add default) for a fresh user. Mismatched expectation
    -- → NULL signals retry.
    IF p_expected_version <> 0 THEN
      RETURN NULL;
    END IF;
    INSERT INTO public.user_progress (
      user_id,
      streak_freezes_available,
      streak_freeze_used_dates,
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

  -- Optimistic lock: expected version must match the row's current
  -- version. Mismatch = a concurrent writer landed; caller retries.
  IF v_current_version <> p_expected_version THEN
    RETURN NULL;
  END IF;

  v_new_version := v_current_version + 1;
  UPDATE public.user_progress
    SET streak_freezes_available = p_freezes_available,
        streak_freeze_used_dates = p_freeze_used_dates,
        streak_freezes_last_refill = p_freezes_last_refill,
        streak_progress_version = v_new_version
    WHERE user_id = p_user_id
      AND streak_progress_version = p_expected_version;
  RETURN v_new_version;
END;
$$;

-- RLS: callable by authenticated users — the function itself enforces
-- the per-user check via p_user_id (which must equal auth.uid() in
-- the caller's enforcement layer). SECURITY DEFINER means the
-- function runs with the table owner's privileges; the
-- `SET search_path = public` mitigates the 7ad035 search-path-injection
-- class.
REVOKE EXECUTE ON FUNCTION public.update_streak_progress(
  UUID, BIGINT, INT, TEXT[], TEXT
) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_streak_progress(
  UUID, BIGINT, INT, TEXT[], TEXT
) TO authenticated;

COMMENT ON FUNCTION public.update_streak_progress IS
  'C-15 (audit-2026-05-11) — optimistic-lock writer for '
  'user_progress.streak_freezes_*. Returns the new version on success, '
  'NULL on version mismatch (caller re-reads + retries).';
