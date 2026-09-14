// Set env vars before any imports that reference them at module scope
const CRON_SECRET_FOR_TEST = "test-cron-secret-12345678901234567890";
Deno.env.set("SUPABASE_URL", "https://dedsavbjuwgarrhphgnl.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "dummy-service-role-key-for-testing");
Deno.env.set("TELEGRAM_BOT_TOKEN", "dummy-telegram-token");
Deno.env.set("FOUNDER_TELEGRAM_CHAT_ID", "123456789");
Deno.env.set("CRON_SECRET", CRON_SECRET_FOR_TEST);

import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { formatCriticalAlertText, handler } from "./index.ts";

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
