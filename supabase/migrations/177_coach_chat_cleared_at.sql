-- Intent: OI-479 - add user_preferences.coach_chat_cleared_at (the AI Coach "Clear conversation" marker) and its monotonic writer RPC raise_coach_chat_cleared_at(timestamptz)
-- Destructive?: no   -- adds one nullable column and one function; no row is rewritten
-- Rollback strategy: inline
-- Linked diagnose-doc: 5970aa

-- WHY. "Clear conversation" hides the chat thread without deleting any row
-- (founder decision D1, plan docs/plans/2026-11-12-oi479-clear-conversation.md).
-- The client keeps one instant, the clear time, and hides every chat row created
-- at or before it. The instant lives here so a restore, a reinstall or a second
-- device does not bring the old thread back (D4).
--
-- The column is written ONLY through raise_coach_chat_cleared_at, never through the
-- client's user_preferences upsert (a two-key whitelist, buildUserPreferencesPayload,
-- whose wholesale replace would let a device holding an OLDER value lower a newer one).

ALTER TABLE public.user_preferences
  ADD COLUMN IF NOT EXISTS coach_chat_cleared_at timestamptz NULL;

COMMENT ON COLUMN public.user_preferences.coach_chat_cleared_at IS
  'AI Coach "Clear conversation" marker: chat rows created at or before this instant are '
  'hidden from the chat thread and the coach history replay on every device. Monotonic, '
  'written only by raise_coach_chat_cleared_at. NULL = never cleared. OI-479.';

-- SECURITY INVOKER + auth.uid(), the shape of migration 123's
-- merge_notification_preferences: the caller's own-row RLS applies and the row is keyed
-- on the session user, never on a caller-supplied id.
--   * NULL p_at is refused: LEAST(NULL, now()) is now(), which would hide the whole
--     thread everywhere.
--   * LEAST(p_at, now()) clamps a fast client clock to the server's now, so a bad clock
--     cannot hide messages written after the clear.
--   * GREATEST keeps the value monotonic (and ignores a NULL stored value): a device
--     holding an older clear can never lower a newer one.
CREATE OR REPLACE FUNCTION public.raise_coach_chat_cleared_at(p_at timestamptz)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'raise_coach_chat_cleared_at: no authenticated user';
  END IF;
  IF p_at IS NULL THEN
    RAISE EXCEPTION 'raise_coach_chat_cleared_at: p_at must not be null';
  END IF;

  INSERT INTO public.user_preferences AS up (user_id, coach_chat_cleared_at, updated_at)
  VALUES (auth.uid(), LEAST(p_at, now()), now())
  ON CONFLICT (user_id) DO UPDATE
    SET coach_chat_cleared_at = GREATEST(up.coach_chat_cleared_at, LEAST(p_at, now())),
        updated_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.raise_coach_chat_cleared_at(timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.raise_coach_chat_cleared_at(timestamptz) FROM anon;
GRANT EXECUTE ON FUNCTION public.raise_coach_chat_cleared_at(timestamptz) TO authenticated;

COMMENT ON FUNCTION public.raise_coach_chat_cleared_at(timestamptz) IS
  'Monotonic writer of user_preferences.coach_chat_cleared_at for the session user '
  '(GREATEST of the stored value and LEAST(p_at, now())). Refuses a NULL p_at. '
  'SECURITY INVOKER + auth.uid(). OI-479.';

-- Rollback (inline):
-- DROP FUNCTION IF EXISTS public.raise_coach_chat_cleared_at(timestamptz);
-- ALTER TABLE public.user_preferences DROP COLUMN IF EXISTS coach_chat_cleared_at;
