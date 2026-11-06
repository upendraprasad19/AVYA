/**
 * Diet values from user_profile.diet_preference. The REAL vocabulary the
 * client's own Edit Profile chips write (edit_profile_screen.dart
 * `_buildDietPreferenceChips`) is: 'non_veg' / 'vegetarian' / 'vegan' /
 * 'pescatarian' / 'keto'. 'veg' is ALSO live — it is onboarding's documented
 * default (lib/features/onboarding/CLAUDE.md: "diet_preference defaults to
 * 'veg' (Indian-first default)") for every user who has not yet visited Edit
 * Profile — so both 'veg' AND 'vegetarian' must be treated as vegetarian.
 * ('eggetarian' does NOT exist anywhere in the client or onboarding vocabulary
 * — corrected 2026-09-27, a2b-2 batch, after grep confirmed zero writers; the
 * prior version of this comment and this file's own test both asserted a
 * value that could never occur in production.)
 *   - 'veg' / 'vegetarian' / 'vegan' → vegetarian suggestions (paneer, milk, almonds)
 *   - 'non_veg' / 'pescatarian' / 'keto' / null → all options on the table (chicken, eggs)
 */
export function pickQuickFix(gap: number, diet: string | null): string {
  const isVeg = diet === "veg" || diet === "vegetarian" || diet === "vegan";
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
