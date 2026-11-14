// supabase/functions/_shared/diet_strategies.ts
//
// Diet plan Unit 3b-2 (2026-11-14, docs/plans/diet-strategy-3b.md §5): the
// server's read of the diet STRATEGY (user_profile.diet_strategy, migration
// 179). Mirror of lib/core/constants/diet_strategies.dart `dietStrategyOf`:
// a tolerant read whose fail-safe is Balanced (today's behaviour) for any
// value it cannot read.
export type DietStrategyKey = "balanced" | "low_carb" | "keto";

export function normalizeDietStrategy(raw: unknown): DietStrategyKey {
  if (typeof raw !== "string") return "balanced";
  const key = raw.trim().toLowerCase().replace(/[\s-]+/g, "_");
  return key === "low_carb" || key === "keto" ? key : "balanced";
}
