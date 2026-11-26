// supabase/functions/_shared/tools/workout/requestCompletionTile.ts
//
// Coach workout parity S3 (OI-492, founder decision C): "I'm done" in chat
// makes the app's own "X of Y - Complete workout" tile appear (one tap total).
// The tool asserts nothing and never completes: the client re-runs the app's
// own decision (decideCoachDay) for IST today and re-shows its own tile only
// when the day is part logged. The tap stays the user's (ADR-0012).
//
// Not an APPLY card: the intent type is auto-run (AUTO_RUN_INTENT_TYPES in
// _shared/completion_tile_routing.ts) and the tool loop handles this tool in a
// dedicated branch (queued once, after the loop; dropped when sets are logged
// in the same turn). `name`, `requiresCapability` and the intent `type` are
// string LITERALS: the coverage gate's regex cannot read an identifier, and a
// Deno test pins each literal to the routing file's const. This file imports
// only zod and types.ts.

import { z } from "npm:zod@3.25.76";
import type { ToolDefinition } from "../types.ts";

// One required single-value enum so the Gemini declaration never has empty
// `properties` (zodToGemini emits OBJECT with properties {} for z.object({})).
const schema = z.object({
  trigger: z.enum(["user_says_done"]).describe("Always user_says_done."),
});

type Args = z.infer<typeof schema>;

export const requestCompletionTileTool: ToolDefinition<Args> = {
  name: "requestCompletionTile",
  family: "workout",
  kind: "write",
  confirmationClass: "trivial",
  tier: "free",
  requiresCapability: "request_completion_tile",
  description:
    "Show the user's Complete workout tile when they say they are finished with today's workout and today's workout is only part logged. The app re-checks and shows the tile only if it applies. This does NOT complete anything.",
  selectionHints:
    "Call only when the user says they are done with today's workout and the snapshot shows today_workout is part logged (not completed, not rest, all_logged false, exercises non-empty). NOT for logging sets (logSet), NOT for rest days.",
  schema,
  queuedStatus: "tile_requested",
  queuedNote:
    "The tile is shown under this reply unless you also log sets this turn, and only if the day is part logged. NOTHING is completed. There is no APPLY card. Do not say the workout is done, completed, counted or marked. Say: Tap Complete workout on the tile below to finish today.",
  intentBuilder: () => ({
    type: "request_completion_tile",
    payload: {},
    confirmationClass: "trivial",
    previewSummary: "Show the Complete workout tile",
  }),
};
