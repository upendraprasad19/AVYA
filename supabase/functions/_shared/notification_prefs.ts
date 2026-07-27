/**
 * notification_prefs.ts — the single server-side reader of a user's
 * notification preferences (Unit E).
 *
 * THE RULE: ABSENT ⇒ SEND (decision N2)
 * ------------------------------------
 * A missing key, a missing snapshot, a failed query, a malformed value — every
 * one of them means SEND. Only a literal `enabled === false` silences a push.
 * Nobody loses a notification to a sync gap or a transient database error; the
 * cost of the opposite default is a user who turned something off and can never
 * work out why it still arrives.
 *
 * WHY latest-desc AND NOT today-pinned
 * ------------------------------------
 * The obvious implementation pins `snapshot_date` to today. It is inert.
 * Measured against live data: 91 snapshot rows across 17 users, exactly **1**
 * row for today, only 3 users fresh within three days, and the stalest user's
 * newest row was two months old. A today-pinned read would therefore find
 * nothing for 16 of 17 users and fall through to SEND — i.e. the toggles would
 * still do nothing, while looking implemented.
 *
 * It is worse than merely ineffective for `re-engagement`, whose targets are BY
 * DEFINITION people who have not opened the app recently. Their snapshot can
 * never be today's. A today-pinned guard there is not "usually inert", it is
 * guaranteed inert.
 *
 * So: order by snapshot_date DESC and keep the FIRST row per user — the user's
 * most recent known preferences, however old. Shape copied from
 * `weekly-recap-ready/index.ts:163-185`, which already had it right.
 *
 * WHY BATCHED
 * -----------
 * One query per run, not one per user. `re-engagement` already runs a
 * multi-query loop per candidate; adding a per-user `.single()` there would
 * multiply the round-trips on the function with the largest candidate set.
 */

// deno-lint-ignore no-explicit-any
type SupabaseLike = any;

/** Per-user preference maps, keyed by user_id. */
export type PrefsByUser = Map<string, Record<string, unknown>>;

/**
 * Most-recent notification preferences for each of [userIds].
 *
 * Returns an EMPTY map on any failure — callers then send to everyone, which is
 * the fail-safe direction (N2). Never throws: an exception escaping here would
 * abort a whole cron run for a preferences lookup.
 */
export async function fetchNotificationPrefs(
  client: SupabaseLike,
  userIds: string[],
): Promise<PrefsByUser> {
  const out: PrefsByUser = new Map();
  if (!userIds || userIds.length === 0) return out;

  try {
    const { data, error } = await client
      .from("user_daily_snapshots")
      .select("user_id, snapshot_json")
      .in("user_id", userIds)
      .order("snapshot_date", { ascending: false });

    if (error) {
      console.error(
        "[notification_prefs] fetch failed, defaulting to SEND:",
        error.message,
      );
      return out;
    }

    for (const row of (data ?? []) as Record<string, unknown>[]) {
      const uid = row.user_id as string | undefined;
      if (!uid || out.has(uid)) continue; // first row wins = most recent
      const snap = (row.snapshot_json ?? {}) as Record<string, unknown>;
      const prefs = snap.notification_preferences;
      out.set(
        uid,
        prefs && typeof prefs === "object" && !Array.isArray(prefs)
          ? prefs as Record<string, unknown>
          : {},
      );
    }
    return out;
  } catch (err) {
    // Transport-level rejection (DNS, reset, timeout before any HTTP
    // response) rejects the promise rather than returning { error }. Same
    // reasoning as _shared/subscription.ts — without this, one network blip
    // aborts the entire cron run instead of degrading to "send to everyone".
    console.error("[notification_prefs] threw, defaulting to SEND:", err);
    return out;
  }
}

/**
 * True when [key] should be SENT to [userId].
 *
 * Only an explicit `enabled === false` returns false. Absent user, absent key,
 * non-object entry, non-boolean `enabled` — all send.
 */
export function isNotificationEnabled(
  prefs: PrefsByUser,
  userId: string,
  key: string,
): boolean {
  const userPrefs = prefs.get(userId);
  if (!userPrefs) return true;

  const entry = userPrefs[key];
  if (!entry || typeof entry !== "object" || Array.isArray(entry)) return true;

  return (entry as Record<string, unknown>).enabled !== false;
}
