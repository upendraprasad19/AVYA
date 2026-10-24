// Deno tests for the chat-channel suffix of the Captain's Manual
// (A-batch, ai-coach-ux-tool-integrity spec 2026-09-18, founder obs 1).
// Run: deno test --allow-all supabase/functions/_shared/captain_manual_chat_test.ts
//
// Pins two instruction families the client cannot enforce:
//   1. REPLY LENGTH — the chat channel previously had NO cap (morning/
//      weekly/proactive all did), so replies ran long, especially on photo
//      turns.
//   2. ANTI-INTERROGATION — the model must resolve names→IDs from its own
//      snapshot and never demand "exercises, sets, reps" checklists
//      (founder screenshot 2026-09-18).
// The other channels' caps must remain UNCHANGED (guard against the suffix
// being dropped or overwritten).

import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { captainPrompt } from "./captain_manual.ts";

Deno.test("chat channel carries hard reply-length rules", () => {
  const p = captainPrompt("chat");
  assertStringIncludes(p, "100 words or fewer");
  assertStringIncludes(p, "60 words or fewer");
  assertStringIncludes(p, "Bullets over paragraphs");
});

Deno.test("chat channel carries anti-interrogation rules", () => {
  const p = captainPrompt("chat");
  assertStringIncludes(p, "NEVER ask the user for exercise IDs");
  assertStringIncludes(p, "ONE short question");
  assertStringIncludes(p, "Resolve names to IDs yourself");
});

Deno.test("other channels keep their own caps (no regression)", () => {
  assertStringIncludes(captainPrompt("morning"), "under 80 words");
  assertStringIncludes(captainPrompt("proactive"), "under 60 words");
  assertStringIncludes(captainPrompt("weekly"), "3 wins, 1 friction");
  assert(!captainPrompt("morning").includes("NEVER ask the user for exercise IDs"),
    "chat-specific rules must not leak into other channels");
});
