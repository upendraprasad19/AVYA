// OI-321 -- behavioural tests for the clean-orphan-media sweep core.
//
// The rule under test: an object is removed ONLY when the subscription read
// SUCCEEDED and found no active unexpired row. Everything else leaves it alone.
//
// The end-to-end tests drive `runSweep` with ONE fake client that serves both
// the `subscriptions` read (PostgREST semantics: `.maybeSingle()` over more than
// one row answers PGRST116 with a null `data`) and Storage `remove`, so a wiring
// mistake (a constant "free" dependency, a swapped argument, the wrong bucket)
// changes the answer.
//
// Run: deno test --no-check --allow-all --node-modules-dir=none supabase/functions/clean-orphan-media/

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { ProState } from "../_shared/subscription.ts";
import {
  isSystematicFailure,
  removeFromBucket,
  runErrorSummary,
  runSweep,
  SYSTEMIC_MIN_UNDECIDED,
  sweepOrphans,
  type OrphanCandidate,
  type RemoveOutcome,
  type StorageLike,
  type SweepDeps,
  type SweepResult,
} from "./logic.ts";

const A = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const B = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const C = "cccccccc-cccc-cccc-cccc-cccccccccccc";
const cand = (user_id: string, name = "p.jpg"): OrphanCandidate => ({ user_id, path: `${user_id}/${name}` });

/** Silences console output while a test provokes failure legs. */
async function quiet<T>(fn: () => Promise<T>): Promise<T> {
  const e = console.error;
  console.error = () => {};
  try {
    return await fn();
  } finally {
    console.error = e;
  }
}

// ── removeFromBucket ────────────────────────────────────────────────────────

function fakeStorage(
  script: (bucket: string, paths: string[]) => { data: unknown; error: unknown } | "throw",
  calls: Array<{ bucket: string; paths: string[] }> = [],
): StorageLike {
  return {
    from(bucket: string) {
      return {
        remove(paths: string[]) {
          calls.push({ bucket, paths });
          const r = script(bucket, paths);
          if (r === "throw") return Promise.reject(new Error("transport reset"));
          return Promise.resolve(r);
        },
      };
    },
  };
}

Deno.test("removeFromBucket: passes the bucket and the single path through, reports the removed count", async () => {
  const calls: Array<{ bucket: string; paths: string[] }> = [];
  const out = await removeFromBucket(
    fakeStorage((_b, p) => ({ data: p.map((name) => ({ name })), error: null }), calls),
    "chat-media",
    `${A}/x.jpg`,
  );
  assertEquals(out, { error: null, removed: 1 });
  assertEquals(calls, [{ bucket: "chat-media", paths: [`${A}/x.jpg`] }]);
});

Deno.test("removeFromBucket: an error is RETURNED (never swallowed into success)", async () => {
  const err = { message: "denied", statusCode: "403" };
  const out = await removeFromBucket(fakeStorage(() => ({ data: null, error: err })), "chat-media", `${A}/x.jpg`);
  assertEquals(out.error, err);
  assertEquals(out.removed, null);
});

Deno.test("removeFromBucket: a THROWN storage call becomes { error } instead of escaping", async () => {
  const out = await removeFromBucket(fakeStorage(() => "throw"), "chat-media", `${A}/x.jpg`);
  assertEquals(out.error instanceof Error, true);
  assertEquals(out.removed, null);
});

Deno.test("removeFromBucket: empty data = removed 0 (already gone); non-array data = removed null (not said)", async () => {
  assertEquals((await removeFromBucket(fakeStorage(() => ({ data: [], error: null })), "chat-media", "p")).removed, 0);
  assertEquals((await removeFromBucket(fakeStorage(() => ({ data: null, error: null })), "chat-media", "p")).removed, null);
});

// ── sweepOrphans: the decision ──────────────────────────────────────────────

function deps(
  states: Record<string, ProState | "throw" | "weird">,
  removeResult: (path: string) => RemoveOutcome | "throw" = () => ({ error: null, removed: 1 }),
) {
  const reads: string[] = [];
  const removed: string[] = [];
  const d: SweepDeps = {
    readProState: (userId) => {
      reads.push(userId);
      const s = states[userId];
      if (s === "throw") return Promise.reject(new Error("boom"));
      return Promise.resolve((s ?? "unknown") as ProState);
    },
    removeObject: (path) => {
      removed.push(path);
      const r = removeResult(path);
      if (r === "throw") return Promise.reject(new Error("remove threw"));
      return Promise.resolve(r);
    },
  };
  return { d, reads, removed };
}

Deno.test("sweepOrphans: free is removed and counted; pro is NOT removed", async () => {
  const { d, removed } = deps({ [A]: "free", [B]: "pro" });
  const r = await sweepOrphans([cand(A), cand(B)], d);
  assertEquals(removed, [`${A}/p.jpg`]);
  assertEquals(
    { scanned: r.scanned, deleted: r.deleted, skippedPro: r.skippedPro, skippedUnknown: r.skippedUnknown, failed: r.failed },
    { scanned: 2, deleted: 1, skippedPro: 1, skippedUnknown: 0, failed: 0 },
  );
});

Deno.test("sweepOrphans: unknown is NOT removed, is counted, and does not stop the next candidate", async () => {
  const { d, removed } = deps({ [A]: "unknown", [B]: "free" });
  const r = await sweepOrphans([cand(A), cand(B)], d);
  assertEquals(removed, [`${B}/p.jpg`], "A's object survives; B's is still removed");
  assertEquals(r.skippedUnknown, 1);
  assertEquals(r.deleted, 1);
  assertEquals(r.firstFailure, "read_unknown");
});

Deno.test("sweepOrphans: a state outside the union leaves the object alone (only exactly 'free' removes)", async () => {
  const { d, removed } = deps({ [A]: "weird" });
  const r = await sweepOrphans([cand(A)], d);
  assertEquals(removed, []);
  assertEquals(r.skippedUnknown, 1);
});

Deno.test("sweepOrphans: a throwing readProState dependency reads as unknown, not free", async () => {
  const { d, removed } = deps({ [A]: "throw", [B]: "free" });
  const r = await sweepOrphans([cand(A), cand(B)], d);
  assertEquals(removed, [`${B}/p.jpg`]);
  assertEquals(r.skippedUnknown, 1);
});

Deno.test("sweepOrphans: a removal ERROR is failed, never deleted, and the run continues", async () => {
  const { d, removed } = deps({ [A]: "free", [B]: "free" }, (p) =>
    p.startsWith(A) ? { error: { code: "PGRST301" }, removed: null } : { error: null, removed: 1 });
  const r = await sweepOrphans([cand(A), cand(B)], d);
  assertEquals(removed, [`${A}/p.jpg`, `${B}/p.jpg`]);
  assertEquals({ deleted: r.deleted, failed: r.failed, firstFailure: r.firstFailure }, { deleted: 1, failed: 1, firstFailure: "PGRST301" });
});

Deno.test("sweepOrphans: a THROWING removeObject dependency is failed and does not abort the run", async () => {
  const { d } = deps({ [A]: "free", [B]: "free" }, (p) => (p.startsWith(A) ? "throw" : { error: null, removed: 1 }));
  const r = await sweepOrphans([cand(A), cand(B)], d);
  assertEquals({ deleted: r.deleted, failed: r.failed }, { deleted: 1, failed: 1 });
});

Deno.test("sweepOrphans: removed 0 is alreadyGone (not deleted); removed null (not said) still counts as deleted", async () => {
  const { d } = deps({ [A]: "free", [B]: "free" }, (p) =>
    p.startsWith(A) ? { error: null, removed: 0 } : { error: null, removed: null });
  const r = await sweepOrphans([cand(A), cand(B)], d);
  assertEquals({ deleted: r.deleted, alreadyGone: r.alreadyGone }, { deleted: 1, alreadyGone: 1 });
});

Deno.test("sweepOrphans: the PRO state is read once per candidate at delete time (no per-run cache)", async () => {
  // Two objects of one user; the user upgrades between the two reads.
  const sequence: ProState[] = ["free", "pro"];
  const removed: string[] = [];
  const d: SweepDeps = {
    readProState: () => Promise.resolve(sequence.shift() ?? "unknown"),
    removeObject: (p) => {
      removed.push(p);
      return Promise.resolve({ error: null, removed: 1 });
    },
  };
  const r = await sweepOrphans([cand(A, "one.jpg"), cand(A, "two.jpg")], d);
  assertEquals(removed, [`${A}/one.jpg`], "the second object is kept because the user is PRO by then");
  assertEquals({ deleted: r.deleted, skippedPro: r.skippedPro }, { deleted: 1, skippedPro: 1 });
});

Deno.test("sweepOrphans: a malformed candidate, or a path that is not under its user id, is skipped as unknown", async () => {
  const { d, reads, removed } = deps({ [A]: "free", [B]: "free" });
  const r = await sweepOrphans(
    [
      { user_id: A, path: `${B}/p.jpg` }, // path belongs to someone else
      { user_id: "", path: "/p.jpg" },
      { user_id: A, path: "" },
      { user_id: A, path: A }, // no folder separator
      { user_id: undefined as unknown as string, path: `${A}/p.jpg` },
      null as unknown as OrphanCandidate,
    ],
    d,
  );
  assertEquals(removed, []);
  assertEquals(reads, [], "an invalid candidate is not even looked up");
  assertEquals({ scanned: r.scanned, skippedUnknown: r.skippedUnknown, firstFailure: r.firstFailure }, { scanned: 6, skippedUnknown: 6, firstFailure: "invalid_candidate" });
});

Deno.test("sweepOrphans: empty list, order preserved, firstFailure is only the FIRST code", async () => {
  const empty = await sweepOrphans([], deps({}).d);
  assertEquals(empty, { scanned: 0, deleted: 0, skippedPro: 0, skippedUnknown: 0, failed: 0, alreadyGone: 0, firstFailure: null });

  const { d, reads } = deps({ [A]: "unknown", [B]: "free", [C]: "free" }, (p) =>
    p.startsWith(B) ? { error: { code: "SECOND" }, removed: null } : { error: null, removed: 1 });
  const r = await sweepOrphans([cand(A), cand(B), cand(C)], d);
  assertEquals(reads, [A, B, C]);
  assertEquals(r.firstFailure, "read_unknown", "the earlier failure wins");
  assertEquals({ skippedUnknown: r.skippedUnknown, failed: r.failed, deleted: r.deleted }, { skippedUnknown: 1, failed: 1, deleted: 1 });
});

Deno.test("sweepOrphans: a failure code that is not a plain identifier never reaches the result", async () => {
  const { d } = deps({ [A]: "free" }, () => ({ error: { code: A /* a uuid */, message: `object ${A}/p.jpg` }, removed: null }));
  const r = await sweepOrphans([cand(A)], d);
  assertEquals(r.firstFailure, "remove_error");
});

// ── runSweep: the production composition, one fake client end to end ────────

interface SubRow {
  user_id: string;
  status: string;
  end_date: string;
}

function fakeClient(
  rows: SubRow[],
  opts: {
    subsFail?: "error" | "throw";
    remove?: (bucket: string, paths: string[]) => { data: unknown; error: unknown };
    onSubsRead?: (userId: string) => void;
  } = {},
) {
  const removeCalls: Array<{ bucket: string; paths: string[] }> = [];
  const client = {
    from(table: string) {
      if (table !== "subscriptions") throw new Error(`unexpected table ${table}`);
      const filters: Array<[string, string, unknown]> = [];
      let limitN: number | null = null;
      const evaluate = () => {
        const m = rows.filter((r) =>
          filters.every(([col, op, v]) => {
            const cell = (r as unknown as Record<string, unknown>)[col];
            if (op === "eq") return cell === v;
            if (op === "gte") return Date.parse(String(cell)) >= Date.parse(String(v));
            return Date.parse(String(cell)) > Date.parse(String(v));
          })
        );
        return limitN === null ? m : m.slice(0, limitN);
      };
      const builder = {
        select() {
          return builder;
        },
        eq(col: string, v: unknown) {
          filters.push([col, "eq", v]);
          if (col === "user_id") opts.onSubsRead?.(String(v));
          return builder;
        },
        gt(col: string, v: unknown) {
          filters.push([col, "gt", v]);
          return builder;
        },
        gte(col: string, v: unknown) {
          filters.push([col, "gte", v]);
          return builder;
        },
        limit(n: number) {
          limitN = n;
          return builder;
        },
        maybeSingle() {
          const m = evaluate();
          if (m.length > 1) {
            return Promise.resolve({ data: null, error: { code: "PGRST116", message: "multiple rows" } });
          }
          return Promise.resolve({ data: m[0] ?? null, error: null });
        },
        then(res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) {
          if (opts.subsFail === "throw") return Promise.reject(new Error("transport reset")).then(res, rej);
          if (opts.subsFail === "error") return Promise.resolve({ data: null, error: { code: "57014", message: "boom" } }).then(res, rej);
          return Promise.resolve({ data: evaluate().map((r) => ({ user_id: r.user_id })), error: null }).then(res, rej);
        },
      };
      return builder;
    },
    storage: fakeStorage(
      (bucket, paths) => (opts.remove ? opts.remove(bucket, paths) : { data: paths.map((name) => ({ name })), error: null }),
      removeCalls,
    ),
  };
  return { client, removeCalls };
}

const FUTURE = "2099-01-01T00:00:00.000Z";
const active = (user_id: string, end_date = FUTURE): SubRow => ({ user_id, status: "active", end_date });

Deno.test("runSweep: the OI-321 user (two unexpired active rows) is PRO -- remove is NEVER called", async () => {
  const { client, removeCalls } = fakeClient([active(A, FUTURE), active(A, "2099-06-01T00:00:00.000Z")]);
  const r = await runSweep(client, [cand(A)]);
  assertEquals(removeCalls, []);
  assertEquals({ skippedPro: r.skippedPro, deleted: r.deleted, skippedUnknown: r.skippedUnknown }, { skippedPro: 1, deleted: 0, skippedUnknown: 0 });
});

Deno.test("runSweep: an unreadable subscription (error OR throw) is never a delete", async () => {
  for (const subsFail of ["error", "throw"] as const) {
    const { client, removeCalls } = fakeClient([], { subsFail });
    const r = await quiet(() => runSweep(client, [cand(A)]));
    assertEquals(removeCalls, [], subsFail);
    assertEquals({ skippedUnknown: r.skippedUnknown, deleted: r.deleted }, { skippedUnknown: 1, deleted: 0 }, subsFail);
  }
});

Deno.test("runSweep: a free user's object is removed from the chat-media bucket, once, by its path", async () => {
  const { client, removeCalls } = fakeClient([active(B)]); // A has no subscription at all
  const r = await runSweep(client, [cand(A, "old.jpg")]);
  assertEquals(removeCalls, [{ bucket: "chat-media", paths: [`${A}/old.jpg`] }]);
  assertEquals({ deleted: r.deleted, failed: r.failed }, { deleted: 1, failed: 0 });
});

Deno.test("runSweep: a lapsed subscription (status active, end_date past) is free; a user who upgrades mid-run is kept", async () => {
  const rows: SubRow[] = [active(A, "2000-01-01T00:00:00.000Z")];
  const { client, removeCalls } = fakeClient(rows, {
    // B upgrades the moment A's object has been looked up (before B's recheck).
    onSubsRead: (uid) => {
      if (uid === A && rows.length === 1) rows.push(active(B));
    },
  });
  const r = await runSweep(client, [cand(A), cand(B)]);
  assertEquals(removeCalls.map((c) => c.paths[0]), [`${A}/p.jpg`], "B is PRO at recheck time, so only A is removed");
  assertEquals({ deleted: r.deleted, skippedPro: r.skippedPro }, { deleted: 1, skippedPro: 1 });
});

Deno.test("runSweep: a Storage error is failed and surfaces in the summary", async () => {
  const { client } = fakeClient([], { remove: () => ({ data: null, error: { code: "PGRST301", message: "nope" } }) });
  const r = await runSweep(client, [cand(A)]);
  assertEquals({ deleted: r.deleted, failed: r.failed }, { deleted: 0, failed: 1 });
  assertEquals(runErrorSummary(r), "skipped_unknown=0 failed=1 first=PGRST301");
});

// ── runErrorSummary ─────────────────────────────────────────────────────────

Deno.test("runErrorSummary: undefined on a clean run (including skipped_pro only, and removals that coexist with already-gone ones)", () => {
  assertEquals(runErrorSummary({ scanned: 0, deleted: 0, skippedPro: 0, skippedUnknown: 0, failed: 0, alreadyGone: 0, firstFailure: null }), undefined);
  assertEquals(runErrorSummary({ scanned: 5, deleted: 2, skippedPro: 2, skippedUnknown: 0, failed: 0, alreadyGone: 1, firstFailure: null }), undefined);
});

Deno.test("runErrorSummary: counts unknown and failed separately, plus the first code", () => {
  const base = { scanned: 9, deleted: 0, skippedPro: 0, alreadyGone: 0 };
  assertEquals(runErrorSummary({ ...base, skippedUnknown: 3, failed: 0, firstFailure: "read_unknown" }), "skipped_unknown=3 failed=0 first=read_unknown");
  assertEquals(runErrorSummary({ ...base, skippedUnknown: 0, failed: 2, firstFailure: "remove_error" }), "skipped_unknown=0 failed=2 first=remove_error");
  assertEquals(runErrorSummary({ ...base, skippedUnknown: 1, failed: 1, firstFailure: "read_unknown" }), "skipped_unknown=1 failed=1 first=read_unknown");
});

Deno.test("runErrorSummary: carries no user id or path, even when the failing object belongs to a user", async () => {
  const { d } = deps({ [A]: "free" }, () => ({ error: { code: A, message: `${A}/p.jpg` }, removed: null }));
  const r = await sweepOrphans([cand(A)], d);
  const summary = runErrorSummary(r) ?? "";
  assertEquals(summary.includes(A), false);
  assertEquals(summary.includes("p.jpg"), false);
  assertEquals(summary, "skipped_unknown=0 failed=1 first=remove_error");
});


// ── failure codes: the shape storage-js really produces ─────────────────────
//
// storage-js 2.5.x / 2.7.x (the versions supabase-js 2.39.3 resolves to) throw a
// `StorageApiError { message, status: number }`: NO `code`. A PostgREST failure
// carries `code`. A fixture shaped only like the latter would let a Storage failure
// collapse to `remove_error` in production without any test noticing.

Deno.test("firstFailure: a Storage-shaped error (numeric status, no code) yields the status; a PostgREST code still works", async () => {
  const storageShaped = { message: "The resource was not found", status: 404 };
  const { d } = deps({ [A]: "free" }, () => ({ error: storageShaped, removed: null }));
  assertEquals((await sweepOrphans([cand(A)], d)).firstFailure, "404");

  const withStatusCode = { message: "denied", statusCode: "403" };
  const { d: d2 } = deps({ [A]: "free" }, () => ({ error: withStatusCode, removed: null }));
  assertEquals((await sweepOrphans([cand(A)], d2)).firstFailure, "403");

  const postgrest = { message: "x", code: "PGRST301" };
  const { d: d3 } = deps({ [A]: "free" }, () => ({ error: postgrest, removed: null }));
  assertEquals((await sweepOrphans([cand(A)], d3)).firstFailure, "PGRST301");
});

Deno.test("firstFailure: a status that is not a plain identifier (too long, punctuation) falls back, never leaks", async () => {
  for (const bad of [{ status: "x".repeat(40) }, { status: `${A}` }, { statusCode: "a/b" }, { status: undefined }, {}]) {
    const { d } = deps({ [A]: "free" }, () => ({ error: bad, removed: null }));
    assertEquals((await sweepOrphans([cand(A)], d)).firstFailure, "remove_error", JSON.stringify(bad));
  }
});

Deno.test("runSweep: a real-shaped Storage failure surfaces its status in the summary", async () => {
  const { client } = fakeClient([], { remove: () => ({ data: null, error: { message: "denied", status: 403 } }) });
  const r = await runSweep(client, [cand(A)]);
  assertEquals(runErrorSummary(r), "skipped_unknown=0 failed=1 first=403");
});

// ── runErrorSummary: a run that removed nothing because everything was already gone ──

Deno.test("runErrorSummary: a run whose every removal found the object already gone reports already_gone", () => {
  const r: SweepResult = { scanned: 3, deleted: 0, skippedPro: 0, skippedUnknown: 0, failed: 0, alreadyGone: 3, firstFailure: null };
  assertEquals(runErrorSummary(r), "skipped_unknown=0 failed=0 first=none already_gone=3");
});

Deno.test("runErrorSummary: already_gone alongside real removals is NOT noise on the cron row", () => {
  const r: SweepResult = { scanned: 4, deleted: 1, skippedPro: 0, skippedUnknown: 0, failed: 0, alreadyGone: 3, firstFailure: null };
  assertEquals(runErrorSummary(r), undefined);
});

Deno.test("runErrorSummary: already_gone is appended to a failure summary only when nothing was removed", () => {
  const none: SweepResult = { scanned: 3, deleted: 0, skippedPro: 0, skippedUnknown: 1, failed: 0, alreadyGone: 2, firstFailure: "read_unknown" };
  assertEquals(runErrorSummary(none), "skipped_unknown=1 failed=0 first=read_unknown already_gone=2");
  const some: SweepResult = { ...none, deleted: 1 };
  assertEquals(runErrorSummary(some), "skipped_unknown=1 failed=0 first=read_unknown");
});

// ── isSystematicFailure: the only thing that turns a sweep into a `failed` cron row ──
//
// `failed` creates a critical alert within the hour (alert_cron_failures). It must fire
// when the sweep could not do its job (most candidates undecided, at least five) and must
// NOT fire for one blip or one permanently stuck object.

const result = (over: Partial<SweepResult>): SweepResult => ({
  scanned: 0, deleted: 0, skippedPro: 0, skippedUnknown: 0, failed: 0, alreadyGone: 0, firstFailure: null, ...over,
});

Deno.test("isSystematicFailure: the minimum is five undecided candidates", () => {
  assertEquals(SYSTEMIC_MIN_UNDECIDED, 5);
  assertEquals(isSystematicFailure(result({ scanned: 4, skippedUnknown: 4 })), false, "4 of 4: below the minimum");
  assertEquals(isSystematicFailure(result({ scanned: 5, skippedUnknown: 5 })), true, "5 of 5");
});

Deno.test("isSystematicFailure: a MAJORITY is required (exactly half is not)", () => {
  assertEquals(isSystematicFailure(result({ scanned: 10, skippedUnknown: 5 })), false, "5 of 10 is half");
  assertEquals(isSystematicFailure(result({ scanned: 10, skippedUnknown: 6 })), true, "6 of 10");
  assertEquals(isSystematicFailure(result({ scanned: 9, skippedUnknown: 5 })), true, "5 of 9");
  assertEquals(isSystematicFailure(result({ scanned: 100, skippedUnknown: 5 })), false, "5 of 100 is a blip");
});

Deno.test("isSystematicFailure: failed removals count with unreadable ones", () => {
  assertEquals(isSystematicFailure(result({ scanned: 6, skippedUnknown: 3, failed: 3 })), true, "3 + 3 of 6");
  assertEquals(isSystematicFailure(result({ scanned: 6, failed: 6 })), true, "all removals failed");
  assertEquals(isSystematicFailure(result({ scanned: 6, skippedUnknown: 6 })), true);
  assertEquals(isSystematicFailure(result({ scanned: 12, skippedUnknown: 3, failed: 3 })), false, "6 of 12 is half");
});

Deno.test("isSystematicFailure: nothing to do, all PRO, a few deletions, one stuck object are all fine", () => {
  assertEquals(isSystematicFailure(result({})), false, "scanned 0: 0 >= 5 is false");
  assertEquals(isSystematicFailure(result({ scanned: 50, skippedPro: 50 })), false);
  assertEquals(isSystematicFailure(result({ scanned: 20, deleted: 19, failed: 1 })), false, "one stuck object");
  assertEquals(isSystematicFailure(result({ scanned: 1, skippedUnknown: 1 })), false, "one blip, one candidate");
});

Deno.test("runSweep end to end: an unreadable subscriptions table across five candidates is a systemic failure and removes nothing", async () => {
  const { client, removeCalls } = fakeClient([], { subsFail: "error" });
  const users = [A, B, C, "dddddddd-dddd-dddd-dddd-dddddddddddd", "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"];
  const r = await quiet(() => runSweep(client, users.map((u) => cand(u))));
  assertEquals(removeCalls, []);
  assertEquals(r.skippedUnknown, 5);
  assertEquals(isSystematicFailure(r), true);
});

Deno.test("runSweep end to end: a healthy table with twelve candidates, a few unreadable, is NOT systemic", async () => {
  const users = Array.from({ length: 12 }, (_, i) => `${String(i).padStart(8, "0")}-0000-0000-0000-000000000000`);
  const flaky = new Set(users.slice(0, 3));
  const rows: SubRow[] = [];
  let attempts = 0;
  const { client } = fakeClient(rows, { onSubsRead: () => void attempts++ });
  // make the first three users' reads fail by wrapping `from`
  const realFrom = client.from.bind(client);
  // deno-lint-ignore no-explicit-any
  (client as any).from = (table: string) => {
    const b = realFrom(table);
    const origEq = b.eq.bind(b);
    let isFlaky = false;
    b.eq = (col: string, v: unknown) => {
      if (col === "user_id" && flaky.has(String(v))) isFlaky = true;
      return origEq(col, v);
    };
    const origThen = b.then.bind(b);
    b.then = (res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) =>
      isFlaky ? Promise.resolve({ data: null, error: { code: "57014", message: "boom" } }).then(res, rej) : origThen(res, rej);
    return b;
  };
  const r = await quiet(() => runSweep(client, users.map((u) => cand(u))));
  assertEquals({ scanned: r.scanned, skippedUnknown: r.skippedUnknown, deleted: r.deleted }, { scanned: 12, skippedUnknown: 3, deleted: 9 });
  assertEquals(isSystematicFailure(r), false);
  assertEquals(attempts >= 12, true);
});
