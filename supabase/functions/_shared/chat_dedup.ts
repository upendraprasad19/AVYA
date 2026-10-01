/**
 * chat_dedup — what ai-proxy's 30-second same-message dedup may do with the
 * most recent matching `ai_coach_interactions` row.
 *
 * Hermes 2026-09-26, L29-F3. The dedup served ANY row with a non-empty
 * `ai_response` back as a 200 reply. When runToolLoop throws, ai-proxy closes
 * the reserved row with `ai_response: "[failed] runToolLoop threw"` and
 * `model_used: MODEL_USED_LOOP_THREW_SENTINEL`, then returns 502 — which the
 * client retries after 2 s (`SupabaseService.retryColdStart`), inside the
 * window. So the retry received the internal failure marker as the coach's
 * reply.
 *
 * A failed row now replays the FAILURE, not a reply. Re-running the message
 * instead would reserve a new row, and each reservation spends a unit of the
 * free tier's 10/day chat cap on the ledger, so the client's three retries
 * could spend three more units on one message. A pending reservation
 * (`ai_response` still "") is processed as before.
 */

export type DedupDecision = "process" | "replay_reply" | "replay_failure";

export interface DedupRow {
  ai_response?: unknown;
  model_used?: unknown;
}

export function dedupDecision(
  row: DedupRow | null | undefined,
  loopThrewSentinel: string,
): DedupDecision {
  if (!row) return "process";
  if (row.model_used === loopThrewSentinel) return "replay_failure";
  if (typeof row.ai_response === "string" && row.ai_response.length > 0) {
    return "replay_reply";
  }
  return "process";
}
