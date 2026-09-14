// Set env vars before any imports that reference them at module scope
const CRON_SECRET_FOR_TEST = "test-cron-secret-12345678901234567890";
Deno.env.set("SUPABASE_URL", "https://dedsavbjuwgarrhphgnl.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "dummy-service-role-key-for-testing");
Deno.env.set("TELEGRAM_BOT_TOKEN", "dummy-telegram-token");
Deno.env.set("FOUNDER_TELEGRAM_CHAT_ID", "123456789");
Deno.env.set("CRON_SECRET", CRON_SECRET_FOR_TEST);

import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { formatCriticalAlertText, handler } from "./index.ts";

/**
 * Loads a FRESH instance of index.ts via a cache-busted dynamic import.
 *
 * Every other test in this file uses the static `handler` import at the top,
 * which is fine because they all return before the handler's internal
 * `createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)` call — that's
 * deliberate (R2-16's comment above). But `SUPABASE_URL`/
 * `SUPABASE_SERVICE_ROLE_KEY` in index.ts are MODULE-SCOPE consts, and ES
 * module imports are hoisted: the static `import { handler } from "./index.ts"`
 * at the top of this file evaluates index.ts's top level BEFORE this file's
 * own `Deno.env.set()` calls run, despite those calls appearing first in
 * source order. So the statically-imported `handler` closes over an EMPTY
 * `SUPABASE_URL` — reaching its `createClient()` call always throws
 * "supabaseUrl is required" before ever touching `alerts` or `sendFn`.
 * (Same class `supabase/functions/CLAUDE.md`'s pitfall table already
 * documents for `ai-media-proxy`'s `STORAGE_PREFIX`: "needs `Deno.env.set(...)`
 * BEFORE a dynamic `await import("./index.ts")` — a static import is hoisted
 * above the `set`".) A cache-busted dynamic import re-evaluates the module
 * fresh, AFTER the env vars above are already set, so its `handler` actually
 * reaches the `alerts` read and `sendFn` — which is what the F5 test below
 * needs to exercise the real token-leak-shaped catch path.
 */
async function importFreshHandler(): Promise<typeof handler> {
  const mod = await import(`./index.ts?cachebust=${crypto.randomUUID()}`) as { handler: typeof handler };
  return mod.handler;
}

/**
 * Stubs `globalThis.fetch` so the handler's internal supabase-js `alerts`
 * row read succeeds without touching the real network — same pattern as
 * `_shared/gemini_backoff_retry_test.ts`'s `installFetchQueue`. Returns a
 * restore function; callers MUST call it in a `finally`.
 */
function stubFetchForAlertsRead(): () => void {
  const original = globalThis.fetch;
  globalThis.fetch = ((_input: unknown, _init?: unknown): Promise<Response> => {
    return Promise.resolve(
      new Response(
        JSON.stringify({
          source: "alert_test",
          summary: "test summary",
          detected_at: "2026-09-14T02:00:00.000Z",
          suggested_action: null,
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
  }) as typeof fetch;
  return () => {
    globalThis.fetch = original;
  };
}

Deno.test("formatCriticalAlertText includes the source, summary, and suggested action", () => {
  const text = formatCriticalAlertText({
    source: "alert_client_errors_spike",
    summary: "client_errors spike: 612 errors in last hour",
    detected_at: "2026-09-13T02:00:00.000Z",
    suggested_action: "Inspect docs/diagnoses for recent regression.",
  });
  assertStringIncludes(text, "alert_client_errors_spike");
  assertStringIncludes(text, "612 errors");
  assertStringIncludes(text, "Inspect docs/diagnoses");
});

Deno.test("formatCriticalAlertText renders detected_at as an IST clock time (review round 1 F13 — it was selected/typed but never rendered)", () => {
  const text = formatCriticalAlertText({
    source: "alert_client_errors_spike",
    summary: "test",
    detected_at: "2026-09-13T02:00:00.000Z", // 07:30 IST
    suggested_action: null,
  });
  assertStringIncludes(text, "07:30");
  assertStringIncludes(text, "IST");
});

Deno.test("formatCriticalAlertText handles a null suggested_action without crashing", () => {
  const text = formatCriticalAlertText({
    source: "alert_payment_flow_health",
    summary: "test",
    detected_at: "2026-09-13T02:00:00.000Z",
    suggested_action: null,
  });
  assertEquals(typeof text, "string");
});

Deno.test("handler rejects a request with no cron auth", async () => {
  const req = new Request("https://example.com/alert-critical-notify", {
    method: "POST",
    body: JSON.stringify({ alert_id: 1 }),
  });
  const res = await handler(req);
  assertEquals(res.status, 401);
});

Deno.test("handler rejects a request with non-numeric alert_id", async () => {
  // Create a test request with proper cron authentication
  // and a non-numeric alert_id to trigger the type validation
  const req = new Request("https://example.com/alert-critical-notify", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${CRON_SECRET_FOR_TEST}`,
    },
    body: JSON.stringify({ alert_id: "not-a-number" }),
  });

  // R2-16 (review round 2): this request passes cron auth, so the handler
  // reaches `logCronStart` BEFORE validating alert_id — with the module-
  // level env vars above pointing at the REAL project URL (dummy
  // service-role key), the un-injected path made a genuine outbound network
  // request here on every run. Inject no-op telemetry stand-ins so this test
  // never touches the network. Mirrors telegram-admin-bot's injectable
  // `sendFn` (R2-05).
  let startCalls = 0;
  let endCalls: Array<{ status: string; opts?: unknown }> = [];
  const res = await handler(
    req,
    {
      logCronStart: async (_fn: string) => {
        startCalls++;
        return 1;
      },
      logCronEnd: async (_id, status, opts) => {
        endCalls.push({ status, opts });
      },
    },
    async () => ({ ok: true }),
  );

  // The handler should return 400 when alert_id is not a number
  assertEquals(res.status, 400);
  const body = await res.json();
  assertStringIncludes(body.error, "alert_id must be a number");
  // And the injected telemetry stand-ins were actually exercised — proves
  // the injection point is real, not dead code the handler never reaches.
  assertEquals(startCalls, 1);
  assertEquals(endCalls.length, 1);
  assertEquals(endCalls[0].status, "failed");
});

Deno.test("F5 (Hermes 2026-09-14, L21): the final catch never leaks a bot-token-shaped error string into telemetry", async () => {
  // This exercises the outer catch block (index.ts's bottom try/catch) via
  // an injected sendFn that throws the SHAPE of error a real Deno `fetch`
  // TypeError has against the Telegram API: err.toString()/.message embeds
  // the full request URL, which for a Telegram call includes the bot token.
  // Not reachable today (sendTelegram never lets a raw fetch rejection
  // escape to this catch — see _shared/telegram.ts's own header), but the
  // guard is positional, not structural, so this pins the structural fix:
  // only telegramErrorSummary's output (which extracts err.name only) may
  // reach logCronEnd's errorSummary field, never the raw error string.
  const restoreFetch = stubFetchForAlertsRead();
  try {
    const freshHandler = await importFreshHandler();
    const req = new Request("https://example.com/alert-critical-notify", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${CRON_SECRET_FOR_TEST}`,
      },
      body: JSON.stringify({ alert_id: 42 }),
    });

    const fakeTokenShapedError = new Error(
      "error sending request for url (https://api.telegram.org/bot123456:FAKE-TOKEN-VALUE/sendMessage)",
    );

    const endCalls: Array<{ status: string; opts?: { errorSummary?: string } }> = [];
    const res = await freshHandler(
      req,
      {
        logCronStart: async (_fn: string) => 1,
        logCronEnd: async (_id, status, opts) => {
          endCalls.push({ status, opts: opts as { errorSummary?: string } });
        },
      },
      async () => {
        throw fakeTokenShapedError;
      },
    );

    assertEquals(res.status, 500);
    assertEquals(endCalls.length, 1);
    assertEquals(endCalls[0].status, "failed");
    const summary = endCalls[0].opts?.errorSummary ?? "";
    assertEquals(summary.includes("123456:FAKE-TOKEN-VALUE"), false);
    assertEquals(summary.includes("api.telegram.org"), false);
    assertStringIncludes(summary, "Error");
  } finally {
    restoreFetch();
  }
});
