// supabase/functions/_shared/tools/__tests__/requestCompletionTile_test.ts
//
// Coach workout parity S3 (OI-492). The tool's shape, and the literals the
// coverage gate reads pinned to the routing file's consts (the gate's regex
// reads only literals: plan 3.1 1a, mutants M1, M13, M41).

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { requestCompletionTileTool } from "../workout/requestCompletionTile.ts";
import { swapWorkoutDaysTool } from "../workout/swapWorkoutDays.ts";
import { toolToFunctionDeclaration } from "../zodToGemini.ts";
import {
  AUTO_RUN_INTENT_TYPES,
  CAPABILITY_REQUEST_COMPLETION_TILE,
  COMPLETION_TILE_QUEUED_NOTE,
  REQUEST_COMPLETION_TILE_TOOL_NAME,
} from "../../completion_tile_routing.ts";
import { CAPABILITY_SWAP_WORKOUT_DAYS } from "../../day_swap_routing.ts";
import type { ToolContext } from "../types.ts";

function ctx(): ToolContext {
  // deno-lint-ignore no-explicit-any
  return { userId: "u", isPro: false, sb: null as any, requestId: "r" };
}

Deno.test("requestCompletionTile — free, write, trivial, workout", () => {
  assertEquals(requestCompletionTileTool.tier, "free");
  assertEquals(requestCompletionTileTool.kind, "write");
  assertEquals(requestCompletionTileTool.confirmationClass, "trivial");
  assertEquals(requestCompletionTileTool.family, "workout");
});

Deno.test("requestCompletionTile — capability literal equals the exported const", () => {
  assertEquals(requestCompletionTileTool.requiresCapability, "request_completion_tile");
  assertEquals(
    requestCompletionTileTool.requiresCapability,
    CAPABILITY_REQUEST_COMPLETION_TILE,
  );
});

Deno.test("swapWorkoutDays — capability literal equals the exported const", () => {
  assertEquals(swapWorkoutDaysTool.requiresCapability, CAPABILITY_SWAP_WORKOUT_DAYS);
});

Deno.test("requestCompletionTile — name equals REQUEST_COMPLETION_TILE_TOOL_NAME", () => {
  assertEquals(requestCompletionTileTool.name, REQUEST_COMPLETION_TILE_TOOL_NAME);
});

Deno.test("requestCompletionTile — queuedStatus tile_requested and the conditional note", () => {
  assertEquals(requestCompletionTileTool.queuedStatus, "tile_requested");
  assertEquals(requestCompletionTileTool.queuedNote, COMPLETION_TILE_QUEUED_NOTE);
  assert(!(requestCompletionTileTool.queuedNote ?? "").includes("tap APPLY"));
});

Deno.test("requestCompletionTile — schema accepts user_says_done, rejects {} and other values", () => {
  assert(requestCompletionTileTool.schema.safeParse({ trigger: "user_says_done" }).success);
  assert(!requestCompletionTileTool.schema.safeParse({}).success);
  assert(!requestCompletionTileTool.schema.safeParse({ trigger: "done" }).success);
});

Deno.test("requestCompletionTile — the Gemini declaration has non-empty properties", () => {
  const decl = toolToFunctionDeclaration(requestCompletionTileTool) as {
    parameters: { properties: Record<string, unknown> };
  };
  assert(Object.keys(decl.parameters.properties).length > 0);
  assert("trigger" in decl.parameters.properties);
});

Deno.test("requestCompletionTile — intent shape, an auto-run type", async () => {
  const intent = await requestCompletionTileTool.intentBuilder!(
    { trigger: "user_says_done" },
    ctx(),
  );
  assertEquals(intent.type, "request_completion_tile");
  assertEquals(intent.payload, {});
  assertEquals(intent.confirmationClass, "trivial");
  assert(AUTO_RUN_INTENT_TYPES.has(intent.type));
});
