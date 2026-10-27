// _shared/order_abuse_guards.ts — the kill switch and the wait wording of the order and promo-check limits
// (payment-hardening U3, OI-366). Read by create-razorpay-order, validate-promo and the founder digest (which
// marks both quota keys UNMETERED while the switch is on).
//
// Pure: no imports, no I/O. Tests: order_abuse_guards_test.ts.

/** Exactly "true" turns OFF, together, both hourly limits and the strict promo rule at order time. */
export const ORDER_ABUSE_GUARDS_DISABLE_ENV = "DISABLE_ORDER_ABUSE_GUARDS";

/** The wait in whole minutes for a fixed-bucket limit's refusal ("1 minute", "37 minutes"), never "0". */
export function retryMinutes(retryAfterSeconds: number): string {
  const m = Math.max(1, Math.ceil(retryAfterSeconds / 60));
  return m === 1 ? "1 minute" : `${m} minutes`;
}

/** Whole seconds left in the fixed bucket that started at [bucketStartMs] (at least 1). */
export function secondsLeftInBucket(bucketStartMs: number, windowMs: number, nowMs: number = Date.now()): number {
  return Math.max(1, Math.ceil((bucketStartMs + windowMs - nowMs) / 1000));
}
