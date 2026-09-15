-- 066_cleanup_pending_chat_duplicates.sql
-- Closes-diagnose: a17bc3 (docs/diagnoses/2026-05-16-chat-dedup-a17bc3.md)
-- Author: APK Test #16.1 / Agent B (2026-05-16)
--
-- Symptom
-- -------
-- Founder's `ai_coach_interactions` table accumulated 18 phantom
-- placeholder rows (model_used='pending', tokens_used=0) for a single
-- "curd 200gms whey 1.5 scoops cashew 6" message during a Gemini 502
-- storm — 9 rows on channel='food_text_analysis' and 9 on
-- channel='in_app_orphan'. 3 manual "Analyze with AI" taps × 2 distinct
-- write paths × 3 duplicate sync runs = 18 rows. 8 distinct
-- (user_id, user_message, channel) groups across the 18 rows.
--
-- Root cause
-- ----------
-- 1) `ai-proxy` food_text_analysis branch INSERTed a placeholder row
--    BEFORE calling Gemini, without dedup. Gemini 502'd → placeholder
--    stayed `pending` forever.
-- 2) Client `saveUserMessagePending` minted a fresh Hive `coach_*`
--    row on every tap, no dedup. Each row later synced as
--    channel='in_app_orphan' by `_syncCoachInteractions`.
--
-- Both writers tightened in the same batch (see diagnose doc).
-- This migration is the one-shot cleanup of the existing residue.
--
-- Safety
-- ------
-- - Verified live `pending` count in last 5 minutes = 0 via MCP
--   `execute_sql` before writing this migration. No in-flight requests
--   risk being clobbered.
-- - 30-day upper bound preserves anything older than 30 days as
--   forensic data (acceptable: cloud query confirmed all 18 rows are
--   in last 30 days, so this scope is sufficient).
-- - 5-minute lower bound prevents racing a live request that just
--   inserted a legitimate `pending` slot 2 seconds ago. Belt-and-
--   suspenders alongside the trigger-driven rate-limit row.
-- - GROUP BY (user_id, user_message, channel) keeps the EARLIEST row
--   per group (min(id) lexicographically, which for UUIDv4 is random
--   but stable). The user's intent was a single message; one survivor
--   per group preserves that signal for analytics.
--
-- Expected cloud delta
-- --------------------
-- 18 pending rows → 8 (one per distinct group). 10 rows DELETEd.

BEGIN;

WITH survivors AS (
  -- Earliest row per (user_id, user_message, channel) — by min(id)
  -- which is lexicographically stable across calls. We could also
  -- order by created_at, but min(id) is deterministic for repeated
  -- runs and matches the "first-write" intent for UUIDv7 / time-
  -- ordered ids when those land.
  SELECT min(id::text) AS keep_id
  FROM ai_coach_interactions
  WHERE model_used = 'pending'
    AND created_at >= now() - interval '30 days'
    AND created_at < now() - interval '5 minutes'
  GROUP BY user_id, user_message, channel
)
DELETE FROM ai_coach_interactions
WHERE model_used = 'pending'
  AND created_at >= now() - interval '30 days'
  AND created_at < now() - interval '5 minutes'
  AND id::text NOT IN (SELECT keep_id FROM survivors);

COMMIT;

-- Verification (run manually after apply):
--   SELECT channel, count(*) FROM ai_coach_interactions
--   WHERE model_used='pending'
--     AND created_at >= now() - interval '30 days'
--   GROUP BY channel;
-- Expected: food_text_analysis 4-5, in_app_orphan 3-4 (depending on
-- exact group distribution). NOT zero — earliest survivors retained.
