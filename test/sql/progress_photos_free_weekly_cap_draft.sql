-- Intent: A free (or lapsed) user may hold ONE progress photo per IST week (Mon 00:00 to Sun 23:59 IST) at BOTH doors (the Storage object and the progress_photos row); a user with an active, unexpired subscription has no cap.
-- Destructive?: yes   -- the literal reading of "yes if it DROPs" (as migration 154 declared): the block holds DROP TRIGGER IF EXISTS of its own two triggers (no-ops on the first run); no row is read, written or rewritten and no data is lost; the Storage INSERT policy is altered IN PLACE (name, roles, command and PERMISSIVE flag kept; its subscription conjunct moves into a trigger); one trigger on storage.objects, one BEFORE UPDATE trigger on public.progress_photos and three functions are added; the progress_photos INSERT trigger function body is replaced (its trigger is kept)
-- Rollback strategy: inline   -- commented block at the end of the file restores migration 154's objects exactly; needs its own explicit go (CLAUDE.md 4.3)
-- Linked diagnose-doc: f3c9a1
--
-- OI-348 Landing 3c (P2), plan docs/plans/oi348-landing3c.md. Reviewed as a draft outside the migrations
-- directory (supabase/migrations/CLAUDE.md) and copied here byte-identical at apply, with its number reserved
-- by scripts/mint_migration.sh; the draft path was test/sql/progress_photos_free_weekly_cap_draft.sql.
--
-- WHAT IT DOES. ONE statement (a DO block), so every change commits or rolls back together.
--
--   (1) public.progress_photo_week_start(timestamptz): the ONE definition of "this IST week": Monday 00:00
--       Asia/Kolkata as an instant. The client mirror is progressPhotoWeekStartUtc
--       (lib/features/profile/repositories/progress_photo_repository.dart).
--   (2) public.enforce_progress_photo_object_cap(): a BEFORE INSERT row trigger on storage.objects, fired
--       ONLY for bucket 'progress-photos' (the trigger's WHEN clause; no other bucket ever calls it). The
--       owner is the first folder of the object name; a name with no uuid folder is refused. When the
--       request's JWT role is anon or authenticated (auth.role(), claim-based: inside a definer
--       current_user is the definer) and the owner is not the caller (auth.uid(); NULL for anon), the
--       function returns at once and RLS refuses it (anon has no INSERT policy; the authenticated one is
--       own-folder): no count, no lock on the other user's key, no answer about that user's week. Any
--       other role (service_role, Storage's own role on a signed upload, a direct postgres insert, where
--       auth.role() is NULL) is capped by the OWNER of the folder.
--       PRO (status = 'active' AND end_date > now()) passes with no lock and no count. Otherwise a
--       per-owner advisory transaction lock, then: any object of the owner in the bucket created since the
--       week start refuses with 42501 and the literal progress_photo_pro_required. A trigger, not a policy
--       conjunct, because Storage checks a policy when a signed upload URL is MINTED and not when the upload
--       through it lands: several URLs minted while the slot is open would each upload. A row trigger fires
--       on every insert path.
--   (3) The Storage INSERT policy progress_photos_insert_own goes back to the own-folder test only (migration
--       154's subscription conjunct is now the trigger's PRO branch). Postgres applies RLS WITH CHECK after
--       BEFORE row triggers, so the trigger's refusal is the one a client sees.
--   (4) public.enforce_progress_photo_pro() (the progress_photos row door of migration 154; trigger
--       trg_progress_photo_pro kept, NOT re-created): when the request's JWT role is anon or authenticated
--       and NEW.user_id is not the caller, it returns at once and RLS WITH CHECK refuses the row: no lookup,
--       no lock, no answer about another user's subscription or week (the storage door's guard; Hermes A1:
--       as a definer it could otherwise read another user's state). Then NEW.created_at is set by the server: the created_at of
--       the caller's own Storage object at NEW.storage_path when there is one, else now(). The photo's week
--       is therefore its OBJECT's week at both doors (an upload at Sunday 23:59:50 whose row lands at Monday
--       00:00:05 belongs to Sunday's week at both). PRO passes; otherwise the same lock key, and any row of
--       the user whose created_at falls in the same IST week refuses with P0001 progress_photo_pro_required
--       (the literal shipped clients already read).
--   (5) public.keep_progress_photo_created_at() + trigger trg_progress_photo_created_at_keep BEFORE UPDATE
--       on public.progress_photos: an UPDATE cannot move created_at or storage_path (the owner's UPDATE policy
--       of migration 022 would otherwise let a free user backdate this week's row, or repoint an old row at
--       this week's object, and free the row door; no client updates either column).
--
-- SECURITY DEFINER (the three trigger functions; a change from migration 154's INVOKER, and from diagnose
-- d8f2a6's "no definer" choice, which was about a callable predicate helper): the insert that fires the
-- storage trigger is not always made as the uploading user (a signed upload lands through Storage's own
-- role), and an invoker read of public.subscriptions through RLS would then see no row and refuse a payer.
-- The functions RETURN trigger, so no role can call them through PostgREST; EXECUTE is revoked from
-- PUBLIC, anon and authenticated anyway, every function call except the built-ins (now, date_trunc: the
-- pinned path searches pg_catalog first) is schema-qualified, and the search_path is pinned.
--
-- WHAT COUNTS. Photos HELD in the IST week. Deleting this week's photo opens the slot again (a retake);
-- storage held stays at most one object per week for a free user. A lapsed PRO is free. An object whose
-- row insert failed counts until the client removes it (removeIfNoRow, then the bounded sweep).
--
-- CONCURRENCY. The lock is taken before the count; the count is a separate statement of a VOLATILE
-- plpgsql function, so under READ COMMITTED it takes a fresh snapshot and sees an upload that committed
-- while this one waited. Designed, not measured (two concurrent sessions cannot be driven through MCP).
--
-- CONSTRAINT FOR FUTURE WRITERS: these triggers fire for every INSERT / UPDATE, service role and postgres
-- included. Only the table owner can step around them. A future writer of progress photos for a free user
-- is capped like the user, and any created_at it sends is DISCARDED (the server sets it on INSERT and keeps
-- it on UPDATE); a restore that must keep old created_at values needs the owner to disable the triggers.
--
-- TWO COUNTS. The storage door counts objects, the row door rows. A free user who deletes this week's
-- object through the Storage API (keeping its row) can upload a second object; its row is then refused
-- by the row door and the client removes the object (removeIfNoRow), so storage held stays bounded.
--
-- FAILS OPEN IF DROPPED. Migration 154's policy conjunct failed CLOSED (PRO only) if anything went wrong;
-- this rule lives in a trigger, and a dashboard edit or a Storage platform migration that drops
-- trg_progress_photo_object_cap leaves every user uncapped with no alert (OI-316's class; the live
-- verify catches it once, at apply time). Accepted for a free photo of at most 8 MiB per upload; named
-- on OI-316.
--
-- LOCKS: CREATE TRIGGER on storage.objects and public.progress_photos (SHARE ROW EXCLUSIVE), ALTER POLICY on
-- storage.objects and the supautils hooks named in migration 154's header (ACCESS EXCLUSIVE on the auth,
-- realtime and storage tables, held until the block commits). Milliseconds on an idle database. Apply
-- off-peak.
--
-- Verification after apply (founder go): test/sql/progress_photos_free_weekly_cap_live_verify.sql (one
-- always-aborting DO block, nothing persists).

DO $mig$
BEGIN
  -- a lock wait longer than 5 s aborts the whole block: nothing is applied, a re-run is idempotent
  PERFORM set_config('lock_timeout', '5s', true);

  -- (1) the IST week start
  CREATE OR REPLACE FUNCTION public.progress_photo_week_start(p_at timestamptz)
  RETURNS timestamptz LANGUAGE sql STABLE SET search_path = pg_catalog, pg_temp AS $fn$
    SELECT (date_trunc('week', p_at AT TIME ZONE 'Asia/Kolkata')) AT TIME ZONE 'Asia/Kolkata'
  $fn$;
  REVOKE EXECUTE ON FUNCTION public.progress_photo_week_start(timestamptz) FROM PUBLIC, anon, authenticated;

  -- (2) the Storage door
  CREATE OR REPLACE FUNCTION public.enforce_progress_photo_object_cap()
  RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $fn$
  DECLARE
    v_owner uuid;
    v_caller uuid := auth.uid();
    v_role text := auth.role();
  BEGIN
    BEGIN
      v_owner := ((storage.foldername(NEW.name))[1])::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
      v_owner := NULL;
    END;
    IF v_owner IS NULL THEN
      RAISE EXCEPTION 'progress_photo_pro_required' USING ERRCODE = '42501';
    END IF;
    IF v_role IN ('anon', 'authenticated') AND v_owner IS DISTINCT FROM v_caller THEN
      RETURN NEW;
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.user_id = v_owner
        AND s.status = 'active'
        AND s.end_date > now()
    ) THEN
      RETURN NEW;
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('progress_photo_cap:' || v_owner::text, 0));
    IF EXISTS (
      SELECT 1 FROM storage.objects o
      WHERE o.bucket_id = 'progress-photos'
        AND o.name LIKE v_owner::text || '/%'
        AND o.created_at >= public.progress_photo_week_start(now())
    ) THEN
      RAISE EXCEPTION 'progress_photo_pro_required' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END;
  $fn$;
  REVOKE EXECUTE ON FUNCTION public.enforce_progress_photo_object_cap() FROM PUBLIC, anon, authenticated;

  DROP TRIGGER IF EXISTS trg_progress_photo_object_cap ON storage.objects;
  CREATE TRIGGER trg_progress_photo_object_cap
    BEFORE INSERT ON storage.objects
    FOR EACH ROW
    WHEN (NEW.bucket_id = 'progress-photos')
    EXECUTE FUNCTION public.enforce_progress_photo_object_cap();

  -- (3) the Storage INSERT policy: own folder only (the PRO test moved into the trigger)
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'progress_photos_insert_own'
  ) THEN
    ALTER POLICY "progress_photos_insert_own" ON storage.objects
      WITH CHECK (
        bucket_id = 'progress-photos'
        AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
      );
  ELSE
    CREATE POLICY "progress_photos_insert_own" ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (
        bucket_id = 'progress-photos'
        AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
      );
  END IF;

  -- (4) the row door (trigger trg_progress_photo_pro of migration 154 is kept, not re-created)
  CREATE OR REPLACE FUNCTION public.enforce_progress_photo_pro()
  RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $fn$
  DECLARE
    v_week timestamptz;
  BEGIN
    IF auth.role() IN ('anon', 'authenticated') AND NEW.user_id IS DISTINCT FROM auth.uid() THEN
      RETURN NEW;
    END IF;
    NEW.created_at := COALESCE(
      (SELECT o.created_at FROM storage.objects o
        WHERE o.bucket_id = 'progress-photos'
          AND o.name = NEW.storage_path
          AND o.name LIKE NEW.user_id::text || '/%'),
      now());
    IF EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.user_id = NEW.user_id
        AND s.status = 'active'
        AND s.end_date > now()
    ) THEN
      RETURN NEW;
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('progress_photo_cap:' || NEW.user_id::text, 0));
    v_week := public.progress_photo_week_start(NEW.created_at);
    IF EXISTS (
      SELECT 1 FROM public.progress_photos p
      WHERE p.user_id = NEW.user_id
        AND p.created_at >= v_week
        AND p.created_at < v_week + interval '168 hours'
    ) THEN
      RAISE EXCEPTION 'progress_photo_pro_required' USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
  END;
  $fn$;
  REVOKE EXECUTE ON FUNCTION public.enforce_progress_photo_pro() FROM PUBLIC, anon, authenticated;

  -- (5) an UPDATE cannot move created_at
  CREATE OR REPLACE FUNCTION public.keep_progress_photo_created_at()
  RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $fn$
  BEGIN
    NEW.created_at := OLD.created_at;
    NEW.storage_path := OLD.storage_path;
    RETURN NEW;
  END;
  $fn$;
  REVOKE EXECUTE ON FUNCTION public.keep_progress_photo_created_at() FROM PUBLIC, anon, authenticated;

  DROP TRIGGER IF EXISTS trg_progress_photo_created_at_keep ON public.progress_photos;
  CREATE TRIGGER trg_progress_photo_created_at_keep
    BEFORE UPDATE ON public.progress_photos
    FOR EACH ROW EXECUTE FUNCTION public.keep_progress_photo_created_at();
END
$mig$;

-- ── Rollback (inline) ──────────────────────────────────────────────────────
-- Needs its own explicit go (CLAUDE.md 4.3). One statement, atomic like the forward block. Restores
-- migration 154's live state: the Storage INSERT policy with its subscription conjunct, the row trigger
-- function as SECURITY INVOKER with 154's body and its live ACL before this migration (read 2026-11-26:
-- {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}),
-- no storage trigger, no UPDATE trigger. Same lock footprint. Proven by the second rehearsal (forward,
-- this block, then test/sql/progress_photos_free_weekly_cap_rollback_verify.sql in one aborting statement).
--
-- DO $rb$
-- BEGIN
--   PERFORM set_config('lock_timeout', '5s', true);
--   DROP TRIGGER IF EXISTS trg_progress_photo_object_cap ON storage.objects;
--   DROP FUNCTION IF EXISTS public.enforce_progress_photo_object_cap();
--   DROP TRIGGER IF EXISTS trg_progress_photo_created_at_keep ON public.progress_photos;
--   DROP FUNCTION IF EXISTS public.keep_progress_photo_created_at();
--   ALTER POLICY "progress_photos_insert_own" ON storage.objects
--     WITH CHECK (
--       bucket_id = 'progress-photos'
--       AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
--       AND EXISTS (
--         SELECT 1 FROM public.subscriptions s
--         WHERE s.user_id = (SELECT auth.uid())
--           AND s.status = 'active'
--           AND s.end_date > now()
--       )
--     );
--   CREATE OR REPLACE FUNCTION public.enforce_progress_photo_pro()
--   RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, pg_temp AS $fn$
--   BEGIN
--     IF NOT EXISTS (
--       SELECT 1 FROM public.subscriptions
--       WHERE user_id = NEW.user_id
--         AND status = 'active'
--         AND end_date > now()
--     ) THEN
--       RAISE EXCEPTION 'progress_photo_pro_required' USING ERRCODE = 'P0001';
--     END IF;
--     RETURN NEW;
--   END;
--   $fn$;
--   GRANT EXECUTE ON FUNCTION public.enforce_progress_photo_pro() TO PUBLIC, anon, authenticated, service_role;
--   DROP FUNCTION IF EXISTS public.progress_photo_week_start(timestamptz);
-- END
-- $rb$;
