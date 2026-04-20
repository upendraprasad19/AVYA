/**
 * Shared dedup helper for proactive notification triggers.
 *
 * Brainstorm §5 rule: "Never repeat same trigger type two days in a row."
 * Implementation: each function calls shouldSendProactive(supabase, userId, type)
 * BEFORE sending, and markProactiveSent(supabase, userId, type) AFTER successful push.
 *
 * Trigger types (canonical strings — keep in sync with the matrix):
 *   morning_brief, workout_window, protein_gap, streak_protection,
 *   pr_celebration, plateau_alert, weekly_recap, re_engagement,
 *   subscription_expiry
 *
 * Dedup window: same calendar day in IST (the app's primary timezone).
 * Stored as ISO timestamp + type string in coach_memory; we compare
 * IST date components.
 */

import { fetchCoachMemory, upsertCoachMemory } from "./coach_memory.ts";

export type ProactiveType =
  | "morning_brief"
  | "workout_window"
  | "protein_gap"
  | "streak_protection"
  | "pr_celebration"
  | "plateau_alert"
  | "weekly_recap"
  | "re_engagement"
  | "subscription_expiry";

/**
 * Returns true if this proactive type can be sent now (i.e. NOT already
 * sent today in IST). Respects coach_memory.private_mode by ALWAYS allowing
 * sends — private_mode only suppresses personalization in copy, not the
 * fact of sending operationally important nudges.
 *
 * Returns true ALSO when coach_memory row doesn't exist yet (new user) —
 * we want them to receive their first nudge.
 */
export async function shouldSendProactive(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  type: ProactiveType,
): Promise<boolean> {
  try {
    const memory = await fetchCoachMemory(supabase, userId);
    if (!memory) return true; // new user — allow

    const lastType = memory.last_proactive_type as string | null | undefined;
    const lastAt = memory.updated_at as string | null | undefined;
    if (!lastType || !lastAt) return true;
    if (lastType !== type) return true; // different type — fine to send

    // Same type — check if it was today in IST
    return !isSameISTDate(lastAt, new Date().toISOString());
  } catch (e) {
    // Defensive: dedup failure should never block a nudge.
    console.warn(`[proactive_dedup] shouldSend check failed for ${userId}/${type}:`, e);
    return true;
  }
}

/**
 * Records that a proactive of this type was just sent. Updates
 * coach_memory.last_proactive_type. Non-fatal on failure (the push
 * already went out).
 */
export async function markProactiveSent(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  type: ProactiveType,
): Promise<void> {
  try {
    await upsertCoachMemory(supabase, userId, {
      last_proactive_type: type,
    });
  } catch (e) {
    console.warn(`[proactive_dedup] markSent failed for ${userId}/${type}:`, e);
  }
}

/** Returns true if both ISO timestamps fall on the same calendar date in IST (UTC+5:30). */
function isSameISTDate(a: string, b: string): boolean {
  const da = new Date(a);
  const db = new Date(b);
  // IST = UTC + 5:30 → add 5*60+30 = 330 minutes
  const aIst = new Date(da.getTime() + 330 * 60_000);
  const bIst = new Date(db.getTime() + 330 * 60_000);
  return (
    aIst.getUTCFullYear() === bIst.getUTCFullYear() &&
    aIst.getUTCMonth() === bIst.getUTCMonth() &&
    aIst.getUTCDate() === bIst.getUTCDate()
  );
}
