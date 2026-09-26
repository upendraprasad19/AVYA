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
import { fetchAllByIds, fetchAllPages } from "./paged_fetch.ts";
import { sanitizeIdentifier } from "./sanitize_for_prompt.ts";

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
 * `founder_metrics_for_admin_api()` RPC row (delegates to `private.founder_metrics()`).
 * ⚠ `signups_today_ist` and `pro_expired` are deliberately NEVER rendered from
 * this row (B1, review round 2) — see the render-site comments in
 * `buildDigestText` for why each is unsafe to surface here.
 */
export interface AdminMetricsRow {
  total_users: number;
  signups_today_ist: number;
  signups_7d: number;
  signups_30d: number;
  pro_active: number;
  pro_expired: number;
  free_users: number;
  active_subscriptions: number;
  active_last_7d: number;
  generated_at: string;
}

/**
 * `founder_metrics_ops()` RPC row.
 * ⚠ `client_errors_today` is deliberately NEVER rendered — same partial-day
 * defect as `AdminMetricsRow.signups_today_ist` (both are "since IST midnight
 * TODAY" gauges, and the digest cron runs at 08:00 IST reporting YESTERDAY).
 */
export interface OpsMetricsRow {
  client_errors_today: number;
  client_errors_7d: number;
  open_alerts_count: number;
  cron_failures_24h: number;
  generated_at: string;
}

/**
 * `founder_metrics_engagement()` RPC row.
 * ⚠ `workouts_logged_today`, `food_logs_today`, `ai_messages_today` and
 * `holds_started_today` are deliberately NEVER rendered — all four share the
 * exact same "since IST midnight TODAY" partial-day shape B1 fixed for
 * `signups_today_ist`; this RPC was never reviewed for that class in the
 * spec, but the underlying SQL (verified live) has the identical defect.
 */
export interface EngagementMetricsRow {
  workouts_logged_today: number;
  food_logs_today: number;
  ai_messages_today: number;
  streak_maintained_current_week: number;
  holds_started_today: number;
  holds_started_7d: number;
  holders_total: number;
  generated_at: string;
}

/**
 * Per CLAUDE.md §1: ₹349/month or ₹2,999/year for PRO — these are BOOKING
 * prices (what a signup pays at that cadence), not monthly-recurring
 * contributions. `computeNewMrr` below divides the yearly price by 12 before
 * summing; never sum this map's raw values directly into an "MRR" figure.
 *
 * A known, deliberately-free plan value (`referral_trial`) contributes ₹0
 * and must NOT be added here (see `KNOWN_ZERO_PRICE_PLANS` below) — adding a
 * price for it would make New MRR silently start booking revenue that was
 * never collected. Any OTHER plan value not in this map contributes ₹0 and
 * is counted separately (`computeNewMrr`'s `unknownPlanCount`) so a genuinely
 * unrecognized or future plan value is visible in the digest rather than
 * silently mispriced or silently dropped.
 */
export const PLAN_PRICES_RUPEES: Readonly<Record<string, number>> = {
  monthly: 349,
  yearly: 2999,
};

/**
 * Plan values that are REAL, live `subscriptions.plan` values but are
 * deliberately priced at ₹0 — excluded from `unknownPlanCount` so the
 * digest's "add to PLAN_PRICES_RUPEES" warning never tells the founder to
 * price a free trial (Hermes L22 F1, 2026-09-21: `referral_trial` is a live
 * plan value, 4 active rows confirmed, and the original warning copy would
 * have led the founder to add `referral_trial: 349` — silently turning every
 * future referral trial into booked revenue that was never collected).
 */
const KNOWN_ZERO_PRICE_PLANS = new Set(["referral_trial"]);

/**
 * New MRR (yesterday), computed from the SAME `subscriptions.rows` the
 * "Subscriptions (new, yesterday)" section already reads — no separate DB
 * read. Gross, before promo discounts: `razorpay-webhook/index.ts:130-143`
 * shows promo codes discount the captured amount, and the discount is never
 * persisted on the row, so a promo-redeemed signup overstates this figure by
 * the discount amount (B3, review round 1) — the caller must render the
 * "gross, before promo discounts" caveat alongside this number.
 *
 * A YEARLY plan contributes its price DIVIDED BY 12 — MRR is a *monthly*
 * figure by definition. Fixed by a Hermes pass (L1/L21, 2026-09-21): the
 * first cut summed the full ₹2,999 booking price per yearly signup, a 12x
 * overstatement caught by cross-referencing `telegram-admin-bot/index.ts`'s
 * OWN `/revenue` command, which already divides yearly by 12 for exactly
 * this reason — this function failed to reuse that established pattern.
 * Rounded to the nearest rupee only in the final sum, not per-row, so
 * rounding error cannot compound across many yearly rows.
 */
export function computeNewMrr(
  rows: readonly SubscriptionRow[],
): { rupees: number; unknownPlanCount: number } {
  let rupeesExact = 0;
  let unknownPlanCount = 0;
  for (const r of rows) {
    if (KNOWN_ZERO_PRICE_PLANS.has(r.plan)) continue;
    const price = PLAN_PRICES_RUPEES[r.plan];
    if (price === undefined) {
      unknownPlanCount++;
      continue;
    }
    rupeesExact += r.plan === "yearly" ? price / 12 : price;
  }
  return { rupees: Math.round(rupeesExact), unknownPlanCount };
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

  /**
   * Genuinely-windowed count of NEW user signups (`users.created_at`) inside
   * yesterday's IST day. NOT `AdminMetricsRow.signups_today_ist`, which is a
   * partial "since IST midnight TODAY" gauge (B1, review round 2).
   */
  signupsYesterday: { count: number } | { unreadable: string };
  /** `founder_metrics_for_admin_api()` RPC row (B1). See its own doc comment for which fields are safe to render. */
  adminMetrics: SectionRead<AdminMetricsRow>;
  /** `founder_metrics_ops()` RPC row (B1). See its own doc comment for which fields are safe to render. */
  opsMetrics: SectionRead<OpsMetricsRow>;
  /** `founder_metrics_engagement()` RPC row (B1). See its own doc comment for which fields are safe to render. */
  engagementMetrics: SectionRead<EngagementMetricsRow>;
  /**
   * `user_id` -> a display-ready first name, or `null` when unavailable
   * (no/empty `full_name`) or opted out via `coach_memory.private_mode`
   * (B2). Covers every distinct `user_id` present in `windowed.rows` — a
   * superset of whichever 5 end up in `buildDigestText`'s Top Users ranking,
   * computed there and only there, so this map itself is never filtered to
   * a top-N ahead of time. Built ONCE here (impure) so the PURE
   * `buildDigestText` never queries the database itself.
   */
  userNames: ReadonlyMap<string, string | null>;
  /**
   * Count of `subscriptions.cancelled_at` (migration 138) falling inside
   * yesterday's IST window — manual-dashboard-action only today. Reads 0 for
   * every day before that migration lands (no retroactive backfill,
   * founder-accepted) — the digest copy states this explicitly (B3).
   */
  cancelledYesterday: { count: number } | { unreadable: string };
  /**
   * Count of `users` rows whose PRO access lapsed (`subscription_expires_at`
   * fell inside yesterday's IST window while `subscription_status` is still
   * `'pro'` — never reconciled by any job, per `_shared/subscription.ts`).
   * The corrected "churn" proxy (B3, review round 2) — NOT
   * `AdminMetricsRow.pro_expired`, which is an un-windowed cumulative total
   * that would read as a "yesterday" figure but isn't one.
   */
  lapsedYesterday: { count: number } | { unreadable: string };
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
  // B2: a display-ready first name when one is available (not opted out via
  // coach_memory.private_mode, and full_name is non-empty) — falls back to
  // the pre-existing id-prefix format otherwise, exactly as before B2.
  lines.push(
    top.length === 0
      ? "<b>Top users</b>: none"
      : `<b>Top users</b>: ${
        top.map(([u, n]) => {
          const name = input.userNames.get(u);
          const label = name ? escapeHtml(name) : idPrefix(u);
          return `${label} ×${n}`;
        }).join(" · ")
      }`,
  );

  // B1: new signups (yesterday), genuinely windowed — NOT
  // adminMetrics.signups_today_ist (a partial "since IST midnight TODAY"
  // gauge). signups_7d / signups_30d from the RPC ARE safe rolling windows.
  lines.push("");
  lines.push("<b>New signups (yesterday)</b>");
  if ("unreadable" in input.signupsYesterday) {
    lines.push(unreadableLine("new signups", input.signupsYesterday.unreadable));
  } else {
    lines.push(`${input.signupsYesterday.count}`);
  }
  if ("unreadable" in input.adminMetrics) {
    lines.push(unreadableLine("signups 7d/30d", input.adminMetrics.unreadable));
  } else if (input.adminMetrics.rows.length > 0) {
    const m = input.adminMetrics.rows[0];
    lines.push(`7d: ${m.signups_7d} · 30d: ${m.signups_30d}`);
  }

  // B1: account totals — a current snapshot, not a "yesterday" figure.
  // pro_expired is deliberately NEVER rendered here (B3 computes its own
  // genuinely-windowed "Lapsed" figure below — rendering both would
  // duplicate/contradict with no cross-reference).
  lines.push("");
  lines.push("<b>Account totals</b>");
  if ("unreadable" in input.adminMetrics) {
    lines.push(unreadableLine("account totals", input.adminMetrics.unreadable));
  } else if (input.adminMetrics.rows.length === 0) {
    lines.push("none");
  } else {
    const m = input.adminMetrics.rows[0];
    lines.push(
      `Total: ${m.total_users} · PRO: ${m.pro_active} · Free: ${m.free_users}`,
    );
    lines.push(
      `Active subscriptions: ${m.active_subscriptions} · active last 7d: ${m.active_last_7d}`,
    );
  }

  // B1: engagement — only the rolling/cumulative/current-snapshot fields.
  // workouts_logged_today, food_logs_today, ai_messages_today and
  // holds_started_today are deliberately NEVER rendered — see
  // EngagementMetricsRow's own doc comment for why (same partial-day defect
  // as signups_today_ist).
  lines.push("");
  lines.push("<b>Engagement</b>");
  if ("unreadable" in input.engagementMetrics) {
    lines.push(unreadableLine("engagement", input.engagementMetrics.unreadable));
  } else if (input.engagementMetrics.rows.length === 0) {
    lines.push("none");
  } else {
    const m = input.engagementMetrics.rows[0];
    lines.push(`Streak maintained (current week): ${m.streak_maintained_current_week}`);
    lines.push(`Hold starts (7d): ${m.holds_started_7d} · total ever: ${m.holders_total}`);
  }

  // B1: ops — client_errors_today is deliberately NEVER rendered (same
  // partial-day defect). open_alerts_count and cron_failures_24h are
  // current-snapshot / rolling-24h figures, safe as-is.
  lines.push("");
  lines.push("<b>Ops</b>");
  if ("unreadable" in input.opsMetrics) {
    lines.push(unreadableLine("ops", input.opsMetrics.unreadable));
  } else if (input.opsMetrics.rows.length === 0) {
    lines.push("none");
  } else {
    const m = input.opsMetrics.rows[0];
    lines.push(`Client errors (7d): ${m.client_errors_7d}`);
    lines.push(`Open alerts: ${m.open_alerts_count} · cron failures (24h): ${m.cron_failures_24h}`);
  }

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
    // B3: New MRR, computed from this SAME already-fetched rows array — no
    // separate read. Gross, before promo discounts (razorpay-webhook applies
    // a discount that is never persisted on the row — review round 1).
    const mrr = computeNewMrr(input.subscriptions.rows);
    lines.push(`New MRR: ₹${mrr.rupees} (gross, before promo discounts)`);
    if (mrr.unknownPlanCount > 0) {
      lines.push(
        `⚠ ${mrr.unknownPlanCount} subscription(s) with an unpriced plan value excluded from MRR — add to PLAN_PRICES_RUPEES`,
      );
    }
  }

  // B3: two genuinely-windowed figures, never merged into one "Churn" line
  // (a merged figure would hide which of the two — manual cancellation vs.
  // silent non-renewal — actually happened). Both read 0 for every day
  // before migration 138 lands — expected, stated explicitly rather than
  // shown as a silent bare zero.
  lines.push("");
  lines.push("<b>Cancelled / lapsed (yesterday)</b>");
  lines.push("<i>Manual-cancellation tracking started 2026-09-21 — 0 before that date is expected, not \"no churn\"</i>");
  if ("unreadable" in input.cancelledYesterday) {
    lines.push(unreadableLine("cancelled (manual)", input.cancelledYesterday.unreadable));
  } else {
    lines.push(`Cancelled (manual): ${input.cancelledYesterday.count}`);
  }
  if ("unreadable" in input.lapsedYesterday) {
    lines.push(unreadableLine("lapsed", input.lapsedYesterday.unreadable));
  } else {
    lines.push(`Lapsed (PRO access expired, not renewed): ${input.lapsedYesterday.count}`);
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
// `rpc` is OPTIONAL: `readDigestSections` never calls it (only
// `gatherDigestInput`'s 3 new RPC reads do, B1), and widening this one
// shared type to REQUIRE it broke every pre-existing test fixture that
// passes a `.from()`-only fake client to `readDigestSections` — none of
// them exercise the RPC path, so they should not need to implement it.
// deno-lint-ignore no-explicit-any
export type DigestClient = { from(table: string): any; rpc?(fn: string): any };

/** Runs a section read; a failure becomes that section's "unreadable" state. */
async function readSection<T>(
  read: () => Promise<{ rows: T[]; total?: number }>,
  // R2-15 (review round 2): this module is now called by BOTH
  // founder-digest's daily cron AND telegram-admin-bot's `/digest` command
  // — every read-failure log line used to be hardcoded to "[founder-digest]",
  // which misnames the caller when it was really telegram-admin-bot.
  callerLabel: string = "founder-digest",
): Promise<SectionRead<T>> {
  try {
    return await read();
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    console.error(`[${callerLabel}] section read failed:`, reason.slice(0, 300));
    return { unreadable: reason };
  }
}

/** Reads the three sections for one window; each independently three-state. */
export async function readDigestSections(
  supabase: DigestClient,
  window: { yStart: string; tStart: string },
  callerLabel: string = "founder-digest",
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
  }), callerLabel);

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
  }), callerLabel);

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
  }, callerLabel);

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
  // R2-15 (review round 2): threaded through to every section's read-failure
  // log line so it names the REAL caller — founder-digest's daily cron, or
  // telegram-admin-bot's `/digest` command — instead of always saying
  // "[founder-digest]".
  callerLabel: string = "founder-digest",
): Promise<DigestInput> {
  const window = istYesterdayWindow(now);
  const { yStart, tStart } = window;
  const { windowed, lifetime, alerts } = await readDigestSections(supabase, window, callerLabel);

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
  }), callerLabel);

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
      console.error(`[${callerLabel}] section read failed:`, reason.slice(0, 300));
      return { unreadable: reason };
    }
  })();

  // `rpc` is optional on DigestClient (see its own doc comment) — a caller
  // that never provides one (every pre-existing test fake) degrades an RPC
  // section to "unreadable" via readSection's own try/catch, rather than
  // throwing a raw TypeError out of gatherDigestInput.
  async function callRpc<T>(fnName: string): Promise<T[]> {
    if (typeof supabase.rpc !== "function") {
      throw new Error(`DigestClient has no rpc() — cannot call ${fnName}`);
    }
    const { data, error } = await supabase.rpc(fnName);
    if (error) throw new Error(error.message);
    return (data ?? []) as T[];
  }

  // B1: three existing SECURITY DEFINER metrics functions, previously unused
  // by the digest. Each independently three-state via readSection, same as
  // every other section — a failed RPC degrades that ONE section to
  // "unreadable", never the whole digest.
  const adminMetricsRead = readSection<AdminMetricsRow>(
    async () => ({ rows: await callRpc<AdminMetricsRow>("founder_metrics_for_admin_api") }),
    callerLabel,
  );

  const opsMetricsRead = readSection<OpsMetricsRow>(
    async () => ({ rows: await callRpc<OpsMetricsRow>("founder_metrics_ops") }),
    callerLabel,
  );

  const engagementMetricsRead = readSection<EngagementMetricsRow>(
    async () => ({ rows: await callRpc<EngagementMetricsRow>("founder_metrics_engagement") }),
    callerLabel,
  );

  // B1 (review round 2): `AdminMetricsRow.signups_today_ist` is a partial
  // "since IST midnight TODAY" gauge, not "yesterday" — a genuinely windowed
  // replacement, reusing the SAME yStart/tStart every other section already
  // uses.
  const signupsYesterdayRead: Promise<DigestInput["signupsYesterday"]> = (async () => {
    try {
      const { count, error } = await supabase
        .from("users")
        .select("id", { count: "exact", head: true })
        .gte("created_at", yStart)
        .lt("created_at", tStart);
      if (error) throw new Error(error.message);
      return { count: count ?? 0 };
    } catch (err) {
      const reason = err instanceof Error ? err.message : String(err);
      console.error(`[${callerLabel}] section read failed:`, reason.slice(0, 300));
      return { unreadable: reason };
    }
  })();

  // B3: manual-cancellation count (migration 138's cancelled_at). Reads
  // "unreadable" (column does not exist) until that migration is applied —
  // a live-apply is a separate, explicitly-authorized action, so this code
  // ships ahead of it deliberately, per this file's own three-state
  // contract (an unreadable section is never rendered as a bare zero).
  // The `.eq('status', 'cancelled')` filter is belt-and-suspenders on top of
  // migration 140's trigger fix (Hermes L22 F2, 2026-09-21): the trigger now
  // clears `cancelled_at` on reactivation, but this filter means the count
  // stays correct even for any row a future writer stamps out of band.
  const cancelledYesterdayRead: Promise<DigestInput["cancelledYesterday"]> = (async () => {
    try {
      const { count, error } = await supabase
        .from("subscriptions")
        .select("id", { count: "exact", head: true })
        .eq("status", "cancelled")
        .gte("cancelled_at", yStart)
        .lt("cancelled_at", tStart);
      if (error) throw new Error(error.message);
      return { count: count ?? 0 };
    } catch (err) {
      const reason = err instanceof Error ? err.message : String(err);
      console.error(`[${callerLabel}] section read failed:`, reason.slice(0, 300));
      return { unreadable: reason };
    }
  })();

  // B3 (review round 2, corrected): the real "churn" proxy — a user whose
  // `subscription_expires_at` fell inside yesterday's IST window while
  // `subscription_status` is still 'pro' (never reconciled to 'expired' by
  // any job — `_shared/subscription.ts`). NOT `AdminMetricsRow.pro_expired`,
  // which is an un-windowed cumulative total.
  const lapsedYesterdayRead: Promise<DigestInput["lapsedYesterday"]> = (async () => {
    try {
      const { count, error } = await supabase
        .from("users")
        .select("id", { count: "exact", head: true })
        .eq("subscription_status", "pro")
        .gte("subscription_expires_at", yStart)
        .lt("subscription_expires_at", tStart);
      if (error) throw new Error(error.message);
      return { count: count ?? 0 };
    } catch (err) {
      const reason = err instanceof Error ? err.message : String(err);
      console.error(`[${callerLabel}] section read failed:`, reason.slice(0, 300));
      return { unreadable: reason };
    }
  })();

  // B2: batch-fetch a display name for every distinct user_id already
  // present in `windowed.rows` — a superset of whichever 5 end up in
  // buildDigestText's Top Users ranking (computed there, purely, from this
  // same `windowed` data). Two separate plain `.from()` queries rather than
  // a PostgREST embedded join, matching this file's own established
  // "literal, inline .from() chains" convention (so
  // check_schema_column_refs.dart keeps validating both tables' columns).
  // Never queries anything if `windowed` itself is unreadable — the ranking
  // that would consume this map is empty in that case regardless.
  const userNamesRead: Promise<DigestInput["userNames"]> = (async () => {
    if ("unreadable" in windowed) return new Map<string, string | null>();
    const ids = [...new Set(windowed.rows.map((r) => r.user_id))];
    if (ids.length === 0) return new Map<string, string | null>();
    try {
      // Both `.in()` reads are bounded via fetchAllByIds (OI-79 class,
      // check_unbounded_cron_reads.dart): chunking the id list alone bounds
      // the request URL but not the response row count, so an unpaged
      // `.in()` read can still be silently truncated at PostgREST's
      // db-max-rows. Each throws on a page error, caught by this try/catch.
      const [names, memory] = await Promise.all([
        fetchAllByIds<{ id: string; full_name: string | null }>(
          (chunk) => supabase.from("users").select("id, full_name").in("id", chunk),
          ids,
          { orderBy: "id", label: `${callerLabel} userNames`, maxPages: MAX_PAGES },
        ),
        fetchAllByIds<{ user_id: string; private_mode: boolean }>(
          (chunk) =>
            supabase.from("coach_memory").select("user_id, private_mode").in(
              "user_id",
              chunk,
            ),
          ids,
          {
            orderBy: "user_id",
            label: `${callerLabel} userNames privacy`,
            maxPages: MAX_PAGES,
          },
        ),
      ]);
      // Default-DENY on identity exposure (Hermes L40 F3, 2026-09-21): a user
      // with NO coach_memory row at all (never opened the AI coach) used to
      // fall through to "shown" — opted OUT by construction, with no surface
      // on which they could ever have expressed the preference this control
      // exists for. Build the set of users EXPLICITLY confirmed
      // private_mode=false instead of the inverse; everyone else (no row, or
      // private_mode=true) is suppressed to the id prefix.
      const explicitlyVisibleIds = new Set<string>(
        memory.filter((m) => m.private_mode === false).map((m) => m.user_id),
      );
      const map = new Map<string, string | null>();
      for (const row of names) {
        if (!explicitlyVisibleIds.has(row.id)) {
          map.set(row.id, null);
          continue;
        }
        // sanitizeIdentifier (Hermes L23 #2, 2026-09-21): a bare
        // escapeHtml + .split(" ")[0] does not strip newlines/control
        // characters or cap length — `users.full_name` is attacker-adjacent
        // (seeded verbatim from signup metadata), so an unsanitised name
        // could inject forged lines into this admin-only Telegram message
        // or push the digest past TELEGRAM_MAX_CHARS, silently truncating
        // sections below it. Same helper `re-engagement` already uses for
        // this exact purpose.
        const first = sanitizeIdentifier(row.full_name, {
          maxLen: 32,
          fallback: "",
        }).split(" ")[0];
        map.set(row.id, first.length === 0 ? null : first);
      }
      return map;
    } catch (err) {
      const reason = err instanceof Error ? err.message : String(err);
      console.error(`[${callerLabel}] section read failed:`, reason.slice(0, 300));
      // A failed name lookup degrades to "no names available" — every user
      // renders under the pre-existing id-prefix format. Never a hard
      // failure: a name is a display nicety, not load-bearing data.
      return new Map<string, string | null>();
    }
  })();

  const [
    subscriptions,
    expiringSoon,
    adminMetrics,
    opsMetrics,
    engagementMetrics,
    signupsYesterday,
    cancelledYesterday,
    lapsedYesterday,
    userNames,
  ] = await Promise.all([
    subscriptionsRead,
    expiringSoonRead,
    adminMetricsRead,
    opsMetricsRead,
    engagementMetricsRead,
    signupsYesterdayRead,
    cancelledYesterdayRead,
    lapsedYesterdayRead,
    userNamesRead,
  ]);
  return {
    dayLabel: window.label,
    windowed,
    lifetime,
    alerts,
    subscriptions,
    expiringSoon,
    adminMetrics,
    opsMetrics,
    engagementMetrics,
    signupsYesterday,
    cancelledYesterday,
    lapsedYesterday,
    userNames,
  };
}
