/**
 * Deno unit tests for `founder-digest`'s pure pieces (OI-153, T6).
 *
 * Run:
 *   deno test --no-check --allow-all --node-modules-dir=none supabase/functions/founder-digest/
 *
 * Scope: `buildDigestText`, `istYesterdayWindow`, `escapeHtml`, `idPrefix`,
 * `istClock`, `telegramErrorSummary`, `sendTelegram` (through an injected
 * fetch), `readDigestSections` (through a recording fake client),
 * `DIGEST_KEYS` — the serve handler is NOT exercised here (needs live env +
 * a bot). End-to-end verification is the manual `net.http_post` in the
 * plan's T9 and the cron's own 02:30Z fire.
 *
 * ⚠ test/contracts/usage_quota_ledger_writer_to_reader_test.dart walks every
 * .ts under supabase/functions/ (comment-stripped) and allowlists direct
 * ledger readers BY FILE. This file is allowlisted there — not because it
 * reads the ledger (it never does) but because the read-shape tests at the
 * bottom assert the TABLE NAME each section queries through a recording fake.
 * It must never spell the consume RPC's name: the digest has no such call and
 * the sibling census assertion pins that by the file's absence from that list.
 */

import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  type AdminMetricsRow,
  buildDigestText,
  computeNewMrr,
  DIGEST_KEYS,
  type DigestInput,
  type EngagementMetricsRow,
  escapeHtml,
  gatherDigestInput,
  idPrefix,
  istClock,
  istYesterdayWindow,
  LIFETIME_WINDOW,
  MAX_ALERT_LINES,
  MAX_PAGES,
  type OpsMetricsRow,
  readDigestSections,
  sendTelegram,
  type SubscriptionRow,
  TELEGRAM_MAX_CHARS,
  telegramErrorSummary,
  type UsageRow,
} from "./index.ts";

const DAY = "2026-09-11";
const U1 = "0a1b2c3d-1111-4222-8333-444455556666";
const U2 = "9f8e7d6c-1111-4222-8333-444455556666";
const U3 = "5d4c3b2a-1111-4222-8333-444455556666";

function row(
  user_id: string,
  quota_key: string,
  used: number,
  window_start = `${DAY}T18:30:00+00:00`,
): UsageRow {
  return { user_id, quota_key, window_start, used, updated_at: `${DAY}T20:00:00+00:00` };
}

function input(over: Partial<DigestInput> = {}): DigestInput {
  return {
    dayLabel: DAY,
    windowed: { rows: [] },
    lifetime: { rows: [] },
    alerts: { rows: [] },
    // Task 5 (telegram-admin-bot) grew DigestInput by two fields; this file's
    // fixtures predate that and don't exercise either section, so default them
    // to the readable-empty state so every existing `input()` call keeps
    // compiling and rendering exactly as before.
    subscriptions: { rows: [] },
    expiringSoon: { count7d: 0, count30d: 0 },
    // B1/B2/B3 (observation-batch-and-digest-redesign, 2026-09-21) grew
    // DigestInput by 7 more fields; same "readable-empty default, override
    // via `over` when a test actually exercises one" pattern as above.
    signupsYesterday: { count: 0 },
    adminMetrics: { rows: [] },
    opsMetrics: { rows: [] },
    engagementMetrics: { rows: [] },
    userNames: new Map<string, string | null>(),
    cancelledYesterday: { count: 0 },
    lapsedYesterday: { count: 0 },
    ...over,
  };
}

function assertNotIncludes(actual: string, expected: string, msg?: string) {
  assert(!actual.includes(expected), msg ?? `expected "${expected}" to be absent`);
}

// ---------------------------------------------------------------------------
// Three states per section: data · none · unreadable (never zeros).
// ---------------------------------------------------------------------------

Deno.test("all-quiet day renders 'none' for every section, no unreadable marker", () => {
  const text = buildDigestText(input());
  assertStringIncludes(text, "PRO image reads: none");
  assertStringIncludes(text, "PRO video reads: none");
  assertStringIncludes(text, "Free image reads (lifetime): none");
  assertStringIncludes(text, "<b>Top users</b>: none");
  assertStringIncludes(text, "<b>Alerts yesterday</b>: none");
  assertNotIncludes(text, "unreadable");
  assertNotIncludes(text, "⚠");
});

Deno.test("an unreadable usage section renders the marker and NEVER a zero or 'none' for its keys", () => {
  const text = buildDigestText(input({ windowed: { unreadable: "permission denied" } }));
  assertStringIncludes(text, "⚠ usage ledger unreadable: permission denied");
  assertNotIncludes(text, "PRO image reads: none");
  assertNotIncludes(text, "PRO image reads: 0");
  // The other two sections are independent and still render.
  assertStringIncludes(text, "Free image reads (lifetime): none");
  assertStringIncludes(text, "<b>Alerts yesterday</b>: none");
});

Deno.test("unreadable lifetime and alerts sections each carry their own marker", () => {
  const text = buildDigestText(input({
    lifetime: { unreadable: "timeout" },
    alerts: { unreadable: "relation missing" },
  }));
  assertStringIncludes(text, "⚠ lifetime meters unreadable: timeout");
  assertStringIncludes(text, "⚠ alerts unreadable: relation missing");
  assertStringIncludes(text, "PRO image reads: none");
});

Deno.test("the unreadable reason is HTML-escaped and bounded", () => {
  const text = buildDigestText(input({ windowed: { unreadable: "<b>" + "x".repeat(500) } }));
  assertStringIncludes(text, "⚠ usage ledger unreadable: &lt;b&gt;");
  assertNotIncludes(text, "unreadable: <b>");
  assert(text.length < 1500, "a 500-char reason must be cut, not pasted whole");
});

// ---------------------------------------------------------------------------
// Counting: totals, users, at-cap (>=, not >), lifetime vs windowed.
// ---------------------------------------------------------------------------

Deno.test("totals, distinct users and at-cap use `used >= cap`", () => {
  const text = buildDigestText(input({
    windowed: {
      rows: [
        row(U1, "pro_image_daily", 50), // at cap
        row(U2, "pro_image_daily", 49), // one under — NOT at cap
        row(U1, "pro_video_daily", 11), // over cap still counts as at cap
      ],
    },
  }));
  assertStringIncludes(text, "PRO image reads: 99 (2 users) · at cap 50: 1");
  assertStringIncludes(text, "PRO video reads: 11 (1 user) · at cap 10: 1");
});

Deno.test("keys without a single cap (food_text, sub-day buckets) are totals-only on the Also line", () => {
  const text = buildDigestText(input({
    windowed: {
      rows: [
        row(U1, "food_text", 7),
        row(U2, "food_text", 200),
        row(U1, "delete_account", 1, `${DAY}T19:00:00+00:00`),
        row(U1, "delete_account", 2, `${DAY}T20:00:00+00:00`),
        row(U2, "verify_payment", 3, `${DAY}T19:10:00+00:00`),
      ],
    },
  }));
  assertStringIncludes(text, "Also: Food text 207 · delete-account 3 · verify-payment 3");
  assertNotIncludes(text, "Food text:");
  assertNotIncludes(text, "at cap 200");
});

Deno.test("lifetime rows are reported as users MOVED and at-ceiling, never as a day total", () => {
  const text = buildDigestText(input({
    lifetime: {
      rows: [
        row(U1, "free_image_analysis", 5, LIFETIME_WINDOW),
        row(U2, "free_image_analysis", 2, LIFETIME_WINDOW),
        row(U1, "weekly_report_free", 1, LIFETIME_WINDOW),
      ],
    },
  }));
  // "reached … yesterday", not "at": the rows are yesterday's MOVERS, and a
  // refusal past the cap never touches updated_at, so a mover at the ceiling
  // reached it yesterday — the users already parked there are not in view.
  assertStringIncludes(text, "Free image reads (lifetime): 2 users moved · reached 5/5 yesterday: 1");
  assertStringIncludes(text, "Weekly report (free) (lifetime): 1 user moved · reached 1/1 yesterday: 1");
  assertNotIncludes(text, "at 5/5");
  // A lifetime row handed to the WINDOWED section would be a windowing bug in
  // the handler; the renderer keeps the two families apart by kind, so a
  // lifetime key never appears in the windowed block even if rows carry it.
  const crossed = buildDigestText(input({
    windowed: { rows: [row(U1, "free_image_analysis", 5, LIFETIME_WINDOW)] },
  }));
  assertStringIncludes(crossed, "Free image reads (lifetime): none");
  assertNotIncludes(crossed, "Free image reads: 5");
});

Deno.test("a quota_key DIGEST_KEYS does not list is SURFACED with its total, never silently dropped (L1)", () => {
  // "Ignored" and "none" are indistinguishable on the message; a new
  // consumer (or a misspelt key) is exactly what the founder must see.
  const text = buildDigestText(input({
    windowed: { rows: [row(U1, "not_a_key", 99), row(U2, "not_a_key", 1), row(U1, "b_key<", 2)] },
  }));
  assertStringIncludes(text, "⚠ unlisted keys: b_key&lt; 2 · not_a_key 100 — add to DIGEST_KEYS");
  // And the unlisted usage still ranks the user.
  assertStringIncludes(text, `${U1.slice(0, 8)} ×101`);
  // No unlisted line at all when every key is known.
  const clean = buildDigestText(input({ windowed: { rows: [row(U1, "chat_app", 3)] } }));
  assertNotIncludes(clean, "unlisted");
  // The lifetime section has its own line.
  const life = buildDigestText(input({ lifetime: { rows: [row(U1, "ghost_lifetime", 4, LIFETIME_WINDOW)] } }));
  assertStringIncludes(life, "⚠ unlisted lifetime keys: ghost_lifetime 1 user moved — add to DIGEST_KEYS");
});

Deno.test("an unlisted LIFETIME key reports MOVERS, never a summed cumulative counter (B-pass 2026-09-13)", () => {
  // Two DIFFERENT users, each with their own cumulative lifetime `used` —
  // summing those counters (the windowed-section behaviour) would print a
  // number that reads as "yesterday's activity" but is actually two
  // different point-in-time totals added together. The listed lifetime
  // branch is already hardened against exactly this; the unlisted fallback
  // must be too.
  const text = buildDigestText(input({
    lifetime: {
      rows: [
        row(U1, "ghost_lifetime", 100, LIFETIME_WINDOW),
        row(U2, "ghost_lifetime", 5, LIFETIME_WINDOW),
      ],
    },
  }));
  assertStringIncludes(text, "⚠ unlisted lifetime keys: ghost_lifetime 2 users moved — add to DIGEST_KEYS");
  assertNotIncludes(text, "105");
  // The WINDOWED section, by contrast, still sums — that total IS a bounded
  // day's activity, not a running counter.
  const windowed = buildDigestText(input({
    windowed: { rows: [row(U1, "not_a_key", 99), row(U2, "not_a_key", 1)] },
  }));
  assertStringIncludes(windowed, "⚠ unlisted keys: not_a_key 100 — add to DIGEST_KEYS");
});

// ---------------------------------------------------------------------------
// Top users: 8-char prefixes, sorted, capped, never a whole uuid.
// ---------------------------------------------------------------------------

Deno.test("top users shows 8-char id prefixes sorted by usage and never a whole uuid " +
    "when no name is available (B2 — no userNames entry for either user)", () => {
  const text = buildDigestText(input({
    windowed: {
      rows: [
        row(U1, "pro_image_daily", 3),
        row(U1, "chat_app", 4),
        row(U2, "chat_app", 10),
      ],
    },
  }));
  // B2 (observation-batch-and-digest-redesign): the label dropped the
  // literal "(id prefix)" suffix because the value shown is no longer
  // always an id prefix — it is a first name when userNames has one, the
  // id prefix otherwise. This fixture supplies no userNames map (the
  // input() helper defaults it to an empty Map), so every entry still
  // falls back to the id-prefix format, which is what this test pins.
  assertStringIncludes(text, "<b>Top users</b>: 9f8e7d6c ×10 · 0a1b2c3d ×7");
  assertNotIncludes(text, U1);
  assertNotIncludes(text, U2);
  assertEquals(idPrefix(U1), "0a1b2c3d");
});

Deno.test("top users is capped at 5", () => {
  const rows: UsageRow[] = [];
  for (let i = 0; i < 8; i++) {
    rows.push(row(`user${i}xxxx-0000-4000-8000-000000000000`, "chat_app", 8 - i));
  }
  const text = buildDigestText(input({ windowed: { rows } }));
  const line = text.split("\n").find((l) => l.startsWith("<b>Top users</b>"))!;
  assertEquals(line.split(" · ").length, 5);
  assertStringIncludes(line, "user0xxx ×8");
  assertNotIncludes(line, "user5xxx");
});

// ---------------------------------------------------------------------------
// Alerts: escaping, IST clock, the 10-line cap, the 4096 ceiling.
// ---------------------------------------------------------------------------

Deno.test("alert fields are HTML-escaped and stamped in IST", () => {
  const text = buildDigestText(input({
    alerts: {
      rows: [{
        detected_at: "2026-09-11T18:45:00+00:00",
        source: "alert_<cron>",
        severity: "warn",
        summary: "a & b > c",
      }],
    },
  }));
  assertStringIncludes(text, "<b>Alerts yesterday</b> (1):");
  assertStringIncludes(text, "00:15 [warn] alert_&lt;cron&gt; — a &amp; b &gt; c");
  assertNotIncludes(text, "alert_<cron>");
});

Deno.test("more than 10 alerts collapses to 10 lines plus a '+N more' tail", () => {
  const rows = Array.from({ length: 14 }, (_, i) => ({
    detected_at: `2026-09-11T${String(19 + Math.floor(i / 10)).padStart(2, "0")}:${String(i % 10).padStart(2, "0")}:00+00:00`,
    source: `src${i}`,
    severity: "info",
    summary: `s${i}`,
  }));
  const text = buildDigestText(input({ alerts: { rows } }));
  assertStringIncludes(text, "<b>Alerts yesterday</b> (14):");
  assertEquals(text.split("\n").filter((l) => /^\d\d:\d\d \[info\]/.test(l)).length, MAX_ALERT_LINES);
  assertStringIncludes(text, "… +4 more");
  assertNotIncludes(text, "src13");
});

Deno.test("the message never exceeds Telegram's 4096-char ceiling", () => {
  const rows = Array.from({ length: 10 }, (_, i) => ({
    detected_at: "2026-09-11T19:00:00+00:00",
    source: `src${i}`,
    severity: "critical",
    summary: "y".repeat(900),
  }));
  const text = buildDigestText(input({ alerts: { rows } }));
  assert(text.length <= TELEGRAM_MAX_CHARS, `got ${text.length}`);
  assertStringIncludes(text, "… (truncated)");
});

Deno.test("the alerts header carries the SERVER count, and the tail counts against it (L22)", () => {
  // The read is capped at the lines rendered, so a 73-alert day arrives as
  // 10 rows + total 73. A header that counted the page would say "(10)".
  const rows = Array.from({ length: MAX_ALERT_LINES }, (_, i) => ({
    detected_at: "2026-09-11T19:00:00+00:00",
    source: `src${i}`,
    severity: "warn",
    summary: `s${i}`,
  }));
  const text = buildDigestText(input({ alerts: { rows, total: 73 } }));
  assertStringIncludes(text, "<b>Alerts yesterday</b> (73):");
  assertStringIncludes(text, "… +63 more");
  // A total equal to the page length has no tail; an absent total falls
  // back to the page (the pre-count contract, so a fake without counts
  // still renders).
  const exact = buildDigestText(input({ alerts: { rows: rows.slice(0, 3), total: 3 } }));
  assertStringIncludes(exact, "<b>Alerts yesterday</b> (3):");
  assertNotIncludes(exact, "more");
  const noCount = buildDigestText(input({ alerts: { rows: rows.slice(0, 3) } }));
  assertStringIncludes(noCount, "<b>Alerts yesterday</b> (3):");
});

Deno.test("truncation cuts on a LINE boundary — every surviving line is a whole line, tags balanced (L21)", () => {
  const rows = Array.from({ length: MAX_ALERT_LINES }, (_, i) => ({
    detected_at: "2026-09-11T19:00:00+00:00",
    source: `src${i}`,
    severity: "critical",
    // Odd lengths so no line ends exactly at the limit by accident; entities
    // and angle brackets so a mid-line cut would leave `&am` or `&lt;b` dangling.
    summary: `<b>${"y & z".repeat(150 + i)}</b>`,
  }));
  const full = buildDigestText(input({ alerts: { rows } }));
  assert(full.length <= TELEGRAM_MAX_CHARS);
  const marker = "\n… (truncated)";
  assert(full.endsWith(marker), "the marker must be the last line");
  const kept = full.slice(0, full.length - marker.length);
  // Every kept alert line must be one of the renderer's whole lines
  // verbatim, so nothing was cut mid-line.
  const esc = (t: string) => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const wholeLines = new Set(rows.map((a) => `00:30 [critical] ${a.source} — ${esc(a.summary)}`));
  const alertLines = kept.split("\n").filter((l) => l.startsWith("00:30 ["));
  assert(alertLines.length >= 1, "at least one alert line must survive");
  for (const l of alertLines) assert(wholeLines.has(l), `cut mid-line: …${l.slice(-40)}`);
  // No dangling entity at the cut.
  const last = kept.split("\n").at(-1) ?? "";
  assert(!/&[a-z]*$/.test(last), `dangling entity: …${last.slice(-20)}`);
});

Deno.test("istClock converts a UTC stamp to IST and is empty for garbage", () => {
  assertEquals(istClock("2026-09-11T18:45:00+00:00"), "00:15 ");
  assertEquals(istClock("2026-09-11T02:30:00Z"), "08:00 ");
  assertEquals(istClock("not a date"), "");
});

// ---------------------------------------------------------------------------
// The IST day window.
// ---------------------------------------------------------------------------

Deno.test("istYesterdayWindow flips at 18:30:00Z exactly and returns ISO-Z strings", () => {
  const before = istYesterdayWindow(new Date("2026-09-12T18:29:59Z"));
  assertEquals(before, {
    yStart: "2026-09-10T18:30:00.000Z",
    tStart: "2026-09-11T18:30:00.000Z",
    label: "2026-09-11",
  });
  const after = istYesterdayWindow(new Date("2026-09-12T18:30:00Z"));
  assertEquals(after, {
    yStart: "2026-09-11T18:30:00.000Z",
    tStart: "2026-09-12T18:30:00.000Z",
    label: "2026-09-12",
  });
  // The 08:00-IST cron fires at 02:30Z; on that tick "yesterday" is the IST
  // day that ended 8 hours earlier.
  const cron = istYesterdayWindow(new Date("2026-09-13T02:30:00Z"));
  assertEquals(cron.label, "2026-09-12");
});

Deno.test("the header names the IST day being reported", () => {
  const text = buildDigestText(input({ dayLabel: "2026-09-11" }));
  // 2026-09-11 is a Friday (2026-01-01 was a Thursday; day 254 of the year).
  assertStringIncludes(text, "Fri 11 Sep 2026 (IST day)");
});

// ---------------------------------------------------------------------------
// Secret hygiene: a fetch error's message embeds the bot URL. Never surface it.
// ---------------------------------------------------------------------------

Deno.test("telegramErrorSummary carries the error NAME only — never the URL-bearing message", () => {
  const leaky = new TypeError(
    "error sending request for url (https://api.telegram.org/bot123456789:AAHfakeTOKENvalue/sendMessage)",
  );
  const summary = telegramErrorSummary(leaky);
  assertEquals(summary, "telegram send threw TypeError");
  assertNotIncludes(summary, "api.telegram.org");
  assertNotIncludes(summary, "123456789:AA");
  assertNotIncludes(summary, "/bot");
  assertEquals(telegramErrorSummary("string thrown"), "telegram send threw string");
});

Deno.test("sendTelegram: a fetch that THROWS a URL-bearing error yields a summary with no token, no host (L40)", async () => {
  const token = "123456789:AAHfakeTOKENvalue";
  const throwing = ((input: RequestInfo | URL) => {
    const url = typeof input === "string" ? input : (input as URL).href ?? (input as Request).url;
    return Promise.reject(new TypeError(`error sending request for url (${url})`));
  }) as typeof fetch;
  const res = await sendTelegram(token, "4242", "hi", throwing);
  assert(!res.ok);
  assertEquals(res.summary, "telegram send threw TypeError");
  assertNotIncludes(res.summary, token);
  assertNotIncludes(res.summary, "api.telegram.org");
  assertNotIncludes(res.summary, "4242");
});

Deno.test("sendTelegram: a non-2xx reply surfaces the status and Telegram's description, bounded", async () => {
  const seen: { url: string; body: string }[] = [];
  const rejecting = ((input: RequestInfo | URL, init?: RequestInit) => {
    seen.push({ url: String(input), body: String(init?.body ?? "") });
    return Promise.resolve(
      new Response(JSON.stringify({ ok: false, description: "Bad Request: can't parse entities " + "x".repeat(300) }), { status: 400 }),
    );
  }) as typeof fetch;
  const res = await sendTelegram("tok", "4242", "<b>hi", rejecting);
  assert(!res.ok);
  assertStringIncludes(res.summary, "telegram HTTP 400: ");
  assertStringIncludes(res.summary, "can't parse entities");
  assert(res.summary.length <= "telegram HTTP 400: ".length + 200, `bounded: ${res.summary.length}`);
  // The request itself: HTML parse mode, previews off, the chat id in the body.
  assertEquals(seen.length, 1);
  assertStringIncludes(seen[0].url, "/bottok/sendMessage");
  const sent = JSON.parse(seen[0].body);
  assertEquals(sent.parse_mode, "HTML");
  assertEquals(sent.disable_web_page_preview, true);
  assertEquals(sent.chat_id, "4242");
  assertEquals(sent.text, "<b>hi");
});

Deno.test("MAX_PAGES bounds every ledger read at 200 pages (L31)", () => {
  assertEquals(MAX_PAGES, 200);
});

Deno.test("escapeHtml covers exactly the three Telegram-HTML metacharacters", () => {
  assertEquals(escapeHtml("<a & b>"), "&lt;a &amp; b&gt;");
  assertEquals(escapeHtml("plain"), "plain");
});

Deno.test("DIGEST_KEYS has no duplicate keys and every lifetime key has a cap", () => {
  const keys = DIGEST_KEYS.map((k) => k.key);
  assertEquals(new Set(keys).size, keys.length);
  for (const k of DIGEST_KEYS) {
    if (k.kind === "lifetime") assert(k.cap !== undefined, `${k.key} needs a cap`);
    if (k.kind === "subday") assert(k.cap === undefined, `${k.key} must not carry a cap`);
  }
});

// ---------------------------------------------------------------------------
// The READ SHAPES — which table and which columns each section filters on.
// B-pass 2026-09-13 finding 2: with the reads inlined in the handler, mutating
// the lifetime filter's `updated_at` to `window_start` (a filter that can
// never match — every lifetime row's window_start is the epoch sentinel)
// reddened NOTHING. The lifetime section would have read "none" forever with
// no error. A recording fake client now drives `readDigestSections` and pins
// every filter call per section.
// ---------------------------------------------------------------------------

type Call = [string, ...unknown[]];

/** A recording stand-in for the supabase-js query builder + client. */
function fakeClient(opts: {
  rows?: Record<string, unknown[]>;
  failTables?: string[];
  /** Exact server-side count a table reports (the `{ count: "exact" }` reply). */
  counts?: Record<string, number>;
}) {
  const calls: Record<string, Call[][]> = {};
  const served: Record<string, number> = {};
  const client = {
    from(table: string) {
      const chain: Call[] = [];
      (calls[table] ??= []).push(chain);
      // First builder for a table serves its rows; later ones serve [] so
      // fetchAllPages sees the empty page that ends its loop.
      const n = served[table] ?? 0;
      served[table] = n + 1;
      const failing = (opts.failTables ?? []).includes(table);
      const data = n === 0 ? (opts.rows?.[table] ?? []) : [];
      const builder: Record<string, unknown> = {};
      for (const m of ["select", "eq", "gte", "lt", "order", "limit", "range"]) {
        builder[m] = (...args: unknown[]) => {
          chain.push([m, ...args]);
          return builder;
        };
      }
      const count = opts.counts?.[table] ?? null;
      builder.then = (resolve: (v: unknown) => void) =>
        resolve(
          failing
            ? { data: null, error: { message: `${table} unreadable` }, count: null }
            : { data, error: null, count },
        );
      return builder;
    },
  };
  return { client, calls };
}

const WINDOW = { yStart: "2026-09-10T18:30:00.000Z", tStart: "2026-09-11T18:30:00.000Z" };

/** The filter calls (eq/gte/lt) of the FIRST builder for a table. */
function filtersOf(calls: Record<string, Call[][]>, table: string, nth = 0): Call[] {
  return calls[table][nth].filter(([m]) => m === "eq" || m === "gte" || m === "lt");
}

Deno.test("windowed rows are filtered by window_start on [yStart, tStart)", async () => {
  const { client, calls } = fakeClient({});
  await readDigestSections(client, WINDOW);
  const usage = calls["usage_counters"];
  assert(usage.length >= 2, "expected a windowed AND a lifetime read");
  assertEquals(filtersOf(calls, "usage_counters", 0), [
    ["gte", "window_start", WINDOW.yStart],
    ["lt", "window_start", WINDOW.tStart],
  ]);
});

Deno.test("lifetime rows are pinned to the epoch window_start and filtered by updated_at", async () => {
  const { client, calls } = fakeClient({});
  await readDigestSections(client, WINDOW);
  // The lifetime read is the second usage_counters builder (its first page).
  const lifetimeIdx = calls["usage_counters"].findIndex((c) =>
    c.some(([m, col]) => m === "eq" && col === "window_start")
  );
  assert(lifetimeIdx >= 0, "no lifetime read found");
  assertEquals(filtersOf(calls, "usage_counters", lifetimeIdx), [
    ["eq", "window_start", LIFETIME_WINDOW],
    ["gte", "updated_at", WINDOW.yStart],
    ["lt", "updated_at", WINDOW.tStart],
  ]);
});

Deno.test("alerts are filtered by detected_at, ordered ascending, capped at the lines RENDERED with an exact count", async () => {
  const { client, calls } = fakeClient({});
  await readDigestSections(client, WINDOW);
  const chain = calls["alerts"][0];
  assertEquals(filtersOf(calls, "alerts", 0), [
    ["gte", "detected_at", WINDOW.yStart],
    ["lt", "detected_at", WINDOW.tStart],
  ]);
  assertEquals(chain.find(([m]) => m === "order"), ["order", "detected_at", { ascending: true }]);
  assertEquals(chain.find(([m]) => m === "limit"), ["limit", MAX_ALERT_LINES]);
  assertEquals(chain[0], ["select", "detected_at, source, severity, summary", { count: "exact" }]);
});

Deno.test("the alerts section carries the server count as `total`, and omits it when the server sends none", async () => {
  const rows = Array.from({ length: 3 }, (_, i) => ({
    detected_at: "2026-09-11T19:00:00+00:00",
    source: `s${i}`,
    severity: "warn",
    summary: "x",
  }));
  const counted = fakeClient({ rows: { alerts: rows }, counts: { alerts: 73 } });
  const a = (await readDigestSections(counted.client, WINDOW)).alerts;
  assert("rows" in a);
  assertEquals(a.rows.length, 3);
  assertEquals(a.total, 73);
  const uncounted = fakeClient({ rows: { alerts: rows } });
  const b = (await readDigestSections(uncounted.client, WINDOW)).alerts;
  assert("rows" in b);
  assertEquals(b.total, undefined);
});

Deno.test("every section selects exactly the columns the renderer reads", async () => {
  const { client, calls } = fakeClient({});
  await readDigestSections(client, WINDOW);
  for (const chain of calls["usage_counters"]) {
    assertEquals(chain[0], ["select", "user_id, quota_key, window_start, used, updated_at"]);
  }
  assertEquals(calls["alerts"][0][0], ["select", "detected_at, source, severity, summary", { count: "exact" }]);
});

Deno.test("a failing table makes ONLY its section unreadable; the others still carry rows", async () => {
  const { client } = fakeClient({
    rows: { alerts: [{ detected_at: "2026-09-11T00:00:00+00:00", source: "s", severity: "P2", summary: "x" }] },
    failTables: ["usage_counters"],
  });
  const out = await readDigestSections(client, WINDOW);
  assert("unreadable" in out.windowed, "windowed must be unreadable");
  assert("unreadable" in out.lifetime, "lifetime must be unreadable");
  assert("rows" in out.alerts && out.alerts.rows.length === 1, "alerts must still read");
  assertStringIncludes((out.windowed as { unreadable: string }).unreadable, "usage_counters unreadable");
});

Deno.test("a failing alerts table makes the alerts section unreadable — never 'none'", async () => {
  // Mutation n4 (B-pass follow-up): `if (error) return []` in the alerts read
  // reddened nothing while only usage_counters was ever failed. The mirror.
  const { client } = fakeClient({
    rows: { usage_counters: [row(U1, "chat_app", 2)] },
    failTables: ["alerts"],
  });
  const out = await readDigestSections(client, WINDOW);
  assert("unreadable" in out.alerts, "alerts must be unreadable, not an empty list");
  assertStringIncludes((out.alerts as { unreadable: string }).unreadable, "alerts unreadable");
  assert("rows" in out.windowed && out.windowed.rows.length === 1, "usage must still read");
  // And the rendered message carries the marker, not "Alerts yesterday: none".
  const text = buildDigestText({
    dayLabel: DAY,
    subscriptions: { rows: [] },
    expiringSoon: { count7d: 0, count30d: 0 },
    signupsYesterday: { count: 0 },
    adminMetrics: { rows: [] },
    opsMetrics: { rows: [] },
    engagementMetrics: { rows: [] },
    userNames: new Map<string, string | null>(),
    cancelledYesterday: { count: 0 },
    lapsedYesterday: { count: 0 },
    ...out,
  });
  assertStringIncludes(text, "⚠ alerts unreadable");
  assertNotIncludes(text, "<b>Alerts yesterday</b>: none");
});

Deno.test("rows served by the client reach the sections unchanged", async () => {
  const r = row(U1, "pro_image_daily", 3);
  const { client } = fakeClient({ rows: { usage_counters: [r] } });
  const out = await readDigestSections(client, WINDOW);
  // The fake serves the same first page to whichever usage_counters builder
  // comes first — the windowed read — and [] to the lifetime one.
  assertEquals(out.windowed, { rows: [r] });
  assertEquals(out.lifetime, { rows: [] });
});

// ---------------------------------------------------------------------------
// B1/B2/B3 (observation-batch-and-digest-redesign, 2026-09-21)
// ---------------------------------------------------------------------------

function adminMetricsRow(over: Partial<AdminMetricsRow> = {}): AdminMetricsRow {
  return {
    total_users: 32,
    signups_today_ist: 999, // deliberately absurd — must NEVER be rendered
    signups_7d: 4,
    signups_30d: 11,
    pro_active: 9,
    pro_expired: 777, // deliberately absurd — must NEVER be rendered
    free_users: 23,
    active_subscriptions: 9,
    active_last_7d: 6,
    generated_at: "2026-09-11T02:30:00Z",
    ...over,
  };
}

function opsMetricsRow(over: Partial<OpsMetricsRow> = {}): OpsMetricsRow {
  return {
    client_errors_today: 888, // deliberately absurd — must NEVER be rendered
    client_errors_7d: 42,
    open_alerts_count: 2,
    cron_failures_24h: 0,
    generated_at: "2026-09-11T02:30:00Z",
    ...over,
  };
}

function engagementMetricsRow(
  over: Partial<EngagementMetricsRow> = {},
): EngagementMetricsRow {
  return {
    workouts_logged_today: 111, // deliberately absurd — must NEVER be rendered
    food_logs_today: 222, // deliberately absurd — must NEVER be rendered
    ai_messages_today: 333, // deliberately absurd — must NEVER be rendered
    streak_maintained_current_week: 12,
    holds_started_today: 444, // deliberately absurd — must NEVER be rendered
    holds_started_7d: 3,
    holders_total: 8,
    generated_at: "2026-09-11T02:30:00Z",
    ...over,
  };
}

Deno.test("B1: renders adminMetrics' safe fields, NEVER signups_today_ist or pro_expired", () => {
  const text = buildDigestText(input({ adminMetrics: { rows: [adminMetricsRow()] } }));
  assertStringIncludes(text, "7d: 4");
  assertStringIncludes(text, "30d: 11");
  assertStringIncludes(text, "Total: 32");
  assertStringIncludes(text, "PRO: 9");
  assertStringIncludes(text, "Free: 23");
  assertStringIncludes(text, "Active subscriptions: 9");
  assertStringIncludes(text, "active last 7d: 6");
  assertNotIncludes(text, "999", "signups_today_ist must never be rendered");
  assertNotIncludes(text, "777", "pro_expired must never be rendered — B3 owns churn");
});

Deno.test("B1: renders opsMetrics' safe fields, NEVER client_errors_today", () => {
  const text = buildDigestText(input({ opsMetrics: { rows: [opsMetricsRow()] } }));
  assertStringIncludes(text, "Client errors (7d): 42");
  assertStringIncludes(text, "Open alerts: 2");
  assertStringIncludes(text, "cron failures (24h): 0");
  assertNotIncludes(text, "888", "client_errors_today must never be rendered");
});

Deno.test("B1: renders engagementMetrics' safe fields, NEVER the four *_today fields", () => {
  const text = buildDigestText(
    input({ engagementMetrics: { rows: [engagementMetricsRow()] } }),
  );
  assertStringIncludes(text, "Streak maintained (current week): 12");
  assertStringIncludes(text, "Hold starts (7d): 3");
  assertStringIncludes(text, "total ever: 8");
  for (const absurd of ["111", "222", "333", "444"]) {
    assertNotIncludes(text, absurd, `*_today field (${absurd}) must never be rendered`);
  }
});

Deno.test("B1: adminMetrics/opsMetrics/engagementMetrics each render their OWN " +
    "unreadable marker independently, never a silent zero", () => {
  const text = buildDigestText(input({
    adminMetrics: { unreadable: "admin rpc timeout" },
    opsMetrics: { unreadable: "ops rpc timeout" },
    engagementMetrics: { unreadable: "engagement rpc timeout" },
  }));
  assertStringIncludes(text, "admin rpc timeout");
  assertStringIncludes(text, "ops rpc timeout");
  assertStringIncludes(text, "engagement rpc timeout");
});

Deno.test("B1: new signups (yesterday) is genuinely windowed, independent of adminMetrics", () => {
  const text = buildDigestText(input({ signupsYesterday: { count: 5 } }));
  assertStringIncludes(text, "<b>New signups (yesterday)</b>\n5");
});

Deno.test("B2: a user with a real, non-empty full_name shows their first name, escaped", () => {
  const text = buildDigestText(input({
    windowed: { rows: [row(U1, "chat_app", 10)] },
    userNames: new Map([[U1, "Priya"]]),
  }));
  assertStringIncludes(text, "<b>Top users</b>: Priya ×10");
  assertNotIncludes(text, idPrefix(U1));
});

Deno.test("B2: a name is HTML-escaped before interpolation into the Telegram message", () => {
  // Not a realistic full_name, but the render site must not trust it — same
  // discipline every other user-controlled string in this file already gets.
  const text = buildDigestText(input({
    windowed: { rows: [row(U1, "chat_app", 10)] },
    userNames: new Map([[U1, "<b>hacked</b>"]]),
  }));
  assertStringIncludes(text, "&lt;b&gt;hacked&lt;/b&gt;");
  assertNotIncludes(text, "<b>hacked</b>");
});

Deno.test("B2: userNames absent for a user (opted out via private_mode, or empty " +
    "full_name) falls back to the pre-existing id-prefix format", () => {
  const text = buildDigestText(input({
    windowed: { rows: [row(U1, "chat_app", 10)] },
    userNames: new Map([[U1, null]]),
  }));
  assertStringIncludes(text, `<b>Top users</b>: ${idPrefix(U1)} ×10`);
});

Deno.test("B3: computeNewMrr prices monthly/yearly correctly (yearly ÷12 — " +
    "MRR is a monthly figure), treats referral_trial as a KNOWN zero-price " +
    "plan (not unknown), and excludes a genuinely unrecognized plan from " +
    "the price sum while counting it as unknown", () => {
  const rows: SubscriptionRow[] = [
    { plan: "monthly", created_at: "2026-09-11T00:00:00Z" },
    { plan: "monthly", created_at: "2026-09-11T00:00:00Z" },
    { plan: "yearly", created_at: "2026-09-11T00:00:00Z" },
    { plan: "referral_trial", created_at: "2026-09-11T00:00:00Z" },
    { plan: "some_future_plan", created_at: "2026-09-11T00:00:00Z" },
  ];
  const mrr = computeNewMrr(rows);
  // Hermes L1/L21 (2026-09-21): this assertion previously read
  // `349 + 349 + 2999` (= 3697) — summing the yearly BOOKING price raw
  // instead of dividing by 12, the exact pre-fix bug. Correct:
  // 2×349 + 2999/12 = 698 + 249.9166... = 947.9166... rounds to 948.
  assertEquals(mrr.rupees, 948);
  // referral_trial is a real, live plan value (discovered during the same
  // Hermes pass) deliberately priced at ₹0 — it must NOT inflate
  // unknownPlanCount, or the digest's own warning would tell the founder to
  // add a price for a free trial. Only some_future_plan is genuinely
  // unrecognized.
  assertEquals(mrr.unknownPlanCount, 1);
});

Deno.test("B3: New MRR renders with the gross-before-promo-discounts caveat, " +
    "and surfaces an unknown-plan warning for a genuinely unrecognized " +
    "plan — but never for referral_trial, a known free plan", () => {
  const text = buildDigestText(input({
    subscriptions: {
      rows: [
        { plan: "monthly", created_at: "2026-09-11T00:00:00Z" },
        { plan: "referral_trial", created_at: "2026-09-11T00:00:00Z" },
        { plan: "some_future_plan", created_at: "2026-09-11T00:00:00Z" },
      ],
    },
  }));
  // Only the one monthly plan prices in — referral_trial (known, ₹0) and
  // some_future_plan (unknown, ₹0) both contribute nothing to the sum.
  assertStringIncludes(text, "New MRR: ₹349 (gross, before promo discounts)");
  // Exactly 1 — referral_trial must not be double-counted into this warning
  // alongside the genuinely unrecognized plan (Hermes L1/L21, 2026-09-21).
  assertStringIncludes(text, "⚠ 1 subscription(s) with an unpriced plan value excluded from MRR");
});

Deno.test("B3: no unknown-plan warning line when every plan is recognized", () => {
  const text = buildDigestText(input({
    subscriptions: { rows: [{ plan: "yearly", created_at: "2026-09-11T00:00:00Z" }] },
  }));
  assertNotIncludes(text, "unpriced plan");
});

Deno.test("B3: Cancelled/Lapsed render their counts, always carry the " +
    "manual-cancellation-tracking-started caveat, and each fails " +
    "independently to 'unreadable' rather than a silent zero", () => {
  const readable = buildDigestText(
    input({ cancelledYesterday: { count: 2 }, lapsedYesterday: { count: 1 } }),
  );
  assertStringIncludes(readable, "Cancelled (manual): 2");
  assertStringIncludes(readable, "Lapsed (PRO access expired, not renewed): 1");
  assertStringIncludes(readable, "Manual-cancellation tracking started 2026-09-21");

  const degraded = buildDigestText(input({
    cancelledYesterday: { unreadable: "column cancelled_at does not exist" },
    lapsedYesterday: { count: 0 },
  }));
  assertStringIncludes(degraded, "column cancelled_at does not exist");
  // The sibling section still reads fine — one section's failure never
  // blanks another (this file's own three-state contract).
  assertStringIncludes(degraded, "Lapsed (PRO access expired, not renewed): 0");
});

// --- gatherDigestInput wiring (B1/B2) — a hand-rolled fake with .rpc() and
// .in() support, distinct from the shared `fakeClient` above (which is
// scoped to readDigestSections's narrower select/eq/gte/lt/order/limit/range
// surface and deliberately not widened here, to avoid destabilizing its 33
// existing call sites for a need only this block has). ---

/**
 * Extends the `.from()`/chain shape with `.in()` (B2's name-lookup batch
 * query, via `fetchAllByIds`) and `.rpc()` (B1's 3 metrics functions). Kept
 * separate from `fakeClient` above rather than widening it in place, so its
 * 33 existing `readDigestSections`-level call sites are never put at risk by
 * a change only this block needs.
 *
 * Unlike `fakeClient`'s "first builder call serves rows, later ones serve
 * []" trick (needed there because its `.range()` is a no-op terminal), this
 * builder does REAL slicing: every fresh `.from(table)` call starts from
 * that table's full configured row set (optionally narrowed by `.in()`), and
 * `.range(from, to)` slices it. That makes `fetchAllPages`/`fetchAllByIds`
 * terminate correctly (a `.range()` past the end returns `[]`) without
 * depending on call ORDER — load-bearing here because `windowed` and
 * `lifetime` (and, for `.in()`, `users` and `coach_memory`) issue
 * INDEPENDENT `.from()` calls against the same table, each of which must see
 * the full configured set on its own first page, not whichever call
 * happened to run first.
 */
function wiringFakeClient(opts: {
  rows?: Record<string, unknown[]>;
  rpcResults?: Record<string, unknown[]>;
  users?: { id: string; full_name: string | null }[];
  coachMemory?: { user_id: string; private_mode: boolean }[];
}) {
  const rpcCalls: string[] = [];
  const inCalls: { table: string; column: string; values: unknown[] }[] = [];
  const client = {
    from(table: string) {
      let data: Record<string, unknown>[] =
        table === "users"
          ? ((opts.users ?? []) as unknown as Record<string, unknown>[])
          : table === "coach_memory"
          ? ((opts.coachMemory ?? []) as unknown as Record<string, unknown>[])
          : ((opts.rows?.[table] ?? []) as Record<string, unknown>[]);
      const builder: Record<string, unknown> = {};
      for (const m of ["select", "eq", "gte", "lt", "order", "not", "lte"]) {
        builder[m] = () => builder;
      }
      builder.in = (column: string, values: unknown[]) => {
        inCalls.push({ table, column, values });
        data = data.filter((row) => values.includes(row[column]));
        return builder;
      };
      builder.limit = (n: number) =>
        Promise.resolve({ data: data.slice(0, n), error: null, count: data.length });
      builder.range = (from: number, to: number) =>
        Promise.resolve({ data: data.slice(from, to + 1), error: null });
      // A query with no terminal `.range()`/`.limit()` call (e.g. a
      // `{count:'exact', head:true}` count-only read) is awaited directly —
      // resolve to the full (possibly `.in()`-narrowed) set.
      builder.then = (resolve: (v: unknown) => void) =>
        resolve({ data, error: null, count: data.length });
      return builder;
    },
    rpc(fn: string) {
      rpcCalls.push(fn);
      return Promise.resolve({ data: opts.rpcResults?.[fn] ?? [], error: null });
    },
  };
  return { client, rpcCalls, inCalls };
}

Deno.test("B1: gatherDigestInput calls all 3 metrics RPCs by their exact live names", async () => {
  const { client, rpcCalls } = wiringFakeClient({});
  // deno-lint-ignore no-explicit-any
  await gatherDigestInput(client as any, new Date("2026-09-11T08:00:00Z"));
  assert(rpcCalls.includes("founder_metrics_for_admin_api"));
  assert(rpcCalls.includes("founder_metrics_ops"));
  assert(rpcCalls.includes("founder_metrics_engagement"));
});

Deno.test("B1: a DigestClient with no rpc() degrades all 3 metrics sections to " +
    "unreadable instead of throwing out of gatherDigestInput", async () => {
  const { client } = fakeClient({});
  // deno-lint-ignore no-explicit-any
  const out = await gatherDigestInput(client as any, new Date("2026-09-11T08:00:00Z"));
  assert("unreadable" in out.adminMetrics);
  assert("unreadable" in out.opsMetrics);
  assert("unreadable" in out.engagementMetrics);
});

Deno.test("B2: gatherDigestInput's userNames map respects private_mode and " +
    "empty-full_name, batched over exactly the distinct user_ids in " +
    "windowed.rows", async () => {
  const { client, inCalls } = wiringFakeClient({
    rows: { usage_counters: [row(U1, "chat_app", 3), row(U2, "chat_app", 5)] },
    users: [
      { id: U1, full_name: "Priya Sharma" },
      { id: U2, full_name: "" },
    ],
    coachMemory: [{ user_id: U1, private_mode: true }],
  });
  // deno-lint-ignore no-explicit-any
  const out = await gatherDigestInput(client as any, new Date("2026-09-11T08:00:00Z"));
  assertEquals(out.userNames.get(U1), null, "private_mode=true must suppress the name");
  assertEquals(out.userNames.get(U2), null, "empty full_name must fall back to null");
  const userIdCall = inCalls.find((c) => c.table === "users");
  assert(userIdCall, "must query users.id with .in()");
  assertEquals(new Set(userIdCall!.values), new Set([U1, U2]));
});

Deno.test("Hermes L40 F3 (2026-09-21): a user with NO coach_memory row at all " +
    "defaults to SUPPRESSED, not shown — privacy-by-default, not privacy-by-" +
    "explicit-opt-out", async () => {
  const { client } = wiringFakeClient({
    rows: { usage_counters: [row(U1, "chat_app", 3), row(U3, "chat_app", 2)] },
    users: [
      { id: U1, full_name: "Priya Sharma" },
      // U3 has a real, non-empty name but NEVER opened the AI coach, so it
      // has no coach_memory row of any kind — the pre-fix logic only
      // suppressed a user with an EXPLICIT private_mode=true row, so an
      // absent row fell through to "shown". A user who never had a surface
      // to express the preference this control exists for must not be
      // treated as having opted IN by omission.
      { id: U3, full_name: "Rahul Verma" },
    ],
    coachMemory: [{ user_id: U1, private_mode: false }],
  });
  // deno-lint-ignore no-explicit-any
  const out = await gatherDigestInput(client as any, new Date("2026-09-11T08:00:00Z"));
  assertEquals(out.userNames.get(U1), "Priya", "explicit private_mode=false must show the name");
  assertEquals(
    out.userNames.get(U3),
    null,
    "no coach_memory row at all must default to suppressed, not shown",
  );
});

Deno.test("Hermes L23 #2 (2026-09-21): a full_name carrying control characters " +
    "or excess length is sanitized before rendering, not passed through raw", async () => {
  const { client } = wiringFakeClient({
    rows: { usage_counters: [row(U1, "chat_app", 3)] },
    users: [{ id: U1, full_name: "Priya\nSharma <script>" }],
    coachMemory: [{ user_id: U1, private_mode: false }],
  });
  // deno-lint-ignore no-explicit-any
  const out = await gatherDigestInput(client as any, new Date("2026-09-11T08:00:00Z"));
  const name = out.userNames.get(U1);
  assert(name !== null, "a sanitizable name must still render, not fall back to null");
  assert(!name!.includes("\n"), `sanitized name must not carry a newline, got ${JSON.stringify(name)}`);
  // sanitizeIdentifier caps at 32 chars before the .split(" ")[0] first-name
  // extraction runs on it — the first "word" of a newline-stripped string is
  // what should survive here.
  assertEquals(name, "Priya");
});

Deno.test("Hermes L23 #4 / L21 F4 (2026-09-21): both userNames fetchAllByIds " +
    "calls pass an explicit maxPages bound — a page count is invisible to " +
    "any fake DB client (it only ever sees .range() calls, never the loop " +
    "bound that decides how many to issue), so this is a source-pin, " +
    "narrowly scoped to userNamesRead's own body only", () => {
  const source = Deno.readTextFileSync(
    new URL("../_shared/founder_digest_content.ts", import.meta.url),
  );
  const start = source.indexOf("const userNamesRead");
  assert(start >= 0, "userNamesRead not found in source");
  const end = source.indexOf("\n  })();", start);
  assert(end > start, "could not find the end of the userNamesRead IIFE");
  const body = source.slice(start, end);
  const maxPagesCount = (body.match(/maxPages:\s*MAX_PAGES/g) ?? []).length;
  assertEquals(
    maxPagesCount,
    2,
    "expected exactly 2 maxPages: MAX_PAGES occurrences (users + coach_memory " +
      `fetchAllByIds calls) inside userNamesRead, found ${maxPagesCount}`,
  );
});
