// supabase/functions/_shared/gemini_thinking_config_test.ts
//
// FC1 (diagnose 7fbe21) — Gemini 2.5 Flash runs "thinking" ON by default, and
// the hidden thinking tokens count against maxOutputTokens. With our low output
// caps the model could spend the whole budget thinking and return an EMPTY
// candidate (finishReason=MAX_TOKENS), which the caller then silently degraded
// to Flash-Lite. The fix sets `generationConfig.thinkingConfig.thinkingBudget=0`
// for every NON-Pro attempt (Flash + its Lite fallback); MODEL_PRO keeps dynamic
// thinking (weekly-report needs the reasoning headroom).
//
// This is a BEHAVIORAL test: it stubs `globalThis.fetch` (mirrors the pattern in
// the sibling `gemini_backoff_retry_test.ts`), captures the request body that
// geminiChat sends, and asserts:
//   • MODEL_FLASH  → generationConfig.thinkingConfig.thinkingBudget === 0
//   • MODEL_PRO    → generationConfig.thinkingConfig is undefined (untouched)
//
// Run: deno test --allow-env supabase/functions/_shared/gemini_thinking_config_test.ts
//
// NOTE: Deno may not be installed on the dev machine — this test is written for
// CI (which runs the Deno suite). It could not be executed locally.

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

// The module reads GEMINI_API_KEY at eval time — set it BEFORE the dynamic
// import so geminiChat doesn't short-circuit on the missing-key guard.
Deno.env.set("GEMINI_API_KEY", "test-key-not-a-real-secret");

const { geminiChat, MODEL_FLASH, MODEL_PRO } = await import("./gemini.ts");

// A minimal well-formed Gemini success response — enough for geminiChat to
// return content and stop after one call.
function okResponse(text: string): Response {
  return {
    ok: true,
    status: 200,
    text: () => Promise.resolve(""),
    json: () =>
      Promise.resolve({
        candidates: [{ content: { parts: [{ text }] } }],
        usageMetadata: { totalTokenCount: 5 },
      }),
  } as unknown as Response;
}

/**
 * Stub globalThis.fetch, capturing the parsed JSON body of the FIRST request.
 * Returns the captured-body holder + a restore fn. No real network is touched.
 */
function installBodyCapture(): {
  captured: { body: Record<string, unknown> | null };
  restore: () => void;
} {
  const original = globalThis.fetch;
  const captured: { body: Record<string, unknown> | null } = { body: null };
  globalThis.fetch = ((_input: unknown, init?: unknown): Promise<Response> => {
    const reqInit = init as { body?: string } | undefined;
    if (captured.body === null && reqInit?.body) {
      captured.body = JSON.parse(reqInit.body) as Record<string, unknown>;
    }
    return Promise.resolve(okResponse("ok"));
  }) as typeof fetch;
  return { captured, restore: () => (globalThis.fetch = original) };
}

Deno.test("geminiChat — MODEL_FLASH disables thinking (thinkingBudget=0)", async () => {
  const { captured, restore } = installBodyCapture();
  try {
    const res = await geminiChat({
      model: MODEL_FLASH,
      systemPrompt: "you are a coach",
      userPrompt: "hi",
      maxTokens: 1024,
      // Keep the attempt list to a single call so the captured body is Flash's.
      fallbackToLite: false,
    });
    assertEquals(res.content, "ok");

    const gc = (captured.body?.generationConfig ?? {}) as Record<
      string,
      unknown
    >;
    const thinkingConfig = gc.thinkingConfig as
      | { thinkingBudget?: number }
      | undefined;
    assertEquals(thinkingConfig?.thinkingBudget, 0);
  } finally {
    restore();
  }
});

Deno.test("geminiChat — MODEL_PRO leaves thinkingConfig untouched (dynamic thinking)", async () => {
  const { captured, restore } = installBodyCapture();
  try {
    const res = await geminiChat({
      model: MODEL_PRO,
      systemPrompt: "you are a coach",
      userPrompt: "hi",
      maxTokens: 2048,
      // Pro must not fall back to Lite (a text-only Lite retry is meaningless
      // for the weekly-report reasoning path) — and it keeps the single-call
      // guarantee for this assertion.
      fallbackToLite: false,
    });
    assertEquals(res.content, "ok");

    const gc = (captured.body?.generationConfig ?? {}) as Record<
      string,
      unknown
    >;
    assertEquals(gc.thinkingConfig, undefined);
  } finally {
    restore();
  }
});
