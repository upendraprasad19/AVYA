// supabase/functions/assess-body-composition/index_test.ts
//
// OI-238 (sibling of A5/OI-226, f7a2c9) — assess-body-composition's own
// geminiChat() call had no reportGeminiExhaustion wiring: `lastError` was
// never destructured, so the !rawText branch structurally could not alert.
//
// index.ts calls `serve(...)` at module scope with no `import.meta.main`
// guard (same shape as daily-snapshot/index.ts — see that file's own
// index_test.ts header), so importing it directly would boot a real HTTP
// server. This is a SOURCE-GREP wiring test, position-scoped to the
// `!rawText` branch and comment-stripped before any `.includes()` check.
//
// Run:
//   deno test --no-check --allow-all --node-modules-dir=none supabase/functions/assess-body-composition/

import { assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

const source = Deno.readTextFileSync(
  new URL("./index.ts", import.meta.url),
);

function stripComments(s: string): string {
  return s.replace(/\/\*[\s\S]*?\*\//g, " ").replace(/\/\/[^\n]*/g, " ");
}

Deno.test("assess-body-composition imports reportGeminiExhaustion", () => {
  assert(
    source.includes(
      'import { reportGeminiExhaustion } from "../_shared/gemini_failure_alert.ts";',
    ),
    "index.ts must import reportGeminiExhaustion",
  );
});

Deno.test("assess-body-composition destructures lastError from its geminiChat call (OI-238)", () => {
  const callIdx = source.indexOf("await geminiChat({");
  assert(callIdx >= 0, "geminiChat call not found");
  const destructureLine = source.slice(Math.max(0, callIdx - 200), callIdx);
  assert(
    destructureLine.includes("lastError"),
    `expected the geminiChat destructure to include lastError, got: ${destructureLine}`,
  );
});

Deno.test(
  "assess-body-composition reports Gemini exhaustion on the !rawText branch, BEFORE the 502 return (OI-238)",
  () => {
    const branchIdx = source.indexOf("if (!rawText)");
    assert(branchIdx >= 0, "!rawText branch not found");
    const nextFnEnd = source.indexOf("\n    }\n", branchIdx);
    assert(nextFnEnd >= 0, "could not bound the !rawText block");
    const rawBlock = source.slice(branchIdx, nextFnEnd);
    const block = stripComments(rawBlock);

    assert(
      block.includes("reportGeminiExhaustion("),
      "the !rawText branch must call reportGeminiExhaustion",
    );
    assert(
      block.includes('"ai_proxy_gemini_exhausted"'),
      "must reuse the shared ai-proxy dedup source (live user traffic, same quota)",
    );
    assert(
      block.includes('"assess_body_composition"'),
      'must tag this call site with endpoint "assess_body_composition"',
    );
    assert(
      block.includes("lastError ?? null"),
      "must forward the real lastError (or null), not a fabricated value",
    );

    const reportIdx = block.indexOf("reportGeminiExhaustion(");
    const jsonReturnIdx = block.indexOf("json({ error:");
    assert(
      reportIdx >= 0 && jsonReturnIdx >= 0 && reportIdx < jsonReturnIdx,
      "the alert must fire BEFORE the 502 json() response is returned",
    );
  },
);
