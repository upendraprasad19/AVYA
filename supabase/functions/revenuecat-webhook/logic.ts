// revenuecat-webhook/logic.ts — OI-519 (+51), plan section 4 entry point 1.
//
// RevenueCat POSTs every purchase event here (verify_jwt = false). The body is NEVER trusted for state: it only names
// which customer to re-read; the shared mirror (_shared/revenuecat_mirror.ts) reads the truth from RevenueCat's REST API
// and writes the row. Auth: the `Authorization` header must equal the secret REVENUECAT_WEBHOOK_AUTH (set by the founder
// in the Supabase dashboard and the RevenueCat webhook settings; never in code or chat). Unset secret -> 500, nothing
// written (fail closed; RevenueCat retries). Only HTTP 200 counts as delivered for RevenueCat, so a mirror failure answers
// 503 and RevenueCat retries (about 2.5/5/10/20/40 min); after the last retry the hourly reconcile catches up.
//
// Log safety: no body, header, key or app_user_id is ever logged; lines carry the request id and fixed codes only.

import { timingSafeEqual } from "../_shared/cron_auth.ts";
import { isUuid, type MirrorOutcome, RevenueCatReadError } from "../_shared/revenuecat_mirror.ts";

export const WEBHOOK_AUTH_ENV = "REVENUECAT_WEBHOOK_AUTH";
export const MAX_BODY_BYTES = 64 * 1024;
export const TRANSFER_ALERT_SOURCE = "revenuecat_transfer";
export const PAID_NO_ROW_ALERT_SOURCE = "revenuecat_paid_no_row";
const PAID_EVENT_TYPES = new Set(["INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "PRODUCT_CHANGE"]);
/** RevenueCat's documented event types. Only these are ever logged; anything else logs as "other" (the type is body text). */
const KNOWN_EVENT_TYPES = new Set([
  "TEST", "INITIAL_PURCHASE", "RENEWAL", "CANCELLATION", "UNCANCELLATION", "NON_RENEWING_PURCHASE", "SUBSCRIPTION_PAUSED",
  "EXPIRATION", "BILLING_ISSUE", "PRODUCT_CHANGE", "TRANSFER", "SUBSCRIPTION_EXTENDED", "TEMPORARY_ENTITLEMENT_GRANT",
  "REFUND_REVERSED", "INVOICE_ISSUANCE", "VIRTUAL_CURRENCY_TRANSACTION",
]);

export type EventRecord = {
  provider_event_id: string;
  user_id: string | null;
  event_type: string;
  product_id: string | null;
  environment: "SANDBOX" | "PRODUCTION" | null;
  event_timestamp_ms: number | null;
  outcome: string;
};

export type WebhookDeps = {
  env: (name: string) => string | undefined;
  mirrorEnabled: () => boolean;
  userExists: (uid: string) => Promise<boolean>;
  recordEvent: (rec: EventRecord) => Promise<void>;
  mirror: (uid: string) => Promise<MirrorOutcome>;
  alert: (source: string, summary: string, context: Record<string, unknown>) => Promise<void>;
  requestId?: () => string;
};

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

function newRequestId(): string {
  return crypto.randomUUID().split("-")[0];
}

function str(v: unknown): string | null {
  return typeof v === "string" && v.length > 0 && v.length <= 200 ? v : null;
}

export async function handler(req: Request, deps: WebhookDeps): Promise<Response> {
  const rid = (deps.requestId ?? newRequestId)();
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  const secret = deps.env(WEBHOOK_AUTH_ENV);
  if (!secret) {
    console.error(`[revenuecat-webhook] request_id=${rid} ${WEBHOOK_AUTH_ENV} is unset; refusing (fail closed)`);
    return json(500, { error: "Internal server error", request_id: rid });
  }
  // The header must carry the secret, as is or after "Bearer " (the RevenueCat field is free text; B-pass F8). Both
  // comparisons always run, so the time taken does not say which form was tried.
  const header = req.headers.get("Authorization") ?? "";
  const asIs = await timingSafeEqual(header, secret);
  const bearer = await timingSafeEqual(header, `Bearer ${secret}`);
  if (!asIs && !bearer) {
    console.warn(`[revenuecat-webhook] request_id=${rid} bad authorization`);
    return json(401, { error: "Unauthorized" });
  }

  const declared = Number(req.headers.get("Content-Length") ?? "0");
  if (declared > MAX_BODY_BYTES) return json(413, { error: "Payload too large" });
  const raw = await req.text();
  if (new TextEncoder().encode(raw).length > MAX_BODY_BYTES) return json(413, { error: "Payload too large" });

  let event: Record<string, unknown>;
  try {
    const parsed = JSON.parse(raw) as { event?: unknown };
    if (!parsed || typeof parsed.event !== "object" || parsed.event === null) throw new Error("no event");
    event = parsed.event as Record<string, unknown>;
  } catch (_) {
    console.warn(`[revenuecat-webhook] request_id=${rid} unparseable body`);
    return json(400, { error: "Bad request" });
  }

  const eventId = str(event.id);
  const type = str(event.type);
  if (!eventId || !type) return json(400, { error: "Bad request" });
  const typeTag = KNOWN_EVENT_TYPES.has(type) ? type : "other";

  const appUserId = str(event.app_user_id);
  const ledgerUser = isUuid(appUserId) && await deps.userExists(appUserId) ? appUserId : null;
  const env: EventRecord["environment"] = event.environment === "SANDBOX"
    ? "SANDBOX"
    : event.environment === "PRODUCTION"
    ? "PRODUCTION"
    : null;
  const tsMs = typeof event.event_timestamp_ms === "number" && Number.isFinite(event.event_timestamp_ms)
    ? Math.trunc(event.event_timestamp_ms)
    : null;
  const base = {
    provider_event_id: eventId,
    user_id: ledgerUser,
    event_type: type,
    product_id: str(event.product_id),
    environment: env,
    event_timestamp_ms: tsMs,
  };

  if (!deps.mirrorEnabled()) {
    await deps.recordEvent({ ...base, outcome: "switch_off" });
    console.log(`[revenuecat-webhook] request_id=${rid} type=${typeTag} outcome=switch_off`);
    return json(200, { ok: true });
  }
  if (type === "TEST") {
    await deps.recordEvent({ ...base, outcome: "test" });
    console.log(`[revenuecat-webhook] request_id=${rid} type=TEST outcome=test`);
    return json(200, { ok: true });
  }

  // Which customers to re-read. TRANSFER should never happen (founder set "Keep with original App User ID"); if it
  // does, both sides are re-read and the founder is paged.
  const uids = new Set<string>();
  if (type === "TRANSFER") {
    for (const k of ["transferred_from", "transferred_to"]) {
      const arr = event[k];
      if (Array.isArray(arr)) for (const v of arr) if (isUuid(v)) uids.add(v);
    }
    await deps.alert(TRANSFER_ALERT_SOURCE, "RevenueCat transferred a purchase between app accounts", { count: uids.size });
  } else {
    if (isUuid(appUserId)) uids.add(appUserId);
    const original = str(event.original_app_user_id);
    if (isUuid(original)) uids.add(original);
  }

  let outcome = uids.size === 0 ? "no_known_user" : "mirrored";
  let failed = false;
  for (const uid of uids) {
    try {
      const out = await deps.mirror(uid);
      if (out.outcome !== "mirrored") {
        if (outcome === "mirrored") outcome = out.outcome;
        continue;
      }
      if (PAID_EVENT_TYPES.has(type) && !out.rows.some((r) => r.status === "active")) {
        await deps.alert(PAID_NO_ROW_ALERT_SOURCE, "A paid RevenueCat event mirrored to no active Play row", {
          event_type: type,
        });
      }
    } catch (e) {
      failed = true;
      const code = e instanceof RevenueCatReadError ? e.code : (e as { name?: string })?.name ?? "error";
      console.error(`[revenuecat-webhook] request_id=${rid} type=${typeTag} mirror failed code=${code}`);
    }
  }
  if (failed) outcome = "mirror_failed";

  await deps.recordEvent({ ...base, outcome });
  console.log(`[revenuecat-webhook] request_id=${rid} type=${typeTag} outcome=${outcome}`);
  return failed ? json(503, { error: "Retry later", request_id: rid }) : json(200, { ok: true });
}
