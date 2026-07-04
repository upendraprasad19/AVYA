// supabase/functions/_shared/tool-loop_intent_apology_test.ts
//
// FC2 (diagnose 7fbe21) — a queued write intent must NEVER be buried under a
// "trouble reaching the model" apology.
//
// Symptom: the user says "log my bench: 80kg 4x10", round 0 queues a `log_set`
// write intent (the APPLY card the user is looking at), then a LATER
// summarization round hits a transient Gemini failure. Pre-fix, runToolLoop's
// catch block unconditionally set `finalText = "I had trouble reaching the
// model…"` — surfacing an apology OVER a working "Logged" card. The fix gates
// the apology on `!finalText && intents.length === 0`, and the loop-exit path
// replaces the exhaustion message with a POSITIVE "queued below, tap APPLY"
// confirmation when `intents.length > 0`.
//
// This is a BEHAVIORAL test driven end-to-end through runToolLoop. It stubs
// `globalThis.fetch` (geminiChatWithTools calls the global directly, so no
// module-mock shim is needed):
//   • call #1  → a `logSet` functionCall (queues the write intent)
//   • call #2+ → persistent 503 (retriable → the next round exhausts its bounded
//                retry passes and geminiChatWithTools throws → the tool-loop
//                catch fires)
// The assertion: with an intent queued, `runToolLoop().text` is NOT the apology
// AND at least one intent is present.
//
// Run: deno test --allow-env supabase/functions/_shared/tool-loop_intent_apology_test.ts
//
// NOTE: Deno may not be installed on the dev machine — written for CI. It could
// not be executed locally.

import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

// gemini.ts reads GEMINI_API_KEY at eval time — set it before importing anything
// that transitively imports gemini.ts.
Deno.env.set("GEMINI_API_KEY", "test-key-not-a-real-secret");

const { runToolLoop } = await import("./tool-loop.ts");
import type { ToolContext } from "./tools/types.ts";

// ── Fake Response builders ────────────────────────────────────────────
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
        candidates: [
          {
            content: {
              parts: [{ functionCall: { name, args } }],
            },
          },
        ],
        usageMetadata: { totalTokenCount: 11 },
      }),
  } as unknown as Response;
}

function httpErrorResponse(status: number, body = "err"): Response {
  return {
    ok: false,
    status,
    text: () => Promise.resolve(body),
    json: () => Promise.resolve({}),
  } as unknown as Response;
}

/**
 * Stub globalThis.fetch: the FIRST call returns the queued-intent functionCall;
 * every subsequent call returns a retriable 503 (so the next round's bounded
 * retry exhausts and geminiChatWithTools throws). Returns a restore fn.
 */
function installLoggedThenFailFetch(): {
  state: { calls: number };
  restore: () => void;
} {
  const original = globalThis.fetch;
  const state = { calls: 0 };
  globalThis.fetch = ((_input: unknown, _init?: unknown): Promise<Response> => {
    state.calls++;
    if (state.calls === 1) {
      return Promise.resolve(
        functionCallResponse("logSet", {
          exerciseId: "bench_press",
          weightKg: 80,
          reps: 10,
          sets: 4,
        }),
      );
    }
    return Promise.resolve(httpErrorResponse(503, "overloaded"));
  }) as typeof fetch;
  return { state, restore: () => (globalThis.fetch = original) };
}

// Minimal ToolContext — logSet's intentBuilder is synchronous and reads only
// `args`, so `sb` is never touched in this path.
const ctx: ToolContext = {
  userId: "test-user",
  isPro: false,
  // deno-lint-ignore no-explicit-any
  sb: null as any,
  requestId: "test-req",
};

Deno.test(
  "runToolLoop — queued intent + later-round failure does NOT surface the model apology",
  async () => {
    const { restore } = installLoggedThenFailFetch();
    try {
      const result = await runToolLoop({
        systemPrompt: "you are The Captain",
        userMessage: "log my bench: 80kg 4 sets of 10",
        ctx,
        model: "gemini-2.5-flash",
      });

      // The write intent WAS queued.
      assertEquals(result.intents.length, 1);
      assertEquals(result.intents[0].type, "log_set");

      // The user must NOT see the apology over their queued APPLY card.
      assert(
        !result.text.includes("I had trouble reaching the model"),
        `apology leaked over a queued intent: "${result.text}"`,
      );

      // Positive confirmation instead (loop-exit intents.length>0 branch).
      assertStringIncludes(result.text, "APPLY");
    } finally {
      restore();
    }
  },
);
