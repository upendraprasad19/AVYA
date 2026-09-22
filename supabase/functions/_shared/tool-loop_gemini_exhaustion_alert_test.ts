// supabase/functions/_shared/tool-loop_gemini_exhaustion_alert_test.ts
//
// A5/OI-226 (f7a2c9, 2026-09-21) — the coach tool-loop's hard-failure catch
// (tool-loop.ts:282-298) had ZERO telemetry for a terminal Gemini failure.
// Confirmed live: querying client_errors for the founder's account across a
// fully-reproduced incident window returned zero rows — not low volume,
// genuinely nothing. The 3 nutrition endpoints (ai-proxy/index.ts) already
// call reportGeminiExhaustion on their own total-exhaustion path; the coach
// chat path (runToolLoop) never did.
//
// This closes the gap by wiring reportGeminiExhaustion into runToolLoop's
// catch block, reusing gemini.ts's geminiChatWithTools throw — which this
// same batch extended to attach {status, geminiMessage} onto the thrown
// Error (previously only a hand-composed .message string existed, with no
// structured field reportGeminiExhaustion's {status, message} shape could
// consume without re-parsing prose).
//
// This is a BEHAVIORAL test driven end-to-end through runToolLoop, stubbing
// globalThis.fetch (geminiChatWithTools calls the global directly) exactly
// like tool-loop_intent_apology_test.ts, plus a fake Supabase client
// mirroring gemini_failure_alert_test.ts's own fakeClient — proving the two
// pieces (the newly-structured thrown Error + the new call site) actually
// connect end-to-end, not just that each compiles in isolation.
//
// Run: deno test --allow-env supabase/functions/_shared/tool-loop_gemini_exhaustion_alert_test.ts

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

// gemini.ts reads GEMINI_API_KEY at eval time — set it before importing
// anything that transitively imports gemini.ts.
Deno.env.set("GEMINI_API_KEY", "test-key-not-a-real-secret");

const { runToolLoop, HARD_FAILURE_APOLOGY_GEMINI_CALL_FAILED } = await import(
  "./tool-loop.ts"
);
import type { ToolContext } from "./tools/types.ts";

function httpErrorResponse(status: number, body = "err"): Response {
  return {
    ok: false,
    status,
    text: () => Promise.resolve(body),
    json: () => Promise.resolve({}),
  } as unknown as Response;
}

function functionCallResponse(
  name: string,
  args: Record<string, unknown>,
): Response {
  return {
    ok: true,
    status: 200,
    text: () => Promise.resolve(""),
    json: () =>
      Promise.resolve({
        candidates: [{ content: { parts: [{ functionCall: { name, args } }] } }],
        usageMetadata: { totalTokenCount: 5 },
      }),
  } as unknown as Response;
}

function installPersistentFailureFetch(status: number): {
  restore: () => void;
} {
  const original = globalThis.fetch;
  globalThis.fetch = (() =>
    Promise.resolve(httpErrorResponse(status, "overloaded"))) as typeof fetch;
  return { restore: () => (globalThis.fetch = original) };
}

// Mirrors gemini_failure_alert_test.ts's own fakeClient exactly (same
// chainable-builder shape reportGeminiExhaustion's dedup select + insert
// need) — duplicated rather than imported because that file keeps it
// module-private; the shape is small and the duplication makes each test
// file independently readable.
function fakeAlertsClient() {
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
                    Promise.resolve({ data: [], error: null }),
                }),
              }),
            }),
          }),
        }),
        insert: (row: Record<string, unknown>) => {
          inserted.push(row);
          return Promise.resolve({ error: null });
        },
      };
    },
    // deno-lint-ignore no-explicit-any
  } as any;
}

Deno.test(
  "runToolLoop — total Gemini exhaustion fires reportGeminiExhaustion with source/endpoint/status/message",
  async () => {
    const { restore } = installPersistentFailureFetch(503);
    const client = fakeAlertsClient();
    const ctx: ToolContext = {
      userId: "test-user",
      isPro: false,
      sb: client,
      requestId: "test-req",
    };
    try {
      const result = await runToolLoop({
        systemPrompt: "you are The Captain",
        userMessage: "how am I doing this week?",
        ctx,
        model: "gemini-2.5-flash",
      });

      // Pre-existing behavior unchanged: the user still sees the apology.
      assertEquals(result.text, HARD_FAILURE_APOLOGY_GEMINI_CALL_FAILED);
      assertEquals(result.hadHardFailure, true);

      // NEW: exactly one alert fired, with the real failure's status/message
      // threaded through the newly-structured thrown Error.
      assertEquals(client.inserted.length, 1);
      const row = client.inserted[0];
      assertEquals(row.source, "ai_proxy_gemini_exhausted");
      const context = row.context_json as Record<string, unknown>;
      assertEquals(context.endpoint, "chat");
      assertEquals(context.status, 503);
      assert(
        (context.message as string).includes("HTTP 503"),
        `expected message to include the real HTTP status, got: ${context.message}`,
      );
    } finally {
      restore();
    }
  },
);

Deno.test(
  "runToolLoop — a hard failure AFTER a tool call already queued a real " +
    "write intent still fires the alert, and tags it hadQueuedIntent:true " +
    "(Hermes L34 #4, 2026-09-21) — the underlying Gemini failure is equally " +
    "real whether or not an earlier round already queued something",
  async () => {
    let call = 0;
    const original = globalThis.fetch;
    globalThis.fetch = (() => {
      call++;
      // Round 1: the model successfully calls a tool, queuing a write
      // intent and forcing a second round (the loop only stops on a
      // terminal text response). Round 2 (and any later attempt/fallback):
      // Gemini is persistently down — this is the SUMMARIZATION round
      // failing AFTER the real action already succeeded.
      if (call === 1) {
        return Promise.resolve(functionCallResponse("logSet", {
          exerciseId: "bench_press",
          weightKg: 80,
          reps: 10,
          sets: 4,
        }));
      }
      return Promise.resolve(httpErrorResponse(503, "overloaded"));
    }) as typeof fetch;
    const client = fakeAlertsClient();
    const ctx: ToolContext = {
      userId: "test-user",
      isPro: false,
      sb: client,
      requestId: "test-req",
    };
    try {
      const result = await runToolLoop({
        systemPrompt: "you are The Captain",
        userMessage: "log my bench: 80kg 4 sets of 10",
        ctx,
        model: "gemini-2.5-flash",
      });

      // FC2: the queued intent means NO apology text — the loop-exit
      // confirmation renders the successful action instead.
      assertEquals(result.text === HARD_FAILURE_APOLOGY_GEMINI_CALL_FAILED, false);
      // hadHardFailure is about history-poisoning (a1c6b9), a DIFFERENT
      // axis from hadQueuedIntent — FC2's queued-intent acknowledgment is
      // real, useful output and is deliberately excluded from it, so this
      // stays false here even though the alert still fires below.
      assertEquals(result.hadHardFailure, false);

      assertEquals(client.inserted.length, 1);
      const row = client.inserted[0];
      const context = row.context_json as Record<string, unknown>;
      assertEquals(
        context.hadQueuedIntent,
        true,
        `expected hadQueuedIntent:true once a write intent was already queued, got ${
          JSON.stringify(context)
        }`,
      );
    } finally {
      globalThis.fetch = original;
    }
  },
);

Deno.test(
  "runToolLoop — total exhaustion with NOTHING queued tags hadQueuedIntent:false (mirror case)",
  async () => {
    const { restore } = installPersistentFailureFetch(503);
    const client = fakeAlertsClient();
    const ctx: ToolContext = {
      userId: "test-user",
      isPro: false,
      sb: client,
      requestId: "test-req",
    };
    try {
      await runToolLoop({
        systemPrompt: "you are The Captain",
        userMessage: "how am I doing this week?",
        ctx,
        model: "gemini-2.5-flash",
      });
      assertEquals(client.inserted.length, 1);
      const context = client.inserted[0].context_json as Record<string, unknown>;
      assertEquals(context.hadQueuedIntent, false);
    } finally {
      restore();
    }
  },
);

Deno.test(
  "runToolLoop — happy path never fires reportGeminiExhaustion (mirror case)",
  async () => {
    const original = globalThis.fetch;
    globalThis.fetch = (() =>
      Promise.resolve(functionCallResponse("logSet", {
        exerciseId: "bench_press",
        weightKg: 80,
        reps: 10,
        sets: 4,
      }))) as typeof fetch;
    const client = fakeAlertsClient();
    const ctx: ToolContext = {
      userId: "test-user",
      isPro: false,
      sb: client,
      requestId: "test-req",
    };
    try {
      const result = await runToolLoop({
        systemPrompt: "you are The Captain",
        userMessage: "log my bench: 80kg 4 sets of 10",
        ctx,
        model: "gemini-2.5-flash",
      });
      assertEquals(result.hadHardFailure, false);
      assertEquals(
        client.inserted.length,
        0,
        "a successful tool call must never fire the exhaustion alert",
      );
    } finally {
      globalThis.fetch = original;
    }
  },
);
