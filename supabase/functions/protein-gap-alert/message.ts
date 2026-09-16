/**
 * Diet values from user_profile.diet_preference (Indian app enum):
 *   - 'veg' / 'vegan'  → vegetarian suggestions (paneer, milk, almonds)
 *   - 'eggetarian'     → eggs allowed (treated as non-veg for protein density)
 *   - 'non_veg' / null → all options on the table (chicken, eggs)
 */
export function pickQuickFix(gap: number, diet: string | null): string {
  const isVeg = diet === "veg" || diet === "vegan";
  if (gap >= 40) {
    return isVeg
      ? "Quick fix: 200g paneer + a glass of milk."
      : "Quick fix: 150g chicken breast or 4 boiled eggs.";
  }
  if (gap >= 20) {
    return isVeg
      ? "Quick fix: 100g paneer or a scoop of whey."
      : "Quick fix: 100g chicken or 3 boiled eggs.";
  }
  return isVeg
    ? "Quick fix: a glass of milk + 30g almonds."
    : "Quick fix: 2 boiled eggs.";
}

export function buildProteinGapMessage(firstName: string | null, gap: number, diet: string | null): string {
  const quickFix = pickQuickFix(gap, diet);
  const greeting = firstName ? `${firstName} — ` : "";
  return `${greeting}${gap}g short on protein today. ${quickFix} Want a dinner suggestion?`;
}
