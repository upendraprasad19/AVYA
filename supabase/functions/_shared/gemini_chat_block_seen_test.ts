// supabase/functions/_shared/gemini_chat_block_seen_test.ts
//
// Part B (gemini3-limits-caching): the NON-tool `geminiChat` path (food text, scan meal,
// cart auditor) must carry a STICKY `blockSeen`, so a content block on ONE attempt is
// never laundered into a refund by a transport failure on the other attempt. Driven
// end to end through the real geminiChat with a mocked fetch, then judged by the same
// `refundableGeminiChatFailure` ai-proxy calls.
//
// Run: deno test --no-check --allow-env --node-modules-dir=none
//      supabase/functions/_shared/gemini_chat_block_seen_test.ts

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.env.set("GEMINI_API_KEY", "test-key-not-a-real-secret");

const { geminiChat } = await import("./gemini.ts");
const { refundableGeminiChatFailure } = await import("./quota_refund.ts");

function httpError(status: number): Response {
  return { ok: false, status, text: () => Promise.resolve("err"), json: () => Promise.resolve({}) } as unknown as Response;
}
function json200(body: unknown): Response {
  return { ok: true, status: 200, text: () => Promise.resolve(""), json: () => Promise.resolve(body) } as unknown as Response;
}

const SAFETY = { candidates: [{ finishReason: "SAFETY" }], usageMetadata: { totalTokenCount: 1 } };
const SAFETY_EMPTY_PARTS = {
  candidates: [{ finishReason: "SAFETY", content: { parts: [{ text: "" }] } }],
  usageMetadata: { totalTokenCount: 1 },
};
const PROMPT_BLOCKED = { promptFeedback: { blockReason: "OTHER" }, usageMetadata: { totalTokenCount: 1 } };

async function run(...steps: Array<() => Response>) {
  const original = globalThis.fetch;
  let i = 0;
  globalThis.fetch = ((_i: unknown, _o?: unknown) =>
    Promise.resolve(steps[Math.min(i++, steps.length - 1)]())) as typeof fetch;
  try {
    return await geminiChat({
      model: "gemini-3.1-flash-lite",
      systemPrompt: "s",
      userPrompt: "u",
      maxTokens: 64,
      timeoutMs: 2000,
    });
  } finally {
    globalThis.fetch = original;
  }
}

Deno.test("geminiChat: SAFETY on the primary then a 503 on the fallback -> blockSeen, NOT refundable", async () => {
  const r = await run(() => json200(SAFETY), () => httpError(503));
  assertEquals(r.content, null);
  assertEquals(r.blockSeen, true);
  assertEquals(refundableGeminiChatFailure(r), false);
});

Deno.test("geminiChat: a 503 on the primary then SAFETY on the fallback -> NOT refundable", async () => {
  const r = await run(() => httpError(503), () => json200(SAFETY));
  assertEquals(r.blockSeen, true);
  assertEquals(refundableGeminiChatFailure(r), false);
});

Deno.test("geminiChat: SAFETY with empty text -> blocked (the empty-text branch carries the finishReason)", async () => {
  const r = await run(() => json200(SAFETY_EMPTY_PARTS));
  assertEquals(r.blockSeen, true);
  assertEquals(refundableGeminiChatFailure(r), false);
});

Deno.test("geminiChat: promptFeedback.blockReason (HTTP 200, no candidates) -> NOT refundable", async () => {
  const r = await run(() => json200(PROMPT_BLOCKED));
  assertEquals(r.blockSeen, true);
  assertEquals(refundableGeminiChatFailure(r), false);
});

Deno.test("geminiChat: 503 on both attempts stays refundable (control: the sticky flag is not always on)", async () => {
  const r = await run(() => httpError(503));
  assertEquals(r.content, null);
  assertEquals(r.blockSeen, false);
  assertEquals(refundableGeminiChatFailure(r), true);
});
