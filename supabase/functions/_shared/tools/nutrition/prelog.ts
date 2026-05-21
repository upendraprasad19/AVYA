import { z } from "https://deno.land/x/zod@v3.25.76/mod.ts";
import type { ToolDefinition } from "../types.ts";
import { parseFoodText } from "../../food_parser.ts";

/**
 * prelog — Phase C.4
 *
 * Multi-meal multi-day batch logger. Wraps the same `parseFoodText` helper as
 * C.1 `logMealByText`, but in a Promise.all over the args.meals[] list so
 * tool latency = max(parse times) instead of sum.
 *
 * Confirmation class is derived per intent shape (NOT static):
 *   - 1 distinct date  → reviewable (inline card; lighter ceremony)
 *   - 2+ distinct dates → destructive (full diff sheet — multi-day writes
 *     deserve a real review surface)
 *
 * Per-meal parse failures are surfaced in payload.failed_meals[] so the
 * client can render them alongside the successful parses without aborting
 * the batch. The dispatcher iterates payload.parsed_meals[] only.
 */

const mealSchema = z.object({
  description: z.string().min(3).max(300).describe(
    "Free-text meal description (parsed via the same engine as logMealByText).",
  ),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).describe(
    "Date for this meal (YYYY-MM-DD). Multiple meals can share a date.",
  ),
  mealType: z.enum(["breakfast", "lunch", "dinner", "snacks"]).optional()
    .describe(
      "Optional meal type. Defaults to 'snacks' if omitted.",
    ),
});

const schema = z.object({
  meals: z.array(mealSchema).min(1).max(21).describe(
    "List of meals to pre-log (1-21). Each meal carries its own date and optional type. Useful for meal-prep planning, batch-logging missed days, or planning a deliberate eating day.",
  ),
});

type Args = z.infer<typeof schema>;

interface ParsedMealEntry {
  original_description: string;
  date: string;
  meal_type: string | null;
  food_name: string;
  total_calories: number;
  total_protein_g: number;
  total_carbs_g: number;
  total_fat_g: number;
  serving_description: string;
  confidence: "high" | "medium" | "low";
  items: Array<{
    name: string;
    quantity: string;
    calories: number;
    protein_g: number;
    carbs_g: number;
    fat_g: number;
  }>;
}

interface FailedMeal {
  original_description: string;
  date: string;
  error: string;
}

export const prelogTool: ToolDefinition<Args> = {
  name: "prelog",
  family: "nutrition",
  kind: "write",
  // Worst-case default (multi-day). intentBuilder may downgrade to
  // 'reviewable' when the batch only spans a single day.
  confirmationClass: "destructive",
  tier: "pro",
  description:
    "Pre-log multiple meals across one or more days in a single batch. Use when the user is meal-prep planning ('log my standard meals for the next 3 days'), backfilling missed days ('I forgot to log yesterday — I had X for breakfast, Y for lunch'), or planning a deliberate eating day. Each meal is parsed via the same Gemini engine as logMealByText. Confirmation is REVIEWABLE for single-day batches and DESTRUCTIVE for multi-day (full diff sheet). PRO only.",
  schema,
  intentBuilder: async (args) => {
    // Parse every meal in parallel — tool latency = max(parse times),
    // not sum. Each parse swallows its own error so a single bad meal
    // doesn't abort the batch.
    const results = await Promise.all(
      args.meals.map(async (
        meal,
      ): Promise<{ ok: ParsedMealEntry } | { fail: FailedMeal }> => {
        try {
          const parsed = await parseFoodText(meal.description);
          return {
            ok: {
              original_description: meal.description,
              date: meal.date,
              meal_type: meal.mealType ?? null,
              food_name: parsed.food_name,
              total_calories: Math.round(parsed.total_calories),
              total_protein_g: Math.round(parsed.total_protein_g),
              total_carbs_g: Math.round(parsed.total_carbs_g),
              total_fat_g: Math.round(parsed.total_fat_g),
              serving_description: parsed.serving_description,
              confidence: parsed.confidence,
              items: parsed.items ?? [],
            },
          };
        } catch (e) {
          return {
            fail: {
              original_description: meal.description,
              date: meal.date,
              error: String(e),
            },
          };
        }
      }),
    );

    const parsedMeals = results
      .filter((r): r is { ok: ParsedMealEntry } => "ok" in r)
      .map((r) => r.ok);
    const failedMeals = results
      .filter((r): r is { fail: FailedMeal } => "fail" in r)
      .map((r) => r.fail);

    // Confirmation class: how many distinct dates?
    const distinctDates = new Set(parsedMeals.map((m) => m.date)).size;
    const confirmationClass: "reviewable" | "destructive" = distinctDates > 1
      ? "destructive"
      : "reviewable";

    // Preview summary
    const totalKcal = parsedMeals.reduce((s, m) => s + m.total_calories, 0);
    const dayWord = distinctDates === 1 ? "day" : "days";
    const summary =
      `Pre-log ${parsedMeals.length} meal${parsedMeals.length === 1 ? "" : "s"} across ${distinctDates} ${dayWord} (${totalKcal} kcal total)${
        failedMeals.length > 0
          ? ` \u2014 ${failedMeals.length} failed to parse`
          : ""
      }`;

    return {
      type: "prelog",
      payload: {
        parsed_meals: parsedMeals,
        failed_meals: failedMeals,
      },
      confirmationClass,
      previewSummary: summary,
    };
  },
};
