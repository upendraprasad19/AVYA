/**
 * Multi-round Gemini tool-calling orchestrator.
 *
 * Added 2026-04-19 as part of the AI Coach Tool-Calling project (Phase A.4).
 *
 * Algorithm (per docs/superpowers/specs/2026-04-18-ai-coach-tool-calling-design.md):
 *
 *   round = 0..MAX_ROUNDS-1:
 *     call geminiChatWithTools(messages, tools)
 *     if no functionCalls → break (final text response)
 *     for each functionCall:
 *       look up tool in registry
 *       if unknown:                  add `unknown` telemetry,
 *                                    feed back {error: "unknown_tool"}
 *       elif PRO-gated && !isPro:    add `pro_blocked` telemetry,
 *                                    feed back {error: "pro_required"}
 *       else validate args via Zod:
 *         if invalid:                add `invalid_args` telemetry,
 *                                    feed back trimmed details so the
 *                                    model can self-correct on the next round
 *         elif tool.kind === 'read': run handler with maxLatencyMs timeout,
 *                                    feed back the data (or error)
 *         else (write):              build typed intent via tool.intentBuilder,
 *                                    push to intents[], feed back
 *                                    {status: "queued_for_user_confirmation"}
 *                                    so the model can compose narration
 *
 *     append model's last turn (parts) AND the function responses to messages
 *
 *   if loop ran out of rounds without a text break:
 *     finalText = "I started working on that but ran out of steps — try
 *                  again with a more specific request."
 *
 * Per-tool failure isolation: one tool's error never aborts the batch. Each
 * functionCall produces exactly one corresponding functionResponse part so the
 * model's next turn sees a 1:1 mapping (Gemini contract requirement).
 *
 * Caller (ai-proxy) is responsible for:
 *   - Building the system prompt (incl. coach_memory) before invoking us.
 *   - Persisting `toolCallsLog` into ai_coach_interactions.tool_calls.
 *   - Returning `intents` to the client for confirmation + Hive execution.
 */

import { allTools, byName } from "./tools/registry.ts";
import { toolToFunctionDeclaration } from "./tools/zodToGemini.ts";
import type {
  ToolCallRecord,
  ToolContext,
  ToolIntent,
} from "./tools/types.ts";
import {
  type GeminiContent,
  type GeminiPart,
  geminiChatWithTools,
  type GeminiToolsResult,
} from "./gemini.ts";

const MAX_ROUNDS = 3;

export interface ToolLoopOptions {
  /** System prompt — already assembled by caller (7-block layout incl. coach_memory). */
  systemPrompt: string;
  /** The user's message text. */
  userMessage: string;
  /**
   * Snapshot JSON for context — already inside systemPrompt; passed here
   * only if the loop needs to log it. Optional and currently unused by the
   * loop itself; kept on the API surface for telemetry callers.
   */
  snapshot?: Record<string, unknown>;
  /** Authentication + Supabase client + tier flag. */
  ctx: ToolContext;
  /** Model — typically MODEL_FLASH from gemini.ts. */
  model: string;
  /** Optional override for max rounds (default MAX_ROUNDS=3). Used by tests. */
  maxRounds?: number;
}

export interface ToolLoopResult {
  /**
   * Final user-visible text from the model. Falls back to a generic apology
   * if MAX_ROUNDS is exhausted without a terminal response.
   */
  text: string;
  /** Typed write intents queued for client-side confirmation + execution. */
  intents: ToolIntent[];
  /** Per-tool-call telemetry record for ai_coach_interactions.tool_calls. */
  toolCallsLog: ToolCallRecord[];
  /** Total Gemini tokens consumed across all rounds. */
  tokensUsed: number;
  /** Whether at least one round used the Flash-Lite fallback. */
  usedFallback: boolean;
  /** Number of rounds executed (1..maxRounds). */
  roundsExecuted: number;
}

export async function runToolLoop(opts: ToolLoopOptions): Promise<ToolLoopResult> {
  const maxRounds = opts.maxRounds ?? MAX_ROUNDS;

  const messages: GeminiContent[] = [
    { role: "user", parts: [{ text: opts.userMessage }] },
  ];
  const intents: ToolIntent[] = [];
  const toolCallsLog: ToolCallRecord[] = [];
  let tokensUsed = 0;
  let usedFallback = false;
  let finalText = "";
  let roundsExecuted = 0;

  // Tier-filtered tool list passed to the model. Pre-converted once
  // (registry is small; conversion is cheap; doing it once avoids
  // re-walking the Zod schemas every round).
  const visibleTools = allTools(opts.ctx.isPro).map(toolToFunctionDeclaration);

  for (let round = 0; round < maxRounds; round++) {
    roundsExecuted = round + 1;

    let resp: GeminiToolsResult;
    try {
      resp = await geminiChatWithTools({
        model: opts.model,
        systemPrompt: opts.systemPrompt,
        messages,
        tools: visibleTools,
        requestId: opts.ctx.requestId,
      });
    } catch (e) {
      // Hard Gemini failure — abandon the loop. Surface a generic apology
      // unless we already have partial text from an earlier round.
      console.error(
        `[tool-loop] gemini call failed round=${round} request_id=${opts.ctx.requestId}`,
        e,
      );
      if (!finalText) {
        finalText = "I had trouble reaching the model. Try again in a moment.";
      }
      break;
    }

    tokensUsed += resp.tokensUsed;
    if (resp.usedFallback) usedFallback = true;

    // No tool calls → terminal response. We're done.
    if (resp.functionCalls.length === 0) {
      finalText = resp.text;
      break;
    }

    // Append the model's turn to history before processing tool calls.
    // Gemini requires the model turn to precede the function-response turn.
    messages.push({ role: "model", parts: resp.parts });

    // Process each tool call. Each call yields exactly one functionResponse
    // part, in order — Gemini matches them positionally, so 1:1 is mandatory.
    const responseParts: GeminiPart[] = [];

    for (const call of resp.functionCalls) {
      const startMs = Date.now();
      const tool = byName(call.name);

      // ── Unknown tool ───────────────────────────────────────────
      if (!tool) {
        toolCallsLog.push({ name: call.name, status: "unknown" });
        responseParts.push({
          functionResponse: {
            name: call.name,
            response: { error: "unknown_tool" },
          },
        });
        continue;
      }

      // ── Tier check (PRO tools blocked for free users) ──────────
      if (tool.tier === "pro" && !opts.ctx.isPro) {
        toolCallsLog.push({ name: call.name, status: "pro_blocked" });
        responseParts.push({
          functionResponse: {
            name: call.name,
            response: {
              error: "pro_required",
              message: `${call.name} requires PRO subscription`,
            },
          },
        });
        continue;
      }

      // ── Args validation via Zod ────────────────────────────────
      const parsed = tool.schema.safeParse(call.args);
      if (!parsed.success) {
        toolCallsLog.push({
          name: call.name,
          status: "invalid_args",
          args: call.args,
        });
        responseParts.push({
          functionResponse: {
            name: call.name,
            response: {
              error: "invalid_args",
              // Trim to first 3 issues — keep the response payload small
              // so the model isn't biased toward fixating on validation.
              details: parsed.error.issues.slice(0, 3).map((i) => ({
                path: i.path.join("."),
                message: i.message,
              })),
            },
          },
        });
        continue;
      }

      // ── Execute by kind ────────────────────────────────────────
      if (tool.kind === "read") {
        if (!tool.handler) {
          // Misconfigured tool definition — should be caught at registry
          // load time but guard here too.
          toolCallsLog.push({
            name: call.name,
            status: "failed",
            error: "no_handler",
          });
          responseParts.push({
            functionResponse: {
              name: call.name,
              response: { error: "internal", message: "tool has no handler" },
            },
          });
          continue;
        }

        const maxLatency = tool.maxLatencyMs ?? 3000;
        let timeoutHandle: number | undefined;

        try {
          const data = await Promise.race<unknown>([
            tool.handler(opts.ctx, parsed.data),
            new Promise<never>((_, reject) => {
              timeoutHandle = setTimeout(
                () => reject(new Error("tool_timeout")),
                maxLatency,
              );
            }),
          ]);
          if (timeoutHandle !== undefined) clearTimeout(timeoutHandle);

          toolCallsLog.push({
            name: call.name,
            status: "ok",
            args: parsed.data as Record<string, unknown>,
            latency_ms: Date.now() - startMs,
          });
          responseParts.push({
            functionResponse: {
              name: call.name,
              // Wrap non-object results so the response is always a JSON object
              // (Gemini's functionResponse expects an object payload).
              response: _wrapAsObject(data),
            },
          });
        } catch (e) {
          if (timeoutHandle !== undefined) clearTimeout(timeoutHandle);
          const isTimeout = (e as Error)?.message === "tool_timeout";
          toolCallsLog.push({
            name: call.name,
            status: isTimeout ? "timeout" : "failed",
            args: parsed.data as Record<string, unknown>,
            latency_ms: Date.now() - startMs,
            error: String(e),
          });
          responseParts.push({
            functionResponse: {
              name: call.name,
              response: {
                error: isTimeout ? "tool_timeout" : "execution_failed",
                message: isTimeout
                  ? `${call.name} took too long`
                  : `${call.name} failed`,
              },
            },
          });
        }
      } else {
        // ── Write — build intent, queue, short-circuit ───────────
        if (!tool.intentBuilder) {
          toolCallsLog.push({
            name: call.name,
            status: "failed",
            error: "no_intent_builder",
          });
          responseParts.push({
            functionResponse: {
              name: call.name,
              response: {
                error: "internal",
                message: "tool has no intentBuilder",
              },
            },
          });
          continue;
        }

        try {
          const partial = tool.intentBuilder(parsed.data);
          const intent: ToolIntent = {
            ...partial,
            id: crypto.randomUUID(),
            createdAt: new Date().toISOString(),
          };
          intents.push(intent);
          toolCallsLog.push({
            name: call.name,
            status: "queued",
            args: parsed.data as Record<string, unknown>,
          });
          responseParts.push({
            functionResponse: {
              name: call.name,
              response: {
                status: "queued_for_user_confirmation",
                intent_id: intent.id,
              },
            },
          });
        } catch (e) {
          // intentBuilder shouldn't throw, but isolate failures so a buggy
          // builder doesn't kill the rest of the batch.
          toolCallsLog.push({
            name: call.name,
            status: "failed",
            args: parsed.data as Record<string, unknown>,
            error: String(e),
          });
          responseParts.push({
            functionResponse: {
              name: call.name,
              response: {
                error: "intent_build_failed",
                message: `${call.name} could not be queued`,
              },
            },
          });
        }
      }
    }

    // Feed all function responses back to the model in one turn.
    // Per the live Gemini REST docs (verified 2026-04-19), the role for
    // the tool-result turn is "user" — the model treats functionResponse
    // parts as user-supplied input. Some older spec drafts called for
    // role:"function", but the live API rejects that with a 400.
    messages.push({ role: "user", parts: responseParts });
  }

  // Loop exhausted without a terminal text response.
  if (!finalText) {
    finalText =
      "I started working on that but ran out of steps — try again with a more specific request.";
  }

  return {
    text: finalText,
    intents,
    toolCallsLog,
    tokensUsed,
    usedFallback,
    roundsExecuted,
  };
}

/**
 * Gemini's functionResponse.response field is typed as an object. If a read
 * tool returns a primitive or an array, wrap it under a `value` key so the
 * round-trip stays well-formed.
 */
function _wrapAsObject(data: unknown): Record<string, unknown> {
  if (data !== null && typeof data === "object" && !Array.isArray(data)) {
    return data as Record<string, unknown>;
  }
  return { value: data };
}
