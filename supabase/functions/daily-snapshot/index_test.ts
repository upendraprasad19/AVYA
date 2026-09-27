// supabase/functions/daily-snapshot/index_test.ts
//
// index.ts's handler() reads Deno.env.get(...)! at module scope (SUPABASE_URL
// etc.), so a dynamic import in a test without those env vars set would still
// throw at import time — this file stays SOURCE-GREP rather than switching to
// a dynamic-import behavioral test. It proves the handler actually calls the
// merge-safe path fixed for diagnose d8a2f6, not just that the path exists
// somewhere. Behavioral coverage of the merge logic itself lives in
// ../_shared/snapshot_merge_test.ts (mutation-proven).
//
// a2a (single-owner batch, 2026-09-27): serve(...) now boots ONLY under
// `if (import.meta.main)` (see the "boots under..." test below) — this file
// itself never imports index.ts directly, so this was never the thing at
// risk here, but every OTHER consumer (a future behavioral test, or the a2b
// work that follows this piece) can now safely import extractCoachingNotes
// without a live server starting.

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
  // a2a repointed this call from a bare `geminiChat(` to the injectable
  // `geminiChatFn(` — see the geminiChatFn tests below for why. Repointed,
  // not loosened: the call site still exists, just under its new name.
  const callIdx = source.indexOf("await geminiChatFn({");
  assert(callIdx >= 0, "geminiChatFn call not found");
  const destructureLine = source.slice(Math.max(0, callIdx - 200), callIdx);
  assert(
    destructureLine.includes("lastError"),
    `expected the geminiChatFn destructure to include lastError, got: ${destructureLine}`,
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

// ── a2a (single-owner batch, 2026-09-27) ─────────────────────────────────
//
// Test seam + kill switch + private-mode-before-any-read. What this
// function reads/meters is UNCHANGED here — that's a2b's scope, reviewed
// separately.

Deno.test("daily-snapshot boots the server ONLY under import.meta.main", () => {
  assert(
    source.includes("if (import.meta.main) {") &&
      source.includes("serve(handler)"),
    "importing this module for a test must not start a real HTTP server",
  );
  assert(
    !/serve\(async \(req: Request\)/.test(source),
    "the old unguarded `serve(async (req) => {...})` form must be gone, " +
      "not merely joined by a guarded second call",
  );
});

Deno.test("extractCoachingNotes is exported with an injectable geminiChatFn, defaulting to the real geminiChat", () => {
  assert(
    source.includes("export async function extractCoachingNotes("),
    "must be exported for a2b's own tests to call it directly",
  );
  assert(
    source.includes("{ geminiChatFn = geminiChat }: { geminiChatFn?: typeof geminiChat } = {}"),
    "the injectable param must default to the REAL geminiChat import — " +
      "no production call site passes a second argument",
  );
});

Deno.test("daily-snapshot has a DISABLE_COACH_EXTRACTION kill switch (read per call, no redeploy needed)", () => {
  assert(
    source.includes('Deno.env.get("DISABLE_COACH_EXTRACTION") === "true"'),
    "platform-tier §4.6 requires a feature_flag for this kind of change",
  );
  const disableIdx = source.indexOf("DISABLE_COACH_EXTRACTION");
  const fetchIdx = source.indexOf("fetchCoachMemory(supabaseClient, userId)");
  assert(disableIdx >= 0 && fetchIdx >= 0, "both anchors must exist");
  assert(
    disableIdx < fetchIdx,
    "the kill switch must be checked BEFORE the coach_memory read it gates — " +
      "checking it after would still spend the read on every call",
  );
});

Deno.test("private_mode is checked BEFORE the staleness check and BEFORE any extraction call, not after (round-3 #9)", () => {
  // Pre-a2a, only mergeCoachMemoryFields checked private_mode — AFTER
  // extractCoachingNotes had already spent a Gemini call and
  // mergeCoachingNotes had already written diet_preference/injuries/etc.
  // into user_preferences + memory_embeddings + user_profile.
  const privateModeIdx = source.indexOf("if (!existing?.private_mode) {");
  const isStaleIdx = source.indexOf("const isStale =");
  const extractCallIdx = source.indexOf(
    "extractedFacts = await extractCoachingNotes(",
  );
  assert(
    privateModeIdx >= 0 && isStaleIdx >= 0 && extractCallIdx >= 0,
    "all three anchors must exist",
  );
  assert(
    privateModeIdx < isStaleIdx && isStaleIdx < extractCallIdx,
    "private_mode must gate BEFORE isStale is even computed, which must " +
      "precede the actual extraction call — this is the exact ordering " +
      "round 3 finding #9 required",
  );
});

Deno.test("private_mode gate fails OPEN on a missing row or a read error, not closed (matches this function's existing non-fatal posture)", () => {
  // fetchCoachMemory (see _shared/coach_memory.ts) returns null on BOTH "no
  // row yet" and a genuine read error — `!existing?.private_mode` must
  // therefore evaluate true (proceed with extraction) in both cases, never
  // block a legitimate first-time user because coach_memory doesn't exist
  // yet. Asserting the exact `!existing?.private_mode` form (rather than
  // some other private_mode check elsewhere in the file) pins this.
  assert(
    source.includes("if (!existing?.private_mode) {"),
    "must use the optional-chaining form so an absent row (undefined) " +
      "reads as \"not private\", not as a block",
  );
});
