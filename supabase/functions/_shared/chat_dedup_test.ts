// Deno tests for _shared/chat_dedup.ts (Hermes 2026-09-26, L29-F3): a failed
// chat attempt inside the 30-second dedup window must replay its FAILURE —
// never the internal "[failed] runToolLoop threw" marker as a 200 reply, and
// never a fresh run that would spend another chat-cap unit.
//
// Run: deno test --no-check --allow-all --node-modules-dir=none supabase/functions/_shared/chat_dedup_test.ts

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { dedupDecision, LOOP_THREW_RESPONSE_MARKER } from "./chat_dedup.ts";

const SENTINEL = "failed";

Deno.test("no recent row → process the message", () => {
  assertEquals(dedupDecision(null, SENTINEL), "process");
  assertEquals(dedupDecision(undefined, SENTINEL), "process");
});

Deno.test("a real reply is replayed", () => {
  assertEquals(
    dedupDecision({ ai_response: "Drink 3L today.", model_used: "Gemini 3.1 Flash Lite" }, SENTINEL),
    "replay_reply",
  );
});

Deno.test("the runToolLoop-threw row replays the failure, not its marker", () => {
  assertEquals(
    dedupDecision({ ai_response: "[failed] runToolLoop threw", model_used: SENTINEL }, SENTINEL),
    "replay_failure",
  );
});

Deno.test("a pending reservation (empty reply) is processed as before", () => {
  assertEquals(dedupDecision({ ai_response: "", model_used: "pending" }, SENTINEL), "process");
});

// Wiring: ai-proxy must route the dedup row through dedupDecision with the
// real sentinel and return the failure BEFORE the reply branch can serve it.
Deno.test("ai-proxy consults dedupDecision with MODEL_USED_LOOP_THREW_SENTINEL before replaying", async () => {
  const src = await Deno.readTextFile(new URL("../ai-proxy/index.ts", import.meta.url));
  const code = src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
  const call = code.indexOf("dedupDecision(recentDup, MODEL_USED_LOOP_THREW_SENTINEL)");
  const failure = code.indexOf('if (dedup === "replay_failure")');
  const reply = code.indexOf('if (dedup === "replay_reply"');
  assert(call >= 0, "ai-proxy must call dedupDecision(recentDup, MODEL_USED_LOOP_THREW_SENTINEL)");
  assert(failure > call && reply > failure, "the failure branch must precede the reply branch");
  assert(
    !/if\s*\(\s*recentDup\?\.ai_response\s*\)/.test(code),
    "the old truthy-ai_response check would serve the failure marker as a reply",
  );
});

Deno.test("a sentinel row holding a delivered APOLOGY replays the flagged 200, not the 502 (a5c8e2)", () => {
  assertEquals(
    dedupDecision({ ai_response: "I had trouble reaching the model.", model_used: SENTINEL }, SENTINEL),
    "replay_hard_failure",
  );
});

Deno.test("a sentinel row with the threw marker, empty or non-string text replays the 502 (fail safe: never serve unknown text)", () => {
  assertEquals(dedupDecision({ ai_response: LOOP_THREW_RESPONSE_MARKER, model_used: SENTINEL }, SENTINEL), "replay_failure");
  assertEquals(dedupDecision({ ai_response: "", model_used: SENTINEL }, SENTINEL), "replay_failure");
  assertEquals(dedupDecision({ ai_response: null, model_used: SENTINEL }, SENTINEL), "replay_failure");
  assertEquals(dedupDecision({ model_used: SENTINEL }, SENTINEL), "replay_failure");
});

Deno.test("ai-proxy routes the hard-failure decision BEFORE the cached-reply branch", async () => {
  const src = await Deno.readTextFile(new URL("../ai-proxy/index.ts", import.meta.url));
  const code = src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
  const hard = code.indexOf('if (dedup === "replay_hard_failure"');
  const reply = code.indexOf('if (dedup === "replay_reply"');
  assert(hard > 0 && reply > hard, "replay_hard_failure branch must exist and precede replay_reply");
});
