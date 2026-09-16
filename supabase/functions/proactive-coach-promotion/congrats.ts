export interface CongratsContext {
  full_name: string | null;
  total_workouts_done: number;
  current_streak_weeks: number;
  primary_goal: string | null;
}

const RANK_LABELS: Record<string, string> = {
  SD2: "Seaman 2nd Class",
  SD1: "Seaman 1st Class",
  LS: "Leading Seaman",
  PO: "Petty Officer",
  CPO: "Chief Petty Officer",
  MCPO: "Master Chief Petty Officer",
  SubLt: "Sub Lieutenant",
  Lt: "Lieutenant",
  LtCdr: "Lieutenant Commander",
  Cdr: "Commander",
  Capt: "Captain",
};

function goalToCopy(primaryGoal: string | null): string {
  switch (primaryGoal) {
    case "lose_fat": return "fat loss";
    case "build_muscle": return "muscle gain";
    case "gain_strength": return "strength";
    case "general_fitness":
    default: return "general fitness";
  }
}

/** Mirrors index.ts's pre-existing name-sanitisation call — split on
 * whitespace, fall back to "soldier". Kept local since there is no longer
 * a prompt to sanitise for. */
function firstNameOf(fullName: string | null): string {
  const raw = fullName?.split(/\s+/)[0];
  return raw && raw.length > 0 ? raw.slice(0, 32) : "soldier";
}

function variant(
  idx: number,
  name: string,
  rank: string,
  workouts: number,
  weeks: number,
  goal: string,
): string {
  switch (idx) {
    case 0:
      return `${name} — you've been promoted to ${rank}. ${workouts} sessions and a ${weeks}-week streak got you here. Every rung on this ladder is earned, not given. Keep training toward ${goal} — the next rank is already waiting.`;
    case 1:
      return `Well earned, ${name}. ${rank} now — ${workouts} workouts and ${weeks} weeks of showing up don't lie. Stay locked on ${goal} and the next promotion takes care of itself.`;
    default:
      return `${name}, your new rank: ${rank}. ${workouts} sessions logged, ${weeks}-week streak — that's the record that earned it. Keep pushing toward ${goal}. There's more ground to cover.`;
  }
}

/**
 * Deterministic 3-variant congrats copy — replaces the prior Gemini call,
 * which had no fallback at all (a Gemini hiccup silently dropped the
 * user's promotion: no chat message, no push, bare 500).
 */
export function composeCongrats(
  ctx: CongratsContext,
  rankCode: string,
  variantIndex?: number,
): string {
  const rankLabel = RANK_LABELS[rankCode] ?? rankCode;
  const name = firstNameOf(ctx.full_name);
  const goal = goalToCopy(ctx.primary_goal);
  // Deterministic default when the caller doesn't pin one: stable across
  // repeat calls for the same rank-up (keyed on rank code + workout count,
  // not a clock or RNG, so a retry never surfaces a different message).
  const idx = variantIndex ?? (rankCode.length + ctx.total_workouts_done) % 3;
  return variant(idx, name, rankLabel, ctx.total_workouts_done, ctx.current_streak_weeks, goal);
}
