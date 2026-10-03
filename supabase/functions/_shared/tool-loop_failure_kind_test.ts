// supabase/functions/_shared/tool-loop_failure_kind_test.ts
//
// Part B (gemini3-limits-caching): `ToolLoopResult.failureKind` decides whether a
// hard-failed chat turn gets its quota unit back. ONLY `transport` refunds.
// Pinned end to end through runToolLoop with a mocked fetch, one case per class:
//
//   persistent 429 / 503 / 404  -> "transport"       (refundable)
//   persistent SAFETY candidate -> "deterministic"   (user's input; no refund)
//   persistent 400              -> "deterministic"   (a request we built; no refund)
//   401 / 403 / 400 API_KEY_INVALID -> "transport"   (OUR credential failed; refunds)
//   promptFeedback block / IMAGE_SAFETY / empty-parts SAFETY / MAX_TOKENS -> "deterministic"
//   SAFETY then 404 / 503 (fallback) and 503 then SAFETY -> "deterministic" (sticky block)
//   rounds exhausted            -> "rounds_exhausted" (model kept calling tools)
//   happy path                  -> "none"
//
// Run: deno test --no-check --allow-env --node-modules-dir=none
//      supabase/functions/_shared/tool-loop_failure_kind_test.ts

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.env.set("GEMINI_API_KEY", "test-key-not-a-real-secret");

const { runToolLoop } = await import("./tool-loop.ts");
import type { ToolContext } from "./tools/types.ts";

function httpError(status: number, bodyText = "err"): Response {
  return {
    ok: false,
    status,
    text: () => Promise.resolve(bodyText),
    json: () => Promise.resolve({}),
  } as unknown as Response;
}

function json200(body: unknown): Response {
  return {
    ok: true,
    status: 200,
    text: () => Promise.resolve(""),
    json: () => Promise.resolve(body),
  } as unknown as Response;
}

function withFetch(
  impl: () => Response,
): { restore: () => void } {
  const original = globalThis.fetch;
  globalThis.fetch = ((_i: unknown, _o?: unknown) => Promise.resolve(impl())) as typeof fetch;
  return { restore: () => (globalThis.fetch = original) };
}

const ctx: ToolContext = {
  userId: "test-user",
  isPro: false,
  // deno-lint-ignore no-explicit-any
  sb: null as any,
  requestId: "test-req",
};

async function run(impl: () => Response, maxRounds?: number) {
  const { restore } = withFetch(impl);
  try {
    return await runToolLoop({
      systemPrompt: "you are The Captain",
      userMessage: "hi",
      ctx,
      model: "gemini-3.1-flash-lite",
      maxRounds,
    });
  } finally {
    restore();
  }
}

for (const status of [429, 503, 404, 401, 403]) {
  Deno.test(`failureKind: persistent HTTP ${status} -> transport (refundable)`, async () => {
    const r = await run(() => httpError(status));
    assertEquals(r.hadHardFailure, true);
    assertEquals(r.failureKind, "transport");
  });
}

Deno.test("failureKind: persistent SAFETY block -> deterministic (never refunded)", async () => {
  const r = await run(() =>
    json200({ candidates: [{ finishReason: "SAFETY" }], usageMetadata: { totalTokenCount: 1 } })
  );
  assertEquals(r.hadHardFailure, true);
  assertEquals(r.failureKind, "deterministic");
});

Deno.test("failureKind: persistent HTTP 400 -> deterministic (a request we built; never refunded)", async () => {
  const r = await run(() => httpError(400));
  assertEquals(r.hadHardFailure, true);
  assertEquals(r.failureKind, "deterministic");
});

Deno.test("failureKind: an UNKNOWN-reason empty candidate is transport (retriable, user did not cause it)", async () => {
  const r = await run(() => json200({ candidates: [{}], usageMetadata: { totalTokenCount: 1 } }));
  assertEquals(r.hadHardFailure, true);
  assertEquals(r.failureKind, "transport");
});

Deno.test("failureKind: rounds exhausted -> rounds_exhausted (never refunded)", async () => {
  const r = await run(
    () =>
      json200({
        candidates: [{
          content: { parts: [{ functionCall: { name: "getFormCues", args: { exercise_name: "Bench Press" } } }] },
        }],
        usageMetadata: { totalTokenCount: 1 },
      }),
    2,
  );
  assertEquals(r.hadHardFailure, true);
  assertEquals(r.failureKind, "rounds_exhausted");
});

Deno.test("failureKind: happy path -> none", async () => {
  const r = await run(() =>
    json200({
      candidates: [{ content: { parts: [{ text: "Hey Recruit." }] } }],
      usageMetadata: { totalTokenCount: 5 },
    })
  );
  assertEquals(r.hadHardFailure, false);
  assertEquals(r.failureKind, "none");
});

Deno.test("failureKind: HTTP 400 API_KEY_INVALID (our revoked key) -> transport (refundable)", async () => {
  const r = await run(() => httpError(400, '{"error":{"status":"INVALID_ARGUMENT","message":"API key not valid. API_KEY_INVALID"}}'));
  assertEquals(r.hadHardFailure, true);
  assertEquals(r.failureKind, "transport");
});

Deno.test("failureKind: promptFeedback.blockReason (HTTP 200, NO candidates) -> deterministic", async () => {
  const r = await run(() =>
    json200({ promptFeedback: { blockReason: "PROHIBITED_CONTENT" }, usageMetadata: { totalTokenCount: 1 } })
  );
  assertEquals(r.hadHardFailure, true);
  assertEquals(r.failureKind, "deterministic");
});

for (const fr of ["IMAGE_SAFETY", "MAX_TOKENS", "LANGUAGE", "MALFORMED_FUNCTION_CALL"]) {
  Deno.test(`failureKind: finishReason ${fr} -> never refundable`, async () => {
    const r = await run(() => json200({ candidates: [{ finishReason: fr }], usageMetadata: { totalTokenCount: 1 } }));
    assertEquals(r.hadHardFailure, true);
    assertEquals(r.failureKind, "deterministic");
  });
}

Deno.test("failureKind: SAFETY with an EMPTY parts array -> deterministic (not a transient empty)", async () => {
  const r = await run(() =>
    json200({ candidates: [{ finishReason: "SAFETY", content: { parts: [] } }], usageMetadata: { totalTokenCount: 1 } })
  );
  assertEquals(r.hadHardFailure, true);
  assertEquals(r.failureKind, "deterministic");
});

const SAFETY_BODY = { candidates: [{ finishReason: "SAFETY" }], usageMetadata: { totalTokenCount: 1 } };

function sequence(...steps: Array<() => Response>): () => Response {
  let i = 0;
  return () => steps[Math.min(i++, steps.length - 1)]();
}

Deno.test("failureKind: SAFETY on the primary then a transport failure on the fallback -> deterministic (no laundering)", async () => {
  for (const status of [404, 503]) {
    const r = await run(sequence(() => json200(SAFETY_BODY), () => httpError(status)));
    assertEquals(r.hadHardFailure, true, `status ${status}`);
    assertEquals(r.failureKind, "deterministic", `SAFETY -> ${status}`);
  }
});

Deno.test("failureKind: a transport failure THEN a SAFETY block -> deterministic (the block is sticky)", async () => {
  const r = await run(sequence(() => httpError(503), () => json200(SAFETY_BODY)));
  assertEquals(r.hadHardFailure, true);
  assertEquals(r.failureKind, "deterministic");
});
