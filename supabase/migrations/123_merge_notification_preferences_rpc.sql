-- Intent: Make the client's write to user_preferences.notification_preferences PER-KEY ADDITIVE via a jsonb merge RPC, so a device holding a SPARSE preference map cannot delete keys it knows nothing about (OI-98 B-pass Finding 1 / diagnose e4a1b7).
-- Destructive?: no   -- CREATE FUNCTION + grants only; no table, column, or row is touched
-- Rollback strategy: inline   -- reverse block at the end of this file; DROP FUNCTION is total
-- Linked diagnose-doc: e4a1b7

-- ─────────────────────────────────────────────────────────────────────
-- WHY THIS EXISTS — OI-98's own root cause, one layer down
--
-- Migration 122 moved notification preferences out of the wholesale-replaced
-- `snapshot_json` blob and into their own column. That fixed the READ side and
-- left the WRITE side with the identical defect, because a jsonb COLUMN is also
-- replaced wholesale: PostgREST's upsert emits
-- `ON CONFLICT DO UPDATE SET col = EXCLUDED.col`, which is assignment, not a
-- merge.
--
-- The stored map is legitimately SPARSE. `NotificationPrefsRepository.read()`
-- returns exactly what the box holds, and the box holds only what the user has
-- touched: `notification_settings_screen.dart:50-56` seeds `_prefs` from
-- `read()` — `{}` on a fresh device — and each toggle adds ONE key. So a
-- perfectly ordinary device carries a one-key map.
--
-- That makes the failure concrete and routine, not contrived:
--   device A stores {streak_alerts:false}  -> column = {streak_alerts:false}
--   device B stores {weekly_recap:false}   -> column = {weekly_recap:false}
--                                             ^ A's key is DELETED
-- Each device silently revokes every preference it has not personally seen, and
-- the deleted key reverts to ABSENT => SEND. That is precisely OI-98 — a
-- notification the user switched off coming back on — reached through the new
-- home instead of the old one.
--
-- WHY A MERGE RPC AND NOT THE OBVIOUS ALTERNATIVES
--   - Padding the client map to all ten keys re-creates the OTHER half of
--     OI-98: it fabricates `enabled: true` for keys the user never set, and
--     those fabricated values then overwrite another device's real `false`.
--     That design was already reviewed and rejected once.
--   - A client read-modify-write costs a second round trip and races two
--     devices against each other.
--   - PostgREST cannot express a custom ON CONFLICT expression, so the merge
--     has to live in the database.
--
-- `||` on jsonb is a SHALLOW merge: right operand wins per top-level key. That
-- is exactly the semantic wanted — the device that just set a key owns that
-- key's whole value, and keys it did not send are left alone. It deliberately
-- does NOT deep-merge inside a single preference (so a device setting
-- `{enabled:false}` replaces that key's `{enabled:true, time:'20:00'}`
-- wholesale); the settings screen edits a key's value as a unit, so a per-key
-- unit is the right granularity.
--
-- SECURITY INVOKER, NOT DEFINER. The caller's own RLS applies
-- (`user_preferences_insert_own` / `_update_own`, both `auth.uid() = user_id`),
-- and the row is keyed on `auth.uid()` rather than a caller-supplied id, so a
-- user cannot write another user's preferences. A DEFINER function here would
-- both bypass RLS and escalate this migration's blast radius to catastrophic
-- for no benefit.
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.merge_notification_preferences(p_prefs jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Reject anything that is not a JSON object. `||` on a non-object would
  -- either error or concatenate as an array, and a malformed client payload
  -- must never be able to corrupt the stored map.
  IF p_prefs IS NULL OR jsonb_typeof(p_prefs) <> 'object' THEN
    RAISE EXCEPTION 'merge_notification_preferences: p_prefs must be a jsonb object, got %',
      COALESCE(jsonb_typeof(p_prefs), 'null');
  END IF;

  -- An empty object is a no-op rather than an error: the client already omits
  -- the call when it has nothing to say, and a belt here costs nothing.
  IF p_prefs = '{}'::jsonb THEN
    RETURN;
  END IF;

  INSERT INTO public.user_preferences (user_id, notification_preferences, updated_at)
  VALUES (auth.uid(), p_prefs, now())
  ON CONFLICT (user_id) DO UPDATE
    SET notification_preferences =
          COALESCE(public.user_preferences.notification_preferences, '{}'::jsonb)
          || EXCLUDED.notification_preferences,
        updated_at = now();
END;
$$;

-- BOTH revokes are required, and finding that out cost a live verification.
--
-- The usual trap is revoking a ROLE while PUBLIC still holds the grant — a
-- no-op that reads like a lockdown. That is real, hence the PUBLIC revoke. But
-- Supabase also ships ALTER DEFAULT PRIVILEGES granting EXECUTE on every new
-- `public` function to anon / authenticated / service_role EXPLICITLY, so a new
-- function lands carrying BOTH forms. Revoking only PUBLIC left
-- `anon=X/postgres` standing — confirmed by reading `proacl` after the apply
-- rather than assuming the grant block had done what it said:
--   postgres=X | anon=X | authenticated=X | service_role=X
--
-- Not exploitable as written (SECURITY INVOKER => an anon caller's auth.uid()
-- is NULL => user_preferences.user_id NOT NULL rejects the insert, and RLS
-- would refuse regardless), but an anon-executable function that writes a user
-- table is the wrong shape to leave standing. Applied live as 123b minutes
-- after 123; folded in here so a replay reaches the same end state in one pass.
--
-- ⚠ RECURRENCE, not a discovery. `supabase/migrations/CLAUDE.md` already
-- documents this exact trap (migration 103 / diagnose a9d3f1) and prescribes
-- the check that caught it: "VERIFY live: has_function_privilege('anon',
-- 'public.fn()', 'execute') must be false. Static review can't see it (the
-- grant isn't in any migration) — the live post-apply check is the only guard."
-- Post-fix, that check returns anon=false, authenticated=true,
-- service_role=true. The documented guard worked; the documented trap still
-- caught a second author, which is why it is repeated here at the call site
-- rather than left one directory away.
REVOKE ALL ON FUNCTION public.merge_notification_preferences(jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.merge_notification_preferences(jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.merge_notification_preferences(jsonb) TO authenticated;

COMMENT ON FUNCTION public.merge_notification_preferences(jsonb) IS
  'Per-key additive write for user_preferences.notification_preferences. Merges the supplied '
  'object over the stored one (jsonb ||, right wins per key) so a device holding a SPARSE map '
  'cannot delete keys it has never seen. SECURITY INVOKER + auth.uid(): the caller''s RLS '
  'applies and the row is keyed on the session user, not on a caller-supplied id. See OI-98 / '
  'diagnose e4a1b7.';

-- ─────────────────────────────────────────────────────────────────────
-- ROLLBACK (inline). Total and safe — the function holds no state:
--
--   DROP FUNCTION IF EXISTS public.merge_notification_preferences(jsonb);
--
-- ⚠ Dropping it WITHOUT reverting the client returns the write path to a
-- wholesale replace, which re-opens the sparse-map deletion above. Revert the
-- client's rpc() call to nothing rather than to the old upsert field.
-- ─────────────────────────────────────────────────────────────────────
