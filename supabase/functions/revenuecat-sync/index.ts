// revenuecat-sync — OI-519 (+51). Thin shell; the handler lives in logic.ts (tested in index_test.ts). verify_jwt = true.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import {
  isMirrorEnabled,
  mirrorRevenueCatCustomer,
  REVENUECAT_SECRET_ENV,
  supabaseMirrorDb,
} from "../_shared/revenuecat_mirror.ts";
import { corsHeaders, handler, type SyncDeps } from "./logic.ts";

function realDeps(): SyncDeps {
  // Rule 9 (e8a1c3): authenticate with the SERVICE-ROLE client's auth.getUser(token), never the user JWT as the key.
  const client = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const db = supabaseMirrorDb(client);
  return {
    authUser: async (token) => {
      const { data, error } = await client.auth.getUser(token);
      return error || !data?.user ? null : data.user.id;
    },
    // The argument object is built in logic.ts (the founder digest mirror resolves the key, window and limit there).
    consumeQuota: async (args) => await client.rpc("consume_quota", args),
    mirrorEnabled: () => isMirrorEnabled(),
    mirror: (uid) => mirrorRevenueCatCustomer(uid, { db, secretKey: Deno.env.get(REVENUECAT_SECRET_ENV) }),
    readCurrent: async (uid) => {
      const { data, error } = await client
        .from("subscriptions")
        .select("plan, end_date, store, auto_renew, store_expires_at")
        .eq("user_id", uid)
        .eq("status", "active")
        .order("end_date", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (error) throw new Error(`subscriptions read failed: ${(error as { code?: string }).code ?? "unknown"}`);
      return data;
    },
  };
}

export async function serveRequest(req: Request): Promise<Response> {
  try {
    return await handler(req, realDeps());
  } catch (e) {
    const rid = crypto.randomUUID().split("-")[0];
    console.error(`[revenuecat-sync] request_id=${rid} unhandled ${(e as { name?: string })?.name ?? "error"}`);
    return new Response(JSON.stringify({ error: "Internal server error", request_id: rid }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
}

if (import.meta.main) serve((req) => serveRequest(req));
