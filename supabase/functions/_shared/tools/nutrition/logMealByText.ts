import { z } from "npm:zod@3.25.76";
import type { ToolDefinition } from "../types.ts";
import { parseFoodText } from "../../food_parser.ts";

const schema = z.object({
  description: z.string().min(3).max(500).describe(
    "Free-text description of the meal. Examples: 'dal chawal 2 katoris', 'a plate of biryani and raita', 'paneer tikka 6 pieces with naan'. Be specific about quantities — the parser handles Indian portion units (katori, plate, piece, slice).",
  ),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional().describe(
    "Date the meal was eaten (YYYY-MM-DD). Defaults to today if omitted.",
  ),
  mealType: z.enum(["breakfast", "lunch", "dinner", "snacks"]).optional()
    .describe(
      "Optional meal type. The system will default to 'snacks' if omitted.",
    ),
});

type Args = z.infer<typeof schema>;

export const logMealByTextTool: ToolDefinition<Args> = {
  name: "logMealByText",
  family: "nutrition",
  kind: "write",
  confirmationClass: "trivial",
  tier: "free",
  description:
    "Parse a free-text meal description and log it to the user's nutrition for today. Use this when the user says things like 'log [food]', 'I just ate [food]', 'add [food]', or casually reports eating something (e.g. 'had dal chawal', 'just finished lunch — rajma rice'). The system parses Indian dishes, portion sizes (katori, plate, piece), and computes calories/macros. Always trivial-class — the user gets a 5-second auto-confirm card showing the parsed nutrition. Do NOT use this for 'what should I eat' questions (that's suggestMeal, coming later in Phase C).",
  schema,
  // Async intentBuilder — calls Gemini to parse the description before
  // emitting the log intent. See _shared/food_parser.ts.
  intentBuilder: async (args) => {
    const parsed = await parseFoodText(args.description);
    const preview = `${parsed.food_name} — ${
      Math.round(parsed.total_calories)
    } kcal`;
    return {
      type: "log_meal_by_text",
      payload: {
        original_description: args.description,
        date: args.date ?? null,
        meal_type: args.mealType ?? null,
        food_name: parsed.food_name,
        total_calories: Math.round(parsed.total_calories),
        total_protein_g: Math.round(parsed.total_protein_g),
        total_carbs_g: Math.round(parsed.total_carbs_g),
        total_fat_g: Math.round(parsed.total_fat_g),
        serving_description: parsed.serving_description,
        confidence: parsed.confidence,
        items: parsed.items,
      },
      confirmationClass: "trivial",
      previewSummary: preview,
    };
  },
};
