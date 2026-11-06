// supabase/functions/_shared/gemini3_migration_test.ts
//
// Part A (2026-10-01 Gemini 3.x migration) — behavior of gemini.ts, driven
// through the REAL geminiChat / geminiChatWithTools with a scripted fetch that
// records the URL (model) and body of EVERY attempt:
//   - constants + labels
//   - the fallback guard is `model !== MODEL_FALLBACK` (a shared tier slug must NOT
//     remove the fallback), fallbackToLite:false still opts out
//   - HTTP 404 = model unavailable: the model is pruned for the rest of the call,
//     the OTHER attempt still runs, and a pass of only non-429 4xx is never retried
//   - retry classification is PER ATTEMPT (primary 429 + fallback 404 still
//     retries the throttled primary) in BOTH loops
//   - Gemini 3 thought signatures: raw part passthrough, dummy-fill rules, the
//     400-retry safety net
//   - attemptStatuses reach the caller on total failure
//
// Run: deno test --no-check --allow-all --node-modules-dir=none supabase/functions/_shared/gemini3_migration_test.ts

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.env.set("GEMINI_API_KEY", "test-key-not-a-real-secret");

const {
  DUMMY_THOUGHT_SIGNATURE,
  fillMissingThoughtSignature,
  geminiChat,
  geminiChatWithTools,
  labelForModel,
  MODEL_FALLBACK,
  MODEL_FLASH,
  MODEL_FLASH_LITE,
  MODEL_PRO,
} = await import("./gemini.ts");
const { httpError, installFakeFetch, okText, okToolCall } = await import(
  "./gemini_fake_fetch.ts"
);

const PRIMARY = MODEL_FLASH;
const MSGS = [{ role: "user" as const, parts: [{ text: "hi" }] }];
const chat = (extra: Record<string, unknown> = {}) =>
  geminiChat({ model: PRIMARY, systemPrompt: "s", userPrompt: "u", maxTokens: 64, ...extra });
const tools = (extra: Record<string, unknown> = {}) =>
  geminiChatWithTools({ model: PRIMARY, systemPrompt: "s", messages: MSGS, tools: [], ...extra });

// ── constants + labels ───────────────────────────────────────────────────────

Deno.test("constants: every tier is gemini-3.1-flash-lite, the fallback is gemini-3.5-flash-lite", () => {
  assertEquals(MODEL_FLASH, "gemini-3.1-flash-lite");
  assertEquals(MODEL_FLASH_LITE, "gemini-3.1-flash-lite");
  assertEquals(MODEL_PRO, "gemini-3.1-flash-lite");
  assertEquals(MODEL_FALLBACK, "gemini-3.5-flash-lite");
});

Deno.test("labelForModel maps both slugs, tolerates null/unknown", () => {
  assertEquals(labelForModel("gemini-3.1-flash-lite"), "Gemini 3.1 Flash Lite");
  assertEquals(labelForModel("gemini-3.5-flash-lite"), "Gemini 3.5 Flash Lite");
  assertEquals(labelForModel(null), "Gemini");
  assertEquals(labelForModel("some-future-model"), "some-future-model");
});

// ── the fallback guard ───────────────────────────────────────────────────────

Deno.test("geminiChat: a shared tier slug still gets the fallback — attempts are [primary, MODEL_FALLBACK]", async () => {
  const { calls, restore } = installFakeFetch([httpError(503), okText("ok")]);
  try {
    const res = await chat();
    assertEquals(res.content, "ok");
    assertEquals(res.modelUsed, MODEL_FALLBACK);
    assertEquals(calls.map((c) => c.model), [PRIMARY, MODEL_FALLBACK]);
  } finally {
    restore();
  }
});

Deno.test("geminiChat: primary === MODEL_FALLBACK never chains fallback -> fallback; fallbackToLite:false opts out", async () => {
  let f = installFakeFetch([httpError(503)]);
  try {
    await geminiChat({ model: MODEL_FALLBACK, systemPrompt: "s", userPrompt: "u", maxTokens: 8 });
    assertEquals(f.calls.map((c) => c.model), [MODEL_FALLBACK]);
  } finally {
    f.restore();
  }
  f = installFakeFetch([httpError(503)]);
  try {
    await chat({ fallbackToLite: false });
    assertEquals(f.calls.map((c) => c.model), [PRIMARY]);
  } finally {
    f.restore();
  }
});

Deno.test("geminiChatWithTools: same guard — [primary, MODEL_FALLBACK], opt-out honoured", async () => {
  let f = installFakeFetch([httpError(503), okText("ok")]);
  try {
    const r = await tools();
    assertEquals(r.usedFallback, true);
    assertEquals(r.modelUsed, MODEL_FALLBACK);
    assertEquals(f.calls.map((c) => c.model), [PRIMARY, MODEL_FALLBACK]);
  } finally {
    f.restore();
  }
  f = installFakeFetch([okText("ok")]);
  try {
    const r = await tools({ fallbackToLite: false });
    assertEquals(r.usedFallback, false);
    assertEquals(f.calls.map((c) => c.model), [PRIMARY]);
  } finally {
    f.restore();
  }
});

// ── 404 = model unavailable ──────────────────────────────────────────────────

const RETIRED_404 =
  "This model models/gemini-2.5-flash-lite is no longer available to new users. Please update your code to use models/gemini-3.5-flash-lite.";

Deno.test("geminiChat: a 404 primary falls to the fallback exactly once and is NOT retried (retries:2)", async () => {
  const { calls, restore } = installFakeFetch([httpError(404, RETIRED_404), okText("ok")]);
  try {
    const res = await chat({ retries: 2 });
    assertEquals(res.content, "ok");
    assertEquals(calls.map((c) => c.model), [PRIMARY, MODEL_FALLBACK]);
  } finally {
    restore();
  }
});

Deno.test("geminiChat: both 404 -> null, ONE pass only (not 3), attemptStatuses carries both 404s", async () => {
  const { calls, restore } = installFakeFetch([httpError(404, RETIRED_404)]);
  try {
    const res = await chat({ retries: 2 });
    assertEquals(res.content, null);
    assertEquals(calls.length, 2);
    assertEquals(res.attemptStatuses, [
      { model: PRIMARY, status: 404 },
      { model: MODEL_FALLBACK, status: 404 },
    ]);
    assertEquals(res.lastError?.status, 404);
  } finally {
    restore();
  }
});

Deno.test("geminiChat: a pass whose every failure is a non-429 4xx is never retried", async () => {
  const { calls, restore } = installFakeFetch([httpError(400)]);
  try {
    const res = await chat({ retries: 2 });
    assertEquals(res.content, null);
    assertEquals(calls.length, 2);
  } finally {
    restore();
  }
});

Deno.test("geminiChat: per-attempt retry — primary 429 + fallback 404 STILL retries the throttled primary (and skips the pruned fallback)", async () => {
  const { calls, restore } = installFakeFetch([httpError(429), httpError(404), okText("ok")]);
  try {
    const res = await chat({ retries: 1 });
    assertEquals(res.content, "ok");
    assertEquals(res.modelUsed, PRIMARY);
    assertEquals(calls.map((c) => c.model), [PRIMARY, MODEL_FALLBACK, PRIMARY]);
  } finally {
    restore();
  }
});

Deno.test("geminiChat: a transient null (transport throw) + 404 reports statuses [null, 404] and still retries", async () => {
  const { calls, restore } = installFakeFetch(["throw", httpError(404), "throw"]);
  try {
    const res = await chat({ retries: 1 });
    assertEquals(res.content, null);
    assertEquals(calls.map((c) => c.model), [PRIMARY, MODEL_FALLBACK, PRIMARY]);
    assertEquals(res.attemptStatuses, [
      { model: PRIMARY, status: null },
      { model: MODEL_FALLBACK, status: 404 },
      { model: PRIMARY, status: null },
    ]);
  } finally {
    restore();
  }
});

Deno.test("geminiChatWithTools: per-attempt retry — primary 429 + fallback 404 retries the primary only; success returns", async () => {
  const { calls, restore } = installFakeFetch([httpError(429), httpError(404), okText("ok")]);
  try {
    const r = await tools();
    assertEquals(r.text, "ok");
    assertEquals(r.modelUsed, PRIMARY);
    assertEquals(r.usedFallback, false);
    assertEquals(calls.map((c) => c.model), [PRIMARY, MODEL_FALLBACK, PRIMARY]);
  } finally {
    restore();
  }
});

Deno.test("geminiChatWithTools: both 404 -> throws once with attemptStatuses + status 404, no second pass", async () => {
  const { calls, restore } = installFakeFetch([httpError(404, RETIRED_404)]);
  try {
    let caught: unknown = null;
    try {
      await tools();
    } catch (e) {
      caught = e;
    }
    assert(caught instanceof Error);
    const e = caught as Error & { status?: number; attemptStatuses?: unknown };
    assertEquals(e.status, 404);
    assertEquals(e.attemptStatuses, [
      { model: PRIMARY, status: 404 },
      { model: MODEL_FALLBACK, status: 404 },
    ]);
    assertEquals(calls.length, 2);
  } finally {
    restore();
  }
});

Deno.test("geminiChatWithTools: 404 primary + 503 fallback keeps the 404 in attemptStatuses (a transient last status must not hide a retired model)", async () => {
  const { calls, restore } = installFakeFetch([httpError(404, RETIRED_404), httpError(503)]);
  try {
    let caught: unknown = null;
    try {
      await tools();
    } catch (e) {
      caught = e;
    }
    const e = caught as Error & { status?: number; attemptStatuses?: Array<{ status: number | null }> };
    assertEquals(e.status, 503);
    assertEquals(e.attemptStatuses?.some((a) => a.status === 404), true);
    // The 404'd primary is PRUNED for the retry pass: pass 1 calls only the
    // fallback ([P, F, F]) — without the prune it would be [P, F, P, F].
    assertEquals(calls.map((c) => c.model), [PRIMARY, MODEL_FALLBACK, MODEL_FALLBACK]);
  } finally {
    restore();
  }
});

// ── Gemini 3 thought signatures ──────────────────────────────────────────────

const SIG = "OPAQUE-SIGNATURE-FROM-GEMINI";

Deno.test("signatures: a functionCall part is returned RAW (signature beside functionCall); accessors stay name/args only", async () => {
  const { restore } = installFakeFetch([okToolCall("logSet", { reps: 5 }, SIG)]);
  try {
    const r = await tools();
    assertEquals(r.parts, [{ functionCall: { name: "logSet", args: { reps: 5 } }, thoughtSignature: SIG }]);
    assertEquals(r.functionCalls, [{ name: "logSet", args: { reps: 5 } }]);
  } finally {
    restore();
  }
});

Deno.test("signatures: text-part signature and a signature-only part are kept raw too", async () => {
  const { restore } = installFakeFetch([{
    status: 200,
    json: {
      candidates: [{
        content: {
          parts: [
            { text: "thinking out loud", thoughtSignature: "T1" },
            { thoughtSignature: "ONLY" },
            { functionCall: { name: "n", args: {} } },
          ],
        },
      }],
      usageMetadata: { totalTokenCount: 3 },
    },
  }]);
  try {
    const r = await tools();
    assertEquals(r.parts[0], { text: "thinking out loud", thoughtSignature: "T1" });
    assertEquals(r.parts[1], { thoughtSignature: "ONLY" });
  } finally {
    restore();
  }
});

Deno.test("signatures: the replayed model turn in round 2's REQUEST body still carries the signature Gemini sent", async () => {
  const { calls, restore } = installFakeFetch([okToolCall("logSet", { reps: 5 }, SIG), okText("done")]);
  try {
    const r1 = await tools();
    const history = [
      ...MSGS,
      { role: "model" as const, parts: r1.parts },
      { role: "user" as const, parts: [{ functionResponse: { name: "logSet", response: { ok: true } } }] },
    ];
    await tools({ messages: history });
    const sent = calls[1].body.contents[1].parts[0];
    assertEquals(sent.thoughtSignature, SIG);
    assertEquals(sent.functionCall, { name: "logSet", args: { reps: 5 } });
  } finally {
    restore();
  }
});

Deno.test("fillMissingThoughtSignature: only the FIRST functionCall, only when no part carries a signature, never mutating input", () => {
  const noSig = [{ functionCall: { name: "a", args: {} } }, { functionCall: { name: "b", args: {} } }];
  const filled = fillMissingThoughtSignature(noSig as never);
  assertEquals((filled[0] as { thoughtSignature?: string }).thoughtSignature, DUMMY_THOUGHT_SIGNATURE);
  assertEquals((filled[1] as { thoughtSignature?: string }).thoughtSignature, undefined);
  assertEquals((noSig[0] as { thoughtSignature?: string }).thoughtSignature, undefined); // input untouched

  // parallel calls: one signature on the first call -> untouched
  const parallel = [
    { functionCall: { name: "a", args: {} }, thoughtSignature: "REAL" },
    { functionCall: { name: "b", args: {} } },
  ];
  assertEquals(fillMissingThoughtSignature(parallel as never), parallel as never);

  // a signature anywhere in the turn (here on a text part) -> untouched
  const onText = [{ text: "x", thoughtSignature: "T" }, { functionCall: { name: "a", args: {} } }];
  assertEquals(fillMissingThoughtSignature(onText as never), onText as never);

  // text-only turn -> untouched
  const textOnly = [{ text: "just text" }];
  assertEquals(fillMissingThoughtSignature(textOnly as never), textOnly as never);
});

Deno.test("safety net: a 400 'missing a thought_signature' retries THAT attempt once with the dummy signature", async () => {
  const sigError = httpError(
    400,
    "Function call is missing a thought_signature in functionCall parts.",
  );
  const { calls, restore } = installFakeFetch([httpError(503), sigError, okText("ok")]);
  try {
    const history = [
      ...MSGS,
      { role: "model" as const, parts: [{ functionCall: { name: "logSet", args: {} } }] },
      { role: "user" as const, parts: [{ functionResponse: { name: "logSet", response: {} } }] },
    ];
    const r = await tools({ messages: history });
    assertEquals(r.text, "ok");
    assertEquals(r.modelUsed, MODEL_FALLBACK);
    assertEquals(calls.map((c) => c.model), [PRIMARY, MODEL_FALLBACK, MODEL_FALLBACK]);
    assertEquals(calls[1].body.contents[1].parts[0].thoughtSignature, undefined);
    assertEquals(calls[2].body.contents[1].parts[0].thoughtSignature, DUMMY_THOUGHT_SIGNATURE);
  } finally {
    restore();
  }
});

Deno.test("safety net does NOT fire on an unrelated 400", async () => {
  const { calls, restore } = installFakeFetch([httpError(400, "Request contains an invalid argument.")]);
  try {
    let threw = false;
    try {
      await tools();
    } catch {
      threw = true;
    }
    assert(threw);
    assertEquals(calls.length, 2); // primary + fallback, no dummy retry of either
  } finally {
    restore();
  }
});

// ── usage logging ────────────────────────────────────────────────────────────

Deno.test("usage logging defaults absent cached/thought counts to 0 and never throws", async () => {
  const logs: string[] = [];
  const origLog = console.log;
  console.log = (...a: unknown[]) => logs.push(a.join(" "));
  const { restore } = installFakeFetch([okText("ok", { totalTokenCount: 9, promptTokenCount: 7 })]);
  try {
    await chat({ fallbackToLite: false });
  } finally {
    console.log = origLog;
    restore();
  }
  const line = logs.find((l) => l.startsWith("[gemini] usage"));
  assert(line, "expected a [gemini] usage log line");
  assert(line.includes("cached=0") && line.includes("thoughts=0") && line.includes("total=9"), line);
});

// ═════════════════════════════════════════════════════════════════════════════
// B-pass round (2026-10-01) additions — gaps found by mutating the first round.
// ═════════════════════════════════════════════════════════════════════════════

const SIG_ERR = httpError(400, "Function call is missing a thought_signature in functionCall parts.");
const UNSIGNED_HISTORY = [
  ...MSGS,
  { role: "model" as const, parts: [{ functionCall: { name: "logSet", args: {} } }] },
  { role: "user" as const, parts: [{ functionResponse: { name: "logSet", response: {} } }] },
];
const sigOf = (call: { body: { contents: Array<{ role: string; parts: Array<{ thoughtSignature?: string }> }> } }) =>
  call.body.contents.find((c) => c.role === "model")?.parts[0].thoughtSignature;

Deno.test("signature 400 on the PRIMARY attempt retries the primary once with the dummy", async () => {
  const { calls, restore } = installFakeFetch([SIG_ERR, okText("ok")]);
  try {
    const r = await tools({ messages: UNSIGNED_HISTORY });
    assertEquals(r.modelUsed, PRIMARY);
    assertEquals(r.usedFallback, false);
    assertEquals(calls.map((c) => c.model), [PRIMARY, PRIMARY]);
    assertEquals(sigOf(calls[0]), undefined);
    assertEquals(sigOf(calls[1]), DUMMY_THOUGHT_SIGNATURE);
  } finally {
    restore();
  }
});

Deno.test("the dummy history is REMEMBERED: after a signature 400, the fallback and later passes send it straight away", async () => {
  // primary: sig400 -> dummy retry 429 ; fallback: must already carry the dummy
  const { calls, restore } = installFakeFetch([SIG_ERR, httpError(429), okText("ok")]);
  try {
    const r = await tools({ messages: UNSIGNED_HISTORY });
    assertEquals(r.modelUsed, MODEL_FALLBACK);
    assertEquals(calls.map((c) => c.model), [PRIMARY, PRIMARY, MODEL_FALLBACK]);
    assertEquals(sigOf(calls[2]), DUMMY_THOUGHT_SIGNATURE);
  } finally {
    restore();
  }
});

Deno.test("a signature 400 is NOT retried when the fill would change nothing (no identical re-send)", async () => {
  const signed = [
    ...MSGS,
    { role: "model" as const, parts: [{ functionCall: { name: "logSet", args: {} }, thoughtSignature: "REAL" }] },
    { role: "user" as const, parts: [{ functionResponse: { name: "logSet", response: {} } }] },
  ];
  const { calls, restore } = installFakeFetch([SIG_ERR]);
  try {
    let threw = false;
    try {
      await tools({ messages: signed });
    } catch {
      threw = true;
    }
    assert(threw);
    assertEquals(calls.map((c) => c.model), [PRIMARY, MODEL_FALLBACK]);
  } finally {
    restore();
  }
});

Deno.test("the safety net's FORCED fill covers [text(sig), functionCall(unsigned)] — a turn the default fill leaves alone", async () => {
  const mixed = [
    ...MSGS,
    {
      role: "model" as const,
      parts: [{ text: "ok", thoughtSignature: "ON-TEXT" }, { functionCall: { name: "logSet", args: {} } }],
    },
    { role: "user" as const, parts: [{ functionResponse: { name: "logSet", response: {} } }] },
  ];
  const { calls, restore } = installFakeFetch([SIG_ERR, okText("ok")]);
  try {
    const r = await tools({ messages: mixed });
    assertEquals(r.text, "ok");
    const modelTurn = (c: (typeof calls)[number]) => c.body.contents.find((x: { role: string }) => x.role === "model");
    assertEquals(modelTurn(calls[0]).parts[1].thoughtSignature, undefined);
    assertEquals(modelTurn(calls[1]).parts[1].thoughtSignature, DUMMY_THOUGHT_SIGNATURE);
    assertEquals(modelTurn(calls[1]).parts[0].thoughtSignature, "ON-TEXT"); // real one untouched
  } finally {
    restore();
  }
});

Deno.test("signature detection survives the 200-char preview cut and the spaced spelling", async () => {
  const long = "x".repeat(400) + " Function call is missing a thought signature in functionCall parts.";
  const { calls, restore } = installFakeFetch([httpError(400, long), okText("ok")]);
  try {
    await tools({ messages: UNSIGNED_HISTORY });
    assertEquals(calls.length, 2);
    assertEquals(sigOf(calls[1]), DUMMY_THOUGHT_SIGNATURE);
  } finally {
    restore();
  }
});

Deno.test("fillMissingThoughtSignature: a signature on a LATER part leaves the turn untouched (same reference); force still fills the unsigned call", () => {
  const textThenCall = [{ text: "t" }, { functionCall: { name: "a", args: {} }, thoughtSignature: "REAL" }];
  assert(fillMissingThoughtSignature(textThenCall as never) === (textThenCall as never));
  const callsAB = [{ functionCall: { name: "a", args: {} } }, { functionCall: { name: "b", args: {} }, thoughtSignature: "REAL" }];
  assert(fillMissingThoughtSignature(callsAB as never) === (callsAB as never));
  const forced = fillMissingThoughtSignature(callsAB as never, { force: true });
  assertEquals((forced[0] as { thoughtSignature?: string }).thoughtSignature, DUMMY_THOUGHT_SIGNATURE);
  assertEquals((forced[1] as { thoughtSignature?: string }).thoughtSignature, "REAL");
});

Deno.test("an empty-text part that only carries a signature is NOT a terminal reply on the tools path (mirrors geminiChat's !text)", async () => {
  for (
    const parts of [
      [{ text: "", thoughtSignature: "S" }],
      [{ thoughtSignature: "ONLY" }],
      [{ text: "   " }],
    ]
  ) {
    const { calls, restore } = installFakeFetch([
      { status: 200, json: { candidates: [{ content: { parts } }], usageMetadata: { totalTokenCount: 1 } } },
      okText("real"),
    ]);
    try {
      const r = await tools();
      assertEquals(r.text, "real");
      assertEquals(r.modelUsed, MODEL_FALLBACK);
      assertEquals(calls.length, 2);
    } finally {
      restore();
    }
  }
});

Deno.test("geminiChat: 5xx on every attempt IS retried (pass 2), 408 too — and a 403 primary is not pruned", async () => {
  let f = installFakeFetch([httpError(503), httpError(503), okText("ok")]);
  try {
    const res = await chat({ retries: 1 });
    assertEquals(res.content, "ok");
    assertEquals(f.calls.map((c) => c.model), [PRIMARY, MODEL_FALLBACK, PRIMARY]);
  } finally {
    f.restore();
  }
  f = installFakeFetch([httpError(408)]);
  try {
    await chat({ retries: 1 });
    assertEquals(f.calls.length, 4);
  } finally {
    f.restore();
  }
  // 403 is not "model unavailable": the primary stays in the list for pass 2
  f = installFakeFetch([httpError(403), httpError(503), okText("ok")]);
  try {
    const res = await chat({ retries: 1 });
    assertEquals(res.content, "ok");
    assertEquals(f.calls.map((c) => c.model), [PRIMARY, MODEL_FALLBACK, PRIMARY]);
  } finally {
    f.restore();
  }
});

Deno.test("geminiChat: a deterministic SAFETY block is NOT retried; an empty MAX_TOKENS candidate (the FC1 symptom) still is", async () => {
  let f = installFakeFetch([{ status: 200, json: { candidates: [{ finishReason: "SAFETY" }] } }]);
  try {
    const res = await chat({ retries: 2 });
    assertEquals(res.content, null);
    assertEquals(res.deterministicFailure, true);
    assertEquals(f.calls.length, 2); // one pass: primary + fallback
  } finally {
    f.restore();
  }
  f = installFakeFetch([{ status: 200, json: { candidates: [{ finishReason: "MAX_TOKENS" }] } }]);
  try {
    const res = await chat({ retries: 1 });
    assertEquals(res.deterministicFailure, false);
    assertEquals(f.calls.length, 4);
  } finally {
    f.restore();
  }
});

// ── wall-clock deadlines (both loops) ────────────────────────────────────────

function withFakeClock(msPerCall: number): () => void {
  const realNow = Date.now;
  const innerFetch = globalThis.fetch;
  let t = realNow();
  Date.now = () => t;
  globalThis.fetch = ((...a: Parameters<typeof fetch>) => {
    t += msPerCall;
    return innerFetch(...a);
  }) as typeof fetch;
  return () => {
    Date.now = realNow;
    globalThis.fetch = innerFetch;
  };
}

Deno.test("geminiChat: no extra pass once the 20 s retry budget is spent", async () => {
  const f = installFakeFetch([httpError(503)]);
  const undo = withFakeClock(25_000);
  try {
    const res = await chat({ retries: 2 });
    assertEquals(res.content, null);
    assertEquals(f.calls.length, 2);
  } finally {
    undo();
    f.restore();
  }
});

Deno.test("geminiChatWithTools: no second pass once the 20 s retry budget is spent", async () => {
  const f = installFakeFetch([httpError(503)]);
  const undo = withFakeClock(25_000);
  try {
    let threw = false;
    try {
      await tools();
    } catch {
      threw = true;
    }
    assert(threw);
    assertEquals(f.calls.length, 2);
  } finally {
    undo();
    f.restore();
  }
});

// ── shapes the real API can send ─────────────────────────────────────────────

Deno.test("absent / null usageMetadata never fails a successful call (both entry points) and the tools path logs usage", async () => {
  const logs: string[] = [];
  const origLog = console.log;
  console.log = (...a: unknown[]) => logs.push(a.join(" "));
  for (const usageMetadata of [undefined, null]) {
    const { restore } = installFakeFetch([
      { status: 200, json: { candidates: [{ content: { parts: [{ text: "ok" }] } }], usageMetadata } },
    ]);
    try {
      assertEquals((await chat({ fallbackToLite: false })).content, "ok");
      assertEquals((await tools({ fallbackToLite: false })).text, "ok");
    } finally {
      restore();
    }
  }
  console.log = origLog;
  assert(logs.some((l) => l.startsWith("[gemini] usage tools")), "tools path must log usage");
  assert(logs.some((l) => l.startsWith("[gemini] usage single")), "single path must log usage");
});

Deno.test("a functionCall WITHOUT args (zero-arg tool) yields args:{} in both parts and functionCalls", async () => {
  const { restore } = installFakeFetch([
    {
      status: 200,
      json: { candidates: [{ content: { parts: [{ functionCall: { name: "getStreak" } }] } }], usageMetadata: { totalTokenCount: 1 } },
    },
  ]);
  try {
    const r = await tools();
    assertEquals(r.functionCalls, [{ name: "getStreak", args: {} }]);
    assertEquals((r.parts[0] as { functionCall: { args: unknown } }).functionCall.args, {});
  } finally {
    restore();
  }
});

// ── logging ──────────────────────────────────────────────────────────────────

Deno.test("a 404 emits the structured [gemini] MODEL_UNAVAILABLE line in both loops", async () => {
  const warns: string[] = [];
  const origWarn = console.warn;
  console.warn = (...a: unknown[]) => warns.push(a.join(" "));
  const f1 = installFakeFetch([httpError(404, RETIRED_404), okText("ok")]);
  try {
    await chat();
  } finally {
    f1.restore();
  }
  const f2 = installFakeFetch([httpError(404, RETIRED_404), okText("ok")]);
  try {
    await tools();
  } finally {
    f2.restore();
    console.warn = origWarn;
  }
  const lines = warns.filter((w) => w.includes("[gemini] MODEL_UNAVAILABLE model=" + PRIMARY));
  assertEquals(lines.length, 2);
});

Deno.test("geminiChat's 'trying fallback' / 'attempt list exhausted' line reflects the position in the pass, not the pruned list", async () => {
  const warns: string[] = [];
  const origWarn = console.warn;
  console.warn = (...a: unknown[]) => warns.push(a.join(" "));
  const f = installFakeFetch([httpError(503), httpError(404)]);
  try {
    await chat();
  } finally {
    f.restore();
    console.warn = origWarn;
  }
  const nulls = warns.filter((w) => w.includes("returned null"));
  assertEquals(nulls.length, 2);
  assert(nulls[0].includes(PRIMARY) && nulls[0].includes("trying fallback"), nulls[0]);
  assert(nulls[1].includes(MODEL_FALLBACK) && nulls[1].includes("attempt list exhausted"), nulls[1]);
});
