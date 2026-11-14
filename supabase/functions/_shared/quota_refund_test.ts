// supabase/functions/_shared/quota_refund_test.ts
//
// Part B (gemini3-limits-caching): which Gemini failures may give a quota unit
// back (`refundableFailure`), and the never-throws RPC wrapper ai-proxy calls
// (`refundReservation`). The SQL latch/budget half is pinned by the live
// behavioural script test/sql/gemini3_limits_refund_live_verify.sql.
//
// Run: deno test --no-check --allow-env --node-modules-dir=none
//      supabase/functions/_shared/quota_refund_test.ts

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.env.set("GEMINI_API_KEY", "test-key-not-a-real-secret");

const { refundableFailure, classifyNoReply } = await import("./gemini.ts");
const { refundableGeminiChatFailure, refundReservation } = await import("./quota_refund.ts");

Deno.test("refundableFailure: transport-class statuses refund", () => {
  for (const status of [null, 404, 408, 425, 429, 500, 502, 503, 504]) {
    assertEquals(refundableFailure({ status }), true, `status ${status}`);
  }
});

Deno.test("refundableFailure: other 4xx never refund (a request the caller built)", () => {
  for (const status of [400, 413, 422]) {
    assertEquals(refundableFailure({ status }), false, `status ${status}`);
  }
});

Deno.test("refundableFailure: OUR credential failing (401/403, 400 API_KEY_INVALID) refunds", () => {
  assertEquals(refundableFailure({ status: 401 }), true);
  assertEquals(refundableFailure({ status: 403 }), true);
  assertEquals(
    refundableFailure({ status: 400, message: "API key not valid. Please pass a valid API key. API_KEY_INVALID" }),
    true,
  );
  // A plain INVALID_ARGUMENT 400 is the request, not the key.
  assertEquals(refundableFailure({ status: 400, message: "INVALID_ARGUMENT: bad schema" }), false);
  assertEquals(refundableFailure({ status: 400 }), false);
});

Deno.test("refundableFailure: a block seen on ANY attempt never refunds, even if the last attempt was transport", () => {
  assertEquals(refundableFailure({ status: 404, blockSeen: true }), false); // SAFETY -> 404 fallback
  assertEquals(refundableFailure({ status: 503, blockSeen: true }), false); // SAFETY -> 503
  assertEquals(refundableFailure({ status: null, blockSeen: true }), false);
  assertEquals(refundableFailure({ status: 503, blockSeen: false }), true); // 503 -> 503 stays refundable
});

Deno.test("classifyNoReply: promptFeedback block, SAFETY-class and image blocks are deterministic + blocked", () => {
  const pf = classifyNoReply(undefined, "SAFETY");
  assertEquals([pf.deterministic, pf.blocked], [true, true]);
  for (const fr of ["SAFETY", "RECITATION", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "IMAGE_SAFETY", "IMAGE_PROHIBITED_CONTENT", "IMAGE_OTHER", "NO_IMAGE"]) {
    const c = classifyNoReply(fr, null);
    assertEquals([fr, c.deterministic, c.blocked], [fr, true, true]);
  }
});

Deno.test("classifyNoReply: MAX_TOKENS / LANGUAGE / MALFORMED are retriable but never refundable", () => {
  for (const fr of ["MAX_TOKENS", "LANGUAGE", "MALFORMED_FUNCTION_CALL"]) {
    const c = classifyNoReply(fr, null);
    assertEquals([fr, c.deterministic, c.blocked], [fr, false, true]);
  }
});

Deno.test("classifyNoReply: unknown / OTHER finish reasons are transport-ish (refundable)", () => {
  for (const fr of [undefined, null, "OTHER", "FINISH_REASON_UNSPECIFIED"]) {
    const c = classifyNoReply(fr as string | undefined, null);
    assertEquals([String(fr), c.deterministic, c.blocked], [String(fr), false, false]);
  }
});

Deno.test("refundableFailure: a deterministic content block never refunds, whatever the status", () => {
  assertEquals(refundableFailure({ status: null, deterministicFailure: true }), false);
  assertEquals(refundableFailure({ status: 503, deterministicFailure: true }), false);
});

Deno.test("refundableFailure: unknown failure (no evidence) never refunds", () => {
  assertEquals(refundableFailure(null), false);
  assertEquals(refundableFailure(undefined), false);
});

Deno.test("refundableGeminiChatFailure: reads lastError + deterministicFailure; missing lastError -> no refund", () => {
  assertEquals(refundableGeminiChatFailure({ lastError: { status: 503, message: "x" } }), true);
  assertEquals(
    refundableGeminiChatFailure({
      lastError: { status: null, message: "no candidate (finishReason=SAFETY)" },
      deterministicFailure: true,
    }),
    false,
  );
  assertEquals(
    refundableGeminiChatFailure({ lastError: { status: 404, message: "model not found" }, blockSeen: true }),
    false,
  );
  assertEquals(
    refundableGeminiChatFailure({ lastError: { status: 400, message: "API_KEY_INVALID" } }),
    true,
  );
  assertEquals(refundableGeminiChatFailure({ lastError: null }), false);
  assertEquals(refundableGeminiChatFailure({}), false);
});

function fakeSb(result: { data: unknown; error: { message?: string } | null } | "throw") {
  const calls: Array<{ fn: string; args: Record<string, unknown> }> = [];
  return {
    calls,
    sb: {
      rpc(fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });
        if (result === "throw") throw new Error("boom");
        return Promise.resolve(result);
      },
    },
  };
}

Deno.test("refundReservation: calls refund_quota with the reservation id + label, returns the new used", async () => {
  const f = fakeSb({ data: 3, error: null });
  const used = await refundReservation(f.sb, "res-1", "failed_gemini", "food");
  assertEquals(used, 3);
  assertEquals(f.calls, [{
    fn: "refund_quota",
    args: { p_reservation_id: "res-1", p_label: "failed_gemini" },
  }]);
});

Deno.test("refundReservation: no reservation id -> no RPC, -1", async () => {
  const f = fakeSb({ data: 1, error: null });
  assertEquals(await refundReservation(f.sb, undefined, "failed", "chat"), -1);
  assertEquals(f.calls.length, 0);
});

Deno.test("refundReservation: an RPC error is non-fatal (missing function / transient) -> -1", async () => {
  const f = fakeSb({ data: null, error: { message: "function public.refund_quota does not exist" } });
  assertEquals(await refundReservation(f.sb, "res-1", "failed", "chat"), -1);
});

Deno.test("refundReservation: a THROWING client is non-fatal -> -1", async () => {
  const f = fakeSb("throw");
  assertEquals(await refundReservation(f.sb, "res-1", "failed", "chat"), -1);
});

Deno.test("refundReservation: the RPC's -1 (latched/budget spent) passes through; a non-number is -1", async () => {
  assertEquals(await refundReservation(fakeSb({ data: -1, error: null }).sb, "r", "failed", "chat"), -1);
  assertEquals(await refundReservation(fakeSb({ data: null, error: null }).sb, "r", "failed", "chat"), -1);
});
