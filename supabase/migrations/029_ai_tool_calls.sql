-- 029_ai_tool_calls.sql
-- Phase A.1 of AI Coach Tool-Calling plan.
--
-- Adds a per-turn record of Gemini function calls to ai_coach_interactions
-- and a flattening view (coach_tool_invocations_v) for analytics dashboards
-- (failure rate per tool, top tools by volume, latency p95).

-- Add tool_calls column
ALTER TABLE ai_coach_interactions
ADD COLUMN IF NOT EXISTS tool_calls JSONB;

COMMENT ON COLUMN ai_coach_interactions.tool_calls IS
'Per-turn record of Gemini function calls. Array of {name, status, args?, latency_ms?, error?}.';

-- Index for fast failure queries (used by ops dashboards)
CREATE INDEX IF NOT EXISTS idx_ai_coach_interactions_tool_calls_failed
ON ai_coach_interactions USING GIN (tool_calls)
WHERE tool_calls IS NOT NULL;

-- Flattening view: one row per tool call invocation
CREATE OR REPLACE VIEW coach_tool_invocations_v AS
SELECT
  i.id            AS interaction_id,
  i.user_id,
  i.created_at,
  i.model_used,
  call.value->>'name'                AS tool_name,
  call.value->>'status'              AS status,
  (call.value->>'latency_ms')::int   AS latency_ms,
  call.value->>'error'               AS error,
  call.value->'args'                 AS args
FROM ai_coach_interactions i,
     jsonb_array_elements(coalesce(i.tool_calls, '[]'::jsonb)) AS call
WHERE i.tool_calls IS NOT NULL;

COMMENT ON VIEW coach_tool_invocations_v IS
'Flattened per-tool-call view for analytics. Use to compute failure rates, top tools, latency p95.';

-- RLS: view inherits from underlying table; no separate policy needed
