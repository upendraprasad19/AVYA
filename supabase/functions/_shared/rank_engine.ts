// Mirror of `lib/core/services/rank_ladder_data.dart`. Update both
// files in lockstep when migration 039 ladder rows change.

export interface RankEntry {
  code: string;
  ordinal: number;
  minWeeks: number;
  isTerminal: boolean;
}

export interface RankGate {
  streakAtLeast?: number;
  totalWorkoutsAtLeast?: number;
  deploymentsCompleteAtLeast?: number;
  minWeeksSinceSignup?: number;
  maxGapDays?: number;
}

export const LADDER: RankEntry[] = [
  { code: "SD2",   ordinal: 0, minWeeks: 0,   isTerminal: false },
  { code: "SD1",   ordinal: 1, minWeeks: 1,   isTerminal: false },
  { code: "LS",    ordinal: 2, minWeeks: 4,   isTerminal: false },
  { code: "PO",    ordinal: 3, minWeeks: 12,  isTerminal: false },
  { code: "CPO",   ordinal: 4, minWeeks: 26,  isTerminal: false },
  { code: "MCPO",  ordinal: 5, minWeeks: 52,  isTerminal: false },
  { code: "SubLt", ordinal: 6, minWeeks: 104, isTerminal: false },
  { code: "LtCdr", ordinal: 7, minWeeks: 156, isTerminal: false },
  { code: "Cdr",   ordinal: 8, minWeeks: 208, isTerminal: false },
  { code: "Capt",  ordinal: 9, minWeeks: 260, isTerminal: true  },
];

export const GATES: Record<string, RankGate> = {
  SD2: {},
  SD1: { streakAtLeast: 7, minWeeksSinceSignup: 1 },
  LS:  { streakAtLeast: 16, minWeeksSinceSignup: 4 },
  PO:  { streakAtLeast: 60, minWeeksSinceSignup: 12, deploymentsCompleteAtLeast: 1 },
  CPO: { streakAtLeast: 100, minWeeksSinceSignup: 26, deploymentsCompleteAtLeast: 2 },
  MCPO: { minWeeksSinceSignup: 52, maxGapDays: 14 },
  SubLt: { totalWorkoutsAtLeast: 100, minWeeksSinceSignup: 104 },
  LtCdr: { totalWorkoutsAtLeast: 200, minWeeksSinceSignup: 156 },
  Cdr:   { totalWorkoutsAtLeast: 300, minWeeksSinceSignup: 208 },
  Capt:  { totalWorkoutsAtLeast: 500, minWeeksSinceSignup: 260, deploymentsCompleteAtLeast: 3 },
};

export interface EvalState {
  streakDays: number;
  totalWorkouts: number;
  weeksSinceSignup: number;
  deploymentsComplete: number;
  longestGapDays: number;
}

export function qualifies(code: string, s: EvalState): boolean {
  const entry = LADDER.find((r) => r.code === code);
  if (!entry) return false;
  if (s.weeksSinceSignup < entry.minWeeks) return false;
  const gate = GATES[code];
  if (gate.streakAtLeast !== undefined && s.streakDays < gate.streakAtLeast) return false;
  if (gate.totalWorkoutsAtLeast !== undefined && s.totalWorkouts < gate.totalWorkoutsAtLeast) return false;
  if (gate.minWeeksSinceSignup !== undefined && s.weeksSinceSignup < gate.minWeeksSinceSignup) return false;
  if (gate.deploymentsCompleteAtLeast !== undefined && s.deploymentsComplete < gate.deploymentsCompleteAtLeast) return false;
  if (gate.maxGapDays !== undefined && s.longestGapDays > gate.maxGapDays) return false;
  return true;
}

export function highestQualified(s: EvalState): RankEntry {
  let winner = LADDER[0];
  for (const r of LADDER) {
    if (qualifies(r.code, s)) winner = r;
  }
  return winner;
}

export function ranksUpTo(code: string): RankEntry[] {
  const target = LADDER.find((r) => r.code === code);
  if (!target) return [LADDER[0]];
  return LADDER.filter((r) => r.ordinal <= target.ordinal);
}
