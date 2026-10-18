/**
 * subscription_stacking - PRO time stacks AFTER the current PRO end (OI-341,
 * Piece A: the server-side WRITER half; plan docs/plans/oi341-purchase-in-trial.md).
 *
 * `verify-payment` and `razorpay-webhook` insert the paid `subscriptions` row
 * with `start_date = now` and an `end_date` they compute. Today that is
 * `now + plan length`. With stacking enabled it is
 * `max(now, latest active end) + plan length`, so a payment made while the user
 * still has PRO (a referral trial) is added after the current end instead of
 * running alongside it. `start_date` stays the payment time on purpose: the
 * referral reward job (migration 159) reads it as the payment time, and PRO is
 * read from `status` and `end_date` only.
 *
 * DARK BY DEFAULT (CLAUDE.md 4.6 / 4.12.4): the enabling secret
 * `ENABLE_SUBSCRIPTION_STACKING` must be exactly the string "true"; otherwise
 * `resolveEndDate` returns exactly `now + days` and issues NO query. While
 * `create-razorpay-order` keeps its 409 guard, a payment can only be created by
 * a user with no active row, so even an enabled switch computes today's value.
 *
 * Catastrophic tier (a payment-path module): see docs/blast_radius.yaml.
 */

/** The enabling secret. Strictly the string "true"; read per call, never at load. */
export const STACKING_ENABLE_ENV = "ENABLE_SUBSCRIPTION_STACKING";

/** A Razorpay payment id as it is interpolated into a PostgREST logic tree. */
const PAYMENT_ID_RE = /^pay_[A-Za-z0-9]{1,64}$/;

export function isValidPaymentId(id: unknown): id is string {
  return typeof id === "string" && PAYMENT_ID_RE.test(id);
}

/** Minimal structural view of the supabase-js client this module uses. */
// deno-lint-ignore no-explicit-any
export type StackingDb = { from: (table: string) => any };

export type EnvReader = (name: string) => string | undefined;

const defaultEnv: EnvReader = (name) => Deno.env.get(name);

/**
 * `base + days` where `base = max(now, latestActiveEnd ?? now)`, using the SAME
 * `setDate(getDate() + days)` the writers used inline (so with no active row the
 * result is byte-identical to the old `now + days`).
 */
export function stackedEndDate(
  latestActiveEnd: Date | null,
  now: Date,
  days: number,
): Date {
  const base =
    latestActiveEnd !== null && latestActiveEnd.getTime() > now.getTime()
      ? latestActiveEnd
      : now;
  const end = new Date(base);
  end.setDate(end.getDate() + days);
  return end;
}

export type LatestEndResult =
  | { ok: true; end: Date | null }
  | { ok: false; code: string };

/**
 * The caller's latest ACTIVE, UNEXPIRED paid-or-trial end, excluding the row of
 * the payment being recorded (the sibling writer can have inserted it already).
 * Read as an ARRAY with `limit(1)`, never `.maybeSingle()` (a user can hold
 * several active rows, bug f2b9d4). Returns `ok:false` on a database error, on
 * an unparseable `end_date` and on a payment id that fails the format check.
 */
export async function readLatestActiveEnd(
  db: StackingDb,
  userId: string,
  paymentId: string,
  nowIso: string,
): Promise<LatestEndResult> {
  if (!isValidPaymentId(paymentId)) return { ok: false, code: "bad_payment_id" };
  const { data, error } = await db
    .from("subscriptions")
    .select("end_date")
    .eq("user_id", userId)
    .eq("status", "active")
    .gt("end_date", nowIso)
    // `.neq` alone would drop NULL-payment-id rows (trial and admin grants)
    // under SQL NULL semantics, so the `is.null` arm is required.
    .or(`razorpay_payment_id.is.null,razorpay_payment_id.neq.${paymentId}`)
    .order("end_date", { ascending: false })
    .limit(1);
  if (error) {
    // `||`, not `??`: postgrest-js reports a transport failure with code "".
    const code = (error as { code?: string }).code || "read_error";
    return { ok: false, code: String(code) };
  }
  const rows = Array.isArray(data) ? data : [];
  if (rows.length === 0) return { ok: true, end: null };
  const raw = (rows[0] as { end_date?: unknown }).end_date;
  const parsed = typeof raw === "string" ? new Date(raw) : null;
  if (parsed === null || Number.isNaN(parsed.getTime())) {
    return { ok: false, code: "bad_end_date" };
  }
  return { ok: true, end: parsed };
}

export type ResolveResult =
  | { ok: true; endDate: Date }
  | { ok: false; code: string };

/**
 * The ONE function the writers call. Switch OFF (the default): exactly
 * `now + days`, no query, no new failure mode. Switch ON: stacked on the latest
 * active end; a read error (including a thrown rejection) is `ok:false`, never a
 * silent fallback (a fallback would under-deliver paid time).
 */
export async function resolveEndDate(
  db: StackingDb,
  userId: string,
  paymentId: string,
  now: Date,
  days: number,
  env: EnvReader = defaultEnv,
): Promise<ResolveResult> {
  if (env(STACKING_ENABLE_ENV) !== "true") {
    return { ok: true, endDate: stackedEndDate(null, now, days) };
  }
  try {
    const latest = await readLatestActiveEnd(
      db,
      userId,
      paymentId,
      now.toISOString(),
    );
    if (!latest.ok) return { ok: false, code: latest.code };
    const end = stackedEndDate(latest.end, now, days);
    // A base near the Date limit makes the sum an Invalid Date; toISOString() would then throw in the writer.
    if (Number.isNaN(end.getTime())) return { ok: false, code: "bad_end_date" };
    return { ok: true, endDate: end };
  } catch (e) {
    return { ok: false, code: (e as { name?: string })?.name ?? "thrown" };
  }
}
