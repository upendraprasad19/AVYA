import { z } from "npm:zod@3.25.76";
import type { ToolContext, ToolDefinition } from "../types.ts";

const schema = z.object({
  remainingKcal: z.number().int().min(50).max(3000).describe(
    "Calorie budget for this meal (50-3000 kcal). Get this from the user's snapshot.today_nutrition.remaining_calories or similar.",
  ),
  remainingProteinG: z.number().int().min(0).max(150).optional().describe(
    "Optional protein target for this meal in grams. The tool prioritizes options that hit this minimum.",
  ),
  isVeg: z.boolean().optional().describe(
    "Set to true to restrict to vegetarian options. Omit if no preference. (Approximated by excluding common non-veg keywords from the food name — the food_database has no explicit is_veg flag.)",
  ),
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

async function handler(ctx: ToolContext, args: Args): Promise<SuggestMealResponse> {
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
  let query = sb.from("food_database").select(
    "id, name, category, calories_std, protein_std, carbs_std, fat_std, standard_serving_desc, standard_serving_g, is_indian",
  );

  // Cuisine: only 'indian' maps to a column we have. Other values are pass-through.
  if (args.cuisine === "indian") {
    query = query.eq("is_indian", true);
  }

  // Cap candidates to avoid pulling the entire 5K-row table. Calorie filter happens
  // server-side too — drop anything whose standard serving already blows the budget
  // (we still allow a 10% buffer below in the per-row check, but no point fetching
  // a 1200-kcal item when budget is 400).
  const buffer = 1.1;
  query = query.lte("calories_std", args.remainingKcal * buffer);

  const { data, error } = await query.limit(500);
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

function buildSummary(args: Args, minProtein: number): string {
  const parts: string[] = [`${args.remainingKcal} kcal budget`];
  if (minProtein > 0) parts.push(`${minProtein}g protein min`);
  if (args.isVeg === true) parts.push("veg");
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
  schema,
  maxLatencyMs: 4000,
  handler,
};
