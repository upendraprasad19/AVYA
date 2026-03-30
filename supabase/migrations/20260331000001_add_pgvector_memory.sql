-- ============================================================
-- Migration: pgvector + memory_embeddings
-- Enables semantic long-term memory for AI coach
-- Phase A: silent accumulation (free + PRO)
-- Phase B: PRO retrieval via match_memories()
-- ============================================================

-- Step 1: Enable pgvector extension
-- Supabase Postgres ships with pgvector; this activates it.
-- Schema-qualified to avoid search_path ambiguity.
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;

-- Step 2: Create the memory_embeddings table
CREATE TABLE memory_embeddings (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- Gemini text-embedding-004 produces exactly 768 dimensions
  embedding    extensions.vector(768) NOT NULL,

  -- Original text that was embedded — preserved for debugging + future re-embedding
  content      text        NOT NULL,

  -- 'conversation' | 'daily_summary' | 'coaching_note' | 'pattern_insight'
  source_type  text        NOT NULL,

  -- Flexible context: { date, model, channel, interaction_id, archived_by, ... }
  metadata     jsonb       NOT NULL DEFAULT '{}',

  created_at   timestamptz DEFAULT now()
);

-- Step 3: RLS — users can only see their own embeddings
ALTER TABLE memory_embeddings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "memory_embeddings_own"
  ON memory_embeddings
  FOR ALL
  USING (auth.uid() = user_id);

-- Step 4: B-tree index for user_id pre-filter
-- CRITICAL: always filter by user_id before the vector scan so IVFFlat only
-- scans ONE user's vectors rather than the entire table.
CREATE INDEX idx_memory_embeddings_user_id
  ON memory_embeddings(user_id);

-- Step 5: Composite index for chronological queries
CREATE INDEX idx_memory_embeddings_user_created
  ON memory_embeddings(user_id, created_at DESC);

-- Step 6: IVFFlat index for approximate nearest-neighbour cosine search
-- lists = 100: optimal for up to ~1M rows (pgvector recommends sqrt(rows)).
-- Rebuild with higher lists count when corpus exceeds 1M rows.
CREATE INDEX idx_memory_embeddings_ivfflat
  ON memory_embeddings
  USING ivfflat (embedding extensions.vector_cosine_ops)
  WITH (lists = 100);

-- Step 7: match_memories() — RPC function called by ai-proxy-pro
-- Accepts a query embedding, returns top-N semantically similar memories
-- for a specific user above a similarity threshold.
--
-- Usage from Edge Function:
--   supabaseClient.rpc('match_memories', {
--     p_user_id: userId,
--     p_query_embedding: queryEmbedding,   // number[] (768 floats)
--     p_match_count: 5,
--     p_similarity_threshold: 0.65,
--   })
CREATE OR REPLACE FUNCTION match_memories(
  p_user_id              uuid,
  p_query_embedding      extensions.vector(768),
  p_match_count          int     DEFAULT 5,
  p_similarity_threshold float   DEFAULT 0.65
)
RETURNS TABLE (
  id           uuid,
  content      text,
  source_type  text,
  metadata     jsonb,
  created_at   timestamptz,
  similarity   float
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    me.id,
    me.content,
    me.source_type,
    me.metadata,
    me.created_at,
    -- cosine similarity = 1 - cosine distance
    (1 - (me.embedding <=> p_query_embedding))::float AS similarity
  FROM memory_embeddings me
  WHERE
    me.user_id = p_user_id
    AND (1 - (me.embedding <=> p_query_embedding)) >= p_similarity_threshold
  -- ascending distance = descending similarity
  ORDER BY me.embedding <=> p_query_embedding
  LIMIT p_match_count;
END;
$$;

-- ============================================================
-- Verification queries (run after applying this migration):
--
--   SELECT extname FROM pg_extension WHERE extname = 'vector';
--   SELECT column_name, udt_name FROM information_schema.columns
--     WHERE table_name = 'memory_embeddings' ORDER BY ordinal_position;
--   SELECT proname FROM pg_proc WHERE proname = 'match_memories';
-- ============================================================
