// supabase/functions/_shared/gemini_backoff_retry_test.ts
//
// Diagnose d4f1c2 (2026-06-01) — the AI coach intermittently replied
// "I had trouble reaching the model. Try again in a moment." Root cause:
// `geminiChatWithTools` tried [Flash → Flash-Lite] back-to-back with NO time
// spacing, both on the same project quota, so a single transient 429/5xx/empty
// blip tripped both within ~1-2s and the function threw — and `runToolLoop`
// surfaced the apology with zero retry. The fix adds a bounded, time-spaced
// backoff-retry pass for the RETRIABLE bucket (429 / 5xx / empty-candidate)
// while NOT retrying timeouts (budget already spent) or non-429 4xx (a retry
// can't help).
//
// This is a BEHAVIORAL test: it stubs `globalThis.fetch` (no module-mock shim
// needed — geminiChatWithTools calls the global directly) and asserts the
// retry recovers a transient failure, does NOT retry a timeout or a 4xx, and
// stays bounded on a persistent failure.
//
// Run: deno test --allow-env supabase/functions/_shared/gemini_backoff_retry_test.ts

import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

// The module reads GEMINI_API_KEY at eval time — set it BEFORE the dynamic
// import so geminiChatWithTools doesn't short-circuit on the missing-key guard.
Deno.env.set("GEMINI_API_KEY", "test-key-not-a-real-secret");

const { geminiChatWithTools, MODEL_FLASH } = await import("./gemini.ts");

// ── Fake Response builders ────────────────────────────────────────────
function okResponse(text: string): Response {
  return {
    ok: true,
    status: 200,
    text: () => Promise.resolve(""),
    json: () =>
      Promise.resolve({
        candidates: [{ content: { parts: [{ text }] } }],
        usageMetadata: { totalTokenCount: 7 },
      }),
  } as unknown as Response;
}

function httpErrorResponse(status: number, body = "err"): Response {
  return {
    ok: false,
    status,
    text: () => Promise.resolve(body),
    json: () => Promise.resolve({}),
  } as unknown as Response;
}

function abortError(): Promise<Response> {
  return Promise.reject(new DOMException("aborted", "AbortError"));
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

// `fallbackToLite: true` is set EXPLICITLY (not relied on as a default) because
// the call-count assertions below (2 per pass, 4 over two passes) assume the
// attempt list is [Flash, Flash-Lite]. A silent default change would otherwise
// make those assertions wrong without flagging it. (B-pass review P2, 2026-06-01.)
const baseOpts = {
  model: MODEL_FLASH,
  systemPrompt: "you are a coach",
  messages: [{ role: "user" as const, parts: [{ text: "hi" }] }],
  tools: [],
  fallbackToLite: true,
};

Deno.test("geminiChatWithTools — recovers a transient 5xx on the retry pass", async () => {
  // pass 0: Flash 503, Lite 503 → (retriable) sleep → pass 1: Flash 200.
  const { state, restore } = installFetchQueue([
    () => Promise.resolve(httpErrorResponse(503, "overloaded")),
    () => Promise.resolve(httpErrorResponse(503, "overloaded")),
    () => Promise.resolve(okResponse("recovered")),
  ]);
  try {
    const res = await geminiChatWithTools(baseOpts);
    assertEquals(res.text, "recovered");
    // 3 calls: Flash+Lite on pass 0, Flash on pass 1.
    assertEquals(state.calls, 3);
  } finally {
    restore();
  }
});

Deno.test("geminiChatWithTools — does NOT retry a non-429 4xx (a retry can't help)", async () => {
  // 400 is non-retriable: one pass over [Flash, Lite] then throw — no 2nd pass.
  const { state, restore } = installFetchQueue([
    () => Promise.resolve(httpErrorResponse(400, "bad request")),
  ]);
  try {
    await assertRejects(() => geminiChatWithTools(baseOpts));
    assertEquals(state.calls, 2);
  } finally {
    restore();
  }
});

Deno.test("geminiChatWithTools — does NOT retry a timeout (budget already spent)", async () => {
  // AbortError == the 25s timeout fired; retrying in place would risk the
  // overall wall clock, so it's non-retriable: 2 calls (Flash, Lite) then throw.
  const { state, restore } = installFetchQueue([abortError]);
  try {
    await assertRejects(() => geminiChatWithTools(baseOpts));
    assertEquals(state.calls, 2);
  } finally {
    restore();
  }
});

Deno.test("geminiChatWithTools — stays bounded on a persistent retriable failure", async () => {
  // Every attempt 429s. Bounded at TOOLS_MAX_PASSES(2) × [Flash, Lite] = 4
  // calls, then throws — it must NOT retry forever.
  const { state, restore } = installFetchQueue([
    () => Promise.resolve(httpErrorResponse(429, "rate limited")),
  ]);
  try {
    await assertRejects(() => geminiChatWithTools(baseOpts));
    assertEquals(state.calls, 4);
  } finally {
    restore();
  }
});

Deno.test("geminiChatWithTools — happy path makes exactly one call, no retry", async () => {
  const { state, restore } = installFetchQueue([() =>
    Promise.resolve(okResponse("all good"))
  ]);
  try {
    const res = await geminiChatWithTools(baseOpts);
    assertEquals(res.text, "all good");
    assertEquals(res.usedFallback, false);
    assertEquals(state.calls, 1);
  } finally {
    restore();
  }
});
