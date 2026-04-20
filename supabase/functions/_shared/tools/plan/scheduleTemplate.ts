import { z } from "https://deno.land/x/zod@v3.23.8/mod.ts";
import type { ToolDefinition } from "../types.ts";

const schema = z.object({
  templateId: z.string().min(1).describe(
    "Template ID. Use the exact `id` from `snapshot.saved_templates[].id`. For multi-day templates created via createCustomTemplate, this can be ANY of the N day IDs in the group — the system resolves the full group automatically and fans out the days across the supplied dates.",
  ),
  dates: z.array(z.string().regex(/^\d{4}-\d{2}-\d{2}$/)).min(1).max(14)
    .describe(
      "Calendar dates to schedule (YYYY-MM-DD). 1-14 dates allowed. For multi-day templates, dates are assigned to each day of the template in order; if more dates than days are supplied, the template cycles (date[0]→day1, date[1]→day2, ..., date[N]→day1 again). Already-completed dates are silently skipped — history is never overwritten.",
    ),
});

type Args = z.infer<typeof schema>;

export const scheduleTemplateTool: ToolDefinition<Args> = {
  name: "scheduleTemplate",
  family: "plan",
  kind: "write",
  confirmationClass: "destructive",
  tier: "pro",
  description:
    "Schedule a workout template (custom or built-in) onto specific calendar dates. Use ONLY after the user explicitly says they want a saved template put on the calendar — most natural as a chained follow-up to createCustomTemplate ('Saved! Want me to schedule it for Mon/Wed/Fri?'). Works for any template in `snapshot.saved_templates[]`, including multi-day groups (the system resolves the full group from any one day's ID and fans the days across the supplied dates, cycling if needed). Already-completed dates are silently skipped (history is sacred). Each non-completed scheduled workout on the target dates is REPLACED — review the per-date assignment in the diff before confirming.",
  schema,
  intentBuilder: (args) => ({
    type: "schedule_template",
    payload: {
      template_id: args.templateId,
      dates: args.dates,
    },
    confirmationClass: "destructive",
    previewSummary: `Schedule template across ${args.dates.length} date${
      args.dates.length === 1 ? "" : "s"
    }`,
  }),
};
