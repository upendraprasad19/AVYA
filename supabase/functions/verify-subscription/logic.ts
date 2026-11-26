// verify-subscription/logic.ts — OI-519 U4 (plan section 4, "verify-subscription additive fields"), pure.
//
// The PRO predicate itself stays in index.ts, where test/contracts/progress_photos_pro_insert_rule_test.dart pins it
// as whole statements. This file only builds the three additive Play display fields; old clients ignore them. The
// client writes them to `pro_store`, `pro_auto_renews`, `pro_store_expires_at`
// (lib/core/services/subscription_service.dart `playDisplayFields`). They are non-null ONLY for an active Play row:
// every other row has NULL in the three columns (migration 182 adds them nullable), and the client turns all-null
// into a DELETE of its keys.

export type PlayColumns = {
  store?: string | null;
  auto_renew?: boolean | null;
  store_expires_at?: string | null;
};

/** [row] is the ACTIVE row, or null when the response says not PRO. */
export function playDisplayFields(row: PlayColumns | null): {
  store: "play" | null;
  auto_renew: boolean | null;
  store_expires_at: string | null;
} {
  if (!row || row.store !== "play") return { store: null, auto_renew: null, store_expires_at: null };
  return { store: "play", auto_renew: row.auto_renew ?? null, store_expires_at: row.store_expires_at ?? null };
}
