// revenuecat-reconcile — OI-519 (+51). Hourly cron. Thin shell; the run lives in logic.ts (tested in index_test.ts).
// Cron auth via _shared/cron_auth.ts; telemetry via _shared/cron_telemetry.ts (CLAUDE.md section 4.5).
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";
import { logCronEnd, logCronStart } from "../_shared/cron_telemetry.ts";
import {
  isMirrorEnabled,
  mirrorRevenueCatCustomer,
  PLAY_SUBSCRIPTION_ID,
  REVENUECAT_API_BASE,
  REVENUECAT_SECRET_ENV,
  REVENUECAT_TIMEOUT_MS,
  type ServiceClient,
  supabaseMirrorDb,
} from "../_shared/revenuecat_mirror.ts";
import {
  DRAIN_BATCH,
  FN_NAME,
  handler,
  mergeReconcileCandidates,
  type ReconcileDb,
  type ReconcileDeps,
  SWITCH_OFF_CATCH_UP_DAYS,
  switchOffCatchUpUids,
} from "./logic.ts";
import { fetchAllPages } from "../_shared/paged_fetch.ts";

const H = 3600 * 1000;

export function reconcileDb(client: ServiceClient): ReconcileDb {
  const iso = (ms: number) => new Date(ms).toISOString();
  const count = async (q: PromiseLike<{ count: number | null; error: unknown }>) => {
    const { count: n, error } = await q;
    if (error) throw new Error("deferral count failed");
    return n ?? 0;
  };
  return {
    stallCounts: async (now) => ({
      pendingOld: await count(client.from("store_reward_deferrals").select("id", { count: "exact", head: true })
        .eq("status", "pending").lt("created_at", iso(now - 24 * H))),
      inFlightOld: await count(client.from("store_reward_deferrals").select("id", { count: "exact", head: true })
        .eq("status", "in_flight").lt("claimed_at", iso(now - 2 * H))),
      needsCheck: await count(client.from("store_reward_deferrals").select("id", { count: "exact", head: true })
        .eq("status", "needs_check")),
    }),
    reconcileUids: async (now) => {
      const { data, error } = await client.from("subscriptions").select("user_id").eq("store", "play")
        .or(`and(end_date.gte.${iso(now - 72 * H)},end_date.lte.${iso(now + 24 * H)}),and(status.eq.active,store_read_at.lt.${iso(now - 24 * H)})`)
        .order("store_read_at", { ascending: true })
        .limit(200);
      if (error) throw new Error("reconcile candidates read failed");
      // Plus every user whose webhook arrived while the switch was OFF and who has not been read since (a purchase made
      // between the deploy and the switch ON, or during a rollback, would otherwise never be mirrored).
      const regular = (data ?? []).map((r: { user_id: string }) => r.user_id);
      // The catch-up is best effort: any failure (a read error, more than 20 pages of events) skips it for this run and
      // never costs the regular candidates (B-pass round 2 on the hermes fixes).
      let catchUp: string[] = [];
      try {
        // Paged, newest first: one noisy user's events must not hide another user's (dedupe AFTER every page; B-pass on
        // the hermes fixes, seat A).
        type Ev = { user_id: string | null; received_at: string };
        const events = await fetchAllPages<Ev>(
          () => client.from("subscription_events").select("user_id, received_at").eq("outcome", "switch_off")
            .not("user_id", "is", null).gte("received_at", iso(now - SWITCH_OFF_CATCH_UP_DAYS * 24 * H)),
          { orderBy: [{ column: "id", ascending: false }], pageSize: 1000, maxPages: 20, label: "revenuecat-reconcile switch-off events" },
        );
        // The 200 most recent distinct users (one Play row each, so one read row each).
        const evUids = [...new Set<string>(events.map((r) => r.user_id).filter((u): u is string => !!u))].slice(0, 200);
        let reads: { user_id: string; store_read_at: string | null }[] = [];
        if (evUids.length > 0) {
          const rd = await client.from("subscriptions").select("user_id, store_read_at").eq("store", "play")
            .in("user_id", evUids).limit(400);
          if (rd.error) throw new Error("switch-off catch-up reads failed");
          reads = rd.data ?? [];
        }
        catchUp = switchOffCatchUpUids(events.filter((e) => e.user_id && evUids.includes(e.user_id)), reads);
      } catch (e) {
        console.warn(`[revenuecat-reconcile] switch-off catch-up skipped this run: ${(e as { name?: string })?.name ?? "error"}`);
      }
      return mergeReconcileCandidates(regular, catchUp);
    },
    crashedInFlight: async (now) => {
      const { data, error } = await client.from("store_reward_deferrals").select("id, claim_token")
        .eq("status", "in_flight").lt("claimed_at", iso(now - H)).limit(50);
      if (error) throw new Error("in-flight read failed");
      return (data ?? []).map((r: { id: string; claim_token: string }) => ({ id: r.id, token: r.claim_token }));
    },
    pendingRows: async (limit) => {
      if (limit !== DRAIN_BATCH) throw new Error("pendingRows reads exactly one drain batch");
      const { data, error } = await client.from("store_reward_deferrals").select("id, user_id, days")
        .eq("status", "pending").order("updated_at", { ascending: true }).order("created_at", { ascending: true }).limit(20); // = DRAIN_BATCH (a literal for the read gate)
      if (error) throw new Error("pending read failed");
      return data ?? [];
    },
    touch: async (id) => {
      const { error } = await client.from("store_reward_deferrals").update({ updated_at: new Date().toISOString() })
        .eq("id", id).eq("status", "pending").select("id").order("id").limit(1); // PGRST109, as in claim
      if (error) throw new Error("touch failed");
    },
    claim: async (id) => {
      const token = crypto.randomUUID();
      const { data, error } = await client.from("store_reward_deferrals")
        .update({ status: "in_flight", claim_token: token, claimed_at: new Date().toISOString(), updated_at: new Date().toISOString() })
        .eq("id", id).eq("status", "pending").select("id").order("id").limit(1); // PostgREST refuses a limited UPDATE without an order on a unique column (PGRST109)
      if (error) {
        if ((error as { code?: string }).code === "23505") return null; // another defer in flight for this user
        throw new Error("claim failed");
      }
      return Array.isArray(data) && data.length === 1 ? token : null;
    },
    mark: async (id, token, status) => {
      const { data, error } = await client.from("store_reward_deferrals")
        .update({ status, updated_at: new Date().toISOString(), ...(status === "pending" ? { claim_token: null, claimed_at: null } : {}) })
        .eq("id", id).eq("status", "in_flight").eq("claim_token", token).select("id").order("id").limit(1); // PGRST109, as in claim
      if (error) throw new Error("mark failed");
      return Array.isArray(data) && data.length === 1;
    },
    fallBack: async (id, token) => {
      // oi79-ok: store_reward_fall_back RETURNS text (one scalar).
      const { data, error } = await client.rpc("store_reward_fall_back", { p_id: id, p_token: token });
      if (error) throw new Error(`fall back failed: ${(error as { code?: string }).code ?? "unknown"}`);
      return String(data);
    },
  };
}

async function postDefer(uid: string, days: number): Promise<number> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), REVENUECAT_TIMEOUT_MS);
  try {
    const res = await fetch(
      `${REVENUECAT_API_BASE}/subscribers/${encodeURIComponent(uid)}/subscriptions/${PLAY_SUBSCRIPTION_ID}/defer`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${Deno.env.get(REVENUECAT_SECRET_ENV) ?? ""}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ extend_by_days: days }),
        signal: ctrl.signal,
      },
    );
    await res.body?.cancel();
    return res.status;
  } finally {
    clearTimeout(timer);
  }
}

function realDeps(): ReconcileDeps {
  const client = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const mdb = supabaseMirrorDb(client);
  return {
    authorized: (req) => isAuthorizedCronCall(req),
    telemetryStart: () => logCronStart("revenuecat-reconcile"), // a literal: the cron_call_log roster reads it (= FN_NAME)
    telemetryEnd: (id, status, opts) => logCronEnd(id, status, opts),
    mirrorEnabled: () => isMirrorEnabled(),
    db: reconcileDb(client),
    mirror: (uid) => mirrorRevenueCatCustomer(uid, { db: mdb, secretKey: Deno.env.get(REVENUECAT_SECRET_ENV) }),
    postDefer,
    alert: (source, summary, context) => mdb.alert(source, "warn", summary, context),
  };
}

if (import.meta.main) serve((req) => handler(req, realDeps()));
