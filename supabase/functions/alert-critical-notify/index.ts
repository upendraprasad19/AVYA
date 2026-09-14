/**
 * alert-critical-notify — reads ONE alerts row by id and pushes it to the
 * founder's Telegram immediately. Invoked ONLY by the private.
 * dispatch_critical_alert_notify() trigger (migration 133, telemetry added
 * by migration 134) on a critical
 * alerts INSERT — never reachable from anywhere else. Cron-secret
 * authenticated, same as every other server-triggered function in this repo.
 */

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { clientError, corsHeaders, ok, serverError } from "../_shared/error.ts";
import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";
import { logCronEnd, logCronStart } from "../_shared/cron_telemetry.ts";
import { escapeHtml, sendTelegram } from "../_shared/telegram.ts";
import { istClock } from "../_shared/founder_digest_content.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

interface AlertRow {
  source: string;
  summary: string;
  detected_at: string;
  suggested_action: string | null;
}

export function formatCriticalAlertText(alert: AlertRow): string {
  // detected_at was selected and typed but never rendered (review round 1
  // F13) — the founder got a critical alert with no timestamp.
  const lines = [
    `🔴 <b>CRITICAL</b> ${istClock(alert.detected_at)}IST`,
    `${escapeHtml(alert.source)}`,
    escapeHtml(alert.summary),
  ];
  if (alert.suggested_action) {
    lines.push(`→ ${escapeHtml(alert.suggested_action)}`);
  }
  return lines.join("\n");
}

export const handler = async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (!await isAuthorizedCronCall(req)) {
    return clientError("Unauthorized", 401);
  }

  const logId = await logCronStart("alert-critical-notify");

  try {
    const token = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
    const chatId = Deno.env.get("FOUNDER_TELEGRAM_CHAT_ID") ?? "";
    if (!token || !chatId) {
      await logCronEnd(logId, "failed", {
        httpStatus: 500,
        errorSummary: "TELEGRAM_BOT_TOKEN / FOUNDER_TELEGRAM_CHAT_ID not configured",
      });
      return serverError("alert-critical-notify:secrets", new Error("secrets not configured"));
    }

    const body = await req.json().catch(() => ({}));
    const alertId = body?.alert_id;
    if (alertId == null) {
      await logCronEnd(logId, "failed", { httpStatus: 400, errorSummary: "missing alert_id" });
      return clientError("Missing alert_id", 400);
    }
    if (typeof alertId !== "number") {
      await logCronEnd(logId, "failed", { httpStatus: 400, errorSummary: "alert_id must be a number" });
      return clientError("alert_id must be a number", 400);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data, error } = await supabase
      .from("alerts")
      .select("source, summary, detected_at, suggested_action")
      .eq("id", alertId)
      .maybeSingle();

    if (error) throw error;
    if (!data) {
      // Alert row gone by the time we read it — not an error, just nothing to send.
      await logCronEnd(logId, "success", { httpStatus: 200 });
      return ok({ sent: false, reason: "alert_not_found" });
    }

    const text = formatCriticalAlertText(data as AlertRow);
    const result = await sendTelegram(token, chatId, text);

    if (!result.ok) {
      await logCronEnd(logId, "failed", { httpStatus: 502, errorSummary: result.summary });
      return serverError("alert-critical-notify:telegram", new Error(result.summary));
    }

    await logCronEnd(logId, "success", { httpStatus: 200 });
    return ok({ sent: true });
  } catch (err) {
    const requestId = crypto.randomUUID().slice(0, 8);
    console.error(`[alert-critical-notify] request_id=${requestId}`, err);
    await logCronEnd(logId, "failed", { httpStatus: 500, errorSummary: String(err).slice(0, 200) });
    return serverError("alert-critical-notify", err);
  }
};

if (import.meta.main) {
  serve(handler);
}
