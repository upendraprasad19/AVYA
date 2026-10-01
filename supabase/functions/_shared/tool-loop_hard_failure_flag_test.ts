// supabase/functions/_shared/tool-loop_hard_failure_flag_test.ts
//
// APK +43 obs 2 — `runToolLoop`'s hardcoded "I had trouble reaching the
// model" apology gets persisted by ai-proxy as a NORMAL successful turn
// (HTTP 200, a real model label) and replayed into the client's next-request
// `history` by `recentHistoryExchanges()` — which has no way to tell it apart
// from real model output. Live evidence (2026-09-15, request_id 50300807):
// a genuine Gemini quota exhaustion produced the apology at 01:51/01:52 IST;
// by 18:29 IST the SAME account's flash-lite fallback got a real Gemini
// response ("[geminiChatWithTools] fallback succeeded" in the function logs)
// yet the persisted reply was STILL the literal apology string — the model,
// given two recent apology turns in its own history, echoed the pattern back
// rather than answering "hi".
//
// FIX: `ToolLoopResult.hadHardFailure` is true when EITHER of tool-loop.ts's
// two hardcoded, non-model apology texts fires: the catch-block one (every
// bounded Gemini retry pass genuinely exhausted, per diagnose d4f1c2's
// bounded-retry mechanism) AND the loop-exhausted-without-a-terminal-
// response one (maxRounds hit with no text and no queued intent — a
// B-pass finding on this same batch, 2026-09-16: the first version of this
// fix covered only the catch-block apology, leaving the second one able to
// replay into history exactly the same way). ai-proxy threads the flag to
// the client as `had_hard_failure`, and the client marks the Hive row
// `failed: true` so it's excluded from replay — see
// coach_chat_history_replay_writer_to_reader_test.dart (Dart side) for the
// writer/reader pin on the Hive flag itself.
//
// This file pins the SERVER-side origin of that flag, end-to-end through
// runToolLoop: a positive control for EACH of the two apology sites, plus
// two negative controls (a clean happy path; a queued-intent turn that hits
// the SAME persistent failure but must NOT be flagged — mirrors
// tool-loop_intent_apology_test.ts's FC2 case, which already asserts the
// TEXT isn't the apology but never asserted the flag itself).
//
// Run: deno test --no-check --allow-env --node-modules-dir=none
//      supabase/functions/_shared/tool-loop_hard_failure_flag_test.ts

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

// gemini.ts reads GEMINI_API_KEY at eval time — set it before importing
// anything that transitively imports gemini.ts.
Deno.env.set("GEMINI_API_KEY", "test-key-not-a-real-secret");

const { runToolLoop } = await import("./tool-loop.ts");
import type { ToolContext } from "./tools/types.ts";

function httpErrorResponse(status: number, body = "err"): Response {
  return {
    ok: false,
    status,
    text: () => Promise.resolve(body),
    json: () => Promise.resolve({}),
  } as unknown as Response;
}

function textResponse(text: string): Response {
  return {
    ok: true,
    status: 200,
    text: () => Promise.resolve(""),
    json: () =>
      Promise.resolve({
        candidates: [{ content: { parts: [{ text }] } }],
        usageMetadata: { totalTokenCount: 42 },
      }),
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
        candidates: [
          { content: { parts: [{ functionCall: { name, args } }] } },
        ],
        usageMetadata: { totalTokenCount: 11 },
      }),
  } as unknown as Response;
}

function installAlwaysFailFetch(): { restore: () => void } {
  const original = globalThis.fetch;
  // Persistent 429 on every attempt/pass/model — mirrors the live evidence
  // exactly ("You exceeded your current quota…" on both gemini-2.5-flash
  // AND gemini-2.5-flash-lite, both bounded-retry passes).
  globalThis.fetch = ((_input: unknown, _init?: unknown): Promise<Response> =>
    Promise.resolve(httpErrorResponse(429, "quota exceeded"))) as typeof fetch;
  return { restore: () => (globalThis.fetch = original) };
}

function installHappyFetch(reply: string): { restore: () => void } {
  const original = globalThis.fetch;
  globalThis.fetch = ((_input: unknown, _init?: unknown): Promise<Response> =>
    Promise.resolve(textResponse(reply))) as typeof fetch;
  return { restore: () => (globalThis.fetch = original) };
}

function installAlwaysReadToolCallFetch(): { restore: () => void } {
  const original = globalThis.fetch;
  // Every round the model calls a READ tool (getFormCues) — never returns
  // terminal text, never queues a write intent. With ctx.sb null (below)
  // the tool's own handler throws, which tool-loop.ts's per-call catch
  // swallows into a "failed" functionResponse — the loop just keeps going.
  // After maxRounds rounds this hits the loop-exhausted-without-intents
  // branch (tool-loop.ts's OTHER hardcoded apology, distinct from the
  // catch-block one the other 3 tests in this file pin).
  globalThis.fetch = ((_input: unknown, _init?: unknown): Promise<Response> =>
    Promise.resolve(
      functionCallResponse("getFormCues", { exercise_name: "Bench Press" }),
    )) as typeof fetch;
  return { restore: () => (globalThis.fetch = original) };
}

function installLoggedThenFailFetch(): { restore: () => void } {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = ((_input: unknown, _init?: unknown): Promise<Response> => {
    calls++;
    if (calls === 1) {
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
  return { restore: () => (globalThis.fetch = original) };
}

const ctx: ToolContext = {
  userId: "test-user",
  isPro: false,
  // deno-lint-ignore no-explicit-any
  sb: null as any,
  requestId: "test-req",
};

Deno.test(
  "runToolLoop — hadHardFailure=true + exact apology text when every retry pass exhausts",
  async () => {
    const { restore } = installAlwaysFailFetch();
    try {
      const result = await runToolLoop({
        systemPrompt: "you are The Captain",
        userMessage: "hi",
        ctx,
        model: "gemini-2.5-flash",
      });

      assertEquals(result.hadHardFailure, true);
      assertEquals(
        result.text,
        "I had trouble reaching the model. Try again in a moment.",
      );
      assertEquals(result.intents.length, 0);
    } finally {
      restore();
    }
  },
);

Deno.test(
  "runToolLoop — hadHardFailure=false on the happy path (mirror of the positive control)",
  async () => {
    const { restore } = installHappyFetch("Hey Recruit, good to see you.");
    try {
      const result = await runToolLoop({
        systemPrompt: "you are The Captain",
        userMessage: "hi",
        ctx,
        model: "gemini-2.5-flash",
      });

      assertEquals(result.hadHardFailure, false);
      assertEquals(result.text, "Hey Recruit, good to see you.");
    } finally {
      restore();
    }
  },
);

Deno.test(
  "runToolLoop — hadHardFailure=false when a write intent was queued before a later-round failure (FC2 case)",
  async () => {
    const { restore } = installLoggedThenFailFetch();
    try {
      const result = await runToolLoop({
        systemPrompt: "you are The Captain",
        userMessage: "log my bench: 80kg 4 sets of 10",
        ctx,
        model: "gemini-2.5-flash",
      });

      // Sanity: this is the same scenario tool-loop_intent_apology_test.ts
      // exercises (an intent queued, then a persistent failure). The flag
      // must stay false here — the FC2 branch (a queued intent) is a
      // DIFFERENT code path from the hard-failure catch this flag pins, and
      // the positive "queued below, tap APPLY" text is real, not a
      // hardcoded-apology substitute that should be excluded from replay.
      assertEquals(result.intents.length, 1);
      assertEquals(result.hadHardFailure, false);
    } finally {
      restore();
    }
  },
);

Deno.test(
  "runToolLoop — hadHardFailure=true + the OTHER apology text when rounds " +
    "exhaust with no terminal text and no queued intents (B-pass finding)",
  async () => {
    const { restore } = installAlwaysReadToolCallFetch();
    try {
      const result = await runToolLoop({
        systemPrompt: "you are The Captain",
        userMessage: "how do I do a bench press",
        ctx,
        model: "gemini-2.5-flash",
        maxRounds: 2,
      });

      assertEquals(result.intents.length, 0);
      assertEquals(
        result.text,
        "Recruit — I had trouble pinning that down. Try asking again with " +
          "a bit more specificity. If you want today's workout or your " +
          'current plan, ask plainly: "what\'s my workout today" or ' +
          '"what\'s my plan" — I\'ll read the manifest directly.',
      );
      assertEquals(result.hadHardFailure, true);
    } finally {
      restore();
    }
  },
);
