// supabase/functions/_shared/completion_tile_routing.ts
//
// Coach workout parity S3 (OI-492, founder decision C): "I'm done" in chat
// makes the app's own "X of Y - Complete workout" tile appear, one tap total.
// The tool `requestCompletionTile` asserts nothing and never completes: it asks
// the app to re-run its own decision for IST today and re-show its own tile
// (ADR-0012 derive-only). Plan: docs/plans/coach-workout-parity-2-server.md
// section 3.1 and the authoritative checklist 3.1.1.
//
// This file OWNS the tile constants and imports nothing from `_shared/tools/`
// (the tool file imports only zod and types.ts and writes string literals that
// the coverage gate can read; a Deno test pins literal === const).

/** The client capability an app build declares when it can run the tile intent. */
export const CAPABILITY_REQUEST_COMPLETION_TILE = "request_completion_tile";

/** The tool's name as the model calls it. The tool loop's tile branch keys on it. */
export const REQUEST_COMPLETION_TILE_TOOL_NAME = "requestCompletionTile";

/**
 * Intent types the client runs at once, with no APPLY card. FC2's fallback
 * text and the semantic-memory marker treat them differently from queued
 * intents.
 */
export const AUTO_RUN_INTENT_TYPES: ReadonlySet<string> = new Set([
  "request_completion_tile",
]);

/**
 * Tools whose APPLY itself surfaces the tile (the client's only production
 * caller of `_maybeCompleteScheduledDay` is `_executeLogSet`). A meal log does
 * NOT surface a workout tile, so it is not in this set. The NAME only picks
 * the note the model reads for a tile call in the same response
 * (`COMPLETION_TILE_SAME_RESPONSE_NOTE`); whether the tile is dropped is
 * decided after the loop from the real intents (a logSet call that fails
 * validation queues nothing, so the tile must still show; B-pass seat 1 F1).
 */
export const TILE_SURFACING_TOOL_NAMES: ReadonlySet<string> = new Set([
  "logSet",
]);

/** The coach's line after the call (4.1). Also the end of the AUTO note. */
export const COMPLETION_TILE_REPLY_LINE =
  "Tap Complete workout on the tile below to finish today.";

/** Not partial: the day is already completed (4.1). */
export const TILE_NOT_PARTIAL_COMPLETED_LINE =
  "Today's workout is already counted.";

/** Not partial: rest, moved, or no plan (4.1). */
export const TILE_NOT_PARTIAL_NO_PLAN_LINE =
  "No planned workout today, so there is nothing to complete.";

/** Not partial: every planned exercise is logged (4.1). */
export const TILE_NOT_PARTIAL_ALL_LOGGED_LINE =
  "Every planned exercise is in. If Train does not show the day as counted, tap Complete workout on the Train tab.";

/** Not partial: nothing logged yet (the existing approved line in WRITE_CLAIM_RULE). */
export const TILE_NOT_PARTIAL_NOTHING_LOGGED_LINE =
  "Nothing logged yet. Send the sets and I'll queue it.";

/** FC2 fallback when every emitted intent is auto-run (4.1). */
export const COMPLETION_TILE_FC2_AUTO_TEXT =
  "Copy that. If today's workout is part way through, tap Complete workout on the tile below.";

/** functionResponse note for a tile request that is recorded (status tile_requested). */
export const COMPLETION_TILE_QUEUED_NOTE =
  `The tile is shown under this reply unless you also log sets this turn, and only if the day is part logged. NOTHING is completed. There is no APPLY card. Do not say the workout is done, completed, counted or marked. Say: ${COMPLETION_TILE_REPLY_LINE}`;

/** functionResponse note for a tile request dropped because sets were already queued earlier in the turn. */
export const COMPLETION_TILE_NOT_NEEDED_NOTE =
  "The logged sets will show the tile after the user taps APPLY";

/**
 * functionResponse note for a tile request in a response that also calls
 * logSet: the outcome is not known yet (that logSet may fail validation), so
 * the note covers both cases. Model-facing only.
 */
export const COMPLETION_TILE_SAME_RESPONSE_NOTE =
  "If the sets in this reply are queued, the tile shows after the user taps APPLY on them; if not, the tile shows under this reply when the day is part logged. NOTHING is completed. Do not say the workout is done, completed, counted or marked.";

const COMPLETION_TILE_BLOCK = `
## COMPLETE WORKOUT TILE — "I'm done"
- Call requestCompletionTile ONLY when the user says they are finished with today's workout AND, in the snapshot, today_workout.status is not completed, moved or dropped, today_workout.type is not rest, today_workout.today_workout_completion.all_logged is false, and today_workout.exercises is non-empty (something is logged today). The app re-checks. Never call it to log anything.
- When the user says they are finished and today_workout.exercises is non-empty, call requestCompletionTile (if the conditions above hold) instead of asking them to describe exercises, sets, reps or weights; the rule for a finished workout without exercise details still applies when nothing is logged today. requestCompletionTile is an action, not a data read; the rule against calling a tool for today's data covers reads only.
- Never call requestCompletionTile in a turn that also logs sets (logSet in the same response); a meal log does not count. The logged sets show the tile once the user confirms them.
- After the call, say: "${COMPLETION_TILE_REPLY_LINE}"
- If the snapshot says the day is not part logged, do NOT call the tool; say the matching line:
  - already completed: "${TILE_NOT_PARTIAL_COMPLETED_LINE}"
  - rest day, moved, or no plan: "${TILE_NOT_PARTIAL_NO_PLAN_LINE}"
  - all planned exercises logged: "${TILE_NOT_PARTIAL_ALL_LOGGED_LINE}"
  - nothing logged yet: "${TILE_NOT_PARTIAL_NOTHING_LOGGED_LINE}"
- After you call requestCompletionTile, never say the workout is completed, done, counted or marked. The lines above describe the snapshot, not this reply.
`;

/**
 * The per-request prompt block. `""` unless the client declared the
 * capability; identical with the write-claim rule on or off. The caller pushes
 * it only when non-empty (an empty part would still add a separator).
 */
export function completionTileRoutingBlock(
  capabilities: ReadonlySet<string>,
): string {
  return capabilities.has(CAPABILITY_REQUEST_COMPLETION_TILE)
    ? COMPLETION_TILE_BLOCK
    : "";
}

/** The addendum text after WRITE_CLAIM_RULE (copy for founder approval, 4.1). */
export const COMPLETION_TILE_WRITE_CLAIM_ADDENDUM_TEXT =
  "The Complete workout tile (requestCompletionTile) is not a card and never counts as a proposal for the queued lines; never say Queued or APPLY for it. Any other proposal in the same reply keeps its own queued line.";

/**
 * Appended AFTER `writeClaimSuffix(ruleOn)` so it is the last text the model
 * reads. `""` without the capability or with the write-claim rule off.
 */
export function completionTileWriteClaimAddendum(
  capabilities: ReadonlySet<string>,
  writeClaimRule: boolean,
): string {
  if (!writeClaimRule) return "";
  if (!capabilities.has(CAPABILITY_REQUEST_COMPLETION_TILE)) return "";
  return `\n\n${COMPLETION_TILE_WRITE_CLAIM_ADDENDUM_TEXT}`;
}

/**
 * Kill switch `DISABLE_COMPLETION_TILE_TOOL`: exactly lowercase `"true"`
 * removes the capability from the set (in place; the same set is returned),
 * which is identical to an old app build. Anything else leaves it.
 */
export function applyCompletionTileKillSwitch(
  capabilities: Set<string>,
  envValue: string | undefined,
): Set<string> {
  if (envValue === "true") {
    capabilities.delete(CAPABILITY_REQUEST_COMPLETION_TILE);
  }
  return capabilities;
}

/**
 * The marker the embedded semantic-memory turn carries for this request's
 * intents: ` [queued: <types>]` for ordinary intents, and a neutral
 * ` [requested: completion tile]` for auto-run types, so a later retrieval
 * never tells the model a tile was "queued" and still shows an action
 * happened.
 */
export function memoryIntentSummary(
  intents: ReadonlyArray<{ type: string }>,
): string {
  const queued = intents
    .map((i) => i.type)
    .filter((t) => !AUTO_RUN_INTENT_TYPES.has(t));
  const hasAuto = intents.some((i) => AUTO_RUN_INTENT_TYPES.has(i.type));
  let out = "";
  if (queued.length > 0) out += ` [queued: ${queued.join(", ")}]`;
  if (hasAuto) out += " [requested: completion tile]";
  return out;
}
