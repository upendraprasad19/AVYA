// supabase/functions/_shared/write_claim_prompt.ts
//
// coach-log-truth (OI-368 / OI-369, plan docs/plans/coach-log-truth.md §2.2):
// the coach must never say something is logged, saved or done before it is.
// Nothing the coach proposes is saved when it replies: a tool proposal waits
// for APPLY, a workout tag for CONFIRM, a water/weight/food/sleep/measurement
// tag for a 5-second countdown. This module holds every prompt piece that
// teaches that, kept OUT of CAPTAIN_MANUAL (weekly-report imports it too).
//
// Kill switch DISABLE_WRITE_CLAIM_RULE (exactly "true" disables): every
// builder then returns today's bytes (golden-pinned against origin/main by
// write_claim_prompt_test.ts), and writeClaimSuffix returns "".

import type { ToolDefinition } from "./tools/types.ts";

/** True only when DISABLE_WRITE_CLAIM_RULE is exactly "true". Read once per request. */
export function isWriteClaimRuleDisabled(
  get: (name: string) => string | undefined = (n) => Deno.env.get(n),
): boolean {
  return get("DISABLE_WRITE_CLAIM_RULE") === "true";
}

const OLD_HEADER = "FITNESS DATA LOGGING — INSTANT:";
const NEW_HEADER =
  "FITNESS DATA LOGGING — A CARD FIRST; NOTHING IS SAVED WHEN YOU REPLY:";

function header(enabled: boolean): string {
  return enabled ? NEW_HEADER : OLD_HEADER;
}

/**
 * The ai-proxy ICBF_LOG tag protocol, moved here verbatim from
 * ai-proxy/index.ts. Only the header line depends on [enabled].
 */
export function icbfLogInstructions(enabled: boolean): string {
  return `
${header(enabled)}
When the user explicitly states they ALREADY completed an action, embed ONE tag at the END of your response:
<ICBF_LOG>{"action":"log_water","data":{"ml":500}}</ICBF_LOG>
<ICBF_LOG>{"action":"log_weight","data":{"weight_kg":73.5}}</ICBF_LOG>
<ICBF_LOG>{"action":"log_food","data":{"food_name":"Dal Rice","meal_type":"lunch","quantity_g":200,"calories_estimate":280,"protein_estimate":9,"carbs_estimate":55,"fat_estimate":3}}</ICBF_LOG>
<ICBF_LOG>{"action":"log_sleep","data":{"duration_hrs":7,"quality":"good"}}</ICBF_LOG>
<ICBF_LOG>{"action":"log_measurement","data":{"type":"waist","value_cm":82}}</ICBF_LOG>
Measurement types: waist, chest, hips, arms. Convert inches to cm (multiply by 2.54).
Water: 2 glasses=500ml, 1 bottle=750ml, 1 cup=250ml, 1 litre=1000ml.
RULES:
- Only for CONFIRMED PAST actions (I drank, I weighed, I ate, I slept, my waist is). NEVER for future plans or questions.
- The tag is stripped server-side — do not mention it in your visible response.
- One tag per response maximum.

WORKOUT LOGGING — MULTI-TURN:
- If user says they finished a workout WITHOUT exercise details, ask them to describe exercises, sets, reps, weights. No tag yet.
- If user provides exercise details, parse them and emit:
<ICBF_LOG>{"action":"confirm_workout_log","data":{"exercises":[{"name":"Bench Press","logging_type":"weight_reps","sets":[{"weight_kg":80,"reps":8}]},{"name":"Push-ups","logging_type":"bodyweight_reps","sets":[{"reps":15}]},{"name":"Plank","logging_type":"timed","sets":[{"duration_secs":60}]},{"name":"Running","logging_type":"cardio","duration_mins":30,"distance_km":5}]}}</ICBF_LOG>
Parse "5x8 at 80kg" as 5 sets of 8 reps at 80kg. logging_type: weight_reps (weight+reps), bodyweight_reps (reps only), timed (duration), cardio (time/distance).
`;
}

/**
 * The ai-media-proxy ICBF substring (from "\n\nFITNESS DATA LOGGING" to the
 * end of its prompt concatenation), moved here verbatim. Only the header
 * line depends on [enabled].
 */
export function mediaIcbfLogInstructions(enabled: boolean): string {
  return "\n\n" + header(enabled) +
    "\nWhen the user explicitly states they ALREADY completed an action, embed ONE tag at the END of your response:" +
    '\n<ICBF_LOG>{"action":"log_water","data":{"ml":500}}</ICBF_LOG>' +
    '\n<ICBF_LOG>{"action":"log_weight","data":{"weight_kg":73.5}}</ICBF_LOG>' +
    '\n<ICBF_LOG>{"action":"log_food","data":{"food_name":"Dal Rice","meal_type":"lunch","quantity_g":200,"calories_estimate":280,"protein_estimate":9,"carbs_estimate":55,"fat_estimate":3}}</ICBF_LOG>' +
    '\n<ICBF_LOG>{"action":"log_sleep","data":{"duration_hrs":7,"quality":"good"}}</ICBF_LOG>' +
    '\n<ICBF_LOG>{"action":"log_measurement","data":{"type":"waist","value_cm":82}}</ICBF_LOG>' +
    "\nMeasurement types: waist, chest, hips, arms. Convert inches to cm (multiply by 2.54)." +
    "\nWater: 2 glasses=500ml, 1 bottle=750ml, 1 cup=250ml, 1 litre=1000ml." +
    "\nRULES:" +
    "\n- Only for CONFIRMED PAST actions (I drank, I weighed, I ate, I slept, my waist is). NEVER for future plans or questions." +
    "\n- The tag is stripped server-side — do not mention it in your visible response." +
    "\n- One tag per response maximum." +
    "\n\nWORKOUT LOGGING — MULTI-TURN:" +
    "\n- If user says they finished a workout WITHOUT exercise details, ask them to describe exercises, sets, reps, weights. No tag yet." +
    "\n- If user provides exercise details, parse them and emit:" +
    '\n<ICBF_LOG>{"action":"confirm_workout_log","data":{"exercises":[{"name":"Bench Press","logging_type":"weight_reps","sets":[{"weight_kg":80,"reps":8}]},{"name":"Push-ups","logging_type":"bodyweight_reps","sets":[{"reps":15}]},{"name":"Plank","logging_type":"timed","sets":[{"duration_secs":60}]},{"name":"Running","logging_type":"cardio","duration_mins":30,"distance_km":5}]}}</ICBF_LOG>' +
    '\nParse "5x8 at 80kg" as 5 sets of 8 reps at 80kg. logging_type: weight_reps (weight+reps), bodyweight_reps (reps only), timed (duration), cardio (time/distance).';
}

/** The rule for ai-proxy, which offers tools (plan §2.2). */
export const WRITE_CLAIM_RULE = `WRITE CLAIMS — NOTHING IS SAVED WHEN YOU REPLY:
- Anything you propose is NOT saved when you reply. What you proposed with a tool waits for the user to tap APPLY on its card. A workout tag waits for CONFIRM. A water, weight, food, sleep or measurement tag saves after a 5-second countdown unless the user taps SKIP. If you used a tool and a tag for the same item, use the APPLY line.
- Never say logged, saved, recorded, added, tracked, locked in, squared away, on the books or done, and never say swapped, paused, switched, moved, rescheduled, marked, completed, updated or all set, about anything you propose in this reply. Say it is queued, in these words: "Queued. Tap APPLY to log it." (a set or meal you proposed with a tool), "Queued. Tap CONFIRM to log it." (a workout tag), "Queued. It logs in 5 seconds unless you tap SKIP." (a water, weight, food, sleep or measurement tag), "Queued. Tap APPLY to confirm." (any other action you proposed with a tool). If you proposed two or more items and all were tool proposals, say "Queued. Tap APPLY on each card." once; if you mixed tools and tags, give each kind its own line. Put the queued line(s) FIRST in your reply (a countdown card starts when it appears). Only when swapWorkoutDays is the only thing you proposed, the DAY SWAP ROUTING sentence "Tap APPLY below to swap them." is your queued line and may come last; with other proposals, the lines above apply. For a template you proposed with a tool, say "Queued. Tap APPLY to save it."
- If the user asked you to log something and you proposed nothing, do not say anything was logged or queued. Say what you still need. For a workout with no sets, and only when the snapshot shows no entry for that exercise today: "Nothing logged yet. Send the sets and I'll queue it." If it does show one, ask only for the new sets.
- If the user asks whether something saved: if the snapshot shows that exact entry, say it is logged. If not, say: "Not in my data yet. If its card is still up, tap APPLY or CONFIRM on it." Do not queue it again unless they ask.
- Say something is logged only when the snapshot or a history tool's result already shows it.`;

/** The rule for ai-media-proxy, which offers no tools: no "tool" anywhere. */
export const MEDIA_WRITE_CLAIM_RULE = `WRITE CLAIMS — NOTHING IS SAVED WHEN YOU REPLY:
- Anything you propose is NOT saved when you reply. A workout tag waits for the user to tap CONFIRM. A water, weight, food, sleep or measurement tag saves after a 5-second countdown unless the user taps SKIP.
- Never say logged, saved, recorded, added, tracked, locked in, squared away, on the books or done, and never say swapped, paused, switched, moved, rescheduled, marked, completed, updated or all set, about anything you propose in this reply. Say it is queued, in these words: "Queued. Tap CONFIRM to log it." (a workout tag), "Queued. It logs in 5 seconds unless you tap SKIP." (a water, weight, food, sleep or measurement tag). If you proposed both kinds, give each its own line. Put the queued line(s) FIRST in your reply (a countdown card starts when it appears).
- If the user asked you to log something and you proposed nothing, do not say anything was logged or queued. Say what you still need. For a workout with no sets, and only when the snapshot shows no entry for that exercise today: "Nothing logged yet. Send the sets and I'll queue it." If it does show one, ask only for the new sets.
- If the user asks whether something saved: if the snapshot shows that exact entry, say it is logged. If not, say: "Not in my data yet. If its card is still up, tap APPLY or CONFIRM on it." Do not queue it again unless they ask.
- Say something is logged only when the snapshot already shows it.`;

/**
 * Appended unconditionally by the caller: "" when disabled, so the OFF prompt
 * is byte-identical (the separator lives inside the suffix).
 */
export function writeClaimSuffix(
  enabled: boolean,
  opts: { tools?: boolean } = {},
): string {
  if (!enabled) return "";
  return "\n\n" + (opts.tools === false ? MEDIA_WRITE_CLAIM_RULE : WRITE_CLAIM_RULE);
}

/** The note on a queued tool's functionResponse (L1, plan §2.1). */
export const QUEUED_NOTE =
  "NOT saved yet. The user must tap APPLY on the card. Do not say it is logged, saved or done; say it is queued.";

// Exact substrings of the live tool descriptions this module rewrites. The
// test asserts each still exists, so a later edit fails loudly.
export const MEAL_OLD_CARD =
  "Always trivial-class — the user gets a 5-second auto-confirm card showing the parsed nutrition.";
export const MEAL_NEW_CARD =
  "The user gets a card showing the parsed nutrition and must tap APPLY to log it.";
export const MEAL_OLD_LOG = "and log it to the user's nutrition for today";
export const MEAL_NEW_LOG = "and queue it for the user's nutrition today";
export const TEMPLATE_OLD_EXAMPLE =
  "'Saved! Want me to schedule it for Mon/Wed/Fri?'";
export const TEMPLATE_NEW_EXAMPLE =
  "'Queued. Tap APPLY to save it. Want me to schedule it for Mon/Wed/Fri?'";

/**
 * The tool list the model is offered. Enabled: COPIES of logMealByText and
 * scheduleTemplate with their write claims rewritten (a typed meal waits for
 * APPLY; it has no countdown). Disabled: the input array itself, so the
 * declarations are byte-identical.
 */
export function applyWriteClaimDescriptions<T extends ToolDefinition<any>>(
  tools: T[],
  enabled: boolean,
): T[] {
  if (!enabled) return tools;
  return tools.map((t) => {
    if (t.name === "logMealByText") {
      return {
        ...t,
        description: t.description
          .replace(MEAL_OLD_CARD, MEAL_NEW_CARD)
          .replace(MEAL_OLD_LOG, MEAL_NEW_LOG),
      };
    }
    if (t.name === "scheduleTemplate") {
      return {
        ...t,
        description: t.description.replace(
          TEMPLATE_OLD_EXAMPLE,
          TEMPLATE_NEW_EXAMPLE,
        ),
      };
    }
    return t;
  });
}
