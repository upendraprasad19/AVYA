import { ToolDefinition, ToolTier } from "./types.ts";

// Will be populated as tools are added in subsequent tasks (Phase A.5+).
// For now, this is empty — the framework is in place but no tools are registered yet.
const ALL_TOOLS: ToolDefinition[] = [
  // Phase A.5 will add: swapExercise, logSet, getProgressSummary
  // Phase B will add: workout family
  // Phase C will add: nutrition family
  // Phase D will add: progress + plan family
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
