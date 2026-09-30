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
 * WHY THERE IS NO `users.subscription_status` / `users.subscription_expires_at`
 * -----------------------------------------------------------------------------
 * Those two denormalized mirror columns (and the `update_user_subscription_status`
 * trigger + `extend_subscription` RPC that wrote them) were DROPPED by migration
 * 152 (OI-202). The mirror carried no expiry term and nothing wrote it back to
 * 'free', so it drifted from the truth by construction: live it claimed 6 PRO
 * users, all 6 lapsed, and `morning-alert` read it and sent Gemini-generated
 * PRO-tier copy to churned users -- paid tokens spent on people who had stopped
 * paying, and the churn signal destroyed. Migration 093 had called that column
 * "the canonical PRO gate" while ai-proxy called the `subscriptions` predicate
 * canonical: two canonical answers that disagreed by 6 users.
 *
 * THE `subscriptions` TABLE IS THE ONLY SOURCE. Anything that used to read the
 * mirror for a per-user expiry ("who lapses / expires soon") reads
 * `fetchLatestActiveEndByUser` below instead.
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
    // Pin the cutoff ONCE, outside the per-page closure. `fetchAllPages` calls
    // the closure again for every page, so an inline `new Date()` would re-run
    // per request and each page would be offset into a DIFFERENT result set: a
    // subscription expiring mid-scan shrinks the set, every later row shifts
    // down one, and the row at that boundary is never returned. That silently
    // drops a paying user from a PRO *inclusion* set — the same Class-1
    // "silently wrong" outcome this batch exists to remove, re-entered through
    // the predicate instead of the sort key.
    const cutoffIso = new Date().toISOString();
    const data = await fetchAllPages<{ user_id: string }>(
      () =>
        client
          .from("subscriptions")
          .select("user_id")
          .eq("status", "active")
          .gt("end_date", cutoffIso),
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


/**
 * One `subscriptions` row as `fetchLatestActiveEndByUser` reads it.
 * `end_date` is a timestamptz, returned by PostgREST as an ISO-8601 string.
 */
export interface ActiveSubscriptionEndRow {
  user_id: string;
  end_date: string;
}

/**
 * PURE. Reduces subscription rows to the LATEST `end_date` per user.
 *
 * A user can hold several `status='active'` rows across a renewal (live
 * evidence, 2026-09: 7 active rows for 5 users), so "the user's expiry" is the
 * max over their rows -- NOT the value of an arbitrary one. Compared by parsed
 * instant, not by string, because PostgREST may render the same instant with
 * `+00:00` or `Z` and a lexical compare would then order them wrongly. Rows
 * whose `end_date` does not parse are skipped rather than allowed to poison the
 * comparison (`NaN > x` is always false, which would silently keep the FIRST
 * row seen).
 *
 * Deliberately has no try/catch: every returned value has exactly one source,
 * so a test asserting on it cannot be satisfied by an exception handler.
 */
export function reduceLatestEndByUser(
  rows: readonly ActiveSubscriptionEndRow[],
): Map<string, string> {
  const latest = new Map<string, { iso: string; ms: number }>();
  for (const r of rows) {
    const ms = Date.parse(r.end_date);
    if (Number.isNaN(ms)) continue;
    const cur = latest.get(r.user_id);
    if (cur === undefined || ms > cur.ms) {
      latest.set(r.user_id, { iso: r.end_date, ms });
    }
  }
  const out = new Map<string, string>();
  for (const [uid, v] of latest) out.set(uid, v.iso);
  return out;
}

/**
 * PURE. The users whose LATEST active end_date falls in `[from, to)`, or
 * `[from, to]` when `toInclusive` is set. Returns `[user_id, end_date]` pairs.
 *
 * Because the input is already reduced to the latest end per user, a user who
 * renewed (an old row lapsing in the window AND a newer row ending after it) is
 * correctly NOT reported as lapsing or expiring.
 */
export function usersWithLatestEndIn(
  latestEndByUser: ReadonlyMap<string, string>,
  from: Date,
  to: Date,
  toInclusive = false,
): Array<[string, string]> {
  const fromMs = from.getTime();
  const toMs = to.getTime();
  const out: Array<[string, string]> = [];
  for (const [uid, iso] of latestEndByUser) {
    const ms = Date.parse(iso);
    if (Number.isNaN(ms)) continue;
    if (ms < fromMs) continue;
    if (toInclusive ? ms > toMs : ms >= toMs) continue;
    out.push([uid, iso]);
  }
  return out;
}

/**
 * The latest `status='active'` `end_date` per user, for every user whose latest
 * end is at or after `sinceIso`. `null` on ANY read failure.
 *
 * `sinceIso` is a floor, not a page filter: filtering rows by `end_date >= since`
 * before taking the per-user max is exact for users whose global max is >= since
 * (the max row survives the filter) and simply omits the rest -- which is what a
 * caller asking "who ends after X" wants. It also bounds the scan: a
 * years-old lapsed row is never fetched.
 *
 * NULL, NOT AN EMPTY MAP, ON ERROR -- the opposite of `fetchProUserIds`. There an
 * empty set is the fail-safe direction ("nobody is PRO"); here an empty map
 * would read as "no one is expiring" / "no one lapsed", a confident and wrong
 * number in a founder digest. Callers MUST branch on `null` and surface an
 * unreadable section.
 *
 * Paged (OI-79) with a cutoff pinned by the caller, so every page is cut from
 * the same result set.
 */
export async function fetchLatestActiveEndByUser(
  client: SupabaseLike,
  sinceIso: string,
): Promise<Map<string, string> | null> {
  let rows: ActiveSubscriptionEndRow[];
  try {
    rows = await fetchAllPages<ActiveSubscriptionEndRow>(
      () =>
        client
          .from("subscriptions")
          .select("user_id, end_date")
          .eq("status", "active")
          .gte("end_date", sinceIso),
      {
        orderBy: "id",
        pageSize: 1000,
        label: "subscription latest-active-end-by-user",
        // Bounded like every other digest/bot read (MAX_PAGES = 200 in
        // founder_digest_content.ts): /expiring and /digest run this inside a
        // Telegram webhook, where a slow scan outlasts the timeout and
        // triggers a duplicate update (Hermes L21 2026-09-29).
        maxPages: 200,
      },
    ) ?? [];
  } catch (err) {
    console.error("[subscription] fetchLatestActiveEndByUser threw:", err);
    return null;
  }
  // Sanity tripwire, like fetchProUserIds': there is no upper bound on end_date
  // here, so an unexpectedly large active base (or a filter that stopped
  // filtering) should be loud, not silent (Hermes L23 2026-09-29).
  if (rows.length >= _proFetchCap) {
    console.warn(
      `[subscription] fetchLatestActiveEndByUser returned ${rows.length} rows, ` +
        `at or above the ${_proFetchCap} sanity ceiling — check the filter.`,
    );
  }
  // Reduced OUTSIDE the try: a bug in the reducer must not be mistaken for a
  // read failure and swallowed into `null`.
  return reduceLatestEndByUser(rows);
}
