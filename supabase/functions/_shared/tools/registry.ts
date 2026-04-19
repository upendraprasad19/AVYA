import { ToolDefinition, ToolTier } from "./types.ts";
import {
  createCustomExerciseTool,
  logSetTool,
  markWorkoutCompleteTool,
  shortenWorkoutTool,
  swapExerciseTool,
} from "./workout/index.ts";
import { getProgressSummaryTool } from "./progress/index.ts";

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
  // Phase B.3-B.5 will add: modifyWorkoutForInjury, rescheduleWeek,
  //   generateHotelWorkout
  // Phase C will add: nutrition family
  // Phase D will add: plan family
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
