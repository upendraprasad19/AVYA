// supabase/functions/_shared/food_types.ts
//
// Diet plan Unit 2b (2026-11-14, plan diet-food-type-server §2.1): the server
// mirror of lib/core/constants/food_types.dart. ONE food-type vocabulary for
// the profile value `diet_preference`: veg, non_veg, eggetarian, pescatarian,
// vegan; default non_veg (founder, 2026-11-14).
//
// Both readers are pinned by the shared fixture
// _shared/testdata/food_type_vocabulary.json, which the Dart test reads too
// (`expected` = normalizeFoodType / foodTypeOf; `known` = knownFoodType).
//
// Fail-safe direction (same as Dart): never chosen (null, '', a non-string)
// reads as the default, Non-veg; a NON-EMPTY value the table does not know
// reads as Veg, so an unknown deliberate choice is never served meat.

export const FOOD_TYPE_KEYS = [
  "veg",
  "non_veg",
  "eggetarian",
  "pescatarian",
  "vegan",
] as const;

export type FoodTypeKey = typeof FOOD_TYPE_KEYS[number];

export const DEFAULT_FOOD_TYPE: FoodTypeKey = "non_veg";

const LABELS: Record<FoodTypeKey, string> = {
  veg: "Veg",
  non_veg: "Non-veg",
  eggetarian: "Eggetarian",
  pescatarian: "Pescatarian",
  vegan: "Vegan",
};

// The spellings every writer has produced (onboarding, Edit Profile, the
// coach extraction prompt, Gemini variants). Diet STRATEGIES (keto,
// low_carb) are deliberately absent: see STRATEGY_SPELLINGS.
const SPELLINGS: Record<string, FoodTypeKey> = {
  veg: "veg",
  vegetarian: "veg",
  lacto_vegetarian: "veg",
  jain: "veg", // Jain's root-vegetable rule is not modelled
  sattvic: "veg",
  non_veg: "non_veg",
  nonveg: "non_veg",
  non_vegetarian: "non_veg",
  nonvegetarian: "non_veg",
  omnivore: "non_veg",
  anything: "non_veg",
  everything: "non_veg",
  egg: "eggetarian",
  eggetarian: "eggetarian",
  eggitarian: "eggetarian",
  ovo_vegetarian: "eggetarian",
  lacto_ovo_vegetarian: "eggetarian",
  vegetarian_eggs: "eggetarian",
  pescatarian: "pescatarian",
  pescetarian: "pescatarian",
  vegan: "vegan",
  plant_based: "vegan",
};

// Stored as a food type before Unit 2 (Edit Profile's Keto chip, the coach
// extraction prompt). A keto eater eats everything: Non-veg on the tolerant
// read, null on the strict one.
const STRATEGY_SPELLINGS = new Set(["keto", "low_carb"]);

/** Lower-case, trimmed, `-` and runs of whitespace turned into `_`. */
function canon(raw: string): string {
  return raw.trim().toLowerCase().replace(/[\s-]+/g, "_");
}

/** Tolerant read of any stored or legacy value (Dart `foodTypeOf`). */
export function normalizeFoodType(raw: unknown): FoodTypeKey {
  // Nothing stored = the default. Any other non-string (a number, a list,
  // an object) is a corrupt value and reads as Veg, the strictest common
  // type, so a bad write never puts meat on a plate (Unit 2a B-pass F1).
  if (raw === null || raw === undefined) return DEFAULT_FOOD_TYPE;
  if (typeof raw !== "string") return "veg";
  const key = canon(raw);
  if (key === "") return DEFAULT_FOOD_TYPE;
  if (STRATEGY_SPELLINGS.has(key)) return DEFAULT_FOOD_TYPE;
  return SPELLINGS[key] ?? "veg";
}

/**
 * STRICT read: the spelling table only. Null for a non-string, '', a diet
 * strategy and any unknown value. For places where a guess must never become
 * a stored value.
 */
export function knownFoodType(raw: unknown): FoodTypeKey | null {
  if (typeof raw !== "string") return null;
  return SPELLINGS[canon(raw)] ?? null;
}

/** Chip label of a canonical key ("Non-veg"). */
export function foodTypeLabel(key: FoodTypeKey): string {
  return LABELS[key];
}

/**
 * The weekly-report prompt's diet label: a closed label set, never the raw
 * stored string (plan §2.4). Null reads as the founder default, Non-veg.
 */
export function dietPreferenceLine(raw: unknown): string {
  return foodTypeLabel(normalizeFoodType(raw));
}
