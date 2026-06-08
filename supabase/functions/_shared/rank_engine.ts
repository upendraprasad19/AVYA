// Mirror of `lib/core/services/rank_ladder_data.dart`. Update both
// files in lockstep when migration 039/045 ladder rows change.
//
// APK Test #6 Plan G (G-8): adds Lt at ordinal 7, rebalances sailor
// gates, switches officer track to completionRateMinimum primary,
// MCPO becomes the transition rank with completion rate + maxGapDays.

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

export interface RankLadderEntry {
  code: string;
  displayName: string;
  shortName: string;
  ordinal: number;
  minWeeks: number;
  category: 'sailor' | 'officer';
  isTerminal: boolean;
}

export interface RankGate {
  streakAtLeast?: number;
  totalWorkoutsAtLeast?: number;
  deploymentsCompleteAtLeast?: number;
  minWeeksSinceSignup?: number;
  maxGapDays?: number;
  completionRateMinimum?: number;
  completionRateWindowWeeks?: number;
}

// 11-rung ladder, ordinal 0..10. Mirrors lib/core/services/rank_ladder_data.dart.
export const kRankLadder: RankLadderEntry[] = [
  { code: 'SD2',   displayName: 'Seaman 2nd Class',          shortName: 'SEAMAN 2',       ordinal: 0,  minWeeks: 0,   category: 'sailor',  isTerminal: false },
  { code: 'SD1',   displayName: 'Seaman 1st Class',          shortName: 'SEAMAN 1',       ordinal: 1,  minWeeks: 1,   category: 'sailor',  isTerminal: false },
  { code: 'LS',    displayName: 'Leading Seaman',            shortName: 'LEADING SEAMAN', ordinal: 2,  minWeeks: 4,   category: 'sailor',  isTerminal: false },
  { code: 'PO',    displayName: 'Petty Officer',             shortName: 'PETTY OFFICER',  ordinal: 3,  minWeeks: 12,  category: 'sailor',  isTerminal: false },
  { code: 'CPO',   displayName: 'Chief Petty Officer',       shortName: 'CHIEF PO',       ordinal: 4,  minWeeks: 26,  category: 'sailor',  isTerminal: false },
  { code: 'MCPO',  displayName: 'Master Chief Petty Officer',shortName: 'MASTER CHIEF',   ordinal: 5,  minWeeks: 52,  category: 'sailor',  isTerminal: false },
  { code: 'SubLt', displayName: 'Sub Lieutenant',            shortName: 'SUB LT',         ordinal: 6,  minWeeks: 104, category: 'officer', isTerminal: false },
  { code: 'Lt',    displayName: 'Lieutenant',                shortName: 'LIEUTENANT',     ordinal: 7,  minWeeks: 130, category: 'officer', isTerminal: false },
  { code: 'LtCdr', displayName: 'Lieutenant Commander',      shortName: 'LT CDR',         ordinal: 8,  minWeeks: 156, category: 'officer', isTerminal: false },
  { code: 'Cdr',   displayName: 'Commander',                 shortName: 'CDR',            ordinal: 9,  minWeeks: 208, category: 'officer', isTerminal: false },
  { code: 'Capt',  displayName: 'Captain',                   shortName: 'CAPTAIN',        ordinal: 10, minWeeks: 260, category: 'officer', isTerminal: true  },
];

export const kRankGates: Record<string, RankGate> = {
  'SD2':   {},
  'SD1':   { streakAtLeast: 7,  minWeeksSinceSignup: 1 },
  'LS':    { streakAtLeast: 14, minWeeksSinceSignup: 4 },
  'PO':    { streakAtLeast: 30, minWeeksSinceSignup: 12, deploymentsCompleteAtLeast: 2 },
  'CPO':   { streakAtLeast: 50, minWeeksSinceSignup: 26, deploymentsCompleteAtLeast: 3 },
  'MCPO':  { minWeeksSinceSignup: 52,  completionRateMinimum: 0.80, completionRateWindowWeeks: 12,  maxGapDays: 14 },
  'SubLt': { minWeeksSinceSignup: 104, completionRateMinimum: 0.80, completionRateWindowWeeks: 26  },
  'Lt':    { minWeeksSinceSignup: 130, completionRateMinimum: 0.80, completionRateWindowWeeks: 26  },
  'LtCdr': { minWeeksSinceSignup: 156, completionRateMinimum: 0.80, completionRateWindowWeeks: 52  },
  'Cdr':   { minWeeksSinceSignup: 208, completionRateMinimum: 0.80, completionRateWindowWeeks: 52  },
  'Capt':  { minWeeksSinceSignup: 260, completionRateMinimum: 0.85, completionRateWindowWeeks: 104 },
};

// Legacy aliases retained so existing callers (highestQualified / ranksUpTo /
// callers that imported `LADDER` / `GATES`) keep compiling without churn.
export const LADDER = kRankLadder;
export const GATES = kRankGates;

export interface EvalState {
  streak: number;
  totalWorkouts: number;
  weeksSinceSignup: number;
  deploymentsComplete: number;
  lastWorkoutDaysAgo: number | null;
  completionRateProvider: (windowWeeks: number) => Promise<number> | number;
}

export async function qualifies(code: string, s: EvalState): Promise<boolean> {
  const gate = kRankGates[code];
  if (!gate) return false;
  const entry = kRankLadder.find((r) => r.code === code);
  if (!entry) return false;
  // Ladder-level minWeeks gate (always required).
  if (s.weeksSinceSignup < entry.minWeeks) return false;
  if (gate.streakAtLeast !== undefined && s.streak < gate.streakAtLeast) return false;
  if (gate.totalWorkoutsAtLeast !== undefined && s.totalWorkouts < gate.totalWorkoutsAtLeast) return false;
  if (gate.deploymentsCompleteAtLeast !== undefined && s.deploymentsComplete < gate.deploymentsCompleteAtLeast) return false;
  if (gate.minWeeksSinceSignup !== undefined && s.weeksSinceSignup < gate.minWeeksSinceSignup) return false;
  if (gate.maxGapDays !== undefined && s.lastWorkoutDaysAgo !== null && s.lastWorkoutDaysAgo > gate.maxGapDays) return false;
  if (gate.completionRateMinimum !== undefined) {
    const window = gate.completionRateWindowWeeks ?? 26;
    const rate = await Promise.resolve(s.completionRateProvider(window));
    if (rate < gate.completionRateMinimum) return false;
  }
  return true;
}

// Highest rung EARNED, evaluated SEQUENTIALLY — no skipping. Mirror of the
// client `RankService._qualifiedRankCode` (2026-05-31, diagnose b9f4d2, ADR
// rank-sequential). Walk from the bottom; advance only while each successive
// rung's gate passes; STOP at the first failure. The deployment-gated PO/CPO
// rungs cannot be leap-frogged by an officer-track completion-rate qualifier.
// (Pre-fix this picked the highest INDEPENDENTLY-qualifying rung.)
export async function highestQualified(s: EvalState): Promise<RankLadderEntry> {
  let winner = kRankLadder[0]; // SD2 — ordinal 0, empty gate
  for (let i = 1; i < kRankLadder.length; i++) {
    const r = kRankLadder[i];
    if (await qualifies(r.code, s)) {
      winner = r;
    } else {
      break; // sequential: a failed gate blocks every rung above it
    }
  }
  return winner;
}

export function ranksUpTo(code: string): RankLadderEntry[] {
  const target = kRankLadder.find((r) => r.code === code);
  if (!target) return [kRankLadder[0]];
  return kRankLadder.filter((r) => r.ordinal <= target.ordinal);
}

/// SQL-backed completion-rate computation used by the cron caller —
/// scans `scheduled_workouts` rows for the user / window. Rest days
/// and pre-onboarding rows are excluded from both numerator and
/// denominator so the rate matches the client's
/// `WorkoutRepository.completionRateOverWindow` semantics.
export async function completionRateOverWindow(
  supabase: SupabaseClient,
  userId: string,
  windowWeeks: number,
): Promise<number> {
  if (windowWeeks <= 0) return 0.0;
  const sinceIso = new Date(Date.now() - windowWeeks * 7 * 24 * 3600 * 1000)
    .toISOString();
  const { data, error } = await supabase
    .from('scheduled_workouts')
    .select('status, scheduled_date')
    .eq('user_id', userId)
    .gte('scheduled_date', sinceIso.split('T')[0]);
  if (error) {
    console.error('[rank_engine] completionRate query failed', error);
    return 0.0;
  }
  let scheduled = 0;
  let completed = 0;
  for (const row of data ?? []) {
    if (row.status === 'rest') continue;
    // Cloud `scheduled_workouts` has NO `reason` column — it only ever existed
    // in the client's local Hive model. Pre-onboarding placeholder days are
    // written with status='rest' (workout_schedule_read_service.dart:303-309),
    // so the status check above ALREADY excludes them. Selecting `reason` here
    // 42703'd → completionRate silently returned 0.0 for everyone since
    // 2026-05-01. closes-diagnose: d7c3f1.
    scheduled++;
    if (row.status === 'completed') completed++;
  }
  return scheduled === 0 ? 0.0 : completed / scheduled;
}
