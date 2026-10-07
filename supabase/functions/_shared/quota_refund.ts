// supabase/functions/_shared/quota_refund.ts
/**
 * Part B (gemini3-limits-caching): give a quota unit back when a turn failed for
 * a reason the user did not cause. Pure helpers so ai-proxy (which calls
 * `serve()` at module scope and cannot be imported by a test) stays thin.
 *
 * Two halves, deliberately split:
 *   - WHETHER a failure is refundable: `refundableFailure` (gemini.ts), applied
 *     to the Gemini failure shape here (`refundableGeminiChatFailure`).
 *   - HOW: the `refund_quota` RPC (migration 153). It latches the reservation row
 *     out of `pending`, spends the 3/day refund budget and decrements the ledger,
 *     all server-side. A call here that finds the row already terminal, the
 *     budget spent or the ledger at 0 is a no-op (returns -1), never an error.
 *
 * ORDER MATTERS: call `refundReservation` BEFORE the caller's own
 * `UPDATE ... SET model_used = <label>`. The RPC's latch matches
 * `model_used = 'pending'`; once the caller has stamped the row, the refund is
 * gone. The RPC stamps the same label itself, so the caller's later UPDATE only
 * has to add the response text.
 */
import { refundableFailure } from "./gemini.ts";

/** Minimal supabase-js surface this helper needs (a test fake satisfies it). */
export interface RefundRpcClient {
  rpc(
    fn: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: { message?: string } | null }>;
}

/**
 * Refundable-or-not for a `geminiChat` failure (`content === null`).
 * `lastError` absent means no evidence of what happened, so no refund.
 */
export function refundableGeminiChatFailure(
  r: {
    lastError?: { status: number | null; message: string } | null;
    deterministicFailure?: boolean;
    blockSeen?: boolean;
  },
): boolean {
  if (!r.lastError) return false;
  return refundableFailure({
    status: r.lastError.status,
    message: r.lastError.message,
    deterministicFailure: r.deterministicFailure ?? false,
    blockSeen: r.blockSeen ?? false,
  });
}

/**
 * Call `refund_quota` for a reservation. NEVER throws and never blocks the
 * caller's failure response: a missing RPC (migration not applied, or rolled
 * back) or a transient DB error just means no refund. Returns the new `used`
 * count, or -1 when nothing was refunded.
 */
export async function refundReservation(
  sb: RefundRpcClient,
  reservationId: string | undefined,
  label: string,
  tag: string,
): Promise<number> {
  if (!reservationId) return -1;
  try {
    // oi79-ok: refund_quota returns ONE integer (the new `used`, or -1): a scalar, never a row set.
    const { data, error } = await sb.rpc("refund_quota", {
      p_reservation_id: reservationId,
      p_label: label,
    });
    if (error) {
      console.error(
        `[ai-proxy.${tag}] refund_quota failed id=${reservationId}:`,
        error.message ?? error,
      );
      return -1;
    }
    return typeof data === "number" ? data : -1;
  } catch (e) {
    console.error(`[ai-proxy.${tag}] refund_quota threw id=${reservationId}:`, e);
    return -1;
  }
}
