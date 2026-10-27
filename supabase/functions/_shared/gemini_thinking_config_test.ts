// supabase/functions/_shared/gemini_thinking_config_test.ts
//
// Thinking config, Gemini 3.x (rewritten 2026-10-01; originally FC1, diagnose
// 7fbe21, which keyed on MODEL_PRO identity and `thinkingBudget: 0`).
//
// Facts pinned here (probe v2/v3 on the new key):
//   - `thinkingLevel: "minimal"` = off, `"low"` = on, accepted by BOTH Lite models.
//   - `thinkingBudget: 0` is REJECTED (HTTP 400) by gemini-3.5-flash-lite, so it
//     must never be sent — the fallback attempt would 400 on every call.
//   - The config follows the ATTEMPT's model (THINKING_BY_MODEL), never the
//     primary's, and per-call `thinking` replaces the old "not MODEL_PRO" test
//     (every tier now shares one slug, so identity can no longer tell tiers apart).
//
// Behavioral: a fake fetch records the URL + body of EVERY attempt.

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.env.set("GEMINI_API_KEY", "test-key-not-a-real-secret");

const gemini = await import("./gemini.ts");
const {
  geminiChat,
  geminiChatWithTools,
  MODEL_FLASH,
  MODEL_FLASH_LITE,
  MODEL_PRO,
  MODEL_FALLBACK,
  THINKING_BY_MODEL,
  thinkingConfigFor,
} = gemini;
const { installFakeFetch, okText, httpError } = await import("./gemini_fake_fetch.ts");

const tc = (call: { body: { generationConfig?: { thinkingConfig?: unknown } } }) =>
  call.body.generationConfig?.thinkingConfig;

Deno.test("geminiChat — default thinking is OFF = {thinkingLevel:'minimal'}, never thinkingBudget", async () => {
  const { calls, restore } = installFakeFetch([okText("ok")]);
  try {
    const res = await geminiChat({
      model: MODEL_FLASH,
      systemPrompt: "s",
      userPrompt: "hi",
      maxTokens: 1024,
      fallbackToLite: false,
    });
    assertEquals(res.content, "ok");
    assertEquals(calls.length, 1);
    assertEquals(tc(calls[0]), { thinkingLevel: "minimal" });
    assertEquals(JSON.stringify(calls[0].body).includes("thinkingBudget"), false);
  } finally {
    restore();
  }
});

Deno.test("geminiChat — thinking:'on' sends {thinkingLevel:'low'} (weekly-report path)", async () => {
  const { calls, restore } = installFakeFetch([okText("ok")]);
  try {
    await geminiChat({
      model: MODEL_PRO,
      systemPrompt: "s",
      userPrompt: "hi",
      maxTokens: 4096,
      thinking: "on",
      fallbackToLite: false,
    });
    assertEquals(tc(calls[0]), { thinkingLevel: "low" });
  } finally {
    restore();
  }
});

Deno.test("geminiChat — the FALLBACK attempt resolves its OWN row, not the primary's", async () => {
  // Make the two rows differ for the duration of the test so inheritance is visible.
  const saved = THINKING_BY_MODEL[MODEL_FALLBACK].off;
  THINKING_BY_MODEL[MODEL_FALLBACK].off = { thinkingLevel: "high" };
  const { calls, restore } = installFakeFetch([httpError(503), okText("ok")]);
  try {
    const res = await geminiChat({
      model: MODEL_FLASH,
      systemPrompt: "s",
      userPrompt: "hi",
      maxTokens: 1024,
    });
    assertEquals(res.content, "ok");
    assertEquals(res.modelUsed, MODEL_FALLBACK);
    assertEquals(calls.map((c) => c.model), [MODEL_FLASH, MODEL_FALLBACK]);
    assertEquals(tc(calls[0]), { thinkingLevel: "minimal" });
    assertEquals(tc(calls[1]), { thinkingLevel: "high" });
  } finally {
    THINKING_BY_MODEL[MODEL_FALLBACK].off = saved;
    restore();
  }
});

Deno.test("geminiChatWithTools — fallback attempt resolves its own row and thinking:'on' is honoured per attempt", async () => {
  const saved = THINKING_BY_MODEL[MODEL_FALLBACK].on;
  THINKING_BY_MODEL[MODEL_FALLBACK].on = { thinkingLevel: "high" };
  const { calls, restore } = installFakeFetch([httpError(503), okText("ok")]);
  try {
    const res = await geminiChatWithTools({
      model: MODEL_FLASH,
      systemPrompt: "s",
      messages: [{ role: "user", parts: [{ text: "hi" }] }],
      tools: [],
      thinking: "on",
    });
    assertEquals(res.usedFallback, true);
    assertEquals(tc(calls[0]), { thinkingLevel: "low" });
    assertEquals(tc(calls[1]), { thinkingLevel: "high" });
  } finally {
    THINKING_BY_MODEL[MODEL_FALLBACK].on = saved;
    restore();
  }
});

Deno.test("an UNKNOWN slug sends NO thinkingConfig and does not throw (legacy test slugs pass through the real function)", async () => {
  assertEquals(thinkingConfigFor("gemini-2.5-flash", "off"), null);
  const { calls, restore } = installFakeFetch([okText("ok")]);
  try {
    const res = await geminiChat({
      model: "gemini-2.5-flash",
      systemPrompt: "s",
      userPrompt: "hi",
      maxTokens: 64,
      fallbackToLite: false,
    });
    assertEquals(res.content, "ok");
    assertEquals(calls[0].body.generationConfig.thinkingConfig, undefined);
  } finally {
    restore();
  }
});

Deno.test("every exported MODEL_* constant has a capability row with off+on, and neither mode uses thinkingBudget", () => {
  // Iterate EVERY exported MODEL_* constant (not a hand-written list), so a newly
  // added export without a capability row fails here.
  const exported = Object.entries(gemini)
    .filter(([k, v]) => k.startsWith("MODEL_") && typeof v === "string")
    .map(([, v]) => v as string);
  assert(exported.length >= 4, "expected at least the four MODEL_* constants");
  for (const slug of new Set(exported)) {
    const row = THINKING_BY_MODEL[slug];
    assert(row, `no THINKING_BY_MODEL row for ${slug}`);
    for (const mode of ["off", "on"] as const) {
      assert(row[mode], `${slug} missing ${mode}`);
      assertEquals("thinkingBudget" in row[mode], false);
    }
  }
});
