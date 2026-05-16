/**
 * weekly-recap-ready — Sunday cron.
 *
 * Sends a push notification telling users their weekly recap is ready.
 * Respects user notification_preferences.weekly_recap setting.
 *
 * Architecture (10K-safe):
 *   - Paginated user fetch (PAGE_SIZE = 200)
 *   - Bounded concurrency (CONCURRENCY = 20)
 *   - Batch snapshot + progress lookups (not N+1 per-user)
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { sendPushNotification } from "../_shared/send_notification.ts";
import { markProactiveSent, shouldSendProactive } from "../_shared/proactive_dedup.ts";
import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const PAGE_SIZE = 200;
const CONCURRENCY = 20;

interface ActiveUser {
  id: string;
  full_name: string | null;
}

/**
 * Process a single user: check prefs, get week number, send push.
 */
async function processUser(
  user: ActiveUser,
  snapshotMap: Map<string, Record<string, unknown>>,
  progressMap: Map<string, number>,
  supabase: SupabaseClient,
): Promise<"sent" | "skipped" | "error"> {
  try {
    const userId = user.id;
    const firstName = (user.full_name ?? "").split(" ")[0] || "Champion";

    // Check notification preferences from pre-fetched snapshot
    const snapshot = snapshotMap.get(userId);
    const prefs = (snapshot as Record<string, unknown>)?.notification_preferences as
      | Record<string, unknown>
      | undefined;
    if (
      (prefs?.weekly_recap as Record<string, unknown>)?.enabled === false
    ) {
      return "skipped";
    }

    // Proactive dedup: skip if weekly_recap already sent today.
    const allow = await shouldSendProactive(supabase, userId, "weekly_recap");
    if (!allow) {
      console.log(
        `[weekly-recap-ready] skipping ${userId}: dedup hit for weekly_recap`,
      );
      return "skipped";
    }

    const currentWeek = progressMap.get(userId) ?? 1;

    const ok = await sendPushNotification({
      userId,
      title: "Sunday Brief",
      message: `${firstName} — Week ${currentWeek} debrief ready. Stand to.`,
      screen: "/profile/reports",
    });

    if (ok) {
      await markProactiveSent(supabase, userId, "weekly_recap");
      return "sent";
    }
    return "error";
  } catch (err) {
    console.error(`weekly-recap-ready: error for user ${user.id}:`, err);
    return "error";
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // audit-2026-05-16 E.14.C — installed shared `isAuthorizedCronCall(req)`
  // gate (no prior inline check existed; cron caller relied on
  // `verify_jwt: false` alone). Survives Vault/env key rotation: verifies
  // JWT signature against SUPABASE_JWT_SECRET + role-claim ===
  // 'service_role'. CRON_SECRET opaque-token escape hatch preserved
  // inside the helper. Closes Test #16 P1-D drift class.
  if (!await isAuthorizedCronCall(req)) {
    console.warn(`[cron-auth-gate] unauthorized caller; status=401`);
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  try {
    const startTime = Date.now();
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const fourteenDaysAgo = new Date();
    fourteenDaysAgo.setDate(fourteenDaysAgo.getDate() - 14);
    const cutoff = fourteenDaysAgo.toISOString();

    let totalUsers = 0;
    let sent = 0;
    let skipped = 0;
    let errors = 0;
    let offset = 0;
    let hasMore = true;
    let batchNum = 0;

    while (hasMore) {
      // ── Paginated user fetch ──────────────────────────
      const { data: users, error: usersErr } = await supabase
        .from("users")
        .select("id, full_name")
        .gte("last_active_at", cutoff)
        .range(offset, offset + PAGE_SIZE - 1);

      if (usersErr) {
        console.error(`weekly-recap-ready: users fetch error at offset ${offset}:`, usersErr);
        if (offset === 0) {
          return new Response(
            JSON.stringify({ error: "Failed to fetch active users" }),
            { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }
        break;
      }

      if (!users || users.length === 0) break;
      if (users.length < PAGE_SIZE) hasMore = false;

      batchNum++;
      totalUsers += users.length;
      const userIds = users.map((u: ActiveUser) => u.id);

      console.log(
        `weekly-recap-ready: batch ${batchNum}, ${users.length} users (offset ${offset})`,
      );

      // ── Batch fetch snapshots + progress for this page ──────
      // Two parallel bulk queries instead of 2N sequential queries
      const [snapshotResult, progressResult] = await Promise.allSettled([
        supabase
          .from("user_daily_snapshots")
          .select("user_id, snapshot_json")
          .in("user_id", userIds)
          .order("snapshot_date", { ascending: false }),
        supabase
          .from("user_progress")
          .select("user_id, current_week")
          .in("user_id", userIds),
      ]);

      // Build lookup maps
      const snapshotMap = new Map<string, Record<string, unknown>>();
      if (snapshotResult.status === "fulfilled" && snapshotResult.value.data) {
        for (const row of snapshotResult.value.data) {
          // Only keep the first (most recent) per user
          if (!snapshotMap.has(row.user_id)) {
            snapshotMap.set(row.user_id, row.snapshot_json ?? {});
          }
        }
      }

      const progressMap = new Map<string, number>();
      if (progressResult.status === "fulfilled" && progressResult.value.data) {
        for (const row of progressResult.value.data) {
          progressMap.set(row.user_id, (row.current_week as number) ?? 1);
        }
      }

      // ── Process with bounded concurrency ─────────────────
      for (let i = 0; i < users.length; i += CONCURRENCY) {
        const chunk = users.slice(i, i + CONCURRENCY);
        const results = await Promise.allSettled(
          chunk.map((user: ActiveUser) =>
            processUser(user, snapshotMap, progressMap, supabase)
          ),
        );

        for (const r of results) {
          if (r.status === "fulfilled") {
            if (r.value === "sent") sent++;
            else if (r.value === "skipped") skipped++;
            else errors++;
          } else {
            errors++;
          }
        }
      }

      offset += PAGE_SIZE;
    }

    const elapsed = Date.now() - startTime;
    console.log(
      `weekly-recap-ready: completed in ${elapsed}ms, ` +
        `${totalUsers} users, ${sent} sent, ${skipped} skipped, ${errors} errors`,
    );

    return new Response(
      JSON.stringify({
        status: "success",
        active_users: totalUsers,
        notifications_sent: sent,
        skipped_by_preference: skipped,
        errors,
        batches: batchNum,
        elapsed_ms: elapsed,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    // Sanitised 5xx: never leak raw exception / SQL text.
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[weekly-recap-ready] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
