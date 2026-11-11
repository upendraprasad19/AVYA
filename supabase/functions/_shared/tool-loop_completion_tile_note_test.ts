// supabase/functions/_shared/tool-loop_completion_tile_note_test.ts
//
// Coach workout parity S3 (OI-492; plan docs/plans/coach-workout-parity-2-server.md
// 3.1 1c-1e, 5.1 S3). Driven end to end through the REAL runToolLoop and the
// REAL registry with the scripted fake Gemini. Every case asserts the returned
// intents AND the final toolCallsLog (and the tile functionResponse where the
// model sees one):
//   (i)   tile alone: ONE tile intent pushed after the loop, log tile_requested,
//         note = the tool's conditional queuedNote;
//   (ii)  cross-round [logSet] then [tile], and [tile] then [logSet];
//   (iii) same response [logSet, tile] and [tile, logSet] (decided after
//         the loop from the real intents; an INVALID logSet in the same
//         response still lets the tile show: B-pass seat 1 F1);
//   (iv)  a meal log does not suppress the tile, and a meal intent keeps the
//         existing "tap APPLY" FC2 text;
//   (v)   repeated tile calls give exactly ONE tile intent;
//   (vi)  tile alone, then the summarisation round THROWS: the AUTO fallback,
//         no hard failure, alert hadQueuedIntent:true;
//   (vii) [logSet], [tile], then a throw: the existing FC2 text, no tile;
// plus the rule-off shape, the other tools' byte-identical functionResponse,
// and the execution-time capability gate.

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type FakeReply,
  httpError,
  installFakeFetch,
  okText,
  okToolCall,
  okToolCalls,
} from "./gemini_fake_fetch.ts";

Deno.env.set("GEMINI_API_KEY", "test-key-not-a-real-secret");
const { runToolLoop } = await import("./tool-loop.ts");
const { QUEUED_NOTE } = await import("./write_claim_prompt.ts");
const {
  COMPLETION_TILE_FC2_AUTO_TEXT,
  COMPLETION_TILE_NOT_NEEDED_NOTE,
  COMPLETION_TILE_SAME_RESPONSE_NOTE,
} = await import("./completion_tile_routing.ts");
const { requestCompletionTileTool } = await import(
  "./tools/workout/requestCompletionTile.ts"
);
import type { ToolContext } from "./tools/types.ts";

const TILE = { name: "requestCompletionTile", args: { trigger: "user_says_done" } };
const LOG = {
  name: "logSet",
  args: { exerciseId: "bench_press", weightKg: 60, reps: 8, sets: 3 },
};
const MEAL = { name: "logMealByText", args: { description: "2 rotis and dal" } };
// logMealByText's intentBuilder calls Gemini once (food_parser.ts) inside the
// loop, so the script carries that parse reply right after the meal call.
const MEAL_PARSE = okText(JSON.stringify({
  food_name: "Roti and dal",
  total_calories: 420,
  total_protein_g: 16,
  total_carbs_g: 64,
  total_fat_g: 10,
  serving_description: "2 rotis + 1 katori dal",
  confidence: "high",
  items: [],
}));
const EXISTING_FC2 =
  "Copy that, Recruit — I've queued that below. Review the details and tap APPLY to confirm.";
const CAPS = new Set(["request_completion_tile"]);

function fakeAlertsClient() {
  const inserted: Record<string, unknown>[] = [];
  return {
    inserted,
    from(_table: string) {
      const builder = {
        eq: (_a: string, _b: unknown) => builder,
        is: (_a: string, _b: unknown) => builder,
        gte: (_a: string, _b: unknown) => builder,
        limit: (_n: number) => Promise.resolve({ data: [], error: null }),
      };
      return {
        select: (_cols: string) => builder,
        insert: (row: Record<string, unknown>) => {
          inserted.push(row);
          return Promise.resolve({ error: null });
        },
      };
    },
    // deno-lint-ignore no-explicit-any
  } as any;
}

// deno-lint-ignore no-explicit-any
function ctx(sb: any = null): ToolContext {
  return { userId: "u", isPro: false, sb, requestId: "r" };
}

async function run(
  script: FakeReply[],
  opts: { writeClaimRule?: boolean; capabilities?: Set<string>; sb?: unknown } = {},
) {
  const { calls, restore } = installFakeFetch(script);
  try {
    const result = await runToolLoop({
      systemPrompt: "you are The Captain",
      userMessage: "I'm done",
      ctx: ctx(opts.sb),
      model: "gemini-3.1-flash-lite",
      capabilities: opts.capabilities ?? CAPS,
      ...(opts.writeClaimRule === undefined
        ? {}
        : { writeClaimRule: opts.writeClaimRule }),
    });
    return { result, calls };
  } finally {
    restore();
  }
}

// The functionResponse the model received for [name] in request [i].
// deno-lint-ignore no-explicit-any
function responseFor(calls: { body: any }[], i: number, name: string) {
  const turn = calls[i].body.contents[calls[i].body.contents.length - 1];
  const part = turn.parts.find(
    (p: { functionResponse?: { name: string } }) =>
      p.functionResponse?.name === name,
  );
  return part?.functionResponse.response as Record<string, unknown>;
}

function tileLogStatuses(log: { name: string; status: string }[]): string[] {
  return log.filter((r) => r.name === "requestCompletionTile").map((r) =>
    r.status
  );
}

function types(intents: { type: string }[]): string[] {
  return intents.map((i) => i.type);
}

Deno.test("(i) tile alone: one tile intent after the loop, tile_requested, conditional note", async () => {
  const { result, calls } = await run([
    okToolCall(TILE.name, TILE.args),
    okText("Tap Complete workout on the tile below to finish today."),
  ]);
  assertEquals(types(result.intents), ["request_completion_tile"]);
  assertEquals(result.intents[0].payload, {});
  assert(typeof result.intents[0].id === "string" && result.intents[0].id.length > 0);
  assertEquals(tileLogStatuses(result.toolCallsLog), ["tile_requested"]);
  const r = responseFor(calls, 1, TILE.name);
  assertEquals(r.status, "tile_requested");
  assertEquals(r.note, requestCompletionTileTool.queuedNote);
  assert(!("intent_id" in r));
  assertEquals(result.hadHardFailure, false);
});

Deno.test("(i) rule off: tile_requested with no note key", async () => {
  const { result, calls } = await run([
    okToolCall(TILE.name, TILE.args),
    okText("ok"),
  ], { writeClaimRule: false });
  assertEquals(types(result.intents), ["request_completion_tile"]);
  assertEquals(Object.keys(responseFor(calls, 1, TILE.name)), ["status"]);
  assertEquals(responseFor(calls, 1, TILE.name).status, "tile_requested");
});

Deno.test("other tools: the logSet functionResponse is byte-identical to the generic queued shape", async () => {
  const { result, calls } = await run([
    okToolCall(LOG.name, LOG.args),
    okText("Queued. Tap APPLY to log it."),
  ]);
  assertEquals(types(result.intents), ["log_set"]);
  const r = responseFor(calls, 1, LOG.name);
  assertEquals(r, {
    status: "queued_for_user_confirmation",
    intent_id: result.intents[0].id,
    note: QUEUED_NOTE,
  });
  assertEquals(result.toolCallsLog.map((x) => x.status), ["queued"]);
});

Deno.test("(ii) cross-round [logSet] then [tile]: tile not_needed, only the log_set intent", async () => {
  const { result, calls } = await run([
    okToolCall(LOG.name, LOG.args),
    okToolCall(TILE.name, TILE.args),
    okText("Queued. Tap APPLY to log it."),
  ]);
  assertEquals(types(result.intents), ["log_set"]);
  assertEquals(tileLogStatuses(result.toolCallsLog), ["not_needed"]);
  assertEquals(responseFor(calls, 2, TILE.name), {
    status: "not_needed",
    note: COMPLETION_TILE_NOT_NEEDED_NOTE,
  });
});

Deno.test("(ii) cross-round [tile] then [logSet]: tile_requested in round 1, rewritten to not_needed, no tile intent", async () => {
  const { result, calls } = await run([
    okToolCall(TILE.name, TILE.args),
    okToolCall(LOG.name, LOG.args),
    okText("Queued. Tap APPLY to log it."),
  ]);
  assertEquals(responseFor(calls, 1, TILE.name).status, "tile_requested");
  assertEquals(types(result.intents), ["log_set"]);
  assertEquals(tileLogStatuses(result.toolCallsLog), ["not_needed"]);
});

for (const order of [[LOG, TILE], [TILE, LOG]]) {
  Deno.test(`(iii) same response [${order.map((o) => o.name).join(", ")}]: one log_set intent, tile not_needed after the loop, existing FC2 text`, async () => {
    const { result, calls } = await run([
      okToolCalls(order),
      httpError(503, "overloaded"),
    ], { sb: fakeAlertsClient() });
    assertEquals(types(result.intents), ["log_set"]);
    assertEquals(tileLogStatuses(result.toolCallsLog), ["not_needed"]);
    // logSet first: its intent is already queued when the tile call is
    // read, so the answer is definite. Tile first: the outcome is not known
    // yet, so the model reads the note that covers both.
    assertEquals(
      responseFor(calls, 1, TILE.name),
      order[0] === LOG
        ? { status: "not_needed", note: COMPLETION_TILE_NOT_NEEDED_NOTE }
        : { status: "tile_requested", note: COMPLETION_TILE_SAME_RESPONSE_NOTE },
    );
    assertEquals(result.text, EXISTING_FC2);
  });

  Deno.test(`(iii) same response [${order.map((o) => o.name).join(", ")}] with an INVALID logSet: no log_set intent, so the tile IS pushed (B-pass seat 1 F1)`, async () => {
    const bad = order.map((o) =>
      o === LOG ? { name: LOG.name, args: { exerciseId: "bench_press" } } : o
    );
    const { result, calls } = await run([
      okToolCalls(bad),
      okText("Tap Complete workout on the tile below to finish today."),
    ]);
    assertEquals(
      result.toolCallsLog.find((r) => r.name === LOG.name)?.status,
      "invalid_args",
    );
    assertEquals(types(result.intents), ["request_completion_tile"]);
    assertEquals(tileLogStatuses(result.toolCallsLog), ["tile_requested"]);
    assertEquals(responseFor(calls, 1, TILE.name), {
      status: "tile_requested",
      note: COMPLETION_TILE_SAME_RESPONSE_NOTE,
    });
  });
}

Deno.test("(iv) [logMealByText] then [tile]: both intents kept (a meal log does not suppress)", async () => {
  const { result } = await run([
    okToolCall(MEAL.name, MEAL.args),
    MEAL_PARSE,
    okToolCall(TILE.name, TILE.args),
    okText("ok"),
  ]);
  assertEquals(types(result.intents), ["log_meal_by_text", "request_completion_tile"]);
  assertEquals(tileLogStatuses(result.toolCallsLog), ["tile_requested"]);
});

Deno.test("(iv) same response [logMealByText, tile] + summarisation THROWS: both intents, the existing tap-APPLY FC2 text", async () => {
  const { result } = await run([
    okToolCalls([MEAL, TILE]),
    MEAL_PARSE,
    httpError(503, "overloaded"),
  ], { sb: fakeAlertsClient() });
  assertEquals(types(result.intents), ["log_meal_by_text", "request_completion_tile"]);
  assertEquals(result.text, EXISTING_FC2);
  assertEquals(result.hadHardFailure, false);
});

Deno.test("(v) repeated tile calls (same response and a later round): exactly ONE tile intent", async () => {
  const { result } = await run([
    okToolCalls([TILE, TILE]),
    okToolCall(TILE.name, TILE.args),
    okText("ok"),
  ]);
  assertEquals(types(result.intents), ["request_completion_tile"]);
  assertEquals(tileLogStatuses(result.toolCallsLog), [
    "tile_requested",
    "tile_requested",
    "tile_requested",
  ]);
});

Deno.test("(vi) tile alone, then the summarisation round THROWS: AUTO fallback, no hard failure, alert hadQueuedIntent:true", async () => {
  const sb = fakeAlertsClient();
  const { result } = await run([
    okToolCall(TILE.name, TILE.args),
    httpError(503, "overloaded"),
  ], { sb });
  assertEquals(result.text, COMPLETION_TILE_FC2_AUTO_TEXT);
  assertEquals(result.hadHardFailure, false);
  assertEquals(result.failureKind, "none");
  assertEquals(types(result.intents), ["request_completion_tile"]);
  assertEquals(sb.inserted.length, 1);
  const context = sb.inserted[0].context_json as Record<string, unknown>;
  assertEquals(context.hadQueuedIntent, true);
});

Deno.test("(vii) [logSet], [tile], then a throw: the existing FC2 text, one log_set intent, no tile", async () => {
  const { result } = await run([
    okToolCall(LOG.name, LOG.args),
    okToolCall(TILE.name, TILE.args),
    httpError(503, "overloaded"),
  ], { sb: fakeAlertsClient() });
  assertEquals(result.text, EXISTING_FC2);
  assertEquals(types(result.intents), ["log_set"]);
  assertEquals(tileLogStatuses(result.toolCallsLog), ["not_needed"]);
});

Deno.test("an invalid trigger is invalid_args (the tile branch sits after the Zod check)", async () => {
  const { result } = await run([
    okToolCall(TILE.name, { trigger: "something_else" }),
    okText("ok"),
  ]);
  assertEquals(result.intents.length, 0);
  assertEquals(tileLogStatuses(result.toolCallsLog), ["invalid_args"]);
});

Deno.test("capability gate: without request_completion_tile the call is capability_blocked, 0 intents", async () => {
  const { result, calls } = await run([
    okToolCall(TILE.name, TILE.args),
    okText("ok"),
  ], { capabilities: new Set() });
  assertEquals(result.intents.length, 0);
  assertEquals(tileLogStatuses(result.toolCallsLog), ["capability_blocked"]);
  assertEquals(responseFor(calls, 1, TILE.name).error, "capability_required");
  // Not offered either.
  const declared = calls[0].body.tools[0].functionDeclarations.map(
    (d: { name: string }) => d.name,
  );
  assert(!declared.includes(TILE.name));
});

Deno.test("capability gate mirror: with the capability the tool is offered and yields 1 intent", async () => {
  const { result, calls } = await run([
    okToolCall(TILE.name, TILE.args),
    okText("ok"),
  ]);
  const declared = calls[0].body.tools[0].functionDeclarations.map(
    (d: { name: string }) => d.name,
  );
  assert(declared.includes(TILE.name));
  assertEquals(result.intents.length, 1);
  assertEquals(tileLogStatuses(result.toolCallsLog), ["tile_requested"]);
});

Deno.test("the post-loop push fails closed: a throwing intentBuilder gives no tile intent and every tile record 'failed' (B-pass seat 1 F2)", async () => {
  // The registry holds this same object, so swapping its builder for one
  // test reaches the post-loop catch without a test-only seam in tool-loop.
  const original = requestCompletionTileTool.intentBuilder;
  requestCompletionTileTool.intentBuilder = () => {
    throw new Error("builder_boom");
  };
  try {
    const { result } = await run([
      okToolCall(TILE.name, TILE.args),
      okText("ok"),
    ]);
    assertEquals(result.intents.length, 0);
    assertEquals(tileLogStatuses(result.toolCallsLog), ["failed"]);
    const rec = result.toolCallsLog.find((r) => r.name === TILE.name) as {
      error?: string;
    };
    assert(rec.error?.includes("builder_boom"));
    assertEquals(result.hadHardFailure, false);
  } finally {
    requestCompletionTileTool.intentBuilder = original;
  }
});
