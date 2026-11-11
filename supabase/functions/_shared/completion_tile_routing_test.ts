// supabase/functions/_shared/completion_tile_routing_test.ts
//
// Coach workout parity S3 (OI-492; plan 3.1 steps 3, 4, 6; 5.1 S3). The
// routing block, the write-claim addendum, the kill switch and the memory
// marker, plus source pins on how ai-proxy/index.ts wires them. Mutants M10,
// M28, M36, M61, M62a-h.

import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  applyCompletionTileKillSwitch,
  COMPLETION_TILE_REPLY_LINE,
  COMPLETION_TILE_WRITE_CLAIM_ADDENDUM_TEXT,
  completionTileRoutingBlock,
  completionTileWriteClaimAddendum,
  memoryIntentSummary,
  TILE_NOT_PARTIAL_ALL_LOGGED_LINE,
  TILE_NOT_PARTIAL_COMPLETED_LINE,
  TILE_NOT_PARTIAL_NO_PLAN_LINE,
  TILE_NOT_PARTIAL_NOTHING_LOGGED_LINE,
} from "./completion_tile_routing.ts";

const CAPS = new Set(["request_completion_tile"]);
const block = completionTileRoutingBlock(CAPS);

Deno.test("block: empty without the capability, non-empty with it", () => {
  assertEquals(completionTileRoutingBlock(new Set()), "");
  assertEquals(completionTileRoutingBlock(new Set(["swap_workout_days"])), "");
  assert(block.length > 0);
});

Deno.test("block: holds the tile line and the four not-partial lines", () => {
  for (const line of [
    COMPLETION_TILE_REPLY_LINE,
    TILE_NOT_PARTIAL_COMPLETED_LINE,
    TILE_NOT_PARTIAL_NO_PLAN_LINE,
    TILE_NOT_PARTIAL_ALL_LOGGED_LINE,
    TILE_NOT_PARTIAL_NOTHING_LOGGED_LINE,
  ]) {
    assertStringIncludes(block, line);
  }
});

Deno.test("block: no APPLY and no Queued (case-sensitive)", () => {
  assert(!block.includes("APPLY"));
  assert(!block.includes("Queued"));
});

Deno.test("block: conditions key on all_logged, exercises and type rest, never total_logged", () => {
  assertStringIncludes(block, "today_workout.today_workout_completion.all_logged is false");
  assertStringIncludes(block, "today_workout.exercises is non-empty");
  assertStringIncludes(block, "today_workout.type is not rest");
  assert(!block.includes("total_logged"));
  assert(!block.includes("total_planned"));
});

Deno.test("block: precedence over the no-details rule, and action-not-read", () => {
  assertStringIncludes(
    block,
    "instead of asking them to describe exercises, sets, reps or weights",
  );
  assertStringIncludes(block, "the rule for a finished workout without exercise details still applies when nothing is logged today");
  assertStringIncludes(block, "requestCompletionTile is an action, not a data read");
});

Deno.test("block: never in a turn that also logs sets; a meal log does not count", () => {
  assertStringIncludes(block, "Never call requestCompletionTile in a turn that also logs sets");
  assertStringIncludes(block, "a meal log does not count");
});

Deno.test("block: the never-bullet is scoped to after the call", () => {
  assertStringIncludes(
    block,
    "After you call requestCompletionTile, never say the workout is completed, done, counted or marked.",
  );
});

Deno.test("addendum: empty without the capability and with the rule off; scoped text with both", () => {
  assertEquals(completionTileWriteClaimAddendum(new Set(), true), "");
  assertEquals(completionTileWriteClaimAddendum(CAPS, false), "");
  const a = completionTileWriteClaimAddendum(CAPS, true);
  assert(a.startsWith("\n\n"));
  assertEquals(a, `\n\n${COMPLETION_TILE_WRITE_CLAIM_ADDENDUM_TEXT}`);
  assertStringIncludes(a, "never say Queued or APPLY for it");
  assertStringIncludes(a, "Any other proposal in the same reply keeps its own queued line.");
});

Deno.test("kill switch: only exact lowercase 'true' removes the capability; same set returned", () => {
  const cases: Array<[string | undefined, boolean]> = [
    [undefined, true],
    ["", true],
    ["false", true],
    ["TRUE", true],
    ["1", true],
    ["true", false],
  ];
  for (const [env, keeps] of cases) {
    const caps = new Set(["request_completion_tile", "swap_workout_days"]);
    const out = applyCompletionTileKillSwitch(caps, env);
    assert(out === caps, `same set for ${env}`);
    assertEquals(out.has("request_completion_tile"), keeps, `env=${env}`);
    assert(out.has("swap_workout_days"));
  }
});

Deno.test("memoryIntentSummary: queued for ordinary intents, a neutral marker for the tile", () => {
  assertEquals(memoryIntentSummary([]), "");
  assertEquals(memoryIntentSummary([{ type: "log_set" }]), " [queued: log_set]");
  assertEquals(
    memoryIntentSummary([{ type: "log_set" }, { type: "log_meal_by_text" }]),
    " [queued: log_set, log_meal_by_text]",
  );
  assertEquals(
    memoryIntentSummary([{ type: "request_completion_tile" }]),
    " [requested: completion tile]",
  );
  assertEquals(
    memoryIntentSummary([{ type: "log_set" }, { type: "request_completion_tile" }]),
    " [queued: log_set] [requested: completion tile]",
  );
});

// ── Source pins on ai-proxy/index.ts (presence only: the handler has no seam
// that renders the system prompt; the behaviour of each helper is above).
const indexSrc = Deno.readTextFileSync(
  new URL("../ai-proxy/index.ts", import.meta.url),
);

Deno.test("ai-proxy: the tile block is pushed only through `if (tileBlock)`", () => {
  assertStringIncludes(
    indexSrc,
    "const tileBlock = completionTileRoutingBlock(capabilities);\n      if (tileBlock) promptParts.push(tileBlock);",
  );
  assertEquals(indexSrc.split("completionTileRoutingBlock(").length - 1, 1);
});

Deno.test("ai-proxy: the addendum is appended AFTER writeClaimSuffix(", () => {
  const suffixAt = indexSrc.indexOf("writeClaimSuffix(ruleOn)");
  const addendumAt = indexSrc.indexOf("completionTileWriteClaimAddendum(capabilities, ruleOn)");
  assert(suffixAt > 0 && addendumAt > 0);
  assert(addendumAt > suffixAt);
});

Deno.test("ai-proxy: the kill switch is applied before runToolLoop({", () => {
  const killAt = indexSrc.indexOf("applyCompletionTileKillSwitch(");
  const loopAt = indexSrc.indexOf("runToolLoop({");
  assert(killAt > 0 && loopAt > 0);
  assert(killAt < loopAt);
  assertStringIncludes(indexSrc, 'Deno.env.get("DISABLE_COMPLETION_TILE_TOOL")');
});

Deno.test("ai-proxy: the memory marker goes through memoryIntentSummary", () => {
  assertStringIncludes(indexSrc, "memoryIntentSummary(loop.intents)");
  assert(!indexSrc.includes("` [queued: ${loop.intents"));
});
