/**
 * cron_telemetry — per-invocation execution telemetry for cron Edge Functions.
 *
 * Closes audit 2026-05-17 / OI-15. Background: `cron.job_run_details.status='succeeded'`
 * only confirms the pg_cron-side `net.http_post()` dispatch succeeded; it does NOT
 * reflect the Edge Function's actual HTTP response. During the Vault drift incident
 * (2026-05-11..16 — retired root §19 entry #161, relocated to
 * `supabase/functions/CLAUDE.md`'s cron-auth pattern by the 2026-05-18 declutter),
 * pg_cron reported 1066 "succeeded" runs across a week while every single call returned
 * 401 server-side and zero work happened.
 *
 * Each cron Edge Function imports this helper and:
 *   1. Calls `logCronStart(name)` at the top of its `serve` handler → returns a row id.
 *   2. Calls `logCronEnd(id, status, httpStatus?, errorSummary?)` before returning.
 *
 * The row lands in `public.cron_call_log` (migration 068). Retention: 7 days via
 * `public.cleanup_cron_call_log()` (must be wired by founder via pg_cron registration
 * — currently not scheduled; see open_issues.md OI-15 follow-up).
 *
 * Failures inside the telemetry call itself are SWALLOWED (try/catch + debug log).
 * Cron functions MUST NOT 500 because telemetry is broken.
 */

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

type CronLogStatus = "success" | "failed";

let _adminClient: SupabaseClient | null = null;

function adminClient() {
  if (_adminClient) return _adminClient;
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    // Edge runtime quirk — should never happen in prod, but don't crash if it does.
    return null;
  }
  _adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  return _adminClient;
}

/**
 * Insert a `started` row. Returns the row id so the caller can update on exit.
 *
 * Returns `null` if telemetry insert fails — callers should pass that null straight
 * back into `logCronEnd` (which is a no-op on null id). The function itself never
 * throws.
 */
export async function logCronStart(functionName: string): Promise<number | null> {
  try {
    const supabase = adminClient();
    if (!supabase) return null;
    const { data, error } = await supabase
      .from("cron_call_log")
      .insert({ function_name: functionName, status: "started" })
      .select("id")
      .single();
    if (error || !data) {
      console.warn(`[cron_telemetry] start insert failed for ${functionName}`, error);
      return null;
    }
    return (data as { id: number }).id;
  } catch (e) {
    console.warn(`[cron_telemetry] start exception for ${functionName}`, e);
    return null;
  }
}

/**
 * Update the row created by `logCronStart` with terminal status.
 *
 * Passes-through silently when `id` is null (i.e. start insert failed).
 */
export async function logCronEnd(
  id: number | null,
  status: CronLogStatus,
  opts?: { httpStatus?: number; requestId?: string; errorSummary?: string },
): Promise<void> {
  if (id == null) return;
  try {
    const supabase = adminClient();
    if (!supabase) return;
    const patch: Record<string, unknown> = { status };
    if (opts?.httpStatus !== undefined) patch.http_status = opts.httpStatus;
    if (opts?.requestId) patch.request_id = opts.requestId;
    if (opts?.errorSummary) {
      // Cap error summary at 1000 chars to avoid bloat from giant stack traces.
      patch.error_summary = opts.errorSummary.slice(0, 1000);
    }
    const { error } = await supabase
      .from("cron_call_log")
      .update(patch)
      .eq("id", id);
    if (error) {
      console.warn(`[cron_telemetry] end update failed for id=${id}`, error);
    }
  } catch (e) {
    console.warn(`[cron_telemetry] end exception for id=${id}`, e);
  }
}
