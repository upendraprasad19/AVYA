-- Intent: The database refuses to INSERT a progress photo (the Storage object and the progress_photos row) unless the user has an active, unexpired subscription; INSERT only, so a lapsed user can still view and delete the photos they already have.
-- Destructive?: yes   -- the literal reading of "yes if it DROPs": the block holds DROP TRIGGER IF EXISTS (this rule's own trigger, a no-op on the first run) and DROP POLICY IF EXISTS of a policy that is absent live; no row is read, written or rewritten and no data is lost; the Storage INSERT policy is altered IN PLACE (name, roles, command and PERMISSIVE flag kept) and one trigger with its function is added
-- Rollback strategy: inline   -- commented block at the end of the file: ALTER POLICY back to the pre-rule expression, DROP TRIGGER, DROP FUNCTION; needs its own explicit go (CLAUDE.md 4.3)
-- Linked diagnose-doc: d8f2a6
--
-- 154_progress_photos_pro_insert_rls_rule.sql
--
-- Plan: docs/plans/progress-photos-pro-server-rule.md. Unit B1 of the
-- 2026-10-06 progress-photos batch; decision 4 of the founder's six ("yes, separately, with your go").
-- The live apply needs the founder's explicit go for that apply (CLAUDE.md 4.3).
--
-- WHAT IT DOES. ONE statement (a DO block), so every change commits or rolls back together whatever
-- apply_migration does about transactions (that is unverified, see migration 152's header):
--
--   (1) the Storage policy "progress_photos_insert_own" on storage.objects gains a third condition,
--       the caller's active subscription. The policy has no repo history (it exists live; the
--       live catalog is the only source); the first two conjuncts are the live policy's, unchanged apart from the
--       (SELECT ...) wrap of migration 100's initplan idiom. The Storage object is the COST: capture()
--       uploads FIRST, so only this policy stops it. If the policy is absent (a fresh database) it is
--       CREATEd, PERMISSIVE, FOR INSERT, TO authenticated, with the identical expression.
--   (2)(3) a BEFORE INSERT row trigger on public.progress_photos with a SECURITY INVOKER function and
--       a pinned search_path. The row is what the gallery lists and what a direct PostgREST call
--       could forge. Error idiom of the cap triggers: RAISE EXCEPTION '<literal>' USING ERRCODE = 'P0001'.
--   (4) DROP POLICY IF EXISTS "users_own_subscriptions" ON public.subscriptions. Migration 008 creates
--       that policy (FOR ALL, own rows) and nothing in the repo ever drops it; it is ABSENT live
--       (catalog evidence in the plan; how it went missing is not recorded in the repo), so this is a no-op live and makes a database rebuilt from
--       the repo match live. The rule above depends on there being no client write path into
--       subscriptions.
--
-- THE PREDICATE is the server's one definition of PRO, copied (not wrapped in a helper): status =
-- 'active' AND end_date > now(), as in verify-subscription, migration 111 and migration 153.
--
-- INSERT ONLY (founder decision 6): SELECT, DELETE and UPDATE policies on progress_photos and on
-- storage.objects are untouched, so a lapsed user can still view and delete old photos. The rule
-- depends on authenticated keeping SELECT on public.subscriptions through subscriptions_select_own.
-- Precisely: the trigger fires BEFORE conflict resolution, so an `INSERT ... ON CONFLICT DO UPDATE` (or
-- DO NOTHING) by a lapsed user is refused too even when it would only have updated an existing row; edit
-- a row with a plain UPDATE. No caller upserts progress_photos today.
--
-- ERROR SHAPES the client is expected to see (the contract unit B2 consumes; NOT verified against the
-- live Storage API, which this unit never ran). capture() uploads first, so the Storage policy refuses
-- first: a StorageException whose statusCode is '403' (the client takes it from the response BODY first
-- and the HTTP status second, and the HTTP status itself can be 400 or 403 depending on the Storage
-- version), message "new row violates row-level security policy". Key on statusCode '403' or that
-- message, not on the HTTP status. The trigger's PostgREST P0001 / progress_photo_pro_required is the
-- second line of defence and will rarely reach the client.
--
-- CONSTRAINT FOR FUTURE WRITERS: the trigger fires for every INSERT, a service-role one and a postgres one
-- included. Only the table OWNER can step around it (ALTER TABLE ... DISABLE TRIGGER, or SET
-- session_replication_role = replica, as manual or restore work would); no other role can. A future Edge Function that writes progress photos for a lapsed user is refused unless it
-- changes this rule. A service-role STORAGE upload bypasses RLS and is governed by neither policy: only
-- the table trigger governs the row, so such a writer would succeed at Storage, be refused at the row
-- and leave an orphan object.
--
-- NOT DONE HERE (named, so they are not mistaken for closed): a PRO caller's uploads are uncapped on
-- the server (the 5/day cap is client-side); a signed upload URL minted while PRO stays usable until
-- it expires (minutes to hours; resumable and S3-protocol upload sessions were not examined, and neither
-- window was verified here); an object uploaded whose
-- row insert then fails is an orphan; a user who has JUST paid is refused until their subscriptions row
-- exists (the webhook or verify-payment writes it: seconds, up to about 20 minutes in the worst
-- realistic case, see docs/architecture/subscription.md); the out-of-repo Telegram bot (a separate
-- project) was not checked for progress_photos inserts; Storage object COPY and MOVE, and the Storage
-- API's own upsert path, were not examined against the policy; a dashboard edit of the policies is not
-- detected by any recurring check; a DEBUG build can show a user as PRO with no subscriptions row (the
-- dev-panel grant, the no-expiry debug flag, the simulation switch) and that user is refused here like
-- any other; the Storage policy binds now() and its operators WHEN THE BLOCK RUNS, through the apply
-- session's search_path (the trigger function pins its own), so apply with a path that does not list
-- public before pg_catalog and with no public.now() or operator on timestamptz present (the live
-- catalog had neither on 2026-10-06; V6b would catch a shadow that changes the result).
--
-- LOCKS (a LOWER bound, not a full list). The block takes ACCESS EXCLUSIVE locks on storage.objects,
-- public.progress_photos and public.subscriptions. In addition, TWO supautils hooks take ACCESS
-- EXCLUSIVE locks for the postgres role: supautils.policy_grants (fired by policy DDL) and
-- supautils.drop_trigger_grants (fired by DROP TRIGGER), both listing the SAME 24 tables (the auth
-- tables including users, sessions, identities and refresh_tokens, realtime.messages and
-- realtime.subscription, and the storage tables including buckets, objects and prefixes). They fire
-- even when the statement is a no-op (DROP POLICY IF EXISTS, DROP TRIGGER IF EXISTS), and this block
-- runs both kinds, so treat every auth, realtime and storage table as lockable. On a local replica
-- the tables that existed there were locked; on the live database all 24 should be. All locks are held
-- until the block commits: sign-in, token refresh, Realtime and every Storage request queue behind it
-- for the run (milliseconds on an idle database). lock_timeout bounds each lock WAIT, not the block,
-- and each table is its own wait, so the worst case is many waits of up to 5 s before the abort. A
-- concurrent auth transaction that locks two of these tables in the opposite order can deadlock with
-- the block: PostgreSQL ends one of the two after deadlock_timeout (1 s on the replica, shorter than
-- lock_timeout), and it can be the AUTH transaction, not this block (a failed sign-in or refresh, no
-- data lost; observed with a synthetic holder on the replica, GoTrue's real lock order is not in the
-- repo). The inline rollback block below has the same footprint. Apply off-peak.
--
-- Verification after apply (founder-run): test/sql/progress_photos_pro_insert_rule_live_verify.sql writes
-- test rows and role switches INSIDE one always-aborting DO block (nothing persists); the catalog re-reads
-- listed in the plan, section 2 D7 step 6, are read-only.

DO $mig$
BEGIN
  -- a lock wait longer than 5 s aborts the whole block: nothing is applied, a re-run is idempotent
  PERFORM set_config('lock_timeout', '5s', true);

  -- (1) the cost gate: the Storage INSERT policy
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'progress_photos_insert_own'
  ) THEN
    ALTER POLICY "progress_photos_insert_own" ON storage.objects
      WITH CHECK (
        bucket_id = 'progress-photos'
        AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
        AND EXISTS (
          SELECT 1 FROM public.subscriptions s
          WHERE s.user_id = (SELECT auth.uid())
            AND s.status = 'active'
            AND s.end_date > now()
        )
      );
  ELSE
    CREATE POLICY "progress_photos_insert_own" ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (
        bucket_id = 'progress-photos'
        AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
        AND EXISTS (
          SELECT 1 FROM public.subscriptions s
          WHERE s.user_id = (SELECT auth.uid())
            AND s.status = 'active'
            AND s.end_date > now()
        )
      );
  END IF;

  -- (2) the trigger function (invoker rights, pinned search path)
  CREATE OR REPLACE FUNCTION public.enforce_progress_photo_pro()
  RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
  BEGIN
    IF NOT EXISTS (
      SELECT 1 FROM public.subscriptions
      WHERE user_id = NEW.user_id
        AND status = 'active'
        AND end_date > now()
    ) THEN
      RAISE EXCEPTION 'progress_photo_pro_required' USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
  END;
  $fn$;

  -- (3) the row-level door
  DROP TRIGGER IF EXISTS trg_progress_photo_pro ON public.progress_photos;
  CREATE TRIGGER trg_progress_photo_pro
    BEFORE INSERT ON public.progress_photos
    FOR EACH ROW EXECUTE FUNCTION public.enforce_progress_photo_pro();

  -- (4) close the repo's own self-grant path (a no-op live, idempotent)
  DROP POLICY IF EXISTS "users_own_subscriptions" ON public.subscriptions;
END
$mig$;

-- ── Rollback (inline) ──────────────────────────────────────────────────────
-- Needs its own explicit go (CLAUDE.md 4.3). One statement, atomic like the forward block. It
-- restores the pre-rule Storage policy expression (the live text recorded as evidence E1 of the plan:
-- bucket_id = 'progress-photos' AND (storage.foldername(name))[1] = (auth.uid())::text), drops the
-- trigger and then its function. It does NOT re-create users_own_subscriptions (that policy was never
-- live, and re-creating it would re-open a self-grant path). It reverses the ALTER branch only: on a
-- database where the forward block had to CREATE the policy (a database rebuilt from the repo, where it
-- was absent), the policy stays behind with the pre-rule expression; drop it by hand if the pre-state
-- is required. Same lock footprint as the forward block (see LOCKS above), same off-peak advice.
--
-- DO $rb$
-- BEGIN
--   PERFORM set_config('lock_timeout', '5s', true);
--   ALTER POLICY "progress_photos_insert_own" ON storage.objects
--     WITH CHECK (
--       bucket_id = 'progress-photos'
--       AND (storage.foldername(name))[1] = (auth.uid())::text
--     );
--   DROP TRIGGER IF EXISTS trg_progress_photo_pro ON public.progress_photos;
--   DROP FUNCTION IF EXISTS public.enforce_progress_photo_pro();
-- END
-- $rb$;
