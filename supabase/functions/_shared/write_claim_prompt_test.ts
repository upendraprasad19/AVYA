// supabase/functions/_shared/write_claim_prompt_test.ts
//
// coach-log-truth (OI-368 / OI-369, plan docs/plans/coach-log-truth.md §3).
// Golden: with the rule OFF every prompt piece is byte-identical to the bytes
// recorded from origin/main by an independent capture script
// (testdata/icbf_blocks_pre_write_claim.json; command and SHA in the diagnose
// doc). With the rule ON the pieces carry the founder-approved lines verbatim.

import {
  assert,
  assertEquals,
  assertStrictEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  applyWriteClaimDescriptions,
  icbfLogInstructions,
  isWriteClaimRuleDisabled,
  MEAL_OLD_CARD,
  MEAL_OLD_LOG,
  mediaIcbfLogInstructions,
  TEMPLATE_OLD_EXAMPLE,
  writeClaimSuffix,
} from "./write_claim_prompt.ts";
import { daySwapRoutingBlock } from "./day_swap_routing.ts";
import { logMealByTextTool } from "./tools/nutrition/logMealByText.ts";
import { scheduleTemplateTool } from "./tools/plan/scheduleTemplate.ts";

const golden = JSON.parse(
  await Deno.readTextFile(
    new URL("./testdata/icbf_blocks_pre_write_claim.json", import.meta.url),
  ),
);

async function sha256(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

const APPROVED_TOOL_LINES = [
  "Queued. Tap APPLY to log it.",
  "Queued. Tap APPLY to confirm.",
  "Queued. Tap CONFIRM to log it.",
  "Queued. It logs in 5 seconds unless you tap SKIP.",
  "Nothing logged yet. Send the sets and I'll queue it.",
  "Not in my data yet. If its card is still up, tap APPLY or CONFIRM on it.",
  "Queued. Tap APPLY on each card.",
  "Tap APPLY below to swap them.",
  "Queued. Tap APPLY to save it.",
];

const NEW_HEADER =
  "FITNESS DATA LOGGING — A CARD FIRST; NOTHING IS SAVED WHEN YOU REPLY:";

Deno.test("golden: the recorded bytes match their own sha256", async () => {
  assertEquals(await sha256(golden.ai_proxy), golden.sha256_ai_proxy);
  assertEquals(await sha256(golden.media), golden.sha256_media);
  assertEquals(
    await sha256(golden.day_swap_pro_capable),
    golden.sha256_day_swap_pro_capable,
  );
});

Deno.test("OFF: the ICBF blocks are byte-identical to origin/main", async () => {
  assertStrictEquals(icbfLogInstructions(false), golden.ai_proxy);
  assertStrictEquals(mediaIcbfLogInstructions(false), golden.media);
  assertEquals(await sha256(icbfLogInstructions(false)), golden.sha256_ai_proxy);
  assertEquals(await sha256(mediaIcbfLogInstructions(false)), golden.sha256_media);
});

Deno.test("OFF: the suffix is empty, so the separator never lands", () => {
  assertStrictEquals(writeClaimSuffix(false), "");
  assertStrictEquals(writeClaimSuffix(false, { tools: false }), "");
});

Deno.test("OFF: the day-swap block is byte-identical to origin/main", () => {
  const caps = new Set(["swap_workout_days"]);
  assertStrictEquals(
    daySwapRoutingBlock(true, caps, false),
    golden.day_swap_pro_capable,
  );
});

Deno.test("ON: the ai-proxy pieces carry the new header and every approved line", () => {
  const on = icbfLogInstructions(true) + writeClaimSuffix(true);
  assertStringIncludes(on, NEW_HEADER);
  assert(!on.includes("FITNESS DATA LOGGING — INSTANT"));
  for (const line of APPROVED_TOOL_LINES) assertStringIncludes(on, line);
  assert(writeClaimSuffix(true).startsWith("\n\nWRITE CLAIMS"));
});

Deno.test("ON: the media variant names no tool and none of the tool lines", () => {
  const on = mediaIcbfLogInstructions(true) +
    writeClaimSuffix(true, { tools: false });
  assertStringIncludes(on, NEW_HEADER);
  for (
    const line of [
      "Queued. Tap CONFIRM to log it.",
      "Queued. It logs in 5 seconds unless you tap SKIP.",
      "Nothing logged yet. Send the sets and I'll queue it.",
      "Not in my data yet. If its card is still up, tap APPLY or CONFIRM on it.",
    ]
  ) assertStringIncludes(on, line);
  const suffix = writeClaimSuffix(true, { tools: false });
  assert(!/tool/i.test(suffix), "the media rule mentions a tool");
  for (
    const absent of [
      "Queued. Tap APPLY to log it.",
      "Queued. Tap APPLY to confirm.",
      "Queued. Tap APPLY on each card.",
      "Queued. Tap APPLY to save it.",
      "proposed with a tool",
      "swapWorkoutDays",
      "DAY SWAP ROUTING",
      "swap them",
    ]
  ) assert(!suffix.includes(absent), `media rule contains: ${absent}`);
});

Deno.test("ON: the day-swap example says APPLY, not done", () => {
  const caps = new Set(["swap_workout_days"]);
  const block = daySwapRoutingBlock(true, caps, true);
  assertStringIncludes(block, "Tap APPLY below to swap them.");
  assert(!block.includes("it's done"));
  // The default (no third argument) is the rule ON.
  assertStrictEquals(daySwapRoutingBlock(true, caps), block);
});

Deno.test("prompt size: ON adds exactly 2189 UTF-16 units to the ai-proxy pieces", () => {
  const on = icbfLogInstructions(true) + writeClaimSuffix(true);
  const off = icbfLogInstructions(false) + writeClaimSuffix(false);
  assertEquals(on.length - off.length, 2189);
});

Deno.test("tool descriptions: OFF returns the same array; ON rewrites copies", () => {
  // The live descriptions still hold the exact substrings being replaced.
  assertStringIncludes(logMealByTextTool.description, MEAL_OLD_CARD);
  assertStringIncludes(logMealByTextTool.description, MEAL_OLD_LOG);
  assertStringIncludes(scheduleTemplateTool.description, TEMPLATE_OLD_EXAMPLE);

  // deno-lint-ignore no-explicit-any
  const tools: any[] = [logMealByTextTool, scheduleTemplateTool];
  assertStrictEquals(applyWriteClaimDescriptions(tools, false), tools);

  const on = applyWriteClaimDescriptions(tools, true);
  const meal = on.find((t) => t.name === "logMealByText");
  const tmpl = on.find((t) => t.name === "scheduleTemplate");
  assert(meal !== logMealByTextTool, "a copy, not the registry object");
  assert(!meal.description.includes("5-second"));
  assertStringIncludes(meal.description, "must tap APPLY to log it");
  assertStringIncludes(meal.description, "and queue it for the user's nutrition today");
  assertStringIncludes(tmpl.description, "Queued. Tap APPLY to save it.");
  assert(!tmpl.description.includes("'Saved! Want me"));
  // The registry objects are untouched.
  assertStringIncludes(logMealByTextTool.description, "5-second");
});

Deno.test("kill-switch reader: only exactly \"true\" disables", () => {
  const env = (v: string | undefined) => (n: string) =>
    n === "DISABLE_WRITE_CLAIM_RULE" ? v : undefined;
  assertEquals(isWriteClaimRuleDisabled(env("true")), true);
  for (const v of [undefined, "TRUE", "1", "false", " true", "yes"]) {
    assertEquals(isWriteClaimRuleDisabled(env(v)), false, `value ${v}`);
  }
});
