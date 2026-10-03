-- audit-2026-05-11 H-31 — schema-as-code for `community_reviews`.
--
-- Pre-fix: `community_reviews` existed on prod but had no migration
-- in source — created via the Supabase Dashboard SQL editor. A
-- fresh clone (or branch DB / fresh prod replacement) would have no
-- record of how to recreate the table, its constraints, RLS, or
-- the FK to `users(reviewer_id)`. Schema-as-code was broken for
-- this one table.
--
-- This migration codifies prod's current shape so the source is
-- authoritative. Every statement is idempotent (`IF NOT EXISTS` /
-- `DROP POLICY IF EXISTS` + `CREATE POLICY`) so it's a no-op on
-- prod and a clean install on any new database.

-- ── Table ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.community_reviews (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reviewer_id  UUID REFERENCES public.users(id) ON DELETE SET NULL,
  item_type    TEXT NOT NULL,
  item_id      UUID NOT NULL,
  vote         TEXT NOT NULL,
  created_at   TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT community_reviews_item_type_check
    CHECK (item_type = ANY (ARRAY['food'::text, 'exercise'::text])),
  CONSTRAINT community_reviews_vote_check
    CHECK (vote = ANY (ARRAY['approve'::text, 'reject'::text])),
  CONSTRAINT community_reviews_reviewer_id_item_type_item_id_key
    UNIQUE (reviewer_id, item_type, item_id)
);

-- ── RLS ──────────────────────────────────────────────────────
ALTER TABLE public.community_reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read all reviews" ON public.community_reviews;
CREATE POLICY "Users can read all reviews"
  ON public.community_reviews
  FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Users can insert own review" ON public.community_reviews;
CREATE POLICY "Users can insert own review"
  ON public.community_reviews
  FOR INSERT
  WITH CHECK (auth.uid() = reviewer_id);

DROP POLICY IF EXISTS "Users can update own review" ON public.community_reviews;
CREATE POLICY "Users can update own review"
  ON public.community_reviews
  FOR UPDATE
  USING (auth.uid() = reviewer_id)
  WITH CHECK (auth.uid() = reviewer_id);

COMMENT ON TABLE public.community_reviews IS
  'audit-2026-05-11 H-31 — schema codified from prod (was Dashboard-created with no source). One row per (reviewer, item_type, item_id). vote ∈ {approve, reject}.';
