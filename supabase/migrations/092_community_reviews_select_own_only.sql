-- 092_community_reviews_select_own_only.sql
-- Unit 2 (2026-06-13): tighten community_reviews SELECT from world-read to own-only.
--
-- Diagnose: community-review-rls-context. The pre-existing "Users can read all reviews"
-- policy (USING true) de-anonymized the vote graph — any authenticated user could read
-- every (reviewer_id, item_id, vote) row (who-reviewed-what). The only authenticated
-- readers filter to their own rows (submissions_repository.fetchAlreadyReviewedKeys →
-- .eq('reviewer_id', <self>)), so own-only SELECT breaks NO reader.
--
-- The two vote-tally consumers both BYPASS RLS and are unaffected:
--   * trigger trg_auto_approve_community -> auto_approve_community_item() (SECURITY DEFINER)
--   * promote-community-item Edge Function (service-role client)
--
-- INSERT ("Users can insert own review", WITH CHECK auth.uid()=reviewer_id) and UPDATE
-- ("Users can update own review") policies are intentionally LEFT UNTOUCHED -> voting works.
--
-- Deleted-user rows (reviewer_id NULL via migration 049 pseudonymization) become invisible
-- on the authenticated path but are still counted by both BYPASSRLS tallies (0 such rows
-- live at apply time). RLS is already ENABLED on community_reviews; this DROP+CREATE runs
-- inside the migration transaction (no window of total SELECT denial).

DROP POLICY IF EXISTS "Users can read all reviews" ON public.community_reviews;

CREATE POLICY "Users can read own reviews"
  ON public.community_reviews
  FOR SELECT
  USING (auth.uid() = reviewer_id);
