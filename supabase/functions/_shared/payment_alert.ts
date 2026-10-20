/**
 * payment_alert - page the founder when a CAPTURED payment could not be recorded
 * (OI-341 Piece B1, plan docs/plans/oi341-piece-b-door.md section 2.3).
 *
 * The stacking ON path records a paid row through `public.record_paid_subscription`
 * (migration 161). If that call fails, Razorpay has the money and the user has no
 * entitlement row until a retry succeeds. The writer still answers its existing
 * 500 (the webhook retries; the client polls `verify-payment`), and this module
 * writes a `public.alerts` row so the failure is SEEN: `critical` pages Telegram
 * through the migration-133 trigger.
 *
 * Dedup: the FIRST failure for a payment id with no UNRESOLVED
 * `payment_record_failed` row in the last 24 hours is `critical`; later ones are
 * `warn` (digest only), so a persistent failure does not page once per webhook
 * retry and per client poll. A failed dedup read falls back to `critical`. Two
 * writers failing at the same instant can both page: one payment, two pages,
 * accepted. Both round trips are bounded (3 s each), so a hung alerts table adds at
 * most 6 s. That does NOT keep a failing webhook inside Razorpay's response clock:
 * after a 5 s lock timeout the 500 can take ~11 s. Razorpay treats a timeout like
 * the 500 (it retries) and the SQL function is idempotent, so the cost is latency
 * and a duplicate delivery; measuring it against Razorpay's clock is a B2 flip item.
 * A failed insert is logged and never changes the caller's response.
 *
 * No module-scope code: importing this file reads no env and does no I/O, so the
 * writers' OFF branch is unaffected by the import.
 */

export const PAYMENT_ALERT_SOURCE = "payment_record_failed";
const DEDUP_WINDOW_HOURS = 24;
const ROUND_TRIP_TIMEOUT_MS = 3000;

// deno-lint-ignore no-explicit-any
export type AlertDb = { from: (table: string) => any };

export type PaymentRecordFailure = {
  fn: "verify-payment" | "razorpay-webhook";
  requestId: string;
  paymentId: string;
  userId: string;
  plan: string;
  amountPaise: number | null;
  code: string;
};

/** Bound a PostgREST builder (a thenable) by a timeout; a timeout resolves to `{ timedOut: true }`. */
async function bounded<T>(op: PromiseLike<T>): Promise<T | { timedOut: true }> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<{ timedOut: true }>((resolve) => {
    timer = setTimeout(() => resolve({ timedOut: true }), ROUND_TRIP_TIMEOUT_MS);
  });
  try {
    return await Promise.race([Promise.resolve(op), timeout]);
  } finally {
    clearTimeout(timer);
  }
}

export async function reportPaymentRecordFailure(
  client: AlertDb,
  f: PaymentRecordFailure,
): Promise<void> {
  try {
    const since = new Date(Date.now() - DEDUP_WINDOW_HOURS * 3600 * 1000).toISOString();
    const recent = await bounded(
      client
        .from("alerts")
        .select("id")
        .eq("source", PAYMENT_ALERT_SOURCE)
        .eq("context_json->>payment_id", f.paymentId)
        .is("resolved_at", null)
        .gte("detected_at", since)
        .limit(1),
    );
    const r = recent as { data?: unknown[] | null; error?: unknown; timedOut?: true };
    const dedupFailed = r.timedOut === true || !!r.error || !Array.isArray(r.data);
    if (dedupFailed) {
      console.error(`[payment_alert] dedup read failed for payment_id=${f.paymentId}; paging anyway`);
    }
    const severity = !dedupFailed && (r.data as unknown[]).length > 0 ? "warn" : "critical";

    const inserted = await bounded(
      client.from("alerts").insert({
        source: PAYMENT_ALERT_SOURCE,
        severity,
        summary: `${f.fn}: paid payment not recorded (code ${f.code})`,
        context_json: {
          fn: f.fn,
          request_id: f.requestId,
          payment_id: f.paymentId,
          user_id: f.userId,
          plan: f.plan,
          amount_paise: f.amountPaise,
          code: f.code,
        },
        suggested_action:
          "Razorpay captured this payment but no subscriptions row was written. Check whether a later retry recorded it " +
          "(select * from subscriptions where razorpay_payment_id = the payment_id); if not, grep the function logs for " +
          "'stacking read failed' with this request_id and record the row by hand (docs/architecture/payment.md rule 9).",
      }),
    );
    const ins = inserted as { error?: unknown; timedOut?: true };
    if (ins.timedOut === true || ins.error) {
      console.error(`[payment_alert] alerts insert failed for payment_id=${f.paymentId}`);
    }
  } catch (e) {
    console.error(
      `[payment_alert] threw for payment_id=${f.paymentId}: ${(e as { name?: string })?.name ?? "error"}`,
    );
  }
}
