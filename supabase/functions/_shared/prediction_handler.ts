/**
 * prediction_handler — ai-proxy `type: "prediction"` (the 12-week outcome
 * card generated at onboarding and on regenerate / the PRO 30-day refresh).
 *
 * Single-owner audit 2026-09-26, P0 #5. Before this module the branch:
 *   - took its SYSTEM prompt from the request body (`context.system_prompt`),
 *     so any signed-in caller could re-purpose the endpoint wholesale;
 *   - had no length limit (the chat branch's checks ran after it);
 *   - had no quota — every call was a Gemini call, unbounded.
 * The system prompt is now owned here and the caller's is ignored; lengths are
 * owned by `ai_proxy_input_limits.ts` (validated before any branch runs); the
 * daily quota is owned by the `usage_counters` ledger via `consume_quota`.
 *
 * What the cap counts: ATTEMPTS, not results. A unit is consumed before
 * Gemini runs (atomic — concurrent requests cannot overshoot) and is never
 * refunded. That is only safe because a failure here returns 500, which the
 * client does NOT auto-retry: `SupabaseService.retryColdStart` retries
 * 502/503/504 (and 500 only when a caller opts in with `retryOn500`, which
 * `AiService.predict()` does not). A 502 would be retried three more times,
 * each retry consuming a unit, so one Gemini outage would spend the whole
 * day's cap in one tap. Gateway cold starts, which the retries exist for,
 * fail BEFORE this handler runs and so never consume.
 *
 * Kill switch: `DISABLE_PREDICTION_QUOTA=true` in the Edge Function secrets
 * stops the metering without a redeploy, for a ledger that misbehaves and
 * refuses every caller. It skips the LEDGER only — the system prompt stays
 * server-owned either way, because restoring the caller's prompt would
 * re-open the P0. Read on every call, never at module load. The switch's name
 * and rule live in `prediction_quota_switch.ts` so the founder digest can say
 * "UNMETERED" without importing this module's Gemini dependency.
 */

import type { GeminiOptions, GeminiResult } from "./gemini.ts";
import { type GeminiAttemptStatus, labelForModel, MODEL_FLASH } from "./gemini.ts";
import { asPrincipalMessage } from "./sanitize_for_prompt.ts";
import { istDayStartIso } from "./ist_date.ts";
import { predictionQuotaDisabled } from "./prediction_quota_switch.ts";

export { predictionQuotaDisabled };

export const CONSUME_QUOTA_RPC = "consume_quota";

/** `usage_counters.quota_key` — not bare "prediction" (naming glossary: "prediction card"). */
export const PREDICTION_QUOTA_KEY = "prediction_daily";
export const PREDICTION_DAILY_CAP = 3;

/** Server-owned. Today's default, verbatim; the request's system_prompt is ignored. */
export const PREDICTION_SYSTEM_PROMPT =
  "You are a sports science expert making evidence-based fitness predictions. Be specific with numbers but realistic.";


/** Result of one consume attempt: the new count, -1 when the cap is reached, or an error. */
export interface ConsumeOutcome {
  used: unknown;
  error: unknown;
}

interface RpcCapable {
  rpc(
    fn: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: unknown }>;
}

/** The ONE `consume_quota` call for predictions (IST calendar day window). */
export async function consumePredictionQuota(
  supabase: RpcCapable,
  userId: string,
): Promise<ConsumeOutcome> {
  const windowStart = istDayStartIso();
  const { data, error } = await supabase.rpc(CONSUME_QUOTA_RPC, {
    p_user_id: userId,
    p_quota_key: PREDICTION_QUOTA_KEY,
    p_window_start: windowStart,
    p_limit: PREDICTION_DAILY_CAP,
  });
  return { used: data, error };
}

export interface PredictionDeps {
  consume: () => Promise<ConsumeOutcome>;
  /** Defaults to [predictionQuotaDisabled]; injectable for tests. */
  quotaDisabled?: () => boolean;
  geminiChat: (options: GeminiOptions) => Promise<GeminiResult>;
  reportExhaustion: (
    lastError: GeminiResult["lastError"],
    attemptStatuses?: GeminiAttemptStatus[],
  ) => Promise<void>;
}

export interface HandlerResult {
  status: number;
  body: Record<string, unknown>;
}

export async function handlePrediction(
  input: { message: unknown },
  deps: PredictionDeps,
): Promise<HandlerResult> {
  const { message } = input;
  if (!message || typeof message !== "string") {
    return { status: 400, body: { error: "Missing 'message' for prediction" } };
  }

  if ((deps.quotaDisabled ?? predictionQuotaDisabled)()) {
    console.warn(
      "[prediction] DISABLE_PREDICTION_QUOTA is set — no quota consumed",
    );
  } else {
    // Fail CLOSED on a ledger error: an unmetered Gemini call is exactly the
    // defect this module exists to remove.
    const { used, error } = await deps.consume();
    if (error || typeof used !== "number") {
      return {
        status: 500,
        body: { error: "Prediction temporarily unavailable" },
      };
    }
    if (used === -1) {
      return {
        status: 429,
        body: {
          error: `Daily prediction limit reached (${PREDICTION_DAILY_CAP}/day)`,
          code: "RATE_LIMITED",
        },
      };
    }
  }

  const { content, modelUsed, tokensUsed, lastError, attemptStatuses } = await deps.geminiChat({
    model: MODEL_FLASH,
    systemPrompt: PREDICTION_SYSTEM_PROMPT,
    userPrompt: asPrincipalMessage(message),
    maxTokens: 1024,
    temperature: 0.7,
    timeoutMs: 15_000,
    jsonMode: true,
    retries: 2, // f7a2c9 — no other retry on this path
  });

  if (!content) {
    // A5/OI-226 (f7a2c9): report exhaustion, same source as the 3 nutrition
    // sites, distinct endpoint. 500, not 502 — see the header.
    await deps.reportExhaustion(lastError ?? null, attemptStatuses);
    return { status: 500, body: { error: "AI temporarily unavailable" } };
  }

  return {
    status: 200,
    body: {
      reply: content,
      model_used: labelForModel(modelUsed),
      tokens_used: tokensUsed,
      actions: [],
    },
  };
}
