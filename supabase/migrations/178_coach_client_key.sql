-- Intent: OI-503 - add ai_coach_interactions.client_key (the phone's Hive key of a coach chat turn) with a format CHECK and a partial (user_id, client_key) index, so the server row and the phone row of one turn share one identity
-- Destructive?: no   -- adds one nullable column, one CHECK that NULL passes, and one index; no row is rewritten
-- Rollback strategy: inline
-- Linked diagnose-doc: d4a7c9

-- WHY. One coach turn showed twice after a restore (founder screenshot,
-- 2026-11-13). The phone keys its row by its own clock (coach_<ms>), the restore
-- keyed the server's copy by the server's created_at (another ms), and nothing tied
-- the two together. The phone now sends its key with every chat and photo turn
-- (ai-proxy, ai-media-proxy) and the server stores it here; the restore writes the
-- cloud row back AT that key, and the push looks a turn up by it.
-- Plan: docs/plans/2026-11-13-coach-chat-time-dup.md, section 4 (C1).
--
-- * Nullable, no backfill: every row written before this batch, server-originated
--   proactive rows and food-analysis rows carry no key and keep today's restore path.
-- * The CHECK mirrors the Edge Functions' sanitizeClientKey (_shared/client_key.ts).
--   The functions DROP a malformed key before the insert, so the CHECK never rejects
--   a chat turn; it guards the client's own orphan upsert, which applies the same
--   regex before sending the key.
-- * No trigger change: the three BEFORE INSERT rate-limit triggers and
--   trg_suppress_redundant_updates read no column list. RLS is row-level only, so
--   the client's own-row upsert may write the column.
-- * lock_timeout: a blocked ACCESS EXCLUSIVE lock aborts instead of queueing every
--   chat insert behind it (the OI-473 hang).

SET lock_timeout = '5s';

ALTER TABLE public.ai_coach_interactions
  ADD COLUMN IF NOT EXISTS client_key text NULL
    CONSTRAINT ai_coach_interactions_client_key_format
    CHECK (client_key IS NULL OR client_key ~ '^coach_[0-9]{10,16}$');

COMMENT ON COLUMN public.ai_coach_interactions.client_key IS
  'The phone''s Hive key (coach_<ms>) of this coach chat turn, sent by the client and '
  'stored by ai-proxy / ai-media-proxy (or the client''s orphan push). The restore '
  'writes the row back at this key so one turn is one local row. NULL = unkeyed '
  '(pre-OI-503 rows, server-originated rows, food analysis). OI-503.';

CREATE INDEX IF NOT EXISTS idx_ai_coach_interactions_user_client_key
  ON public.ai_coach_interactions (user_id, client_key)
  WHERE client_key IS NOT NULL;

RESET lock_timeout;

-- Rollback (inline). Run only after the Edge Functions that write client_key are
-- redeployed to their previous versions (a deployed function writing a dropped
-- column fails every chat insert):
-- DROP INDEX IF EXISTS public.idx_ai_coach_interactions_user_client_key;
-- ALTER TABLE public.ai_coach_interactions DROP COLUMN IF EXISTS client_key;
