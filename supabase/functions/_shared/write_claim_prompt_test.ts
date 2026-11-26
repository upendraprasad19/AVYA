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
  AI_FOOD_TAG_LINE,
  AI_FOOD_TOOL_RULE,
  applyWriteClaimDescriptions,
  icbfLogInstructions,
  isCoachMealItemsRuleDisabled,
  isWriteClaimRuleDisabled,
  MEAL_OLD_CARD,
  MEAL_OLD_LOG,
  MEDIA_FOOD_ITEMS_RULES,
  MEDIA_FOOD_ITEMS_TAG_LINE,
  MEDIA_FOOD_TAG_LINE,
  MEDIA_WRITE_CLAIM_RULE,
  mediaIcbfLogInstructions,
  ONE_TAG_LINE,
  SUFFIX_CONFIRM_KINDS_NEW,
  SUFFIX_CONFIRM_KINDS_OLD,
  SUFFIX_FOOD_COUNTDOWN_NEW,
  SUFFIX_FOOD_COUNTDOWN_OLD,
  SUFFIX_SKIP_KINDS_NEW,
  SUFFIX_SKIP_KINDS_OLD,
  TAG_RULES_WITH_ATE,
  TAG_RULES_WITHOUT_ATE,
  TEMPLATE_OLD_EXAMPLE,
  WRITE_CLAIM_RULE,
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

// OI-348 Landing 3b: the ON pieces (ICBF block + suffix) as main 238bb44f
// built them before the meal-items rule, recorded by a scratch capture
// script (command in docs/diagnoses/2026-11-26-coach-meal-tag-example-copied-b3f7a1.md).
const mealGolden = JSON.parse(
  await Deno.readTextFile(
    new URL("./testdata/icbf_blocks_pre_meal_items.json", import.meta.url),
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

// ── OI-348 Landing 3b: the meal-items rule (plan docs/plans/oi348-landing3b.md §5.1) ──

const count = (hay: string, needle: string) => hay.split(needle).length - 1;

Deno.test("3b golden: the recorded bytes match their own sha256", async () => {
  assertEquals(await sha256(mealGolden.ai_proxy_on), mealGolden.sha256_ai_proxy_on);
  assertEquals(await sha256(mealGolden.media_on), mealGolden.sha256_media_on);
});

Deno.test("3b OFF: every piece is byte-identical to the bytes before 3b (both write-claim states)", () => {
  for (const off of [{}, { mealItems: false }]) {
    assertStrictEquals(
      icbfLogInstructions(true, off) + writeClaimSuffix(true, off),
      mealGolden.ai_proxy_on,
    );
    assertStrictEquals(
      mediaIcbfLogInstructions(true, off) +
        writeClaimSuffix(true, { tools: false, ...off }),
      mealGolden.media_on,
    );
    assertStrictEquals(icbfLogInstructions(false, off), golden.ai_proxy);
    assertStrictEquals(mediaIcbfLogInstructions(false, off), golden.media);
    assertStrictEquals(writeClaimSuffix(false, off), "");
  }
});

Deno.test("3b: every replaced substring exists exactly once in its base text", () => {
  for (const ruleOn of [true, false]) {
    const ai = icbfLogInstructions(ruleOn);
    const media = mediaIcbfLogInstructions(ruleOn);
    assertEquals(count(ai, AI_FOOD_TAG_LINE), 1, `ai food line, rule ${ruleOn}`);
    assertEquals(count(media, MEDIA_FOOD_TAG_LINE), 1, `media food line, rule ${ruleOn}`);
    for (const t of [ai, media]) {
      assertEquals(count(t, TAG_RULES_WITH_ATE), 1);
      assertEquals(count(t, ONE_TAG_LINE), 1);
    }
  }
  // writeClaimSuffix(false) is "", so the suffix constants live in the rules.
  for (const rule of [WRITE_CLAIM_RULE, MEDIA_WRITE_CLAIM_RULE]) {
    assertEquals(count(rule, SUFFIX_FOOD_COUNTDOWN_OLD), 1);
    assertEquals(count(rule, SUFFIX_CONFIRM_KINDS_OLD), 1);
    assertEquals(count(rule, SUFFIX_SKIP_KINDS_OLD), 1);
  }
});

Deno.test("3b ON, ai-proxy: no food tag example; food goes to logMealByText (both headers)", () => {
  for (const ruleOn of [true, false]) {
    const block = icbfLogInstructions(ruleOn, { mealItems: true });
    assert(!block.includes('"action":"log_food"'), "a food tag example survived");
    assert(!block.includes("Dal Rice"));
    assert(!block.includes(TAG_RULES_WITH_ATE), "the tag rule still says I ate");
    assertStringIncludes(block, TAG_RULES_WITHOUT_ATE);
    assertStringIncludes(block, ONE_TAG_LINE + AI_FOOD_TOOL_RULE);
    // The other tag examples stay.
    for (
      const k of ["log_water", "log_weight", "log_sleep", "log_measurement", "confirm_workout_log"]
    ) {
      assertStringIncludes(block, `"action":"${k}"`);
    }
  }
  // Exactly the three edits: undo two and the base minus the food line comes back.
  const on = icbfLogInstructions(true, { mealItems: true });
  const undone = on
    .replace(ONE_TAG_LINE + AI_FOOD_TOOL_RULE, () => ONE_TAG_LINE)
    .replace(TAG_RULES_WITHOUT_ATE, () => TAG_RULES_WITH_ATE);
  assertStrictEquals(undone, icbfLogInstructions(true).replace(AI_FOOD_TAG_LINE, () => ""));
});

Deno.test("3b ON, media: the items example is valid JSON whose totals are the item sums", () => {
  for (const ruleOn of [true, false]) {
    const block = mediaIcbfLogInstructions(ruleOn, { mealItems: true });
    assert(!block.includes("Dal Rice"));
    assertEquals(count(block, MEDIA_FOOD_ITEMS_TAG_LINE), 1);
    assertStringIncludes(block, ONE_TAG_LINE + MEDIA_FOOD_ITEMS_RULES);
    // The tag is still the photo path's only meal door: "I ate" stays.
    assertStringIncludes(block, TAG_RULES_WITH_ATE);
  }
  const m = MEDIA_FOOD_ITEMS_TAG_LINE.match(/<ICBF_LOG>([\s\S]*?)<\/ICBF_LOG>/);
  assert(m !== null);
  const tag = JSON.parse(m[1]);
  assertEquals(tag.action, "log_food");
  const d = tag.data;
  assertEquals(typeof d.food_name, "string");
  assert(!("meal_type" in d), "the example names a slot");
  assertEquals(d.items.length, 2);
  // deno-lint-ignore no-explicit-any
  const sum = (k: string) => d.items.reduce((s: number, i: any) => s + i[k], 0);
  assertEquals(d.calories_estimate, sum("calories"));
  assertEquals(d.protein_estimate, sum("protein_g"));
  assertEquals(d.carbs_estimate, sum("carbs_g"));
  assertEquals(d.fat_estimate, sum("fat_g"));
  assertEquals(d.quantity_g, sum("quantity_g"));
  for (const i of d.items) {
    for (const k of ["name", "quantity_g", "calories", "protein_g", "carbs_g", "fat_g"]) {
      assert(k in i, `item missing ${k}`);
    }
  }
});

Deno.test("3b ON: both suffixes say a food tag waits for CONFIRM; OFF write-claim stays empty", () => {
  for (const tools of [true, false]) {
    const s = writeClaimSuffix(true, { tools, mealItems: true });
    assertStringIncludes(s, SUFFIX_FOOD_COUNTDOWN_NEW);
    assertStringIncludes(s, SUFFIX_CONFIRM_KINDS_NEW);
    assertStringIncludes(s, SUFFIX_SKIP_KINDS_NEW);
    assert(!s.includes("a water, weight, food"), "food still in the countdown list");
    assert(!s.includes(SUFFIX_CONFIRM_KINDS_OLD));
  }
  assertStrictEquals(writeClaimSuffix(false, { mealItems: true }), "");
  assertStrictEquals(writeClaimSuffix(false, { tools: false, mealItems: true }), "");
  // The media rule still names no tool.
  assert(!/tool/i.test(writeClaimSuffix(true, { tools: false, mealItems: true })));
});

Deno.test("3b kill-switch reader: only exactly \"true\" disables", () => {
  const env = (v: string | undefined) => (n: string) =>
    n === "DISABLE_COACH_MEAL_ITEMS_RULE" ? v : undefined;
  assertEquals(isCoachMealItemsRuleDisabled(env("true")), true);
  for (const v of [undefined, "TRUE", "1", "false", " true", "yes"]) {
    assertEquals(isCoachMealItemsRuleDisabled(env(v)), false, `value ${v}`);
  }
});
