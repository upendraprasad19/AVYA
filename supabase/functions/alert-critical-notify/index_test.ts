// Set env vars before any imports that reference them at module scope
Deno.env.set("SUPABASE_URL", "https://dedsavbjuwgarrhphgnl.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "dummy-service-role-key-for-testing");

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
