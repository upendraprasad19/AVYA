// supabase/functions/weekly-report/index_test.ts
//
// OI-238 (sibling of A5/OI-226, f7a2c9) — weekly-report's own geminiChat()
// call had no reportGeminiExhaustion wiring at all: `lastError` was never
// even destructured from GeminiResult, so the !aiContent branch structurally
// could not alert on total Gemini exhaustion.
//
// index.ts calls `serve(...)` at module scope with no `import.meta.main`
// guard (same shape as assess-body-composition/index.ts and
// rolling-context/index.ts — see either file's own index_test.ts header;
// daily-snapshot/index.ts GAINED this guard in the single-owner-a2a batch,
// 2026-09-27, so it is no longer a same-shaped sibling here), so importing
// this file directly would boot a real HTTP server. This is a SOURCE-GREP
// wiring test, position-scoped to the
// `!aiContent` branch and comment-stripped before any `.includes()` check —
// the exact discipline `gemini_retry_coverage_lib.dart`'s `stripComments()`
// and this same batch's sibling diagnose-doc (f7a2c9) both document, after a
// raw `.contains()` check was found to stay falsely green against a
// commented-out (not deleted) call.
//
// Run:
//   deno test --no-check --allow-all --node-modules-dir=none supabase/functions/weekly-report/

import { assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

const source = Deno.readTextFileSync(
  new URL("./index.ts", import.meta.url),
);

function stripComments(s: string): string {
  return s.replace(/\/\*[\s\S]*?\*\//g, " ").replace(/\/\/[^\n]*/g, " ");
}

Deno.test("weekly-report imports reportGeminiExhaustion", () => {
  assert(
    source.includes(
      'import { reportGeminiExhaustion } from "../_shared/gemini_failure_alert.ts";',
    ),
    "index.ts must import reportGeminiExhaustion",
  );
});

Deno.test("weekly-report destructures lastError from its geminiChat call (OI-238)", () => {
  const callIdx = source.indexOf("await geminiChat({");
  assert(callIdx >= 0, "geminiChat call not found");
  const destructureLine = source.slice(Math.max(0, callIdx - 200), callIdx);
  assert(
    destructureLine.includes("lastError"),
    `expected the geminiChat destructure to include lastError, got: ${destructureLine}`,
  );
});

Deno.test(
  "weekly-report reports Gemini exhaustion on the !aiContent branch, BEFORE the 502 return (OI-238)",
  () => {
    const branchIdx = source.indexOf("if (!aiContent)");
    assert(branchIdx >= 0, "!aiContent branch not found");
    const nextFnEnd = source.indexOf("\n    }\n", branchIdx);
    assert(nextFnEnd >= 0, "could not bound the !aiContent block");
    const rawBlock = source.slice(branchIdx, nextFnEnd);
    const block = stripComments(rawBlock);

    assert(
      block.includes("reportGeminiExhaustion("),
      "the !aiContent branch must call reportGeminiExhaustion",
    );
    assert(
      block.includes('"ai_proxy_gemini_exhausted"'),
      "must reuse the shared ai-proxy dedup source (live user traffic, same quota)",
    );
    assert(
      block.includes('"weekly_report"'),
      'must tag this call site with endpoint "weekly_report"',
    );
    assert(
      block.includes("lastError ?? null"),
      "must forward the real lastError (or null), not a fabricated value",
    );

    const reportIdx = block.indexOf("reportGeminiExhaustion(");
    const jsonResponseIdx = block.indexOf("jsonResponse(");
    assert(
      reportIdx >= 0 && jsonResponseIdx >= 0 && reportIdx < jsonResponseIdx,
      "the alert must fire BEFORE the 502 jsonResponse is returned",
    );
  },
);

// Unit 3b-3 B-pass seat A finding 2: the report reads the strategy (behind the
// manual switch) and puts the line right under the protein target. The line's
// own text is tested on weeklyReportDietStrategyLine (_shared/diet_strategies_test.ts).
Deno.test("weekly-report reads diet_strategy; the line only with the switch on", () => {
  const code = stripComments(source);
  assert(
    code.includes("const dietStrategyOn = !dietStrategyManualRulesOff();"),
    "the switch is read once",
  );
  assert(
    /\.from\("user_profile"\)\s*\.select\(\s*"[^"]*, diet_strategy",/.test(code),
    "the profile read selects diet_strategy",
  );
  assert(
    code.includes("const dietStrategyLine = dietStrategyOn\n      ? weeklyReportDietStrategyLine(userProfile?.diet_strategy, Boolean(hasPro))\n      : \"\";"),
    "the line uses the stored strategy and the PRO answer, empty with the switch off",
  );
});

Deno.test("weekly-report puts the strategy line under the protein target", () => {
  const code = stripComments(source);
  const at = code.indexOf("- Daily protein target: ${proteinTarget}g${dietStrategyLine ? `\\n${dietStrategyLine}` : \"\"}\n\n**THIS WEEK'S NUTRITION");
  assert(at >= 0, "the line sits right after the protein target, nothing when empty");
  assert(code.indexOf("const dietStrategyLine =") < at, "computed before the message");
});
