// supabase/functions/_shared/tools/__tests__/registry_completion_tile_test.ts
//
// Coach workout parity S3 (OI-492). Against the REAL registry: an app build
// that does not declare request_completion_tile sees exactly today's tool
// list (frozen goldens), the new tool appears for free AND PRO only with the
// capability, no other tool carries queuedStatus/queuedNote, and the
// tile-surfacing set is logSet alone (intent log_set). Mutants M1, M10, M39.

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { allTools } from "../registry.ts";
import { logSetTool } from "../workout/logSet.ts";
import { TILE_SURFACING_TOOL_NAMES } from "../../completion_tile_routing.ts";
import type { ToolContext } from "../types.ts";

const PRO_TODAY = [
  "swapExercise",
  "logSet",
  "getProgressSummary",
  "shortenWorkout",
  "createCustomExercise",
  "modifyWorkoutForInjury",
  "rescheduleWeek",
  "generateHotelWorkout",
  "logMealByText",
  "suggestMeal",
  "getNutritionHistory",
  "getExerciseHistory",
  "getPromotionStatus",
  "getPRTimeline",
  "regeneratePlanBlock",
  "pausePlan",
  "switchGoal",
  "createCustomTemplate",
  "scheduleTemplate",
  "getFormCues",
];
const FREE_TODAY = [
  "logSet",
  "getProgressSummary",
  "shortenWorkout",
  "createCustomExercise",
  "logMealByText",
  "getNutritionHistory",
  "getPromotionStatus",
  "getPRTimeline",
  "getFormCues",
];

const names = (isPro: boolean, caps?: string[]) =>
  allTools(isPro, caps ? new Set(caps) : undefined).map((t) => t.name);

Deno.test("no capabilities: today's lists, unchanged (20 PRO / 9 free)", () => {
  assertEquals(names(true), PRO_TODAY);
  assertEquals(names(false), FREE_TODAY);
  assertEquals(names(true, []), PRO_TODAY);
});

Deno.test("swap_workout_days only: today's 21 PRO list", () => {
  const n = names(true, ["swap_workout_days"]);
  assertEquals(n.length, 21);
  assert(n.includes("swapWorkoutDays"));
  assert(!n.includes("requestCompletionTile"));
});

Deno.test("request_completion_tile: the tool appears for PRO (21) and free (10)", () => {
  const pro = names(true, ["request_completion_tile"]);
  const free = names(false, ["request_completion_tile"]);
  assertEquals(pro.length, 21);
  assertEquals(free.length, 10);
  assert(pro.includes("requestCompletionTile"));
  assert(free.includes("requestCompletionTile"));
});

Deno.test("both capabilities: PRO sees 22", () => {
  assertEquals(names(true, ["swap_workout_days", "request_completion_tile"]).length, 22);
});

Deno.test("no other tool carries queuedStatus or queuedNote", () => {
  const all = allTools(true, new Set(["swap_workout_days", "request_completion_tile"]));
  for (const t of all) {
    if (t.name === "requestCompletionTile") continue;
    assertEquals(t.queuedStatus, undefined, t.name);
    assertEquals(t.queuedNote, undefined, t.name);
  }
});

Deno.test("TILE_SURFACING_TOOL_NAMES is {logSet}, and logSet's intent type is log_set", async () => {
  assertEquals([...TILE_SURFACING_TOOL_NAMES], ["logSet"]);
  // deno-lint-ignore no-explicit-any
  const ctx: ToolContext = { userId: "u", isPro: false, sb: null as any, requestId: "r" };
  const intent = await logSetTool.intentBuilder!(
    { exerciseId: "x", weightKg: 1, reps: 1, sets: 1 },
    ctx,
  );
  assertEquals(intent.type, "log_set");
});
