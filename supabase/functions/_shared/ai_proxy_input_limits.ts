/**
 * ai_proxy_input_limits — the ONE owner of ai-proxy's request-size limits
 * (CLAUDE.md §4.4 rule 18: message 5K, snapshot 10K, on ALL AI endpoints).
 *
 * Before this module each branch checked its own fields, and the
 * `prediction` branch — which runs before the chat branch's checks — checked
 * none: a caller could send an unbounded `message` straight into Gemini
 * (single-owner audit 2026-09-26, P0 #5). Validating once, before any branch
 * runs, makes "which branch forgot" structurally impossible.
 *
 * The error strings are the ones each branch returned before, verbatim, so no
 * existing client sees a different message. Lengths only: type checks
 * ("'text' must be a string", "Missing 'message'") stay in their branches,
 * because they depend on which fields that branch requires.
 *
 * Each limit measures the text the prompt actually receives. The snapshot
 * reaches the system prompt through `sanitizeJsonForPrompt`, which re-escapes
 * every raw U+2028 / U+2029 / U+0085 as a six-character sequence, so the old
 * `JSON.stringify(...).length` check let a crafted snapshot pass at 9,998
 * characters and arrive at ~60,000 (Hermes 2026-09-26, L37-F2). For every
 * snapshot without those three characters the two lengths are identical.
 * `message` goes through `asPrincipalMessage`, which returns it unchanged.
 */

import { sanitizeJsonForPrompt } from "./sanitize_for_prompt.ts";

export const MAX_MESSAGE_CHARS = 5000;
export const MAX_TEXT_CHARS = 5000;
export const MAX_SNAPSHOT_CHARS = 10000;

export interface InputLimitViolation {
  status: 400;
  error: string;
}

/** Returns the first violated limit, or null when the body is within limits. */
export function validateAiProxyInput(
  body: Record<string, unknown>,
): InputLimitViolation | null {
  const { message, text, snapshot_json } = body;
  if (typeof message === "string" && message.length > MAX_MESSAGE_CHARS) {
    return { status: 400, error: "Message too long (max 5000 chars)" };
  }
  if (typeof text === "string" && text.length > MAX_TEXT_CHARS) {
    return {
      status: 400,
      error: "food_text_analysis: text too long (max 5000 chars)",
    };
  }
  if (
    snapshot_json &&
    sanitizeJsonForPrompt(snapshot_json).length > MAX_SNAPSHOT_CHARS
  ) {
    return { status: 400, error: "Snapshot too large" };
  }
  return null;
}
