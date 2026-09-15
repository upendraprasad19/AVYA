/**
 * Deno unit tests for `re-engagement`'s pure RPC-row mapper.
 *
 * Run:
 *   deno test --allow-env supabase/functions/re-engagement/index_test.ts
 *
 * Scope: pure-function tests of `mapFallbackCandidates`, following the
 * compute-admin-metrics-daily/index_test.ts convention — the serve handler
 * is NOT exercised here (needs live SUPABASE_URL + service-role env + the
 * deployed public.find_reengagement_silent_candidates() RPC). The RPC's own
 * anti-join correctness is verified live in
 * test/sql/reengagement_silent_candidates_verify.sql (OI-48, diagnose a4e1c9).
 */

import {
  assertEquals,
  assertStrictEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { mapFallbackCandidates } from "./index.ts";

Deno.test("mapFallbackCandidates projects RPC rows into parallel candidate list + name map", () => {
  const rows = [
    { user_id: "u1", full_name: "Alice" },
    { user_id: "u2", full_name: "Bob" },
  ];
  const { candidates, names } = mapFallbackCandidates(rows);
  assertEquals(candidates, ["u1", "u2"]);
  assertEquals(names.get("u1"), "Alice");
  assertEquals(names.get("u2"), "Bob");
});

Deno.test("mapFallbackCandidates defaults a null full_name to null, not undefined — Map.get on a missing key is also undefined, so the caller must be able to tell 'present but null' apart", () => {
  const rows = [{ user_id: "u1", full_name: null }];
  const { candidates, names } = mapFallbackCandidates(rows);
  assertEquals(candidates, ["u1"]);
  assertStrictEquals(names.get("u1"), null);
  assertStrictEquals(names.has("u1"), true);
});

Deno.test("mapFallbackCandidates on an empty RPC result returns an empty candidate list and an empty map — the zero-silent-users happy path", () => {
  const { candidates, names } = mapFallbackCandidates([]);
  assertEquals(candidates, []);
  assertEquals(names.size, 0);
});

Deno.test("mapFallbackCandidates preserves RPC row order — the RPC has no ORDER BY, but the map must not silently reorder what it's given", () => {
  const rows = [
    { user_id: "z", full_name: "Zoe" },
    { user_id: "a", full_name: "Amy" },
  ];
  const { candidates } = mapFallbackCandidates(rows);
  assertEquals(candidates, ["z", "a"]);
});

Deno.test("re-engagement's Path B source no longer issues a per-user query loop — the old .from('workout_logs')/.from('nutrition_logs')/.from('weight_logs') calls inside a for-loop are gone, replaced by one .rpc( call outside any loop", async () => {
  const src = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  const rpcIdx = src.indexOf("find_reengagement_silent_candidates");
  if (rpcIdx === -1) {
    throw new Error("expected a call to find_reengagement_silent_candidates");
  }
  // The three per-table calls that used to live inside the per-user loop
  // must not appear anywhere in the file any more — they were fully
  // replaced by the RPC, not merely supplemented.
  const perTableCalls = [
    '.from("workout_logs")',
    '.from("nutrition_logs")',
    '.from("weight_logs")',
  ];
  for (const call of perTableCalls) {
    if (src.includes(call)) {
      throw new Error(
        `expected ${call} to be gone (replaced by the RPC), but it is still present`,
      );
    }
  }
});

// ── Hermes L34 regression guards ────────────────────────────────────────
// This batch converted Path B's per-user "skip this user on read error"
// handling into ONE whole-invocation throw (a single SQL statement cannot
// partially fail per-row), which makes cron_call_log.error_summary the
// only durable record of a Path B failure. These pin the observability of
// that now-fatal leg. Source-shape assertions (PRESENCE class per
// CLAUDE.md rule 21) — the serve handler needs live env + a deployed RPC,
// so the runtime path is exercised by the live cron, not here.

Deno.test("cron telemetry does not record a bare String(err) — a supabase-js PostgrestError is a plain object, so String() yields '[object Object]' and the failure telemetry carries nothing (Hermes L34 F1; same bug-class fixed at compute-coach-signals:92-98)", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (/errorSummary:\s*String\(err\)/.test(src)) {
    throw new Error(
      "errorSummary uses a bare String(err) — must unwrap .message first, " +
        "else a PostgrestError serializes to '[object Object]'",
    );
  }
  if (!src.includes("{ message?: string } | null)?.message")) {
    throw new Error(
      "expected the .message-unwrapping guard on errorSummary",
    );
  }
});

Deno.test("Path A and Path B failures are distinguishable in cron_call_log — both throws carry a path tag, else one catch serializes them identically and a regression in either is invisible (Hermes L34 F2)", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  for (const tag of ["path_a coach_memory fetch failed", "path_b find_reengagement_silent_candidates rpc failed"]) {
    if (!src.includes(tag)) {
      throw new Error(`expected a tagged throw containing "${tag}"`);
    }
  }
  // The untagged bare re-throws must be gone, not merely supplemented.
  for (const bare of ["if (memError) throw memError;", "if (fallbackErr) throw fallbackErr;"]) {
    if (src.includes(bare)) {
      throw new Error(`expected "${bare}" to be replaced by a tagged throw`);
    }
  }
});

Deno.test("markProactiveSent is NOT wrapped in a local try and no mark-failure counter exists — the helper is non-throwing by contract, so a wrapper would be dead code emitting a permanently-0 metric that falsely asserts 'dedup bookkeeping never failed' (Hermes L34 F3, reverted after verifying the helper)", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const helper = await Deno.readTextFile(
    new URL("../_shared/proactive_dedup.ts", import.meta.url),
  );
  // Pin the PREMISE, not just the shape: if markProactiveSent ever grows a
  // throwing path, this test fails and the call site must be revisited.
  const body = helper.slice(helper.indexOf("export async function markProactiveSent"));
  const fnBody = body.slice(0, body.indexOf("\n}\n") + 3);
  if (!/try\s*\{[\s\S]*\}\s*catch\s*\(/.test(fnBody)) {
    throw new Error(
      "markProactiveSent no longer swallows its own errors — re-evaluate " +
        "whether re-engagement's bare call site needs a local guard",
    );
  }
  if (src.includes("markFailures")) {
    throw new Error(
      "markFailures counter is back — it can only ever be 0 while the " +
        "helper is non-throwing, which is worse than omitting it",
    );
  }
});

Deno.test("both success responses carry the same key set — the zero-candidate early return previously omitted prefs_off (Hermes L34 F4)", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  // Every key the main-path response emits must also appear in the
  // early-return object literal.
  const earlyReturnKeys = [
    "from_memory: 0",
    "from_fallback: 0",
    "sent: 0",
    "prefs_off: 0",
    "dedup_skipped: 0",
    "errors: 0",
  ];
  for (const key of earlyReturnKeys) {
    if (!src.includes(key)) {
      throw new Error(
        `zero-candidate early return is missing "${key}" — its shape must ` +
          "match the main-path response",
      );
    }
  }
});
