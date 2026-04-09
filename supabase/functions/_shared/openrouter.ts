/**
 * Shared OpenRouter cascade chat utility — text + multimodal (images).
 *
 * Tries a list of models in order. If one fails (timeout, HTTP error,
 * empty response), falls through to the next. Returns the first
 * successful response or null if all models fail.
 *
 * Used by: ai-proxy, assess-body-composition, ai-media-proxy,
 *          daily-snapshot, rolling-context, morning-alert,
 *          future-prediction, weekly-report
 *
 * Free-tier vision models (Gemma 4 family):
 *   - google/gemma-4-31b-it:free     (text + image, 31B dense)
 *   - google/gemma-4-26b-a4b-it:free (text + image + video, 26B MoE)
 *
 * Free-tier text-only models:
 *   - qwen/qwen3.6-plus:free
 *   - nvidia/nemotron-3-super-120b-a12b:free
 *   - minimax/minimax-m2.5:free
 */

const OPENROUTER_API_KEY = Deno.env.get("OPENROUTER_API_KEY")!;

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

/** Free-tier text models in cascade priority order. */
export const FREE_TEXT_MODELS = [
  "qwen/qwen3.6-plus:free",
  "nvidia/nemotron-3-super-120b-a12b:free",
  "minimax/minimax-m2.5:free",
] as const;

/** Free-tier vision models (image + text input). */
export const FREE_VISION_MODELS = [
  "google/gemma-4-31b-it:free",
  "google/gemma-4-26b-a4b-it:free",
] as const;

// Backward compat alias
export const FREE_MODELS = FREE_TEXT_MODELS;

export interface CascadeOptions {
  /** Ordered list of model slugs to try. First = highest priority. */
  models: string[];
  /** System prompt. */
  systemPrompt: string;
  /** User prompt (text part). */
  userPrompt: string;
  /** Max tokens for the response. */
  maxTokens: number;
  /** Temperature (default 1.0). */
  temperature?: number;
  /** Per-model timeout in ms (default 10000). */
  timeoutMs?: number;
  /** X-Title header for OpenRouter tracking. */
  title?: string;
  /** Optional base64-encoded image for multimodal models. */
  imageBase64?: string;
  /** MIME type of the image (default: "image/jpeg"). */
  imageMimeType?: string;
}

export interface CascadeResult {
  /** The AI response content, or null if all models failed. */
  content: string | null;
  /** The model slug that succeeded, or null. */
  modelUsed: string | null;
  /** Total tokens used (from the successful response). */
  tokensUsed: number;
}

/**
 * Try each model in sequence. Return the first successful response.
 *
 * Supports multimodal input: if `imageBase64` is provided, the user
 * message is sent as an array of content parts (OpenAI-compatible format).
 *
 * No retries within a single model — the cascade IS the retry strategy.
 */
export async function cascadeChat(
  options: CascadeOptions,
): Promise<CascadeResult> {
  const {
    models,
    systemPrompt,
    userPrompt,
    maxTokens,
    temperature = 1.0,
    timeoutMs = 10000,
    title = "ICANBEFITTER",
    imageBase64,
    imageMimeType = "image/jpeg",
  } = options;

  if (!OPENROUTER_API_KEY) {
    console.error("[cascadeChat] OPENROUTER_API_KEY not configured");
    return { content: null, modelUsed: null, tokensUsed: 0 };
  }

  // Build user message — text-only or multimodal
  const userContent: unknown = imageBase64
    ? [
        {
          type: "image_url",
          image_url: {
            url: `data:${imageMimeType};base64,${imageBase64}`,
          },
        },
        { type: "text", text: userPrompt },
      ]
    : userPrompt;

  for (const model of models) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);

    try {
      const response = await fetch(OPENROUTER_URL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${OPENROUTER_API_KEY}`,
          "Content-Type": "application/json",
          "HTTP-Referer": "https://icanbefitter.app",
          "X-Title": title,
        },
        body: JSON.stringify({
          model,
          messages: [
            { role: "system", content: systemPrompt },
            { role: "user", content: userContent },
          ],
          max_tokens: maxTokens,
          temperature,
        }),
        signal: controller.signal,
      });

      clearTimeout(timer);

      if (!response.ok) {
        console.warn(
          `[cascadeChat] ${model} HTTP ${response.status} — trying next`,
        );
        continue;
      }

      const data = await response.json();
      const content = data.choices?.[0]?.message?.content;
      const tokensUsed = data.usage?.total_tokens ?? 0;

      if (content && typeof content === "string" && content.trim().length > 0) {
        console.log(`[cascadeChat] Success with ${model}`);
        return { content: content.trim(), modelUsed: model, tokensUsed };
      }

      console.warn(`[cascadeChat] ${model} returned empty content — trying next`);
    } catch (err) {
      clearTimeout(timer);
      if (err instanceof DOMException && err.name === "AbortError") {
        console.warn(
          `[cascadeChat] ${model} timed out (${timeoutMs}ms) — trying next`,
        );
      } else {
        console.warn(`[cascadeChat] ${model} error: ${err} — trying next`);
      }
    }
  }

  console.error(
    `[cascadeChat] All ${models.length} models failed: ${models.join(", ")}`,
  );
  return { content: null, modelUsed: null, tokensUsed: 0 };
}
