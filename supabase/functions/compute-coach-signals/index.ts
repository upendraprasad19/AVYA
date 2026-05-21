// supabase/functions/compute-coach-signals/index.ts
// Nightly cron: computes dropout / plateau / pro_upgrade signals
// for every active user and writes them to coach_memory.
// Pure SQL — no AI cost.
//
// Known limitation (v1): per-user RPC round-trip. With the 5000-user
// safety ceiling in active_users_for_signals(), worst-case is 5000
// round-trips. Acceptable for current scale; revisit when active user
// count exceeds ~2000.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { upsertCoachMemory } from "../_shared/coach_memory.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

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
    return new Response(
      JSON.stringify({ status: "ok", processed, failed, request_id: requestId }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error(`[compute-coach-signals] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});

async function computeSignalsForUser(
  supabase: ReturnType<typeof createClient>,
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
