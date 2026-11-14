// supabase/functions/_shared/tool-loop_capability_gate_test.ts
//
// F2 (Task 27 review, "Important" finding; Task 27 fix round) — tool-loop.ts
// executed a tool by NAME (`byName(call.name)`) and only re-checked
// `tool.tier` at execution time. The capability gate (`tool.requiresCapability`
// against the caller's declared `client_capabilities`) was applied ONLY at
// the earlier `visibleTools = allTools(isPro, capabilities)` offer step. In
// the normal case Gemini can't call a tool it was never offered, but nothing
// stopped a functionCall by name for a tool that was never offered —
// hallucinated, or recalled from an earlier turn's `history` — from reaching
// full execution against a client build that never declared support for it
// (e.g. an old client that predates the day-swap engine, receiving a
// `swap_workout_days` intent it cannot render or apply).
//
// This is a BEHAVIORAL test driven end-to-end through the REAL `runToolLoop`
// and the REAL production tool registry (swapWorkoutDaysTool, already
// `requiresCapability: "swap_workout_days"` per Task 27). It stubs
// `globalThis.fetch` exactly as tool-loop_intent_apology_test.ts and
// tool-loop_hard_failure_flag_test.ts already do (geminiChatWithTools calls
// the global directly, so no module-mock shim is needed):
//   • call #1 → a `swapWorkoutDays` functionCall with valid args (simulating
//     the model calling a tool it may never have been offered)
//   • call #2 → a terminal text response (ends the loop cleanly)
//
// Two cases:
//   1. Capability NOT declared by the caller → the tool must NOT execute:
//      no intent queued, toolCallsLog records `capability_blocked`, and the
//      functionResponse fed back to the model carries `capability_required`.
//   2. Capability IS declared (the mirror) → the tool executes normally:
//      the intent IS queued, toolCallsLog records `queued`.
//
// Mutation proof (recorded in task-27-fix1-report.md): deleting the new
// execution-time capability check in tool-loop.ts reddens case 1 only (case
// 2 stays green, since a client that DID declare the capability was never
// affected by the missing check).
//
// Run: deno test --allow-all --node-modules-dir=none
//      supabase/functions/_shared/tool-loop_capability_gate_test.ts

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

// gemini.ts reads GEMINI_API_KEY at eval time — set it before importing
// anything that transitively imports gemini.ts.
Deno.env.set("GEMINI_API_KEY", "test-key-not-a-real-secret");

const { runToolLoop } = await import("./tool-loop.ts");
import type { ToolContext } from "./tools/types.ts";

function textResponse(text: string): Response {
  return {
    ok: true,
    status: 200,
    text: () => Promise.resolve(""),
    json: () =>
      Promise.resolve({
        candidates: [{ content: { parts: [{ text }] } }],
        usageMetadata: { totalTokenCount: 5 },
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

/**
 * Stub globalThis.fetch: the FIRST call returns a `swapWorkoutDays`
 * functionCall (as if the model called it, offered or not); every
 * subsequent call returns a terminal text response so the loop ends
 * cleanly in round 2 without exhausting maxRounds.
 */
function installSwapCallThenTextFetch(): { restore: () => void } {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = ((_input: unknown, _init?: unknown): Promise<Response> => {
    calls++;
    if (calls === 1) {
      return Promise.resolve(
        functionCallResponse("swapWorkoutDays", {
          dateA: "2026-09-25",
          dateB: "2026-09-26",
        }),
      );
    }
    return Promise.resolve(textResponse("done"));
  }) as typeof fetch;
  return { restore: () => (globalThis.fetch = original) };
}

// swapWorkoutDays is `tier: "pro"`, so isPro must be true here — this test is
// isolating the CAPABILITY check, not the tier check (tool-loop.ts checks
// tier first; a tier failure would short-circuit before the capability
// check ever ran, which would prove nothing about F2).
const proCtx: ToolContext = {
  userId: "test-user",
  isPro: true,
  // deno-lint-ignore no-explicit-any
  sb: null as any,
  requestId: "test-req-capability-gate",
};

Deno.test(
  "runToolLoop — a capability-gated tool called by name WITHOUT the declared capability does NOT execute",
  async () => {
    const { restore } = installSwapCallThenTextFetch();
    try {
      const result = await runToolLoop({
        systemPrompt: "you are The Captain",
        userMessage: "swap Friday and Saturday",
        ctx: proCtx,
        model: "gemini-3.1-flash-lite",
        // No `capabilities` passed at all — the exact shape of an old
        // client build that predates `client_capabilities` entirely, or one
        // that simply never declared this specific capability.
      });

      // The tool must NOT have executed: no intent queued.
      assertEquals(result.intents.length, 0);

      // toolCallsLog must record the refusal, not an execution.
      const call = result.toolCallsLog.find((c) => c.name === "swapWorkoutDays");
      assertEquals(call?.status, "capability_blocked");
    } finally {
      restore();
    }
  },
);

Deno.test(
  "runToolLoop — a capability-gated tool called by name WITH the declared capability executes normally (mirror)",
  async () => {
    const { restore } = installSwapCallThenTextFetch();
    try {
      const result = await runToolLoop({
        systemPrompt: "you are The Captain",
        userMessage: "swap Friday and Saturday",
        ctx: proCtx,
        model: "gemini-3.1-flash-lite",
        capabilities: new Set(["swap_workout_days"]),
      });

      // The tool DID execute (queued its write intent, as a write tool does).
      assertEquals(result.intents.length, 1);
      assertEquals(result.intents[0].type, "swap_workout_days");
      assertEquals(result.intents[0].payload, {
        dateA: "2026-09-25",
        dateB: "2026-09-26",
      });

      const call = result.toolCallsLog.find((c) => c.name === "swapWorkoutDays");
      assertEquals(call?.status, "queued");
    } finally {
      restore();
    }
  },
);
