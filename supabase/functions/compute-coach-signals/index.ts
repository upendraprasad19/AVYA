// supabase/functions/compute-coach-signals/index.ts
// Nightly cron: computes dropout / plateau / pro_upgrade signals
// for every active user and writes them to coach_memory.
// Pure SQL — no AI cost.
//
// Known limitation (v1): per-user RPC round-trip. With the 5000-user
// safety ceiling in active_users_for_signals(), worst-case is 5000
// round-trips. Acceptable for current scale; revisit when active user
// count exceeds ~2000.

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { upsertCoachMemory } from "../_shared/coach_memory.ts";
import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";
import { logCronEnd, logCronStart } from "../_shared/cron_telemetry.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // ── Auth gate added 2026-07-26 (diagnose c3f8a1).
  //
  // This function shipped with NO authentication of any kind. It relied
  // entirely on verify_jwt=true at the gateway, which accepts ANY project-signed
  // JWT — including the anon key compiled into every APK and web bundle. Any
  // app user could therefore invoke it and drive up to 5000 RPC round-trips
  // (see the active_users_for_signals ceiling noted above).
  //
  // DEPLOY ORDER MATTERS: this gate must be deployed while verify_jwt is still
  // true (function is then double-protected), THEN verify_jwt flipped to false,
  // THEN migration 108 repoints the cron job onto CRON_SECRET. Flipping the flag
  // before this gate existed would have left the function briefly public.
  if (!await isAuthorizedCronCall(req)) {
    console.warn(`[compute-coach-signals] unauthorized caller; status=401`);
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const logId = await logCronStart("compute-coach-signals");
  const requestId = crypto.randomUUID().split("-")[0];
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: users, error } = await supabase.rpc("active_users_for_signals");
    if (error) throw error;

    let processed = 0;
    let failed = 0;
    for (const row of users ?? []) {
      const userId = (row as { user_id: string }).user_id;
      try {
        const signals = await computeSignalsForUser(supabase, userId);
        await upsertCoachMemory(supabase, userId, {
          ...signals,
          signals_computed_at: new Date().toISOString(),
        });
        processed++;
      } catch (perUserErr) {
        failed++;
        console.error(
          `[compute-coach-signals] request_id=${requestId} user=${userId} per-user-error:`,
          perUserErr,
        );
        // Continue — one bad user must not abort the batch.
      }
    }

    console.log(
      `[compute-coach-signals] request_id=${requestId} done processed=${processed} failed=${failed}`,
    );
    await logCronEnd(logId, "success", { httpStatus: 200, requestId });
    return new Response(
      JSON.stringify({ status: "ok", processed, failed, request_id: requestId }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error(`[compute-coach-signals] request_id=${requestId}`, err);
    await logCronEnd(logId, "failed", {
      httpStatus: 500,
      requestId,
      // NOT String(err): the dominant throw here is `if (error) throw error`
      // on a supabase-js PostgrestError, which is a plain {message, details,
      // hint, code} object — not an Error subclass — so String() yields
      // "[object Object]" and the telemetry carries no diagnostic content for
      // exactly the failure it exists to surface.
      errorSummary: (err as { message?: string } | null)?.message ??
        String(err),
    });
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});

async function computeSignalsForUser(
  supabase: SupabaseClient,
  userId: string,
): Promise<{
  dropout_risk_score: number | null;
  plateau_risk_score: number | null;
  pro_upgrade_probability: number | null;
}> {
  const { data, error } = await supabase.rpc("compute_coach_signals_for_user", {
    p_user_id: userId,
  });
  if (error) throw error;
  if (!data || !Array.isArray(data) || data.length === 0) {
    return {
      dropout_risk_score: null,
      plateau_risk_score: null,
      pro_upgrade_probability: null,
    };
  }
  const r = data[0] as {
    dropout_risk_score: number | null;
    plateau_risk_score: number | null;
    pro_upgrade_probability: number | null;
  };
  return {
    dropout_risk_score: r.dropout_risk_score,
    plateau_risk_score: r.plateau_risk_score,
    pro_upgrade_probability: r.pro_upgrade_probability,
  };
}
