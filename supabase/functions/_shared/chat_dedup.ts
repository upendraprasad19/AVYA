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

// ─────────────────────────────────────────────────────────────────────────────
// OI-505 fix 4 (plan docs/plans/2026-11-13-coach-late-link-timeout-retry.md
// section 4, diagnose d9a3b5): a RETRY of a finished turn reuses it.
//
// The 30 s text dedup above does not reach a Retry tapped minutes later: the
// handler reserves a second row, and each reservation spends a unit of the
// daily chat cap (the cap trigger is BEFORE INSERT only). The phone sends the
// turn's `client_key` (OI-503) and, ONLY on its Retry button, `client_retry:
// true`. With both, ai-proxy first looks for a row of the SAME turn:
//   - a complete one is replayed (one reply body, no reservation, no unit);
//   - a young pending one means the first run is still working: 503
//     `in_progress`, no reservation (the client's cold-start retry asks again);
//   - anything else falls through to the existing dedup and processing.
// A new ask never carries the marker, so a deliberate repeat of the same words
// is never served a stale answer.
// ─────────────────────────────────────────────────────────────────────────────

/** A pending reservation younger than this means the first run is working. */
export const KEYED_PENDING_STALE_MS = 150_000;

/** An answer older than this is not replayed to a Retry (stale, round 3 F7). */
export const KEYED_MAX_REPLAY_AGE_MS = 6 * 60 * 60 * 1000;

/**
 * `tool_calls` statuses/names that mean the reply carried something a text-only
 * replay cannot give back (an APPLY card, a completion tile, legacy `[LOG...]`
 * tags the stored clean reply no longer carries): that turn is re-run.
 */
export const KEYED_UNREPLAYABLE_TOOL_STATUSES: readonly string[] = [
  "queued",
  "queued_for_user_confirmation",
  "tile_requested",
  "legacy_log_actions",
];

/** The marker ai-proxy appends to `tool_calls` when a reply had legacy log tags. */
export const LEGACY_LOG_ACTIONS_MARKER = "legacy_log_actions";

export interface KeyedRow extends DedupRow {
  id?: unknown;
  user_message?: unknown;
  tokens_used?: unknown;
  tool_calls?: unknown;
  created_at?: unknown;
}

export type KeyedVerdict =
  | { kind: "replay_reply"; row: KeyedRow }
  | { kind: "in_progress" }
  | { kind: "fall_through" };

function createdMs(row: KeyedRow): number | null {
  if (typeof row.created_at !== "string") return null;
  const ms = Date.parse(row.created_at);
  return Number.isFinite(ms) ? ms : null;
}

function carriesUnreplayableToolCall(toolCalls: unknown): boolean {
  // proactive-coach-promotion writes an OBJECT there; only an array is a log.
  if (!Array.isArray(toolCalls)) return false;
  return toolCalls.some((t) => {
    if (!t || typeof t !== "object") return false;
    const rec = t as { name?: unknown; status?: unknown };
    return (typeof rec.status === "string" &&
      KEYED_UNREPLAYABLE_TOOL_STATUSES.includes(rec.status)) ||
      rec.name === LEGACY_LOG_ACTIONS_MARKER;
  });
}

export function keyedReplayVerdict(
  rows: readonly KeyedRow[] | null | undefined,
  opts: {
    message: string;
    loopThrewSentinel: string;
    nowMs: number;
    pendingStaleMs?: number;
    maxReplayAgeMs?: number;
  },
): KeyedVerdict {
  if (!Array.isArray(rows) || rows.length === 0) return { kind: "fall_through" };
  const pendingStaleMs = opts.pendingStaleMs ?? KEYED_PENDING_STALE_MS;
  const maxAge = opts.maxReplayAgeMs ?? KEYED_MAX_REPLAY_AGE_MS;
  // Newest first, whatever order the caller's query used.
  const sameMessage = rows
    .filter((r) => r && r.user_message === opts.message)
    .map((r) => ({ r, ms: createdMs(r) }))
    .sort((a, b) => (b.ms ?? -Infinity) - (a.ms ?? -Infinity));

  for (const { r, ms } of sameMessage) {
    if (ms === null || opts.nowMs - ms > maxAge) continue;
    const text = r.ai_response;
    if (
      r.model_used !== "pending" && r.model_used !== opts.loopThrewSentinel &&
      typeof text === "string" && text.length > 0 &&
      !carriesUnreplayableToolCall(r.tool_calls)
    ) {
      return { kind: "replay_reply", row: r };
    }
  }
  for (const { r, ms } of sameMessage) {
    if (
      r.model_used === "pending" && ms !== null &&
      opts.nowMs - ms < pendingStaleMs
    ) {
      return { kind: "in_progress" };
    }
  }
  return { kind: "fall_through" };
}

/** What the handler does with the lookup: two `if`s, no logic of its own. */
export type KeyedReplay =
  | { kind: "replay"; row: KeyedRow }
  | {
    kind: "in_progress";
    status: 503;
    body: { error: "in_progress"; deduplicated: true };
  }
  | { kind: "none" };

export async function resolveKeyedReplay(args: {
  /** The request's `client_retry`, passed through as received: only `true` counts. */
  clientRetry: unknown;
  /** The SANITIZED `client_key` (null when absent or malformed). */
  clientKey: string | null;
  message: string;
  nowMs: number;
  loopThrewSentinel: string;
  /** `DISABLE_CLIENT_KEY_REPLAY` == "1": the old path verbatim. */
  killSwitch: boolean;
  /** Up to 5 rows of (user, key, channel app), newest first. Never required to be total. */
  fetchRows: (clientKey: string) => Promise<readonly KeyedRow[] | null | undefined>;
}): Promise<KeyedReplay> {
  if (args.killSwitch) return { kind: "none" };
  if (args.clientRetry !== true) return { kind: "none" };
  if (args.clientKey === null) return { kind: "none" };
  let rows: readonly KeyedRow[] | null | undefined;
  try {
    rows = await args.fetchRows(args.clientKey);
  } catch {
    // A failed lookup must never block chat: the old path runs.
    return { kind: "none" };
  }
  const verdict = keyedReplayVerdict(rows, {
    message: args.message,
    loopThrewSentinel: args.loopThrewSentinel,
    nowMs: args.nowMs,
  });
  if (verdict.kind === "replay_reply") return { kind: "replay", row: verdict.row };
  if (verdict.kind === "in_progress") {
    return {
      kind: "in_progress",
      status: 503,
      body: { error: "in_progress", deduplicated: true },
    };
  }
  return { kind: "none" };
}
