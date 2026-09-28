/**
 * consume-day-swap — atomically consumes one day-swap allowance unit for the
 * caller's IST week and reports the resulting allowance.
 *
 * Input:  { week_start: "YYYY-MM-DD" }  (must be an IST Monday)
 * Output: { allowed: boolean, used: number, limit: number }
 *     or: { error: <code>, request_id: <8-hex> }  (400 / 401 / 500)
 *
 * Requires JWT auth. This is the ONE call site for quota key `day_swap`
 * (spec 2026-09-26-day-swapper-design.md §5.3 — "one key, one call site, one
 * limit"). All validation + RPC-result mapping lives in logic.ts so it is
 * unit-testable without booting a server.
 *
 * NOT a pre-write gate (Hermes L21 F2, 2026-09-28). A day swap is a local Hive
 * write: the phone checks its own copy of the allowance, performs the swap,
 * counts it, and only THEN calls this function in the background
 * (`DaySwapAllowance.recordSwap`). This call keeps the shared server count and
 * corrects the phone's copy when it answers (server wins when online); no
 * answer keeps the phone's copy (fail open, nothing retries). So `allowed:
 * false` never undoes a swap — it tells the phone the week is spent, which
 * blocks the NEXT swap. Founder-locked design (brainstorm decision 6): the
 * allowance is a convenience quota, not a paid entitlement (§4.4 rule 19's
 * server-verified list does not include it), and blocking offline swaps on a
 * server round-trip was rejected.
 */

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { isProUser } from "../_shared/subscription.ts";
import {
  mapQuotaResult,
  validateWeekStart,
  windowStartIso,
} from "./logic.ts";

// founder_digest_caps_mirror_test.dart's consume_quota-site extractor reads
// each EF's OWN index.ts source (it does not follow imports) and requires
// the p_quota_key / p_window_start / p_limit trio at the RPC call below to be
// LOCAL bare-identifier `const`s -- the same convention verify-payment and
// delete-account already use for their own quota-key/limit constants (fix1
// batch, coordinator ruling). logic.ts's exported DAY_SWAP_QUOTA_KEY /
// FREE_DAY_SWAP_LIMIT / PRO_DAY_SWAP_LIMIT remain the canonical values (used
// by validateWeekStart, logic_test.ts's sanity check, and the SoT registry);
// this file's own literals below are asserted equal to them by
// founder_digest_caps_mirror_test.dart's drift-guard test (comparing both
// files' SOURCE, not a runtime import) rather than duplicated unguarded.
const QUOTA_KEY = "day_swap";
const FREE_LIMIT = 1;
const PRO_LIMIT = 3;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonError(status: number, error: string, requestId: string): Response {
  return new Response(
    JSON.stringify({ error, request_id: requestId }),
    { status, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  const requestId = crypto.randomUUID().split("-")[0];

  if (req.method !== "POST") {
    return jsonError(400, "method_not_allowed", requestId);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace("Bearer ", "");

    // PURE service-role client — NO global Authorization header (the e8a1c3
    // class this file's own gate, check_edge_function_auth_pattern.dart,
    // exists to catch). The caller is authenticated separately via
    // getUser(token) below, and consume_quota is EXECUTE-granted to
    // service_role only (migration 130_consume_quota_revoke_public_execute.sql)
    // — an authenticated-context client could not call it at all.
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const { data: authData, error: authErr } = await supabase.auth.getUser(token);
    if (authErr || !authData?.user) {
      return jsonError(401, "Authentication required", requestId);
    }
    const userId = authData.user.id;

    const body = await req.json().catch(() => ({})) as { week_start?: unknown };
    const validation = validateWeekStart(body.week_start);
    if (!validation.ok) {
      return jsonError(400, validation.error, requestId);
    }
    const { weekStart } = validation;

    const isPro = await isProUser(supabase, userId);
    const windowStart = windowStartIso(weekStart);
    const limit = isPro ? PRO_LIMIT : FREE_LIMIT;

    const { data: rpcResult, error: rpcErr } = await supabase.rpc("consume_quota", {
      p_user_id: userId,
      p_quota_key: QUOTA_KEY,
      p_window_start: windowStart,
      p_limit: limit,
    });

    // Hermes L23 F3 pattern (ai-media-proxy/index.ts:849-861) — a result
    // that is not a number is refused exactly like an RPC error.
    // `consume_quota` returns an int (-1 past the cap, per migration
    // 128_usage_counters.sql:69-118); `null` or a string here is a shape
    // drift (signature change, PostgREST envelope change) and must not be
    // read as GRANTED.
    if (rpcErr || typeof rpcResult !== "number") {
      console.error(
        `[consume-day-swap] request_id=${requestId} quota ledger unreadable ` +
          `for user=${userId} key=${QUOTA_KEY}:`,
        rpcErr ? rpcErr.message : `consume_quota returned ${JSON.stringify(rpcResult)}`,
      );
      return jsonError(500, "Internal server error", requestId);
    }

    const outcome = mapQuotaResult(rpcResult, limit);
    return new Response(
      JSON.stringify(outcome),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error(`[consume-day-swap] request_id=${requestId}`, err);
    return jsonError(500, "Internal server error", requestId);
  }
});
