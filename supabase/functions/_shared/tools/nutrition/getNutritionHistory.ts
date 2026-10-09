// supabase/functions/_shared/tools/nutrition/getNutritionHistory.ts
//
// B-7: nutrition family READ tool that exposes nutrition_logs +
// nutrition_log_items for past date ranges. Today's data is never queried
// here — that lives on the snapshot under meals_today / *_today fields
// (per Captain Manual "Today's nutrition" section). For past dates the
// coach calls this tool with a YYYY-MM-DD inclusive range.
import { z } from "npm:zod@3.25.76";
import type { ToolContext, ToolDefinition } from "../types.ts";
import { chunkIds } from "../../exercise_day.ts";
import { fetchPagesBounded } from "../../paged_fetch_bounded.ts";

/** per_day attaches items only up to this many days (B5); longer ranges return totals only. */
export const MAX_ITEM_RANGE_DAYS = 31;
export const ITEMS_OMITTED_NOTE = "items omitted for ranges over 31 days";

function rangeDays(from: string, to: string): number {
  return Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000) + 1;
}

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
      "per_day returns one row per date with totals + items (items only for ranges up to 31 days; longer ranges return per-day totals without items); total returns a single aggregate over the range.",
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
  note?: string;
  truncated?: boolean; // a read hit its page budget: totals are a lower bound
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
    // Paged (B4): a wide range of logs exceeds PostgREST's 1,000-row cap.
    const logsRes = await fetchPagesBounded<NutritionLogRow>(
      (withCount) =>
        sb
          .from("nutrition_logs")
          .select(
            "id, date, total_calories, total_protein, total_carbs, total_fat, total_fiber, meal_type",
            withCount ? { count: "exact" } : undefined,
          )
          .eq("user_id", userId)
          .gte("date", args.date_from)
          .lte("date", args.date_to),
      {
        orderBy: [{ column: "date" }, { column: "id" }],
        maxPages: 10,
        label: "getNutritionHistory:logs",
      },
    );
    const logs: NutritionLogRow[] = logsRes.rows;
    let truncated = logsRes.truncated;

    // B5: items are never read for `total`; for `per_day` only when the range
    // is <= 31 days. Longer per_day ranges return totals plus a note (no
    // rejection: `aggregation` defaults to per_day, so the default call must work).
    const wantItems = args.aggregation === "per_day" &&
      rangeDays(args.date_from, args.date_to) <= MAX_ITEM_RANGE_DAYS;
    let items: NutritionItemRow[] = [];
    if (wantItems && logs.length > 0) {
      const chunks = await Promise.all(
        chunkIds(logs.map((r) => r.id)).map((ids, i) =>
          fetchPagesBounded<NutritionItemRow>(
            (withCount) =>
              sb
                .from("nutrition_log_items")
                .select(
                  "log_id, food_name, calories, protein, carbs, fat",
                  withCount ? { count: "exact" } : undefined,
                )
                .in("log_id", ids),
            {
              orderBy: [{ column: "id" }],
              maxPages: 5,
              label: `getNutritionHistory:items#${i}`,
            },
          )
        ),
      );
      items = chunks.flatMap((c) => c.rows);
      truncated = truncated || chunks.some((c) => c.truncated);
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
        ...(wantItems ? {} : { note: ITEMS_OMITTED_NOTE }),
        ...(truncated ? { truncated: true } : {}),
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
      ...(truncated ? { truncated: true } : {}),
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
