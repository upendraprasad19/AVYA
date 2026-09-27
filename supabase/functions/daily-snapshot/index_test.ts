// supabase/functions/daily-snapshot/index_test.ts
//
// Two layers: SOURCE-GREP for what's cheapest/clearest to pin textually
// (kill switches, guard literals, ordering of two statements within the
// SAME function), and — since a2b (single-owner batch, 2026-09-27) — real
// BEHAVIORAL coverage of extractCoachingNotes()/mergeCoachMemoryFields()
// through a dynamic import with SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY set
// BEFORE the import (same pattern as ai-media-proxy/founder-digest).
//
// ⚠ CORRECTED (a2b): this file's own a2a-era comment claimed a dynamic
// import "would still throw at import time" because of the module-scope
// `Deno.env.get(...)!` reads — that was never actually re-verified after
// a2a added the `import.meta.main` guard, and it is WRONG: setting the two
// env vars before `await import(...)` resolves cleanly, exactly like the
// four other Edge Functions using this pattern. `handler()` itself is
// still never imported/called here — this file drives the two EXPORTED
// functions directly, not the HTTP handler.
//
// Non-behavioral (a genuine live-Postgres round-trip is out of scope for
// an Edge-Function-only concept — see docs/sot_registry.yaml
// `user_preferences_coaching_notes`'s `presence_only: true`): the fake
// client below is an in-memory filter/sort engine over a fixture array, not
// a real Postgres connection. It DOES apply the real `.eq/.in/.gt/.lte/
// .not/.neq/.order/.limit` semantics against that fixture, so it proves
// extractCoachingNotes's OWN logic (which rows it reads, what it does with
// them), not Postgres's query planner.

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.env.set("SUPABASE_URL", "https://example.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-role-key");
Deno.env.set("DISABLE_GEMINI_FAILURE_ALERT", "true");

const source = Deno.readTextFileSync(
  new URL("./index.ts", import.meta.url),
);

const { extractCoachingNotes, mergeCoachMemoryFields } = await import(
  "./index.ts"
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
    // a2b: the branch now returns the tri-state discriminant, not a bare
    // `null` (item 12) — repointed from "return null;\n  }".
    const branchEnd = source.indexOf("return { ok: false };\n  }", branchIdx);
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

Deno.test("extractCoachingNotes is exported with injectable geminiChatFn/mergeCoachingNotesFn/mergeCoachMemoryFieldsFn, all defaulting to the real functions", () => {
  assert(
    source.includes("export async function extractCoachingNotes("),
    "must be exported for a2b's own tests to call it directly",
  );
  assert(
    source.includes("geminiChatFn = geminiChat,"),
    "the injectable geminiChatFn param must default to the REAL geminiChat import",
  );
  assert(
    source.includes("mergeCoachingNotesFn = mergeCoachingNotes,"),
    "the injectable mergeCoachingNotesFn param must default to the REAL " +
      "mergeCoachingNotes function (B-pass finding 1) — no production call " +
      "site passes a second argument",
  );
  assert(
    source.includes("mergeCoachMemoryFieldsFn = mergeCoachMemoryFields,"),
    "the injectable mergeCoachMemoryFieldsFn param must default to the " +
      "REAL mergeCoachMemoryFields function (B-pass finding 1)",
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

Deno.test(
  "private_mode is checked BEFORE the extractCoachingNotes call, not after (round-3 #9)",
  () => {
    // a2b: the OLD isStale computation and the extraction call were both
    // separate statements inside handler()'s body, so their SOURCE POSITION
    // matched execution order. Now the entire read/consume/extract sequence
    // is encapsulated INSIDE extractCoachingNotes (a function defined
    // EARLIER in the file, before handler()) — a text-position anchor
    // pointing INSIDE that function would sit before privateModeIdx in the
    // source despite running AFTER it, which would assert the wrong thing.
    // Asserting private_mode gates before the CALL SITE is what actually
    // proves the ordering: JS evaluates the call's arguments and body only
    // once execution reaches it, so gating before the call structurally
    // gates before everything the call does, including the read/consume/
    // extract sequence now inside it.
    const privateModeIdx = source.indexOf("if (!existing?.private_mode) {");
    const extractCallIdx = source.indexOf(
      "const result = await extractCoachingNotes(",
    );
    assert(
      privateModeIdx >= 0 && extractCallIdx >= 0,
      "both anchors must exist",
    );
    assert(
      privateModeIdx < extractCallIdx,
      "private_mode must gate BEFORE extractCoachingNotes is even called — " +
        "this is the exact ordering round 3 finding #9 required, now " +
        "expressed at the call boundary since the read/consume/extract " +
        "sequence moved inside the callee",
    );
  },
);

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

Deno.test("the old isStale wall-clock guard is fully removed (item 7)", () => {
  assert(
    !source.includes("const isStale ="),
    "isStale must be gone — the watermark itself is now the staleness " +
      "mechanism (a fixed 6h wall-clock gate reads a FUTURE-DATED " +
      "in_app_orphan row's created_at as recent and can suppress " +
      "extraction entirely)",
  );
  assert(
    !source.includes("const sixHoursMs ="),
    "the old local sixHoursMs constant must be gone too, not just isStale",
  );
});

Deno.test(
  "mergeCoachingNotesFn/mergeCoachMemoryFieldsFn are called only on a non-empty extraction, and GATE the watermark advance (item 18, revised by B-pass finding 1)",
  () => {
    // B-pass finding 1 (2026-09-27) moved the merge calls OUT of the
    // handler and INTO extractCoachingNotes itself, so the handler no
    // longer calls mergeCoachingNotes directly at all — assert that.
    assert(
      !source.includes("await mergeCoachingNotes(supabaseClient"),
      "the handler must no longer call mergeCoachingNotes directly — " +
        "extractCoachingNotes owns the merge step now, gating its own " +
        "watermark advance on merge success",
    );
    assert(
      !source.includes("await mergeCoachMemoryFields(supabaseClient"),
      "the handler must no longer call mergeCoachMemoryFields directly " +
        "either, for the same reason",
    );
    const gateIdx = source.indexOf(
      "if (Object.keys(extracted).length > 0) {",
    );
    const mergeCallIdx = source.indexOf(
      "await mergeCoachingNotesFn(supabase, userId, extracted);",
    );
    const watermarkWriteIdx = source.indexOf(
      "last_extraction_at: lastRowCreatedAt,",
    );
    assert(
      gateIdx >= 0 && mergeCallIdx > gateIdx,
      "mergeCoachingNotesFn must be called INSIDE the non-empty-facts " +
        "gate, not unconditionally on every ok:true result",
    );
    assert(
      watermarkWriteIdx > mergeCallIdx,
      "the watermark write must be SOURCE-ORDERED after the merge call, " +
        "not before it — the whole point of B-pass finding 1's fix",
    );
  },
);

// ── a2b behavioral fixtures ───────────────────────────────────────────────
//
// A minimal in-memory Postgres-filter stand-in. Applies the SAME operators
// extractCoachingNotes actually calls (eq/in/gt/lte/not/neq/order/limit) to
// a fixture row array, so a mutation to any of those calls in the real
// source changes what these tests observe — that is the whole point of a
// behavioral test over a source-grep one here.
//
// B-pass finding 6 (2026-09-27): gt/lte/order below compare with a RAW
// STRING `>`/`<=`, not Date.parse(). This is deliberate, not a gap — the
// reviewer's own suggested fix (parse both sides through Date.parse()) was
// checked and rejected: Date.parse() TRUNCATES TO MILLISECOND precision,
// which would silently defeat the exact microsecond-precision exclusion
// the production code's own readFromIso/readStartIso comparison exists to
// get right (see the "microsecond-identical" test below) — the fixture
// would then be LESS faithful to real Postgres timestamptz comparison, not
// more. Raw string comparison is correct here PROVIDED every timestamp
// compared in the same test uses the SAME format/precision (which every
// row in this file does, via pgTs()) — the real hazard the reviewer named
// is a future test mixing formats (e.g. a raw new Date().toISOString()
// literal alongside a pgTs() row), which WOULD silently misorder under
// string comparison. Always build fixture timestamps through pgTs().

interface Row {
  user_id: string;
  user_message: string;
  ai_response: string;
  channel: string;
  created_at: string;
}

interface RecordedCall {
  method: string;
  args: unknown[];
}

function runFilters(rows: Row[], calls: RecordedCall[]): Row[] {
  let result = [...rows];
  for (const { method, args } of calls) {
    switch (method) {
      case "eq": {
        const [col, val] = args as [keyof Row, unknown];
        result = result.filter((r) => r[col] === val);
        break;
      }
      case "in": {
        const [col, vals] = args as [keyof Row, unknown[]];
        result = result.filter((r) => vals.includes(r[col]));
        break;
      }
      case "gt": {
        const [col, val] = args as [keyof Row, string];
        result = result.filter((r) => String(r[col]) > val);
        break;
      }
      case "lte": {
        const [col, val] = args as [keyof Row, string];
        result = result.filter((r) => String(r[col]) <= val);
        break;
      }
      case "neq": {
        const [col, val] = args as [keyof Row, unknown];
        result = result.filter((r) => r[col] !== val);
        break;
      }
      case "not": {
        const [col, op, val] = args as [keyof Row, string, unknown];
        if (op === "is") {
          result = result.filter((r) => (r[col] as unknown) !== val);
        } else if (op === "like") {
          const pattern = String(val).replace(/%/g, "");
          result = result.filter((r) => !String(r[col] ?? "").startsWith(pattern));
        }
        break;
      }
      case "order": {
        const [col, opts] = args as [keyof Row, { ascending?: boolean }];
        const asc = opts?.ascending !== false;
        result = [...result].sort((a, b) => {
          const av = String(a[col]);
          const bv = String(b[col]);
          if (av === bv) return 0;
          return asc ? (av < bv ? -1 : 1) : (av > bv ? -1 : 1);
        });
        break;
      }
      case "limit": {
        const [n] = args as [number];
        result = result.slice(0, n);
        break;
      }
      // select / maybeSingle: no filtering effect.
    }
  }
  return result;
}

// Not `implements PromiseLike<...>` — a generic `.then()` signature that's
// actually duck-type-awaitable at runtime doesn't structurally satisfy
// PromiseLike's own generic signature under strict checking. `await` only
// needs a callable `.then`, which this class provides.
class FakeBuilder {
  calls: RecordedCall[] = [];
  constructor(
    private resolver: (calls: RecordedCall[]) => { data: unknown; error: unknown },
  ) {}
  private rec(method: string, args: unknown[]) {
    this.calls.push({ method, args });
    return this;
  }
  select(...a: unknown[]) {
    return this.rec("select", a);
  }
  eq(...a: unknown[]) {
    return this.rec("eq", a);
  }
  in(...a: unknown[]) {
    return this.rec("in", a);
  }
  gt(...a: unknown[]) {
    return this.rec("gt", a);
  }
  lte(...a: unknown[]) {
    return this.rec("lte", a);
  }
  neq(...a: unknown[]) {
    return this.rec("neq", a);
  }
  not(...a: unknown[]) {
    return this.rec("not", a);
  }
  order(...a: unknown[]) {
    return this.rec("order", a);
  }
  limit(...a: unknown[]) {
    return this.rec("limit", a);
  }
  maybeSingle(...a: unknown[]) {
    return this.rec("maybeSingle", a);
  }
  upsert(...a: unknown[]) {
    return this.rec("upsert", a);
  }
  // deno-lint-ignore no-explicit-any
  then<T, R>(onF?: any, onR?: any) {
    return Promise.resolve(this.resolver(this.calls)).then(onF, onR);
  }
}

function fakeSupabase(opts: {
  convoRows?: Row[];
  convosError?: { message: string };
  rpcResult?: { data: unknown; error: unknown };
  onRpc?: (name: string, args: Record<string, unknown>) => void;
  onUpsert?: (table: string, payload: Record<string, unknown>) => void;
}) {
  const rows = opts.convoRows ?? [];
  return {
    from(table: string) {
      return new FakeBuilder((calls) => {
        const upsertCall = calls.find((c) => c.method === "upsert");
        if (upsertCall) {
          opts.onUpsert?.(table, upsertCall.args[0] as Record<string, unknown>);
          return { data: null, error: null };
        }
        if (table !== "ai_coach_interactions") {
          const isSingle = calls.some((c) => c.method === "maybeSingle");
          return isSingle ? { data: null, error: null } : { data: [], error: null };
        }
        if (opts.convosError) return { data: null, error: opts.convosError };
        const filtered = runFilters(rows, calls);
        return { data: filtered, error: null };
      });
    },
    // deno-lint-ignore no-explicit-any
    rpc(name: string, args: any) {
      opts.onRpc?.(name, args);
      return Promise.resolve(opts.rpcResult ?? { data: 1, error: null });
    },
    // deno-lint-ignore no-explicit-any
  } as any;
}

/** A geminiChatFn stub that records every call and returns a fixed reply. */
function fakeGemini(content: string | null) {
  // deno-lint-ignore no-explicit-any
  const calls: any[] = [];
  const fn = (args: unknown) => {
    calls.push(args);
    return Promise.resolve({
      content,
      modelUsed: content ? "fake-model" : null,
      tokensUsed: 0,
      lastError: content ? null : { status: 500, message: "fake exhaustion" },
    });
  };
  return { fn, calls };
}

const NOW = Date.now();
/** A Postgres-native-shaped timestamp: fixed offset from a captured NOW, explicit microseconds. */
function pgTs(offsetMs: number, micros = "000000"): string {
  const iso = new Date(NOW + offsetMs).toISOString(); // "...T...sssZ"
  const datePart = iso.slice(0, 19); // strip ".sssZ"
  return `${datePart}.${micros}+00:00`;
}

function row(overrides: Partial<Row>): Row {
  return {
    user_id: "u1",
    user_message: "hi",
    ai_response: "hello",
    channel: "app",
    created_at: pgTs(-60_000),
    ...overrides,
  };
}

Deno.test("extractCoachingNotes: a row exactly AT the watermark (microsecond-identical) is NOT re-read", async () => {
  const watermark = pgTs(-120_000, "100000");
  const excluded = row({ created_at: watermark, user_message: "OLD already-read message" });
  const included = row({ created_at: pgTs(-60_000, "000000"), user_message: "NEW message" });
  const supabase = fakeSupabase({ convoRows: [excluded, included] });
  const gemini = fakeGemini("{}");

  const result = await extractCoachingNotes(supabase, "u1", watermark, {
    geminiChatFn: gemini.fn,
  });

  assert(result.ok, "expected a genuine extraction attempt");
  assertEquals(gemini.calls.length, 1);
  const prompt = String(gemini.calls[0].userPrompt);
  assert(!prompt.includes("OLD already-read message"), "the row AT the watermark must be excluded (strict .gt())");
  assert(prompt.includes("NEW message"), "the row after the watermark must be included");
});

Deno.test("extractCoachingNotes: a future-dated row (beyond the read-start bound) is excluded, and skips Gemini/consume entirely when nothing else is present", async () => {
  const futureDated = row({ created_at: pgTs(10 * 60_000), user_message: "future ghost" });
  const supabase = fakeSupabase({ convoRows: [futureDated] });
  const gemini = fakeGemini("{}");

  const result = await extractCoachingNotes(supabase, "u1", null, {
    geminiChatFn: gemini.fn,
  });

  assertEquals(result.ok, false);
  assertEquals(gemini.calls.length, 0, "Gemini must never be called when the only row is excluded by .lte(readStartIso)");
});

Deno.test("extractCoachingNotes: an app_event-shaped user_message is excluded even inside an allowlisted channel", async () => {
  const eventRow = row({ user_message: "{event: workout_completed}", ai_response: "" });
  const realRow = row({
    created_at: pgTs(-30_000),
    user_message: "I'm vegetarian and have a bad knee",
  });
  const supabase = fakeSupabase({ convoRows: [eventRow, realRow] });
  const gemini = fakeGemini("{}");

  await extractCoachingNotes(supabase, "u1", null, { geminiChatFn: gemini.fn });

  assertEquals(gemini.calls.length, 1);
  const prompt = String(gemini.calls[0].userPrompt);
  assert(!prompt.includes("{event:"), "app_event-shaped content must never reach the prompt");
  assert(prompt.includes("I'm vegetarian and have a bad knee"), "real message content must reach the prompt");
});

Deno.test("extractCoachingNotes: an empty {} extraction is ok:true and still advances the watermark", async () => {
  const only = row({ created_at: pgTs(-30_000) });
  let upserted: Record<string, unknown> | null = null;
  const supabase = fakeSupabase({
    convoRows: [only],
    onUpsert: (_table, payload) => { upserted = payload; },
  });
  const gemini = fakeGemini("{}");

  const result = await extractCoachingNotes(supabase, "u1", null, { geminiChatFn: gemini.fn });

  assert(result.ok, "an empty extraction is still ok:true");
  if (result.ok) assertEquals(Object.keys(result.facts).length, 0);
  assert(upserted !== null, "the watermark write must have happened");
  assertEquals((upserted as Record<string, unknown>).last_extraction_at, only.created_at);
});

Deno.test("extractCoachingNotes: advances the watermark to the RAW last-row string, byte-exact (no reformatting through Date)", async () => {
  const earlier = row({ created_at: pgTs(-120_000, "100000") });
  const latest = row({ created_at: pgTs(-60_000, "987654") });
  let upserted: Record<string, unknown> | null = null;
  const supabase = fakeSupabase({
    convoRows: [earlier, latest],
    onUpsert: (_table, payload) => { upserted = payload; },
  });
  const gemini = fakeGemini("{}");

  await extractCoachingNotes(supabase, "u1", null, { geminiChatFn: gemini.fn });

  assert(upserted !== null);
  assertEquals(
    (upserted as Record<string, unknown>).last_extraction_at,
    latest.created_at,
    "must be the EXACT raw string of the last row Postgres returned (post-.order()), " +
      "not a value round-tripped through new Date().toISOString() (which would " +
      "truncate the .987654 microseconds to .987 and swap the +00:00 suffix for Z)",
  );
});

Deno.test("extractCoachingNotes: a Gemini call failure (!rawText) is ok:false and does NOT advance the watermark", async () => {
  const only = row({ created_at: pgTs(-30_000) });
  let upsertCalled = false;
  const supabase = fakeSupabase({
    convoRows: [only],
    onUpsert: () => { upsertCalled = true; },
  });
  const gemini = fakeGemini(null); // content:null → !rawText branch

  const result = await extractCoachingNotes(supabase, "u1", null, { geminiChatFn: gemini.fn });

  assertEquals(result.ok, false);
  assert(!upsertCalled, "a genuine call failure must NOT advance the watermark — retry next run");
});

Deno.test("extractCoachingNotes: a malformed (non-empty, unparseable) Gemini reply is ok:false and does NOT advance the watermark", async () => {
  const only = row({ created_at: pgTs(-30_000) });
  let upsertCalled = false;
  const supabase = fakeSupabase({
    convoRows: [only],
    onUpsert: () => { upsertCalled = true; },
  });
  const gemini = fakeGemini("not valid json{{{");

  const result = await extractCoachingNotes(supabase, "u1", null, { geminiChatFn: gemini.fn });

  assertEquals(result.ok, false);
  assert(
    !upsertCalled,
    "a malformed-but-non-null reply must be treated the SAME as a call " +
      "failure (item 12's third state) — advancing here would silently " +
      "lose this window's facts forever",
  );
});

Deno.test("extractCoachingNotes: a syntactically-valid but non-object Gemini reply (null/array/string/number) is ok:false and does NOT advance the watermark (B-pass finding 2)", async () => {
  for (const badJson of ["null", "[]", '"just a string"', "42"]) {
    const only = row({ created_at: pgTs(-30_000) });
    let upsertCalled = false;
    const supabase = fakeSupabase({
      convoRows: [only],
      onUpsert: () => { upsertCalled = true; },
    });
    const gemini = fakeGemini(badJson);

    const result = await extractCoachingNotes(supabase, "u1", null, { geminiChatFn: gemini.fn });

    assertEquals(result.ok, false, `expected ok:false for Gemini reply ${JSON.stringify(badJson)}`);
    assert(
      !upsertCalled,
      `expected no watermark advance for Gemini reply ${JSON.stringify(badJson)} — ` +
        "JSON.parse(\"null\") does not throw, so without an explicit object-shape " +
        "check this would slip past the malformed-JSON branch as ok:true",
    );
  }
});

Deno.test("extractCoachingNotes: a mergeCoachingNotesFn failure does NOT advance the watermark, and skips mergeCoachMemoryFieldsFn entirely (B-pass finding 1)", async () => {
  const newRow = row({ created_at: pgTs(-1_000), user_message: "I'm vegetarian" });
  let watermarkAdvanced = false;
  let memoryMergeCalled = false;
  const supabase = fakeSupabase({
    convoRows: [newRow],
    onUpsert: (table) => {
      if (table === "coach_memory") watermarkAdvanced = true;
    },
  });
  const gemini = fakeGemini(JSON.stringify({ diet_preference: "vegetarian" }));

  const result = await extractCoachingNotes(supabase, "u1", null, {
    geminiChatFn: gemini.fn,
    mergeCoachingNotesFn: () => {
      throw new Error("merge boom");
    },
    mergeCoachMemoryFieldsFn: () => {
      memoryMergeCalled = true;
      return Promise.resolve();
    },
  });

  assertEquals(result.ok, true, "the extraction itself succeeded — only the merge failed");
  assert(
    !memoryMergeCalled,
    "a mergeCoachingNotesFn failure must short-circuit the sequential " +
      "await chain — mergeCoachMemoryFieldsFn must never run",
  );
  assert(
    !watermarkAdvanced,
    "a merge-write failure must NOT advance the watermark (B-pass finding 1) — " +
      "the pre-fix design advanced unconditionally inside extractCoachingNotes " +
      "BEFORE the caller's merge call could even throw, permanently losing " +
      "these facts on any downstream write failure",
  );
});

Deno.test("extractCoachingNotes: a mergeCoachMemoryFieldsFn failure ALSO does NOT advance the watermark (B-pass finding 1, second call in the sequence)", async () => {
  const newRow = row({ created_at: pgTs(-1_000), user_message: "I'm vegetarian" });
  let watermarkAdvanced = false;
  let notesMergeCalled = false;
  const supabase = fakeSupabase({
    convoRows: [newRow],
    onUpsert: (table) => {
      if (table === "coach_memory") watermarkAdvanced = true;
    },
  });
  const gemini = fakeGemini(JSON.stringify({ diet_preference: "vegetarian" }));

  const result = await extractCoachingNotes(supabase, "u1", null, {
    geminiChatFn: gemini.fn,
    mergeCoachingNotesFn: () => {
      notesMergeCalled = true;
      return Promise.resolve();
    },
    mergeCoachMemoryFieldsFn: () => {
      throw new Error("memory merge boom");
    },
  });

  assertEquals(result.ok, true);
  assert(notesMergeCalled, "mergeCoachingNotesFn must run first and succeed in this scenario");
  assert(
    !watermarkAdvanced,
    "a mergeCoachMemoryFieldsFn failure, even AFTER mergeCoachingNotesFn " +
      "succeeded, must still block the watermark advance — both merges are " +
      "part of the same all-or-nothing gate",
  );
});

Deno.test("extractCoachingNotes: a genuine conversation-read error is LOGGED, distinct from the ordinary no-new-messages case (B-pass finding 5)", async () => {
  const supabase = fakeSupabase({
    convosError: { message: "connection reset by peer" },
  });
  const originalError = console.error;
  const logged: unknown[][] = [];
  console.error = (...args: unknown[]) => { logged.push(args); };
  try {
    const result = await extractCoachingNotes(supabase, "u1", null, {});
    assertEquals(result.ok, false);
  } finally {
    console.error = originalError;
  }
  assert(
    logged.some((args) =>
      args.some((a) =>
        typeof a === "string" && a.includes("conversation read error")
      )
    ),
    "a genuine read error (data:null, error set) must be logged distinctly " +
      "from the ordinary empty-window case, which logs nothing",
  );
});

Deno.test("extractCoachingNotes: quota-meter exhaustion (-1) skips Gemini and does NOT advance the watermark", async () => {
  const only = row({ created_at: pgTs(-30_000) });
  let upsertCalled = false;
  const supabase = fakeSupabase({
    convoRows: [only],
    rpcResult: { data: -1, error: null },
    onUpsert: () => { upsertCalled = true; },
  });
  const gemini = fakeGemini("{}");

  const result = await extractCoachingNotes(supabase, "u1", null, { geminiChatFn: gemini.fn });

  assertEquals(result.ok, false);
  assertEquals(gemini.calls.length, 0, "Gemini must not be called once the meter reports exhaustion");
  assert(!upsertCalled, "the rows were read but not processed — must not advance");
});

Deno.test("extractCoachingNotes: a quota-meter RPC error fails CLOSED — skips Gemini and does NOT advance the watermark", async () => {
  const only = row({ created_at: pgTs(-30_000) });
  let upsertCalled = false;
  const supabase = fakeSupabase({
    convoRows: [only],
    rpcResult: { data: null, error: { message: "boom" } },
    onUpsert: () => { upsertCalled = true; },
  });
  const gemini = fakeGemini("{}");

  const result = await extractCoachingNotes(supabase, "u1", null, { geminiChatFn: gemini.fn });

  assertEquals(result.ok, false);
  assertEquals(gemini.calls.length, 0, "fail CLOSED — an unreadable meter must not let Gemini run unmetered");
  assert(!upsertCalled);
});

Deno.test("extractCoachingNotes: the quota meter is called with p_limit=1 (item 8/9), and BEFORE the Gemini call (item 13)", async () => {
  const only = row({ created_at: pgTs(-30_000) });
  const sequence: string[] = [];
  const supabase = fakeSupabase({
    convoRows: [only],
    onRpc: (_name, args) => {
      sequence.push("rpc:quota-meter");
      assertEquals(args.p_quota_key, "coach_extraction");
      assertEquals(args.p_limit, 1);
    },
  });
  const gemini = {
    fn: (_args: unknown) => {
      sequence.push("gemini");
      return Promise.resolve({
        content: "{}",
        modelUsed: "fake-model",
        tokensUsed: 0,
        lastError: null,
      });
    },
  };

  await extractCoachingNotes(supabase, "u1", null, { geminiChatFn: gemini.fn });

  assertEquals(sequence, ["rpc:quota-meter", "gemini"], "consume must happen BEFORE the Gemini call, not after");
});

Deno.test("mergeCoachMemoryFields: a single-fact patch (no timestamp key) still triggers upsertCoachMemory (item 11)", async () => {
  let upserted: Record<string, unknown> | null = null;
  const supabase = fakeSupabase({
    onUpsert: (_table, payload) => { upserted = payload; },
  });

  // fetchCoachMemory's own .from("coach_memory").select("*")...maybeSingle()
  // resolves via the generic non-"ai_coach_interactions" branch above,
  // which returns { data: null, error: null } for a maybeSingle() call —
  // i.e. "no existing row" — private_mode is therefore falsy and the
  // function proceeds, matching production's fail-open posture.
  await mergeCoachMemoryFields(supabase, "u1", { preferred_name: "Upen" });

  assert(
    upserted !== null,
    "a patch with exactly ONE identity field (no timestamp key added by " +
      "this function anymore) must still pass the > 0 guard and upsert — " +
      "reverting this to > 1 (the pre-fix guard) would silently drop it",
  );
  assertEquals((upserted as Record<string, unknown>).preferred_name, "Upen");
  assert(
    !("last_extraction_at" in (upserted as Record<string, unknown>)),
    "mergeCoachMemoryFields must no longer write last_extraction_at itself (item 11)",
  );
});

Deno.test("mergeCoachMemoryFields no longer writes last_extraction_at (source presence/absence check)", () => {
  // Per the plan's own Process section: "grep-based regression test
  // acceptable here, since it's a presence/absence check on a single
  // line, not a behavioral claim." The behavioral test above ALSO covers
  // this via the upsert payload; this pins the exact source shape too.
  const fnIdx = source.indexOf("export async function mergeCoachMemoryFields(");
  assert(fnIdx >= 0, "mergeCoachMemoryFields not found");
  const guardIdx = source.indexOf("Object.keys(patch).length > 0", fnIdx);
  assert(guardIdx >= 0, "the widened > 0 guard must be present");
  const body = source.slice(fnIdx, guardIdx);
  assert(
    !body.includes("patch.last_extraction_at ="),
    "mergeCoachMemoryFields must not assign patch.last_extraction_at anymore",
  );
});
