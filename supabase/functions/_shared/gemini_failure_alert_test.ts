// supabase/functions/_shared/gemini_failure_alert_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { reportGeminiExhaustion } from "./gemini_failure_alert.ts";

function fakeClient(overrides: {
  selectResult?: { data: unknown[] | null; error: unknown };
  insertError?: unknown;
}) {
  const inserted: Record<string, unknown>[] = [];
  return {
    inserted,
    from(_table: string) {
      return {
        select: (_cols: string) => ({
          eq: (_a: string, _b: string) => ({
            eq: (_c: string, _d: string) => ({
              is: (_e: string, _f: null) => ({
                gte: (_g: string, _h: string) => ({
                  limit: (_n: number) =>
                    Promise.resolve(overrides.selectResult ?? { data: [], error: null }),
                }),
              }),
            }),
          }),
        }),
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
