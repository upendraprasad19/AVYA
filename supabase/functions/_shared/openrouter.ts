/**
 * Shared OpenRouter cascade chat utility.
 *
 * Tries a list of models in order. If one fails (timeout, HTTP error,
 * empty response), falls through to the next. Returns the first
 * successful response or null if all models fail.
 *
 * Used by: rolling-context, morning-alert, future-prediction, weekly-report
 *
 * Free-tier fallback models (all $0/M tokens on OpenRouter):
 *   - qwen/qwen3.6-plus:free         (1M context, top-ranked)
 *   - stepfun/step-3.5-flash:free     (256K context, fast reasoning)
 *   - nvidia/nemotron-3-super-120b-a12b:free (262K context, strong general)
 *   - minimax/minimax-m2.5:free       (197K context, final fallback)
 */

const OPENROUTER_API_KEY = Deno.env.get("OPENROUTER_API_KEY")!;

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

/** Free-tier models in cascade priority order. */
export const FREE_MODELS = [
  "qwen/qwen3.6-plus:free",
  "stepfun/step-3.5-flash:free",
  "nvidia/nemotron-3-super-120b-a12b:free",
  "minimax/minimax-m2.5:free",
] as const;

export interface CascadeOptions {
  /** Ordered list of model slugs to try. First = highest priority. */
  models: string[];
  /** System prompt. */
  systemPrompt: string;
  /** User prompt. */
  userPrompt: string;
  /** Max tokens for the response. */
  maxTokens: number;
  /** Temperature (default 1.0). */
  temperature?: number;
  /** Per-model timeout in ms (default 10000). */
  timeoutMs?: number;
  /** X-Title header for OpenRouter tracking. */
  title?: string;
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
 * A model is considered failed if:
 *   - The fetch times out (AbortError)
 *   - The HTTP status is not 2xx
 *   - The response body is empty or missing choices
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
  } = options;

  if (!OPENROUTER_API_KEY) {
    console.error("[cascadeChat] OPENROUTER_API_KEY not configured");
    return { content: null, modelUsed: null, tokensUsed: 0 };
  }

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
            { role: "user", content: userPrompt },
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
