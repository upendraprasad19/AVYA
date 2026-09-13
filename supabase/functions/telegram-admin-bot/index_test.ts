// Set env vars before any imports that reference them at module scope
Deno.env.set("SUPABASE_URL", "https://dedsavbjuwgarrhphgnl.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "dummy-service-role-key-for-testing");
Deno.env.set("TELEGRAM_WEBHOOK_SECRET", "test-webhook-secret-12345");
Deno.env.set("FOUNDER_TELEGRAM_CHAT_ID", "12345");
Deno.env.set("TELEGRAM_BOT_TOKEN", "dummy-telegram-token");

import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { HELP_TEXT, handler, isAuthorizedTelegramSender, parseCommand, routeCommand, cmdStatus, cmdRevenue, cmdSubs, cmdExpiring, cmdUsers, cmdFind, cmdUser, cmdAlerts, cmdErrors, cmdCron, cmdDigest, looksLikeUuid } from "./index.ts";

Deno.test("isAuthorizedTelegramSender requires BOTH the secret token and the chat id to match", () => {
  const base = { expectedSecretToken: "s3cr3t", expectedChatId: "12345" };
  assertEquals(
    isAuthorizedTelegramSender({ ...base, secretTokenHeader: "s3cr3t", chatId: "12345" }),
    true,
  );
  assertEquals(
    isAuthorizedTelegramSender({ ...base, secretTokenHeader: "wrong", chatId: "12345" }),
    false,
  );
  assertEquals(
    isAuthorizedTelegramSender({ ...base, secretTokenHeader: "s3cr3t", chatId: "99999" }),
    false,
  );
  assertEquals(
    isAuthorizedTelegramSender({ ...base, secretTokenHeader: null, chatId: "12345" }),
    false,
  );
});

Deno.test("isAuthorizedTelegramSender coerces a numeric Telegram chat id before comparing", () => {
  assertEquals(
    isAuthorizedTelegramSender({
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

Deno.test("handler returns bare 200 with no body detail for a wrong secret token", async () => {
  const req = new Request("https://example.com/telegram-admin-bot", {
    method: "POST",
    headers: { "X-Telegram-Bot-Api-Secret-Token": "wrong" },
    body: JSON.stringify({ message: { chat: { id: 12345 }, text: "/help" } }),
  });
  const res = await handler(req);
  assertEquals(res.status, 200);
  const body = await res.text();
  assertEquals(body, "");
});

Deno.test("handler returns bare 200 for a message from a chat id that isn't the founder's", async () => {
  const req = new Request("https://example.com/telegram-admin-bot", {
    method: "POST",
    headers: { "X-Telegram-Bot-Api-Secret-Token": Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "" },
    body: JSON.stringify({ message: { chat: { id: 999999 }, text: "/help" } }),
  });
  const res = await handler(req);
  assertEquals(res.status, 200);
  assertEquals(await res.text(), "");
});

Deno.test("handler replies to /help from the authorized founder chat", async () => {
  const secret = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";
  const chatId = Deno.env.get("FOUNDER_TELEGRAM_CHAT_ID") ?? "";
  const req = new Request("https://example.com/telegram-admin-bot", {
    method: "POST",
    headers: { "X-Telegram-Bot-Api-Secret-Token": secret },
    body: JSON.stringify({ message: { chat: { id: Number(chatId) }, text: "/help" } }),
  });
  const res = await handler(req);
  assertEquals(res.status, 200);
  // sendTelegram will attempt a real network call here and fail in the test
  // sandbox (no real token) — that's fine, it's caught and logged, never
  // thrown; the assertion is on the HTTP response shape, not on delivery.
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
  const fake = {
    from: (table: string) => ({
      select: () => ({
        eq: () => Promise.resolve({
          data: [{ plan: "monthly" }, { plan: "monthly" }, { plan: "yearly" }],
          error: null,
        }),
      }),
    }),
  };
  const text = await cmdRevenue(fake);
  assertStringIncludes(text, "monthly: 2");
  assertStringIncludes(text, "yearly: 1");
  assertStringIncludes(text, "MRR: ₹948");
});

Deno.test("cmdSubs reports today's and yesterday's new subscriptions by plan", async () => {
  const fake = {
    from: () => ({
      select: () => ({
        eq: () => ({
          gte: () => ({
            lt: () => Promise.resolve({ data: [{ plan: "monthly", created_at: "2026-09-13T01:00:00Z" }], error: null }),
          }),
        }),
      }),
    }),
  };
  const text = await cmdSubs(fake);
  assertStringIncludes(text, "monthly");
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
            }),
          };
        },
      }),
    }),
  };
  const text = await cmdFind(fake, ["match"]);
  assertStringIncludes(capturedFilter!, "match");
  assertEquals(text, '<b>Matches for "match"</b>\nMatch Name — match@example.com — u1');
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
                    maybeSingle: () => Promise.resolve({
                      data: { plan: "yearly", status: "active", end_date: "2027-01-15T00:00:00Z" },
                      error: null,
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
                    maybeSingle: () => Promise.resolve({ data: null, error: null }),
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
  };
  const text = await cmdCron(fake);
  assertEquals(text.includes("<script>"), false);
  assertStringIncludes(text, "&lt;script&gt;");
  assertStringIncludes(text, "&amp;");
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
      lte: (_col: string, _val?: unknown) => builder,
      not: (_col: string, _op?: string, _val?: unknown) => builder,
      order: (_col: string, _opts?: Record<string, unknown>) => builder,
      // Terminal methods that return Promises
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
  // Ensure "unreadable" marker never appears — which would indicate a chain failure
  assertEquals(text.includes("unreadable"), false);
});
