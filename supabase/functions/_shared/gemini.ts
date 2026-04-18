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
