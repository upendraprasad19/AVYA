import { z } from "npm:zod@3.25.76";
import type { ToolContext, ToolDefinition } from "../types.ts";
import { foodTypeLabel, type FoodTypeKey, normalizeFoodType } from "../../food_types.ts";
import { type DietStrategyKey, normalizeDietStrategy } from "../../diet_strategies.ts";

const schemaFor = (isVegDescription: string) => z.object({
  remainingKcal: z.number().int().min(50).max(3000).describe(
    "Calorie budget for this meal (50-3000 kcal). Get this from the user's snapshot.today_nutrition.remaining_calories or similar.",
  ),
  remainingProteinG: z.number().int().min(0).max(150).optional().describe(
    "Optional protein target for this meal in grams. The tool prioritizes options that hit this minimum.",
  ),
  isVeg: z.boolean().optional().describe(isVegDescription),
  cuisine: z.enum([
    "indian",
    "asian",
    "mediterranean",
    "western",
    "any",
  ]).optional().describe(
    "Preferred cuisine. Only 'indian' is enforced (via the is_indian boolean column); other values are passed through but not filtered. 'any' or omit for no filter.",
  ),
  mealType: z.enum(["breakfast", "lunch", "dinner", "snack"]).optional().describe(
    "Meal context. Surfaced in the response notes but does not currently filter; the model can use it when narrating picks.",
  ),
  excludeIngredients: z.array(z.string()).max(10).optional().describe(
    "Ingredients to avoid (e.g. ['peanut', 'shellfish'] for allergies). Names are matched as case-insensitive substrings against the food name.",
  ),
});

// B-pass finding 4: the model reads this description, so the kill switch
// selects the pre-2b text verbatim (the legacy handler ignores the stored type).
const IS_VEG_DESCRIPTION =
  "Set to true to restrict this request to vegetarian options. Omit otherwise: the tool already applies the user's stored food type (veg, non_veg, eggetarian, pescatarian, vegan) from their profile.";
export const LEGACY_IS_VEG_DESCRIPTION =
  "Set to true to restrict to vegetarian options. Omit if no preference. (Approximated by excluding common non-veg keywords from the food name — the food_database has no explicit is_veg flag.)";
const schema = schemaFor(IS_VEG_DESCRIPTION);
const legacySchema = schemaFor(LEGACY_IS_VEG_DESCRIPTION);
type Args = z.infer<typeof schema>;

interface SuggestionItem {
  id: string;
  name: string;
  category: string | null;
  serving_g: number;
  serving_desc: string | null;
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  is_indian: boolean | null;
  /** Protein density: g protein per 100 kcal. Useful ranking signal. */
  protein_per_100kcal: number;
}

interface SuggestMealResponse {
  query_summary: string;
  remaining_kcal: number;
  remaining_protein_g: number | null;
  total_candidates_searched: number;
  top_picks: SuggestionItem[];
  notes: string[];
}

// SWITCH-ON PATH ONLY (DISABLE_SUGGESTMEAL_STORED_FOOD_TYPE=true, diet plan
// Unit 2b): today's name heuristic. The comment below predates migration
// 041; the table DOES have is_veg / is_vegan, which the default path uses.
// Heuristic non-veg keywords. The food_database has no is_veg column, so when the
// model asks for vegetarian options we exclude any name containing these tokens.
// Substring match is case-insensitive. Intentionally conservative — false positives
// on a vegetarian dish ("chicken-style tofu") are better than serving meat to a vegetarian.
const NON_VEG_KEYWORDS = [
  "chicken",
  "mutton",
  "lamb",
  "beef",
  "pork",
  "bacon",
  "ham",
  "sausage",
  "fish",
  "tuna",
  "salmon",
  "prawn",
  "shrimp",
  "crab",
  "lobster",
  "egg",
  "anchovy",
  "sardine",
  "mackerel",
  "turkey",
  "duck",
  "venison",
  "kebab",
  "keema",
  "biryani", // most variants are non-veg; veg biryani users can ask without isVeg
];

// ── Diet plan Unit 2b (2026-11-14, plan diet-food-type-server §2.6) ──────
// Default path: the caller's STORED food type (user_profile.diet_preference,
// read through the one normaliser) filters the query with the table's own
// is_veg / is_vegan columns; the model's isVeg only narrows further.
// Kill switch: DISABLE_SUGGESTMEAL_STORED_FOOD_TYPE exactly "true" = the
// pre-2b handler verbatim (legacyHandler). Read per call.
export function suggestMealStoredFoodTypeOff(): boolean {
  return Deno.env.get("DISABLE_SUGGESTMEAL_STORED_FOOD_TYPE") === "true";
}

// Whole-word name rules for the is_veg = false rows an eggetarian or a
// pescatarian may eat. Meat is matched WITHOUT word boundaries (chain names
// like "McChicken"), after stripping the egg of another bird and "crab
// meat", so Quail Egg, Duck Egg and Crab Meat stay allowed.
export const EGG_RE = /\begg(s)?\b|\banda\b|\bomelet(te)?\b/i;
export const FISH_RE =
  /\b(fish|macher|prawns?|shrimps?|crabs?|lobsters?|pomfret|surmai|rohu|bangda|tuna|salmon|sardines?|mackerel|hilsa|basa|tilapia|squid|seafood|cod|scallops?|mussels?|oysters?|anchov(y|ies)|bass|halibut|trout|swordfish|snapper|catfish|mahi|sushi|sashimi)\b/i;
export const MEAT_RE =
  /(chicken|murgh|mutton|gosht|lamb|goat|keema|kheema|kabab|kebab|seekh|tangdi|nihari|haleem|rogan|beef|pork|bacon|\bham\b|sausage|salami|pepperoni|turkey|duck|quail|veal|goose|ribs|lard|meat|hot ?dogs?|frankfurters?|mcmuffins?|jerky)/i;
const CAPSULE_RE = /\bcapsule\b/i;
const MEAT_EXEMPT_RE = /\b(quail|duck|goose)\s+eggs?\b|\bcrab\s+meat\b/gi;

/** Is this is_veg = false row allowed for [type]? (egg / fish rules only) */
// B-pass finding 1: an egg word no longer admits a fish dish for an
// eggetarian ("Tuna Egg Salad"), and a capsule is never a meal for either.
export function animalRowAllowed(name: string, type: "eggetarian" | "pescatarian"): boolean {
  if (CAPSULE_RE.test(name)) return false;
  if (MEAT_RE.test(name.replace(MEAT_EXEMPT_RE, " "))) return false;
  if (type === "eggetarian" && FISH_RE.test(name)) return false;
  if (EGG_RE.test(name)) return true;
  return type === "pescatarian" && FISH_RE.test(name);
}

// The table tags some dairy / honey dishes is_vegan; drop them. B-pass
// finding 2: a plant word ANYWHERE used to rescue every deny word ("Curd
// Rice", "Ghee Rice", "Peanut Butter with Honey" passed). Now these words
// always drop the row, and the plant rescue applies only to milk, butter,
// cheese, curd, dahi and yogurt, and only when the plant word comes right
// before it (Almond Milk, Peanut Butter, Soy Curd, Coconut Yogurt).
export const VEGAN_ABSOLUTE_RE =
  /\b(honey|ghee|paneer|whey|malai|cream|lassi|buttermilk|chaas|chhaas|raita|kheer|rasmalai|shrikhand|kulfi|ice ?cream|mayo|mayonnaise|eggs?(?!\s*plant)|casein|gelatine?|khoa|khoya|rabri|rabdi|cold coffee|pav)\b/i;
const VEGAN_RESCUABLE_RE = /\b(milk|butter|cheese|curd|dahi|yogh?urt)\b/gi;
const VEGAN_PLANT_BEFORE_RE =
  /\b(soy|soya|almond|oat|coconut|peanut|cashew|rice|hemp|nut|cocoa|vegan|plant|pea)\s*$/i;
export function veganRowAllowed(name: string): boolean {
  if (VEGAN_ABSOLUTE_RE.test(name)) return false;
  for (const m of name.matchAll(VEGAN_RESCUABLE_RE)) {
    if (!VEGAN_PLANT_BEFORE_RE.test(name.slice(0, m.index))) return false;
  }
  return true;
}

type FoodRow = {
  id: string;
  name: string;
  category: string | null;
  calories_std: number | null;
  protein_std: number | null;
  carbs_std: number | null;
  fat_std: number | null;
  standard_serving_desc: string | null;
  standard_serving_g: number | null;
  is_indian: boolean | null;
};

// ── Diet plan Unit 3b-2 (2026-11-14, docs/plans/diet-strategy-3b.md §5) ──
// A PRO caller's stored diet strategy caps carbs per standard serving:
// keto 6 g (a vegan keto caller: low carb, no vegan keto day exists), low
// carb 25 g. Read in the same profile row as the food type; a read error
// keeps the vegan fail-safe and applies no strategy. Only with ctx.isPro
// (server-verified). The column is written only by an app with the strategy
// switched on, so until then every row is balanced (no cap). Kill switch:
// DISABLE_SUGGESTMEAL_DIET_STRATEGY exactly "true" (read per call); with it
// on, the profile read selects diet_preference alone, exactly as before.
// Under a cap the protein powders (category "supplements") are left out:
// they are the densest rows under 6 g and would fill the top five, while
// the manual builds keto meals from food (3b-2 B-pass seat B finding 2).
// The food-type switch DISABLE_SUGGESTMEAL_STORED_FOOD_TYPE routes to the
// verbatim pre-2b legacyHandler, which applies no cap either (accepted,
// B-pass finding 1: that switch restores the whole pre-2b tool).
export const KETO_CARBS_STD_CAP = 6;
export const LOW_CARB_CARBS_STD_CAP = 25;

export function suggestMealDietStrategyOff(): boolean {
  return Deno.env.get("DISABLE_SUGGESTMEAL_DIET_STRATEGY") === "true";
}

/** The carbs_std cap for a strategy and food type, or null (no cap). */
export function carbsStdCapFor(strategy: DietStrategyKey, foodType: FoodTypeKey): number | null {
  if (strategy === "keto") return foodType === "vegan" ? LOW_CARB_CARBS_STD_CAP : KETO_CARBS_STD_CAP;
  if (strategy === "low_carb") return LOW_CARB_CARBS_STD_CAP;
  return null;
}

/**
 * The caller's stored food type and strategy; null when the read failed.
 * [withStrategy] false reads diet_preference alone (the strategy is then
 * balanced), so a strategy-off call never touches the newer column.
 */
async function readStoredProfile(
  ctx: ToolContext,
  withStrategy: boolean,
): Promise<{ foodType: FoodTypeKey; strategy: DietStrategyKey } | null> {
  try {
    const { data, error } = await ctx.sb
      .from("user_profile")
      .select(withStrategy ? "diet_preference, diet_strategy" : "diet_preference")
      .eq("user_id", ctx.userId)
      .limit(1);
    if (error) return null;
    // An absent row is a user who never chose: the defaults (non_veg,
    // balanced).
    const row = data?.[0] as { diet_preference?: unknown; diet_strategy?: unknown } | undefined;
    return {
      foodType: normalizeFoodType(row?.diet_preference),
      strategy: normalizeDietStrategy(row?.diet_strategy),
    };
  } catch {
    return null;
  }
}

async function handler(ctx: ToolContext, args: Args): Promise<SuggestMealResponse> {
  if (suggestMealStoredFoodTypeOff()) return legacyHandler(ctx, args);

  const { sb } = ctx;
  const minProtein = args.remainingProteinG ?? 0;
  const cols =
    "id, name, category, calories_std, protein_std, carbs_std, fat_std, standard_serving_desc, standard_serving_g, is_indian";
  const buffer = 1.1;
  // Each query is bounded by a LITERAL limit in the statement that names
  // the table (the unbounded-read gate, L1b B8); filters chain after it.
  // 500 for the main query, 250 for the is_veg = false rows (196 live).
  const notes: string[] = [];
  // Unit 3b-2: the strategy's carb cap, PRO only, never on a failed read.
  // ctx.isPro is defence in depth: suggestMeal is a tier "pro" tool, so
  // the tool loop refuses a free caller before this handler runs.
  const usesStrategy = ctx.isPro && !suggestMealDietStrategyOff();
  const profile = await readStoredProfile(ctx, usesStrategy);
  const stored = profile?.foodType ?? null;
  const strategy: DietStrategyKey = profile !== null && usesStrategy ? profile.strategy : "balanced";
  const carbCap = carbsStdCapFor(strategy, stored ?? "vegan");
  if (carbCap !== null) {
    // Pushed before any early return, so an empty answer names the cap too
    // (B-pass seat A finding 1). A vegan keto caller gets the low carb cap
    // and is told so.
    notes.push(
      `Filtered for diet strategy: ${carbCap === KETO_CARBS_STD_CAP ? "Keto" : "Low carb"} ` +
        `(at most ${carbCap} g carbs per serving; protein powders left out).`,
    );
  }

  const foodQuery = (main: boolean) => {
    // B-pass finding 6: the veg tables hold more rows than the limit (1,241
    // veg, 637 vegan in the asset), so the rows kept are the most
    // protein-rich, not an arbitrary slice.
    const q = main
      ? sb.from("food_database").select(cols).order("protein_std", { ascending: false }).limit(500)
      : sb.from("food_database").select(cols).order("protein_std", { ascending: false }).limit(250);
    // PostgREST applies every filter before the limit, so the 500 rows kept
    // are the most protein-rich rows UNDER the cap (all three query sites).
    const capped = carbCap === null ? q : q.lte("carbs_std", carbCap).neq("category", "supplements");
    return args.cuisine === "indian" ? capped.eq("is_indian", true) : capped;
  };

  // B-pass finding 3: a failed read is not a choice; vegan options suit
  // every food type, so nobody is offered food outside theirs.
  if (stored === null) {
    notes.push("Could not read the user's food type; showing vegan options, which suit every food type.");
  }
  // The model's isVeg narrows (a vegan stays vegan).
  const userType: FoodTypeKey = stored ?? "vegan";
  const type: FoodTypeKey = args.isVeg === true && userType !== "vegan" ? "veg" : userType;

  let rows: FoodRow[];
  if (type === "eggetarian" || type === "pescatarian") {
    // Query A: every veg row; query B: the is_veg = false rows, filtered by
    // name below (196 live rows, limit 250).
    const [a, b] = await Promise.all([
      foodQuery(true).eq("is_veg", true).lte("calories_std", args.remainingKcal * buffer),
      foodQuery(false).eq("is_veg", false).lte("calories_std", args.remainingKcal * buffer),
    ]);
    if (a.error) throw new Error(`food_database query failed: ${a.error.message}`);
    const animal = b.error
      ? []
      : ((b.data ?? []) as FoodRow[]).filter((r) => animalRowAllowed(r.name, type));
    if (b.error) {
      notes.push(`Egg${type === "pescatarian" ? " and fish" : ""} options could not be read; veg options only.`);
    }
    rows = [...((a.data ?? []) as FoodRow[]), ...animal];
  } else {
    let q = foodQuery(true);
    if (type === "vegan") q = q.eq("is_vegan", true);
    if (type === "veg") q = q.eq("is_veg", true);
    const { data, error } = await q.lte("calories_std", args.remainingKcal * buffer);
    if (error) throw new Error(`food_database query failed: ${error.message}`);
    rows = (data ?? []) as FoodRow[];
    if (type === "vegan") rows = rows.filter((r) => veganRowAllowed(r.name));
  }

  const summary = buildSummary(args, minProtein, type);
  if (rows.length === 0) {
    return {
      query_summary: summary,
      remaining_kcal: args.remainingKcal,
      remaining_protein_g: args.remainingProteinG ?? null,
      total_candidates_searched: 0,
      top_picks: [],
      notes: [
        ...notes,
        "No foods matched the filters. The constraints may be too tight. " +
        "Suggest a higher calorie budget or fewer filters.",
      ],
    };
  }

  const exclude = (args.excludeIngredients ?? []).map((s) => s.toLowerCase().trim()).filter((s) => s.length > 0);
  const candidates: SuggestionItem[] = [];
  for (const row of rows) {
    const calories = row.calories_std ?? 0;
    const protein = row.protein_std ?? 0;
    const carbs = row.carbs_std ?? 0;
    const fat = row.fat_std ?? 0;
    if (calories <= 0) continue;
    const nameLower = row.name.toLowerCase();
    if (exclude.some((e) => nameLower.includes(e))) continue;
    candidates.push({
      id: row.id ?? "",
      name: row.name,
      category: row.category,
      serving_g: row.standard_serving_g ?? 100,
      serving_desc: row.standard_serving_desc,
      calories: Math.round(calories),
      protein_g: Math.round(protein * 10) / 10,
      carbs_g: Math.round(carbs * 10) / 10,
      fat_g: Math.round(fat * 10) / 10,
      is_indian: row.is_indian,
      protein_per_100kcal: Math.round((protein * 100 / calories) * 10) / 10,
    });
  }

  const ideal = args.remainingKcal * 0.7;
  candidates.sort((a, b) => {
    const aHits = a.protein_g >= minProtein ? 1 : 0;
    const bHits = b.protein_g >= minProtein ? 1 : 0;
    if (aHits !== bHits) return bHits - aHits;
    if (a.protein_per_100kcal !== b.protein_per_100kcal) {
      return b.protein_per_100kcal - a.protein_per_100kcal;
    }
    return Math.abs(a.calories - ideal) - Math.abs(b.calories - ideal);
  });
  const topPicks = candidates.slice(0, 5);

  if (topPicks.length === 0) {
    notes.push(
      `Found ${rows.length} foods within the calorie budget but none survived the filters ` +
        `(allergies / excluded ingredients). Try relaxing constraints.`,
    );
  } else if (minProtein > 0 && !topPicks.some((p) => p.protein_g >= minProtein)) {
    notes.push(
      `No options reach ${minProtein}g protein in this calorie budget. Top picks ranked by density.`,
    );
  }
  if (stored !== null) {
    notes.push(`Filtered for food type: ${foodTypeLabel(type)}.`);
  }
  if (args.mealType) {
    notes.push(`Meal context: ${args.mealType}. Picks are not filtered by meal type — model should use this to narrate selection.`);
  }

  return {
    query_summary: summary,
    remaining_kcal: args.remainingKcal,
    remaining_protein_g: args.remainingProteinG ?? null,
    total_candidates_searched: candidates.length,
    top_picks: topPicks,
    notes,
  };
}

// The pre-2b handler, verbatim (switch-ON path). Deleted with the switch.
async function legacyHandler(ctx: ToolContext, args: Args): Promise<SuggestMealResponse> {
  const { sb } = ctx;
  const minProtein = args.remainingProteinG ?? 0;

  // Schema reference (verified 2026-04-20):
  //   id uuid, name text, category text,
  //   calories_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g, fiber_per_100g (numeric),
  //   standard_serving_desc text, standard_serving_g numeric,
  //   calories_std, protein_std, carbs_std, fat_std (numeric),
  //   common_additions text[], is_indian boolean, source text, created_at timestamptz
  //
  // Pre-computed *_std columns are the per-standard-serving macros — we use those
  // directly and skip per-100g math.
  const cols =
    "id, name, category, calories_std, protein_std, carbs_std, fat_std, standard_serving_desc, standard_serving_g, is_indian";

  // Cuisine: only 'indian' maps to a column we have. Other values are pass-through.
  // Cap candidates to avoid pulling the entire 5K-row table. Calorie filter happens
  // server-side too — drop anything whose standard serving already blows the budget
  // (we still allow a 10% buffer below in the per-row check, but no point fetching
  // a 1200-kcal item when budget is 400).
  // One statement, bounded by `.limit(500)` in the same chain (L1b B8: the
  // unbounded-read gate recognises a limit in the statement it flags).
  const buffer = 1.1;
  const { data, error } = await (args.cuisine === "indian"
    ? sb.from("food_database").select(cols).eq("is_indian", true)
    : sb.from("food_database").select(cols))
    .lte("calories_std", args.remainingKcal * buffer)
    .limit(500);
  if (error) {
    throw new Error(`food_database query failed: ${error.message}`);
  }

  const rows = (data ?? []) as Array<{
    id: string;
    name: string;
    category: string | null;
    calories_std: number | null;
    protein_std: number | null;
    carbs_std: number | null;
    fat_std: number | null;
    standard_serving_desc: string | null;
    standard_serving_g: number | null;
    is_indian: boolean | null;
  }>;

  if (rows.length === 0) {
    return {
      query_summary: buildSummary(args, minProtein),
      remaining_kcal: args.remainingKcal,
      remaining_protein_g: args.remainingProteinG ?? null,
      total_candidates_searched: 0,
      top_picks: [],
      notes: [
        "No foods matched the filters. The cloud food_database may be empty (it's seeded client-side from JSON) " +
        "or the constraints are too tight. Suggest a higher calorie budget or fewer filters.",
      ],
    };
  }

  // Compute per-row scoring + apply remaining filters.
  const exclude = (args.excludeIngredients ?? []).map((s) => s.toLowerCase().trim()).filter((s) => s.length > 0);
  const excludeNonVeg = args.isVeg === true;

  const candidates: SuggestionItem[] = [];
  for (const row of rows) {
    const calories = row.calories_std ?? 0;
    const protein = row.protein_std ?? 0;
    const carbs = row.carbs_std ?? 0;
    const fat = row.fat_std ?? 0;

    // Skip rows with no nutrition data.
    if (calories <= 0) continue;

    const nameLower = row.name.toLowerCase();

    // Veg filter (heuristic — see NON_VEG_KEYWORDS comment).
    if (excludeNonVeg && NON_VEG_KEYWORDS.some((k) => nameLower.includes(k))) continue;

    // Allergy / exclude filter.
    if (exclude.some((e) => nameLower.includes(e))) continue;

    candidates.push({
      id: row.id ?? "",
      name: row.name,
      category: row.category,
      serving_g: row.standard_serving_g ?? 100,
      serving_desc: row.standard_serving_desc,
      calories: Math.round(calories),
      protein_g: Math.round(protein * 10) / 10,
      carbs_g: Math.round(carbs * 10) / 10,
      fat_g: Math.round(fat * 10) / 10,
      is_indian: row.is_indian,
      protein_per_100kcal: Math.round((protein * 100 / calories) * 10) / 10,
    });
  }

  // Ranking:
  //   1. Items hitting the minimum protein target win the tiebreak (binary tier).
  //   2. Higher protein density (g protein per 100 kcal) ranks higher.
  //   3. Closer to ~70% of the calorie budget wins (avoids tiny snacks when
  //      the user has a lot of room left).
  const ideal = args.remainingKcal * 0.7;
  candidates.sort((a, b) => {
    const aHits = a.protein_g >= minProtein ? 1 : 0;
    const bHits = b.protein_g >= minProtein ? 1 : 0;
    if (aHits !== bHits) return bHits - aHits;

    if (a.protein_per_100kcal !== b.protein_per_100kcal) {
      return b.protein_per_100kcal - a.protein_per_100kcal;
    }

    return Math.abs(a.calories - ideal) - Math.abs(b.calories - ideal);
  });

  const topPicks = candidates.slice(0, 5);

  const notes: string[] = [];
  if (topPicks.length === 0) {
    notes.push(
      `Found ${rows.length} foods within the calorie budget but none survived the filters ` +
        `(veg / allergies). Try relaxing constraints.`,
    );
  } else if (minProtein > 0 && !topPicks.some((p) => p.protein_g >= minProtein)) {
    notes.push(
      `No options reach ${minProtein}g protein in this calorie budget. Top picks ranked by density.`,
    );
  }
  if (args.isVeg === true) {
    notes.push(
      "Vegetarian filter is heuristic (excludes non-veg keywords from name) — the food_database has no explicit is_veg flag.",
    );
  }
  if (args.mealType) {
    notes.push(`Meal context: ${args.mealType}. Picks are not filtered by meal type — model should use this to narrate selection.`);
  }

  return {
    query_summary: buildSummary(args, minProtein),
    remaining_kcal: args.remainingKcal,
    remaining_protein_g: args.remainingProteinG ?? null,
    total_candidates_searched: candidates.length,
    top_picks: topPicks,
    notes,
  };
}

function buildSummary(args: Args, minProtein: number, foodType?: FoodTypeKey | null): string {
  const parts: string[] = [`${args.remainingKcal} kcal budget`];
  if (minProtein > 0) parts.push(`${minProtein}g protein min`);
  // Unit 2b: the default path names the food type; the legacy path (no third
  // argument) keeps "veg" for isVeg.
  if (foodType) parts.push(foodTypeLabel(foodType).toLowerCase());
  else if (foodType === undefined && args.isVeg === true) parts.push("veg");
  if (args.cuisine && args.cuisine !== "any") parts.push(args.cuisine);
  if (args.mealType) parts.push(args.mealType);
  return parts.join(", ");
}

export const suggestMealTool: ToolDefinition<Args, SuggestMealResponse> = {
  name: "suggestMeal",
  family: "nutrition",
  kind: "read",
  tier: "pro",
  description:
    "Suggest meals from the food database that fit the user's remaining calorie/protein budget. Use when the user asks for a meal suggestion ('what should I eat for dinner?', 'I have 600 cal left, ideas?', 'high-protein lunch please'). Returns up to 5 ranked options with per-serving macros and protein density. Pure read — does NOT log anything; if the user picks one, follow up with logMealByText to log it.",
  get schema() {
    return suggestMealStoredFoodTypeOff() ? legacySchema : schema;
  },
  maxLatencyMs: 4000,
  handler,
};
