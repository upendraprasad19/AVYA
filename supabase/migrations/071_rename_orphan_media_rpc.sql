-- 071_rename_orphan_media_rpc.sql
-- OI-30 (audit-2026-05-17 Hermes F5)
--
-- Migration 070 (2026-05-17) created the `coach-media` bucket for
-- long-term consented retention (user explicitly saves a photo for
-- future coach reference). `chat-media` is the transient analysis
-- bucket with a 30-day TTL for free users.
--
-- The orphan-cleanup RPC + Edge Function were pointing at `coach-media`
-- — which would silently delete consented saves. Re-target both to
-- `chat-media`. The old RPC is dropped so any stale caller fails loudly.
--
-- clean-orphan-media Edge Function v5 → v6 ships in the same batch with
-- the new RPC name.

DROP FUNCTION IF EXISTS public.find_orphan_coach_media(TIMESTAMPTZ);

CREATE OR REPLACE FUNCTION public.find_orphan_chat_media(p_cutoff TIMESTAMPTZ)
RETURNS TABLE (user_id UUID, path TEXT)
LANGUAGE sql
STABLE
AS $$
  SELECT
    NULLIF((REGEXP_MATCH(o.name, '^([0-9a-f-]{36})/'))[1], '')::UUID AS user_id,
    o.name AS path
  FROM   storage.objects o
  WHERE  o.bucket_id = 'chat-media'
    AND  o.created_at < p_cutoff
    AND  EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = NULLIF((REGEXP_MATCH(o.name, '^([0-9a-f-]{36})/'))[1], '')::UUID
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.user_id = NULLIF((REGEXP_MATCH(o.name, '^([0-9a-f-]{36})/'))[1], '')::UUID
        AND s.status = 'active'
        AND s.end_date > NOW()
    );
$$;

GRANT EXECUTE ON FUNCTION public.find_orphan_chat_media TO service_role;
