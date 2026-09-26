// supabase/functions/weekly-report/index_test.ts
//
// OI-238 (sibling of A5/OI-226, f7a2c9) — weekly-report's own geminiChat()
// call had no reportGeminiExhaustion wiring at all: `lastError` was never
// even destructured from GeminiResult, so the !aiContent branch structurally
// could not alert on total Gemini exhaustion.
//
// index.ts calls `serve(...)` at module scope with no `import.meta.main`
// guard (same shape as daily-snapshot/index.ts — see that file's own
// index_test.ts header), so importing it directly would boot a real HTTP
// server. This is a SOURCE-GREP wiring test, position-scoped to the
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
