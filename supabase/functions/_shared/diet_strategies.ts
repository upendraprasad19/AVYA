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

/**
 * The weekly report's diet-strategy line (diet plan Unit 3b-3 B-pass seat A
 * finding 2). The report reads the stored Balanced carbs_grams / fat_grams
 * and shows the week's average carbs with no target, so without this line
 * the model cannot tell that 30 g of carbs is on plan for a Keto user and may
 * tell them to eat more. Empty for Balanced and for a caller without PRO (the
 * app shows Balanced to them too), so their report is unchanged.
 */
export function weeklyReportDietStrategyLine(raw: unknown, isPro: boolean): string {
  if (!isPro) return "";
  const key = normalizeDietStrategy(raw);
  if (key === "keto") {
    return "- Diet strategy: Keto (the user's choice). Carbs are kept very low on purpose and fat is higher; calorie and protein targets do not change. Do not grade carbs or fat against a target and never tell the user to eat more carbs.";
  }
  if (key === "low_carb") {
    return "- Diet strategy: Low carb (the user's choice). Carbs are kept low on purpose (one grain portion at lunch, none at dinner) and fat is higher; calorie and protein targets do not change. Do not grade carbs or fat against a target and never tell the user to eat more carbs.";
  }
  return "";
}
