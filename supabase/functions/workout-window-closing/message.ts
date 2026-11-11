import type { PartialDayInfo } from "../_shared/partial_day_count.ts";

export function buildWindowClosingMessage(firstName: string | null, workoutName: string): string {
  const greeting = firstName ? `${firstName} — ` : "";
  return `${greeting}haven't seen ${workoutName} logged yet. Still happening? Even 20 mins counts.`;
}

/**
 * The 9 pm line: on a partial day (some, not all planned exercises logged)
 * "<name> — 1 exercise left in <plan day>. Finish up and tap Complete."; any
 * other state is today's "haven't seen it logged" line, byte-identical, with
 * the TEMPLATE name (coach workout parity 2, OI-492).
 */
export function selectWindowClosingMessage(
  pd: PartialDayInfo | null,
  firstName: string | null,
  templateWorkoutName: string,
): string {
  if (pd && pd.left >= 1) {
    const greeting = firstName ? `${firstName} — ` : "";
    return `${greeting}${pd.left} exercise${pd.left === 1 ? "" : "s"} left in ${pd.workoutName}. Finish up and tap Complete.`;
  }
  return buildWindowClosingMessage(firstName, templateWorkoutName);
}

/**
 * Where the push opens. A partial-day push opens Train (Train shows a partial
 * day and completes it; the 8 pm push already opens /train); the not-trained
 * line keeps /ai_coach. Chosen from the same condition as the message, so the
 * two cannot diverge.
 */
export function windowClosingScreen(pd: PartialDayInfo | null): string {
  return pd && pd.left >= 1 ? "/train" : "/ai_coach";
}
