// delete-account/revenuecat_leg.ts — OI-519 U4 (plan section 4, "delete-account"), best effort and NON-FATAL, like
// the Razorpay leg (a2c8e6): DPDP §17 erasure must never be blocked by a store outage.
//
// For every Play row of the user that was not refunded (status != 'cancelled'; a paused or on-hold row maps to
// 'expired' but Google can still bill it), FIRST RevenueCat's Google cancel
// (`POST /v1/subscribers/{uid}/subscriptions/{store_transaction_id}/cancel`, stops renewal), each with a 10 s timeout.
// ONLY when every cancel succeeded, `DELETE /v1/subscribers/{uid}` (DPDP: RevenueCat's copy of the customer). Deleting
// first would lose the handle needed to retry a cancel by hand, so one failed cancel skips the delete for the whole
// customer. With no Play row the customer is still deleted (the app's SDK may have created one) when the secret is set.
//
// An EXPIRED row may still bill (paused, or on hold after a failed payment) so it is cancelled too, but Google answers
// a cancel on a subscription that has truly ended (its token dies 60 days after expiry) with 410 Gone: for an expired
// row only, 410 (ENDED_CODES) means already ended. It is reported in the status (`;ended:<txn>:<code>`), not alerted,
// and does not block the customer delete. Every other failure stays a failure and alerts, on any row: 400/404/422 are
// generic answers a paused or held subscription (or a wrong id) could also get, and a silent miss there would delete
// the handle of a subscription that can still bill (B-pass seat A, round 2, 2026-11-24).
//
// A failure is alerted (one critical `alerts` row per deletion, NOT deduplicated: each is a different user to cancel by
// hand) and returned as a status string for the function's logs. It does NOT read the mirror switch: a Play payer who
// deletes the account must stop being billed even with the mirror off.
//
// Logs carry status codes only, never a response body (payment log safety).

import { REVENUECAT_API_BASE, REVENUECAT_TIMEOUT_MS } from "../_shared/revenuecat_mirror.ts";

export const PLAY_DELETE_ALERT_SOURCE = "revenuecat_delete_failed";

export type PlayDeleteDeps = {
  /** REVENUECAT_SECRET_KEY, or null/"" when unset. */
  secret: string | null;
  /** The user's non-refunded Play rows: store transaction id (null = the mirror wrote none) and whether the row is
   *  `expired` (else `active`). */
  readPlayTxns: () => Promise<{ txns: PlayTxn[] } | { error: string }>;
  fetchFn?: typeof fetch;
  timeoutMs?: number;
  alert: (summary: string, context: Record<string, unknown>) => Promise<void>;
};

export type PlayTxn = { txn: string | null; expired: boolean };

/** A cancel answer that, for an EXPIRED row, means the subscription has already ended. */
export const ENDED_CODES: ReadonlySet<string> = new Set(["410"]);

export type PlayDeleteResult = {
  /** For the logs: no_play_sub | no_secret | lookup_failed | cancel_failed:<…> | customer_delete_failed:<…> | done:<n> */
  status: string;
  customerDeleted: boolean;
};

async function call(fetchFn: typeof fetch, url: string, method: string, secret: string, timeoutMs: number): Promise<string> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetchFn(url, {
      method,
      headers: { Authorization: `Bearer ${secret}`, Accept: "application/json" },
      signal: ctrl.signal,
    });
    await res.body?.cancel();
    return String(res.status);
  } catch (e) {
    return (e as { name?: string })?.name === "AbortError" ? "timeout" : "network";
  } finally {
    clearTimeout(timer);
  }
}

const ok = (code: string) => code === "200" || code === "201" || code === "204";

/** The cancel half: what to log, and whether the customer may be deleted once the account is gone. */
export type PlayCancelResult = { status: string; deleteCustomer: boolean };

function failWith(uid: string, deps: PlayDeleteDeps) {
  return async (status: string, context: Record<string, unknown>): Promise<PlayDeleteResult> => {
    try {
      await deps.alert(
        "Account deleted with a Google Play subscription that may still bill: cancel it in RevenueCat / Play Console by hand",
        { user_id: uid, status, ...context },
      );
    } catch (_) {
      // The status string still reaches the function log; an alert failure must not fail the erasure.
    }
    return { status, customerDeleted: false };
  };
}

/**
 * Step 1, BEFORE the auth user is deleted: cancel each Play row. The RevenueCat customer is NOT deleted here: a cancel
 * fires a CANCELLATION webhook, and while the users row still exists the mirror's GET would re-create a deleted customer
 * (a GET creates a missing one). [deletePlayCustomer] runs after the auth delete, when the mirror refuses the uid
 * (hermes seat 4, 2026-11-24).
 */
export async function cancelPlayRows(uid: string, deps: PlayDeleteDeps): Promise<PlayCancelResult> {
  const fetchFn = deps.fetchFn ?? fetch;
  const timeoutMs = deps.timeoutMs ?? REVENUECAT_TIMEOUT_MS;
  const fail = failWith(uid, deps);
  const failed = async (status: string, context: Record<string, unknown>): Promise<PlayCancelResult> =>
    ({ status: (await fail(status, context)).status, deleteCustomer: false });

  let read: { txns: PlayTxn[] } | { error: string };
  try {
    read = await deps.readPlayTxns();
  } catch (_) {
    read = { error: "exception" };
  }
  if ("error" in read) return await failed("lookup_failed", { code: read.error });
  const txns = read.txns;

  const secret = deps.secret ?? "";
  if (!secret) {
    return txns.length === 0 ? { status: "no_play_sub", deleteCustomer: false } : await failed("no_secret", { rows: txns.length });
  }

  const base = `${REVENUECAT_API_BASE}/subscribers/${encodeURIComponent(uid)}`;
  const failures: string[] = [];
  const ended: string[] = [];
  for (const { txn, expired } of txns) {
    if (!txn) {
      failures.push("no_txn");
      continue;
    }
    const code = await call(fetchFn, `${base}/subscriptions/${encodeURIComponent(txn)}/cancel`, "POST", secret, timeoutMs);
    if (ok(code)) continue;
    if (expired && ENDED_CODES.has(code)) ended.push(`${txn}:${code}`);
    else failures.push(`${txn}:${code}`);
  }
  if (failures.length > 0) {
    return await failed(`cancel_failed:${failures.join(",")}`.slice(0, 400), {
      cancelled: txns.length - failures.length - ended.length,
      ...(ended.length > 0 ? { ended: ended.join(",").slice(0, 200) } : {}),
    });
  }

  const endedNote = ended.length > 0 ? `;ended:${ended.join(",")}`.slice(0, 200) : "";
  return { status: `cancelled:${txns.length}${endedNote}`, deleteCustomer: true };
}

/** Step 2, AFTER the auth user is deleted (only when step 1 said so): DELETE the RevenueCat customer (DPDP). */
export async function deletePlayCustomer(uid: string, deps: PlayDeleteDeps): Promise<PlayDeleteResult> {
  const secret = deps.secret ?? "";
  if (!secret) return { status: "no_secret", customerDeleted: false };
  const base = `${REVENUECAT_API_BASE}/subscribers/${encodeURIComponent(uid)}`;
  const del = await call(deps.fetchFn ?? fetch, base, "DELETE", secret, deps.timeoutMs ?? REVENUECAT_TIMEOUT_MS);
  // 404: RevenueCat has no such customer (a web-only user): nothing left to erase.
  if (ok(del) || del === "404") return { status: `customer_deleted:${del}`, customerDeleted: ok(del) };
  return await failWith(uid, deps)(`customer_delete_failed:${del}`, {});
}

/** Both steps in order, for the unit tests (the function calls them apart, with the auth delete between). */
export async function cancelAndDeletePlayCustomer(uid: string, deps: PlayDeleteDeps): Promise<PlayDeleteResult> {
  const c = await cancelPlayRows(uid, deps);
  if (!c.deleteCustomer) return { status: c.status, customerDeleted: false };
  const d = await deletePlayCustomer(uid, deps);
  const n = c.status.replace(/^cancelled:/, "");
  return d.status.startsWith("customer_deleted:") ? { status: `done:${n}`, customerDeleted: d.customerDeleted } : d;
}
