-- Intent: Close client access to public.promo_codes: drop the "Anyone can read active promo codes" policy and revoke every privilege from PUBLIC, anon and authenticated, so only the payment Edge Functions (service role) read the table.
-- Destructive?: yes   -- it DROPs a policy and REVOKEs grants; no row, column or data is touched
-- Rollback strategy: inline   -- the commented-out block at the end restores the captured pre-apply policy and ACL (and re-opens the listing, the original defect)
-- Linked diagnose-doc: a6c2e9

-- WHY (OI-406, diagnose docs/diagnoses/2026-10-24-promo-codes-anon-readable-a6c2e9.md). Migration
-- 20260330_create_promo_codes.sql created the policy "Anyone can read active promo codes" (FOR SELECT,
-- TO public, USING is_active = true), and the platform's default grants gave anon and authenticated
-- every table privilege. Measured live on 2026-10-24 before this migration: anon and authenticated
-- each held DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE (grantor postgres),
-- no PUBLIC entry, no column-level grants, and that one policy; a count-only request with the anon key
-- answered 206 `content-range: */3`. So anyone holding the app's public key could list every active
-- code with its discount without signing in. The writes were already refused by RLS (no INSERT,
-- UPDATE or DELETE policy); TRUNCATE is not subject to RLS but needs the grant revoked below.
--
-- WHO READS THE TABLE. No client: `lib/` and `web/` never name it (pinned by
-- test/contracts/promo_codes_server_only_writer_to_reader_test.dart). The readers are the four payment Edge
-- Functions (validate-promo, create-razorpay-order, verify-payment, razorpay-webhook), all through the
-- service role key, which keeps its own grant and bypasses RLS. RLS stays ENABLED with no policy, so a
-- future grant by mistake still exposes no row.
--
-- Proof after the apply: test/sql/promo_codes_no_client_access_live_verify.sql.

DROP POLICY IF EXISTS "Anyone can read active promo codes" ON public.promo_codes;

REVOKE ALL ON TABLE public.promo_codes FROM PUBLIC, anon, authenticated;

-- ROLLBACK (inline; run by hand only; it re-opens the listing this migration closes):
-- CREATE POLICY "Anyone can read active promo codes"
--   ON public.promo_codes
--   FOR SELECT
--   USING (is_active = true);
-- GRANT ALL ON TABLE public.promo_codes TO anon, authenticated;
