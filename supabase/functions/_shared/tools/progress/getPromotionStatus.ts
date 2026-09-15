// supabase/functions/_shared/tools/progress/getPromotionStatus.ts
//
// Captain coach tool: returns full rank ladder progression with ETAs
// at user's actual cadence and at plan cadence.
//
// Source: APK Test #4 Plan C / C5.
// Mirror: see rank_engine.ts + ceremony_text.ts for display names and gate definitions.

import { z } from "npm:zod@3.25.76";
import type { ToolContext, ToolDefinition } from "../types.ts";
import { LADDER, GATES } from "../../rank_engine.ts";
import { rankDisplayFor, rankAddressFor } from "../../ceremony_text.ts";
import { istDateStr } from "../../ist_date.ts";

const schema = z.object({
  scenario_cadence: z
    .number()
    .min(0)
    .max(14)
    .optional()
    .describe(
      "Optional. Hypothetical workouts/week to project against (e.g. 5 for 'what if I train 5 days?'). If omitted, returns both at actual 4-week cadence and at plan cadence.",
    ),
});

type Args = z.infer<typeof schema>;

interface GateRemaining {
  total_workouts?: number;   // workouts still needed
  weeks?: number;            // weeks still needed since signup
  streak_days?: number;      // streak days still needed (approximated as days)
  deployments?: number;      // deployments still needed
}

interface EtaResult {
  days: number;
  approx_date: string; // YYYY-MM-DD
}

interface LadderEntry {
  code: string;
  display: string;
  address: string;
  ordinal: number;
  is_terminal: boolean;
  achieved: boolean;
  binding_constraint: string | null; // e.g. "total_workouts", "weeks", "streak", "deployments", "max_gap"
  remaining: GateRemaining;
  eta_at_actual_cadence: EtaResult | null;
  eta_at_plan_cadence: EtaResult | null;
  eta_at_scenario_cadence: EtaResult | null;
}

interface PromotionStatusResult {
  current_rank_code: string;
  current_rank_display: string;
  current_rank_address: string;
  cadence: {
    actual_4w: number;       // workouts/week averaged over last 28 days
    plan_target: number;     // days_per_week from user_profile
    scenario?: number;       // if scenario_cadence was supplied
  };
  total_workouts: number;
  weeks_since_signup: number;
  streak_days: number;
  deployments_complete: number;
  ladder: LadderEntry[];
}

function isoDatePlusDays(days: number): string {
  // IST-correct: apply the offset THEN take the date string, so near IST midnight
  // (05:30 UTC) the projected date lands in the right IST day, not yesterday UTC.
  return istDateStr(new Date(Date.now() + days * 86_400_000));
}

/** ETA in days for a gap driven purely by workouts, given a cadence in workouts/week. */
function workoutEtaDays(workoutsNeeded: number, cadencePerWeek: number): number {
  if (cadencePerWeek <= 0) return 99999;
  return Math.ceil((workoutsNeeded * 7) / cadencePerWeek);
}

/** ETA in days for a weeks-since-signup constraint. */
function weeksEtaDays(weeksNeeded: number): number {
  return weeksNeeded * 7;
}

async function handler(
  ctx: ToolContext,
  args: Args,
): Promise<PromotionStatusResult> {
  const { sb, userId } = ctx;

  // ── 1. User profile: current rank + plan cadence ──────────────────────────
  // Unit C (§2.24) — every read below captures its error and throws. Pre-fix a
  // silent DB failure coerced to the `?? "SD2"` / `?? 4` / `?? 0` defaults, so
  // the coach reported a plausible-but-wrong promotion status. A throw is caught
  // per-tool by the tool-loop → Gemini narrates honestly, turn not aborted.
  const { data: profile, error: profErr } = await sb
    .from("user_profile")
    .select("current_rank_code, days_per_week")
    .eq("user_id", userId)
    .maybeSingle();
  if (profErr) throw profErr;

  const currentRankCode = (profile?.current_rank_code as string) ?? "SD2";
  const planTarget = (profile?.days_per_week as number) ?? 4;

  // ── 2. Signup date (from public.users.created_at) ─────────────────────────
  const { data: userRow, error: userErr } = await sb
    .from("users")
    .select("created_at")
    .eq("id", userId)
    .maybeSingle();
  if (userErr) throw userErr;

  const signupDate = userRow
    ? new Date(userRow.created_at as string)
    : new Date(Date.now() - 28 * 86_400_000); // fallback: 4 weeks ago

  const weeksSinceSignup = Math.floor(
    (Date.now() - signupDate.getTime()) / (7 * 86_400_000),
  );

  // ── 3. Total workouts (all-time) ──────────────────────────────────────────
  const { count: totalWorkoutsCount, error: totalWErr } = await sb
    .from("workout_logs")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId);
  if (totalWErr) throw totalWErr;
  const totalWorkouts = totalWorkoutsCount ?? 0;

  // ── 4. Actual cadence: workouts in last 28 days → workouts/week ───────────
  // NOTE: workout_logs uses logged_at (completed_at does not exist on this table).
  const cutoff28 = new Date(Date.now() - 28 * 86_400_000).toISOString();
  const { count: recent28Count, error: recent28Err } = await sb
    .from("workout_logs")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("logged_at", cutoff28);
  if (recent28Err) throw recent28Err;
  const actualCadence = Number(((recent28Count ?? 0) / 4).toFixed(2));

  // ── 5. Progress row: deployments via current_phase ────────────────────────
  // user_progress does NOT have current_streak_days, deployments_complete, or
  // longest_gap_days. We derive:
  //   deploymentsComplete = current_phase - 1  (each phase = 1 deployment done)
  // streakDays and longestGapDays are computed inline from workout_logs.date below.
  const { data: progressRow, error: progressErr } = await sb
    .from("user_progress")
    .select("current_phase")
    .eq("user_id", userId)
    .maybeSingle();
  if (progressErr) throw progressErr;

  const deploymentsComplete = Math.max(
    0,
    ((progressRow?.current_phase as number | undefined) ?? 1) - 1,
  );

  // ── 5a. Streak + gap: computed inline from workout_logs.date ─────────────
  // Pull distinct workout dates from the last year to compute streak and gap.
  const cutoff365 = istDateStr(new Date(Date.now() - 365 * 86_400_000));
  const { data: dateLogs, error: dateLogsErr } = await sb
    .from("workout_logs")
    .select("date")
    .eq("user_id", userId)
    .gte("date", cutoff365)
    .order("date", { ascending: false });
  if (dateLogsErr) throw dateLogsErr;

  // Deduplicate dates and sort descending. Cast `dateLogs` (typed `any` via the
  // `sb: any` context) to a typed row array so `.map` yields `string[]` — otherwise
  // the array infers `unknown[]` and the `.sort()`/`new Date(...)` calls below fail
  // type-checking (Unit C B-pass P2-1).
  const sortedDates: string[] = [
    ...new Set(
      ((dateLogs ?? []) as Array<{ date: string }>).map((r) => r.date),
    ),
  ].sort((a, b) => b.localeCompare(a));

  let streakDays = 0;
  let longestGapDays = 0;
  if (sortedDates.length > 0) {
    // Current streak: count consecutive days back from today/yesterday
    const todayStr = istDateStr(); // IST today, not UTC today
    let cursor = todayStr;
    for (const d of sortedDates) {
      const dayDiff =
        (new Date(cursor).getTime() - new Date(d).getTime()) / 86_400_000;
      if (dayDiff <= 1.5) {
        streakDays++;
        cursor = d;
      } else {
        break;
      }
    }

    // Longest gap: max gap between consecutive workout dates
    for (let i = 0; i < sortedDates.length - 1; i++) {
      const gap =
        (new Date(sortedDates[i]).getTime() -
          new Date(sortedDates[i + 1]).getTime()) /
        86_400_000;
      if (gap > longestGapDays) longestGapDays = Math.floor(gap);
    }
  }

  // ── 6. Current rank index ─────────────────────────────────────────────────
  const currentIdx = LADDER.findIndex((r) => r.code === currentRankCode);

  // ── 7. Build ladder entries ───────────────────────────────────────────────
  const scenarioCadence = args.scenario_cadence;

  const ladder: LadderEntry[] = LADDER.map((entry, idx) => {
    const achieved = idx <= currentIdx;
    const gate = GATES[entry.code] ?? {};

    // Remaining for each gate dimension
    const remWorkouts = Math.max(
      0,
      (gate.totalWorkoutsAtLeast ?? 0) - totalWorkouts,
    );
    const remWeeks = Math.max(
      0,
      (gate.minWeeksSinceSignup ?? entry.minWeeks ?? 0) - weeksSinceSignup,
    );
    const remStreak = Math.max(0, (gate.streakAtLeast ?? 0) - streakDays);
    const remDeployments = Math.max(
      0,
      (gate.deploymentsCompleteAtLeast ?? 0) - deploymentsComplete,
    );
    // maxGapDays is a ceiling constraint, not a "remaining" count
    const gapBlocked =
      gate.maxGapDays !== undefined && longestGapDays > gate.maxGapDays;

    const remaining: GateRemaining = {};
    if (remWorkouts > 0) remaining.total_workouts = remWorkouts;
    if (remWeeks > 0) remaining.weeks = remWeeks;
    if (remStreak > 0) remaining.streak_days = remStreak;
    if (remDeployments > 0) remaining.deployments = remDeployments;

    // Binding constraint: whichever drives the longest ETA
    let bindingConstraint: string | null = null;
    let maxEtaDays = 0;

    if (!achieved) {
      if (gapBlocked) {
        // MCPO-style: current longest gap exceeds limit → streak must restart
        bindingConstraint = "max_gap";
        maxEtaDays = 52 * 7; // need full 52-week gap-free window
      } else {
        // Pick the constraint that takes longest
        const etaCandidates: Array<{ key: string; days: number }> = [];

        if (remWeeks > 0) {
          etaCandidates.push({ key: "weeks", days: weeksEtaDays(remWeeks) });
        }
        if (remWorkouts > 0) {
          const d = workoutEtaDays(remWorkouts, actualCadence);
          etaCandidates.push({ key: "total_workouts", days: d });
        }
        if (remStreak > 0) {
          // Streak days ≈ calendar days (conservative)
          etaCandidates.push({ key: "streak", days: remStreak });
        }
        if (remDeployments > 0) {
          // Deployments = phase completions; rough ETA: 4 weeks per deployment
          etaCandidates.push({
            key: "deployments",
            days: remDeployments * 28,
          });
        }

        for (const c of etaCandidates) {
          if (c.days > maxEtaDays) {
            maxEtaDays = c.days;
            bindingConstraint = c.key;
          }
        }
      }
    }

    // ETA builders — both null when already achieved or constraint isn't workouts-driven
    function buildEta(cadence: number): EtaResult | null {
      if (achieved || (Object.keys(remaining).length === 0 && !gapBlocked)) {
        return null;
      }
      if (gapBlocked) {
        const d = 52 * 7; // must complete a full no-gap 52-week window
        return { days: d, approx_date: isoDatePlusDays(d) };
      }

      // ETA = max of all remaining constraints in days
      let etaDays = 0;

      if (remWeeks > 0) {
        etaDays = Math.max(etaDays, weeksEtaDays(remWeeks));
      }
      if (remWorkouts > 0) {
        const d = workoutEtaDays(remWorkouts, cadence);
        etaDays = Math.max(etaDays, d === 99999 ? 9999 : d);
      }
      if (remStreak > 0) {
        etaDays = Math.max(etaDays, remStreak);
      }
      if (remDeployments > 0) {
        etaDays = Math.max(etaDays, remDeployments * 28);
      }

      return etaDays > 0
        ? { days: etaDays, approx_date: isoDatePlusDays(etaDays) }
        : null;
    }

    const etaActual = achieved ? null : buildEta(actualCadence);
    const etaPlan = achieved ? null : buildEta(planTarget);
    const etaScenario =
      achieved || scenarioCadence === undefined
        ? null
        : buildEta(scenarioCadence);

    return {
      code: entry.code,
      display: rankDisplayFor(entry.code),
      address: rankAddressFor(entry.code),
      ordinal: entry.ordinal,
      is_terminal: entry.isTerminal,
      achieved,
      binding_constraint: achieved ? null : bindingConstraint,
      remaining,
      eta_at_actual_cadence: etaActual,
      eta_at_plan_cadence: etaPlan,
      eta_at_scenario_cadence: etaScenario,
    };
  });

  const cadenceBlock: PromotionStatusResult["cadence"] = {
    actual_4w: actualCadence,
    plan_target: planTarget,
  };
  if (scenarioCadence !== undefined) {
    cadenceBlock.scenario = scenarioCadence;
  }

  return {
    current_rank_code: currentRankCode,
    current_rank_display: rankDisplayFor(currentRankCode),
    current_rank_address: rankAddressFor(currentRankCode),
    cadence: cadenceBlock,
    total_workouts: totalWorkouts,
    weeks_since_signup: weeksSinceSignup,
    streak_days: streakDays,
    deployments_complete: deploymentsComplete,
    ladder,
  };
}

export const getPromotionStatusTool: ToolDefinition<Args, PromotionStatusResult> = {
  name: "getPromotionStatus",
  family: "progress",
  kind: "read",
  tier: "free",
  description:
    "Returns the full 10-rung rank ladder with the user's current standing, remaining requirements for every rank, and ETAs at actual cadence, plan cadence, and an optional scenario cadence. Call when the user asks questions beyond the immediate next rank — e.g. 'how do I reach Lt Cdr?', 'fastest path to Sub Lt?', 'what's my pace look like?', 'how long until I'm Captain?', 'show me the full ladder'. For the immediate-next-rank question only, prefer the snapshot data directly. Use this tool when the question spans multiple ranks or asks for a comparison between current and plan cadence.",
  schema,
  maxLatencyMs: 4000,
  handler,
};
