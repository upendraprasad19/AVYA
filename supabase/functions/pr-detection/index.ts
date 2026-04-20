// PR Detection — Brainstorm §5 trigger #5.
// Cron-poll every 15 minutes: scan workout_log_exercises rows with is_pr=true
// inserted in the last 20 minutes (15min interval + 5min buffer for cron drift).
// Group PRs by user, send ONE notification per user mentioning their PR(s).
// Both free + PRO. Dedup via coach_memory.last_proactive_type (1/day max).
// Cron target: */15 * * * * (every 15 min). Registration deferred to T6.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { sendPushNotification } from "../_shared/send_notification.ts";
import {
  markProactiveSent,
  shouldSendProactive,
} from "../_shared/proactive_dedup.ts";
import { fetchCoachMemory } from "../_shared/coach_memory.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface PRRow {
  user_id: string;
  exercise_id: string; // = exercise name per CLAUDE.md §11
  weight_kg: number | null;
  reps: number | null;
  created_at: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  const requestId = crypto.randomUUID().split("-")[0];

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Window: last 20 minutes (15min cron + 5min buffer)
    const since = new Date(Date.now() - 20 * 60_000).toISOString();

    const { data: rows, error } = await supabase
      .from("workout_log_exercises")
      .select("user_id, exercise_id, weight_kg, reps, created_at")
      .eq("is_pr", true)
      .gte("created_at", since)
      .order("created_at", { ascending: false });
    if (error) throw error;

    if (!rows || rows.length === 0) {
      console.log(
        `[pr-detection] request_id=${requestId} no PRs in window`,
      );
      return new Response(JSON.stringify({ checked: 0, sent: 0 }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Group PRs by user
    const prsByUser = new Map<string, PRRow[]>();
    for (const row of rows as PRRow[]) {
      if (!prsByUser.has(row.user_id)) prsByUser.set(row.user_id, []);
      prsByUser.get(row.user_id)!.push(row);
    }

    let sent = 0;
    let dedupSkipped = 0;
    let errors = 0;

    for (const [userId, prs] of prsByUser.entries()) {
      // Dedup gate
      if (!(await shouldSendProactive(supabase, userId, "pr_celebration"))) {
        dedupSkipped++;
        continue;
      }

      // Personalization
      const memory = await fetchCoachMemory(supabase, userId);
      const usableMemory = memory?.private_mode ? null : memory;
      const firstName =
        (usableMemory?.preferred_name as string | null) ?? "champ";

      // Compose message — single line, ≤ 2 PRs explicitly named, "+N more" for tail
      const message = composeMessage(firstName, prs);

      try {
        const ok = await sendPushNotification({
          userId,
          title: prs.length === 1 ? "New PR! 🏆" : `${prs.length} new PRs! 🏆`,
          message,
          screen: "/train",
        });
        if (ok) {
          sent++;
          await markProactiveSent(supabase, userId, "pr_celebration");
        } else {
          errors++;
        }
      } catch (e) {
        console.warn(`[pr-detection] send failed for ${userId}:`, e);
        errors++;
      }
    }

    console.log(
      `[pr-detection] request_id=${requestId} pr_rows=${rows.length} users=${prsByUser.size} sent=${sent} dedup_skipped=${dedupSkipped} errors=${errors}`,
    );

    return new Response(
      JSON.stringify({
        pr_rows: rows.length,
        users: prsByUser.size,
        sent,
        dedup_skipped: dedupSkipped,
        errors,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error(`[pr-detection] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

/** Build a single-line celebratory message from up to 2 PRs (+N more). */
function composeMessage(firstName: string, prs: PRRow[]): string {
  if (prs.length === 0) return "";

  const fmt = (p: PRRow) => {
    const weight = p.weight_kg ?? 0;
    const reps = p.reps ?? 0;
    if (weight > 0) {
      return `${p.exercise_id} ${weight}kg`;
    }
    return `${p.exercise_id} ${reps} reps`;
  };

  if (prs.length === 1) {
    return `${firstName} — new ${fmt(prs[0])} PR. Want to bump next week's target?`;
  }
  if (prs.length === 2) {
    return `${firstName} — new PRs: ${fmt(prs[0])}, ${fmt(prs[1])}. Strong session.`;
  }
  // 3+ PRs
  const tail = prs.length - 2;
  return `${firstName} — new PRs: ${fmt(prs[0])}, ${fmt(prs[1])} +${tail} more. Strong session.`;
}
