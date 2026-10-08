// supabase/functions/_shared/gemini_failure_alert_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { alertClass, reportGeminiExhaustion } from "./gemini_failure_alert.ts";

function fakeClient(overrides: {
  selectResult?: { data: unknown[] | null; error: unknown };
  insertError?: unknown;
}) {
  const inserted: Record<string, unknown>[] = [];
  // Every `.eq(col, val)` of the dedup query, in order — the dedup key.
  const dedupEqs: Array<[string, unknown]> = [];
  return {
    inserted,
    dedupEqs,
    from(_table: string) {
      // One chainable builder (eq/is/gte return it; limit resolves), so the
      // fake does not hard-code the query's chain length: adding the
      // `context_json->>class` filter must not need a new fake level.
      const builder = {
        eq: (col: string, val: unknown) => {
          dedupEqs.push([col, val]);
          return builder;
        },
        is: (_c: string, _v: unknown) => builder,
        gte: (_c: string, _v: unknown) => builder,
        limit: (_n: number) =>
          Promise.resolve(overrides.selectResult ?? { data: [], error: null }),
      };
      return {
        select: (_cols: string) => builder,
        insert: (row: Record<string, unknown>) => {
          inserted.push(row);
          return Promise.resolve({ error: overrides.insertError ?? null });
        },
      };
    },
    // deno-lint-ignore no-explicit-any
  } as any;
}

Deno.test("reportGeminiExhaustion classifies 429 as quota/billing", async () => {
  const client = fakeClient({ selectResult: { data: [], error: null } });
  await reportGeminiExhaustion(client, "ai_proxy_gemini_exhausted", { status: 429, message: "quota exceeded" });
  assertEquals(client.inserted.length, 1);
  assertEquals(client.inserted[0].severity, "critical");
  assertEquals(
    (client.inserted[0].suggested_action as string).includes("quota"),
    true,
  );
});

Deno.test("reportGeminiExhaustion classifies 401/403 as key/secret issue", async () => {
  const client = fakeClient({ selectResult: { data: [], error: null } });
  await reportGeminiExhaustion(client, "ai_proxy_gemini_exhausted", { status: 403, message: "forbidden" });
  assertEquals(
    (client.inserted[0].suggested_action as string).includes("GEMINI_API_KEY"),
    true,
  );
});

Deno.test("reportGeminiExhaustion downgrades to warn inside the dedup window", async () => {
  const client = fakeClient({ selectResult: { data: [{ id: 1 }], error: null } });
  await reportGeminiExhaustion(client, "ai_proxy_gemini_exhausted", { status: 429, message: "quota exceeded" });
  assertEquals(client.inserted[0].severity, "warn");
});

Deno.test("reportGeminiExhaustion never throws when insert fails", async () => {
  const client = fakeClient({ selectResult: { data: [], error: null }, insertError: new Error("boom") });
  // Must not throw.
  await reportGeminiExhaustion(client, "ai_proxy_gemini_exhausted", { status: 500, message: "server error" });
});

Deno.test("reportGeminiExhaustion never throws when the dedup select errors", async () => {
  const client = fakeClient({ selectResult: { data: null, error: new Error("boom") } });
  await reportGeminiExhaustion(client, "ai_proxy_gemini_exhausted", { status: 500, message: "server error" });
});

Deno.test(
  "DISABLE_GEMINI_FAILURE_ALERT=true skips the alert entirely (§4.6 feature-flag protocol, 2026-09-20)",
  async () => {
    Deno.env.set("DISABLE_GEMINI_FAILURE_ALERT", "true");
    try {
      const client = fakeClient({ selectResult: { data: [], error: null } });
      await reportGeminiExhaustion(client, "ai_proxy_gemini_exhausted", { status: 429, message: "quota exceeded" });
      assertEquals(client.inserted.length, 0);
    } finally {
      Deno.env.delete("DISABLE_GEMINI_FAILURE_ALERT");
    }
  },
);

Deno.test(
  "DISABLE_GEMINI_FAILURE_ALERT unset still alerts as before (mirror case)",
  async () => {
    Deno.env.delete("DISABLE_GEMINI_FAILURE_ALERT");
    const client = fakeClient({ selectResult: { data: [], error: null } });
    await reportGeminiExhaustion(client, "ai_proxy_gemini_exhausted", { status: 429, message: "quota exceeded" });
    assertEquals(client.inserted.length, 1);
  },
);

Deno.test(
  "endpoint distinguishes otherwise-identical alerts in summary + context_json (B-pass finding, 2026-09-20)",
  async () => {
    const client = fakeClient({ selectResult: { data: [], error: null } });
    await reportGeminiExhaustion(
      client,
      "ai_proxy_gemini_exhausted",
      { status: 500, message: "server error" },
      "scan_meal",
    );
    assertEquals(
      (client.inserted[0].summary as string).startsWith("scan_meal:"),
      true,
    );
    assertEquals(
      (client.inserted[0].context_json as Record<string, unknown>).endpoint,
      "scan_meal",
    );
  },
);

Deno.test(
  "endpoint omitted falls back to source in summary + null in context_json (mirror case)",
  async () => {
    const client = fakeClient({ selectResult: { data: [], error: null } });
    await reportGeminiExhaustion(client, "ai_proxy_gemini_exhausted", { status: 500, message: "server error" });
    assertEquals(
      (client.inserted[0].summary as string).startsWith("ai_proxy_gemini_exhausted:"),
      true,
    );
    assertEquals(
      (client.inserted[0].context_json as Record<string, unknown>).endpoint,
      null,
    );
  },
);

// ── A3 (2026-10-01): model_unavailable class, judged over EVERY attempt ──────

// Fixtures = the two real 404 bodies the probe captured on the new key.
const RETIRED_404 =
  "This model models/gemini-2.5-flash-lite is no longer available to new users. Please update your code to use models/gemini-3.5-flash-lite for the latest features and improvements.";
const UNKNOWN_404 =
  "models/gemini-9-does-not-exist is not found for API version v1beta, or is not supported for generateContent.";

Deno.test("alertClass: a 404 on ANY attempt is model_unavailable, even when the last attempt was a 503", () => {
  assertEquals(
    alertClass(503, [{ model: "a", status: 404 }, { model: "b", status: 503 }]),
    "model_unavailable",
  );
  assertEquals(alertClass(404, undefined), "model_unavailable");
  assertEquals(alertClass(429, [{ model: "a", status: 429 }]), "quota");
  assertEquals(alertClass(403, undefined), "auth");
  // 5xx, timeouts and unclassified failures COLLAPSE into one class: the last
  // attempt's status varies request to request in one outage and each critical
  // insert is a Telegram page, so a raw status key would page up to 5x per window.
  for (const st of [503, 500, 502, null, 400]) {
    assertEquals(alertClass(st, undefined), "transient");
  }
});

Deno.test("model_unavailable: both real 404 body shapes classify the same, store class + statuses, and point at the constant", async () => {
  for (const message of [RETIRED_404, UNKNOWN_404]) {
    const client = fakeClient({ selectResult: { data: [], error: null } });
    await reportGeminiExhaustion(
      client,
      "ai_proxy_gemini_exhausted",
      { status: 404, message },
      "chat",
      undefined,
      [{ model: "gemini-3.1-flash-lite", status: 404 }, { model: "gemini-3.5-flash-lite", status: 404 }],
    );
    const row = client.inserted[0];
    const ctx = row.context_json as Record<string, unknown>;
    assertEquals(ctx.class, "model_unavailable");
    assertEquals((ctx.attempt_statuses as unknown[]).length, 2);
    assertEquals(
      (row.suggested_action as string).includes("supabase/functions/_shared/gemini.ts"),
      true,
    );
    assertEquals(row.severity, "critical");
  }
});

Deno.test("dedup is keyed per class: the select filters on context_json->>class", async () => {
  const client = fakeClient({ selectResult: { data: [], error: null } });
  await reportGeminiExhaustion(
    client,
    "ai_proxy_gemini_exhausted",
    { status: 503, message: "x" },
    "chat",
    undefined,
    [{ model: "a", status: 404 }, { model: "b", status: 503 }],
  );
  assertEquals(
    client.dedupEqs.some(([c, v]: [string, unknown]) =>
      c === "context_json->>class" && v === "model_unavailable"
    ),
    true,
  );
  // source stays the constant dedup key (A5's "no new alert" check relies on it)
  assertEquals(
    client.dedupEqs.some(([c, v]: [string, unknown]) =>
      c === "source" && v === "ai_proxy_gemini_exhausted"
    ),
    true,
  );
});

Deno.test("a different class inside the window is NOT suppressed to a duplicate of the other class's alert (class is part of the key)", async () => {
  // The fake returns a recent row only when asked about the class it holds.
  const inserted: Record<string, unknown>[] = [];
  let askedClass: unknown = null;
  const client = {
    inserted,
    from() {
      const b = {
        eq: (c: string, v: unknown) => {
          if (c === "context_json->>class") askedClass = v;
          return b;
        },
        is: () => b,
        gte: () => b,
        limit: () =>
          Promise.resolve({
            data: askedClass === "transient" ? [{ id: 1 }] : [],
            error: null,
          }),
      };
      return {
        select: () => b,
        insert: (row: Record<string, unknown>) => {
          inserted.push(row);
          return Promise.resolve({ error: null });
        },
      };
    },
    // deno-lint-ignore no-explicit-any
  } as any;
  // an existing recent `transient`-class alert must not downgrade a NEW model_unavailable one
  await reportGeminiExhaustion(client, "ai_proxy_gemini_exhausted", { status: 404, message: RETIRED_404 }, "chat", undefined, [
    { model: "a", status: 404 },
  ]);
  assertEquals(inserted[0].severity, "critical");
  // ...and a second server-class one inside the window still downgrades
  await reportGeminiExhaustion(client, "ai_proxy_gemini_exhausted", { status: 503, message: "x" }, "chat");
  assertEquals(inserted[1].severity, "warn");
});

Deno.test("a missing attemptStatuses argument degrades to today's behaviour (classified from lastError only)", async () => {
  const client = fakeClient({ selectResult: { data: [], error: null } });
  await reportGeminiExhaustion(client, "ai_proxy_gemini_exhausted", { status: 503, message: "x" });
  const ctx = client.inserted[0].context_json as Record<string, unknown>;
  assertEquals(ctx.class, "transient");
  assertEquals(ctx.attempt_statuses, null);
});
