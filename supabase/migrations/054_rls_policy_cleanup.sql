-- Migration 054: RLS policy cleanup — rank_ladder + promo_code_uses
--
-- closes-finding: H-30, H-40 (audit 2026-05-11)
--
-- Two unrelated RLS hygiene fixes batched as a single migration since
-- both are <10 lines of policy DDL with no shared tooling concern.
--
-- H-40: rank_ladder is reference data (11 rows: SD2 ... Capt) used by
-- both the client (rank_service.dart, phase_roadmap_screen.dart) and
-- Edge Functions. RLS was enabled but no policy existed — the table
-- is currently unreadable for authenticated callers (deny-all). The
-- client codebase doesn't query it directly today (Dart constants
-- mirror the rows), but adding a public-read policy is correct
-- future-proofing AND removes the `rls_enabled_no_policy` advisor flag.
--
-- H-30: promo_code_uses had an INSERT policy `Service role can insert
-- promo uses` with `roles=public, with_check=true`. Despite the name,
-- it was NOT scoped to service_role — any authenticated user could
-- insert audit rows directly via PostgREST. Flagged by Supabase
-- advisor as `rls_policy_always_true`. Service role bypasses RLS so
-- doesn't need a policy; the right fix is to drop the open policy and
-- replace with `WITH CHECK (false)` which blocks every role except
-- service_role (which bypasses RLS regardless).
--
-- Pre-migration audit (run 2026-05-11 via MCP):
--   - rank_ladder: rls_enabled=true, 11 rows, 0 policies
--   - promo_code_uses: 2 policies. INSERT had with_check=true (always-true).
--   - Codebase: rank_ladder NOT queried via PostgREST in lib/; only
--     referenced as a Dart-side constant set. promo_code_uses INSERT
--     happens only inside Edge Functions (razorpay-webhook, verify-payment)
--     using service_role.

BEGIN;

-- ──────────────────────────────────────────────────────────────────────
-- H-40: rank_ladder public-read policy
-- ──────────────────────────────────────────────────────────────────────

CREATE POLICY rank_ladder_public_read
  ON public.rank_ladder
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- Reference data, no user-specific filtering. Both anon (for marketing
-- pages or pre-auth roadmap previews) and authenticated (in-app rank
-- ladder UI) can read.

-- ──────────────────────────────────────────────────────────────────────
-- H-30: promo_code_uses INSERT scoped to service_role only
-- ──────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Service role can insert promo uses" ON public.promo_code_uses;

-- New policy: explicit `WITH CHECK (false)` blocks all RLS-bound roles.
-- service_role bypasses RLS unconditionally, so Edge Function inserts
-- (razorpay-webhook, verify-payment) keep working. authenticated users
-- and anon now cannot insert audit rows directly.
CREATE POLICY promo_code_uses_no_client_insert
  ON public.promo_code_uses
  FOR INSERT
  TO authenticated, anon
  WITH CHECK (false);

-- The existing `Users can see own promo uses` SELECT policy is unchanged.

COMMIT;
