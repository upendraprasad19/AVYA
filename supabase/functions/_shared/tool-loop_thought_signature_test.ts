// supabase/functions/_shared/tool-loop_thought_signature_test.ts
//
// Gemini 3 thought signatures through the REAL runToolLoop (2026-10-01).
// Probe v2: replaying a model turn whose functionCall part lacks the signature
// is an HTTP 400 on every Gemini 3 model. Before this fix tool-loop stored a
// rebuilt `{functionCall:{name,args}}` (signature dropped) so EVERY tool-using
// chat turn would have 400'd. Pinned here:
//   1. round 2's request carries the exact signature Gemini sent in round 1;
//   2. a model turn with NO signature gets the documented dummy on its first call
//      (defensive net) and a turn that has one is left alone;
//   3. the signature never reaches anything the caller persists or returns
//      (toolCallsLog / intents / text) — it lives only in the in-memory history.
//
// Run: deno test --no-check --allow-all --node-modules-dir=none supabase/functions/_shared/tool-loop_thought_signature_test.ts

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.env.set("GEMINI_API_KEY", "test-key-not-a-real-secret");

const { runToolLoop } = await import("./tool-loop.ts");
const { DUMMY_THOUGHT_SIGNATURE, MODEL_FLASH } = await import("./gemini.ts");
const { installFakeFetch, okText, okToolCall } = await import("./gemini_fake_fetch.ts");
import type { ToolContext } from "./tools/types.ts";

const ctx: ToolContext = {
  userId: "test-user",
  isPro: false,
  // deno-lint-ignore no-explicit-any
  sb: null as any,
  requestId: "test-req-sig",
};
const LOG_SET = { exerciseId: "bench_press", weightKg: 80, reps: 10, sets: 4 };
const SIG = "SIGNATURE-MINTED-IN-ROUND-1";

Deno.test("round 2 replays the model turn with the EXACT signature Gemini sent in round 1", async () => {
  const { calls, restore } = installFakeFetch([okToolCall("logSet", LOG_SET, SIG), okText("Logged.")]);
  try {
    const result = await runToolLoop({
      systemPrompt: "you are The Captain",
      userMessage: "log my bench",
      ctx,
      model: MODEL_FLASH,
    });
    assertEquals(result.text, "Logged.");
    assertEquals(calls.length, 2);
    const modelTurn = calls[1].body.contents.find((c: { role: string }) => c.role === "model");
    assertEquals(modelTurn.parts[0].thoughtSignature, SIG);
    assertEquals(modelTurn.parts[0].functionCall.name, "logSet");
  } finally {
    restore();
  }
});

Deno.test("a turn with NO signature gets the dummy on its first functionCall at store time", async () => {
  const { calls, restore } = installFakeFetch([okToolCall("logSet", LOG_SET), okText("Logged.")]);
  try {
    await runToolLoop({ systemPrompt: "s", userMessage: "log", ctx, model: MODEL_FLASH });
    const modelTurn = calls[1].body.contents.find((c: { role: string }) => c.role === "model");
    assertEquals(modelTurn.parts[0].thoughtSignature, DUMMY_THOUGHT_SIGNATURE);
  } finally {
    restore();
  }
});

Deno.test("the signature never reaches the result's toolCallsLog / intents / text, nor the dummy", async () => {
  const { restore } = installFakeFetch([okToolCall("logSet", LOG_SET, SIG), okText("Logged.")]);
  try {
    const result = await runToolLoop({ systemPrompt: "s", userMessage: "log", ctx, model: MODEL_FLASH });
    const persisted = JSON.stringify({
      toolCallsLog: result.toolCallsLog,
      intents: result.intents,
      text: result.text,
    });
    assertEquals(persisted.includes(SIG), false);
    assertEquals(persisted.includes("thoughtSignature"), false);
    assertEquals(persisted.includes(DUMMY_THOUGHT_SIGNATURE), false);
  } finally {
    restore();
  }
});

Deno.test("modelUsed reports the slug that answered the last round", async () => {
  const { restore } = installFakeFetch([okToolCall("logSet", LOG_SET, SIG), okText("Logged.")]);
  try {
    const result = await runToolLoop({ systemPrompt: "s", userMessage: "log", ctx, model: MODEL_FLASH });
    assertEquals(result.modelUsed, MODEL_FLASH);
    assertEquals(result.usedFallback, false);
  } finally {
    restore();
  }
});
