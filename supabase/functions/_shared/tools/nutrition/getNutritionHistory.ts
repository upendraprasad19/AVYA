// supabase/functions/_shared/tools/nutrition/getNutritionHistory.ts
//
// B-7: nutrition family READ tool that exposes nutrition_logs +
// nutrition_log_items for past date ranges. Today's data is never queried
// here — that lives on the snapshot under meals_today / *_today fields
// (per Captain Manual "Today's nutrition" section). For past dates the
// coach calls this tool with a YYYY-MM-DD inclusive range.
import { z } from "https://deno.land/x/zod@v3.23.8/mod.ts";
import type { ToolContext, ToolDefinition } from "../types.ts";

const schema = z.object({
  date_from: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "date_from must be YYYY-MM-DD")
    .describe(
      "Start date (inclusive) in YYYY-MM-DD format, IST. Must be in the past — today's data is in the snapshot, not this tool.",
    ),
  date_to: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "date_to must be YYYY-MM-DD")
    .describe(
      "End date (inclusive) in YYYY-MM-DD format, IST. Same value as date_from for a single day.",
    ),
  aggregation: z
    .enum(["per_day", "total"])
    .default("per_day")
    .describe(
      "per_day returns one row per date with totals + items; total returns a single aggregate over the range.",
    ),
});

type Args = z.infer<typeof schema>;

interface DayItem {
  food_name: string;
  meal_type: string;
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
}

interface DayRow {
  date: string;
  total_calories: number;
  total_protein: number;
  total_carbs: number;
  total_fat: number;
  total_fiber: number;
  meal_count: number;
  items: DayItem[];
}

interface TotalRow {
  total_calories: number;
  total_protein: number;
  total_carbs: number;
  total_fat: number;
  total_fiber: number;
  meal_count: number;
  days_with_logs: number;
  avg_calories_per_logged_day: number;
  avg_protein_per_logged_day: number;
}

interface Result {
  range: { from: string; to: string };
  aggregation: "per_day" | "total";
  days?: DayRow[];
  total?: TotalRow;
}

interface NutritionLogRow {
  id: string;
  date: string;
  total_calories: number | null;
  total_protein: number | null;
  total_carbs: number | null;
  total_fat: number | null;
  total_fiber: number | null;
  meal_type: string | null;
}

interface NutritionItemRow {
  log_id: string;
  food_name: string | null;
  calories: number | null;
  protein: number | null;
  carbs: number | null;
  fat: number | null;
}

export const getNutritionHistoryTool: ToolDefinition<Args, Result> = {
  name: "getNutritionHistory",
  family: "nutrition",
  kind: "read",
  tier: "free",
  description:
    "Returns aggregated nutrition data for a PAST date range. Use this when the user asks about food on past dates (e.g. 'what did I eat last Tuesday', 'protein average last week', 'compare yesterday vs day before'). Do NOT use for today — today's data is in your snapshot under meals_today / calories_consumed_today / protein_today.",
  selectionHints:
    "Use ONLY for past dates. For today, read meals_today / calories_consumed_today / protein_today directly from snapshot.",
  schema,
  maxLatencyMs: 3000,
  handler: async (ctx: ToolContext, args: Args): Promise<Result> => {
    const { sb, userId } = ctx;
    const { data: logsRaw, error: logsErr } = await sb
      .from("nutrition_logs")
      .select(
        "id, date, total_calories, total_protein, total_carbs, total_fat, total_fiber, meal_type",
      )
      .eq("user_id", userId)
      .gte("date", args.date_from)
      .lte("date", args.date_to)
      .order("date", { ascending: true });
    if (logsErr) {
      throw new Error(`nutrition_logs query failed: ${logsErr.message}`);
    }
    const logs: NutritionLogRow[] = logsRaw ?? [];

    const logIds = logs.map((r) => r.id);
    let items: NutritionItemRow[] = [];
    if (logIds.length > 0) {
      const { data: itemRows, error: itemsErr } = await sb
        .from("nutrition_log_items")
        .select("log_id, food_name, calories, protein, carbs, fat")
        .in("log_id", logIds);
      if (itemsErr) {
        throw new Error(
          `nutrition_log_items query failed: ${itemsErr.message}`,
        );
      }
      items = itemRows ?? [];
    }

    // Group by date
    const byDate = new Map<string, DayRow>();
    for (const log of logs) {
      const day = byDate.get(log.date) ?? {
        date: log.date,
        total_calories: 0,
        total_protein: 0,
        total_carbs: 0,
        total_fat: 0,
        total_fiber: 0,
        meal_count: 0,
        items: [],
      };
      day.total_calories += Number(log.total_calories ?? 0);
      day.total_protein += Number(log.total_protein ?? 0);
      day.total_carbs += Number(log.total_carbs ?? 0);
      day.total_fat += Number(log.total_fat ?? 0);
      day.total_fiber += Number(log.total_fiber ?? 0);
      day.meal_count += 1;
      byDate.set(log.date, day);
    }

    // Index logs by id so we can attach items + carry meal_type onto items.
    const logById = new Map<string, NutritionLogRow>();
    for (const log of logs) logById.set(log.id, log);

    for (const item of items) {
      const log = logById.get(item.log_id);
      if (!log) continue;
      const day = byDate.get(log.date);
      if (!day) continue;
      day.items.push({
        food_name: item.food_name ?? "",
        meal_type: log.meal_type ?? "",
        calories: Number(item.calories ?? 0),
        protein_g: Number(item.protein ?? 0),
        carbs_g: Number(item.carbs ?? 0),
        fat_g: Number(item.fat ?? 0),
      });
    }

    const days = Array.from(byDate.values()).sort((a, b) =>
      a.date.localeCompare(b.date)
    );

    if (args.aggregation === "per_day") {
      return {
        range: { from: args.date_from, to: args.date_to },
        aggregation: "per_day",
        days,
      };
    }

    const total = days.reduce(
      (acc, d) => ({
        total_calories: acc.total_calories + d.total_calories,
        total_protein: acc.total_protein + d.total_protein,
        total_carbs: acc.total_carbs + d.total_carbs,
        total_fat: acc.total_fat + d.total_fat,
        total_fiber: acc.total_fiber + d.total_fiber,
        meal_count: acc.meal_count + d.meal_count,
      }),
      {
        total_calories: 0,
        total_protein: 0,
        total_carbs: 0,
        total_fat: 0,
        total_fiber: 0,
        meal_count: 0,
      },
    );
    const daysWithLogs = days.length;
    return {
      range: { from: args.date_from, to: args.date_to },
      aggregation: "total",
      total: {
        ...total,
        days_with_logs: daysWithLogs,
        avg_calories_per_logged_day: daysWithLogs === 0
          ? 0
          : Math.round(total.total_calories / daysWithLogs),
        avg_protein_per_logged_day: daysWithLogs === 0
          ? 0
          : Math.round(total.total_protein / daysWithLogs),
      },
    };
  },
};
