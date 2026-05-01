import { ToolDefinition, ToolTier } from "./types.ts";
import {
  createCustomExerciseTool,
  generateHotelWorkoutTool,
  logSetTool,
  markWorkoutCompleteTool,
  modifyWorkoutForInjuryTool,
  rescheduleWeekTool,
  shortenWorkoutTool,
  swapExerciseTool,
} from "./workout/index.ts";
import {
  getExerciseHistoryTool,
  getPRTimelineTool,
  getProgressSummaryTool,
  getPromotionStatusTool,
  logPRTool,
} from "./progress/index.ts";
import {
  adjustCaloricTargetTool,
  getNutritionHistoryTool,
  logMealByTextTool,
  prelogTool,
  suggestMealTool,
} from "./nutrition/index.ts";
import {
  createCustomTemplateTool,
  pausePlanTool,
  regeneratePlanBlockTool,
  scheduleTemplateTool,
  switchGoalTool,
} from "./plan/index.ts";
import { getFormCuesTool } from "./exercise/index.ts";

const ALL_TOOLS: ToolDefinition[] = [
  // Phase A anchor tools — one per confirmation class, one per tool kind.
  swapExerciseTool, // workout / write / reviewable / PRO
  logSetTool, // workout / write / trivial / FREE
  getProgressSummaryTool, // progress / read / FREE
  // Phase B.1
  markWorkoutCompleteTool, // workout / write / trivial / FREE
  shortenWorkoutTool, // workout / write / trivial / FREE
  // Phase B.2
  createCustomExerciseTool, // workout / write / reviewable / FREE
  // Phase B.3
  modifyWorkoutForInjuryTool, // workout / write / destructive / PRO
  // Phase B.4
  rescheduleWeekTool, // workout / write / destructive / PRO
  // Phase B.5
  generateHotelWorkoutTool, // workout / write / destructive / PRO
  // ── Phase C: nutrition family ─────────────────────────────────────
  // Append future C-phase tools below this marker.
  logMealByTextTool, // nutrition / write / trivial / FREE  (C.1)
  adjustCaloricTargetTool, // nutrition / write / trivial-or-reviewable / PRO  (C.2)
  suggestMealTool, // nutrition / read / PRO  (C.3)
  prelogTool, // nutrition / write / reviewable-or-destructive / PRO  (C.4)
  getNutritionHistoryTool, // nutrition / read / FREE  (C.5 — past-date food/macros)
  // ── Phase D: progress family expansion ────────────────────────────
  // Append future D-phase tools below this marker.
  getExerciseHistoryTool, // progress / read / PRO  (D.1)
  logPRTool, // progress / write / trivial / FREE  (D.2)
  getPromotionStatusTool, // progress / read / FREE  (C5 — rank ladder + ETAs)
  getPRTimelineTool, // progress / read / FREE  (C7 — dated PR history, optional date range)
  // ── Phase D.3: plan family ────────────────────────────────────────
  // First plan-family tool. Append future plan tools below this marker.
  regeneratePlanBlockTool, // plan / write / destructive / PRO  (D.3)
  pausePlanTool, // plan / write / destructive / PRO  (D.4)
  switchGoalTool, // plan / write / destructive / PRO  (D.5)
  createCustomTemplateTool, // plan / write / destructive / PRO  (D.6)
  scheduleTemplateTool, // plan / write / destructive / PRO  (D.7)
  // ── Phase C.6: exercise family ────────────────────────────────────
  getFormCuesTool, // exercise / read / FREE  (C.6 — coaching cues + common mistakes)
];

/**
 * Returns the subset of tools available to a user given their tier.
 * Free users get only `tier='free'` tools; PRO users get everything.
 */
export function allTools(isPro: boolean): ToolDefinition[] {
  return ALL_TOOLS.filter((t) => isPro || t.tier === "free");
}

/**
 * Look up a tool by name regardless of tier. The caller (tool-loop) is responsible for tier enforcement.
 * Returns undefined if not found.
 */
export function byName(name: string): ToolDefinition | undefined {
  return ALL_TOOLS.find((t) => t.name === name);
}

/**
 * Internal: register a tool. Tools should NOT call this directly; instead, they're added to ALL_TOOLS
 * by the family barrel files in this directory tree (workout/, nutrition/, etc.).
 */
export function _registerToolForTesting(tool: ToolDefinition): void {
  ALL_TOOLS.push(tool);
}

/** TEST-ONLY: clear the registry. Used by unit tests to set up isolated state. */
export function _clearRegistryForTesting(): void {
  ALL_TOOLS.length = 0;
}
