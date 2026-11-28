// supabase/functions/_shared/partial_day_loader.ts
//
// IO half of the partial-day reminder count (coach workout parity 2, OI-492).
// One `user_progress` plan read and one `workout_log_exercises` read per user
// chunk, both bounded through fetchAllByIds and both scoped with
// `.in("user_id", chunk)`; the pure rule lives in partial_day_count.ts.
//
// This is ENRICHMENT of a push message, not an exclusion set: any failure is
// caught INSIDE the loader and degrades to an empty map (every caller then
// sends today's line), unlike the callers' own exclusion reads, which throw.

import { fetchAllByIds } from "./paged_fetch.ts";
import { workoutLogIdForDate } from "./uuid_v5.ts";
import {
  countPartialDay,
  type PartialDayInfo,
  partialDayKillSwitchOn,
  partialDayWorkoutName,
} from "./partial_day_count.ts";

export type { PartialDayInfo } from "./partial_day_count.ts";

/**
 * Chunk size of the FALLBACK plan read, which selects the whole
 * `plan_json->schedules` object (every `schedule_*` key, tens of KB per user).
 * Hard cap: never above 10.
 */
export const PLAN_FALLBACK_CHUNK_SIZE = 10;

export interface LoaderDeps {
  /** Per-user rule; default = countPartialDay + partialDayWorkoutName. */
  computeUser: (
    todayRow: unknown,
    names: ReadonlySet<string>,
  ) => PartialDayInfo | null;
  workoutLogIdForDate: (istDate: string) => Promise<string>;
  /**
   * Which plan read ships. `primary` selects only today's schedule row through a
   * JSON path; `fallback` selects `plan_json->schedules` and picks today's key
   * in code. Which one works against live PostgREST is recorded in the S2
   * diagnose-doc (hard precondition for the deploy, U2).
   */
  planRead: "primary" | "fallback";
}

/** The default per-user rule. */
export function defaultComputeUser(
  todayRow: unknown,
  names: ReadonlySet<string>,
): PartialDayInfo | null {
  const pd = countPartialDay(todayRow, names);
  if (!pd) return null;
  return { ...pd, workoutName: partialDayWorkoutName(todayRow) };
}

export function realLoaderDeps(): LoaderDeps {
  return {
    computeUser: defaultComputeUser,
    workoutLogIdForDate,
    planRead: "primary",
  };
}

function errName(e: unknown): string {
  return e instanceof Error ? e.name : "unknown";
}

/**
 * Users with a partial coach day today, keyed by user id. An absent key means
 * "cannot count" (no plan row, nothing logged, all logged, stale plan, read
 * failure, kill switch): the caller keeps today's line.
 */
export async function loadPartialDays(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userIds: string[],
  todayIST: string,
  deps: LoaderDeps = realLoaderDeps(),
): Promise<Map<string, PartialDayInfo>> {
  const out = new Map<string, PartialDayInfo>();
  if (userIds.length === 0) return out;

  try {
    if (partialDayKillSwitchOn(Deno.env.get("DISABLE_PARTIAL_DAY_REMINDER"))) {
      return out;
    }

    const ids = [...new Set(userIds)];
    const workoutLogId = await deps.workoutLogIdForDate(todayIST); // once, BEFORE the chunk callback

    // The select strings are TEMPLATE LITERALS (dynamic date key) on purpose:
    // scripts/check_schema_column_refs.dart only extracts select arguments from
    // plain quoted literals and would misread `today_row:plan_json->...` as a
    // nonexistent `user_progress` column; a backtick template is never matched.
    const planRows = deps.planRead === "fallback"
      ? await fetchAllByIds<Record<string, unknown>>(
        (chunk) =>
          supabase.from("user_progress").select(`id, user_id, schedules:plan_json->schedules`)
            .in("user_id", chunk),
        ids,
        { orderBy: "id", chunkSize: PLAN_FALLBACK_CHUNK_SIZE, label: "partial-day plan (fallback)" },
      )
      : await fetchAllByIds<Record<string, unknown>>(
        (chunk) =>
          supabase.from("user_progress").select(
            `id, user_id, today_row:plan_json->schedules->schedule_${todayIST}`,
          ).in("user_id", chunk),
        ids,
        { orderBy: "id", label: "partial-day plan" },
      );

    const wleRows = await fetchAllByIds<Record<string, unknown>>(
      (chunk) =>
        supabase
          .from("workout_log_exercises")
          .select("id, user_id, exercise_id, exercise_name")
          .in("user_id", chunk)
          .eq("workout_log_id", workoutLogId)
          .is("deleted_at", null),
      ids,
      { orderBy: "id", label: "partial-day wle" },
    );

    // Group by the row's own user_id; only REQUESTED ids are ever read back.
    const todayRowByUser = new Map<string, unknown>();
    for (const r of planRows) {
      const uid = r.user_id;
      if (typeof uid !== "string" || todayRowByUser.has(uid)) continue;
      let todayRow: unknown;
      if (deps.planRead === "fallback") {
        const sch = r.schedules;
        todayRow = sch !== null && typeof sch === "object"
          ? (sch as Record<string, unknown>)[`schedule_${todayIST}`]
          : undefined;
      } else {
        todayRow = r.today_row;
      }
      if (todayRow !== undefined && todayRow !== null) todayRowByUser.set(uid, todayRow);
    }
    const namesByUser = new Map<string, Set<string>>();
    for (const r of wleRows) {
      const uid = r.user_id;
      if (typeof uid !== "string") continue;
      const name = typeof r.exercise_name === "string" && r.exercise_name.length > 0
        ? r.exercise_name
        : r.exercise_id;
      if (typeof name !== "string" || name.length === 0) continue;
      let set = namesByUser.get(uid);
      if (!set) namesByUser.set(uid, set = new Set<string>());
      set.add(name);
    }

    let counted = 0;
    let nullCount = 0;
    let threw = 0;
    for (const uid of ids) {
      const todayRow = todayRowByUser.get(uid);
      if (todayRow === undefined) {
        nullCount++;
        continue;
      }
      try {
        const info = deps.computeUser(todayRow, namesByUser.get(uid) ?? new Set<string>());
        if (info) {
          out.set(uid, info);
          counted++;
        } else {
          nullCount++;
        }
      } catch {
        nullCount++;
        threw++;
      }
    }

    console.log(`[partial-day] users=${ids.length} counted=${counted} null=${nullCount}`);
    if (threw > 0) console.log(`[partial-day] count-threw=${threw}`);
    return out;
  } catch (e) {
    console.error(`[partial-day] read failed: ${errName(e)}`);
    return new Map<string, PartialDayInfo>();
  }
}
