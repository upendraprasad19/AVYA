-- Intent: Allow client_errors.user_id to be NULL so signed-out (pre-auth) failures can be recorded at all — today they are structurally unloggable.
-- Destructive?: no   -- DROP NOT NULL only widens what the column accepts; every existing row keeps its user_id and no data is read, written or moved
-- Rollback strategy: inline   -- see commented-out reverse block at end of file; it re-adds NOT NULL and is only valid once the pre-auth rows are deleted
-- Linked diagnose-doc: b6e4f2

-- closes-diagnose: b6e4f2
--
-- Every failure that happens BEFORE a session exists — forgot-password send,
-- sign-in, sign-up, the OAuth launch — was impossible to record, on four
-- independent counts:
--
--   1. client  — `ErrorTelemetry.logEvent` routes through
--                `SupabaseService.callFunction`, which refreshes the session
--                first and THROWS 'No active session. Please sign in again.'
--                (supabase_service.dart:246-250) when there isn't one. The
--                event died before the network.
--   2. function— `log-client-error` returned 401 for any token that resolved
--                to no user (index.ts:234-236) and stamped `user_id: user.id`.
--   3. column  — THIS constraint: `client_errors.user_id` was NOT NULL.
--   4. RLS     — the INSERT policy is `(SELECT auth.uid()) = user_id`.
--
-- Consequence: `auth_forgot_password_send_failed` has ZERO rows in the table's
-- entire history, so when the founder hit "Could not send reset link" on
-- 2026-08-06 there was no evidence whatsoever of what had thrown. The Edge
-- Function's own header calls auth failures signals "we must never lose", and
-- it gives `auth_failure_` a high-priority lane that the signed-out half of
-- them could never reach.
--
-- This migration removes barrier 3. Barriers 1 and 2 are removed in the same
-- commit (error_telemetry.dart + log-client-error/index.ts).
--
-- Barrier 4 is deliberately LEFT IN PLACE: the pre-auth lane writes through
-- the Edge Function's SERVICE_ROLE client, which bypasses RLS, while the
-- authenticated INSERT policy still rejects a NULL user_id. So a signed-in
-- client cannot forge an anonymous row, and the only way one enters the table
-- is through the function's op_type allow-list and its global daily cap.
--
-- The FK `client_errors_user_id_fkey -> auth.users(id) ON DELETE CASCADE`
-- is UNCHANGED and stays valid: SQL foreign keys do not constrain NULL, so a
-- NULL user_id passes without needing a sentinel row in auth.users (a sentinel
-- was the alternative considered and rejected — it would have meant creating a
-- fake auth user, and every existing `user_id = <sentinel>` query would have
-- silently swept real pre-auth rows into per-user reports).
--
-- Reader impact: existing queries either filter by a real user_id (unaffected —
-- a NULL never equals one) or scan the whole table (they now also see pre-auth
-- rows, which is the point). `user_id IS NULL` is the discriminator.
--
-- Alert impact, VERIFIED (not assumed): `alert_client_errors_spike` is a
-- pg_cron job body, not a pg_proc — its current definition is migration 087.
-- It counts `public.client_errors` over a 1h window with NO user_id predicate,
-- and 087 deliberately RE-INCLUDES breadcrumb-coded (`error_code='event'`) rows
-- whose op_type is failure-shaped. Every PRE_AUTH_OP_TYPES entry ends in
-- `_failed`, so pre-auth failures DO count toward the spike alert. That is the
-- intended behaviour — a burst of signed-out auth failures is exactly the thing
-- worth waking up for — and the lane's 200-row/24h global cap bounds how loud it
-- can get.

ALTER TABLE public.client_errors
  ALTER COLUMN user_id DROP NOT NULL;

COMMENT ON COLUMN public.client_errors.user_id IS
  'Owning user. NULL = pre-auth (signed-out) telemetry written by the '
  'log-client-error Edge Function''s allow-listed anonymous lane — see '
  'diagnose b6e4f2. Authenticated inserts still require auth.uid() = user_id '
  'via RLS, so only the service-role function can produce a NULL row.';

-- ── Rollback (inline) ────────────────────────────────────────────────
-- NOT NULL cannot be restored while pre-auth rows exist, so the delete is
-- part of the rollback, not an optional extra. It discards exactly the rows
-- this feature adds and nothing else.
--
-- DELETE FROM public.client_errors WHERE user_id IS NULL;
-- ALTER TABLE public.client_errors ALTER COLUMN user_id SET NOT NULL;
-- COMMENT ON COLUMN public.client_errors.user_id IS NULL;
