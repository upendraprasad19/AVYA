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
  buildDigestText,
  DIGEST_KEYS,
  type DigestInput,
  escapeHtml,
  idPrefix,
  istClock,
  istYesterdayWindow,
  LIFETIME_WINDOW,
  MAX_ALERT_LINES,
  MAX_PAGES,
  readDigestSections,
  sendTelegram,
  TELEGRAM_MAX_CHARS,
  telegramErrorSummary,
  type UsageRow,
} from "./index.ts";

const DAY = "2026-09-11";
const U1 = "0a1b2c3d-1111-4222-8333-444455556666";
const U2 = "9f8e7d6c-1111-4222-8333-444455556666";

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

Deno.test("top users shows 8-char id prefixes sorted by usage and never a whole uuid", () => {
  const text = buildDigestText(input({
    windowed: {
      rows: [
        row(U1, "pro_image_daily", 3),
        row(U1, "chat_app", 4),
        row(U2, "chat_app", 10),
      ],
    },
  }));
  assertStringIncludes(text, "<b>Top users</b> (id prefix): 9f8e7d6c ×10 · 0a1b2c3d ×7");
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
