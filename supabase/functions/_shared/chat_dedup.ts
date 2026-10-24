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
 * daily chat cap (free 7 / PRO 20) on the ledger, so the client's three retries
 * could spend three more units on one message. A pending reservation
 * (`ai_response` still "") is processed as before.
 */

/**
 * The `ai_response` ai-proxy writes when runToolLoop THREW (the row also carries
 * the failure sentinel as `model_used`). ai-proxy writes the SAME literal inline
 * (kept verbatim there: the Dart parity test slices that catch block); a Deno
 * test pins that the two stay equal.
 */
export const LOOP_THREW_RESPONSE_MARKER = "[failed] runToolLoop threw";

/**
 * - `replay_failure`: the loop THREW — replay the 502 (never the marker text).
 * - `replay_hard_failure` (2026-10-01, a5c8e2): the loop RETURNED a hardcoded
 *   apology (`hadHardFailure`). The row carries the sentinel (so restore and the
 *   server memory readers skip it) but the ORIGINAL response was a delivered 200
 *   with `had_hard_failure`, so the dedup replays that same 200 — a 502 here
 *   would send the client's cold-start retry (2 s / 6 s / 12 s) into the same
 *   dedup hit for ~20 s before an error bubble.
 */
export type DedupDecision =
  | "process"
  | "replay_reply"
  | "replay_failure"
  | "replay_hard_failure";

export interface DedupRow {
  ai_response?: unknown;
  model_used?: unknown;
}

export function dedupDecision(
  row: DedupRow | null | undefined,
  loopThrewSentinel: string,
): DedupDecision {
  if (!row) return "process";
  if (row.model_used === loopThrewSentinel) {
    const text = row.ai_response;
    return typeof text === "string" && text.length > 0 &&
        text !== LOOP_THREW_RESPONSE_MARKER
      ? "replay_hard_failure"
      : "replay_failure";
  }
  if (typeof row.ai_response === "string" && row.ai_response.length > 0) {
    return "replay_reply";
  }
  return "process";
}
