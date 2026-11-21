// supabase/functions/_shared/tool-loop_write_claim_note_test.ts
//
// coach-log-truth (OI-368 / OI-369, plan docs/plans/coach-log-truth.md §2.1).
// Driven end to end through runToolLoop with the scripted fake Gemini: a
// queued tool's functionResponse tells the model the item is NOT saved yet
// (rule on, or the option left undefined) and is byte-identical to before
// with the rule off; the meal and template tool declarations stop claiming a
// save with the rule on.

import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { installFakeFetch, okText, okToolCall } from "./gemini_fake_fetch.ts";

Deno.env.set("GEMINI_API_KEY", "test-key-not-a-real-secret");
const { runToolLoop } = await import("./tool-loop.ts");
const { QUEUED_NOTE } = await import("./write_claim_prompt.ts");
import type { ToolContext } from "./tools/types.ts";

function ctx(isPro: boolean): ToolContext {
  // deno-lint-ignore no-explicit-any
  return { userId: "u", isPro, sb: null as any, requestId: "r" };
}

// deno-lint-ignore no-explicit-any
function queuedResponse(body: any): Record<string, unknown> {
  const turn = body.contents[body.contents.length - 1];
  const part = turn.parts.find((p: Record<string, unknown>) => p.functionResponse);
  return part.functionResponse.response;
}

// deno-lint-ignore no-explicit-any
function declaration(body: any, name: string): { description: string } {
  return body.tools[0].functionDeclarations.find(
    (d: { name: string }) => d.name === name,
  );
}

async function runLogSet(writeClaimRule: boolean | undefined, isPro = false) {
  const { calls, restore } = installFakeFetch([
    okToolCall("logSet", { exerciseId: "bench_press", weightKg: 60, reps: 8, sets: 3 }),
    okText("Queued. Tap APPLY to log it."),
  ]);
  try {
    const result = await runToolLoop({
      systemPrompt: "you are The Captain",
      userMessage: "log bench 3x8 at 60",
      ctx: ctx(isPro),
      model: "gemini-3.1-flash-lite",
      ...(writeClaimRule === undefined ? {} : { writeClaimRule }),
    });
    assertEquals(result.intents.length, 1);
    return calls;
  } finally {
    restore();
  }
}

Deno.test("rule on: the queued functionResponse carries the NOT-saved note", async () => {
  const calls = await runLogSet(true);
  const r = queuedResponse(calls[1].body);
  assertEquals(r.status, "queued_for_user_confirmation");
  assertEquals(r.note, QUEUED_NOTE);
  assertStringIncludes(QUEUED_NOTE, "NOT saved yet");
});

Deno.test("rule undefined (existing callers): the note is there too", async () => {
  const calls = await runLogSet(undefined);
  assertEquals(queuedResponse(calls[1].body).note, QUEUED_NOTE);
});

Deno.test("rule off: the functionResponse is today's shape, no note key", async () => {
  const calls = await runLogSet(false);
  const r = queuedResponse(calls[1].body);
  assertEquals(Object.keys(r).sort(), ["intent_id", "status"]);
});

Deno.test("meal declaration: APPLY text when on, original bytes when off", async () => {
  const on = await runLogSet(true);
  const mealOn = declaration(on[0].body, "logMealByText");
  assert(!mealOn.description.includes("5-second"));
  assertStringIncludes(mealOn.description, "must tap APPLY to log it");

  const off = await runLogSet(false);
  const mealOff = declaration(off[0].body, "logMealByText");
  assertStringIncludes(
    mealOff.description,
    "Always trivial-class — the user gets a 5-second auto-confirm card showing the parsed nutrition.",
  );
});

Deno.test("template declaration (PRO): Queued line when on, Saved! when off", async () => {
  const on = await runLogSet(true, true);
  assertStringIncludes(
    declaration(on[0].body, "scheduleTemplate").description,
    "Queued. Tap APPLY to save it.",
  );
  const off = await runLogSet(false, true);
  assertStringIncludes(
    declaration(off[0].body, "scheduleTemplate").description,
    "'Saved! Want me to schedule",
  );
});
