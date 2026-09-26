// supabase/functions/_shared/gemini_test.ts
//
// Obs 6 (food-logging-observations batch, 2026-09-20) — users saw a generic
// "The AI is offline (502)" error with no way for the founder to distinguish
// genuine Gemini quota exhaustion from a client bug or a real outage, because
// `GeminiResult` only exposed `{content, modelUsed, tokensUsed}`, discarding
// the real HTTP status/error message before it reached any caller. This adds
// an optional `lastError` field so the real failure reason survives total
// exhaustion. Task 10 (separate) wires this into an admin-only alert; this
// task only makes the data available.
//
// This is a BEHAVIORAL test: it stubs `globalThis.fetch` (mirrors the pattern
// in the sibling `gemini_backoff_retry_test.ts` / `gemini_thinking_config_test.ts`
// — no module-mock shim needed, geminiChat calls the global directly) and
// asserts `lastError` is populated with the LAST attempt's real failure
// reason when every attempt in the [Flash, Flash-Lite] list fails.
//
// Run: deno test --no-check --allow-all --node-modules-dir=none supabase/functions/_shared/gemini_test.ts

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

// The module reads GEMINI_API_KEY at eval time — set it BEFORE the dynamic
// import so geminiChat doesn't short-circuit on the missing-key guard (that
// branch is covered separately below, WITHOUT touching this shared key, since
// deleting an already-loaded module-scope const has no effect — see the task
// brief's implementer note).
Deno.env.set("GEMINI_API_KEY", "test-key-not-a-real-secret");

const { geminiChat, MODEL_FLASH } = await import("./gemini.ts");

function httpErrorResponse(status: number, body: string): Response {
  return {
    ok: false,
    status,
    text: () => Promise.resolve(body),
    json: () => Promise.resolve({}),
  } as unknown as Response;
}

/**
 * Replace globalThis.fetch with a queue of behaviors. Each call consumes the
 * next behavior (the last behavior repeats if the queue is exhausted). Returns
 * a live call counter + a restore fn. No real network is touched.
 */
function installFetchQueue(
  behaviors: Array<() => Promise<Response>>,
): { state: { calls: number }; restore: () => void } {
  const original = globalThis.fetch;
  const state = { calls: 0 };
  globalThis.fetch = ((_input: unknown, _init?: unknown): Promise<Response> => {
    const idx = Math.min(state.calls, behaviors.length - 1);
    state.calls++;
    return behaviors[idx]();
  }) as typeof fetch;
  return { state, restore: () => (globalThis.fetch = original) };
}

Deno.test("geminiChat surfaces lastError when all attempts fail (429 quota exhaustion)", async () => {
  // Flash 429, then Flash-Lite fallback also 429 — total exhaustion. The
  // LAST attempt (Flash-Lite) is what should be captured in lastError.
  const { restore } = installFetchQueue([
    () => Promise.resolve(httpErrorResponse(429, "quota exceeded for flash")),
    () => Promise.resolve(httpErrorResponse(429, "quota exceeded for flash-lite")),
  ]);
  try {
    const result = await geminiChat({
      model: MODEL_FLASH,
      systemPrompt: "test",
      userPrompt: "test",
      maxTokens: 10,
    });
    assertEquals(result.content, null);
    assertEquals(result.modelUsed, null);
    // The shape must be the LAST attempt's real reason, not a generic string.
    assertEquals(result.lastError !== undefined, true);
    assertEquals(result.lastError, {
      status: 429,
      message: "quota exceeded for flash-lite",
    });
  } finally {
    restore();
  }
});

Deno.test("geminiChat surfaces lastError with status:null on a thrown/timeout-shaped failure", async () => {
  const { restore } = installFetchQueue([
    () => Promise.reject(new DOMException("aborted", "AbortError")),
    () => Promise.reject(new DOMException("aborted", "AbortError")),
  ]);
  try {
    const result = await geminiChat({
      model: MODEL_FLASH,
      systemPrompt: "test",
      userPrompt: "test",
      maxTokens: 10,
      timeoutMs: 5,
    });
    assertEquals(result.content, null);
    assertEquals(result.lastError !== undefined, true);
    assertEquals(result.lastError?.status, null);
    assertEquals(result.lastError?.message, "timed out after 5ms");
  } finally {
    restore();
  }
});

Deno.test("geminiChat does NOT set lastError on success", async () => {
  const { restore } = installFetchQueue([
    () =>
      Promise.resolve({
        ok: true,
        status: 200,
        text: () => Promise.resolve(""),
        json: () =>
          Promise.resolve({
            candidates: [{ content: { parts: [{ text: "hi there" }] } }],
            usageMetadata: { totalTokenCount: 3 },
          }),
      } as unknown as Response),
  ]);
  try {
    const result = await geminiChat({
      model: MODEL_FLASH,
      systemPrompt: "test",
      userPrompt: "test",
      maxTokens: 10,
      fallbackToLite: false,
    });
    assertEquals(result.content, "hi there");
    assertEquals(result.lastError, undefined);
  } finally {
    restore();
  }
});

// NOTE on the `!GEMINI_API_KEY` branch (gemini.ts's other lastError site):
// GEMINI_API_KEY is a module-scope const captured at import time (gemini.ts:34),
// and this test file's import above already set a key BEFORE loading the
// module (required so the three tests above can exercise the fetch seam at
// all). That makes the missing-key branch unreachable via env mutation from
// within this file — a later `Deno.env.delete()` cannot un-evaluate an
// already-captured const. Not asserted here; verified by code inspection in
// the self-review instead (a literal `lastError: { status: null, message:
// "GEMINI_API_KEY not configured" }` alongside the existing `content: null`
// return).
