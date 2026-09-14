// Set env vars before any imports that reference them at module scope
Deno.env.set("SUPABASE_URL", "https://dedsavbjuwgarrhphgnl.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "dummy-service-role-key-for-testing");
Deno.env.set("TELEGRAM_WEBHOOK_SECRET", "test-webhook-secret-12345");
Deno.env.set("FOUNDER_TELEGRAM_CHAT_ID", "12345");
Deno.env.set("TELEGRAM_BOT_TOKEN", "dummy-telegram-token");

import { assertEquals, assertRejects, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { HELP_TEXT, handler, isAuthorizedTelegramSender, parseCommand, routeCommand, cmdStatus, cmdRevenue, cmdSubs, bucketSubsByPlan, cmdExpiring, cmdUsers, cmdFind, sanitizeFindQuery, cmdUser, cmdAlerts, cmdErrors, cmdCron, cmdDigest, looksLikeUuid } from "./index.ts";

Deno.test("isAuthorizedTelegramSender requires BOTH the secret token and the chat id to match", async () => {
  // Async since review round 1 F11 — the secret comparison now runs
  // through _shared/cron_auth.ts's constant-time timingSafeEqual.
  const base = { expectedSecretToken: "s3cr3t", expectedChatId: "12345" };
  assertEquals(
    await isAuthorizedTelegramSender({ ...base, secretTokenHeader: "s3cr3t", chatId: "12345" }),
    true,
  );
  assertEquals(
    await isAuthorizedTelegramSender({ ...base, secretTokenHeader: "wrong", chatId: "12345" }),
    false,
  );
  assertEquals(
    await isAuthorizedTelegramSender({ ...base, secretTokenHeader: "s3cr3t", chatId: "99999" }),
    false,
  );
  assertEquals(
    await isAuthorizedTelegramSender({ ...base, secretTokenHeader: null, chatId: "12345" }),
    false,
  );
});

Deno.test("isAuthorizedTelegramSender coerces a numeric Telegram chat id before comparing", async () => {
  assertEquals(
    await isAuthorizedTelegramSender({
      secretTokenHeader: "s3cr3t",
      expectedSecretToken: "s3cr3t",
      chatId: 12345,
      expectedChatId: "12345",
    }),
    true,
  );
});

Deno.test("parseCommand strips the leading slash and any @BotName suffix, lowercases the command", () => {
  assertEquals(parseCommand("/Status@IcanbefitterBot"), { cmd: "status", args: [] });
  assertEquals(parseCommand("/user  foo@bar.com"), { cmd: "user", args: ["foo@bar.com"] });
  assertEquals(parseCommand("not a command"), null);
  assertEquals(parseCommand(""), null);
});

// R2-05 (review round 2): `handler` ALWAYS returns a bare 200 regardless of
// auth outcome (index.ts:135 — an unauthorized sender must learn nothing),
// so `res.status === 200` alone cannot tell a working auth check from a
// silently broken one — a mutation that disabled the auth check entirely
// would leave all three tests below green, because an unauthorized request
// just falls through to `sendFn` (whose failure is silently caught/logged).
// Each test now injects a counting stand-in for `sendFn` and asserts the
// SEND COUNT: 0 for a rejected request, exactly 1 for an authorized one.
// This also closes R2-16 (a live network call to api.telegram.org from the
// "authorized /help" test) as a side effect — the real `sendTelegram` is
// never reached once a stand-in is injected.
function countingSendFn() {
  let calls = 0;
  const fn = async (_token: string, _chatId: string, _text: string) => {
    calls++;
    return { ok: true as const };
  };
  return { fn, calls: () => calls };
}

Deno.test("handler returns bare 200 with no body detail for a wrong secret token, and never sends", async () => {
  const req = new Request("https://example.com/telegram-admin-bot", {
    method: "POST",
    headers: { "X-Telegram-Bot-Api-Secret-Token": "wrong" },
    body: JSON.stringify({ message: { chat: { id: 12345 }, text: "/help" } }),
  });
  const { fn, calls } = countingSendFn();
  const res = await handler(req, fn);
  assertEquals(res.status, 200);
  const body = await res.text();
  assertEquals(body, "");
  assertEquals(calls(), 0);
});

Deno.test("handler returns bare 200 for a message from a chat id that isn't the founder's, and never sends", async () => {
  const req = new Request("https://example.com/telegram-admin-bot", {
    method: "POST",
    headers: { "X-Telegram-Bot-Api-Secret-Token": Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "" },
    body: JSON.stringify({ message: { chat: { id: 999999 }, text: "/help" } }),
  });
  const { fn, calls } = countingSendFn();
  const res = await handler(req, fn);
  assertEquals(res.status, 200);
  assertEquals(await res.text(), "");
  assertEquals(calls(), 0);
});

Deno.test("handler replies to /help from the authorized founder chat, sending exactly once", async () => {
  const secret = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";
  const chatId = Deno.env.get("FOUNDER_TELEGRAM_CHAT_ID") ?? "";
  const req = new Request("https://example.com/telegram-admin-bot", {
    method: "POST",
    headers: { "X-Telegram-Bot-Api-Secret-Token": secret },
    body: JSON.stringify({ message: { chat: { id: Number(chatId) }, text: "/help" } }),
  });
  const { fn, calls } = countingSendFn();
  const res = await handler(req, fn);
  assertEquals(res.status, 200);
  assertEquals(calls(), 1);
});

Deno.test("handler stays a silent 200 for a request body that is the JSON literal null", async () => {
  // `req.json()` resolves `null` without throwing for a body of literal
  // `null` — the existing JSON-parse try/catch never fires. The very next
  // line used to read `update.message?.chat?.id`, which threw an uncaught
  // TypeError off a null `update` and broke the endpoint's silent-200
  // invariant (a non-200 is a reconnaissance signal an attacker must never
  // get). Regression for that fix.
  const secret = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";
  const req = new Request("https://example.com/telegram-admin-bot", {
    method: "POST",
    headers: { "X-Telegram-Bot-Api-Secret-Token": secret },
    body: "null",
  });
  const res = await handler(req);
  assertEquals(res.status, 200);
  assertEquals(await res.text(), "");
});

Deno.test("routeCommand('help', ...) returns HELP_TEXT exactly", async () => {
  // The HTTP-level /help test above only asserts status===200, which every
  // failure branch (wrong token, wrong chat id, unknown command) also
  // returns — it can't distinguish a working auth check from a silently
  // broken one. This asserts the routed command's actual return value.
  const reply = await routeCommand("help", [], null);
  assertEquals(reply, HELP_TEXT);
});

// Telegram's HTML parse_mode accepts only a closed literal tag list and
// rejects the WHOLE message with a 400 on anything else — see
// _shared/telegram.ts's header. HELP_TEXT and every static Usage string are
// sent with parse_mode: "HTML" but are hand-written, not escapeHtml()'d (the
// way every DB-sourced field is), so a placeholder like "<text>" reads as an
// unsupported start tag and silently kills the whole reply (review round 1,
// F2, diagnose 2fa7c1). This asserts every "<...>" token in each static
// string is one of Telegram's supported tags.
const TELEGRAM_SUPPORTED_TAGS = new Set([
  "b", "/b", "strong", "/strong", "i", "/i", "em", "/em", "u", "/u",
  "ins", "/ins", "s", "/s", "strike", "/strike", "del", "/del",
  "code", "/code", "pre", "/pre", "blockquote", "/blockquote",
  "tg-spoiler", "/tg-spoiler", "/a", "/span",
]);

function assertOnlySupportedTelegramTags(text: string, label: string) {
  const tokens = text.match(/<[^>]*>/g) ?? [];
  for (const token of tokens) {
    const inner = token.slice(1, -1).trim();
    const tagName = inner.split(/\s/)[0].toLowerCase();
    const isAnchorOrSpan = /^a\s+href=/.test(inner) || /^span\s+class=/.test(inner);
    if (!TELEGRAM_SUPPORTED_TAGS.has(tagName) && !isAnchorOrSpan) {
      throw new Error(
        `${label} contains unsupported Telegram HTML tag "${token}" — this will make sendTelegram fail with a 400 and the whole reply silently disappears.`,
      );
    }
  }
}

Deno.test("HELP_TEXT contains no Telegram-unsupported HTML tags", () => {
  assertOnlySupportedTelegramTags(HELP_TEXT, "HELP_TEXT");
});

Deno.test("static Usage strings contain no Telegram-unsupported HTML tags", async () => {
  const findUsage = await routeCommand("find", [], null);
  const userUsage = await routeCommand("user", [], null);
  assertOnlySupportedTelegramTags(findUsage, "/find usage string");
  assertOnlySupportedTelegramTags(userUsage, "/user usage string");
});

Deno.test("cmdStatus formats alert count, signups, and reports the ops RPC's cron_failures_24h", async () => {
  const fake = {
    rpc: (name: string) => ({
      single: async () => {
        if (name === "founder_metrics_for_admin_api") {
          return { data: { signups_today_ist: 2, pro_active: 5 }, error: null };
        }
        if (name === "founder_metrics_ops") {
          return { data: { open_alerts_count: 1, cron_failures_24h: 0 }, error: null };
        }
        throw new Error(`unexpected rpc ${name}`);
      },
    }),
  };
  const text = await cmdStatus(fake);
  assertStringIncludes(text, "Signups today: 2");
  assertStringIncludes(text, "Open alerts: 1");
  assertStringIncludes(text, "PRO active: 5");
  assertStringIncludes(text, "Cron failures (24h): 0");
});

Deno.test("cmdRevenue reports active subscription counts by plan and MRR", async () => {
  // Routed through fetchAllPages since the gate check_unbounded_cron_reads.dart
  // newly scans this file (it imports _shared/cron_auth.ts as of F11) and a
  // hard .limit() would silently undercount MRR — this fake matches
  // fetchAllPages' real chain shape: .order() then .range(). fetchAllPages
  // only stops on an EMPTY page (a short page could be a server cap, not
  // end-of-data — see paged_fetch.ts's own comment), so the fake must
  // return rows once and an empty page on every call after, or it loops.
  let rangeCalls = 0;
  const fake = {
    from: (_table: string) => ({
      select: () => ({
        eq: () => ({
          order: () => ({
            range: () => {
              rangeCalls++;
              return Promise.resolve(
                rangeCalls === 1
                  ? { data: [{ plan: "monthly" }, { plan: "monthly" }, { plan: "yearly" }], error: null }
                  : { data: [], error: null },
              );
            },
          }),
        }),
      }),
    }),
  };
  const text = await cmdRevenue(fake);
  assertStringIncludes(text, "monthly: 2");
  assertStringIncludes(text, "yearly: 1");
  assertStringIncludes(text, "MRR: ₹948");
});

Deno.test("cmdRevenue's fetchAllPages call is bounded at maxPages:200 (R2-14) — an unbounded read risks exceeding Telegram's webhook timeout", async () => {
  // Real `fetchAllPages` (not mocked) driven by a fake that ALWAYS returns a
  // full page (never an empty one), so the loop can only stop via the
  // maxPages guard, never via end-of-data. Proves the bound is actually
  // WIRED into cmdRevenue's real call, not just present in a comment.
  let rangeCalls = 0;
  const fake = {
    from: (_table: string) => ({
      select: () => ({
        eq: () => ({
          order: () => ({
            range: () => {
              rangeCalls++;
              return Promise.resolve({
                data: Array.from({ length: 1000 }, () => ({ plan: "monthly" })),
                error: null,
              });
            },
          }),
        }),
      }),
    }),
  };
  await assertRejects(() => cmdRevenue(fake), Error, "exceeded maxPages=200");
  assertEquals(rangeCalls, 200);
});

Deno.test("bucketSubsByPlan splits rows into today/yesterday by the tStart boundary and counts by plan", () => {
  // Review round 1 F8: the spec, HELP_TEXT, and this function's own
  // (previously-mistitled) test all promised BOTH today and yesterday;
  // only yesterday was ever queried. This is the pure bucketing logic,
  // deterministic and boundary-exact — `>= tStart` is TODAY, not yesterday.
  const tStart = "2026-09-14T00:00:00+05:30";
  const { today, yesterday } = bucketSubsByPlan(
    [
      { plan: "monthly", created_at: "2026-09-14T01:00:00+05:30" }, // today
      { plan: "monthly", created_at: "2026-09-14T02:00:00+05:30" }, // today
      { plan: "yearly", created_at: "2026-09-13T20:00:00+05:30" }, // yesterday
      { plan: "monthly", created_at: "2026-09-13T10:00:00+05:30" }, // yesterday
      { plan: "monthly", created_at: tStart }, // exactly the boundary — today (>=)
    ],
    tStart,
  );
  assertEquals(today.get("monthly"), 3);
  assertEquals(today.has("yearly"), false);
  assertEquals(yesterday.get("yearly"), 1);
  assertEquals(yesterday.get("monthly"), 1);
});

Deno.test("cmdSubs queries only eq+gte (no upper bound) and renders both Today: and Yesterday: lines", async () => {
  const now = Date.now();
  const justNow = new Date(now - 60 * 1000).toISOString(); // today, almost certainly
  const wellIntoYesterday = new Date(now - 25 * 60 * 60 * 1000).toISOString(); // yesterday, safely past any IST boundary
  const calls: string[] = [];
  const fake = {
    from: () => ({
      select: () => ({
        eq: (col: string, val: string) => {
          calls.push(`eq(${col},${val})`);
          return {
            gte: (col2: string, val2: string) => {
              calls.push(`gte(${col2},...)`);
              return {
                limit: () => Promise.resolve({
                  data: [
                    { plan: "monthly", created_at: justNow },
                    { plan: "yearly", created_at: wellIntoYesterday },
                  ],
                  error: null,
                }),
              };
            },
          };
        },
      }),
    }),
  };
  const text = await cmdSubs(fake);
  assertEquals(calls, ["eq(status,active)", "gte(created_at,...)"]);
  assertStringIncludes(text, "Today: monthly: 1");
  assertStringIncludes(text, "Yesterday: yearly: 1");
});

Deno.test("cmdSubs renders an explicit cap marker when the read hits SUBS_QUERY_CAP (B-pass finding 2)", async () => {
  const rows = Array.from({ length: 1000 }, () => ({
    plan: "monthly",
    created_at: new Date().toISOString(),
  }));
  const fake = {
    from: () => ({
      select: () => ({
        eq: () => ({
          gte: () => ({
            limit: () => Promise.resolve({ data: rows, error: null }),
          }),
        }),
      }),
    }),
  };
  const text = await cmdSubs(fake);
  assertStringIncludes(text, "capped at 1000 rows");
});

Deno.test("cmdExpiring reports 7d and 30d counts", async () => {
  let lteCallCount = 0;
  const fake = {
    from: () => ({
      select: () => ({
        not: () => ({
          gte: () => ({
            lte: () => {
              lteCallCount++;
              if (lteCallCount === 1) {
                return Promise.resolve({ count: 3, data: null, error: null }); // 7d: 3
              } else {
                return Promise.resolve({ count: 9, data: null, error: null }); // 30d: 9
              }
            },
          }),
        }),
      }),
    }),
  };
  const text = await cmdExpiring(fake);
  assertStringIncludes(text, "7d: 3");
  assertStringIncludes(text, "30d: 9");
});

Deno.test("looksLikeUuid recognizes a v4-shaped uuid and rejects an email", () => {
  assertEquals(looksLikeUuid("12345678-abcd-4ef0-9234-56789abcdef0"), true);
  assertEquals(looksLikeUuid("founder@example.com"), false);
});

Deno.test("cmdUsers with no page arg fetches page 1 (offset 0, limit 10)", async () => {
  let capturedRange: [number, number] | null = null;
  const fake = {
    from: () => ({
      select: () => ({
        order: () => ({
          range: (from: number, to: number) => {
            capturedRange = [from, to];
            return Promise.resolve({
              data: [{ id: "u1", email: "a@example.com", created_at: "2026-09-10T00:00:00Z" }],
              error: null,
            });
          },
        }),
      }),
    }),
  };
  const text = await cmdUsers(fake, []);
  assertEquals(capturedRange, [0, 9]);
  assertEquals(text, "<b>Users — page 1</b>\na@example.com — u1\n\n/users 2 for more");
});

Deno.test("cmdUsers with page 2 offsets by 10", async () => {
  let capturedRange: [number, number] | null = null;
  const fake = {
    from: () => ({
      select: () => ({
        order: () => ({
          range: (from: number, to: number) => {
            capturedRange = [from, to];
            return Promise.resolve({ data: [], error: null });
          },
        }),
      }),
    }),
  };
  await cmdUsers(fake, ["2"]);
  assertEquals(capturedRange, [10, 19]);
});

Deno.test("cmdFind with no query text returns a usage hint, not an error", async () => {
  const text = await cmdFind({}, []);
  assertStringIncludes(text.toLowerCase(), "usage");
});

Deno.test("cmdFind searches both email and full_name", async () => {
  let capturedFilter: string | null = null;
  const fake = {
    from: () => ({
      select: () => ({
        or: (filter: string) => {
          capturedFilter = filter;
          return {
            limit: () => Promise.resolve({
              data: [{ id: "u1", email: "match@example.com", full_name: "Match Name" }],
              error: null,
              count: 1,
            }),
          };
        },
      }),
    }),
  };
  const text = await cmdFind(fake, ["match"]);
  assertStringIncludes(capturedFilter!, "match");
  assertEquals(text, '<b>Matches for "match"</b> (1):\nMatch Name — match@example.com — u1');
});

Deno.test("sanitizeFindQuery strips PostgREST or= structural characters and query wildcards", () => {
  // Review round 1 F7: a comma injects an extra disjunct into the `or=`
  // filter (e.g. `/find x,id.neq.<uuid>` could widen the match to
  // everyone); an unbalanced paren 400s the whole request; `%`/`*` let a
  // caller escape the "contains" wrapper this function already applies.
  assertEquals(sanitizeFindQuery("a,b"), "ab");
  assertEquals(sanitizeFindQuery("O'Brien (VP)"), "O'Brien VP");
  assertEquals(sanitizeFindQuery("100%match"), "100match");
  assertEquals(sanitizeFindQuery("plain name"), "plain name");
});

Deno.test("sanitizeFindQuery PRESERVES dots — R2-04, review round 2: stripping them broke every email search", () => {
  // Round 1's fix stripped `.` alongside `,()%*\`, which destroyed the
  // documented primary use case: `/find john.doe@x.com` became
  // "johndoexcom" and could never match. A `.` is not structurally
  // dangerous inside a PostgREST `or=` filter VALUE — only the FIRST TWO
  // dots of each `column.operator.value` term are parsed as structure;
  // everything after that is the value, dots and all.
  assertEquals(sanitizeFindQuery("john.doe@x.com"), "john.doe@x.com");
  assertEquals(sanitizeFindQuery("a.b.c"), "a.b.c");
});

Deno.test("cmdFind sanitizes a comma-bearing query before building the or= filter (does not inject an extra disjunct)", async () => {
  let capturedFilter: string | null = null;
  const fake = {
    from: () => ({
      select: () => ({
        or: (filter: string) => {
          capturedFilter = filter;
          return { limit: () => Promise.resolve({ data: [], error: null, count: 0 }) };
        },
      }),
    }),
  };
  await cmdFind(fake, ["evil,id.neq.x"]);
  // The comma must be stripped before interpolation — exactly one top-level
  // disjunct pair (email.ilike / full_name.ilike), not three. Dots survive
  // (R2-04): they are not structural inside a PostgREST `or=` filter VALUE,
  // only the injected comma is.
  assertEquals(capturedFilter, "email.ilike.%evilid.neq.x%,full_name.ilike.%evilid.neq.x%");
});

Deno.test("cmdFind renders a total and an overflow line when matches exceed the page size", async () => {
  const fake = {
    from: () => ({
      select: () => ({
        or: () => ({
          limit: () => Promise.resolve({
            data: [{ id: "u1", email: "a@example.com", full_name: "A" }],
            error: null,
            count: 23,
          }),
        }),
      }),
    }),
  };
  const text = await cmdFind(fake, ["a"]);
  assertStringIncludes(text, '(23):');
  assertStringIncludes(text, "… +13 more");
});

Deno.test("cmdUser with no args returns a usage hint", async () => {
  const text = await cmdUser({}, []);
  assertStringIncludes(text.toLowerCase(), "usage");
});

Deno.test("cmdUser routes a uuid-shaped arg to an id lookup and an email-shaped arg to an email lookup", async () => {
  let usedColumn: string | null = null;
  const fake = {
    from: () => ({
      select: () => ({
        eq: (col: string) => {
          usedColumn = col;
          return { maybeSingle: () => Promise.resolve({ data: null, error: null }) };
        },
      }),
    }),
  };
  await cmdUser(fake, ["12345678-abcd-4ef0-9234-56789abcdef0"]);
  assertEquals(usedColumn, "id");
  await cmdUser(fake, ["someone@example.com"]);
  assertEquals(usedColumn, "email");
});

Deno.test("cmdUser reports 'not found' rather than a raw null/error for a missing user", async () => {
  const fake = {
    from: () => ({
      select: () => ({
        eq: () => ({ maybeSingle: () => Promise.resolve({ data: null, error: null }) }),
      }),
    }),
  };
  const text = await cmdUser(fake, ["nobody@example.com"]);
  assertStringIncludes(text.toLowerCase(), "not found");
});

Deno.test("cmdUser with an active subscription renders the plan line with end date, reading from `subscriptions` (never users.subscription_status)", async () => {
  const queriedTables: string[] = [];
  const subEqCalls: [string, unknown][] = [];
  const fake = {
    from: (table: string) => {
      queriedTables.push(table);
      if (table === "users") {
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: () => Promise.resolve({
                data: {
                  id: "u42",
                  email: "vip@example.com",
                  full_name: "VIP User",
                  created_at: "2026-01-15T10:30:00Z",
                  last_active_at: "2026-09-12T08:00:00Z",
                },
                error: null,
              }),
            }),
          }),
        };
      }
      if (table === "subscriptions") {
        return {
          select: () => ({
            eq: (col: string, val: unknown) => {
              subEqCalls.push([col, val]);
              return {
                eq: (col2: string, val2: unknown) => {
                  subEqCalls.push([col2, val2]);
                  return {
                    order: () => ({
                      limit: () => Promise.resolve({
                        data: [{ plan: "yearly", status: "active", end_date: "2027-01-15T00:00:00Z" }],
                        error: null,
                      }),
                    }),
                  };
                },
              };
            },
          }),
        };
      }
      throw new Error(`unexpected table: ${table}`);
    },
  };
  const text = await cmdUser(fake, ["vip@example.com"]);
  assertEquals(queriedTables, ["users", "subscriptions"]);
  assertEquals(subEqCalls, [["user_id", "u42"], ["status", "active"]]);
  assertEquals(
    text,
    "<b>VIP User</b>\nvip@example.com\nid: u42\nsigned up: 2026-01-15\nlast active: 2026-09-12\nplan: yearly (ends 2027-01-15)",
  );
});

Deno.test("cmdUser with TWO active subscription rows (a real live shape — renewal overlap) orders by end_date desc, limits to 1, and does not throw", async () => {
  // Review round 1 F3: `.maybeSingle()` on this query throws PGRST116 when
  // >1 row matches, and live data on 2026-09-14 showed exactly this shape
  // for one real user. `.order("end_date", desc).limit(1)` replaces it.
  // This pins the order/limit call args AND that a multi-row scenario (the
  // fake returns 2 rows, oldest-first, deliberately NOT pre-sorted — a
  // real un-ordered query could return them in any order) reads data[0]
  // rather than crashing on ambiguity.
  const orderCalls: [string, unknown][] = [];
  let limitArg: number | undefined;
  const fake = {
    from: (table: string) => {
      if (table === "users") {
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: () => Promise.resolve({
                data: {
                  id: "u-multi",
                  email: "renewed@example.com",
                  full_name: "Renewed User",
                  created_at: "2026-01-01T00:00:00Z",
                  last_active_at: "2026-09-10T00:00:00Z",
                },
                error: null,
              }),
            }),
          }),
        };
      }
      if (table === "subscriptions") {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({
                order: (col: string, opts: unknown) => {
                  orderCalls.push([col, opts]);
                  return {
                    limit: (n: number) => {
                      limitArg = n;
                      return Promise.resolve({
                        data: [
                          { plan: "yearly", status: "active", end_date: "2026-08-01T00:00:00Z" },
                          { plan: "monthly", status: "active", end_date: "2027-06-01T00:00:00Z" },
                        ],
                        error: null,
                      });
                    },
                  };
                },
              }),
            }),
          }),
        };
      }
      throw new Error(`unexpected table: ${table}`);
    },
  };
  const text = await cmdUser(fake, ["renewed@example.com"]);
  assertEquals(orderCalls, [["end_date", { ascending: false }]]);
  assertEquals(limitArg, 1);
  // Reads data[0] verbatim (the real ORDER BY does the sorting server-side —
  // this test's fixture deliberately puts the "wrong" row first to prove
  // the code trusts data[0], not that it re-sorts client-side).
  assertEquals(
    text,
    "<b>Renewed User</b>\nrenewed@example.com\nid: u-multi\nsigned up: 2026-01-01\nlast active: 2026-09-10\nplan: yearly (ends 2026-08-01)",
  );
});

Deno.test("cmdUser without an active subscription renders 'plan: free', reading from `subscriptions` (never users.subscription_status)", async () => {
  const queriedTables: string[] = [];
  const subEqCalls: [string, unknown][] = [];
  const fake = {
    from: (table: string) => {
      queriedTables.push(table);
      if (table === "users") {
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: () => Promise.resolve({
                data: {
                  id: "u43",
                  email: "free@example.com",
                  full_name: "Free User",
                  created_at: "2026-02-20T00:00:00Z",
                  last_active_at: "2026-09-01T00:00:00Z",
                },
                error: null,
              }),
            }),
          }),
        };
      }
      if (table === "subscriptions") {
        return {
          select: () => ({
            eq: (col: string, val: unknown) => {
              subEqCalls.push([col, val]);
              return {
                eq: (col2: string, val2: unknown) => {
                  subEqCalls.push([col2, val2]);
                  return {
                    order: () => ({
                      limit: () => Promise.resolve({ data: [], error: null }),
                    }),
                  };
                },
              };
            },
          }),
        };
      }
      throw new Error(`unexpected table: ${table}`);
    },
  };
  const text = await cmdUser(fake, ["free@example.com"]);
  assertEquals(queriedTables, ["users", "subscriptions"]);
  assertEquals(subEqCalls, [["user_id", "u43"], ["status", "active"]]);
  assertEquals(
    text,
    "<b>Free User</b>\nfree@example.com\nid: u43\nsigned up: 2026-02-20\nlast active: 2026-09-01\nplan: free",
  );
});

Deno.test("cmdAlerts lists open alerts most-recent-first, capped at 10", async () => {
  const rows = Array.from({ length: 12 }, (_, i) => ({
    source: `check_${i}`,
    severity: "warn",
    summary: `row ${i}`,
    detected_at: "2026-09-13T01:00:00Z",
  }));
  const fake = {
    from: () => ({
      select: () => ({
        is: () => ({
          order: () => ({
            limit: (n: number) => Promise.resolve({ data: rows.slice(0, n), error: null }),
          }),
        }),
      }),
    }),
  };
  const text = await cmdAlerts(fake);
  assertStringIncludes(text, "row 0");
  assertStringIncludes(text, "row 9");
  // Verify cap: exactly 10 rows shown (rows 0-9), NOT row 10 or 11
  assertEquals(text.includes("row 10"), false);
  assertEquals(text.includes("row 11"), false);
});

Deno.test("cmdAlerts renders the exact server count and an overflow line when open alerts exceed the page size", async () => {
  // Review round 1 F5: a bare page of MAX_ALERT_LINES with no total left
  // the founder unable to tell "10 alerts" from "10 of 29" — live data
  // 2026-09-14 had 29 open, silently showing only the newest 10. Mirrors
  // founder_digest_content.ts's already-fixed { count: "exact" } pattern.
  const fake = {
    from: () => ({
      select: () => ({
        is: () => ({
          order: () => ({
            limit: () => Promise.resolve({
              data: [{ source: "s", severity: "warn", summary: "m", detected_at: "2026-09-13T01:00:00Z" }],
              error: null,
              count: 29,
            }),
          }),
        }),
      }),
    }),
  };
  const text = await cmdAlerts(fake);
  assertStringIncludes(text, "(29):");
  assertStringIncludes(text, "… +19 more");
});

Deno.test("cmdAlerts escapes HTML in alert fields", async () => {
  const rows = [
    {
      source: "check<script>",
      severity: "warn<severity>",
      summary: "info&summary",
      detected_at: "2026-09-13T01:00:00Z",
    },
  ];
  const fake = {
    from: () => ({
      select: () => ({
        is: () => ({
          order: () => ({
            limit: () => Promise.resolve({ data: rows, error: null }),
          }),
        }),
      }),
    }),
  };
  const text = await cmdAlerts(fake);
  // Verify each field is independently escaped (not just one field hiding for another)
  // Each field uses a DISTINCT special character to ensure mutations catch field-specific escaping
  assertEquals(text.includes("<script>"), false);
  assertStringIncludes(text, "&lt;script&gt;"); // source: <> must be escaped
  assertEquals(text.includes("<severity>"), false);
  assertStringIncludes(text, "warn&lt;severity&gt;"); // severity: <> must be escaped
  assertStringIncludes(text, "info&amp;summary"); // summary: & must be escaped
});

Deno.test("cmdAlerts reports 'none' when there are no open alerts", async () => {
  const fake = {
    from: () => ({
      select: () => ({
        is: () => ({
          order: () => ({ limit: () => Promise.resolve({ data: [], error: null }) }),
        }),
      }),
    }),
  };
  assertStringIncludes(await cmdAlerts(fake), "none");
});

Deno.test("cmdErrors groups yesterday's real errors by op_type and excludes event/info codes", async () => {
  const fake = {
    from: () => ({
      select: () => ({
        gte: () => ({
          lt: () => ({
            limit: () => Promise.resolve({
              data: [
                { op_type: "sync_service_restore_op_timeout", error_code: "minified:a0Z" },
                { op_type: "sync_service_restore_op_timeout", error_code: "minified:a0Z" },
                { op_type: "realtime_stream_weight_logs", error_code: "minified:aQC" },
                { op_type: "excluded_op", error_code: "event" },
                { op_type: "also_excluded_op", error_code: "info" },
              ],
              error: null,
            }),
          }),
        }),
      }),
    }),
  };
  const text = await cmdErrors(fake);
  assertStringIncludes(text, "sync_service_restore_op_timeout: 2");
  assertStringIncludes(text, "realtime_stream_weight_logs: 1");
  // Verify event and info codes are filtered out
  assertEquals(text.includes("excluded_op"), false);
  assertEquals(text.includes("also_excluded_op"), false);
});

Deno.test("cmdErrors RE-INCLUDES an 'event'-coded row whose op_type is failure-shaped (R2-02, mirrors migration 087)", async () => {
  // ErrorTelemetry.logEvent (lib/core/services/error_telemetry.dart:332)
  // hardcodes error_code:'event' even for genuine failures — a bare
  // `error_code !== 'event'` exclusion reproduces migration 086's original
  // blind spot, which 087 fixed on the cron-alert side by re-including any
  // 'event'-coded row whose op_type matches a failure-shaped regex. `/errors`
  // must mirror that predicate exactly, or it stays blind to a whole class
  // of real production failures.
  const fake = {
    from: () => ({
      select: () => ({
        gte: () => ({
          lt: () => ({
            limit: () => Promise.resolve({
              data: [
                // Failure-shaped op_type, error_code='event' — MUST appear.
                { op_type: "sync_failed", error_code: "event" },
                { op_type: "widget_error_fallback", error_code: "event" },
                // Benign breadcrumb, error_code='event' — must NOT appear.
                { op_type: "user_clicked_button", error_code: "event" },
                { op_type: "restore_op_done", error_code: "event" },
                // 'info' stays fully excluded regardless of op_type.
                { op_type: "some_failed_thing", error_code: "info" },
              ],
              error: null,
            }),
          }),
        }),
      }),
    }),
  };
  const text = await cmdErrors(fake);
  assertStringIncludes(text, "sync_failed: 1");
  assertStringIncludes(text, "widget_error_fallback: 1");
  assertEquals(text.includes("user_clicked_button"), false);
  assertEquals(text.includes("restore_op_done"), false);
  assertEquals(text.includes("some_failed_thing"), false);
});

Deno.test("cmdErrors renders an explicit cap marker when the read hits PostgREST's row limit (review round 1 F6)", async () => {
  // `.limit(2000)` was never a real bound — this project's PostgREST
  // db-max-rows is 1000, and a truncated read returns HTTP 200 with no
  // signal at all (scripts/check_unbounded_cron_reads.dart's header). A
  // fixture returning exactly CLIENT_ERRORS_QUERY_CAP (1000) rows is the
  // observable proxy for "the read was capped" from inside this function —
  // it cannot see PostgREST's own truncation, only that it got exactly its
  // own limit back.
  const rows = Array.from({ length: 1000 }, () => ({ op_type: "some_op", error_code: "minified:x" }));
  const fake = {
    from: () => ({
      select: () => ({
        gte: () => ({
          lt: () => ({
            limit: () => Promise.resolve({ data: rows, error: null }),
          }),
        }),
      }),
    }),
  };
  const text = await cmdErrors(fake);
  assertStringIncludes(text, "capped at 1000 rows");
});

Deno.test("cmdErrors escapes HTML in op_type field", async () => {
  const fake = {
    from: () => ({
      select: () => ({
        gte: () => ({
          lt: () => ({
            limit: () => Promise.resolve({
              data: [
                { op_type: "sync<script>", error_code: "test" },
              ],
              error: null,
            }),
          }),
        }),
      }),
    }),
  };
  const text = await cmdErrors(fake);
  assertEquals(text.includes("<script>"), false);
  assertStringIncludes(text, "&lt;script&gt;");
});

Deno.test("cmdCron deduplicates by function name and sorts by age (most stale first)", async () => {
  const now = new Date();
  const fiveMinutesAgo = new Date(now.getTime() - 5 * 60 * 1000).toISOString();
  const tenMinutesAgo = new Date(now.getTime() - 10 * 60 * 1000).toISOString();
  const fifteenMinutesAgo = new Date(now.getTime() - 15 * 60 * 1000).toISOString();

  const fake = {
    from: () => ({
      select: () => ({
        gte: () => ({
          order: () => ({
            limit: () => Promise.resolve({
              data: [
                // Most recent of morning-alert (should be used)
                { function_name: "morning-alert", status: "success", started_at: fiveMinutesAgo },
                // Older of morning-alert (should be ignored)
                { function_name: "morning-alert", status: "failed", started_at: fifteenMinutesAgo },
                // Most recent of evening-alert
                { function_name: "evening-alert", status: "success", started_at: tenMinutesAgo },
              ],
              error: null,
            }),
          }),
        }),
      }),
    }),
  };
  const text = await cmdCron(fake);
  // Should show evening-alert first (15 min ago - most stale), then morning-alert (5 min ago)
  const eveningIndex = text.indexOf("evening-alert");
  const morningIndex = text.indexOf("morning-alert");
  assertEquals(eveningIndex > 0 && morningIndex > eveningIndex, true);
  // Should NOT show the failed duplicate morning-alert
  assertEquals(text.match(/morning-alert/g)?.length, 1);
  assertStringIncludes(text, "success");
});

Deno.test("cmdCron escapes HTML in function name and status", async () => {
  const now = new Date();
  const fake = {
    from: () => ({
      select: () => ({
        gte: () => ({
          order: () => ({
            limit: () => Promise.resolve({
              data: [
                { function_name: "alert<script>", status: "fail&success", started_at: now.toISOString() },
              ],
              error: null,
            }),
          }),
        }),
      }),
    }),
  };
  const text = await cmdCron(fake);
  assertEquals(text.includes("<script>"), false);
  assertStringIncludes(text, "&lt;script&gt;");
  assertStringIncludes(text, "&amp;");
});

Deno.test("cmdCron queries a 7-day time window (gte on started_at), not a row-count limit — a genuinely stale job that a row cap would drop must still appear", async () => {
  // Review round 1 F4: `.limit(200)` on `started_at desc` silently dropped
  // whichever functions were stalest — live evidence showed 3 real
  // functions missing entirely. A 7-day `.gte()` window closes that
  // specific gap (correct bound, never a row count) — though it is not a
  // COMPLETE fix: `cleanup_cron_call_log()`'s LIVE definition (migration
  // 110, not the superseded 109 — R2-06/R2-07) spares TWO rows globally
  // (newest success + newest any-status), still not each function's
  // latest, so true >7-day silence still goes invisible past the
  // retention cut (B-pass finding, same day; see the code comment above
  // cmdCron; deeper fix tracked as OI-199).
  const now = new Date();
  const threeDaysAgo = new Date(now.getTime() - 3 * 24 * 60 * 60 * 1000).toISOString();
  let gteCol: string | undefined;
  let gteVal: string | undefined;
  let limitArg: number | undefined;
  const fake = {
    from: () => ({
      select: () => ({
        gte: (col: string, val: string) => {
          gteCol = col;
          gteVal = val;
          return {
            order: () => ({
              limit: (n: number) => {
                limitArg = n;
                return Promise.resolve({
                  // A genuinely stale function (3 days silent) — well past
                  // where any 200-row recency window would have reached,
                  // but inside the 7-day retention window this query uses.
                  data: [{ function_name: "plateau-alert", status: "success", started_at: threeDaysAgo }],
                  error: null,
                });
              },
            }),
          };
        },
      }),
    }),
  };
  const text = await cmdCron(fake);
  assertEquals(gteCol, "started_at");
  // Within a few ms of "7 days ago" — assert the window, not an exact instant.
  const gteAgeMs = now.getTime() - new Date(gteVal!).getTime();
  const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
  assertEquals(Math.abs(gteAgeMs - sevenDaysMs) < 5000, true);
  assertEquals(limitArg, 1000);
  assertStringIncludes(text, "plateau-alert");
});

/**
 * Minimal fake supabase client that satisfies gatherDigestInput's query chain.
 * Resolves all reads to empty data + 0 counts, so every section renders "none".
 *
 * Pattern: intermediate chainable methods (.select(), .gte(), .lt(), .eq(), .order(),
 * .not(), .lte()) return the builder itself so .order().range() or .limit() can be
 * chained on top. Only terminal methods (.range(), .limit()) return Promises.
 * Follows the exact chainable pattern from _shared/paged_fetch_test.ts makeFake().
 */
function makeEmptyDigestFake() {
  // Shared builder that can chain any intermediate method and any terminal method
  function makeBuilder() {
    const builder = {
      select: (_cols: string, _opts?: Record<string, unknown>) => builder,
      eq: (_col: string, _val?: unknown) => builder,
      gte: (_col: string, _val?: unknown) => builder,
      lt: (_col: string, _val?: unknown) => builder,
      not: (_col: string, _op?: string, _val?: unknown) => builder,
      order: (_col: string, _opts?: Record<string, unknown>) => builder,
      // Terminal methods that return Promises
      //
      // `.lte()` is terminal here, not intermediate: readDigestSections'
      // expiringSoonRead (founder_digest_content.ts:484-510) is the ONLY
      // caller of `.lte()` in this module and awaits it directly (no
      // trailing .order()/.range()/.limit()), reading `r7.count`/`r7.error`
      // off the result directly. Grepped: `.lte(` has exactly 2 call sites
      // in founder_digest_content.ts, both this one pair, neither chained
      // further. Matching the real terminal shape here is a structural-
      // fidelity fix, not a mutation-sensitivity one — a 0-valued count is
      // indistinguishable whether it comes from this Promise's explicit 0
      // or from a broken chainable `.lte()`'s `undefined ?? 0` fallback, so
      // no assertion on THIS fixture's zero counts can catch a regression
      // here; only a nonzero fixture could, which would conflict with this
      // test's "empty digest" premise.
      lte: (_col: string, _val?: unknown) => Promise.resolve({
        count: 0,
        error: null,
      }),
      range: (_from: number, _to: number) => Promise.resolve({
        rows: [],
        data: [],
        error: null,
      }),
      limit: (_n: number) => Promise.resolve({
        rows: [],
        data: [],
        count: 0,
        error: null,
      }),
      maybeSingle: () => Promise.resolve({
        data: null,
        error: null,
      }),
    };
    return builder;
  }

  return {
    from: (_table: string) => makeBuilder(),
  };
}

Deno.test("cmdDigest builds text via the shared founder_digest_content module, not a re-implementation", async () => {
  const text = await cmdDigest(makeEmptyDigestFake());
  // Every section should render as empty ("none"), never as "unreadable" due to chain failures
  assertStringIncludes(text, "Chat (free, 10/day): none");
  assertStringIncludes(text, "Free image reads (lifetime): none");
  assertStringIncludes(text, "Weekly report (free) (lifetime): none");
  assertStringIncludes(text, "<b>Top users</b>: none");
  assertStringIncludes(text, "<b>Alerts yesterday</b>: none");
  assertStringIncludes(text, "<b>Subscriptions (new, yesterday)</b>\nnone");
  assertStringIncludes(text, "7d: 0 · 30d: 0");
  // Ensure "unreadable" marker never appears — which would indicate a chain failure
  assertEquals(text.includes("unreadable"), false);
});
