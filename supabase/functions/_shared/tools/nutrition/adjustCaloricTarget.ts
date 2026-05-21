import { z } from "https://deno.land/x/zod@v3.25.76/mod.ts";
import type { ToolDefinition } from "../types.ts";

const schema = z.object({
  deltaKcal: z.number().int().min(-1500).max(1500).describe(
    "Signed kcal adjustment vs the user's baseline daily target. Negative for deficit (cut), positive for surplus (bulk/refuel). Range -1500 to +1500.",
  ),
  ttlDays: z.number().int().min(1).max(28).describe(
    "How many days the override applies (1-28). After expiry, the baseline target resumes automatically.",
  ),
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional().describe(
    "Optional start date (YYYY-MM-DD). Defaults to today.",
  ),
  reason: z.string().max(120).optional().describe(
    "Optional brief explanation shown to the user (e.g. 'cutting for event', 'heavy training week').",
  ),
});

type Args = z.infer<typeof schema>;

export const adjustCaloricTargetTool: ToolDefinition<Args> = {
  name: "adjustCaloricTarget",
  family: "nutrition",
  kind: "write",
  // Worst-case default; intent overrides per delta below.
  confirmationClass: "reviewable",
  tier: "pro",
  description:
    "Temporarily adjust the user's daily calorie target by a signed delta for N days (1-28). Use when the user wants to cut harder ('drop me 300 cals for a week'), refuel ('+400 today, big training session'), or experiment ('try a deficit for 5 days'). The adjustment auto-expires; baseline target resumes after TTL. Confirmation class is dynamic: |delta| <= 200 is trivial (5s auto-confirm); |delta| > 200 is reviewable (explicit confirm).",
  schema,
  intentBuilder: (args) => {
    const isLargeAdjustment = Math.abs(args.deltaKcal) > 200;
    const sign = args.deltaKcal >= 0 ? "+" : "";
    const dayWord = args.ttlDays === 1 ? "day" : "days";
    const reasonSuffix = args.reason ? ` \u2014 ${args.reason}` : "";
    return {
      type: "adjust_caloric_target",
      payload: {
        delta_kcal: args.deltaKcal,
        ttl_days: args.ttlDays,
        start_date: args.startDate ?? null,
        reason: args.reason ?? null,
      },
      confirmationClass: isLargeAdjustment ? "reviewable" : "trivial",
      previewSummary:
        `${sign}${args.deltaKcal} kcal/day for ${args.ttlDays} ${dayWord}${reasonSuffix}`,
    };
  },
};
