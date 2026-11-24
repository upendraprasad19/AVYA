// revenuecat-webhook — OI-519 (+51). Thin shell; the handler and its rules live in logic.ts (tested in index_test.ts).
// Deploy with verify_jwt = false (RevenueCat sends no Supabase JWT; the Authorization header is checked in logic.ts).
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import {
  isMirrorEnabled,
  mirrorRevenueCatCustomer,
  REVENUECAT_SECRET_ENV,
  type ServiceClient,
  supabaseMirrorDb,
} from "../_shared/revenuecat_mirror.ts";
import { handler, type WebhookDeps } from "./logic.ts";

/** The ledger write (exported for test/sql/revenuecat_reconcile_postgrest_local.ts, which runs it against a real PostgREST). */
export function ledgerWriter(client: ServiceClient): WebhookDeps["recordEvent"] {
  return async (rec) => {
    const { error } = await client.from("subscription_events").upsert(
      { provider: "revenuecat", ...rec },
      { onConflict: "provider_event_id" },
    );
    if (error) throw new Error(`ledger write failed: ${(error as { code?: string }).code ?? "unknown"}`);
  };
}

function realDeps(): WebhookDeps {
  const client = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const db = supabaseMirrorDb(client);
  return {
    env: (n) => Deno.env.get(n),
    mirrorEnabled: () => isMirrorEnabled(),
    userExists: (uid) => db.userExists(uid),
    recordEvent: ledgerWriter(client),
    mirror: (uid) => mirrorRevenueCatCustomer(uid, { db, secretKey: Deno.env.get(REVENUECAT_SECRET_ENV) }),
    alert: (source, summary, context) => db.alert(source, "critical", summary, context),
  };
}

export async function serveRequest(req: Request): Promise<Response> {
  try {
    return await handler(req, realDeps());
  } catch (e) {
    const rid = crypto.randomUUID().split("-")[0];
    console.error(`[revenuecat-webhook] request_id=${rid} unhandled ${(e as { name?: string })?.name ?? "error"}`);
    return new Response(JSON.stringify({ error: "Internal server error", request_id: rid }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
}

if (import.meta.main) serve((req) => serveRequest(req));
