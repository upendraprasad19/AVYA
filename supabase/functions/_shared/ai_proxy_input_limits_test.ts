// Deno tests for _shared/ai_proxy_input_limits.ts (single-owner audit
// 2026-09-26, P0 #5) — the ONE owner of ai-proxy's request-size limits.
//
// Run: deno test --no-check --allow-all --node-modules-dir=none supabase/functions/_shared/ai_proxy_input_limits_test.ts

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  MAX_MESSAGE_CHARS,
  MAX_SNAPSHOT_CHARS,
  MAX_TEXT_CHARS,
  validateAiProxyInput,
} from "./ai_proxy_input_limits.ts";

Deno.test("message — at the limit passes, one over is refused with the old string", () => {
  assertEquals(validateAiProxyInput({ message: "a".repeat(MAX_MESSAGE_CHARS) }), null);
  assertEquals(
    validateAiProxyInput({ message: "a".repeat(MAX_MESSAGE_CHARS + 1) }),
    { status: 400, error: "Message too long (max 5000 chars)" },
  );
});

Deno.test("text — at the limit passes, one over is refused with the old string", () => {
  assertEquals(validateAiProxyInput({ text: "a".repeat(MAX_TEXT_CHARS) }), null);
  assertEquals(
    validateAiProxyInput({ text: "a".repeat(MAX_TEXT_CHARS + 1) }),
    { status: 400, error: "food_text_analysis: text too long (max 5000 chars)" },
  );
});

Deno.test("snapshot_json — 10000 passes, 10001 refused (plain ASCII: sanitised length = serialised length)", () => {
  // JSON.stringify({ k: "x" * n }) = n + 8 chars ({"k":""}).
  const at = { k: "x".repeat(MAX_SNAPSHOT_CHARS - 8) };
  assertEquals(JSON.stringify(at).length, MAX_SNAPSHOT_CHARS);
  assertEquals(validateAiProxyInput({ snapshot_json: at }), null);
  const over = { k: "x".repeat(MAX_SNAPSHOT_CHARS - 7) };
  assertEquals(
    validateAiProxyInput({ snapshot_json: over }),
    { status: 400, error: "Snapshot too large" },
  );
});

// Hermes 2026-09-26, L37-F2: the cap measures the text the prompt receives.
// A raw U+2028 is 1 character to JSON.stringify and 6 after
// sanitizeJsonForPrompt, so 9,990 of them stringify under the cap and reach
// the system prompt at ~60,000 characters.
Deno.test("snapshot_json — measured after sanitizeJsonForPrompt, not before", () => {
  const separators = { k: "\u2028".repeat(MAX_SNAPSHOT_CHARS - 10) };
  assert(JSON.stringify(separators).length <= MAX_SNAPSHOT_CHARS, "fixture stringifies under the cap");
  assertEquals(
    validateAiProxyInput({ snapshot_json: separators }),
    { status: 400, error: "Snapshot too large" },
  );
});

Deno.test("the prediction shape (the P0) is bounded: a long message is refused", () => {
  assertEquals(
    validateAiProxyInput({
      type: "prediction",
      message: "p".repeat(MAX_MESSAGE_CHARS + 1),
      context: {},
    })?.status,
    400,
  );
});

Deno.test("absent / non-string fields are left to each branch's own type checks", () => {
  assertEquals(validateAiProxyInput({}), null);
  assertEquals(validateAiProxyInput({ message: 12345, text: ["x"] }), null);
});

// ── Wiring — the validator is only an owner if it runs before EVERY branch ──
Deno.test("ai-proxy calls validateAiProxyInput before the first type branch", async () => {
  const src = await Deno.readTextFile(
    new URL("../ai-proxy/index.ts", import.meta.url),
  );
  // Comment-stripped (block and line): a comment naming the call must not
  // satisfy this — a mutation that left the call only in a comment stayed
  // green against the first version of this test.
  const code = src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
  const callIdx = code.indexOf("const limitViolation = validateAiProxyInput(body);");
  const actIdx = code.indexOf(
    "if (limitViolation) return err(limitViolation.status, limitViolation.error);",
  );
  const firstBranchIdx = code.indexOf("if (type ===");
  assert(callIdx >= 0, "ai-proxy must call validateAiProxyInput(body)");
  assert(
    actIdx > callIdx,
    "ai-proxy must RETURN the violation — calling the validator and ignoring " +
      "its result bounds nothing",
  );
  assert(firstBranchIdx >= 0, "no type branch found");
  assert(
    actIdx < firstBranchIdx,
    "validateAiProxyInput must run and be acted on before the first `if (type ===` " +
      "branch — a branch above it would be unbounded (the prediction P0 shape)",
  );
});

Deno.test("ai-proxy prediction branch delegates to handlePrediction", async () => {
  const src = await Deno.readTextFile(
    new URL("../ai-proxy/index.ts", import.meta.url),
  );
  const anchor = src.indexOf('if (type === "prediction") {');
  assert(anchor >= 0, "prediction branch not found");
  // Comments stripped: the branch's own comment says the caller's
  // system_prompt is ignored, and that sentence must not satisfy or fail this.
  const window = src.slice(anchor, anchor + 1500).replace(/\/\/[^\n]*/g, "");
  assert(
    window.includes("await handlePrediction("),
    "the prediction branch must delegate to _shared/prediction_handler.ts",
  );
  assert(
    !window.includes("system_prompt"),
    "the prediction branch must not read a caller-supplied system_prompt",
  );
  // B-pass c5d659f52986 Finding 2: the handler receives the message and
  // nothing else — passing `body` or `body.context` would hand it the
  // caller's prompt again without ever spelling "system_prompt" here.
  assert(
    /await handlePrediction\(\s*\{\s*message\s*\}\s*,/.test(window),
    "handlePrediction's first argument must be exactly `{ message }`",
  );
});
