// _shared/promo_rules.ts — the ONE rule for "can this promo code be used now?" (OI-366, payment-hardening U3).
//
// Read STRICTLY where a code is accepted for a new purchase: validate-promo (what the paywall shows) and
// create-razorpay-order (the price of the order). The payment writers (verify-payment, razorpay-webhook) keep
// their TOLERANT read on purpose: a payment already made at the discounted price must still be recordable if
// the code expires or runs out between the order and the capture (docs/architecture/payment.md rule 2).
//
// Order of the checks matches validate-promo's answers: inactive, then expired, then exhausted.
// `valid_until` is a `date` column: the code is usable THROUGH that IST calendar day.

import { istDateStr } from "./ist_date.ts";

export type PromoUsability = "ok" | "inactive" | "expired" | "exhausted";

export type PromoRow = {
  is_active?: unknown;
  valid_until?: unknown;
  max_uses?: unknown;
  used_count?: unknown;
};

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export function promoUsableAt(promo: PromoRow, now: Date = new Date()): PromoUsability {
  // The column is nullable with a default: only an explicit true is active.
  if (promo.is_active !== true) return "inactive";
  // Live rows are "YYYY-MM-DD"; a timestamp form is cut to its date. Anything that is not a plain date
  // ("infinity", "", null, garbage) is EXPIRED: a bare string compare would sort letters after digits and
  // keep such a code alive for ever (fail open).
  const until = promo.valid_until == null ? "" : String(promo.valid_until).slice(0, 10);
  if (!DATE_RE.test(until)) return "expired";
  if (istDateStr(now) > until) return "expired";
  // Loose `!= null`: a missing max_uses is unlimited, never NaN.
  if (promo.max_uses != null && Number(promo.used_count ?? 0) >= Number(promo.max_uses)) return "exhausted";
  return "ok";
}
