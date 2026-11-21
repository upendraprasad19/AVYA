import { type FoodTypeKey, normalizeFoodType } from "../_shared/food_types.ts";

/**
 * The quick fix by food type (diet plan Unit 2b, 2026-11-14, plan
 * diet-food-type-server §2.3). `diet` is user_profile.diet_preference in ANY
 * spelling (onboarding's old 'veg', Edit Profile's 'vegetarian' / 'keto',
 * the canonical five keys); it is read through the ONE normaliser
 * (_shared/food_types.ts): null / '' / keto -> non_veg, an unknown value ->
 * veg. Bands: >= 40 g, >= 20 g, else. Each new cell covers its band's lower
 * bound; the veg and non-veg cells are unchanged copy.
 */
const QUICK_FIX: Record<FoodTypeKey, [string, string, string]> = {
  veg: [
    "200g paneer + a glass of milk.",
    "100g paneer or a scoop of whey.",
    "a glass of milk + 30g almonds.",
  ],
  eggetarian: [
    "4 boiled eggs + 100g paneer.",
    "3 boiled eggs + a glass of milk.",
    "2 boiled eggs.",
  ],
  pescatarian: [
    "200g fish (rohu, tuna) or 3 boiled eggs + a glass of milk.",
    "100g fish + a glass of milk.",
    "2 boiled eggs.",
  ],
  vegan: [
    "200g firm tofu + a cup of soy milk, or 50g dry soya chunks.",
    "50g dry soya chunks or a cup of roasted chana.",
    "30g roasted peanuts + a cup of soy milk.",
  ],
  non_veg: [
    "150g chicken breast or 4 boiled eggs.",
    "100g chicken or 3 boiled eggs.",
    "2 boiled eggs.",
  ],
};

export function pickQuickFix(gap: number, diet: string | null): string {
  const row = QUICK_FIX[normalizeFoodType(diet)];
  const cell = gap >= 40 ? row[0] : gap >= 20 ? row[1] : row[2];
  return `Quick fix: ${cell}`;
}

export function buildProteinGapMessage(firstName: string | null, gap: number, diet: string | null): string {
  const quickFix = pickQuickFix(gap, diet);
  const greeting = firstName ? `${firstName} — ` : "";
  return `${greeting}${gap}g short on protein today. ${quickFix} Want a dinner suggestion?`;
}
