/**
 * founder_digest_content.ts — the digest's CONTENT builder + data-gatherer,
 * extracted from founder-digest/index.ts (OI-153, telegram-admin-bot Task 4)
 * so `/digest` (Task 12) can call the exact same code path the daily cron
 * uses to build a digest message, guaranteeing the two can never drift
 * apart. Pure content-building (`buildDigestText`) + the read-only
 * data-gathering (`gatherDigestInput`) that feeds it, over one caller-chosen
 * window. READ-ONLY over the database; decides no quota and writes nothing.
 *
 * The Telegram SEND itself does NOT live here — `sendTelegram` differs in
 * shape per caller (founder-digest's cron sender has an injectable
 * `fetchImpl` for its own secret-hygiene tests; a future `/digest` handler
 * may want its own). This module hands callers a finished message string;
 * what they do with it is theirs.
 *
 * Three states per section, never two (feedback_bad_news_vs_no_news): data ·
 * "none" · an explicit "unreadable" marker. An unreadable section is never
 * rendered as zeros.
 *
 * ⚠ Truncation stays INSIDE `buildDigestText`, not at a caller's send
 * boundary. `_shared/telegram.ts`'s `truncateForTelegram` does a raw
 * character slice; this builder needs a LINE-boundary-aware cut instead —
 * every rendered line closes its own HTML tags/entities, and Telegram
 * rejects unbalanced HTML with a 400 that loses the WHOLE digest rather
 * than shortening it (Hermes L21, 2026-09-13 — pinned by
 * `founder-digest/index_test.ts`'s "truncation cuts on a LINE boundary"
 * test). Switching to the shared raw-slice truncator would silently
 * reintroduce that exact P0, so this is a deliberate deviation from Task
 * 4's illustrative Step 4 sketch, which described deleting this block.
 */

import { escapeHtml, TELEGRAM_MAX_CHARS } from "./telegram.ts";
import { IST_OFFSET_MS, istYesterdayWindow } from "./ist_date.ts";
import { fetchAllPages } from "./paged_fetch.ts";

/** The lifetime sentinel `'epoch'::timestamptz`, as PostgREST renders it. */
export const LIFETIME_WINDOW = "1970-01-01T00:00:00+00:00";

export const MAX_ALERT_LINES = 10;
export const TOP_USERS = 5;
/** Per-read page bound (x1000 rows): 200k rows is ~1,150 users at the worst-case 173 rows/day. */
export const MAX_PAGES = 200;

export interface DigestKey {
  key: string;
  label: string;
  kind: "daily" | "subday" | "lifetime";
  /** Absent for keys whose ceiling varies by tier or is not a ceiling at all. */
  cap?: number;
}

/**
 * EVERY quota_key the ledger carries, enumerated — and pinned both ways by
 * test/contracts/founder_digest_caps_mirror_test.dart against the callers'
 * `p_quota_key` constants and the cap triggers (migration 129). A map of
 * "the keys I thought of" over a template of nine sections is membership
 * without completeness: a misspelt key returns 0 rows and renders "none",
 * which the three-state rendering cannot see.
 *
 * Explicit type, NOT `as const`: with `cap` present on 6 of 9 literals,
 * `as const` makes a union whose members disagree on `cap`, and `k.cap` is
 * TS2339 under CI's `deno check`.
 */
export const DIGEST_KEYS: readonly DigestKey[] = [
  { key: "pro_image_daily", label: "PRO image reads", kind: "daily", cap: 50 },
  { key: "pro_video_daily", label: "PRO video reads", kind: "daily", cap: 10 },
  { key: "chat_app", label: "Chat (free, 10/day)", kind: "daily", cap: 10 },
  { key: "vision_analysis", label: "Vision (scan/cart)", kind: "daily", cap: 20 },
  // 10 free / 200 PRO — tier-dependent, so no single "at cap" ceiling.
  { key: "food_text", label: "Food text", kind: "daily" },
  // Hourly buckets, totals only. ⚠ Known ≤30-min/day slop (B-pass 2026-09-13
  // finding 3): delete-account floors its bucket to the UTC hour, and IST
  // midnight is 18:30Z, so the 18:00Z-19:00Z bucket straddles the day
  // boundary — attempts in the first 30 min of an IST day are reported on
  // the PREVIOUS day's digest. Same-magnitude shift, never lost or doubled.
  { key: "delete_account", label: "delete-account", kind: "subday" },
  // 10-minute buckets, totals only. Unaffected by the slop above: 18:30Z is
  // an exact 10-minute boundary, so its buckets never straddle IST midnight.
  { key: "verify_payment", label: "verify-payment", kind: "subday" },
  { key: "free_image_analysis", label: "Free image reads", kind: "lifetime", cap: 5 },
  { key: "weekly_report_free", label: "Weekly report (free)", kind: "lifetime", cap: 1 },
];

export interface UsageRow {
  user_id: string;
  quota_key: string;
  window_start: string;
  used: number;
  updated_at: string;
}

export interface AlertRow {
  detected_at: string;
  source: string;
  severity: string;
  summary: string;
}

/** One `subscriptions` row created yesterday (IST), for the per-plan breakdown. */
export interface SubscriptionRow {
  plan: string;
  created_at: string;
}

/**
 * A section's read result: rows, or the reason it could not be read.
 * `total` is the exact server-side count when the read was CAPPED (alerts
 * fetch only the lines they render) — a header that counted the page would
 * report "(10)" on a 73-alert day (Hermes L22, 2026-09-13).
 */
export type SectionRead<T> = { rows: T[]; total?: number } | { unreadable: string };

export interface DigestInput {
  /** IST calendar day being reported, e.g. "2026-09-11". */
  dayLabel: string;
  /** Windowed rows whose window_start falls inside yesterday's IST day. */
  windowed: SectionRead<UsageRow>;
  /** Lifetime rows whose updated_at falls inside yesterday's IST day. */
  lifetime: SectionRead<UsageRow>;
  /** Alerts detected inside yesterday's IST day. */
  alerts: SectionRead<AlertRow>;
  /** `subscriptions` rows created inside yesterday's IST day (status='active'). */
  subscriptions: SectionRead<SubscriptionRow>;
  /** Users whose `subscription_expires_at` falls within 7d / 30d of `now`. */
  expiringSoon: { count7d: number; count30d: number } | { unreadable: string };
}

/** 8-char prefix of a user id — enough to correlate, never a whole uuid. */
export function idPrefix(userId: string): string {
  return userId.slice(0, 8);
}

function formatDayLabel(dayLabel: string): string {
  // "2026-09-11" -> "Thu 11 Sep 2026". The label is an IST date; parse it at
  // UTC midnight so the weekday cannot drift with the runtime's timezone.
  const d = new Date(`${dayLabel}T00:00:00Z`);
  if (Number.isNaN(d.getTime())) return dayLabel;
  const day = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getUTCDay()];
  const mon = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ][d.getUTCMonth()];
  return `${day} ${d.getUTCDate()} ${mon} ${d.getUTCFullYear()}`;
}

/** "HH:MM " in IST for an alert stamp; empty when the stamp does not parse. */
export function istClock(iso: string): string {
  const ms = Date.parse(iso);
  if (Number.isNaN(ms)) return "";
  const ist = new Date(ms + IST_OFFSET_MS);
  const hh = String(ist.getUTCHours()).padStart(2, "0");
  const mm = String(ist.getUTCMinutes()).padStart(2, "0");
  return `${hh}:${mm} `;
}

function unreadableLine(section: string, reason: string): string {
  // The marker deliberately names the SECTION, not the table, so the Deno
  // test file never needs the table-name literal that the ledger census in
  // test/contracts/usage_quota_ledger_writer_to_reader_test.dart scans for.
  return `⚠ ${section} unreadable: ${escapeHtml(reason.slice(0, 120))}`;
}

/**
 * Keys present in the rows that DIGEST_KEYS does not enumerate, with a per-key
 * figure. Rendered as a warning line rather than dropped: a new consumer (or
 * a misspelt key) is exactly what the digest must SHOW, and "ignored" is
 * indistinguishable from "none" (Hermes L1 F2, 2026-09-13).
 *
 * `mode` matters: a WINDOWED row's `used` is a bounded day's consumption, so
 * summing it is "yesterday's total". A LIFETIME row's `used` is a running
 * cumulative counter (the same fact the listed lifetime branch above is
 * hardened for — "report who MOVED, never a total"), so summing IT adds two
 * different point-in-time counters together and prints a number that reads
 * as activity but is not. B-pass finding 2026-09-13 caught the unlisted
 * fallback walking back into the exact trap the listed path was fixed for.
 */
function unlistedTotals(rows: UsageRow[], mode: "windowed" | "lifetime"): string[] {
  const known = new Set(DIGEST_KEYS.map((k) => k.key));
  const totals = new Map<string, number>();
  const movers = new Map<string, Set<string>>();
  for (const r of rows) {
    if (known.has(r.quota_key)) continue;
    totals.set(r.quota_key, (totals.get(r.quota_key) ?? 0) + (r.used ?? 0));
    if (!movers.has(r.quota_key)) movers.set(r.quota_key, new Set());
    movers.get(r.quota_key)!.add(r.user_id);
  }
  const keys = [...totals.keys()].sort((a, b) => a.localeCompare(b));
  if (mode === "windowed") {
    return keys.map((k) => `${escapeHtml(k)} ${totals.get(k)}`);
  }
  return keys.map((k) => {
    const n = movers.get(k)!.size;
    return `${escapeHtml(k)} ${n} user${n === 1 ? "" : "s"} moved`;
  });
}

/** Pure: the whole Telegram message for one day's inputs. */
export function buildDigestText(input: DigestInput): string {
  const lines: string[] = [];
  lines.push(`📊 <b>Avya — daily digest</b> · ${formatDayLabel(input.dayLabel)} (IST day)`);
  lines.push("");
  lines.push("<b>Usage yesterday</b>");

  const perUser = new Map<string, number>();

  if ("unreadable" in input.windowed) {
    lines.push(unreadableLine("usage ledger", input.windowed.unreadable));
  } else {
    const rows = input.windowed.rows;
    const alsoParts: string[] = [];
    for (const k of DIGEST_KEYS) {
      if (k.kind === "lifetime") continue;
      const mine = rows.filter((r) => r.quota_key === k.key);
      const total = mine.reduce((s, r) => s + (r.used ?? 0), 0);
      const users = new Set(mine.map((r) => r.user_id)).size;
      if (k.kind === "subday" || k.cap === undefined) {
        alsoParts.push(`${k.label} ${total}`);
        continue;
      }
      const atCap = mine.filter((r) => r.used >= k.cap!).length;
      lines.push(
        mine.length === 0
          ? `${k.label}: none`
          : `${k.label}: ${total} (${users} user${users === 1 ? "" : "s"}) · at cap ${k.cap}: ${atCap}`,
      );
    }
    lines.push(`Also: ${alsoParts.join(" · ")}`);
    // Every windowed row counts toward the per-user ranking — unlisted keys
    // included, since they are real usage the key table simply lacks.
    for (const r of rows) {
      perUser.set(r.user_id, (perUser.get(r.user_id) ?? 0) + (r.used ?? 0));
    }
    const unlisted = unlistedTotals(rows, "windowed");
    if (unlisted.length > 0) {
      lines.push(`⚠ unlisted keys: ${unlisted.join(" · ")} — add to DIGEST_KEYS`);
    }
  }

  if ("unreadable" in input.lifetime) {
    lines.push(unreadableLine("lifetime meters", input.lifetime.unreadable));
  } else {
    const rows = input.lifetime.rows;
    for (const k of DIGEST_KEYS) {
      if (k.kind !== "lifetime") continue;
      const mine = rows.filter((r) => r.quota_key === k.key);
      const moved = new Set(mine.map((r) => r.user_id)).size;
      const atCap = k.cap === undefined ? 0 : mine.filter((r) => r.used >= k.cap!).length;
      // A lifetime row's `used` is cumulative, so "consumed yesterday" is not
      // knowable from the row — report who MOVED. The rows are yesterday's
      // movers only, and a refusal past the cap never touches `updated_at`
      // (migration 128), so a mover at the ceiling REACHED it yesterday —
      // "reached", not "at": the digest does not see the users already
      // parked there (Hermes L1 F3, 2026-09-13).
      lines.push(
        mine.length === 0
          ? `${k.label} (lifetime): none`
          : `${k.label} (lifetime): ${moved} user${moved === 1 ? "" : "s"} moved · reached ${k.cap}/${k.cap} yesterday: ${atCap}`,
      );
    }
    const unlisted = unlistedTotals(rows, "lifetime");
    if (unlisted.length > 0) {
      lines.push(`⚠ unlisted lifetime keys: ${unlisted.join(" · ")} — add to DIGEST_KEYS`);
    }
  }

  lines.push("");
  const top = [...perUser.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, TOP_USERS);
  lines.push(
    top.length === 0
      ? "<b>Top users</b>: none"
      : `<b>Top users</b> (id prefix): ${top.map(([u, n]) => `${idPrefix(u)} ×${n}`).join(" · ")}`,
  );

  lines.push("");
  if ("unreadable" in input.alerts) {
    lines.push(unreadableLine("alerts", input.alerts.unreadable));
  } else if (input.alerts.rows.length === 0) {
    lines.push("<b>Alerts yesterday</b>: none");
  } else {
    const rows = input.alerts.rows;
    // The server count, never the page length: the read is capped at the
    // lines rendered, so `rows.length` would under-report any busier day.
    const total = input.alerts.total ?? rows.length;
    lines.push(`<b>Alerts yesterday</b> (${total}):`);
    for (const a of rows.slice(0, MAX_ALERT_LINES)) {
      lines.push(
        `${istClock(a.detected_at)}[${escapeHtml(a.severity)}] ${escapeHtml(a.source)} — ${
          escapeHtml(a.summary)
        }`,
      );
    }
    if (total > MAX_ALERT_LINES) {
      lines.push(`… +${total - MAX_ALERT_LINES} more`);
    }
  }

  lines.push("");
  lines.push("<b>Subscriptions (new, yesterday)</b>");
  if ("unreadable" in input.subscriptions) {
    lines.push(unreadableLine("subscriptions", input.subscriptions.unreadable));
  } else if (input.subscriptions.rows.length === 0) {
    lines.push("none");
  } else {
    const byPlan = new Map<string, number>();
    for (const r of input.subscriptions.rows) {
      byPlan.set(r.plan, (byPlan.get(r.plan) ?? 0) + 1);
    }
    for (const [plan, n] of byPlan) {
      lines.push(`${escapeHtml(plan)}: ${n}`);
    }
  }

  lines.push("");
  lines.push("<b>Expiring soon</b>");
  if ("unreadable" in input.expiringSoon) {
    lines.push(unreadableLine("expiring-soon", input.expiringSoon.unreadable));
  } else {
    lines.push(`7d: ${input.expiringSoon.count7d} · 30d: ${input.expiringSoon.count30d}`);
  }

  let text = lines.join("\n");
  if (text.length > TELEGRAM_MAX_CHARS) {
    const marker = "\n… (truncated)";
    const limit = TELEGRAM_MAX_CHARS - marker.length;
    // Cut on a LINE boundary. Every line closes its own tags and entities, so
    // a mid-line cut can leave `<b>` open or `&am` dangling — and Telegram
    // rejects unbalanced HTML with a 400, which loses the whole digest rather
    // than shortening it (Hermes L21, 2026-09-13). A raw slice only when a
    // single line is itself over the limit.
    const nl = text.lastIndexOf("\n", limit);
    text = text.slice(0, nl > 0 ? nl : limit) + marker;
  }
  return text;
}

/**
 * The structural slice of a supabase-js client this function uses. Typed
 * this loosely on purpose: the B-pass (2026-09-13, finding 2) mutated the
 * lifetime filter's `updated_at` to `window_start` — a filter that can never
 * match, so the lifetime section would read "none" forever — and NOTHING
 * reddened, because the reads lived inside the handler behind
 * `createClient(...)` where no test could reach them. `founder-digest`'s
 * `index_test.ts` drives this with a recording fake and asserts every column
 * each section filters on. The `.from("<table>")` chains stay LITERAL and
 * inline here so `scripts/check_schema_column_refs.dart` keeps validating
 * their columns against the live schema snapshot (that gate scans all of
 * `supabase/functions/`, this file included) — extracting the filters into
 * table-less helpers would have moved them out of that gate's input set.
 */
// deno-lint-ignore no-explicit-any
export type DigestClient = { from(table: string): any };

/** Runs a section read; a failure becomes that section's "unreadable" state. */
async function readSection<T>(
  read: () => Promise<{ rows: T[]; total?: number }>,
): Promise<SectionRead<T>> {
  try {
    return await read();
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    console.error("[founder-digest] section read failed:", reason.slice(0, 300));
    return { unreadable: reason };
  }
}

/** Reads the three sections for one window; each independently three-state. */
export async function readDigestSections(
  supabase: DigestClient,
  window: { yStart: string; tStart: string },
): Promise<Pick<DigestInput, "windowed" | "lifetime" | "alerts">> {
  const { yStart, tStart } = window;

  // The three reads are independent, so they run in PARALLEL — each
  // `readSection` still fails alone. Sequential awaits cost ~1 s per round
  // trip here (7.5 s first send, 20 s at the contended 02:30Z tick), and the
  // page bound turns a runaway ledger (MAX_PAGES x 1000 rows) into an
  // "unreadable" section instead of an unbounded loop (Hermes L31, 2026-09-13).
  const windowedRead = readSection<UsageRow>(async () => ({
    rows: await fetchAllPages<UsageRow>(
      () =>
        supabase
          .from("usage_counters")
          .select("user_id, quota_key, window_start, used, updated_at")
          .gte("window_start", yStart)
          .lt("window_start", tStart),
      {
        orderBy: [{ column: "user_id" }, { column: "quota_key" }, { column: "window_start" }],
        label: "founder-digest windowed",
        maxPages: MAX_PAGES,
      },
    ),
  }));

  // Lifetime rows all share window_start = epoch, so "moved yesterday" is
  // answered by updated_at — the column consume_quota touches on every
  // increment (migration 128). Filtering these by window_start would match
  // nothing, ever, and render "none" with no error: the exact silent shape
  // the three-state rendering cannot see. Pinned by founder-digest/index_test.ts.
  const lifetimeRead = readSection<UsageRow>(async () => ({
    rows: await fetchAllPages<UsageRow>(
      () =>
        supabase
          .from("usage_counters")
          .select("user_id, quota_key, window_start, used, updated_at")
          .eq("window_start", LIFETIME_WINDOW)
          .gte("updated_at", yStart)
          .lt("updated_at", tStart),
      {
        orderBy: [{ column: "user_id" }, { column: "quota_key" }, { column: "window_start" }],
        label: "founder-digest lifetime",
        maxPages: MAX_PAGES,
      },
    ),
  }));

  // Only the rendered lines are fetched; the header's number is the exact
  // server-side count, so a 73-alert day reads "(73) … +63 more", not "(10)".
  const alertsRead = readSection<AlertRow>(async () => {
    const { data, error, count } = await supabase
      .from("alerts")
      .select("detected_at, source, severity, summary", { count: "exact" })
      .gte("detected_at", yStart)
      .lt("detected_at", tStart)
      .order("detected_at", { ascending: true })
      // A LITERAL, not MAX_ALERT_LINES: check_unbounded_cron_reads.dart accepts
      // only `.limit(<digits>)` so it can verify the bound is <= 1000 (OI-79).
      // founder-digest/index_test.ts pins this literal equal to MAX_ALERT_LINES.
      .limit(10);
    if (error) throw new Error(error.message);
    return {
      rows: (data ?? []) as AlertRow[],
      total: typeof count === "number" ? count : undefined,
    };
  });

  const [windowed, lifetime, alerts] = await Promise.all([windowedRead, lifetimeRead, alertsRead]);
  return { windowed, lifetime, alerts };
}

/**
 * Gathers the SAME data the daily cron sends — the single source both the
 * cron and `/digest` read, so they can never drift apart. Composes
 * `istYesterdayWindow` (the caller-agnostic "yesterday's IST day" window,
 * `_shared/ist_date.ts`) with `readDigestSections` above.
 */
export async function gatherDigestInput(
  supabase: DigestClient,
  now: Date = new Date(),
): Promise<DigestInput> {
  const window = istYesterdayWindow(now);
  const { yStart, tStart } = window;
  const { windowed, lifetime, alerts } = await readDigestSections(supabase, window);

  // New paid subscriptions created inside yesterday's IST day, for the
  // per-plan breakdown. Independent read, same three-state contract as the
  // other sections above. Routed through fetchAllPages (OI-79,
  // check_unbounded_cron_reads.dart): an un-paged `.from()` read in a
  // cron-dispatched function silently truncates at PostgREST's 1000-row
  // db-max-rows cap with HTTP 200 and error===null, exactly the failure
  // paged_fetch.ts exists to prevent. `id` is the primary key — unique and
  // immutable — so it is a safe page-ordering tiebreaker.
  const subscriptionsRead = readSection<SubscriptionRow>(async () => ({
    rows: await fetchAllPages<SubscriptionRow>(
      () =>
        supabase
          .from("subscriptions")
          .select("id, plan, created_at")
          .eq("status", "active")
          .gte("created_at", yStart)
          .lt("created_at", tStart),
      {
        orderBy: [{ column: "id" }],
        label: "founder-digest subscriptions",
        maxPages: MAX_PAGES,
      },
    ),
  }));

  // Users whose subscription expires within 7 / 30 days of `now` — a
  // point-in-time snapshot (not windowed to yesterday), so it uses `now`
  // directly rather than the yesterday-window instants above.
  const expiringSoonRead: Promise<DigestInput["expiringSoon"]> = (async () => {
    try {
      const in7dIso = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000).toISOString();
      const in30dIso = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000).toISOString();
      const [r7, r30] = await Promise.all([
        supabase
          .from("users")
          .select("id", { count: "exact", head: true })
          .not("subscription_expires_at", "is", null)
          .gte("subscription_expires_at", now.toISOString())
          .lte("subscription_expires_at", in7dIso),
        supabase
          .from("users")
          .select("id", { count: "exact", head: true })
          .not("subscription_expires_at", "is", null)
          .gte("subscription_expires_at", now.toISOString())
          .lte("subscription_expires_at", in30dIso),
      ]);
      if (r7.error) throw new Error(r7.error.message);
      if (r30.error) throw new Error(r30.error.message);
      return { count7d: r7.count ?? 0, count30d: r30.count ?? 0 };
    } catch (err) {
      const reason = err instanceof Error ? err.message : String(err);
      console.error("[founder-digest] section read failed:", reason.slice(0, 300));
      return { unreadable: reason };
    }
  })();

  const [subscriptions, expiringSoon] = await Promise.all([subscriptionsRead, expiringSoonRead]);
  return { dayLabel: window.label, windowed, lifetime, alerts, subscriptions, expiringSoon };
}
