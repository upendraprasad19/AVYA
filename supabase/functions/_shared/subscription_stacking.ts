/**
 * subscription_stacking - PRO time stacks AFTER the current PRO end (OI-341).
 *
 * `verify-payment` and `razorpay-webhook` insert the paid `subscriptions` row.
 * Piece A (docs/plans/oi341-purchase-in-trial.md) put the stacked end date
 * behind the enabling secret below; Piece B1 (docs/plans/oi341-piece-b-door.md)
 * replaced Piece A's ON path (a read, then an insert: two requests, nothing
 * serialising them per user) with ONE call to the Postgres function
 * `public.record_paid_subscription` (migration 161), which takes the per-user
 * lock shared with the referral redeem and job, checks idempotency, computes
 * `max(now, latest active end) + days` and inserts, in one transaction.
 * `start_date` stays the payment time on purpose: the referral reward job
 * (migration 159) reads it as the payment time.
 *
 * DARK BY DEFAULT (CLAUDE.md 4.6 / 4.12.4): unless the enabling secret
 * `ENABLE_SUBSCRIPTION_STACKING` is exactly the string "true", the writers run
 * their OFF branch: today's insert with `plainEndDate(now, days)`, no extra
 * query and no call to the function.
 *
 * Catastrophic tier (a payment-path module): see docs/blast_radius.yaml.
 */

/** The enabling secret. Strictly the string "true"; read per call, never at load. */
export const STACKING_ENABLE_ENV = "ENABLE_SUBSCRIPTION_STACKING";

/** A Razorpay payment id: the only shape either writer accepts. */
const PAYMENT_ID_RE = /^pay_[A-Za-z0-9]{1,64}$/;

export function isValidPaymentId(id: unknown): id is string {
  return typeof id === "string" && PAYMENT_ID_RE.test(id);
}

export type EnvReader = (name: string) => string | undefined;

const defaultEnv: EnvReader = (name) => Deno.env.get(name);

/** The ONE switch rule (shared with the purchase door of Piece B2): exactly "true". */
export function isStackingEnabled(env: EnvReader = defaultEnv): boolean {
  return env(STACKING_ENABLE_ENV) === "true";
}

/**
 * The OFF-branch end date: `now + days` with the SAME `setDate(getDate() + days)`
 * the writers used inline before Piece A, so the OFF output is byte-identical to
 * `origin/main` (pinned by the golden recordings in each writer's tests).
 */
export function plainEndDate(now: Date, days: number): Date {
  const end = new Date(now);
  end.setDate(end.getDate() + days);
  return end;
}

/** Minimal structural view of the supabase-js client the ON path uses. */
// deno-lint-ignore no-explicit-any
export type RecordDb = { rpc: (fn: string, args: Record<string, unknown>) => any };

export type RecordArgs = {
  userId: string;
  plan: string;
  paymentId: string;
  /** A Razorpay entity can omit order_id; undefined is sent as JSON null (an omitted key would make PostgREST miss the 5-arg function). */
  orderId: string | null | undefined;
  signature: string;
};

export type RecordResult =
  | { ok: true; endDate: Date; startDate: Date; inserted: boolean }
  | { ok: false; code: string };

function parseInstant(raw: unknown): Date | null {
  if (typeof raw !== "string") return null;
  const d = new Date(raw);
  return Number.isNaN(d.getTime()) ? null : d;
}

/**
 * The ON path: one call to `public.record_paid_subscription`. Returns `ok:false`
 * on a database error (its SQLSTATE, or `read_error` for a transport failure
 * that postgrest-js reports with an empty code), on a thrown rejection, and on a
 * malformed answer (not a one-row array, or an end/start that does not parse):
 * `bad_rpc_response`, so a missing route or a scalar answer never reads as
 * success.
 */
export async function recordPaidSubscription(
  db: RecordDb,
  args: RecordArgs,
): Promise<RecordResult> {
  try {
    // oi79-ok: the function returns exactly one row by construction (RETURN QUERY once per path); a non-one-row answer is bad_rpc_response below.
    const { data, error } = await db.rpc("record_paid_subscription", {
      p_user_id: args.userId,
      p_plan: args.plan,
      p_payment_id: args.paymentId,
      p_order_id: args.orderId ?? null,
      p_signature: args.signature,
    });
    if (error) {
      // `||`, not `??`: postgrest-js reports a transport failure with code "".
      const code = (error as { code?: string }).code || "read_error";
      return { ok: false, code: String(code) };
    }
    if (!Array.isArray(data) || data.length !== 1) {
      return { ok: false, code: "bad_rpc_response" };
    }
    const row = data[0] as {
      out_end_date?: unknown;
      out_start_date?: unknown;
      out_inserted?: unknown;
    };
    const endDate = parseInstant(row.out_end_date);
    const startDate = parseInstant(row.out_start_date);
    if (endDate === null || startDate === null || typeof row.out_inserted !== "boolean") {
      return { ok: false, code: "bad_rpc_response" };
    }
    return { ok: true, endDate, startDate, inserted: row.out_inserted };
  } catch (e) {
    return { ok: false, code: (e as { name?: string })?.name ?? "thrown" };
  }
}
