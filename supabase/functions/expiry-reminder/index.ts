/**
 * expiry-reminder — Daily 6AM IST cron.
 *
 * Finds PRO subscribers whose plan expires within 3 days.
 * Sends a push notification via OneSignal to prompt renewal.
 *
 * Respects user notification_preferences.subscription_reminders setting.
 */

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { sendPushNotification } from "../_shared/send_notification.ts";
import { markProactiveSent, shouldSendProactive } from "../_shared/proactive_dedup.ts";
import { logCronStart, logCronEnd } from "../_shared/cron_telemetry.ts";
import { fetchLatestActiveEndByUser, usersWithLatestEndIn } from "../_shared/subscription.ts";
import {
  fetchNotificationPrefsDetailed,
  isNotificationEnabled,
} from "../_shared/notification_prefs.ts";
import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // OI-31 (audit-2026-05-17 Hermes F6) — cron-only function. Reject any
  // caller that isn't pg_cron (helper verifies JWT signature against
  // SUPABASE_JWT_SECRET + role-claim === 'service_role'). Pre-fix this
  // function created a service-role client without verifying the caller —
  // a public POST could trigger fan-out of push notifications to every
  // PRO user expiring within 3 days.
  if (!await isAuthorizedCronCall(req)) {
    console.warn(`[cron-auth-gate] expiry-reminder unauthorized; status=401`);
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const logId = await logCronStart("expiry-reminder");

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const now = new Date();
    const threeDaysFromNow = new Date(now.getTime() + 3 * 24 * 60 * 60 * 1000);

    // 1. Find users whose LATEST active subscription ends within 3 days.
    //    OI-202 (Hermes L1 2026-09-29): this used to select EVERY active row
    //    ending inside the window, so a user with an older row about to lapse
    //    AND a later renewal row (live: 7 active rows for 5 users) got a
    //    "PRO plan expiring soon" push while already renewed — the exact case
    //    the latest-end reduction exists for. It also yielded one entry per row
    //    rather than per user. `fetchLatestActiveEndByUser` is paged (OI-79)
    //    and returns null on ANY read failure: that must reach the outer catch
    //    (cron telemetry "failed"), never read as "nobody is expiring" — the
    //    a7e2c4 bug class on a renewal-critical path. Genuinely empty still
    //    exits 200.
    const latestEnd = await fetchLatestActiveEndByUser(supabase, now.toISOString());
    if (latestEnd === null) throw new Error("expiry-reminder: subscriptions read failed");
    const expiringSubs: Array<{ user_id: string; end_date: string }> =
      usersWithLatestEndIn(latestEnd, now, threeDaysFromNow, true)
        .map(([user_id, end_date]) => ({ user_id, end_date }));

    if (expiringSubs.length === 0) {
      await logCronEnd(logId, "success", { httpStatus: 200 });
      return new Response(
        JSON.stringify({
          status: "success",
          message: "No subscriptions expiring within 3 days",
          users_checked: 0,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // OI-98 / e4a1b7 — ONE batched preference lookup instead of a per-user
    // query inside the loop, reading `user_preferences.notification_preferences`
    // with the legacy snapshot as fallback.
    //
    // `Detailed` because this function skips a user it cannot verify rather
    // than risk a reminder they switched off; the plain helper collapses
    // "could not ask" into ABSENT => SEND.
    const { prefs: notifPrefs, degraded: prefsDegraded } =
      await fetchNotificationPrefsDetailed(
        supabase,
        expiringSubs.map((s) => s.user_id as string),
      );
    if (prefsDegraded) {
      console.error(
        "[expiry-reminder] preference lookup degraded — skipping all sends",
      );
    }

    let sent = 0;
    let skipped = 0;

    for (const sub of expiringSubs) {
      const userId = sub.user_id as string;
      const endDate = new Date(sub.end_date as string);

      // Calculate days remaining.
      const daysLeft = Math.ceil(
        (endDate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24),
      );

      // Check notification preferences.
      //
      // Unit C (§2.24) direction preserved through the OI-98 move: a lapsing
      // PAYING user with no stored preferences must still get their reminder
      // (ABSENT => SEND, which `isNotificationEnabled` applies), and only a
      // GENUINE inability to read preferences skips them (`prefsDegraded`).
      //
      // ⚠ ONE WAY THIS IS NOT IDENTICAL, stated rather than glossed (B-pass
      // Finding 4). The old per-user query failed per USER; `degraded` is
      // batch-wide, because `fetchAllByIds` raises on any page and one lost
      // page makes the whole lookup untrustworthy. So a transient error now
      // skips EVERY candidate this run instead of one. That is the same
      // direction (skip rather than risk an unwanted push) and it is
      // self-healing — the next scheduled run re-reads — but it is a wider
      // blast radius for a transient fault, and calling it "preserved
      // verbatim" would have been an over-claim.
      if (prefsDegraded) {
        skipped++;
        continue;
      }
      if (!isNotificationEnabled(notifPrefs, userId, "subscription_reminders")) {
        skipped++;
        continue;
      }

      // Proactive dedup: skip if subscription_expiry already sent today.
      const allow = await shouldSendProactive(
        supabase,
        userId,
        "subscription_expiry",
      );
      if (!allow) {
        console.log(
          `[expiry-reminder] skipping ${userId}: dedup hit for subscription_expiry`,
        );
        skipped++;
        continue;
      }

      // Send push notification.
      const daysText =
        daysLeft <= 0
          ? "today"
          : daysLeft === 1
            ? "tomorrow"
            : `in ${daysLeft} days`;

      const ok = await sendPushNotification({
        userId,
        title: "PRO plan expiring soon",
        message: `Your PRO plan expires ${daysText}. Renew to keep your data and features.`,
        screen: "/profile",
      });

      if (ok) {
        sent++;
        await markProactiveSent(supabase, userId, "subscription_expiry");
      }
    }

    await logCronEnd(logId, "success", { httpStatus: 200 });
    return new Response(
      JSON.stringify({
        status: "success",
        expiring_subscriptions: expiringSubs.length,
        notifications_sent: sent,
        skipped_by_preference: skipped,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    // Sanitised 5xx: never leak raw exception / SQL text.
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[expiry-reminder] request_id=${requestId}`, err);
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
