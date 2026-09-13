/**
 * Deno unit tests for `founder-digest`'s pure pieces (OI-153, T6).
 *
 * Run:
 *   deno test --no-check --allow-all --node-modules-dir=none supabase/functions/founder-digest/
 *
 * Scope: `buildDigestText`, `istYesterdayWindow`, `escapeHtml`, `idPrefix`,
 * `istClock`, `telegramErrorSummary`, `DIGEST_KEYS` — the serve handler is NOT
 * exercised here (needs live env + a bot). End-to-end verification is the
 * manual `net.http_post` in the plan's T9.
 *
 * ⚠ This file deliberately never spells the ledger table's name or the RPC's
 * name: test/contracts/usage_quota_ledger_writer_to_reader_test.dart walks
 * every .ts under supabase/functions/ (comment-stripped) and allowlists direct
 * readers BY FILE, and this file is not a reader.
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
  assertStringIncludes(text, "Free image reads (lifetime): 2 users moved · at 5/5: 1");
  assertStringIncludes(text, "Weekly report (free) (lifetime): 1 user moved · at 1/1: 1");
  // A lifetime row handed to the WINDOWED section would be a windowing bug in
  // the handler; the renderer keeps the two families apart by kind, so a
  // lifetime key never appears in the windowed block even if rows carry it.
  const crossed = buildDigestText(input({
    windowed: { rows: [row(U1, "free_image_analysis", 5, LIFETIME_WINDOW)] },
  }));
  assertStringIncludes(crossed, "Free image reads (lifetime): none");
  assertNotIncludes(crossed, "Free image reads: 5");
});

Deno.test("an unknown quota_key in the rows is ignored, not rendered", () => {
  const text = buildDigestText(input({ windowed: { rows: [row(U1, "not_a_key", 99)] } }));
  assertNotIncludes(text, "not_a_key");
  assertNotIncludes(text, "99");
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
        severity: "P1",
        summary: "a & b > c",
      }],
    },
  }));
  assertStringIncludes(text, "<b>Alerts yesterday</b> (1):");
  assertStringIncludes(text, "00:15 [P1] alert_&lt;cron&gt; — a &amp; b &gt; c");
  assertNotIncludes(text, "alert_<cron>");
});

Deno.test("more than 10 alerts collapses to 10 lines plus a '+N more' tail", () => {
  const rows = Array.from({ length: 14 }, (_, i) => ({
    detected_at: `2026-09-11T${String(19 + Math.floor(i / 10)).padStart(2, "0")}:${String(i % 10).padStart(2, "0")}:00+00:00`,
    source: `src${i}`,
    severity: "P2",
    summary: `s${i}`,
  }));
  const text = buildDigestText(input({ alerts: { rows } }));
  assertStringIncludes(text, "<b>Alerts yesterday</b> (14):");
  assertEquals(text.split("\n").filter((l) => /^\d\d:\d\d \[P2\]/.test(l)).length, MAX_ALERT_LINES);
  assertStringIncludes(text, "… +4 more");
  assertNotIncludes(text, "src13");
});

Deno.test("the message never exceeds Telegram's 4096-char ceiling", () => {
  const rows = Array.from({ length: 10 }, (_, i) => ({
    detected_at: "2026-09-11T19:00:00+00:00",
    source: `src${i}`,
    severity: "P0",
    summary: "y".repeat(900),
  }));
  const text = buildDigestText(input({ alerts: { rows } }));
  assert(text.length <= TELEGRAM_MAX_CHARS, `got ${text.length}`);
  assertStringIncludes(text, "… (truncated)");
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
