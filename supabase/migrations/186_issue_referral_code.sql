-- Intent: The server mints referral codes (OI-348 B2, walk A10): public.issue_referral_code() returns the caller's live code, or mints a fresh 7-day one when there is none or it expired; REGENERATE stops failing on the missing UPDATE policy.
-- Destructive?: no   -- adds one function; an expired code row is overwritten by design (an expired code is refused by redeem-referral already)
-- Rollback strategy: inline   -- the reverse DDL is at the end of this file
-- Linked diagnose-doc: c2e8a4

-- Plan: docs/plans/oi348-walk-fixes-landing2.md, Unit B2 (PR B).
--
-- Why: the client upserted {user_id, code, expires_at} onConflict user_id. For an existing row
-- that is an UPDATE, and referral_codes has SELECT and INSERT policies only (migration 035), so
-- every REGENERATE after the first code failed with 42501 and the sheet showed nothing. The INSERT
-- policy also let a user's FIRST row carry any code text and any expiry; that door is closed by
-- migration M2 (PR C) once the web build calling this function is live.
--
-- Shape:
--   * SECURITY DEFINER, owner postgres, relforcerowsecurity false: the function bypasses RLS and
--     keeps the table privileges. SET search_path = '' and every name schema-qualified.
--   * The OUT names (out_code, out_expires_at) differ from the columns: equal names make plpgsql
--     raise "column reference is ambiguous" inside the body.
--   * auth.uid() NULL -> raise: there is no anonymous path, and EXECUTE is revoked from anon.
--   * A per-user transaction advisory lock serialises two devices tapping at once. Without it the
--     second call passes its expiry check, waits on the first call's row lock, then OVERWRITES the
--     code the first call just returned. Held across the collision retries.
--   * A live code (expires_at > now()) is returned unchanged; expiry exactly now() is expired.
--   * A new code is 'AVYA-' plus 8 characters of [A-Z0-9] drawn from extensions.gen_random_bytes;
--     a byte >= 252 is discarded (252 = 7 x 36), so the draw has no modulo bias.
--   * ON CONFLICT (user_id) DO UPDATE replaces an EXPIRED row only (WHERE expires_at <= now()):
--     until migration M2 the old client can still INSERT a first code without taking the lock,
--     and a live row it commits after the check above is kept, not overwritten (the final
--     re-select returns it). A clash on the UNIQUE code
--     (referral_codes_code_key) retries with a new code, up to 5 attempts; any other unique
--     violation is re-raised.
--   * The result is always re-read from the table at the end; zero rows raise, so the function
--     never answers with nothing.

CREATE OR REPLACE FUNCTION public.issue_referral_code()
RETURNS TABLE (out_code text, out_expires_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_alphabet constant text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  v_body text;
  v_bytes bytea;
  v_byte int;
  v_i int;
  v_attempt int;
  v_constraint text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'issue_referral_code: not authenticated'
      USING ERRCODE = '42501';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('issue_referral_code:' || v_uid::text, 0));

  IF EXISTS (
    SELECT 1
      FROM public.referral_codes rc
     WHERE rc.user_id = v_uid
       AND rc.expires_at > pg_catalog.now()
  ) THEN
    RETURN QUERY
      SELECT rc.code, rc.expires_at
        FROM public.referral_codes rc
       WHERE rc.user_id = v_uid;
    RETURN;
  END IF;

  FOR v_attempt IN 1..5 LOOP
    v_body := '';
    WHILE pg_catalog.length(v_body) < 8 LOOP
      v_bytes := extensions.gen_random_bytes(16);
      FOR v_i IN 0..15 LOOP
        EXIT WHEN pg_catalog.length(v_body) >= 8;
        v_byte := pg_catalog.get_byte(v_bytes, v_i);
        IF v_byte < 252 THEN
          v_body := v_body || pg_catalog.substr(v_alphabet, (v_byte % 36) + 1, 1);
        END IF;
      END LOOP;
    END LOOP;

    BEGIN
      INSERT INTO public.referral_codes AS rc (user_id, code, expires_at, created_at)
      VALUES (v_uid, 'AVYA-' || v_body,
              pg_catalog.now() + interval '7 days', pg_catalog.now())
      ON CONFLICT (user_id) DO UPDATE
        SET code = EXCLUDED.code,
            expires_at = pg_catalog.now() + interval '7 days',
            created_at = pg_catalog.now()
        WHERE rc.expires_at <= pg_catalog.now();
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
      IF v_constraint IS DISTINCT FROM 'referral_codes_code_key' THEN
        RAISE;
      END IF;
      IF v_attempt = 5 THEN
        RAISE EXCEPTION 'issue_referral_code: no free code after 5 attempts';
      END IF;
    END;
  END LOOP;

  RETURN QUERY
    SELECT rc.code, rc.expires_at
      FROM public.referral_codes rc
     WHERE rc.user_id = v_uid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'issue_referral_code: no row for the caller after the write';
  END IF;
END;
$$;

-- The platform's default privileges grant EXECUTE on a new public function DIRECTLY to anon and
-- authenticated, so revoking from PUBLIC alone leaves anon able to call it
-- (supabase/migrations/CLAUDE.md, migration 103 / a9d3f1).
REVOKE EXECUTE ON FUNCTION public.issue_referral_code() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.issue_referral_code() TO authenticated;

-- ---------------------------------------------------------------------------
-- Rollback (inline). The real rollback is ROLL-FORWARD: fix the body in a NEW migration with
-- CREATE OR REPLACE, restating SECURITY DEFINER and SET search_path = '' (a replace keeps the
-- ACL but resets both). Dropping the function leaves every build from this change on with no
-- way to get a code (load and REGENERATE both show the error + TRY AGAIN; the old client write
-- is deleted from this build); builds before it never call the function. An expired code the
-- function replaced is not restorable (it was refused by redeem-referral already).
--
-- DROP FUNCTION IF EXISTS public.issue_referral_code();
