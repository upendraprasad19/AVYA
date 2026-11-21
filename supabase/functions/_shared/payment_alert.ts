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
 * accepted. Both round trips are bounded (3 s each by default, so a hung alerts
 * table adds at most 6 s; the webhook passes 1 s since Piece B2a, so 2 s). After a
 * 5 s lock timeout the webhook's 500 can still exceed Razorpay's 5 s clock; Razorpay
 * treats a timeout like the 500 (it retries) and the SQL function is idempotent, so
 * the cost is latency and a duplicate delivery. Since Piece B2a the same alert also
 * covers a captured payment whose amount matches no plan (codes amount_no_match,
 * amount_cross_check): the money is taken and no row can be written.
 * A failed insert is logged and never changes the caller's response.
 *
 * OI-341 Piece B2a (docs/plans/oi341-piece-b2-door.md 2.4, 2.5):
 * - every round trip takes an optional `timeoutMs` (default 3000); the webhook
 *   passes 1000 so its failure 500 stays near Razorpay's 5 s clock;
 * - `checkStackingMismatch` is the writers' OFF-branch alarm: after an OFF insert
 *   it reads for an active `referral_trial` row that outlives the new row's start.
 *   A hit means a trial user was charged while this isolate read stacking OFF (a
 *   door-ON order on a stale isolate, or a referral redeemed mid-checkout), so
 *   the paid days overlap the trial instead of following it. It logs and pages
 *   `stacking_switch_mismatch` (`reportStackingMismatch`); it never changes the
 *   row, the status or the body, and a read error, throw or hang is ignored.
 *
 * No module-scope code: importing this file reads no env and does no I/O, so the
 * writers' OFF branch is unaffected by the import.
 */

export const PAYMENT_ALERT_SOURCE = "payment_record_failed";
export const STACKING_MISMATCH_SOURCE = "stacking_switch_mismatch";
const DEDUP_WINDOW_HOURS = 24;
const ROUND_TRIP_TIMEOUT_MS = 3000;

// deno-lint-ignore no-explicit-any
export type AlertDb = { from: (table: string) => any };

export type AlertOptions = {
  /** Bound for EACH round trip (dedup read, insert). Default 3000 ms. */
  timeoutMs?: number;
};

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
async function bounded<T>(op: PromiseLike<T>, timeoutMs: number): Promise<T | { timedOut: true }> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<{ timedOut: true }>((resolve) => {
    timer = setTimeout(() => resolve({ timedOut: true }), timeoutMs);
  });
  try {
    return await Promise.race([Promise.resolve(op), timeout]);
  } finally {
    clearTimeout(timer);
  }
}

type AlertRow = {
  source: string;
  paymentId: string;
  summary: string;
  context: Record<string, unknown>;
  suggestedAction: string;
};

/**
 * Dedup (this SOURCE, this payment id, unresolved, last 24 h), then insert. The
 * first row is `critical` (it pages), later ones `warn`; a failed dedup read
 * pages anyway. Never throws.
 */
async function insertDedupedAlert(client: AlertDb, a: AlertRow, timeoutMs: number): Promise<void> {
  try {
    const since = new Date(Date.now() - DEDUP_WINDOW_HOURS * 3600 * 1000).toISOString();
    const recent = await bounded(
      client
        .from("alerts")
        .select("id")
        .eq("source", a.source)
        .eq("context_json->>payment_id", a.paymentId)
        .is("resolved_at", null)
        .gte("detected_at", since)
        .limit(1),
      timeoutMs,
    );
    const r = recent as { data?: unknown[] | null; error?: unknown; timedOut?: true };
    const dedupFailed = r.timedOut === true || !!r.error || !Array.isArray(r.data);
    if (dedupFailed) {
      console.error(`[payment_alert] dedup read failed for payment_id=${a.paymentId}; paging anyway`);
    }
    const severity = !dedupFailed && (r.data as unknown[]).length > 0 ? "warn" : "critical";

    const inserted = await bounded(
      client.from("alerts").insert({
        source: a.source,
        severity,
        summary: a.summary,
        context_json: a.context,
        suggested_action: a.suggestedAction,
      }),
      timeoutMs,
    );
    const ins = inserted as { error?: unknown; timedOut?: true };
    if (ins.timedOut === true || ins.error) {
      console.error(`[payment_alert] alerts insert failed for payment_id=${a.paymentId}`);
    }
  } catch (e) {
    console.error(
      `[payment_alert] threw for payment_id=${a.paymentId}: ${(e as { name?: string })?.name ?? "error"}`,
    );
  }
}

export async function reportPaymentRecordFailure(
  client: AlertDb,
  f: PaymentRecordFailure,
  opts: AlertOptions = {},
): Promise<void> {
  await insertDedupedAlert(client, {
    source: PAYMENT_ALERT_SOURCE,
    paymentId: f.paymentId,
    summary: `${f.fn}: paid payment not recorded (code ${f.code})`,
    context: {
      fn: f.fn,
      request_id: f.requestId,
      payment_id: f.paymentId,
      user_id: f.userId,
      plan: f.plan,
      amount_paise: f.amountPaise,
      code: f.code,
    },
    suggestedAction:
      "Razorpay captured this payment but no subscriptions row was written. Check whether a later retry recorded it " +
      "(select * from subscriptions where razorpay_payment_id = the payment_id); if not, grep the function logs for " +
      "this payment_id ('stacking read failed' for an rpc code; 'does not match any plan' or 'cross-check failed' for " +
      "amount_no_match / amount_cross_check, where the promo code was usually edited or deleted mid-checkout) and " +
      "record the row by hand (docs/architecture/payment.md rule 9).",
  }, opts.timeoutMs ?? ROUND_TRIP_TIMEOUT_MS);
}

export type StackingMismatch = {
  fn: "verify-payment" | "razorpay-webhook";
  paymentId: string;
  userId: string;
  plan: string;
  /** The paid row the OFF branch just wrote. */
  rowEnd: string;
  /** The active referral trial it overlaps. */
  trialEnd: string;
};

export async function reportStackingMismatch(
  client: AlertDb,
  m: StackingMismatch,
  opts: AlertOptions = {},
): Promise<void> {
  await insertDedupedAlert(client, {
    source: STACKING_MISMATCH_SOURCE,
    paymentId: m.paymentId,
    summary: `${m.fn}: paid row recorded without stacking over an active trial (row ends ${m.rowEnd}, trial ends ${m.trialEnd})`,
    context: {
      fn: m.fn,
      payment_id: m.paymentId,
      user_id: m.userId,
      plan: m.plan,
      row_end: m.rowEnd,
      trial_end: m.trialEnd,
    },
    suggestedAction:
      "The paid subscriptions row WAS written, but by a writer that read ENABLE_SUBSCRIPTION_STACKING as off, so its " +
      "days overlap the user's active referral trial instead of following it (a door-ON order recorded by a stale " +
      "isolate, a referral code redeemed mid-checkout, or a referrer's own credit landing mid-checkout). Consider " +
      "moving that row's end_date to the trial end plus " +
      "the plan days (30 monthly, 365 yearly), and check the switch on both writers (docs/architecture/payment.md rule 9).",
  }, opts.timeoutMs ?? ROUND_TRIP_TIMEOUT_MS);
}

export type MismatchCheck = {
  fn: "verify-payment" | "razorpay-webhook";
  paymentId: string;
  userId: string;
  plan: string;
  /** The new row's start_date (ISO). A trial still active after it overlaps the new row. */
  rowStart: string;
  rowEnd: string;
};

/** Bound of the mismatch read and of each alert round trip it may add. */
export const MISMATCH_TIMEOUT_MS = 1000;

/**
 * The OFF-branch alarm (plan 2.5). Call it only after the OFF branch itself
 * inserted the row (never on the skip paths, the 23505 race arms or the ON path),
 * and after the promo redemption. ONE try/catch: a read error, a thrown client or
 * a hang (bounded at 1 s) is logged and ignored; the caller's response never
 * changes.
 */
// Worst case added to a success response: about 3 s (the read up to 1 s, then the
// dedup read and the insert up to 1 s each on a hit).
export async function checkStackingMismatch(client: AlertDb, c: MismatchCheck): Promise<void> {
  try {
    const read = await bounded(
      client
        .from("subscriptions")
        .select("id, end_date")
        .eq("user_id", c.userId)
        .eq("status", "active")
        .eq("plan", "referral_trial")
        .gt("end_date", c.rowStart)
        .limit(1),
      MISMATCH_TIMEOUT_MS,
    );
    const r = read as { data?: Array<{ end_date?: unknown }> | null; error?: unknown; timedOut?: true };
    if (r.timedOut === true || r.error || !Array.isArray(r.data)) {
      console.error(`[${c.fn}] stacking mismatch check unavailable payment_id=${c.paymentId}`);
      return;
    }
    if (r.data.length === 0) return;
    const trialEnd = String(r.data[0].end_date ?? "");
    console.error(`[${c.fn}] stacking_switch_mismatch payment_id=${c.paymentId} user_id=${c.userId}`);
    await reportStackingMismatch(client, {
      fn: c.fn,
      paymentId: c.paymentId,
      userId: c.userId,
      plan: c.plan,
      rowEnd: c.rowEnd,
      trialEnd,
    }, { timeoutMs: MISMATCH_TIMEOUT_MS });
  } catch (e) {
    console.error(
      `[${c.fn}] stacking mismatch check threw payment_id=${c.paymentId}: ${(e as { name?: string })?.name ?? "error"}`,
    );
  }
}
