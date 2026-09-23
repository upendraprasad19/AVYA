// supabase/functions/rolling-context/index_test.ts
//
// OI-238 (sibling of A5/OI-226, f7a2c9) — rolling-context's summarizeMessages()
// had no reportGeminiExhaustion wiring: `lastError` was never destructured,
// and the function didn't even receive a Supabase client, so an alert was
// structurally impossible on a total Gemini exhaustion.
//
// This is the one CRON-dispatched call site among the 5 OI-238 functions —
// it runs nightly inside a per-user loop, so it deliberately uses its OWN
// dedup source ("rolling_context_gemini_exhausted"), NOT the shared
// "ai_proxy_gemini_exhausted" source the other 4 (live, user-invoked) sites
// reuse — see the code comment at the call site for the full reasoning
// (a burst of per-user failures in one nightly run must not suppress a
// same-day LIVE ai-proxy alert to "warn" for the rest of that source's
// 30-minute dedup window).
//
// index.ts calls `serve(...)` at module scope with no `import.meta.main`
// guard (same shape as daily-snapshot/index.ts — see that file's own
// index_test.ts header), so importing it directly would boot a real HTTP
// server. This is a SOURCE-GREP wiring test, position-scoped to the
// `if (!content)` branch inside summarizeMessages() and comment-stripped
// before any `.includes()` check.
//
// Run:
//   deno test --no-check --allow-all --node-modules-dir=none supabase/functions/rolling-context/

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

const source = Deno.readTextFileSync(
  new URL("./index.ts", import.meta.url),
);

function stripComments(s: string): string {
  return s.replace(/\/\*[\s\S]*?\*\//g, " ").replace(/\/\/[^\n]*/g, " ");
}

Deno.test("rolling-context imports reportGeminiExhaustion", () => {
  assert(
    source.includes(
      'import { reportGeminiExhaustion } from "../_shared/gemini_failure_alert.ts";',
    ),
    "index.ts must import reportGeminiExhaustion",
  );
});

Deno.test("summarizeMessages takes a Supabase client parameter (needed to alert)", () => {
  const sigIdx = source.indexOf("async function summarizeMessages(");
  assert(sigIdx >= 0, "summarizeMessages signature not found");
  const sigEnd = source.indexOf("): Promise<string | null> {", sigIdx);
  assert(sigEnd >= 0);
  const signature = source.slice(sigIdx, sigEnd);
  assert(
    signature.includes("supabase: SupabaseClient"),
    `expected summarizeMessages to take a supabase: SupabaseClient param, got: ${signature}`,
  );
});

Deno.test("the call site passes supabaseClient into summarizeMessages", () => {
  assert(
    source.includes("await summarizeMessages(toSummarize, supabaseClient)"),
    "summarizeMessages must be called with the loop's supabaseClient",
  );
});

Deno.test("summarizeMessages destructures lastError from its geminiChat call (OI-238)", () => {
  const callIdx = source.indexOf("await geminiChat({");
  assert(callIdx >= 0, "geminiChat call not found");
  const destructureLine = source.slice(Math.max(0, callIdx - 200), callIdx);
  assert(
    destructureLine.includes("lastError"),
    `expected the geminiChat destructure to include lastError, got: ${destructureLine}`,
  );
});

Deno.test(
  "summarizeMessages reports Gemini exhaustion on the !content branch, on its OWN dedup source (OI-238)",
  () => {
    const branchIdx = source.indexOf("if (!content) {");
    assert(branchIdx >= 0, "!content branch not found");
    const branchEnd = source.indexOf("\n  }\n\n  return content;", branchIdx);
    assert(branchEnd >= 0, "could not bound the !content block");
    const rawBlock = source.slice(branchIdx, branchEnd);
    const block = stripComments(rawBlock);

    assert(
      block.includes("reportGeminiExhaustion("),
      "the !content branch must call reportGeminiExhaustion",
    );
    assert(
      block.includes('"rolling_context_gemini_exhausted"'),
      "rolling-context must use its OWN dedup source, not the shared " +
        "ai_proxy_gemini_exhausted one (it is the sole cron-dispatched " +
        "site among the 5 and can fan out across many users per run)",
    );
    assertEquals(
      block.includes('"ai_proxy_gemini_exhausted"'),
      false,
      "must NOT also reuse the live-traffic dedup source",
    );
    assert(
      block.includes('"rolling_context_summarize"'),
      'must tag this call site with endpoint "rolling_context_summarize"',
    );
    assert(
      block.includes("lastError ?? null"),
      "must forward the real lastError (or null), not a fabricated value",
    );
  },
);

Deno.test("summarizeMessages still returns content on the happy path (no regression)", () => {
  const returnIdx = source.lastIndexOf("return content;\n}");
  assert(returnIdx >= 0, "summarizeMessages must still return content");
});
