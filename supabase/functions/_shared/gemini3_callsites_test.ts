// supabase/functions/_shared/gemini3_callsites_test.ts
//
// PRESENCE-ONLY pins (2026-10-01 Gemini 3.x migration) for the call sites that
// live in files calling `serve()` at module scope (ai-proxy, ai-media-proxy,
// weekly-report, assess-body-composition, rolling-context) and so cannot be
// imported by a test. The BEHAVIOR (fallback, 404 prune, thinking per attempt,
// signatures) is tested at the gemini.ts level in gemini3_migration_test.ts and
// gemini_thinking_config_test.ts; these pin that the call sites still use it.
//
// Run: deno test --no-check --allow-all --node-modules-dir=none supabase/functions/_shared/gemini3_callsites_test.ts

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

async function code(rel: string): Promise<string> {
  const src = await Deno.readTextFile(new URL(rel, import.meta.url));
  // strip comments so a comment can neither satisfy nor trip a pin
  return src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
}

Deno.test("weekly-report: the ONLY thinking:'on' call, with a 4096 output cap (thought tokens count against it)", async () => {
  const c = await code("../weekly-report/index.ts");
  assert(/thinking:\s*"on"/.test(c), 'weekly-report must pass thinking: "on"');
  assert(/maxTokens:\s*4096/.test(c), "weekly-report maxTokens must be 4096");
  assertEquals(/maxTokens:\s*1500/.test(c), false);
});

Deno.test("no other function turns thinking on", async () => {
  for (
    const f of [
      "../ai-proxy/index.ts",
      "../ai-media-proxy/index.ts",
      "../assess-body-composition/index.ts",
      "../daily-snapshot/index.ts",
      "../rolling-context/index.ts",
      "./tool-loop.ts",
      "./food_parser.ts",
      "./prediction_handler.ts",
    ]
  ) {
    assertEquals(/thinking:\s*"on"/.test(await code(f)), false, `${f} must not enable thinking`);
  }
});

Deno.test("no call site opts out of the fallback any more (the fallback is the 404/outage safety net)", async () => {
  for (
    const f of [
      "../ai-proxy/index.ts",
      "../ai-media-proxy/index.ts",
      "../assess-body-composition/index.ts",
      "../weekly-report/index.ts",
      "../daily-snapshot/index.ts",
      "../rolling-context/index.ts",
      "./prediction_handler.ts",
      "./food_parser.ts",
      "./tool-loop.ts",
    ]
  ) {
    assertEquals(/fallbackToLite:\s*false/.test(await code(f)), false, `${f} still opts out of the fallback`);
  }
});

Deno.test("no stale 2.5 slug or 2.5 label survives in non-test function code", async () => {
  for (
    const f of [
      "./gemini.ts",
      "../ai-proxy/index.ts",
      "../ai-media-proxy/index.ts",
      "../weekly-report/index.ts",
      "../assess-body-composition/index.ts",
      "../daily-snapshot/index.ts",
      "../rolling-context/index.ts",
      "./prediction_handler.ts",
      "./tool-loop.ts",
    ]
  ) {
    const c = await code(f);
    assertEquals(/gemini-2\.5/.test(c), false, `${f} still names a gemini-2.5 slug`);
    assertEquals(/Gemini 2\.5/.test(c), false, `${f} still labels a Gemini 2.5 model`);
  }
});

/** Argument text of every `name(` call, paren-balanced, in comment-stripped code. */
function callArgs(src: string, name: string): string[] {
  const out: string[] = [];
  let from = 0;
  for (;;) {
    const i = src.indexOf(name + "(", from);
    if (i < 0) return out;
    let depth = 0;
    let j = i + name.length;
    for (; j < src.length; j++) {
      if (src[j] === "(") depth++;
      else if (src[j] === ")" && --depth === 0) break;
    }
    out.push(src.slice(i + name.length + 1, j));
    from = j;
  }
}

Deno.test("EVERY reportGeminiExhaustion call passes attemptStatuses INSIDE its own argument list (A3; per call, not per file)", async () => {
  const expectedCalls: Record<string, number> = {
    "../ai-proxy/index.ts": 4, // food, scan, cart, prediction
    "../ai-media-proxy/index.ts": 1,
    "../weekly-report/index.ts": 1,
    "../assess-body-composition/index.ts": 1,
    "../daily-snapshot/index.ts": 1,
    "../rolling-context/index.ts": 1,
    "./tool-loop.ts": 1,
  };
  for (const [f, n] of Object.entries(expectedCalls)) {
    const calls = callArgs(await code(f), "reportGeminiExhaustion");
    assertEquals(calls.length, n, `${f}: expected ${n} reportGeminiExhaustion call(s)`);
    for (const args of calls) {
      assert(/attemptStatuses/.test(args), `${f}: a call is missing attemptStatuses in its arguments: ${args.slice(0, 120)}`);
    }
  }
});

Deno.test("prediction: the reportExhaustion callback forwards attemptStatuses to reportGeminiExhaustion", async () => {
  const c = await code("../ai-proxy/index.ts");
  assert(/reportExhaustion:\s*\(lastError,\s*attemptStatuses\)\s*=>/.test(c));
});

Deno.test("ai-media-proxy persists a label built from the slug that answered, not a constant", async () => {
  const c = await code("../ai-media-proxy/index.ts");
  // the ASSIGNMENT itself (a stray `void labelForModel(modelUsed)` cannot satisfy this)
  assert(
    /const modelLabel = `\$\{labelForModel\(modelUsed\)\}\$\{MODEL_LABEL_SUFFIX\}`;/.test(c),
    "modelLabel must be built from labelForModel(modelUsed)",
  );
  assertEquals(/const MODEL_LABEL\s*=/.test(c), false);
});

Deno.test("rolling-context: hard-failure rows are deleted with the rest but never embedded or summarised; the literal matches ai-proxy's sentinel", async () => {
  const c = await code("../rolling-context/index.ts");
  const proxy = await code("../ai-proxy/index.ts");
  assert(/export const MODEL_USED_LOOP_THREW_SENTINEL = "failed"/.test(proxy));
  assert(/const MODEL_USED_FAILED = "failed";/.test(c), "rolling-context's literal must equal ai-proxy's sentinel");
  assert(c.includes('.select("id, user_message, ai_response, created_at, model_used")'), "model_used must be selected");
  assert(/const forMemory = toSummarize\.filter\(\(m\) => m\.model_used !== MODEL_USED_FAILED\);/.test(c));
  assert(/for \(const msg of forMemory\)/.test(c), "the embed loop must run over forMemory");
  assert(c.includes("await summarizeMessages(forMemory, supabaseClient)"));
  assert(c.includes("const idsToDelete = toSummarize.map((m) => m.id);"), "ALL summarised rows (failed included) are still deleted");
});

Deno.test("daily-snapshot: the conversation read excludes model_used='failed' with a NULL-safe .or (behaviour is pinned in index_test.ts)", async () => {
  const c = await code("../daily-snapshot/index.ts");
  assert(c.includes('.or("model_used.is.null,model_used.neq.failed")'));
});
