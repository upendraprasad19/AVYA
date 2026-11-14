// supabase/functions/_shared/captain_manual_limits_test.ts
//
// Part B (gemini3-limits-caching): the Captain manual's tier/limit facts are
// interpolated from _shared/ai_limits.ts, never typed, and never promise
// "unlimited". Also pins the two plain-words rules added after the Gemini 3 probe
// (tool names leaked into user text; "your plan is already built into the system").
//
// Run: deno test --no-check --allow-all --node-modules-dir=none
//      supabase/functions/_shared/captain_manual_limits_test.ts

import { assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { captainPrompt, CAPTAIN_MANUAL } from "./captain_manual.ts";
import {
  FREE_CHAT_DAILY_CAP,
  FREE_VISION_DAILY_CAP,
  PRO_CHAT_DAILY_CAP,
  PRO_VISION_DAILY_CAP,
} from "./ai_limits.ts";

Deno.test("manual states the chat and vision caps from ai_limits.ts", () => {
  assertStringIncludes(CAPTAIN_MANUAL, `Free tier: ${FREE_CHAT_DAILY_CAP} messages/day`);
  assertStringIncludes(CAPTAIN_MANUAL, `(${PRO_CHAT_DAILY_CAP} messages/day)`);
  assertStringIncludes(
    CAPTAIN_MANUAL,
    `free ${FREE_VISION_DAILY_CAP}/day combined, PRO ${PRO_VISION_DAILY_CAP}/day combined`,
  );
});

Deno.test("manual never offers 'unlimited' and no stale 10/day figure remains", () => {
  assert(!/Want unlimited/i.test(CAPTAIN_MANUAL), "the upsell line must be gone");
  assert(!/Unlimited AI messages/i.test(CAPTAIN_MANUAL));
  assert(!/messages\/day to AI coach, forever/.test(CAPTAIN_MANUAL.replace(`${FREE_CHAT_DAILY_CAP} messages/day`, "")),
    "only the interpolated free cap may precede 'messages/day to AI coach'");
  assert(!CAPTAIN_MANUAL.includes("Free tier: 10 messages"), "stale pre-Part-B free cap");
  assert(!CAPTAIN_MANUAL.includes("Scan-meal: 10/day"), "stale pre-Part-B scan cap");
});

Deno.test("a PRO user at the cap gets no upsell instruction", () => {
  assertStringIncludes(CAPTAIN_MANUAL, "When a PRO user hits the");
  assertStringIncludes(CAPTAIN_MANUAL, "resets at midnight IST. No upsell");
});

Deno.test("chat channel carries the plain-words rules", () => {
  const p = captainPrompt("chat");
  assertStringIncludes(p, "NEVER name an internal tool, function or data field to the user");
  assertStringIncludes(p, "already built into the system");
  assertStringIncludes(p, "point them to the Train tab");
});
