/**
 * notification_prefs.ts — the single server-side reader of a user's
 * notification preferences (Unit E).
 *
 * ⚠ SOURCE OF TRUTH MOVED (OI-98 / e4a1b7, 2026-08-26)
 * ----------------------------------------------------
 * The primary source is now `user_preferences.notification_preferences` — one
 * row per user, written by partial-column upsert. Everything below about
 * snapshots describes the FALLBACK, which is read only for users the column
 * does not answer for, and which exists solely so client and server deploys do
 * not have to be ordered. It is retired once APK +39 adoption makes it dead
 * weight.
 *
 * WHY IT MOVED. `snapshot_json` is a DERIVED document: rebuilt wholesale from
 * Hive on every write and REPLACED, not merged, on upsert. That is correct for
 * regenerable data and wrong for user intent, which is the only copy in
 * existence. Two failures followed, both measured live on 2026-08-26:
 *   1. A reinstalled device — its Hive box empty, which is indistinguishable
 *      from "everything enabled" — pushed an all-enabled default that REPLACED
 *      the server's stored copy. The choice was destroyed, not merely unread.
 *   2. FOUR Edge Functions write that row (`daily-snapshot`, `rolling-context`,
 *      `future-prediction`, `beat-my-coach`) and the last three create a
 *      preference-less row when the day has none. Since every reader takes the
 *      newest row with no fall-through, 3 of the 5 users who had ever stored a
 *      preference were being ignored outright.
 * A column has one writer per concept, survives its siblings' upserts, and has
 * no "newest row" to lose — so neither failure is representable.
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
 *
 * WHY PAGED (OI-79)
 * -----------------
 * The batched read used to be a bare `.in(userIds)`, which PostgREST caps at
 * `db-max-rows` (1000) — returning HTTP 200 with `error === null`, so a clipped
 * result is indistinguishable from a complete one. `user_daily_snapshots` holds
 * MANY rows per user (97 rows across 17 users live, ~5.7 each), so the cap bites
 * at roughly 175 users, not 1000.
 *
 * That interacts badly with everything above. Rows arrive `snapshot_date DESC`
 * and the first row per user wins, so truncation removes the TAIL — precisely
 * the users whose newest snapshot is oldest. Under the ABSENT ⇒ SEND rule those
 * users' preferences then read as absent, and **every toggle they set is
 * silently ignored**. That is the same "toggles look implemented but do nothing"
 * failure this file's own header was written to prevent, reached by a different
 * route.
 *
 * `fetchAllByIds` fixes it and preserves the semantics: chunking is BY user id,
 * so all of one user's rows stay in a single chunk, and the compound sort key
 * (`snapshot_date DESC`, then `id`) keeps the global order stable across pages —
 * so "first row per user wins = most recent" still holds. `id` is the tiebreaker
 * because `snapshot_date` is not unique and a non-unique page key can shuffle
 * ties between requests.
 */

import { fetchAllByIds } from "./paged_fetch.ts";

// deno-lint-ignore no-explicit-any
type SupabaseLike = any;

/** Per-user preference maps, keyed by user_id. */
export type PrefsByUser = Map<string, Record<string, unknown>>;

/**
 * [fetchNotificationPrefs]'s result, plus whether the lookup could actually be
 * PERFORMED.
 *
 * WHY THIS EXISTS — "absent" and "could not ask" are different facts.
 * `PrefsByUser` alone cannot tell them apart: a user missing from the map means
 * either "this user has set no preferences" (a real answer, and ABSENT => SEND
 * correctly applies) or "every query failed" (no answer at all). Collapsing the
 * two is fine for the six callers that want N2's fail-safe unconditionally, and
 * NOT fine for `workout-window-closing`, which deliberately skips a user it
 * cannot verify rather than risk a nudge they switched off.
 *
 * `degraded` is true only when a source THREW. A source that returns zero rows
 * is an answer, not a failure.
 */
export interface PrefsLookup {
  prefs: PrefsByUser;
  degraded: boolean;
}

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
  return (await fetchNotificationPrefsDetailed(client, userIds)).prefs;
}

/**
 * As [fetchNotificationPrefs], but also reports whether the lookup could be
 * performed at all — see [PrefsLookup].
 *
 * Callers that want N2's unconditional fail-safe should keep using
 * [fetchNotificationPrefs]; this variant is for a caller whose correct
 * behaviour on "could not ask" differs from its behaviour on "no preferences
 * set".
 */
export async function fetchNotificationPrefsDetailed(
  client: SupabaseLike,
  userIds: string[],
): Promise<PrefsLookup> {
  const out: PrefsByUser = new Map();
  let degraded = false;
  // An empty input is a complete answer to a question about nobody, not a
  // failure — degraded stays false.
  if (!userIds || userIds.length === 0) return { prefs: out, degraded };

  // ── PRIMARY: user_preferences.notification_preferences (OI-98 / e4a1b7) ──
  //
  // The preferences used to live inside `user_daily_snapshots.snapshot_json`,
  // which is a DERIVED document: replaced wholesale on every write, by four
  // different writers, with the readers below taking only the NEWEST row and
  // never falling through. Three of five users with a stored preference were
  // being ignored because a cron had created that day's row before their
  // device wrote one. `user_preferences` is one row per user, written by
  // partial-column upsert, so none of that applies.
  //
  // STILL PAGED. "One row per user" does not make `.in()` safe — a bare `.in()`
  // is clipped at PostgREST's db-max-rows with HTTP 200 and `error === null`,
  // which is the OI-79 failure this file's header documents. One row per user
  // moves the cliff from ~175 users to 1000; it does not remove it, and
  // truncation still fails toward SEND. `user_id` is the sort key and is unique
  // here (it is the upsert's conflict target), which is what `orderBy` requires.
  const resolved = new Set<string>();
  try {
    const rows = await fetchAllByIds<Record<string, unknown>>(
      (chunk) =>
        client
          .from("user_preferences")
          .select("user_id, notification_preferences")
          .in("user_id", chunk),
      userIds,
      { orderBy: "user_id", label: "notification_prefs_column" },
    );

    for (const row of (rows ?? []) as Record<string, unknown>[]) {
      const uid = row.user_id as string | undefined;
      if (!uid) continue;
      const prefs = row.notification_preferences;
      // NULL means "no record for this user" and must fall through to the
      // snapshot during the cutover. A non-null value — including `{}` — is a
      // real record and is authoritative, so it does NOT fall through.
      if (prefs === null || prefs === undefined) continue;
      resolved.add(uid);
      out.set(
        uid,
        typeof prefs === "object" && !Array.isArray(prefs)
          ? prefs as Record<string, unknown>
          : {},
      );
    }
  } catch (err) {
    // Same contract as the snapshot path below: never throw, degrade to the
    // fallback (and ultimately to SEND). A column read that fails must not
    // abort a whole cron run.
    console.error("[notification_prefs] column read failed, falling back:", err);
    degraded = true;
  }

  // ── FALLBACK: the legacy snapshot key ──
  //
  // Read ONLY for users the column did not answer for. This is what removes the
  // deploy-ordering constraint between client and server: a device that has not
  // yet synced the new column keeps being honoured exactly as before. It is
  // retired once +39 adoption makes it dead weight — tracked on the OI board
  // with that trigger, not left to be noticed.
  const unresolved = userIds.filter((id) => !resolved.has(id));
  if (unresolved.length === 0) return { prefs: out, degraded };

  try {
    const data = await fetchAllByIds<Record<string, unknown>>(
      (chunk) =>
        client
          .from("user_daily_snapshots")
          .select("user_id, snapshot_json")
          .in("user_id", chunk),
      unresolved,
      {
        // snapshot_date DESC preserves "first row per user wins = most recent";
        // `id` is the unique tiebreaker that makes the paging stable (OI-79).
        orderBy: [
          { column: "snapshot_date", ascending: false },
          { column: "id", ascending: true },
        ],
        label: "notification_prefs",
      },
    );

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
    return { prefs: out, degraded };
  } catch (err) {
    // Catches BOTH a transport-level rejection (DNS, reset, timeout before any
    // HTTP response) AND a query error, which `fetchAllByIds` now raises rather
    // than returning as `{ error }`. Either way this degrades to "send to
    // everyone" instead of aborting the whole cron run — the N2 fail-safe
    // direction, and the reason this function's contract is "never throws".
    // Same reasoning as _shared/subscription.ts.
    console.error("[notification_prefs] failed, defaulting to SEND:", err);
    return { prefs: out, degraded: true };
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
