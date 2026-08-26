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

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { sendPushNotification } from "../_shared/send_notification.ts";
import { markProactiveSent, shouldSendProactive } from "../_shared/proactive_dedup.ts";
import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";
import { logCronStart, logCronEnd } from "../_shared/cron_telemetry.ts";
import { fetchAllByIds } from "../_shared/paged_fetch.ts";
import {
  fetchNotificationPrefs,
  isNotificationEnabled,
  type PrefsByUser,
} from "../_shared/notification_prefs.ts";
import { fetchProUserIds } from "../_shared/subscription.ts";

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
  notifPrefs: PrefsByUser,
  progressMap: Map<string, number>,
  supabase: SupabaseClient,
): Promise<"sent" | "skipped" | "error"> {
  try {
    const userId = user.id;
    const firstName = (user.full_name ?? "").split(" ")[0] || "Champion";

    // Check notification preferences (OI-98 / e4a1b7 — now sourced from
    // `user_preferences.notification_preferences`, snapshot as fallback, via
    // the shared helper rather than read inline off a snapshot row).
    // ABSENT => SEND is unchanged; only a literal `false` skips.
    if (!isNotificationEnabled(notifPrefs, userId, "weekly_recap")) {
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

  const logId = await logCronStart("weekly-recap-ready");

  try {
    const startTime = Date.now();
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const fourteenDaysAgo = new Date();
    fourteenDaysAgo.setDate(fourteenDaysAgo.getDate() - 14);
    const cutoff = fourteenDaysAgo.toISOString();

    // The Sunday Brief is a PRO deliverable, but this function had NO
    // subscription check of any kind — `last_active_at >= cutoff` was its ONLY
    // eligibility filter, so every active free/lapsed user got the PRO push.
    // Confirmed live 2026-08-07 on the founder's own account (PRO ended
    // 2026-07-05, still receiving it). Same shared helper morning-alert /
    // plateau-alert / protein-gap-alert already use — `status='active' AND
    // end_date > now()`, NOT the stale denormalized `users.subscription_status`.
    // Fetched ONCE, outside the page loop (it is a full-table set, not per-page).
    // Fail-safe: fetchProUserIds returns an EMPTY set on error and never throws,
    // so a lookup failure sends to nobody rather than to everybody — the safe
    // direction for a paid-tier push. Diagnose e3b9d7.
    const proUserIds = await fetchProUserIds(supabase);
    console.log(`weekly-recap-ready: ${proUserIds.size} PRO users eligible`);

    let totalUsers = 0;
    let sent = 0;
    let skipped = 0;
    let skippedNotPro = 0; // entitlement misses, NOT preference opt-outs
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
        // OI-79: stable sort key required — see the note in morning-alert. An
        // unordered .range() loop can duplicate or skip users between pages.
        .order("id", { ascending: true })
        .range(offset, offset + PAGE_SIZE - 1);

      if (usersErr) {
        console.error(`weekly-recap-ready: users fetch error at offset ${offset}:`, usersErr);
        if (offset === 0) {
          await logCronEnd(logId, "failed", {
            httpStatus: 500,
            errorSummary: `fetch users failed: ${String(usersErr)}`,
          });
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
      // Pagination bookkeeping above stays keyed on the RAW page (that is what
      // `.range()` walked); everything below works on the PRO subset only, so
      // the batch snapshot/progress fetches don't pull rows for users we will
      // never message.
      const proUsers = users.filter((u: ActiveUser) => proUserIds.has(u.id));
      // Counted separately from `skipped`. `skipped` feeds the response field
      // `skipped_by_preference`, which is specifically about a user having
      // switched the recap OFF. Folding entitlement misses into it would make
      // that number read as "N users disabled this" when most of N were simply
      // never PRO — and the free population dwarfs the opted-out one.
      skippedNotPro += users.length - proUsers.length;
      if (proUsers.length === 0) {
        offset += PAGE_SIZE;
        continue;
      }
      const userIds = proUsers.map((u: ActiveUser) => u.id);

      console.log(
        `weekly-recap-ready: batch ${batchNum}, ${users.length} users (offset ${offset})`,
      );

      // ── Batch fetch snapshots + progress for this page ──────
      // Two parallel bulk queries instead of 2N sequential queries
      // OI-79 — found by check_unbounded_cron_reads.dart, not by the manual
      // sweep. `user_daily_snapshots` holds ~5.7 rows per user (97 rows / 17
      // users live), so a 200-user page yields ~1140 rows and clipped at 1000
      // with no error. The rows dropped are the OLDEST-dated ones, and the
      // "first row per user wins" reduction below reads that as "this user has
      // no snapshot" — so users at the tail of a page silently lost their recap
      // data. Chunked + paged; the compound sort key keeps snapshot_date DESC
      // authoritative with `id` as the unique tiebreaker.
      const [prefsResult, progressResult] = await Promise.allSettled([
        // OI-98 — the snapshot batch this replaced existed ONLY to read
        // notification preferences off the newest row per user (`snapshotMap`
        // had no other consumer). The shared helper now owns that read, its
        // paging, and its fallback, so the whole reduction below went away with
        // it. `fetchNotificationPrefs` never throws, so the allSettled wrapper
        // is belt-and-braces rather than load-bearing here.
        fetchNotificationPrefs(supabase, userIds),
        fetchAllByIds<Record<string, unknown>>(
          (chunk) =>
            supabase.from("user_progress").select("user_id, current_week").in(
              "user_id",
              chunk,
            ),
          userIds,
          { orderBy: "id", label: "weekly-recap-ready progress" },
        ),
      ]);

      // Build lookup maps
      // `fetchAllByIds` resolves to the row array itself (and rejects on a page
      // error), so `.value` IS the rows — there is no `{ data, error }` wrapper
      // to unpack any more. Promise.allSettled still absorbs a rejection into
      // `status: "rejected"`, preserving this loop's existing "degrade to an
      // empty map rather than abort the page" behaviour.
      // An empty map degrades to ABSENT => SEND for everyone, which is the
      // same fail-safe direction this loop had before.
      let notifPrefs: PrefsByUser = new Map();
      if (prefsResult.status === "fulfilled") {
        notifPrefs = prefsResult.value;
      } else {
        console.error(
          "weekly-recap-ready: notification preference batch failed:",
          prefsResult.reason,
        );
      }

      const progressMap = new Map<string, number>();
      if (progressResult.status === "fulfilled") {
        for (const row of progressResult.value) {
          progressMap.set(row.user_id as string, (row.current_week as number) ?? 1);
        }
      } else {
        console.error(
          "weekly-recap-ready: progress batch failed:",
          progressResult.reason,
        );
      }

      // ── Process with bounded concurrency ─────────────────
      for (let i = 0; i < proUsers.length; i += CONCURRENCY) {
        const chunk = proUsers.slice(i, i + CONCURRENCY);
        const results = await Promise.allSettled(
          chunk.map((user: ActiveUser) =>
            processUser(user, notifPrefs, progressMap, supabase)
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
        `${totalUsers} users, ${sent} sent, ${skipped} skipped-by-pref, ${skippedNotPro} not-pro, ${errors} errors`,
    );

    await logCronEnd(logId, "success", { httpStatus: 200 });
    return new Response(
      JSON.stringify({
        status: "success",
        active_users: totalUsers,
        notifications_sent: sent,
        skipped_by_preference: skipped,
        skipped_not_pro: skippedNotPro,
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
    await logCronEnd(logId, "failed", {
      httpStatus: 500,
      requestId,
      errorSummary: String(err),
    });
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
