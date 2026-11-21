// Deno tests for the OI-505 fix 4 half of _shared/chat_dedup.ts (diagnose
// d9a3b5): a RETRY of a finished turn (client_retry: true + the turn's
// client_key) reuses that turn: a replay for a complete row, 503 in_progress
// for a young pending one, everything else falls through to the old path.
//
// Run: deno test --no-check --allow-all --node-modules-dir=none supabase/functions/_shared/chat_dedup_keyed_test.ts

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  KEYED_MAX_REPLAY_AGE_MS,
  type KeyedRow,
  keyedReplayVerdict,
  resolveKeyedReplay,
} from "./chat_dedup.ts";

const SENTINEL = "failed";
const NOW = Date.parse("2026-11-13T10:00:00.000Z");
const MSG = "what is my workout";
const KEY = "coach_1763000000000";
const ago = (ms: number) => new Date(NOW - ms).toISOString();

function row(over: Partial<KeyedRow> = {}): KeyedRow {
  return {
    id: "r1",
    user_message: MSG,
    ai_response: "Push day.",
    model_used: "Gemini 3.1 Flash Lite",
    tokens_used: 12,
    tool_calls: null,
    created_at: ago(5 * 60_000),
    ...over,
  };
}
const verdict = (rows: KeyedRow[] | null | undefined, message = MSG) =>
  keyedReplayVerdict(rows, { message, loopThrewSentinel: SENTINEL, nowMs: NOW });

Deno.test("verdict: no rows, null, undefined fall through", () => {
  assertEquals(verdict([]).kind, "fall_through");
  assertEquals(verdict(null).kind, "fall_through");
  assertEquals(verdict(undefined).kind, "fall_through");
});

Deno.test("verdict: a complete row of the same message is replayed", () => {
  const v = verdict([row()]);
  assertEquals(v.kind, "replay_reply");
  assert(v.kind === "replay_reply" && v.row.id === "r1");
});

Deno.test("verdict: a row of ANOTHER message is never replayed (the key may be reused for a different ask)", () => {
  assertEquals(verdict([row({ user_message: "something else" })]).kind, "fall_through");
});

Deno.test("verdict: A real + B newer failed replays A", () => {
  const a = row({ id: "A", created_at: ago(20 * 60_000) });
  const b = row({
    id: "B",
    ai_response: "[failed] runToolLoop threw",
    model_used: SENTINEL,
    created_at: ago(10 * 60_000),
  });
  const v = verdict([b, a]);
  assert(v.kind === "replay_reply" && v.row.id === "A");
});

Deno.test("verdict: the NEWEST complete row wins, whatever order the rows arrive in", () => {
  const older = row({ id: "old", created_at: ago(60 * 60_000) });
  const newer = row({ id: "new", created_at: ago(30 * 60_000) });
  for (const rows of [[older, newer], [newer, older]]) {
    const v = verdict(rows);
    assert(v.kind === "replay_reply" && v.row.id === "new");
  }
});

Deno.test("verdict: a failure-sentinel row alone falls through (the text dedup still decides)", () => {
  assertEquals(
    verdict([row({ model_used: SENTINEL, ai_response: "[failed] runToolLoop threw" })]).kind,
    "fall_through",
  );
});

Deno.test("verdict: a young pending row is in_progress", () => {
  assertEquals(
    verdict([row({ model_used: "pending", ai_response: "", created_at: ago(30_000) })]).kind,
    "in_progress",
  );
});

Deno.test("verdict: a stale pending row (>= 150 s) falls through", () => {
  assertEquals(
    verdict([row({ model_used: "pending", ai_response: "", created_at: ago(151_000) })]).kind,
    "fall_through",
  );
});

Deno.test("verdict: a complete row beats a young pending one (the answer exists)", () => {
  const done = row({ id: "done", created_at: ago(10 * 60_000) });
  const pending = row({ id: "p", model_used: "pending", ai_response: "", created_at: ago(10_000) });
  assertEquals(verdict([pending, done]).kind, "replay_reply");
});

Deno.test("verdict: rows whose reply carried a card, a tile or legacy log tags are re-run, never replayed", () => {
  for (const status of ["queued", "queued_for_user_confirmation", "tile_requested"]) {
    assertEquals(
      verdict([row({ tool_calls: [{ name: "logSet", status }] })]).kind,
      "fall_through",
      status,
    );
  }
  assertEquals(
    verdict([row({ tool_calls: [{ name: "legacy_log_actions", status: "ok", args: { count: 1 } }] })]).kind,
    "fall_through",
    "the marker by NAME",
  );
  // A read tool that ran is fine to replay.
  assertEquals(
    verdict([row({ tool_calls: [{ name: "getWorkoutHistory", status: "ok" }] })]).kind,
    "replay_reply",
  );
});

Deno.test("verdict: tool_calls as an object, a string, a number or null never throws", () => {
  for (const tc of [{ promoted: true }, "x", 3, null, undefined]) {
    assertEquals(verdict([row({ tool_calls: tc })]).kind, "replay_reply");
  }
});

Deno.test("verdict: the age cap: a 6 h + 1 min old answer is not replayed, 5 h 59 min is", () => {
  assertEquals(
    verdict([row({ created_at: ago(KEYED_MAX_REPLAY_AGE_MS + 60_000) })]).kind,
    "fall_through",
  );
  assertEquals(
    verdict([row({ created_at: ago(KEYED_MAX_REPLAY_AGE_MS - 60_000) })]).kind,
    "replay_reply",
  );
});

Deno.test("verdict: an unparseable or missing created_at is never replayed", () => {
  assertEquals(verdict([row({ created_at: "not a date" })]).kind, "fall_through");
  assertEquals(verdict([row({ created_at: undefined })]).kind, "fall_through");
});

Deno.test("verdict: an empty ai_response is not a reply", () => {
  assertEquals(verdict([row({ ai_response: "" })]).kind, "fall_through");
  assertEquals(verdict([row({ ai_response: null })]).kind, "fall_through");
});

// ── resolveKeyedReplay: the wiring, with an injected lookup ────────────────

function harness(rows: KeyedRow[] | Error, over: Record<string, unknown> = {}) {
  const calls: string[] = [];
  const run = () =>
    resolveKeyedReplay({
      clientRetry: true,
      clientKey: KEY,
      message: MSG,
      nowMs: NOW,
      loopThrewSentinel: SENTINEL,
      killSwitch: false,
      fetchRows: (k: string) => {
        calls.push(k);
        return rows instanceof Error ? Promise.reject(rows) : Promise.resolve(rows);
      },
      ...over,
    });
  return { calls, run };
}

Deno.test("resolve: a Retry with a key and a finished row replays it (one lookup, with that key)", async () => {
  const h = harness([row()]);
  const r = await h.run();
  assert(r.kind === "replay" && r.row.id === "r1");
  assertEquals(h.calls, [KEY]);
});

Deno.test("resolve: no lookup at all without client_retry === true (only the boolean true counts)", async () => {
  for (const marker of [undefined, null, false, "true", 1, "1", {}]) {
    const h = harness([row()], { clientRetry: marker });
    assertEquals((await h.run()).kind, "none", String(marker));
    assertEquals(h.calls.length, 0, String(marker));
  }
});

Deno.test("resolve: no lookup without a sanitized key", async () => {
  const h = harness([row()], { clientKey: null });
  assertEquals((await h.run()).kind, "none");
  assertEquals(h.calls.length, 0);
});

Deno.test("resolve: the kill switch skips the lookup (the old path verbatim)", async () => {
  const h = harness([row()], { killSwitch: true });
  assertEquals((await h.run()).kind, "none");
  assertEquals(h.calls.length, 0);
});

Deno.test("resolve: a young pending row answers 503 in_progress with the exact body", async () => {
  const h = harness([row({ model_used: "pending", ai_response: "", created_at: ago(20_000) })]);
  const r = await h.run();
  assert(r.kind === "in_progress");
  assertEquals(r.status, 503);
  assertEquals(r.body, { error: "in_progress", deduplicated: true });
});

Deno.test("resolve: a failed lookup never blocks chat (none)", async () => {
  const h = harness(new Error("db down"));
  assertEquals((await h.run()).kind, "none");
});

Deno.test("resolve: nothing usable is none", async () => {
  assertEquals((await harness([]).run()).kind, "none");
  assertEquals((await harness([row({ model_used: SENTINEL, ai_response: "[failed] runToolLoop threw" })]).run()).kind, "none");
});
