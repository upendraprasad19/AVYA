/** Minimal shape composeMessage needs — structurally compatible with the
 * richer PRRow used in index.ts's Supabase row type. */
export interface PrRecord {
  exercise_id: string;
  weight_kg: number | null;
  reps: number | null;
}

export function composeMessage(firstName: string, prs: PrRecord[]): string {
  if (prs.length === 0) return "";

  const fmt = (p: PrRecord) => {
    const weight = p.weight_kg ?? 0;
    const reps = p.reps ?? 0;
    if (weight > 0) {
      return `${p.exercise_id} ${weight}kg`;
    }
    return `${p.exercise_id} ${reps} reps`;
  };

  if (prs.length === 1) {
    return `${firstName} — new ${fmt(prs[0])} PR. Keep going 💪.`;
  }
  if (prs.length === 2) {
    return `${firstName} — new PRs: ${fmt(prs[0])}, ${fmt(prs[1])}. Strong session.`;
  }
  const tail = prs.length - 2;
  return `${firstName} — new PRs: ${fmt(prs[0])}, ${fmt(prs[1])} +${tail} more. Strong session.`;
}
