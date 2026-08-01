/**
 * subscription.ts — the single definition of "is this user PRO".
 *
 * Added 2026-07-26 (diagnose <id>). Before this, every Edge Function that
 * needed PRO status hand-rolled the predicate. Five distinct variants existed
 * across the codebase, and one of them was wrong in a way that cost money.
 *
 * THE PREDICATE
 * -------------
 *   subscriptions.status = 'active'  AND  end_date > now()
 *
 * BOTH terms are required. `status` is NEVER reconciled to 'expired' by any
 * job, cron or trigger — so rows sit at `status='active'` with an end_date
 * months in the past, indefinitely. A status-only check treats every one of
 * them as PRO.
 *
 * This is not hypothetical. At the time of writing, live production held 5
 * `status='active'` rows and **zero** of them were unexpired; the newest had
 * expired 13 days earlier. A status-only check would have reported 4 PRO
 * users where the correct answer is 0.
 *
 * WHY NOT `users.subscription_status`
 * -----------------------------------
 * That denormalized column is worse than the status-only shape: it carries no
 * expiry term at all, and **nothing writes it back to 'free'**. Three code
 * paths set it to 'pro' (the `update_user_subscription_status` trigger,
 * razorpay-webhook, verify-payment); none unset it. Live it claimed 6 PRO
 * users, all 6 lapsed. `morning-alert` read it and sent Gemini-generated
 * PRO-tier copy to churned users — paid tokens spent on people who had
 * stopped paying, and the churn signal destroyed. That is the bug this file
 * exists to make unrepeatable.
 *
 * Migration 093 calls that column "the canonical PRO gate" while
 * ai-proxy/index.ts calls the `subscriptions` predicate canonical. Two
 * canonical answers that disagree by 6 users. THIS FILE is the tiebreak: the
 * `subscriptions` table is the source of truth; the column is a stale cache.
 */

import { fetchAllPages } from "./paged_fetch.ts";

// deno-lint-ignore no-explicit-any
type SupabaseLike = any;

/// Sanity ceiling on the batch fetch — see the canary in fetchProUserIds.
/// NOT a query limit: the read is paged (OI-79), so this is a "that number
/// looks wrong" tripwire rather than a cap that silently discards rows.
const _proFetchCap = 5000;

/**
 * The set of user_ids that are PRO right now.
 *
 * Use this when you have a batch of users to classify — one query for the
 * whole run, then O(1) membership checks. Do NOT call `isProUser` in a loop.
 *
 * Returns an EMPTY SET on query error, never throws. Callers must treat that
 * as "nobody is PRO" — the fail-safe direction, since the alternative is
 * sending paid-tier content to unknown users.
 */
export async function fetchProUserIds(
  client: SupabaseLike,
): Promise<Set<string>> {
  try {
    // OI-79 — the `.limit(_proFetchCap)` (5000) this replaces was UNREACHABLE:
    // PostgREST caps every response at db-max-rows (1000), so the read silently
    // stopped at 1000 active PRO users and every one past that was treated as
    // free. Worse, the `rows.length >= _proFetchCap` guard below could never
    // fire — a saturation detector that is structurally always false is more
    // dangerous than none, because it reads as "we would have been told".
    // Paged, so `_proFetchCap` is now a real ceiling the loop can actually reach.
    const data = await fetchAllPages<{ user_id: string }>(
      () =>
        client
          .from("subscriptions")
          .select("user_id")
          .eq("status", "active")
          .gt("end_date", new Date().toISOString()),
      { orderBy: "id", pageSize: 1000, label: "subscription pro-user-ids" },
    );

    const rows = data ?? [];
    // Canary — now genuinely reachable. Before OI-79 this compared against a
    // 5000 cap on a read PostgREST clipped at 1000, so it could never fire
    // however many PRO users existed: the very truncation it was written to
    // announce would silently happen 4000 rows below the threshold. Paging
    // removes the 1000 ceiling, so exceeding _proFetchCap is once again a real
    // condition worth shouting about (an unexpectedly huge PRO base, or a
    // filter that stopped filtering).
    if (rows.length >= _proFetchCap) {
      console.warn(
        `[subscription] fetchProUserIds returned ${rows.length} rows, at or ` +
          `above the ${_proFetchCap} sanity ceiling — check the status/end_date ` +
          `filter before trusting this PRO set.`,
      );
    }
    return new Set<string>(rows.map((r: { user_id: string }) => r.user_id));
  } catch (err) {
    // The `{ data, error }` shape catches API-level failures, but a
    // transport-level fetch rejection (DNS, reset, timeout before any HTTP
    // response) may reject the promise instead. Without this catch that would
    // propagate into morning-alert's single outer try and abort the whole
    // nightly run for every user — not just skip the PRO/free split. Cheap to
    // rule out, and it makes the "never throws" contract above literally true.
    console.error("[subscription] fetchProUserIds threw:", err);
    return new Set<string>();
  }
}

/**
 * True when this one user is PRO right now.
 *
 * For a single user only — in a loop use `fetchProUserIds` instead.
 * Returns false on error, never throws (fail-safe, as above).
 */
export async function isProUser(
  client: SupabaseLike,
  userId: string,
): Promise<boolean> {
  try {
    const { data, error } = await client
      .from("subscriptions")
      .select("user_id")
      .eq("user_id", userId)
      .eq("status", "active")
      .gt("end_date", new Date().toISOString())
      .limit(1);

    if (error) {
      console.error("[subscription] isProUser failed:", error.message);
      return false;
    }
    return (data ?? []).length > 0;
  } catch (err) {
    // Same transport-rejection reasoning as fetchProUserIds above.
    console.error("[subscription] isProUser threw:", err);
    return false;
  }
}
