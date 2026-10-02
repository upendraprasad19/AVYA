/**
 * Shared Google Gemini chat utility — text + vision.
 *
 * Added 2026-04-18 as part of the Gemini-only migration. Replaces the
 * OpenRouter cascade (`_shared/openrouter.ts`) that previously fronted
 * free-tier Gemma models + Cerebras-via-OpenRouter for PRO.
 *
 * Used by: ai-proxy, ai-media-proxy, assess-body-composition,
 *          daily-snapshot, rolling-context, morning-alert,
 *          future-prediction, weekly-report.
 *
 * Model matrix (stay in sync with docs/architecture/ai.md). Migrated to
 * Gemini 3.x on 2026-10-01: the new API key returns HTTP 404 for the retired
 * gemini-2.5-* slugs ("no longer available to new users"; 2.5-flash-lite was
 * probed, 2.5-flash and 2.5-pro were reported 404 by the founder). EVERY tier now runs
 * on ONE model, gemini-3.1-flash-lite (founder decision D2), and each tier keeps
 * its own constant below so a per-tier revert is a ONE-LINE change:
 *   MODEL_FLASH       — chat, structured JSON, food text, prediction
 *   MODEL_FLASH_LITE  — vision paths (scan_meal, cart_auditor, ai-media-proxy,
 *                       assess-body-composition)
 *   MODEL_PRO         — weekly-report (runs with `thinking: "on"`)
 *   MODEL_FALLBACK    — gemini-3.5-flash-lite, the second attempt for every call
 *
 * Fallback: on 5xx / 429 / empty-content / 404 from the primary model, retry
 * once against MODEL_FALLBACK. Because every tier shares one slug, the guard is
 * `model !== MODEL_FALLBACK` (NOT the old "primary is not Flash-Lite" test,
 * which with a shared slug would remove the fallback for every call). Pass
 * `fallbackToLite: false` to skip (the option NAME is kept: CI runs
 * `deno test --no-check`, so a rename would silently ignore stale call sites).
 *
 * Thinking is a per-call option (`thinking: "off" | "on"`, default off) and the
 * request config follows the ATTEMPT's model through THINKING_BY_MODEL —
 * the fallback attempt must never inherit the primary's config (3.5 rejects
 * the 2.5-era `thinkingBudget: 0` with HTTP 400; `thinkingLevel: "minimal"` is
 * accepted by both Lite models).
 *
 * Gemini 3 thought signatures: a functionCall part carries `thoughtSignature`
 * and a replayed model turn WITHOUT it is a 400. `geminiChatWithTools` therefore
 * returns the RAW parts Gemini sent (see `GeminiPart`) and the tool loop stores
 * them unchanged.
 *
 * Not retried: 4xx other than 429 (request is broken; retrying won't help; a 404
 * additionally prunes that model for the rest of the call) and explicit
 * quota-exceeded responses.
 */

import type { GeminiFunctionDeclaration } from "./tools/zodToGemini.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY")!;

const GEMINI_URL_TEMPLATE =
  "https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={KEY}";

/**
 * Strips GEMINI_API_KEY from a string before it can reach a log line, an
 * `alerts` row, or (via `reportGeminiExhaustion`) the founder's Telegram
 * digest — none of which are secret-safe destinations. Deno's `fetch`
 * rejects a network-level failure with a TypeError whose `.message` embeds
 * the full request URL, and our request URL carries the key as a `?key=...`
 * query param — the exact "Telegram token in a fetch error" shape this
 * repo's own CLAUDE.md already documents for `_shared/telegram.ts`, applied
 * here to a different secret (Hermes L40 F1, 2026-09-21).
 *
 * Applied at every point in this file where an exception or an upstream
 * response body becomes part of `lastError.message` / `reason` — not just
 * the one confirmed leak — because any of them can reach the same sink and
 * a fetch/URL implementation detail changing later must not reopen this.
 * Idempotent and cheap on a string that never contained the key.
 */
export function redactSecrets(input: string): string {
  let out = input;
  if (GEMINI_API_KEY) {
    out = out.split(GEMINI_API_KEY).join("[REDACTED]");
  }
  return out.replace(/([?&]key=)[^&\s"']+/gi, "$1[REDACTED]");
}

// Stable SKU names — colocated here so callers pick from a canonical list.
// One constant PER TIER (all the same string today — founder decision D2,
// 2026-10-01) so a per-tier revert is one line. Do NOT compare a model against
// one of these to infer "which tier is this" — with a shared slug the answer is
// always yes; use MODEL_FALLBACK and THINKING_BY_MODEL instead.
export const MODEL_FLASH = "gemini-3.1-flash-lite";
export const MODEL_FLASH_LITE = "gemini-3.1-flash-lite";
export const MODEL_PRO = "gemini-3.1-flash-lite";
/** Second attempt for every call (probe-proven on every request shape). */
export const MODEL_FALLBACK = "gemini-3.5-flash-lite";

/** Per-call thinking switch. Default "off". */
export type GeminiThinking = "off" | "on";

/**
 * Capability table: attempt-model slug -> thinkingConfig per mode.
 * `thinkingLevel: "minimal"` = off (0 thought tokens) and `"low"` = on (~135
 * thought tokens) are probe-proven on BOTH Lite models; `thinkingBudget: 0` is
 * accepted by 3.1 and REJECTED (HTTP 400) by 3.5, so it must never be sent.
 * A new MODEL_* slug needs a row here (pinned by gemini_thinking_config_test.ts, which iterates every exported MODEL_* constant).
 */
export const THINKING_BY_MODEL: Record<
  string,
  Record<GeminiThinking, Record<string, unknown>>
> = {
  "gemini-3.1-flash-lite": {
    off: { thinkingLevel: "minimal" },
    on: { thinkingLevel: "low" },
  },
  "gemini-3.5-flash-lite": {
    off: { thinkingLevel: "minimal" },
    on: { thinkingLevel: "low" },
  },
};

/**
 * thinkingConfig for ONE attempt. Unknown slug => null (send NO thinkingConfig,
 * warn, never throw: tests pass legacy slugs through the real function, and an
 * omitted config is the safe default on the Lite models — 0 thoughts).
 */
export function thinkingConfigFor(
  attemptModel: string,
  thinking: GeminiThinking,
): Record<string, unknown> | null {
  const row = THINKING_BY_MODEL[attemptModel];
  if (!row) {
    console.warn(
      `[gemini] no thinking capability row for model=${attemptModel}; sending no thinkingConfig`,
    );
    return null;
  }
  return row[thinking];
}

/** Human label for a model slug (the value stored in ai_coach_interactions.model_used). */
export function labelForModel(modelUsed: string | null | undefined): string {
  switch (modelUsed) {
    case "gemini-3.1-flash-lite":
      return "Gemini 3.1 Flash Lite";
    case "gemini-3.5-flash-lite":
      return "Gemini 3.5 Flash Lite";
    default:
      return modelUsed && modelUsed.length > 0 ? modelUsed : "Gemini";
  }
}

/** One attempt's outcome, for classification (404 = model unavailable). */
export interface GeminiAttemptStatus {
  model: string;
  status: number | null;
}

/**
 * `finishReason`s that are a deterministic content decision: a second model or a
 * retry gives the same answer, so they must not burn retry passes.
 */
const DETERMINISTIC_FINISH_REASONS = new Set([
  "SAFETY",
  "RECITATION",
  "PROHIBITED_CONTENT",
  "BLOCKLIST",
  "SPII",
  // Image-input blocks (scan_meal / cart_auditor): the same image gets the same answer.
  "IMAGE_SAFETY",
  "IMAGE_PROHIBITED_CONTENT",
  "IMAGE_OTHER",
  "NO_IMAGE",
]);

/**
 * `finishReason`s that a retry MAY fix (so they keep their retry passes) but that the
 * USER's own request produced, so they must never earn a quota refund: our output cap was
 * too small for their ask, the language is unsupported, or the model emitted a malformed call.
 */
const NON_REFUNDABLE_RETRIABLE_FINISH_REASONS = new Set([
  "MAX_TOKENS",
  "LANGUAGE",
  "MALFORMED_FUNCTION_CALL",
]);

/**
 * Classify a 200-OK Gemini body that produced no usable reply. `promptFeedback.blockReason`
 * (the most common user-input block: HTTP 200, NO `candidates`) is a content block exactly like
 * a SAFETY finishReason. `deterministic` = a retry/second model gets the same answer (do not
 * burn passes); `blocked` = never refund (deterministic OR user-caused).
 */
export function classifyNoReply(
  finishReason: string | null | undefined,
  blockReason?: string | null,
): { finishReason: string; deterministic: boolean; blocked: boolean } {
  if (blockReason) {
    return { finishReason: `blocked:${blockReason}`, deterministic: true, blocked: true };
  }
  const fr = finishReason ?? "unknown";
  const deterministic = DETERMINISTIC_FINISH_REASONS.has(fr);
  return {
    finishReason: fr,
    deterministic,
    blocked: deterministic || NON_REFUNDABLE_RETRIABLE_FINISH_REASONS.has(fr),
  };
}

/** True for the Gemini "model does not exist for this key" shape (HTTP 404). */
export function isModelUnavailableStatus(status: number | null | undefined): boolean {
  return status === 404;
}

/**
 * Part B (gemini3-limits-caching): may a failed Gemini turn give its quota unit
 * back? ONLY a transport-class failure qualifies, the kind the user cannot cause
 * and a retry would plausibly fix: no HTTP status (timeout / empty candidate /
 * network), 404 (model gone for this key), 408/425/429 and 5xx.
 *
 * Our own credential failing is ALSO ours, not the user's: 401, 403, and the HTTP 400
 * Gemini returns for a revoked/invalid key (`API_KEY_INVALID`) refund.
 *
 * Never refundable: a content block seen on ANY attempt (`blockSeen`: SAFETY-class
 * finishReasons incl. image blocks, a `promptFeedback.blockReason`, or a user-caused
 * MAX_TOKENS / LANGUAGE / MALFORMED_FUNCTION_CALL) even if a later fallback attempt failed
 * for a transport reason (the fallback must not launder the block); any other 4xx (a
 * request the caller built); and an UNKNOWN failure (`failure` null/undefined: no
 * evidence). Pure; the SQL side (`refund_quota`) enforces the latch + budget.
 */
export function refundableFailure(
  failure:
    | {
      status?: number | null;
      message?: string | null;
      deterministicFailure?: boolean;
      blockSeen?: boolean;
    }
    | null
    | undefined,
): boolean {
  if (!failure) return false;
  if (failure.deterministicFailure === true || failure.blockSeen === true) return false;
  const status = failure.status ?? null;
  if (status === null) return true;
  if (status === 400) {
    return /API_KEY_INVALID|API key (not valid|expired)/i.test(failure.message ?? "");
  }
  return status === 401 || status === 403 || status === 404 || status === 408 ||
    status === 425 || status === 429 || status >= 500;
}

/** Log the cached/thought token counts per call (console only; absent fields = 0). */
function logUsage(label: string, model: string, usage: unknown): void {
  const u = (usage ?? {}) as Record<string, unknown>;
  const num = (v: unknown) => (typeof v === "number" ? v : 0);
  console.log(
    `[gemini] usage ${label} model=${model} prompt=${num(u.promptTokenCount)} ` +
      `out=${num(u.candidatesTokenCount)} cached=${num(u.cachedContentTokenCount)} ` +
      `thoughts=${num(u.thoughtsTokenCount)} total=${num(u.totalTokenCount)}`,
  );
}

export interface GeminiOptions {
  /** SKU name — use the MODEL_* constants above. */
  model: string;
  /** System prompt (goes into `systemInstruction`). */
  systemPrompt: string;
  /** User prompt (text portion). */
  userPrompt: string;
  /** Max output tokens. */
  maxTokens: number;
  /** Default 0.7. Gemini tolerates up to 2.0. */
  temperature?: number;
  /** Per-call request timeout in ms. Default 30 s (Gemini Pro can be slow). */
  timeoutMs?: number;
  /** Optional base64 image for vision input (Flash-Lite supports). */
  imageBase64?: string;
  /** MIME type of the image (default image/jpeg). */
  imageMimeType?: string;
  /** Request structured JSON output (sets responseMimeType). */
  jsonMode?: boolean;
  /**
   * On 5xx / 429 / empty content / 404, retry once against MODEL_FALLBACK.
   * Default true. Pass false only when a second model genuinely adds nothing
   * (no call site does today). The option NAME is historical and kept on purpose.
   */
  fallbackToLite?: boolean;
  /**
   * "off" (default) or "on". Resolved PER ATTEMPT through THINKING_BY_MODEL —
   * thinking tokens count against `maxTokens`, so an "on" caller must size it.
   */
  thinking?: GeminiThinking;
  /**
   * FC3 (diagnose 7fbe21): EXTRA passes over the whole [primary, MODEL_FALLBACK]
   * attempt list on a null (transient empty / quota) result, each spaced by a
   * short backoff. Default 0 = current single-pass behavior. Opt in ONLY where
   * a one-shot empty is user-visible (e.g. parseFoodText) — the tool loop has
   * its own retry; the ~17 other geminiChat callers keep 0 (no latency/quota
   * regression for the cron generators).
   */
  retries?: number;
}

export interface GeminiResult {
  /** Trimmed text content. null if every attempt failed. */
  content: string | null;
  /** The model slug that produced `content`. null on total failure. */
  modelUsed: string | null;
  /** Approximate token usage — totalTokenCount from Gemini's usageMetadata. */
  tokensUsed: number;
  /**
   * Present only when content is null: the LAST attempt's raw failure,
   * for server-side classification/alerting (obs 6, 2026-09-20). Never
   * surfaced to the client — callers pass this to reportGeminiExhaustion,
   * never into an HTTP response body.
   */
  lastError?: { status: number | null; message: string } | null;
  /**
   * Present only when content is null: EVERY attempt's HTTP status (not just the
   * last). A retired primary (404) followed by a transient fallback failure must
   * still classify as `model_unavailable`. A side field — `lastError` stays
   * `{status, message}` (tests deep-equal it).
   */
  attemptStatuses?: GeminiAttemptStatus[];
  /**
   * True when this failure is a deterministic content block (SAFETY etc.): the
   * retry loop does not spend extra passes on it. A side field for the same reason
   * as `attemptStatuses`.
   */
  deterministicFailure?: boolean;
  /**
   * True when ANY attempt (any model, any pass) hit a content block or a user-caused
   * no-reply (classifyNoReply.blocked). Sticky, unlike `deterministicFailure` (which is the LAST
   * failure's): the refund decision must not let a transport failure on the fallback launder a
   * block on the primary.
   */
  blockSeen?: boolean;
}

/**
 * Single-request call to Gemini. Handles:
 *   - System-instruction translation from OpenAI-style roles
 *   - Optional inline-data image (Gemini's `inline_data` part)
 *   - JSON mode via `responseMimeType: application/json`
 *   - Primary → MODEL_FALLBACK on retriable errors (and 404, which also prunes the model)
 */
export async function geminiChat(options: GeminiOptions): Promise<GeminiResult> {
  const {
    model,
    systemPrompt,
    userPrompt,
    maxTokens,
    temperature = 0.7,
    timeoutMs = 30_000,
    imageBase64,
    imageMimeType = "image/jpeg",
    jsonMode = false,
    fallbackToLite = true,
    thinking = "off",
    retries = 0,
  } = options;

  if (!GEMINI_API_KEY) {
    console.error("[geminiChat] GEMINI_API_KEY not configured");
    return {
      content: null,
      modelUsed: null,
      tokensUsed: 0,
      lastError: { status: null, message: "GEMINI_API_KEY not configured" },
    };
  }

  // Try primary, then (optionally) MODEL_FALLBACK. Never chain fallback → fallback.
  // The guard is `model !== MODEL_FALLBACK`: every tier shares one slug today, so
  // the old "primary is not Flash-Lite" test would drop the fallback for every call.
  let attempts: string[] = [model];
  if (fallbackToLite && model !== MODEL_FALLBACK) {
    attempts.push(MODEL_FALLBACK);
  }

  // FC3 (diagnose 7fbe21): optional EXTRA passes over the attempt list on a
  // transient null, spaced by a short backoff. retries=0 → single pass (the
  // default for every caller except parseFoodText).
  //
  // B-pass P2: bound total retry latency. One pass can spend timeoutMs ×
  // attempts (~30s for the food parser); without a wall-clock deadline,
  // retries=2 could stack to ~90s on the meal-log write path during a genuine
  // Gemini outage. Cap it (mirrors geminiChatWithTools' TOOLS_RETRY_DEADLINE_MS):
  // fast transient failures still get their retries; a slow outage stops after
  // roughly one full attempt list.
  const retryStartedAt = Date.now();
  const retryDeadlineMs = 20_000;
  let lastFailure: GeminiResult | null = null;
  const attemptStatuses: GeminiAttemptStatus[] = [];
  let blockSeen = false;
  for (let pass = 0; pass <= retries; pass++) {
    // Retry only if SOME attempt this pass failed transiently (no HTTP status =
    // timeout/empty/transport, 429, 5xx). A pass whose every failure was a
    // non-429 4xx (400/403/404) cannot be fixed by waiting.
    let passHadTransientFailure = false;
    // Snapshot: a 404 reassigns `attempts` mid-pass; the index below stays valid.
    const passAttempts = attempts;
    for (const [attemptIdx, attemptModel] of passAttempts.entries()) {
      const result = await _callOnce({
        model: attemptModel,
        systemPrompt,
        userPrompt,
        maxTokens,
        temperature,
        timeoutMs,
        imageBase64,
        imageMimeType,
        jsonMode,
        thinking,
      });

      if (result.content !== null) {
        // Success on the first attempt is the common path; log the
        // fallback / retry case so we can monitor primary health in prod.
        if (attemptModel !== model || pass > 0) {
          console.warn(
            `[geminiChat] recovered (${model} → ${attemptModel}, pass ${pass})`,
          );
        }
        return result;
      }
      lastFailure = result;
      if (result.blockSeen === true) blockSeen = true;
      const status = result.lastError?.status ?? null;
      attemptStatuses.push({ model: attemptModel, status });
      if (isModelUnavailableStatus(status)) {
        // Retired / unknown model: never try it again within this call.
        console.warn(`[gemini] MODEL_UNAVAILABLE model=${attemptModel}`);
        attempts = attempts.filter((m) => m !== attemptModel);
      } else if (
        !result.deterministicFailure &&
        // no HTTP status (timeout / empty / transport), 408/425/429, 5xx
        (status === null || status === 408 || status === 425 || status === 429 ||
          status >= 500)
      ) {
        passHadTransientFailure = true;
      }
      console.warn(
        `[geminiChat] ${attemptModel} returned null — ${attemptIdx < passAttempts.length - 1 ? "trying fallback" : "attempt list exhausted"}`,
      );
    }
    // Space the next pass so a transient quota/empty blip can clear — but only
    // if we're still inside the retry wall-clock budget (B-pass P2).
    if (pass >= retries) break;
    // `attempts.length === 0` is defensive: a pass can only be transient if some
    // model it tried survived the prune, so it cannot decide alone today.
    if (attempts.length === 0 || !passHadTransientFailure) break;
    if (Date.now() - retryStartedAt >= retryDeadlineMs) {
      console.warn(
        `[geminiChat] retry budget (${retryDeadlineMs}ms) exhausted for primary=${model}`,
      );
      break;
    }
    await new Promise((r) => setTimeout(r, 700));
  }

  console.error(
    `[geminiChat] All attempts failed for primary=${model} (retries=${retries})`,
  );
  return {
    content: null,
    modelUsed: null,
    tokensUsed: 0,
    lastError: lastFailure?.lastError ?? null,
    attemptStatuses,
    deterministicFailure: lastFailure?.deterministicFailure ?? false,
    blockSeen,
  };
}

// ── Private: single HTTP call to Gemini. Returns null on any failure. ──
async function _callOnce(opts: {
  model: string;
  systemPrompt: string;
  userPrompt: string;
  maxTokens: number;
  temperature: number;
  timeoutMs: number;
  imageBase64?: string;
  imageMimeType: string;
  jsonMode: boolean;
  thinking: GeminiThinking;
}): Promise<GeminiResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs);

  try {
    const url = GEMINI_URL_TEMPLATE
      .replace("{MODEL}", opts.model)
      .replace("{KEY}", GEMINI_API_KEY);

    // Build user parts — text first, then inline_data for the image if present.
    const userParts: unknown[] = [{ text: opts.userPrompt }];
    if (opts.imageBase64) {
      userParts.push({
        inline_data: {
          mime_type: opts.imageMimeType,
          data: opts.imageBase64,
        },
      });
    }

    const body: Record<string, unknown> = {
      systemInstruction: {
        parts: [{ text: opts.systemPrompt }],
      },
      contents: [
        {
          role: "user",
          parts: userParts,
        },
      ],
      generationConfig: {
        temperature: opts.temperature,
        maxOutputTokens: opts.maxTokens,
      },
    };

    if (opts.jsonMode) {
      (body.generationConfig as Record<string, unknown>).responseMimeType =
        "application/json";
    }

    // Thinking config follows the ATTEMPT model (diagnose 7fbe21 FC1 history:
    // thinking tokens count against maxOutputTokens, so an uncontrolled default
    // can return an EMPTY candidate at our low caps). `minimal` = off,
    // `low` = on; `thinkingBudget: 0` is NOT used — 3.5 rejects it with HTTP 400.
    const thinkingConfig = thinkingConfigFor(opts.model, opts.thinking);
    if (thinkingConfig) {
      (body.generationConfig as Record<string, unknown>).thinkingConfig =
        thinkingConfig;
    }

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });

    clearTimeout(timer);

    // Retriable statuses: 429 (rate-limited), 500/502/503/504 (server).
    // Non-retriable 4xx (incl. 404 = model unavailable) returns null immediately —
    // the caller logs, prunes a 404'd model and moves on.
    if (!response.ok) {
      const status = response.status;
      let preview = "";
      try {
        // Redact BEFORE truncating — a key straddling the 200-char cut
        // would survive un-redacted if sliced first (B-pass F2, 2026-09-21).
        preview = redactSecrets(await response.text()).slice(0, 200);
      } catch (_) { /* body read may also fail */ }
      const safePreview = preview;
      console.warn(
        `[geminiChat] ${opts.model} HTTP ${status}: ${safePreview}`,
      );
      return {
        content: null,
        modelUsed: null,
        tokensUsed: 0,
        lastError: { status, message: safePreview || `HTTP ${status}` },
      };
    }

    const data = await response.json();
    const candidate = data.candidates?.[0];

    // Safety-filter blocks or missing candidate: treat as failure.
    if (!candidate || !candidate.content?.parts) {
      const cls = classifyNoReply(candidate?.finishReason, data.promptFeedback?.blockReason);
      const finishReason = cls.finishReason;
      console.warn(
        `[geminiChat] ${opts.model} no candidate (finishReason=${finishReason})`,
      );
      return {
        content: null,
        modelUsed: null,
        tokensUsed: 0,
        lastError: { status: null, message: `no candidate (finishReason=${finishReason})` },
        deterministicFailure: cls.deterministic,
        blockSeen: cls.blocked,
      };
    }

    // Stitch multi-part responses into one string.
    const text = (candidate.content.parts as Array<{ text?: string }>)
      .map((p) => p.text ?? "")
      .join("")
      .trim();

    if (!text) {
      // An empty candidate can still carry a block finishReason (SAFETY with `parts: []`).
      const cls = classifyNoReply(candidate.finishReason, data.promptFeedback?.blockReason);
      return {
        content: null,
        modelUsed: null,
        tokensUsed: 0,
        lastError: { status: null, message: "empty text in candidate" },
        deterministicFailure: cls.deterministic,
        blockSeen: cls.blocked,
      };
    }

    const tokensUsed = data.usageMetadata?.totalTokenCount ?? 0;
    logUsage("single", opts.model, data.usageMetadata);

    return {
      content: text,
      modelUsed: opts.model,
      tokensUsed,
    };
  } catch (err) {
    clearTimeout(timer);
    let message: string;
    if (err instanceof DOMException && err.name === "AbortError") {
      message = `timed out after ${opts.timeoutMs}ms`;
      console.warn(`[geminiChat] ${opts.model} ${message}`);
    } else {
      message = `threw: ${redactSecrets(String(err)).slice(0, 200)}`;
      console.warn(`[geminiChat] ${opts.model} ${message}`);
    }
    return {
      content: null,
      modelUsed: null,
      tokensUsed: 0,
      lastError: { status: null, message },
    };
  }
}

// ─────────────────────────────────────────────────────────────────────
// Multi-turn function-calling variant (added 2026-04-19, Phase A.3)
// ─────────────────────────────────────────────────────────────────────

/**
 * A single Content entry in a Gemini multi-turn conversation.
 * See https://ai.google.dev/api/rest/v1beta/Content.
 *
 * The `function` role is used to feed tool results back to the model
 * so it can compose its next turn.
 */
export interface GeminiContent {
  role: "user" | "model" | "function";
  parts: GeminiPart[];
}

/**
 * A single part inside a Content entry. A response candidate may contain a
 * mix of `text` and `functionCall` parts in the same turn — callers must
 * handle both. The `inline_data` variant is for vision input (mirrors the
 * single-turn helper).
 */
export type GeminiPart =
  | { text: string; thoughtSignature?: string }
  | {
    functionCall: { name: string; args: Record<string, unknown> };
    /**
     * Gemini 3: the signature rides on the part, beside `functionCall`. A
     * replayed model turn whose functionCall part lacks it is an HTTP 400
     * ("Function call is missing a thought_signature"). Echo it RAW.
     */
    thoughtSignature?: string;
  }
  | { functionResponse: { name: string; response: Record<string, unknown> } }
  | { inline_data: { mime_type: string; data: string } }
  | { thoughtSignature: string };

/** Documented Google value that bypasses signature validation (probe: 200 on 3.1 + 3.5). */
export const DUMMY_THOUGHT_SIGNATURE = "skip_thought_signature_validator";

/**
 * Defensive fill for a model turn about to be stored/replayed: ONLY the FIRST
 * functionCall part, ONLY when NO part in the turn carries a signature
 * (parallel calls carry a single signature on the first call; the dummy is
 * probe-proven for a single call). Returns a NEW array; never mutates input.
 */
export function fillMissingThoughtSignature(
  parts: GeminiPart[],
  opts: { force?: boolean } = {},
): GeminiPart[] {
  const hasSig = (p: GeminiPart) =>
    typeof (p as { thoughtSignature?: unknown }).thoughtSignature === "string";
  // Default: act only when NO part in the turn carries a signature (so a turn
  // that already has one is returned UNCHANGED, same reference). `force` (the
  // 400 safety net only) puts the dummy on the first functionCall that itself
  // lacks a signature even when a text part carries one — a turn Google just
  // rejected is already known to be missing something.
  if (!opts.force && parts.some(hasSig)) return parts;
  const idx = parts.findIndex((p) => "functionCall" in p && !hasSig(p));
  if (idx < 0) return parts;
  const out = parts.slice();
  out[idx] = {
    ...(out[idx] as { functionCall: { name: string; args: Record<string, unknown> } }),
    thoughtSignature: DUMMY_THOUGHT_SIGNATURE,
  };
  return out;
}

/** Apply {@link fillMissingThoughtSignature} to every model turn of a history. */
export function fillMissingThoughtSignaturesInHistory(
  messages: GeminiContent[],
  opts: { force?: boolean } = {},
): GeminiContent[] {
  let changed = false;
  const out = messages.map((m) => {
    if (m.role !== "model") return m;
    const parts = fillMissingThoughtSignature(m.parts, opts);
    if (parts === m.parts) return m;
    changed = true;
    return { ...m, parts };
  });
  // Same reference when nothing needed filling: lets a caller tell "retry with
  // dummies" from "an identical request would be re-sent".
  return changed ? out : messages;
}

export interface GeminiToolsOptions {
  /** SKU name — use the MODEL_* constants. */
  model: string;
  /** System instruction (single text block — same shape as single-turn helper). */
  systemPrompt: string;
  /**
   * Multi-turn conversation history. Caller owns this array and is responsible
   * for appending the model's last turn + the corresponding `function`-role
   * tool responses between rounds.
   */
  messages: GeminiContent[];
  /**
   * Function declarations the model may call. Empty array disables tool calling
   * (in which case `toolConfig` is also omitted from the request body).
   */
  tools: GeminiFunctionDeclaration[];
  /** Default 0.7 (matches single-turn helper). */
  temperature?: number;
  /** Default 1024. */
  maxTokens?: number;
  /**
   * Per-call request timeout in ms. Default 25_000ms — multi-round loops
   * stack these, so we keep each single round tighter than `geminiChat`'s 30s.
   */
  timeoutMs?: number;
  /** Default true. On 5xx / 429 / empty content / 404, retry once on MODEL_FALLBACK. */
  fallbackToLite?: boolean;
  /** "off" (default) | "on"; resolved per attempt via THINKING_BY_MODEL. */
  thinking?: GeminiThinking;
  /** Optional correlation ID — surfaced in log lines for cross-referencing. */
  requestId?: string;
}

export interface GeminiToolsResult {
  /**
   * Concatenated text from all `text` parts in the model's response.
   * May be empty if the model's response consisted only of function calls.
   */
  text: string;
  /**
   * Function calls the model wants to make this round. Empty array if the
   * model produced only text (terminal response).
   */
  functionCalls: Array<{ name: string; args: Record<string, unknown> }>;
  /**
   * Raw parts of the model's response — caller appends these back to the
   * conversation history (as a `model`-role content) before the next round.
   */
  parts: GeminiPart[];
  /**
   * Model that ultimately produced this response. Equal to `opts.model` on
   * the happy path; `MODEL_FALLBACK` if the fallback path fired.
   */
  modelUsed: string;
  /** Total tokens (input + output) per Gemini's usageMetadata. 0 on failure. */
  tokensUsed: number;
  /** True iff this response came from the fallback model. */
  usedFallback: boolean;
}

// ── Backoff-retry tuning for the tool-calling path (diagnose d4f1c2) ──
// A transient Gemini blip (HTTP 429 / 5xx / empty-candidate) hits the shared
// project quota, so the [Flash → Flash-Lite] attempt list can fail back-to-back
// in ~1-2s. Without time spacing the loop gives up immediately and the caller
// (runToolLoop) surfaces "I had trouble reaching the model" — the exact coach
// flakiness diagnose d4f1c2 found live. We re-run the whole attempt list up to
// TOOLS_MAX_PASSES times, sleeping TOOLS_PASS_BACKOFF_MS between passes, but
// ONLY while the last failure was retriable (429/5xx/empty — NOT a 25s timeout
// that already spent the round's budget, and NOT a 4xx a different attempt
// can't fix) AND we're still inside the wall-clock budget. Worst-case added
// latency on fast transient failures is one extra pass (~2 calls + one sleep).
const TOOLS_MAX_PASSES = 2;
const TOOLS_PASS_BACKOFF_MS = 700;
const TOOLS_RETRY_DEADLINE_MS = 20_000;

function _sleepMs(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Multi-turn Gemini call with function-calling support.
 *
 * Caller owns the messages array across rounds — this helper does NOT
 * mutate it. Append the model's response (`role: "model", parts: result.parts`)
 * AND the function-response turns (`role: "user", parts: [...]`) before
 * the next call. Note the role is "user" — the live Gemini REST API rejects
 * `role: "function"` even though some older spec drafts referenced it.
 *
 * Resilience (diagnose d4f1c2): each pass tries the primary model then (if
 * `fallbackToLite`) `MODEL_FALLBACK`. On a RETRIABLE failure of the whole
 * pass (429 / 5xx / empty content) it sleeps a short backoff and retries the
 * pass, bounded by TOOLS_MAX_PASSES and a wall-clock deadline. Timeouts and
 * non-429 4xx are treated as non-retriable (another attempt won't help / has
 * no budget). Throws only after every bounded attempt fails, so the caller can
 * surface a user-visible apology.
 */
export async function geminiChatWithTools(
  opts: GeminiToolsOptions,
): Promise<GeminiToolsResult> {
  const {
    model,
    systemPrompt,
    messages,
    tools,
    temperature = 0.7,
    maxTokens = 1024,
    timeoutMs = 25_000,
    fallbackToLite = true,
    thinking = "off",
    requestId,
  } = opts;

  if (!GEMINI_API_KEY) {
    console.error(
      `[geminiChatWithTools] GEMINI_API_KEY not configured request_id=${requestId ?? "n/a"}`,
    );
    throw new Error("GEMINI_API_KEY not configured");
  }

  // Guard is `model !== MODEL_FALLBACK` (see the header): a shared tier slug
  // must not remove the fallback.
  let attempts: string[] = [model];
  if (fallbackToLite && model !== MODEL_FALLBACK) {
    attempts.push(MODEL_FALLBACK);
  }

  const startedAt = Date.now();
  let lastError: unknown = null;
  let lastReason = "";
  let lastStatus: number | null = null;
  let lastDeterministic = false;
  let blockSeen = false;
  const attemptStatuses: GeminiAttemptStatus[] = [];
  // Once an attempt 400s on a missing thought signature we replay the dummy-filled
  // history for every LATER attempt/pass of this call too (re-sending the raw
  // history would just 400 again). null = the raw history is still in use.
  let dummyHistory: GeminiContent[] | null = null;

  for (let pass = 0; pass < TOOLS_MAX_PASSES; pass++) {
    // Per-ATTEMPT retriability: a primary 429 followed by a fallback 404 must
    // still retry the (healthy-but-throttled) primary. Keying on the LAST
    // attempt only (the old `lastRetriable`) aborted that retry.
    let passHadRetriableFailure = false;
    // `attempts` is reassigned (never mutated) on a 404, so iterating it directly
    // is already a snapshot.
    for (const attemptModel of attempts) {
      const callArgs = {
        model: attemptModel,
        systemPrompt,
        messages: dummyHistory ?? messages,
        tools,
        temperature,
        maxTokens,
        timeoutMs,
        thinking,
        requestId,
      };
      let result = await _callOnceWithTools(callArgs);

      // Safety net (A2): cross-model replay under `minimal` is unproven. If any
      // attempt (primary included) 400s on a missing thought signature, fill the
      // documented dummy (forced, see fillMissingThoughtSignature) and retry THAT
      // attempt once; the dummy history is then kept for the rest of the call.
      // Skipped when the fill would change nothing (an identical re-send) or the
      // dummy history was already the one that 400'd.
      if (!result.ok && result.status === 400 && result.signatureMissing && dummyHistory === null) {
        const filled = fillMissingThoughtSignaturesInHistory(messages, { force: true });
        if (filled !== messages) {
          console.warn(
            `[geminiChatWithTools] ${attemptModel} 400 thought_signature — retrying once with dummy signatures request_id=${requestId ?? "n/a"}`,
          );
          dummyHistory = filled;
          result = await _callOnceWithTools({ ...callArgs, messages: filled });
        }
      }

      if (result.ok) {
        const usedFallback = attemptModel !== model;
        if (usedFallback) {
          console.warn(
            `[geminiChatWithTools] fallback succeeded (${model} → ${attemptModel}) request_id=${requestId ?? "n/a"}`,
          );
        }
        if (pass > 0) {
          console.warn(
            `[geminiChatWithTools] recovered on retry pass=${pass} model=${attemptModel} request_id=${requestId ?? "n/a"}`,
          );
        }
        return { ...result.value, usedFallback };
      }

      lastError = result.error;
      lastReason = result.reason;
      lastStatus = result.status ?? null;
      lastDeterministic = result.deterministic === true;
      if (result.blocked === true) blockSeen = true;
      attemptStatuses.push({ model: attemptModel, status: lastStatus });
      if (isModelUnavailableStatus(lastStatus)) {
        // Retired / unknown model: prune it for the rest of THIS call.
        console.warn(
          `[gemini] MODEL_UNAVAILABLE model=${attemptModel} request_id=${requestId ?? "n/a"}`,
        );
        attempts = attempts.filter((m) => m !== attemptModel);
      } else if (result.retriable) {
        passHadRetriableFailure = true;
      }
      // Redact again at this log sink, defense-in-depth: result.reason is
      // already redacted at its source (_callOnceWithTools), but this line
      // must not depend on that staying true — a B-pass mutation proved
      // that reverting the inner redaction leaves THIS log line leaking
      // the key on every retriable failure while every existing test (which
      // only inspects the final exhaustion message) stays green, because
      // geminiChatWithTools separately re-redacts lastReason for THAT
      // message (2026-09-21).
      console.warn(
        `[geminiChatWithTools] ${attemptModel} failed (${redactSecrets(result.reason)}) retriable=${result.retriable} pass=${pass} request_id=${requestId ?? "n/a"}`,
      );
    }

    // Whole attempt list failed this pass. Spend another pass only if SOME
    // attempt failed retriably (a transient 429/5xx/empty — NOT a timeout or a
    // 4xx), a live model remains, and we still have wall-clock budget headroom.
    const elapsedMs = Date.now() - startedAt;
    // `attempts.length > 0` is defensive (see geminiChat): unreachable as the sole
    // deciding term today.
    const canRetry = pass < TOOLS_MAX_PASSES - 1 &&
      passHadRetriableFailure &&
      attempts.length > 0 &&
      elapsedMs < TOOLS_RETRY_DEADLINE_MS;
    if (!canRetry) break;
    await _sleepMs(TOOLS_PASS_BACKOFF_MS);
  }

  const exhaustionError = new Error(
    `geminiChatWithTools: all attempts failed for primary=${model}` +
      ` lastReason=${redactSecrets(lastReason)}` +
      (lastError ? ` lastError=${redactSecrets(String(lastError))}` : ""),
  );
  // A5/OI-226 (f7a2c9): attach structured failure info so a catcher (i.e.
  // tool-loop.ts) can feed reportGeminiExhaustion's {status, message} shape
  // without re-parsing the hand-composed .message string above. Additive —
  // .message is unchanged, and tool-loop.ts (the sole production caller) only
  // ever logs it, never parses it (confirmed by grep before this change).
  Object.assign(exhaustionError, {
    status: lastStatus,
    geminiMessage: lastReason,
    attemptStatuses,
    deterministicFailure: lastDeterministic,
    blockSeen,
  });
  throw exhaustionError;
}

interface CallOnceWithToolsArgs {
  model: string;
  systemPrompt: string;
  messages: GeminiContent[];
  tools: GeminiFunctionDeclaration[];
  temperature: number;
  maxTokens: number;
  timeoutMs: number;
  thinking: GeminiThinking;
  requestId?: string;
}

type CallOnceResult =
  | { ok: true; value: Omit<GeminiToolsResult, "usedFallback"> }
  | {
    ok: false;
    reason: string;
    retriable: boolean;
    error?: unknown;
    // A5/OI-226 (f7a2c9): the real HTTP status for an HTTP failure, null for
    // every other failure shape (timeout / empty candidate / transport
    // error) — mirrors geminiChat's own GeminiResult.lastError.status
    // convention so both paths feed reportGeminiExhaustion identically.
    status?: number | null;
    // True when the (untruncated, redacted) 400 body names a missing thought
    // signature. Computed BEFORE the 200-char preview cut so a long tool name
    // cannot push the token past it.
    signatureMissing?: boolean;
    // True when the failure is a deterministic content block (SAFETY etc.):
    // carried onto the thrown exhaustion error for refundableFailure().
    deterministic?: boolean;
    // True for a content block OR a user-caused no-reply (see classifyNoReply): never refund.
    blocked?: boolean;
  };

// ── Private: single HTTP call to Gemini with tool config. ──────────
async function _callOnceWithTools(
  opts: CallOnceWithToolsArgs,
): Promise<CallOnceResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs);

  try {
    const url = GEMINI_URL_TEMPLATE
      .replace("{MODEL}", opts.model)
      .replace("{KEY}", GEMINI_API_KEY);

    const body: Record<string, unknown> = {
      systemInstruction: {
        parts: [{ text: opts.systemPrompt }],
      },
      contents: opts.messages,
      generationConfig: {
        temperature: opts.temperature,
        maxOutputTokens: opts.maxTokens,
      },
    };

    // Thinking config follows the ATTEMPT model (see _callOnce). `minimal` =
    // off, `low` = on; never `thinkingBudget: 0` (3.5 rejects it with a 400).
    const thinkingConfig = thinkingConfigFor(opts.model, opts.thinking);
    if (thinkingConfig) {
      (body.generationConfig as Record<string, unknown>).thinkingConfig =
        thinkingConfig;
    }

    if (opts.tools.length > 0) {
      body.tools = [{ functionDeclarations: opts.tools }];
      // AUTO = model decides whether to call a tool or answer directly.
      // (ANY would force a tool call every turn — wrong for our coach UX.)
      body.toolConfig = {
        functionCallingConfig: { mode: "AUTO" },
      };
    }

    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: controller.signal,
    });

    clearTimeout(timer);

    if (!response.ok) {
      const status = response.status;
      let preview = "";
      let signatureMissing = false;
      try {
        // Redact BEFORE truncating — see the identical fix + comment in
        // _callOnce above (B-pass F2, 2026-09-21).
        const full = redactSecrets(await response.text());
        signatureMissing = /thought[\s_]?signature/i.test(full);
        preview = full.slice(0, 200);
      } catch (_) { /* body read may also fail */ }
      // 429 + 5xx are the retriable bucket — a spaced retry / fallback can
      // help. Other 4xx (e.g. 400 malformed request) won't be helped by a
      // different model or a retry, so mark them non-retriable.
      return {
        ok: false,
        reason: `HTTP ${status}: ${preview}`,
        retriable: status === 429 || status >= 500,
        status,
        signatureMissing,
      };
    }

    const data = await response.json();
    const candidate = data.candidates?.[0];

    if (!candidate || !candidate.content?.parts) {
      // Empty / missing candidate is usually a transient overload; retry can
      // help (matches the existing fallback intent). A hard content block
      // (SAFETY / RECITATION / PROHIBITED_CONTENT) is deterministic, so don't
      // burn extra passes on it.
      const cls = classifyNoReply(candidate?.finishReason, data.promptFeedback?.blockReason);
      return {
        ok: false,
        reason: `no candidate (finishReason=${cls.finishReason})`,
        retriable: !cls.deterministic,
        deterministic: cls.deterministic,
        blocked: cls.blocked,
      };
    }

    const rawParts = candidate.content.parts as Array<Record<string, unknown>>;

    // Normalise into our discriminated GeminiPart union and split into
    // the convenience accessors (text + functionCalls).
    const parts: GeminiPart[] = [];
    const textBuffer: string[] = [];
    const functionCalls: Array<{ name: string; args: Record<string, unknown> }> = [];

    // Gemini 3 thought signatures: every recognised part is kept RAW (so a
    // `thoughtSignature` beside `functionCall`/`text` survives into the stored
    // model turn). The convenience accessors still carry only name/args/text.
    for (const p of rawParts) {
      if (typeof p.text === "string") {
        parts.push(p as unknown as GeminiPart);
        textBuffer.push(p.text);
      } else if (p.functionCall && typeof p.functionCall === "object") {
        const fc = p.functionCall as { name?: string; args?: Record<string, unknown> };
        if (typeof fc.name === "string") {
          parts.push(
            {
              ...p,
              functionCall: { name: fc.name, args: fc.args ?? {} },
            } as unknown as GeminiPart,
          );
          functionCalls.push({ name: fc.name, args: fc.args ?? {} });
        }
      } else if (p.functionResponse && typeof p.functionResponse === "object") {
        // Defensive — model normally never emits these, but keep round-trip safe.
        const fr = p.functionResponse as {
          name?: string;
          response?: Record<string, unknown>;
        };
        if (typeof fr.name === "string") {
          parts.push({
            functionResponse: { name: fr.name, response: fr.response ?? {} },
          });
        }
      } else if (p.inline_data && typeof p.inline_data === "object") {
        parts.push(p as unknown as GeminiPart);
      } else if (typeof p.thoughtSignature === "string") {
        // Signature-only part (no text / call): echo it raw too.
        parts.push({ thoughtSignature: p.thoughtSignature });
      }
    }

    // Empty response (no text AND no function calls) — treat as failure
    // so the caller's fallback can fire. This matches geminiChat()'s
    // empty-text behaviour.
    if (parts.length === 0) {
      const cls = classifyNoReply(candidate.finishReason, data.promptFeedback?.blockReason);
      return {
        ok: false,
        reason: "empty parts array",
        retriable: !cls.deterministic,
        deterministic: cls.deterministic,
        blocked: cls.blocked,
      };
    }
    // Judge the JOINED, trimmed text: Gemini 3 can send an empty-text part that
    // only carries a signature, which must not pass as a terminal reply
    // (geminiChat already treats `!text` as a failure; the two paths must agree).
    if (functionCalls.length === 0 && textBuffer.join("").trim() === "") {
      const cls = classifyNoReply(candidate.finishReason, data.promptFeedback?.blockReason);
      return {
        ok: false,
        reason: "no text and no function calls",
        retriable: !cls.deterministic,
        deterministic: cls.deterministic,
        blocked: cls.blocked,
      };
    }

    const tokensUsed = data.usageMetadata?.totalTokenCount ?? 0;
    logUsage("tools", opts.model, data.usageMetadata);

    return {
      ok: true,
      value: {
        text: textBuffer.join("").trim(),
        functionCalls,
        parts,
        modelUsed: opts.model,
        tokensUsed,
      },
    };
  } catch (err) {
    clearTimeout(timer);
    if (err instanceof DOMException && err.name === "AbortError") {
      // A 25s timeout already consumed this round's budget — retrying in place
      // would risk the overall wall clock. Not retriable; fall through to the
      // next model (or throw).
      return {
        ok: false,
        reason: `timeout (${opts.timeoutMs}ms)`,
        retriable: false,
        error: err,
      };
    }
    // Network blip / transport error — a spaced retry can recover.
    return {
      ok: false,
      reason: `threw: ${redactSecrets(String(err))}`,
      retriable: true,
      error: err,
    };
  }
}
