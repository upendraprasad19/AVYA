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
 * Model matrix (stay in sync with CLAUDE.md §11):
 *   gemini-2.5-flash       — primary chat + structured JSON (ai-proxy,
 *                            morning-alert, rolling-context,
 *                            future-prediction, daily-snapshot text,
 *                            food_text_analysis)
 *   gemini-2.5-flash-lite  — vision paths (scan_meal, cart_auditor,
 *                            assess-body-composition, ai-media-proxy)
 *                            and fallback for Flash
 *   gemini-2.5-pro         — weekly-report only (deepest reasoning)
 *
 * Fallback: on 5xx / 429 / empty-content from the primary model, retry
 * once against `gemini-2.5-flash-lite` (cheaper + usually has quota
 * headroom when Flash is rate-limited). Set `fallbackToLite: false` to
 * skip (e.g. when primary is ALREADY Flash-Lite, or when the call is so
 * vision-heavy that a text-only Lite retry is meaningless).
 *
 * Not retried: 4xx other than 429 (request is broken; retrying won't
 * help) and explicit quota-exceeded responses.
 */

import type { GeminiFunctionDeclaration } from "./tools/zodToGemini.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY")!;

const GEMINI_URL_TEMPLATE =
  "https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={KEY}";

// Stable SKU names — colocated here so callers pick from a canonical list.
export const MODEL_FLASH = "gemini-2.5-flash";
export const MODEL_FLASH_LITE = "gemini-2.5-flash-lite";
export const MODEL_PRO = "gemini-2.5-pro";

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
   * On 5xx / 429 / empty content, retry once against Flash-Lite.
   * Default true. Pass false when primary is already Flash-Lite or
   * when fallback wouldn't add value.
   */
  fallbackToLite?: boolean;
}

export interface GeminiResult {
  /** Trimmed text content. null if every attempt failed. */
  content: string | null;
  /** The model slug that produced `content`. null on total failure. */
  modelUsed: string | null;
  /** Approximate token usage — totalTokenCount from Gemini's usageMetadata. */
  tokensUsed: number;
}

/**
 * Single-request call to Gemini. Handles:
 *   - System-instruction translation from OpenAI-style roles
 *   - Optional inline-data image (Gemini's `inline_data` part)
 *   - JSON mode via `responseMimeType: application/json`
 *   - Flash → Flash-Lite fallback on retriable errors
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
  } = options;

  if (!GEMINI_API_KEY) {
    console.error("[geminiChat] GEMINI_API_KEY not configured");
    return { content: null, modelUsed: null, tokensUsed: 0 };
  }

  // Try primary, then (optionally) Flash-Lite. Never chain Lite → Lite.
  const attempts: string[] = [model];
  if (fallbackToLite && model !== MODEL_FLASH_LITE) {
    attempts.push(MODEL_FLASH_LITE);
  }

  for (const attemptModel of attempts) {
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
    });

    if (result.content !== null) {
      // Success on the first attempt is the common path; log the
      // fallback case so we can monitor Flash quota health in prod.
      if (attemptModel !== model) {
        console.warn(
          `[geminiChat] fallback succeeded (${model} → ${attemptModel})`,
        );
      }
      return result;
    }
    console.warn(
      `[geminiChat] ${attemptModel} returned null — ${attempts.indexOf(attemptModel) < attempts.length - 1 ? "trying fallback" : "all attempts exhausted"}`,
    );
  }

  console.error(
    `[geminiChat] All ${attempts.length} attempts failed for primary=${model}`,
  );
  return { content: null, modelUsed: null, tokensUsed: 0 };
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
    // Non-retriable 4xx returns null immediately — caller logs & moves on.
    if (!response.ok) {
      const status = response.status;
      let preview = "";
      try {
        preview = (await response.text()).slice(0, 200);
      } catch (_) { /* body read may also fail */ }
      console.warn(
        `[geminiChat] ${opts.model} HTTP ${status}: ${preview}`,
      );
      return { content: null, modelUsed: null, tokensUsed: 0 };
    }

    const data = await response.json();
    const candidate = data.candidates?.[0];

    // Safety-filter blocks or missing candidate: treat as failure.
    if (!candidate || !candidate.content?.parts) {
      console.warn(
        `[geminiChat] ${opts.model} no candidate (finishReason=${candidate?.finishReason ?? "unknown"})`,
      );
      return { content: null, modelUsed: null, tokensUsed: 0 };
    }

    // Stitch multi-part responses into one string.
    const text = (candidate.content.parts as Array<{ text?: string }>)
      .map((p) => p.text ?? "")
      .join("")
      .trim();

    if (!text) {
      return { content: null, modelUsed: null, tokensUsed: 0 };
    }

    const tokensUsed = data.usageMetadata?.totalTokenCount ?? 0;

    return {
      content: text,
      modelUsed: opts.model,
      tokensUsed,
    };
  } catch (err) {
    clearTimeout(timer);
    if (err instanceof DOMException && err.name === "AbortError") {
      console.warn(
        `[geminiChat] ${opts.model} timed out (${opts.timeoutMs}ms)`,
      );
    } else {
      console.warn(`[geminiChat] ${opts.model} threw: ${err}`);
    }
    return { content: null, modelUsed: null, tokensUsed: 0 };
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
  | { text: string }
  | { functionCall: { name: string; args: Record<string, unknown> } }
  | { functionResponse: { name: string; response: Record<string, unknown> } }
  | { inline_data: { mime_type: string; data: string } };

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
  /** Default true. On 5xx / 429 / empty content, retry once on Flash-Lite. */
  fallbackToLite?: boolean;
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
   * the happy path; `MODEL_FLASH_LITE` if the fallback path fired.
   */
  modelUsed: string;
  /** Total tokens (input + output) per Gemini's usageMetadata. 0 on failure. */
  tokensUsed: number;
  /** True iff this response came from the Flash-Lite fallback. */
  usedFallback: boolean;
}

/**
 * Multi-turn Gemini call with function-calling support.
 *
 * Caller owns the messages array across rounds — this helper does NOT
 * mutate it. Append the model's response (`role: "model", parts: result.parts`)
 * AND the function-response turns (`role: "function", parts: [...]`) before
 * the next call.
 *
 * On 5xx / 429 / empty content from the primary model, retries once against
 * `MODEL_FLASH_LITE` if `fallbackToLite` is true (default). Throws on total
 * failure so the caller can surface a user-visible apology.
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
    requestId,
  } = opts;

  if (!GEMINI_API_KEY) {
    console.error(
      `[geminiChatWithTools] GEMINI_API_KEY not configured request_id=${requestId ?? "n/a"}`,
    );
    throw new Error("GEMINI_API_KEY not configured");
  }

  const attempts: string[] = [model];
  if (fallbackToLite && model !== MODEL_FLASH_LITE) {
    attempts.push(MODEL_FLASH_LITE);
  }

  let lastError: unknown = null;

  for (const attemptModel of attempts) {
    const result = await _callOnceWithTools({
      model: attemptModel,
      systemPrompt,
      messages,
      tools,
      temperature,
      maxTokens,
      timeoutMs,
      requestId,
    });

    if (result.ok) {
      const usedFallback = attemptModel !== model;
      if (usedFallback) {
        console.warn(
          `[geminiChatWithTools] fallback succeeded (${model} → ${attemptModel}) request_id=${requestId ?? "n/a"}`,
        );
      }
      return { ...result.value, usedFallback };
    }

    lastError = result.error;
    console.warn(
      `[geminiChatWithTools] ${attemptModel} failed (${result.reason}) request_id=${requestId ?? "n/a"}` +
        (attempts.indexOf(attemptModel) < attempts.length - 1
          ? " — trying fallback"
          : " — all attempts exhausted"),
    );
  }

  throw new Error(
    `geminiChatWithTools: all ${attempts.length} attempt(s) failed for primary=${model}` +
      (lastError ? ` lastError=${String(lastError)}` : ""),
  );
}

interface CallOnceWithToolsArgs {
  model: string;
  systemPrompt: string;
  messages: GeminiContent[];
  tools: GeminiFunctionDeclaration[];
  temperature: number;
  maxTokens: number;
  timeoutMs: number;
  requestId?: string;
}

type CallOnceResult =
  | { ok: true; value: Omit<GeminiToolsResult, "usedFallback"> }
  | { ok: false; reason: string; error?: unknown };

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
      try {
        preview = (await response.text()).slice(0, 200);
      } catch (_) { /* body read may also fail */ }
      // 429 + 5xx are the retriable bucket — fallback can help.
      // Other 4xx (e.g. 400 malformed request) won't be helped by a
      // different model, but we still treat them uniformly here so the
      // caller's fallback policy is the single source of truth.
      return {
        ok: false,
        reason: `HTTP ${status}: ${preview}`,
      };
    }

    const data = await response.json();
    const candidate = data.candidates?.[0];

    if (!candidate || !candidate.content?.parts) {
      return {
        ok: false,
        reason: `no candidate (finishReason=${candidate?.finishReason ?? "unknown"})`,
      };
    }

    const rawParts = candidate.content.parts as Array<Record<string, unknown>>;

    // Normalise into our discriminated GeminiPart union and split into
    // the convenience accessors (text + functionCalls).
    const parts: GeminiPart[] = [];
    const textBuffer: string[] = [];
    const functionCalls: Array<{ name: string; args: Record<string, unknown> }> = [];

    for (const p of rawParts) {
      if (typeof p.text === "string") {
        parts.push({ text: p.text });
        textBuffer.push(p.text);
      } else if (p.functionCall && typeof p.functionCall === "object") {
        const fc = p.functionCall as { name?: string; args?: Record<string, unknown> };
        if (typeof fc.name === "string") {
          const normalised = { name: fc.name, args: fc.args ?? {} };
          parts.push({ functionCall: normalised });
          functionCalls.push(normalised);
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
      }
    }

    // Empty response (no text AND no function calls) — treat as failure
    // so the caller's fallback can fire. This matches geminiChat()'s
    // empty-text behaviour.
    if (parts.length === 0) {
      return { ok: false, reason: "empty parts array" };
    }
    if (textBuffer.length === 0 && functionCalls.length === 0) {
      return { ok: false, reason: "no text and no function calls" };
    }

    const tokensUsed = data.usageMetadata?.totalTokenCount ?? 0;

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
      return {
        ok: false,
        reason: `timeout (${opts.timeoutMs}ms)`,
        error: err,
      };
    }
    return {
      ok: false,
      reason: `threw: ${err}`,
      error: err,
    };
  }
}
