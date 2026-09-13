// Set env vars before any imports that reference them at module scope
Deno.env.set("SUPABASE_URL", "https://dedsavbjuwgarrhphgnl.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "dummy-service-role-key-for-testing");
Deno.env.set("TELEGRAM_WEBHOOK_SECRET", "test-webhook-secret-12345");
Deno.env.set("FOUNDER_TELEGRAM_CHAT_ID", "12345");
Deno.env.set("TELEGRAM_BOT_TOKEN", "dummy-telegram-token");

import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { HELP_TEXT, handler, isAuthorizedTelegramSender, parseCommand, routeCommand, cmdStatus, cmdRevenue, cmdSubs, cmdExpiring, cmdUsers, cmdFind, cmdUser, looksLikeUuid } from "./index.ts";

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
