// supabase/functions/_shared/row_model_label_test.ts
//
// rowModelLabel (2026-10-01, a1c6b9 recurrence): a hard-failure reply (the
// hardcoded apology) used to be persisted with the REAL model label and
// tokens_used=0, so dedupDecision replayed the apology as a normal 200 and a
// cold restore re-fed it as history. It is now stamped with the failure
// SENTINEL. End-to-end: the label rowModelLabel produces is what dedupDecision
// reads on the next request.
//
// Run: deno test --no-check --allow-all --node-modules-dir=none supabase/functions/_shared/row_model_label_test.ts

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.env.set("GEMINI_API_KEY", "test-key-not-a-real-secret");

const { rowModelLabel } = await import("./row_model_label.ts");
const { dedupDecision, LOOP_THREW_RESPONSE_MARKER } = await import("./chat_dedup.ts");

const SENTINEL = "failed";

Deno.test("hard failure -> the sentinel, whatever model was involved", () => {
  assertEquals(rowModelLabel(true, "gemini-3.1-flash-lite", SENTINEL), SENTINEL);
  assertEquals(rowModelLabel(true, null, SENTINEL), SENTINEL);
});

Deno.test("success -> the label of the slug that actually answered", () => {
  assertEquals(rowModelLabel(false, "gemini-3.1-flash-lite", SENTINEL), "Gemini 3.1 Flash Lite");
  assertEquals(rowModelLabel(false, "gemini-3.5-flash-lite", SENTINEL), "Gemini 3.5 Flash Lite");
});

Deno.test("success with no recorded model falls back to the primary tier's label, never the sentinel", () => {
  assertEquals(rowModelLabel(false, null, SENTINEL), "Gemini 3.1 Flash Lite");
});

Deno.test("end-to-end: a hard-failure row replays the flagged apology (not a normal reply); a normal turn's row replays the reply", () => {
  const apology = "I had trouble reaching the model. Please try again.";
  const failedRow = { ai_response: apology, model_used: rowModelLabel(true, "gemini-3.1-flash-lite", SENTINEL) };
  // a delivered apology row replays the SAME 200 (flagged), never a normal reply and
  // never a 502; only the loop-THREW row (marker text) replays the 502.
  assertEquals(dedupDecision(failedRow, SENTINEL), "replay_hard_failure");
  assertEquals(
    dedupDecision({ ai_response: LOOP_THREW_RESPONSE_MARKER, model_used: SENTINEL }, SENTINEL),
    "replay_failure",
  );
  const goodRow = { ai_response: "Drink 3L today.", model_used: rowModelLabel(false, "gemini-3.1-flash-lite", SENTINEL) };
  assertEquals(dedupDecision(goodRow, SENTINEL), "replay_reply");
});

// ── ai-proxy wiring: position-pinned slices (a dead object or a stray call elsewhere
// in the file cannot satisfy these; the comment-stripped source is sliced around the
// REAL statement). ai-proxy calls serve() at module scope so source is all we can read.

async function proxyCode(): Promise<string> {
  const src = await Deno.readTextFile(new URL("../ai-proxy/index.ts", import.meta.url));
  return src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
}

function sliceFrom(code: string, anchor: string, len: number): string {
  const i = code.indexOf(anchor);
  assert(i >= 0, `anchor not found in ai-proxy: ${anchor}`);
  return code.slice(i, i + len);
}

Deno.test("ai-proxy wiring: the chat reservation-resolve UPDATE itself writes rowModelUsed; the client response keeps the real label", async () => {
  const code = await proxyCode();
  assert(
    /const rowModelUsed = rowModelLabel\(\s*loop\.hadHardFailure,\s*loop\.modelUsed,\s*MODEL_USED_LOOP_THREW_SENTINEL,?\s*\)/.test(code),
    "row label must come from rowModelLabel(loop.hadHardFailure, loop.modelUsed, SENTINEL)",
  );
  // the .update({ ... }) object that carries snapshot_id + ai_response: cleanReply
  const update = sliceFrom(code, "snapshot_id: snapshotData?.id ?? null,", 320);
  assert(/ai_response: cleanReply,\s*model_used: rowModelUsed,/.test(update), "the UPDATE must write rowModelUsed");
  assert(!/model_used: modelLabel/.test(update), "the UPDATE must not write the client label");
  // response body
  assert(/reply: cleanReply,\s*model_used: modelLabel,/.test(code), "the client response keeps the real label");
  assert(code.includes("const modelLabel = labelForModel(loop.modelUsed ?? MODEL_FLASH);"));
});

Deno.test("ai-proxy wiring: the runToolLoop-threw catch stamps the SENTINEL constant (not a re-typed literal) with the marker text", async () => {
  const code = await proxyCode();
  const catchBody = sliceFrom(code, "} catch (loopErr) {", 1600);
  const end = catchBody.indexOf("return err(502");
  assert(end > 0, "catch must return a 502");
  const body = catchBody.slice(0, end);
  assert(/ai_response: "\[failed\] runToolLoop threw",\s*model_used: MODEL_USED_LOOP_THREW_SENTINEL,/.test(body));
  assertEquals(body.includes("failed_loop"), false);
});

Deno.test("the threw-marker literal in ai-proxy equals chat_dedup's LOOP_THREW_RESPONSE_MARKER", async () => {
  const code = await proxyCode();
  assert(code.includes(`ai_response: "${LOOP_THREW_RESPONSE_MARKER}",`));
});

Deno.test("ai-proxy wiring: dedup branches — hard-failure replays a flagged 200; the cached-reply fallback label is the labelled primary", async () => {
  const code = await proxyCode();
  const hf = sliceFrom(code, 'if (dedup === "replay_hard_failure" && recentDup) {', 700);
  assert(/status: 200/.test(hf) && /had_hard_failure: true/.test(hf) && /deduplicated: true/.test(hf) && /reply: recentDup\.ai_response/.test(hf));
  assertEquals(/err\(502/.test(hf), false, "a delivered apology must not replay as a 502");
  const reply = sliceFrom(code, 'if (dedup === "replay_reply" && recentDup) {', 700);
  assert(reply.includes("model_used: recentDup.model_used ?? labelForModel(MODEL_FLASH),"));
});

Deno.test("ai-proxy wiring: food/scan/cart resolve their rows with labelForModel(modelUsed) at the resolve call itself", async () => {
  const code = await proxyCode();
  assert(
    /await resolvePlaceholder\(\s*labelForModel\(modelUsed\),\s*JSON\.stringify\(parsed\),\s*tokensUsed,?\s*\);/.test(code),
    "food_text_analysis success resolve",
  );
  const vision = code.match(/await resolveVisionPlaceholder\(labelForModel\(modelUsed\), "success", tokensUsed\);/g) ?? [];
  assertEquals(vision.length, 2, "scan_meal and cart_auditor");
});
