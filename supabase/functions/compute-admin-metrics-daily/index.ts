/**
 * compute-admin-metrics-daily — nightly snapshot for the founder admin
 * dashboard's trend charts.
 *
 * Calls the three public.founder_metrics_*() functions (migration 101) and
 * upserts one row per IST day into public.admin_metrics_daily (migration
 * 102). A live query can only ever show "right now" — this snapshot is what
 * makes "how did PRO count move over the last 30 days" answerable at all.
 *
 * Trigger: cron only (pg_cron, 23:45 IST daily — see migration 102). No
 * manual/admin invocation path; unlike promote-community-item there's no
 * legitimate reason for a human to trigger this outside the schedule.
 *
 * Idempotency: `admin_metrics_daily.snapshot_date` is UNIQUE; the upsert
 * below uses `onConflict: 'snapshot_date'` so a pg_cron retry (pg_cron does
 * not guarantee exactly-once execution) corrects the same day's row instead
 * of creating a duplicate that would corrupt every trend chart.
 */

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { corsHeaders, ok, serverError } from "../_shared/error.ts";
import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";
import { logCronEnd, logCronStart } from "../_shared/cron_telemetry.ts";
import { istDateStr } from "../_shared/ist_date.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

interface GrowthRow {
  total_users: number | null;
  signups_today_ist: number | null;
  signups_7d: number | null;
  signups_30d: number | null;
  pro_active: number | null;
  pro_expired: number | null;
  free_users: number | null;
  active_subscriptions: number | null;
  active_last_7d: number | null;
  generated_at: string;
}

interface EngagementRow {
  workouts_logged_today: number | null;
  food_logs_today: number | null;
  ai_messages_today: number | null;
  streak_maintained_current_week: number | null;
  generated_at: string;
}

interface OpsRow {
  client_errors_today: number | null;
  client_errors_7d: number | null;
  open_alerts_count: number | null;
  cron_failures_24h: number | null;
  generated_at: string;
}

export interface SnapshotRow {
  snapshot_date: string;
  total_users: number;
  signups_today_ist: number;
  signups_7d: number;
  signups_30d: number;
  pro_active: number;
  pro_expired: number;
  free_users: number;
  active_subscriptions: number;
  active_last_7d: number;
  workouts_logged_today: number;
  food_logs_today: number;
  ai_messages_today: number;
  streak_maintained_current_week: number;
  client_errors_today: number;
  client_errors_7d: number;
  open_alerts_count: number;
  cron_failures_24h: number;
}

const n = (v: number | null | undefined): number => v ?? 0;

/**
 * Merge the three RPC results into one admin_metrics_daily row. Pure —
 * no I/O, no Date.now(). Every numeric field is coalesced to 0 (never
 * null) so downstream trend/delta math never has to null-check.
 */
export function buildSnapshotRow(
  snapshotDate: string,
  growth: GrowthRow,
  engagement: EngagementRow,
  ops: OpsRow,
): SnapshotRow {
  return {
    snapshot_date: snapshotDate,
    total_users: n(growth.total_users),
    signups_today_ist: n(growth.signups_today_ist),
    signups_7d: n(growth.signups_7d),
    signups_30d: n(growth.signups_30d),
    pro_active: n(growth.pro_active),
    pro_expired: n(growth.pro_expired),
    free_users: n(growth.free_users),
    active_subscriptions: n(growth.active_subscriptions),
    active_last_7d: n(growth.active_last_7d),
    workouts_logged_today: n(engagement.workouts_logged_today),
    food_logs_today: n(engagement.food_logs_today),
    ai_messages_today: n(engagement.ai_messages_today),
    streak_maintained_current_week: n(engagement.streak_maintained_current_week),
    client_errors_today: n(ops.client_errors_today),
    client_errors_7d: n(ops.client_errors_7d),
    open_alerts_count: n(ops.open_alerts_count),
    cron_failures_24h: n(ops.cron_failures_24h),
  };
}

export const handler = async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (!await isAuthorizedCronCall(req)) {
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const logId = await logCronStart("compute-admin-metrics-daily");

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const [growthRes, engagementRes, opsRes] = await Promise.all([
      supabase.rpc("founder_metrics_for_admin_api").single(),
      supabase.rpc("founder_metrics_engagement").single(),
      supabase.rpc("founder_metrics_ops").single(),
    ]);

    if (growthRes.error || engagementRes.error || opsRes.error) {
      const errorSummary = [growthRes.error, engagementRes.error, opsRes.error]
        .filter(Boolean)
        .map((e) => e!.message)
        .join(" | ");
      await logCronEnd(logId, "failed", { httpStatus: 500, errorSummary });
      return serverError(
        "compute-admin-metrics-daily:rpc",
        new Error(errorSummary),
      );
    }

    const snapshotDate = istDateStr();
    const row = buildSnapshotRow(
      snapshotDate,
      growthRes.data as GrowthRow,
      engagementRes.data as EngagementRow,
      opsRes.data as OpsRow,
    );

    const { error: upsertError } = await supabase
      .from("admin_metrics_daily")
      .upsert(row, { onConflict: "snapshot_date" });

    if (upsertError) {
      await logCronEnd(logId, "failed", {
        httpStatus: 500,
        errorSummary: upsertError.message,
      });
      return serverError("compute-admin-metrics-daily:upsert", upsertError);
    }

    await logCronEnd(logId, "success", { httpStatus: 200 });
    return ok({ ok: true, snapshot_date: snapshotDate });
  } catch (err) {
    await logCronEnd(logId, "failed", {
      httpStatus: 500,
      errorSummary: String(err).slice(0, 500),
    });
    return serverError("compute-admin-metrics-daily", err);
  }
};

if (import.meta.main) {
  serve(handler);
}
