// supabase/functions/_shared/partial_day_count.ts
//
// PURE, no IO. The server's mirror of the client's coach-day rule
// (`decideCoachDay` + `loggedPlannedExerciseCount` in
// lib/features/train/services/coach_day_completion.dart) for the 8 pm and 9 pm
// reminders (coach workout parity 2, OI-492): a PARTIAL day is one where some,
// but not all, of today's planned exercises are logged and nothing has marked
// the day done. `null` is the one rule for "cannot count": the caller keeps
// today's line.

import { sanitizeIdentifier } from "./sanitize_for_prompt.ts";

export interface PartialDay {
  planned: number;
  logged: number;
  /** Planned exercises not yet logged. Always >= 1. */
  left: number;
}

/** A partial day plus the plan day's display name (same name the tile shows). */
export interface PartialDayInfo extends PartialDay {
  workoutName: string;
}

/** Fallback when the plan row has no usable name. */
export const PARTIAL_DAY_FALLBACK_NAME = "your workout";

/**
 * Mirror of the client's `kPlaceholderWorkoutNames`
 * (lib/core/services/workout_write_service.dart:71).
 */
const PLACEHOLDER_NAMES = new Set(["workout", "chat workout"]);

/** The `exlogKey` normalisation: lower-case + trim. Non-strings never match. */
function key(v: unknown): string {
  return typeof v === "string" ? v.toLowerCase().trim() : "";
}

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

/**
 * Counts today's planned exercises against the logged exercise names.
 *
 * Returns `null` ("cannot count") unless ALL hold:
 *  - `planRow` is an object; `status` is a string or absent and not
 *    `completed` / `moved` / `dropped`; `type !== 'rest'`;
 *  - `exercises` is an array with at least one object element (maps only);
 *  - EVERY logged name matches some planned `exercise_name` or `swapped_from`
 *    (the stale-plan guard: a logged name the plan copy does not know means the
 *    plan copy is stale, or the log is off-plan, and a conservative null keeps
 *    today's line instead of a wrong count);
 *  - at least one planned exercise is logged, and not all of them.
 *
 * A planned exercise counts as logged when its `exercise_name` OR its
 * `swapped_from` is in the (lower-cased, trimmed) logged set.
 */
export function countPartialDay(
  planRow: unknown,
  loggedNames: Iterable<string>,
): PartialDay | null {
  if (!isPlainObject(planRow)) return null;

  const status = planRow.status;
  if (status !== undefined && status !== null && typeof status !== "string") {
    return null;
  }
  if (status === "completed" || status === "moved" || status === "dropped") {
    return null;
  }
  if (planRow.type === "rest") return null;

  if (!Array.isArray(planRow.exercises)) return null;
  // No explicit empty-plan return: with zero planned exercises `matched` stays
  // 0 (null below), and any logged name trips the stale-plan guard first. A
  // separate `planned.length === 0` check was an unkillable equivalent mutant
  // (M55c, implementation 2026-11-11) and was removed.
  const planned = planRow.exercises.filter(isPlainObject);

  const logged = new Set<string>();
  for (const n of loggedNames) {
    if (typeof n === "string") logged.add(n.toLowerCase().trim());
  }

  const plannedKeys = new Set<string>();
  let matched = 0;
  for (const ex of planned) {
    const name = key(ex.exercise_name);
    const swappedFrom = key(ex.swapped_from);
    if (name) plannedKeys.add(name);
    if (swappedFrom) plannedKeys.add(swappedFrom);
    if ((name && logged.has(name)) || (swappedFrom && logged.has(swappedFrom))) {
      matched++;
    }
  }

  // Stale-plan guard: every logged name must be one the plan knows.
  for (const n of logged) {
    if (!plannedKeys.has(n)) return null;
  }

  if (matched === 0 || matched >= planned.length) return null;
  return { planned: planned.length, logged: matched, left: planned.length - matched };
}

/**
 * The plan day's display name: trimmed `workout_name`, dropped when empty or a
 * placeholder, else sanitised and capped at 40 characters (the push may show a
 * shorter name than the tile for a name over 40: accepted, R7). Never empty and
 * never throws: a non-string `workout_name` yields the fallback.
 */
export function partialDayWorkoutName(planRow: unknown): string {
  if (!isPlainObject(planRow)) return PARTIAL_DAY_FALLBACK_NAME;
  const raw = planRow.workout_name;
  if (typeof raw !== "string") return PARTIAL_DAY_FALLBACK_NAME;
  const name = raw.trim();
  if (name.length === 0 || PLACEHOLDER_NAMES.has(name.toLowerCase())) {
    return PARTIAL_DAY_FALLBACK_NAME;
  }
  return sanitizeIdentifier(name, { maxLen: 40, fallback: PARTIAL_DAY_FALLBACK_NAME });
}

/** Kill switch `DISABLE_PARTIAL_DAY_REMINDER`: exactly lowercase `"true"`. */
export function partialDayKillSwitchOn(envValue: string | undefined): boolean {
  return envValue === "true";
}
