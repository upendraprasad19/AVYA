/**
 * founder-digest — one Telegram message a day to the founder: yesterday's
 * usage per quota_key, users at a ceiling, top users by id prefix, and the
 * alerts the cron rules raised. READ-ONLY over the database; it decides no
 * quota and writes nothing but its own cron_call_log row.
 *
 * Triggers: pg_cron job `founder_digest_daily`, `30 2 * * *` UTC = 08:00 IST
 *   (migration 131). Every day, including all-quiet days: the message's
 *   ARRIVAL is the liveness signal — its absence means the cron or the bot
 *   is dead, which `alert_cron_function_dead` (8-day window) would otherwise
 *   take a week to notice. A manual re-run sends a duplicate; acceptable.
 * Edge Function secrets: TELEGRAM_BOT_TOKEN, FOUNDER_TELEGRAM_CHAT_ID (both
 *   stored 2026-09-12 and proven by a delivered message), CRON_SECRET (the
 *   gate), platform-injected SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.
 * Owner: founder
 * Created: 2026-09-12 (OI-153)
 *
 * Three states per section, never two (feedback_bad_news_vs_no_news): data ·
 * "none" · an explicit "unreadable" marker. An unreadable section is never
 * rendered as zeros.
 *
 * The Telegram send is a private twin of morning-alert's, with ONE deliberate
 * difference: the fetch is wrapped in its own try/catch and NEITHER the error
 * object nor String(err) is ever logged or passed to logCronEnd. A Deno fetch
 * TypeError's message embeds the request URL — `api.telegram.org/bot<TOKEN>/…`
 * — so logging it would put the bot token in the function logs. Only
 * `err.name`, and for a non-2xx the status + the first 200 chars of Telegram's
 * body (which never echoes the token), ever leave this function.
 */

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { corsHeaders, ok, serverError } from "../_shared/error.ts";
import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";
import { logCronEnd, logCronStart } from "../_shared/cron_telemetry.ts";
import { IST_OFFSET_MS, istDateStr, istDayStartIso } from "../_shared/ist_date.ts";
import { fetchAllPages } from "../_shared/paged_fetch.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

/** The lifetime sentinel `'epoch'::timestamptz`, as PostgREST renders it. */
export const LIFETIME_WINDOW = "1970-01-01T00:00:00+00:00";

export const TELEGRAM_MAX_CHARS = 4096;
export const MAX_ALERT_LINES = 10;
export const TOP_USERS = 5;
/** IST has no DST; an IST day is always exactly this long. */
const ONE_DAY_MS = 24 * 60 * 60 * 1000;

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
  // Hourly buckets, totals only.
  { key: "delete_account", label: "delete-account", kind: "subday" },
  // 10-minute buckets, totals only.
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

/** A section's read result: rows, or the reason it could not be read. */
export type SectionRead<T> = { rows: T[] } | { unreadable: string };

export interface DigestInput {
  /** IST calendar day being reported, e.g. "2026-09-11". */
  dayLabel: string;
  /** Windowed rows whose window_start falls inside yesterday's IST day. */
  windowed: SectionRead<UsageRow>;
  /** Lifetime rows whose updated_at falls inside yesterday's IST day. */
  lifetime: SectionRead<UsageRow>;
  /** Alerts detected inside yesterday's IST day. */
  alerts: SectionRead<AlertRow>;
}

/**
 * Yesterday's IST day as ISO-Z strings for `.gte()` / `.lt()` filters, plus
 * its label. ISO strings, deliberately: a `Date` handed to a PostgREST filter
 * stringifies via `toString()` (non-ISO), which Postgres rejects — the usage
 * section would then read "unreadable" every single day.
 */
export function istYesterdayWindow(
  now: Date = new Date(),
): { yStart: string; tStart: string; label: string } {
  const tStartMs = Date.parse(istDayStartIso(now));
  const yStartMs = tStartMs - ONE_DAY_MS;
  return {
    yStart: new Date(yStartMs).toISOString(),
    tStart: new Date(tStartMs).toISOString(),
    label: istDateStr(new Date(yStartMs)),
  };
}

/** Telegram `parse_mode: "HTML"` treats these three as markup. */
export function escapeHtml(s: string): string {
  return s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

/** 8-char prefix of a user id — enough to correlate, never a whole uuid. */
export function idPrefix(userId: string): string {
  return userId.slice(0, 8);
}

/**
 * The name of an error and NOTHING else. A Deno fetch TypeError's `.message`
 * embeds the request URL, which carries the bot token; `.name` cannot.
 */
export function telegramErrorSummary(err: unknown): string {
  const name = err instanceof Error ? err.name : typeof err;
  return `telegram send threw ${name}`;
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
      for (const r of mine) {
        perUser.set(r.user_id, (perUser.get(r.user_id) ?? 0) + (r.used ?? 0));
      }
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
      // knowable from the row — report who MOVED and who sits at the ceiling.
      lines.push(
        mine.length === 0
          ? `${k.label} (lifetime): none`
          : `${k.label} (lifetime): ${moved} user${moved === 1 ? "" : "s"} moved · at ${k.cap}/${k.cap}: ${atCap}`,
      );
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
    lines.push(`<b>Alerts yesterday</b> (${rows.length}):`);
    for (const a of rows.slice(0, MAX_ALERT_LINES)) {
      lines.push(
        `${istClock(a.detected_at)}[${escapeHtml(a.severity)}] ${escapeHtml(a.source)} — ${
          escapeHtml(a.summary)
        }`,
      );
    }
    if (rows.length > MAX_ALERT_LINES) {
      lines.push(`… +${rows.length - MAX_ALERT_LINES} more`);
    }
  }

  let text = lines.join("\n");
  if (text.length > TELEGRAM_MAX_CHARS) {
    const marker = "\n… (truncated)";
    text = text.slice(0, TELEGRAM_MAX_CHARS - marker.length) + marker;
  }
  return text;
}

/** Private twin of morning-alert's sender — see the header for the difference. */
async function sendTelegram(
  token: string,
  chatId: string,
  text: string,
): Promise<{ ok: true } | { ok: false; summary: string }> {
  try {
    const res = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: chatId,
        text,
        parse_mode: "HTML",
        disable_web_page_preview: true,
      }),
    });
    if (!res.ok) {
      const body = (await res.text().catch(() => "")).slice(0, 200);
      return { ok: false, summary: `telegram HTTP ${res.status}: ${body}` };
    }
    return { ok: true };
  } catch (err) {
    return { ok: false, summary: telegramErrorSummary(err) };
  }
}

export const handler = async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (!await isAuthorizedCronCall(req)) {
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const logId = await logCronStart("founder-digest");

  try {
    const token = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
    const chatId = Deno.env.get("FOUNDER_TELEGRAM_CHAT_ID") ?? "";
    if (!token || !chatId) {
      // Loud, never a silent `return false` (the shape morning-alert has).
      const errorSummary = "TELEGRAM_BOT_TOKEN / FOUNDER_TELEGRAM_CHAT_ID not configured";
      await logCronEnd(logId, "failed", { httpStatus: 500, errorSummary });
      return serverError("founder-digest:secrets", new Error(errorSummary));
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { yStart, tStart, label } = istYesterdayWindow();

    const windowed = await readSection<UsageRow>(() =>
      fetchAllPages<UsageRow>(
        () =>
          supabase
            .from("usage_counters")
            .select("user_id, quota_key, window_start, used, updated_at")
            .gte("window_start", yStart)
            .lt("window_start", tStart),
        {
          orderBy: [{ column: "user_id" }, { column: "quota_key" }, { column: "window_start" }],
          label: "founder-digest windowed",
        },
      )
    );

    const lifetime = await readSection<UsageRow>(() =>
      fetchAllPages<UsageRow>(
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
        },
      )
    );

    const alerts = await readSection<AlertRow>(async () => {
      const { data, error } = await supabase
        .from("alerts")
        .select("detected_at, source, severity, summary")
        .gte("detected_at", yStart)
        .lt("detected_at", tStart)
        .order("detected_at", { ascending: true })
        .limit(50);
      if (error) throw new Error(error.message);
      return (data ?? []) as AlertRow[];
    });

    const text = buildDigestText({ dayLabel: label, windowed, lifetime, alerts });

    const sent = await sendTelegram(token, chatId, text);
    if (!sent.ok) {
      await logCronEnd(logId, "failed", { httpStatus: 502, errorSummary: sent.summary });
      return new Response(
        JSON.stringify({ error: "telegram send failed" }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    await logCronEnd(logId, "success", { httpStatus: 200 });
    return ok({ ok: true, day: label, chars: text.length });
  } catch (err) {
    // Reads and rendering only reach here — the send catches its own errors
    // internally, so a fetch error (URL-bearing) can never be stringified.
    await logCronEnd(logId, "failed", {
      httpStatus: 500,
      errorSummary: String(err).slice(0, 500),
    });
    return serverError("founder-digest", err);
  }
};

/** Runs a section read; a failure becomes that section's "unreadable" state. */
async function readSection<T>(read: () => Promise<T[]>): Promise<SectionRead<T>> {
  try {
    return { rows: await read() };
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    console.error("[founder-digest] section read failed:", reason.slice(0, 300));
    return { unreadable: reason };
  }
}

if (import.meta.main) {
  serve(handler);
}
