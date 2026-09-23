// supabase/functions/daily-snapshot/index_test.ts
//
// index.ts calls `serve(...)` at module scope with no `import.meta.main`
// guard, so importing it directly would boot a real HTTP server (the exact
// trap supabase/functions/CLAUDE.md warns about). This is a SOURCE-GREP
// wiring test — it proves the handler actually calls the merge-safe path
// fixed for diagnose d8a2f6, not just that the path exists somewhere.
// Behavioral coverage of the merge logic itself lives in
// ../_shared/snapshot_merge_test.ts (mutation-proven).

import { assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

const source = Deno.readTextFileSync(
  new URL("./index.ts", import.meta.url),
);

Deno.test("daily-snapshot imports the shared merge helper", () => {
  assert(
    source.includes('import { mergeSnapshotJson } from "../_shared/snapshot_merge.ts";'),
    "index.ts must import mergeSnapshotJson from the shared module",
  );
});

Deno.test("daily-snapshot reads the existing row with maybeSingle before upserting", () => {
  assert(
    source.includes(".maybeSingle()"),
    "must use maybeSingle() — a first-ever snapshot of the day has no " +
      "existing row, and .single() would throw on that legitimate case",
  );
});

Deno.test("daily-snapshot upserts the MERGED result, not the raw request payload", () => {
  assert(
    source.includes("mergeSnapshotJson("),
    "the merge helper must actually be called",
  );
  assert(
    source.includes("snapshot_json: mergedSnapshotJson"),
    "the upsert must write the merged value — writing raw `snapshot_json` " +
      "here is exactly the pre-fix bug (a blind wholesale replace)",
  );
});

Deno.test("daily-snapshot's merge-safe path has a kill-switch (platform-tier §4.6)", () => {
  assert(
    source.includes('Deno.env.get("DISABLE_SNAPSHOT_MERGE_SAFE_UPSERT")'),
    "platform tier requires a feature_flag per docs/blast_radius.yaml — " +
      "the merge-read must be gated so it can revert to the verbatim " +
      "pre-fix blind-replace upsert without a redeploy",
  );
  assert(
    source.includes("let mergedSnapshotJson: Record<string, unknown> = snapshot_json;"),
    "the kill-switch's fallback value must be the RAW payload (the exact " +
      "pre-fix behavior), not an empty object or the merge result",
  );
});

Deno.test("daily-snapshot logs (not swallows) a failed existing-row read", () => {
  assert(
    source.includes("existingRowError"),
    "the existing-row SELECT's error must be captured, not discarded — an " +
      "unread error silently degrades to the pre-fix blind-replace with " +
      "zero trace, indistinguishable from the legitimate absent-row case",
  );
  assert(
    source.includes("console.error(") &&
      source.includes("existing-row read failed"),
    "a failed read must be logged so the degradation is observable",
  );
});

// ── OI-238 (sibling of A5/OI-226, f7a2c9) ────────────────────────────────
//
// extractCoachingNotes()'s own geminiChat() call had no reportGeminiExhaustion
// wiring: `lastError` was never destructured, so the !rawText branch
// structurally could not alert on total Gemini exhaustion. Same SOURCE-GREP
// approach as the rest of this file (see header) — position-scoped to the
// `!rawText` branch and comment-stripped before any `.includes()` check.

function stripComments(s: string): string {
  return s.replace(/\/\*[\s\S]*?\*\//g, " ").replace(/\/\/[^\n]*/g, " ");
}

Deno.test("daily-snapshot imports reportGeminiExhaustion", () => {
  assert(
    source.includes(
      'import { reportGeminiExhaustion } from "../_shared/gemini_failure_alert.ts";',
    ),
    "index.ts must import reportGeminiExhaustion",
  );
});

Deno.test("extractCoachingNotes destructures lastError from its geminiChat call (OI-238)", () => {
  const callIdx = source.indexOf("await geminiChat({");
  assert(callIdx >= 0, "geminiChat call not found");
  const destructureLine = source.slice(Math.max(0, callIdx - 200), callIdx);
  assert(
    destructureLine.includes("lastError"),
    `expected the geminiChat destructure to include lastError, got: ${destructureLine}`,
  );
});

Deno.test(
  "extractCoachingNotes reports Gemini exhaustion on the !rawText branch, using the caller's own supabase param (OI-238)",
  () => {
    const branchIdx = source.indexOf("if (!rawText) {");
    assert(branchIdx >= 0, "!rawText branch not found");
    const branchEnd = source.indexOf("return null;\n  }", branchIdx);
    assert(branchEnd >= 0, "could not bound the !rawText block");
    const rawBlock = source.slice(branchIdx, branchEnd);
    const block = stripComments(rawBlock);

    assert(
      block.includes("reportGeminiExhaustion("),
      "the !rawText branch must call reportGeminiExhaustion",
    );
    assert(
      block.includes('"ai_proxy_gemini_exhausted"'),
      "must reuse the shared ai-proxy dedup source (live client-invoked traffic, same quota)",
    );
    assert(
      block.includes('"daily_snapshot_extraction"'),
      'must tag this call site with endpoint "daily_snapshot_extraction"',
    );
    assert(
      block.includes("lastError ?? null"),
      "must forward the real lastError (or null), not a fabricated value",
    );
    assert(
      /reportGeminiExhaustion\(\s*supabase,/.test(block),
      "must pass the function's OWN supabase parameter, not a module-level client",
    );
  },
);
