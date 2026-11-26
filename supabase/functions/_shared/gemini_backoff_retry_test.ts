// supabase/functions/_shared/gemini_backoff_retry_test.ts
//
// Diagnose d4f1c2 (2026-06-01) — the AI coach intermittently replied
// "I had trouble reaching the model. Try again in a moment." Root cause:
// `geminiChatWithTools` tried [Flash → Flash-Lite] back-to-back with NO time
// spacing, both on the same project quota, so a single transient 429/5xx/empty
// blip tripped both within ~1-2s and the function threw — and `runToolLoop`
// surfaced the apology with zero retry. The fix adds a bounded, time-spaced
// backoff-retry pass for the RETRIABLE bucket (429 / 5xx / empty-candidate)
// while NOT retrying timeouts (budget already spent) or non-429 4xx (a retry
// can't help).
//
// This is a BEHAVIORAL test: it stubs `globalThis.fetch` (no module-mock shim
// needed — geminiChatWithTools calls the global directly) and asserts the
// retry recovers a transient failure, does NOT retry a timeout or a 4xx, and
// stays bounded on a persistent failure.
//
// Run: deno test --allow-env supabase/functions/_shared/gemini_backoff_retry_test.ts

import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

// The module reads GEMINI_API_KEY at eval time — set it BEFORE the dynamic
// import so geminiChatWithTools doesn't short-circuit on the missing-key guard.
// Named (not just inlined) so the redactSecrets tests below can assert this
// EXACT value is the one being stripped.
const TEST_GEMINI_KEY = "test-key-not-a-real-secret";
Deno.env.set("GEMINI_API_KEY", TEST_GEMINI_KEY);

const { geminiChat, geminiChatWithTools, MODEL_FLASH, redactSecrets } =
  await import("./gemini.ts");

// ── Fake Response builders ────────────────────────────────────────────
function okResponse(text: string): Response {
  return {
    ok: true,
    status: 200,
    text: () => Promise.resolve(""),
    json: () =>
      Promise.resolve({
        candidates: [{ content: { parts: [{ text }] } }],
        usageMetadata: { totalTokenCount: 7 },
      }),
  } as unknown as Response;
}

function httpErrorResponse(status: number, body = "err"): Response {
  return {
    ok: false,
    status,
    text: () => Promise.resolve(body),
    json: () => Promise.resolve({}),
  } as unknown as Response;
}

function abortError(): Promise<Response> {
  return Promise.reject(new DOMException("aborted", "AbortError"));
}

/**
 * Replace globalThis.fetch with a queue of behaviors. Each call consumes the
 * next behavior (the last behavior repeats if the queue is exhausted). Returns
 * a live call counter + a restore fn. No real network is touched.
 */
function installFetchQueue(
  behaviors: Array<() => Promise<Response>>,
): { state: { calls: number }; restore: () => void } {
  const original = globalThis.fetch;
  const state = { calls: 0 };
  globalThis.fetch = ((_input: unknown, _init?: unknown): Promise<Response> => {
    const idx = Math.min(state.calls, behaviors.length - 1);
    state.calls++;
    return behaviors[idx]();
  }) as typeof fetch;
  return { state, restore: () => (globalThis.fetch = original) };
}

// `fallbackToLite: true` is set EXPLICITLY (not relied on as a default) because
// the call-count assertions below (2 per pass, 4 over two passes) assume the
// attempt list is [Flash, Flash-Lite]. A silent default change would otherwise
// make those assertions wrong without flagging it. (B-pass review P2, 2026-06-01.)
const baseOpts = {
  model: MODEL_FLASH,
  systemPrompt: "you are a coach",
  messages: [{ role: "user" as const, parts: [{ text: "hi" }] }],
  tools: [],
  fallbackToLite: true,
};

Deno.test("geminiChatWithTools — recovers a transient 5xx on the retry pass", async () => {
  // pass 0: Flash 503, Lite 503 → (retriable) sleep → pass 1: Flash 200.
  const { state, restore } = installFetchQueue([
    () => Promise.resolve(httpErrorResponse(503, "overloaded")),
    () => Promise.resolve(httpErrorResponse(503, "overloaded")),
    () => Promise.resolve(okResponse("recovered")),
  ]);
  try {
    const res = await geminiChatWithTools(baseOpts);
    assertEquals(res.text, "recovered");
    // 3 calls: Flash+Lite on pass 0, Flash on pass 1.
    assertEquals(state.calls, 3);
  } finally {
    restore();
  }
});

Deno.test("geminiChatWithTools — does NOT retry a non-429 4xx (a retry can't help)", async () => {
  // 400 is non-retriable: one pass over [Flash, Lite] then throw — no 2nd pass.
  const { state, restore } = installFetchQueue([
    () => Promise.resolve(httpErrorResponse(400, "bad request")),
  ]);
  try {
    await assertRejects(() => geminiChatWithTools(baseOpts));
    assertEquals(state.calls, 2);
  } finally {
    restore();
  }
});

Deno.test("geminiChatWithTools — does NOT retry a timeout (budget already spent)", async () => {
  // AbortError == the 25s timeout fired; retrying in place would risk the
  // overall wall clock, so it's non-retriable: 2 calls (Flash, Lite) then throw.
  const { state, restore } = installFetchQueue([abortError]);
  try {
    await assertRejects(() => geminiChatWithTools(baseOpts));
    assertEquals(state.calls, 2);
  } finally {
    restore();
  }
});

Deno.test("geminiChatWithTools — stays bounded on a persistent retriable failure", async () => {
  // Every attempt 429s. Bounded at TOOLS_MAX_PASSES(2) × [Flash, Lite] = 4
  // calls, then throws — it must NOT retry forever.
  const { state, restore } = installFetchQueue([
    () => Promise.resolve(httpErrorResponse(429, "rate limited")),
  ]);
  try {
    await assertRejects(() => geminiChatWithTools(baseOpts));
    assertEquals(state.calls, 4);
  } finally {
    restore();
  }
});

Deno.test("geminiChatWithTools — happy path makes exactly one call, no retry", async () => {
  const { state, restore } = installFetchQueue([() =>
    Promise.resolve(okResponse("all good"))
  ]);
  try {
    const res = await geminiChatWithTools(baseOpts);
    assertEquals(res.text, "all good");
    assertEquals(res.usedFallback, false);
    assertEquals(state.calls, 1);
  } finally {
    restore();
  }
});

// ── A2b (f7a2c9, 2026-09-21) ─────────────────────────────────────────────
// `geminiChat` (the plain single-shot helper — NOT `geminiChatWithTools`
// above) had 9 production call sites with no `retries` argument (default 0),
// so a single transient empty-candidate response failed the whole request
// outright: food_text_analysis, scan_meal, cart_auditor and the `prediction`
// handler in ai-proxy/index.ts, plus assess-body-composition, daily-snapshot,
// ai-media-proxy, rolling-context and weekly-report. Fixed by passing
// `retries: 2` at all 9 (mirroring food_parser.ts's existing pattern for the
// coach's own logMealByText tool — see its `retries: 2` at line ~114).
//
// Two behavioral tests below prove the shared mechanism these 9 sites now
// opt into actually retries an empty candidate (rather than re-deriving the
// same proof 9 times); 9 source-pin tests confirm each real call site was
// actually changed, not just the shared helper.

Deno.test("geminiChat — retries:2 recovers from an empty-candidate response (A2b, f7a2c9)", async () => {
  // fallbackToLite:false isolates the RETRIES mechanism from Flash→Lite
  // fallback (already covered above) — a single-model attempt list means
  // recovery can only come from the retry pass, not a fallback within a pass.
  const { state, restore } = installFetchQueue([
    () => Promise.resolve(okResponse("")), // pass 0: empty candidate → null
    () => Promise.resolve(okResponse("recovered on retry")), // pass 1: success
  ]);
  try {
    const res = await geminiChat({
      model: MODEL_FLASH,
      systemPrompt: "test",
      userPrompt: "test",
      maxTokens: 100,
      fallbackToLite: false,
      retries: 2,
    });
    assertEquals(res.content, "recovered on retry");
    assertEquals(state.calls, 2);
  } finally {
    restore();
  }
});

Deno.test("geminiChat — retries:0 (the pre-A2b default) does NOT retry an empty candidate", async () => {
  // The contrast case: proves the fix actually changes behavior rather than
  // geminiChat always having retried empty candidates regardless of the
  // option (which would make the 9 call-site edits below a no-op).
  const { state, restore } = installFetchQueue([
    () => Promise.resolve(okResponse("")),
    () => Promise.resolve(okResponse("should never be reached")),
  ]);
  try {
    const res = await geminiChat({
      model: MODEL_FLASH,
      systemPrompt: "test",
      userPrompt: "test",
      maxTokens: 100,
      fallbackToLite: false,
      // retries omitted — defaults to 0.
    });
    assertEquals(res.content, null);
    assertEquals(state.calls, 1);
  } finally {
    restore();
  }
});

// ── Per-call-site source pins ─────────────────────────────────────────────
// Presence-only (rule 21): confirms `retries: 2` was actually added AT EACH
// of the 9 real call sites, not just proven possible in the abstract above.
// Bounded-window, not a whole-file `includes` count — a file-wide count
// would go green even if `retries: 2` landed on only 1 of 4 ai-proxy sites
// and was simply absent from the other 3 (the exact
// feedback_green_check_input_set_width class: a filter/count that can't
// tell "present at the right place" from "present somewhere").

function assertRetriesNearAnchor(
  source: string,
  anchor: string,
  label: string,
) {
  const anchorIdx = source.indexOf(anchor);
  assertEquals(anchorIdx >= 0, true, `${label}: anchor not found in source`);
  const second = source.indexOf(anchor, anchorIdx + 1);
  assertEquals(second, -1, `${label}: anchor is not unique in this file`);

  // Bounds measured against the real files (max observed: 1247 anchor→call
  // for the ai-proxy type-check anchors) plus margin — NOT a round guess.
  const callIdx = source.indexOf("geminiChat({", anchorIdx);
  assertEquals(
    callIdx >= 0 && callIdx - anchorIdx < 1600,
    true,
    `${label}: no geminiChat( call found within 1600 chars of the anchor`,
  );
  const window = source.slice(callIdx, callIdx + 1000);
  assertEquals(
    window.includes("retries: 2"),
    true,
    `${label}: retries: 2 not found at this call site`,
  );
}

/** Counts non-overlapping occurrences of `needle` in `source`. */
function _countOccurrences(source: string, needle: string): number {
  let count = 0;
  let from = 0;
  while (true) {
    const at = source.indexOf(needle, from);
    if (at < 0) break;
    count++;
    from = at + needle.length;
  }
  return count;
}

function assertSoleCallSiteHasRetries(
  source: string,
  label: string,
  expectedRetries = 2,
) {
  // daily-snapshot's a2a test-seam refactor (2026-09-27) calls Gemini
  // through an injectable `geminiChatFn` parameter (defaulting to the real
  // `geminiChat`) rather than the bare function name at the call site — the
  // SAME runtime call, different literal text. Recognize both spellings so
  // this test doesn't go permanently blind to `retries: 2` the moment a
  // function adopts this testability pattern (found live, 2026-09-28: this
  // exact gap reddened only in the FULL `deno test supabase/functions/`
  // run, never in any targeted per-file run, because the two literal
  // substrings are mutually exclusive — "geminiChat({" is not a substring
  // of "geminiChatFn({" — so neither spelling can double-count the other).
  const directIdx = source.indexOf("geminiChat({");
  const seamIdx = source.indexOf("geminiChatFn({");
  const idx = directIdx >= 0 ? directIdx : seamIdx;
  assertEquals(
    idx >= 0,
    true,
    `${label}: no geminiChat(/geminiChatFn( call found`,
  );
  const totalCallSites = _countOccurrences(source, "geminiChat({") +
    _countOccurrences(source, "geminiChatFn({");
  assertEquals(
    totalCallSites,
    1,
    `${label}: expected exactly one geminiChat(/geminiChatFn( call site in this file`,
  );
  // Max observed call→retries distance across these 5 files: 1489 chars
  // (rolling-context — widened 2026-09-21, Hermes L21 F3 fix, when its own
  // explanatory comment above `retries:` grew past the previous 763-char
  // max and this window's old 1000-char bound silently stopped reaching the
  // argument at all, per this file's own class of hazard: a comment edit
  // above a scanned line is the same shape as a code move). 1800 leaves
  // margin.
  const window = source.slice(idx, idx + 1800);
  assertEquals(
    window.includes(`retries: ${expectedRetries}`),
    true,
    `${label}: retries: ${expectedRetries} missing at its sole geminiChat( call site`,
  );
}

Deno.test("ai-proxy food_text_analysis — retries: 2 passed", async () => {
  const source = await Deno.readTextFile(
    new URL("../ai-proxy/index.ts", import.meta.url),
  );
  // Anchored on the prompt text (not the outer type-check, which sits
  // 5706 chars from the call here — cap-check + placeholder-insert logic
  // intervenes) — unique to food_text_analysis, ~787 chars from the call.
  assertRetriesNearAnchor(
    source,
    "Analyse this as a meal and return ONLY a JSON object",
    "food_text_analysis",
  );
});

Deno.test("ai-proxy scan_meal — retries: 2 passed", async () => {
  const source = await Deno.readTextFile(
    new URL("../ai-proxy/index.ts", import.meta.url),
  );
  assertRetriesNearAnchor(
    source,
    'if (type === "scan_meal" && body.image) {',
    "scan_meal",
  );
});

Deno.test("ai-proxy cart_auditor — retries: 2 passed", async () => {
  const source = await Deno.readTextFile(
    new URL("../ai-proxy/index.ts", import.meta.url),
  );
  assertRetriesNearAnchor(
    source,
    'if (type === "cart_auditor" && body.image) {',
    "cart_auditor",
  );
});

// Single-owner audit 2026-09-26 (P0 #5): the prediction call moved out of
// ai-proxy/index.ts into _shared/prediction_handler.ts (DI'd so it can be
// tested behaviourally — see prediction_handler_test.ts). Repointed, same
// assertion: the ONE geminiChat call there passes retries: 2.
Deno.test("ai-proxy prediction — retries: 2 passed", async () => {
  const source = await Deno.readTextFile(
    new URL("./prediction_handler.ts", import.meta.url),
  );
  assertSoleCallSiteHasRetries(source, "prediction");
});

// A5/OI-226 (f7a2c9, 2026-09-21) — the OTHER half of OI-226: the prediction
// handler's geminiChat() call never destructured `lastError`, so its !content
// branch could not call reportGeminiExhaustion at all (the 3 nutrition sites
// above already could — this was the one geminiChat() site left uninstrumented
// after the food-logging-observations batch and the tool-loop.ts fix, per
// docs/audit/open_issues.md's OI-226 entry naming BOTH gaps explicitly).
//
// Repointed 2026-09-26 (single-owner audit P0 #5): the handler now lives in
// _shared/prediction_handler.ts with reporting injected, so the pin is split
// in two, each position-scoped rather than a whole-file `contains`:
//   (1) in the handler, `lastError` is destructured from the ONE geminiChat
//       call and the injected report runs BEFORE the !content return — now a
//       500, deliberately not a 502 (a 502 is auto-retried by the client and
//       each retry would consume a daily-quota unit; see the handler header);
//   (2) in ai-proxy's prediction branch, the injected report is
//       reportGeminiExhaustion with endpoint "prediction".
// The behaviour itself (report called once, with lastError, and a 500) is
// asserted with fakes in prediction_handler_test.ts.
Deno.test(
  "ai-proxy prediction — reportGeminiExhaustion wired on !content (OI-226)",
  async () => {
    const handler = await Deno.readTextFile(
      new URL("./prediction_handler.ts", import.meta.url),
    );
    const fnIdx = handler.indexOf("export async function handlePrediction(");
    assert(fnIdx >= 0, "handlePrediction not found");
    const body = handler.slice(fnIdx);

    assert(
      body.includes(
        "const { content, modelUsed, tokensUsed, lastError, attemptStatuses } = await deps.geminiChat(",
      ),
      "prediction handler must destructure lastError from geminiChat() — " +
        "without it, reportGeminiExhaustion has nothing to report",
    );
    const reportIdx = body.indexOf("await deps.reportExhaustion(");
    const returnIdx = body.indexOf(
      'return { status: 500, body: { error: "AI temporarily unavailable" } };',
    );
    assert(returnIdx > 0, "the !content 500 return was not found in the handler");
    assert(
      reportIdx >= 0 && reportIdx < returnIdx,
      "the exhaustion report must run BEFORE the !content return, mirroring " +
        "the 3 nutrition sites' own pattern",
    );
    assert(
      !body.includes("status: 502"),
      "the prediction handler must not return 502 — the client auto-retries " +
        "502 and every retry would consume a daily-quota unit",
    );

    const proxy = await Deno.readTextFile(
      new URL("../ai-proxy/index.ts", import.meta.url),
    );
    const anchorIdx = proxy.indexOf('if (type === "prediction") {');
    assert(anchorIdx >= 0, "prediction branch anchor not found in ai-proxy");
    const window = proxy.slice(anchorIdx, anchorIdx + 1500);
    const wiredIdx = window.indexOf("reportGeminiExhaustion(");
    assert(
      wiredIdx >= 0 && window.indexOf("handlePrediction(") < wiredIdx,
      "ai-proxy must inject reportGeminiExhaustion into handlePrediction",
    );
    assert(
      window.slice(wiredIdx, wiredIdx + 300).includes('"prediction"'),
      'the call must pass endpoint="prediction" so this alert stays ' +
        "distinguishable from the other sites sharing the same source",
    );
  },
);

Deno.test("assess-body-composition — retries: 2 passed", async () => {
  const source = await Deno.readTextFile(
    new URL("../assess-body-composition/index.ts", import.meta.url),
  );
  assertSoleCallSiteHasRetries(source, "assess-body-composition");
});

Deno.test("daily-snapshot — retries: 2 passed", async () => {
  const source = await Deno.readTextFile(
    new URL("../daily-snapshot/index.ts", import.meta.url),
  );
  assertSoleCallSiteHasRetries(source, "daily-snapshot");
});

Deno.test("ai-media-proxy — retries: 2 passed", async () => {
  const source = await Deno.readTextFile(
    new URL("../ai-media-proxy/index.ts", import.meta.url),
  );
  assertSoleCallSiteHasRetries(source, "ai-media-proxy");
});

Deno.test("rolling-context — retries: 1 passed (Hermes L21 F3, 2026-09-21 — " +
    "halved from 2 to bound this per-user-loop call's worst-case Gemini " +
    "call amplification across a whole nightly run)", async () => {
  const source = await Deno.readTextFile(
    new URL("../rolling-context/index.ts", import.meta.url),
  );
  assertSoleCallSiteHasRetries(source, "rolling-context", 1);
});

Deno.test("weekly-report — retries: 2 passed", async () => {
  const source = await Deno.readTextFile(
    new URL("../weekly-report/index.ts", import.meta.url),
  );
  assertSoleCallSiteHasRetries(source, "weekly-report");
});

// ---------------------------------------------------------------------------
// redactSecrets (Hermes L40 F1, 2026-09-21) — Deno's fetch rejects a
// network-level failure with a TypeError whose .message embeds the full
// request URL, and the Gemini request URL carries GEMINI_API_KEY as a
// `?key=...` query param. Unredacted, that message can reach
// reportGeminiExhaustion -> public.alerts -> the founder's Telegram digest,
// none of which are secret-safe destinations — the same shape this repo's
// own CLAUDE.md already documents for a Telegram bot token leaking through
// `_shared/telegram.ts`, applied here to a different secret.
// ---------------------------------------------------------------------------

Deno.test("redactSecrets strips the literal GEMINI_API_KEY value wherever it appears", () => {
  const leaky =
    `error sending request for url (https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${TEST_GEMINI_KEY})`;
  const redacted = redactSecrets(leaky);
  assert(!redacted.includes(TEST_GEMINI_KEY), `key leaked in: ${redacted}`);
  assert(redacted.includes("[REDACTED]"), `expected a redaction marker, got: ${redacted}`);
  // The rest of the diagnostic text survives — this is a targeted strip,
  // not a blanket "throw away the whole message" like telegramErrorSummary.
  assert(redacted.includes("generativelanguage.googleapis.com"));
});

Deno.test("redactSecrets also strips a generic key= query param even if the exact literal doesn't match", () => {
  // Belt-and-suspenders form: covers a differently-encoded or rotated key
  // this test's own literal wouldn't catch.
  const leaky = "GET https://generativelanguage.googleapis.com/v1beta/models/x:generateContent?key=SOME-OTHER-VALUE&foo=bar failed";
  const redacted = redactSecrets(leaky);
  assert(!redacted.includes("SOME-OTHER-VALUE"), `key leaked in: ${redacted}`);
  assert(redacted.includes("foo=bar"), "unrelated query params must survive");
});

Deno.test("redactSecrets is a no-op on a string that never contained the key", () => {
  const clean = "HTTP 503: upstream overloaded, try again later";
  assertEquals(redactSecrets(clean), clean);
});

Deno.test("geminiChat: a fetch that THROWS a URL-bearing error never leaks GEMINI_API_KEY into lastError.message", async () => {
  const throwing = ((input: RequestInfo | URL) => {
    const url = typeof input === "string" ? input : (input as URL).href ?? (input as Request).url;
    return Promise.reject(new TypeError(`error sending request for url (${url})`));
  }) as typeof fetch;
  const originalFetch = globalThis.fetch;
  globalThis.fetch = throwing;
  try {
    const result = await geminiChat({
      model: MODEL_FLASH,
      systemPrompt: "sys",
      userPrompt: "hi",
      maxTokens: 100,
      fallbackToLite: false,
    });
    assertEquals(result.content, null);
    assert(result.lastError, "expected a lastError on total failure");
    assert(
      !result.lastError!.message.includes(TEST_GEMINI_KEY),
      `key leaked in lastError.message: ${result.lastError!.message}`,
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

// ── Redact-before-truncate ordering (B-pass F2, 2026-09-21) ───────────────
// Both HTTP-not-ok branches (_callOnce, _callOnceWithTools) used to slice
// the raw response body to 200 chars BEFORE calling redactSecrets(), unlike
// the two catch/transport-error branches (which redact-then-slice). A key
// straddling the 200-char cut would be truncated to an incomplete fragment
// that redactSecrets' exact-literal match can no longer find, leaking that
// fragment unredacted. Constructs a body where the key starts at char 190
// (ends at 216, straddling the cut) to reproduce exactly that shape.

Deno.test("geminiChat: redacts a straddling GEMINI_API_KEY BEFORE truncating the 200-char HTTP-error preview", async () => {
  const padding = "x".repeat(190);
  const rawBody = padding + TEST_GEMINI_KEY + " trailing text past the cut";
  const keyFragment = TEST_GEMINI_KEY.slice(0, 10); // "test-key-n" — what leaked pre-fix

  const { state, restore } = installFetchQueue([
    () => Promise.resolve(httpErrorResponse(503, rawBody)),
  ]);
  try {
    const res = await geminiChat({
      model: MODEL_FLASH,
      systemPrompt: "sys",
      userPrompt: "hi",
      maxTokens: 100,
      fallbackToLite: false,
    });
    assertEquals(res.content, null);
    assert(res.lastError, "expected a lastError on the HTTP error branch");
    assert(
      !res.lastError!.message.includes(keyFragment),
      `key fragment leaked in lastError.message: ${res.lastError!.message}`,
    );
    assertEquals(state.calls, 1);
  } finally {
    restore();
  }
});

Deno.test("geminiChatWithTools: redacts a straddling GEMINI_API_KEY BEFORE truncating the 200-char HTTP-error preview", async () => {
  const padding = "x".repeat(190);
  const rawBody = padding + TEST_GEMINI_KEY + " trailing text past the cut";
  const keyFragment = TEST_GEMINI_KEY.slice(0, 10);

  const { state, restore } = installFetchQueue([
    () => Promise.resolve(httpErrorResponse(400, rawBody)), // 400: non-retriable, one pass, no fallback noise
  ]);
  try {
    let caught: Error | undefined;
    try {
      await geminiChatWithTools(baseOpts);
    } catch (e) {
      caught = e as Error;
    }
    assert(caught, "expected geminiChatWithTools to throw on a non-retriable 400");
    assert(
      !caught!.message.includes(keyFragment),
      `key fragment leaked in thrown Error.message: ${caught!.message}`,
    );
    // 400 is non-retriable: one pass over [Flash, Lite], no 2nd pass —
    // matches "does NOT retry a non-429 4xx" above.
    assertEquals(state.calls, 2);
  } finally {
    restore();
  }
});

Deno.test("geminiChatWithTools: per-attempt console.warn never leaks GEMINI_API_KEY, independent of _callOnceWithTools's own redaction (B-pass F1, 2026-09-21, defense-in-depth)", async () => {
  // Reviewer B (B-pass on this batch) proved by mutation that BEFORE this
  // test/fix existed, reverting _callOnceWithTools's inner redactSecrets()
  // call left this exact console.warn line leaking the raw key on every
  // retriable attempt while all 22 pre-existing tests stayed green — every
  // one of them inspects only the FINAL thrown/alerted message, which stays
  // clean because geminiChatWithTools separately re-redacts lastReason for
  // THAT message. This test closes that gap by asserting on the actual
  // per-attempt log line itself.
  const warnings: string[] = [];
  const originalWarn = console.warn;
  console.warn = (...args: unknown[]) => {
    warnings.push(args.map(String).join(" "));
  };
  const throwing = ((input: RequestInfo | URL) => {
    const url = typeof input === "string" ? input : (input as URL).href ?? (input as Request).url;
    return Promise.reject(new TypeError(`error sending request for url (${url})`));
  }) as typeof fetch;
  const originalFetch = globalThis.fetch;
  globalThis.fetch = throwing;
  try {
    try {
      await geminiChatWithTools({
        model: MODEL_FLASH,
        systemPrompt: "sys",
        messages: [{ role: "user", parts: [{ text: "hi" }] }],
        tools: [],
      });
    } catch (_) { /* the exhaustion throw itself is covered by the test below */ }
    const attemptWarnings = warnings.filter((w) => w.includes("failed ("));
    assert(
      attemptWarnings.length > 0,
      "expected at least one per-attempt failure console.warn to have fired",
    );
    for (const w of attemptWarnings) {
      assert(!w.includes(TEST_GEMINI_KEY), `key leaked in a console.warn call: ${w}`);
    }
  } finally {
    globalThis.fetch = originalFetch;
    console.warn = originalWarn;
  }
});

Deno.test("geminiChatWithTools: a persistent fetch throw never leaks GEMINI_API_KEY into the thrown exhaustion Error's message", async () => {
  const throwing = ((input: RequestInfo | URL) => {
    const url = typeof input === "string" ? input : (input as URL).href ?? (input as Request).url;
    return Promise.reject(new TypeError(`error sending request for url (${url})`));
  }) as typeof fetch;
  const originalFetch = globalThis.fetch;
  globalThis.fetch = throwing;
  try {
    let caught: Error | undefined;
    try {
      await geminiChatWithTools({
        model: MODEL_FLASH,
        systemPrompt: "sys",
        messages: [{ role: "user", parts: [{ text: "hi" }] }],
        tools: [],
      });
    } catch (e) {
      caught = e as Error;
    }
    assert(caught, "expected geminiChatWithTools to throw on total exhaustion");
    assert(
      !caught!.message.includes(TEST_GEMINI_KEY),
      `key leaked in thrown Error.message: ${caught!.message}`,
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});
