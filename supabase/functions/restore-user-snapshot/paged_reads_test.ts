// Behavioural tests for restore-user-snapshot/paged_reads.ts.
//
// These are not shape assertions. The fake database below reproduces the PostgREST behaviour that
// made the old reads lossy (see `_shared/paged_fetch.ts`): a response is clamped to `db-max-rows`
// (1000) with HTTP 200 and `error === null`, so a truncated read is indistinguishable from a small
// one. It is also ADVERSARIAL on ties: when the requested order does not END in the unique `id`,
// rows that tie are returned in a different order on every request, so a missing tiebreak
// duplicates and skips rows exactly the way a real database may. And it holds a SECOND user's rows,
// so a read that drops its `user_id` scope returns them and the test fails.
//
// Run: deno test --no-check --allow-all --node-modules-dir=none supabase/functions/restore-user-snapshot/

import {
  assert,
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { istDateStr } from "../_shared/ist_date.ts";
import {
  COACH_LIMIT,
  COACH_TABLE,
  createPageBudget,
  MAX_PAGES,
  PAGED_READ_NAMES,
  PAGED_READS,
  type PageBudget,
  readCoachNewest,
  readPaged,
  rowCountLogLine,
  scopeEmbed,
  SINCE,
  SINCE_DATE,
  TOTAL_PAGE_BUDGET,
  UUID_RE,
} from "./paged_reads.ts";

type Row = Record<string, unknown>;

interface Call {
  table: string;
  select: string;
  filters: { op: "eq" | "gte"; column: string; value: unknown }[];
  orders: { column: string; ascending: boolean | undefined }[];
  range?: [number, number];
  limit?: number;
}

// readPaged REQUIRES a per-request budget; every behavioural case below gets a fresh one.
// deno-lint-ignore no-explicit-any
const read = (db: any, uid: string, name: string, budget: PageBudget = createPageBudget()) =>
  readPaged(db, uid, name, budget);

const ME = "11111111-1111-4111-8111-111111111111";
const OTHER = "22222222-2222-4222-8222-222222222222";
// uuids that contain hex LETTERS (ME / OTHER are all digits, so toUpperCase() would be a no-op on them)
const HEX = "abcdef01-2345-4678-89ab-cdef01234567";
const HEX_OTHER = "fedcba98-7654-4321-8fed-cba987654321";

const uuid = (n: number, tag = 1) =>
  `${String(tag).padStart(8, "0")}-0000-4000-8000-${String(n).padStart(12, "0")}`;

function shuffled<T>(rows: T[], seed: number): T[] {
  const out = [...rows];
  let s = (seed * 2654435761) >>> 0;
  for (let i = out.length - 1; i > 0; i--) {
    s = (s * 1664525 + 1013904223) >>> 0;
    const j = s % (i + 1);
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

function makeDb(
  data: Record<string, Row[]>,
  o: { serverCap?: number; failOnRequest?: number } = {},
) {
  const calls: Call[] = [];
  let requestNo = 0;
  const cap = o.serverCap ?? 1000;
  return {
    calls,
    from(table: string) {
      const call: Call = { table, select: "", filters: [], orders: [] };
      // deno-lint-ignore no-explicit-any
      const b: any = {
        select(s: string) {
          call.select = s;
          return b;
        },
        eq(column: string, value: unknown) {
          call.filters.push({ op: "eq", column, value });
          return b;
        },
        gte(column: string, value: unknown) {
          call.filters.push({ op: "gte", column, value });
          return b;
        },
        order(column: string, opts?: { ascending?: boolean }) {
          call.orders.push({ column, ascending: opts?.ascending });
          return b;
        },
        range(from: number, to: number) {
          call.range = [from, to];
          return run();
        },
        limit(n: number) {
          call.limit = n;
          return run();
        },
      };
      function run() {
        requestNo++;
        calls.push({ ...call, filters: [...call.filters], orders: [...call.orders] });
        if (o.failOnRequest === requestNo) {
          return Promise.resolve({ data: null, error: { message: "boom" } });
        }
        let rows = (data[table] ?? []).filter((r) =>
          call.filters.every((f) =>
            f.op === "eq"
              ? r[f.column] === f.value
              : String(r[f.column]) >= String(f.value)
          )
        );
        // Ties reshuffle per request UNLESS the order ends in the unique `id`.
        const last = call.orders[call.orders.length - 1]?.column;
        if (last !== "id") rows = shuffled(rows, requestNo);
        rows = rows.sort((a, b) => {
          for (const t of call.orders) {
            const x = a[t.column] as string | number;
            const y = b[t.column] as string | number;
            if (x === y) continue;
            const c = x < y ? -1 : 1;
            return t.ascending === false ? -c : c;
          }
          return 0;
        });
        let out = rows;
        if (call.range) out = rows.slice(call.range[0], call.range[1] + 1);
        else if (call.limit !== undefined) out = rows.slice(0, call.limit);
        out = out.slice(0, cap); // db-max-rows: clamped, error === null
        return Promise.resolve({
          data: out.map((r) => structuredClone(r)),
          error: null,
        });
      }
      return b;
    },
  };
}

const BASE = Date.UTC(2024, 0, 1);
const iso = (k: number) => new Date(BASE + k * 1000).toISOString();
const day = (k: number) => istDateStr(new Date(BASE + Math.floor(k / 3) * 86400000));

// The tied window starts at row 600 so it STRADDLES the first page boundary (sorted positions
// 600..1299 span the cut at 1000): a missing tiebreak then shows up as duplicated/skipped rows.
const TIE_START = 600;
const inTie = (i: number, shared: number) => i >= TIE_START && i < TIE_START + shared;

/** Dataset A: `shared` rows (from TIE_START) tie on EVERY time column (the primary sort key). */
function datasetA(owner: string, n: number, shared: number, tag: number): Row[] {
  return Array.from({ length: n }, (_, i) => {
    const k = inTie(i, shared) ? TIE_START : i;
    return {
      id: uuid(i, tag),
      user_id: owner,
      created_at: iso(k),
      completed_at: iso(k),
      scheduled_date: day(k),
      date: day(k),
    };
  });
}

/**
 * Dataset B: `shared` rows (from TIE_START) tie on completed_at / scheduled_date / date, but their
 * created_at is DISTINCT and runs OPPOSITE to id order — so only an order that includes
 * `created_at` before `id` returns the insertion-order proxy the manifest promises.
 */
function datasetB(owner: string, n: number, shared: number, tag: number): Row[] {
  return Array.from({ length: n }, (_, i) => {
    const k = inTie(i, shared) ? TIE_START : i;
    return {
      id: uuid(i, tag),
      user_id: owner,
      created_at: iso(n - 1 - i),
      completed_at: iso(k),
      scheduled_date: day(k),
      date: day(k),
    };
  });
}

/**
 * Dataset C: every id runs OPPOSITE to every time column (id index = n-1-i), so a READER that stopped
 * applying the manifest order and sorted by `id` alone would return the rows backwards (the date-primary
 * tables otherwise have dates that rise with id and cannot tell `[date, id]` from `[id]`). NOTE: the
 * sorted-ness check compares against the manifest the code itself used, so a MANIFEST that lost its
 * primary term is caught by the old-chains oracle test (section 7), not by this dataset.
 */
function datasetC(owner: string, n: number, shared: number, tag: number): Row[] {
  return Array.from({ length: n }, (_, i) => {
    const k = inTie(i, shared) ? TIE_START : i;
    return {
      id: uuid(n - 1 - i, tag),
      user_id: owner,
      created_at: iso(k),
      completed_at: iso(k),
      scheduled_date: day(k),
      date: day(k),
    };
  });
}

/** A row older than the restore window on EVERY time column: a read with a `gte` must drop it. */
function ancientRow(owner: string): Row {
  return {
    id: uuid(999999, 7),
    user_id: owner,
    created_at: "2019-06-01T00:00:00.000Z",
    completed_at: "2019-06-01T00:00:00.000Z",
    scheduled_date: "2019-06-01",
    date: "2019-06-01",
  };
}

function compareBy(order: { column: string; ascending?: boolean }[]) {
  return (a: Row, b: Row) => {
    for (const t of order) {
      const x = a[t.column] as string | number;
      const y = b[t.column] as string | number;
      if (x === y) continue;
      const c = x < y ? -1 : 1;
      return t.ascending === false ? -c : c;
    }
    return 0;
  };
}

function assertSortedAndUnique(rows: Row[], name: string) {
  const cmp = compareBy(PAGED_READS[name].order);
  for (let i = 1; i < rows.length; i++) {
    assert(
      cmp(rows[i - 1], rows[i]) <= 0,
      `${name}: rows ${i - 1},${i} out of manifest order`,
    );
  }
  assertEquals(new Set(rows.map((r) => r.id)).size, rows.length, `${name}: duplicate rows`);
}

function assertAllScoped(calls: Call[], uid: string) {
  assert(calls.length > 0, "no query was issued");
  for (const c of calls) {
    assertEquals(
      c.filters[0],
      { op: "eq", column: "user_id", value: uid },
      `${c.table}: the user_id scope must be the FIRST filter of every request`,
    );
    for (const f of c.filters) {
      if (f.op === "eq" && f.column === "user_id") assertEquals(f.value, uid);
    }
    for (const t of c.orders) {
      assert(typeof t.ascending === "boolean", `${c.table}: order('${t.column}') has no explicit direction`);
    }
  }
}

// ── 1. every row comes back, once, in manifest order, scoped to the caller ──────────────────────

for (const name of PAGED_READ_NAMES) {
  for (const [label, make] of [["A", datasetA], ["B", datasetB], ["C", datasetC]] as const) {
    Deno.test(`${name}: 2,500 rows with 700 tied on the sort key come back exactly (dataset ${label})`, async () => {
      const spec = PAGED_READS[name];
      const mine = make(ME, 2500, 700, 1);
      const theirs = make(OTHER, 300, 100, 2);
      const ancient = ancientRow(ME);
      const db = makeDb({ [name]: [...mine, ...theirs, ...(spec.gte ? [ancient] : [])] });
      const rows = (await read(db, ME, name)) as Row[];
      assertEquals(rows.length, 2500);
      assert(!rows.some((r) => r.id === ancient.id), `${name}: a row older than the window came back`);
      // WHAT WAS SENT is what the manifest says: the exact select string and exactly the window filter
      for (const c of db.calls) {
        assertEquals(c.select, spec.select, `${name}: select string differs from the manifest`);
        assertEquals(
          c.filters.slice(1),
          spec.gte ? [{ op: "gte", column: spec.gte.column, value: spec.gte.value }] : [],
          `${name}: filters after the user scope differ from the manifest`,
        );
      }
      assertEquals(new Set(rows.map((r) => r.id)), new Set(mine.map((r) => r.id)));
      assert(rows.every((r) => r.user_id === ME), `${name}: a row of another user came back`);
      assertSortedAndUnique(rows, name);
      assertAllScoped(db.calls, ME);
      // pages advance by rows received: 0-999, 1000-1999, 2000-2999, then the confirming 2500-3499
      assertEquals(db.calls.map((c) => c.range), [[0, 999], [1000, 1999], [2000, 2999], [2500, 3499]]);
    });
  }

  Deno.test(`${name}: exact multiple of 1000, empty table, and a failing page`, async () => {
    const two = makeDb({ [name]: datasetA(ME, 2000, 0, 1) });
    assertEquals(((await read(two, ME, name)) as Row[]).length, 2000);

    const none = makeDb({ [name]: [] });
    assertEquals(await read(none, ME, name), []);

    const bad = makeDb({ [name]: datasetA(ME, 2500, 0, 1) }, { failOnRequest: 2 });
    await assertRejects(() => read(bad, ME, name), Error, "failed");
  });

  Deno.test(`${name}: another user's rows are never returned, on any page`, async () => {
    const db = makeDb({
      [name]: [...datasetA(OTHER, 1500, 0, 2), ...datasetA(ME, 40, 0, 1)],
    });
    const rows = (await read(db, ME, name)) as Row[];
    assertEquals(rows.length, 40);
    assert(rows.every((r) => r.user_id === ME));
    assertAllScoped(db.calls, ME);
  });
}

// The two workout tables promise an insertion-order proxy among rows that tie on completed_at:
// created_at BEFORE the random id. Dataset B makes created_at run OPPOSITE to id order, so only a
// created_at term returns the tied rows in created_at order (the generic loop above cannot tell).
for (const name of ["workout_log_exercises", "workout_log_sets"]) {
  Deno.test(`${name}: rows tied on completed_at come back in created_at order, not id order`, async () => {
    const mine = datasetB(ME, 1500, 700, 1);
    const db = makeDb({ [name]: mine });
    const rows = (await read(db, ME, name)) as Row[];
    assertEquals(rows.length, 1500);
    // dataset B: created_at ascending == index DESCENDING, so the 700 tied rows (i = 600..1299,
    // sorted positions 600..1299) come back as i = 1299..600
    assertEquals(
      rows.slice(TIE_START, TIE_START + 700).map((r) => r.id),
      Array.from({ length: 700 }, (_, k) => uuid(TIE_START + 699 - k, 1)),
    );
    assertEquals(
      PAGED_READS[name].order.map((t) => t.column),
      ["completed_at", "created_at", "id"],
    );
  });
}

// The custom-item reads had no order before; the client keeps the FIRST row per lower-cased name, so
// they now come back in created_at order (an insertion-order proxy), id only as the page-seam tiebreak.
for (const name of ["user_custom_exercises", "user_custom_foods"]) {
  Deno.test(`${name}: rows come back in created_at order, not id order`, async () => {
    const mine = datasetB(ME, 1500, 0, 1); // created_at ascending == index DESCENDING
    const db = makeDb({ [name]: mine });
    const rows = (await read(db, ME, name)) as Row[];
    assertEquals(rows.map((r) => r.id), Array.from({ length: 1500 }, (_, k) => uuid(1499 - k, 1)));
    assertEquals(PAGED_READS[name].order.map((t) => t.column), ["created_at", "id"]);
  });
}

// A server cap BELOW the page size (e.g. a stricter db-max-rows): pages advance by rows RECEIVED,
// so nothing is skipped or duplicated and the read still ends on the empty page.
Deno.test("a server cap below the page size still returns every row exactly once", async () => {
  for (const name of ["workout_logs", "daily_steps"]) {
    const mine = datasetC(ME, 1700, 0, 1);
    const db = makeDb({ [name]: mine }, { serverCap: 500 });
    const rows = (await read(db, ME, name)) as Row[];
    assertEquals(rows.length, 1700);
    assertEquals(new Set(rows.map((r) => r.id)).size, 1700);
    assertEquals(db.calls.length, 5); // 500 + 500 + 500 + 200 rows, then the empty page
  }
});

// ── 1b. the request-wide page budget (abuse bound: a user can write unbounded rows of their own) ─

Deno.test("the budget starts at TOTAL_PAGE_BUDGET and is charged one per page request", async () => {
  const budget = createPageBudget();
  assertEquals(budget.remaining, TOTAL_PAGE_BUDGET);
  const db = makeDb({ weight_logs: datasetA(ME, 2500, 0, 1) });
  await read(db, ME, "weight_logs", budget);
  assertEquals(db.calls.length, 4);
  assertEquals(budget.remaining, TOTAL_PAGE_BUDGET - 4);
  // a fresh request gets a fresh budget (no module-level state shared between requests)
  assertEquals(createPageBudget().remaining, TOTAL_PAGE_BUDGET);
});

Deno.test("the budget is SHARED across reads: the third 50,000-row table throws, and the request never exceeds the budget", async () => {
  const budget = createPageBudget();
  const names = ["user_custom_exercises", "user_custom_foods", "weight_logs"];
  const db = makeDb(Object.fromEntries(names.map((n, i) => [n, datasetA(ME, 50000, 0, i + 1)])));
  assertEquals(((await read(db, ME, names[0], budget)) as Row[]).length, 50000); // 51 requests
  assertEquals(((await read(db, ME, names[1], budget)) as Row[]).length, 50000); // 51 more
  assertEquals(budget.remaining, TOTAL_PAGE_BUDGET - 102);
  const tripped = await assertRejects(() => read(db, ME, names[2], budget), Error, "page budget exhausted at 'weight_logs'");
  assert(!tripped.message.includes("sort key"), "a budget trip must not read as a sort-key problem");
  assertEquals(budget.remaining, 0, "a failed read is still charged for the pages it took");
  assert(db.calls.length <= TOTAL_PAGE_BUDGET, `${db.calls.length} requests exceed the budget`);
});

Deno.test("TOTAL_PAGE_BUDGET covers the floor: one request per empty table, two per small table", () => {
  assert(TOTAL_PAGE_BUDGET >= 2 * PAGED_READ_NAMES.length, "adding readers or lowering the budget would starve small users");
});

Deno.test("ONE request reads all thirteen tables under ONE budget without tripping it (small and 3,000-row users)", async () => {
  for (const [rowsPerTable, requestsPerTable] of [[0, 1], [400, 2], [1200, 3], [3000, 4]] as const) {
    const budget = createPageBudget();
    const data = Object.fromEntries(
      PAGED_READ_NAMES.map((n, i) => [n, datasetA(ME, rowsPerTable, 0, i + 1)]),
    );
    const db = makeDb(data);
    for (const name of PAGED_READ_NAMES) {
      assertEquals(((await read(db, ME, name, budget)) as Row[]).length, rowsPerTable, name);
    }
    assertEquals(db.calls.length, PAGED_READ_NAMES.length * requestsPerTable);
    assertEquals(budget.remaining, TOTAL_PAGE_BUDGET - PAGED_READ_NAMES.length * requestsPerTable);
  }
});

Deno.test("a spent, missing or malformed budget throws BEFORE any request", async () => {
  for (const bad of [{ remaining: 0 }, { remaining: -3 }, { remaining: Number.NaN }, undefined, null]) {
    const db = makeDb({ weight_logs: datasetA(ME, 10, 0, 1) });
    await assertRejects(
      () => readPaged(db, ME, "weight_logs", bad as unknown as PageBudget),
      Error,
      "page budget exhausted",
    );
    assertEquals(db.calls.length, 0);
  }
});

Deno.test("a failing page is charged to the budget too (try/finally)", async () => {
  const budget: PageBudget = { remaining: 10 };
  const db = makeDb({ weight_logs: datasetA(ME, 2500, 0, 1) }, { failOnRequest: 2 });
  await assertRejects(() => read(db, ME, "weight_logs", budget), Error, "failed");
  assertEquals(budget.remaining, 8);
});

// ── 2. the 50,000-row ceiling: 50,000 pass, 50,001 throw (fail closed) ──────────────────────────
// Two representative tables (id-only order and the three-term order): the limit lives in ONE code
// path (readPaged), so running all thirteen at 50k rows would only add CI time.

for (const name of ["user_custom_exercises", "workout_log_exercises"]) {
  Deno.test(`${name}: exactly 50,000 rows pass; 50,001 throw`, async () => {
    const ok = makeDb({ [name]: datasetA(ME, 50000, 0, 1) });
    assertEquals(((await read(ok, ME, name)) as Row[]).length, 50000);
    assertEquals(ok.calls.length, MAX_PAGES); // 50 full pages + the confirming empty page

    const over = makeDb({ [name]: datasetA(ME, 50001, 0, 1) });
    await assertRejects(() => read(over, ME, name), Error, `exceeded maxPages=${MAX_PAGES}`);
  });
}

// ── 3. guards: unknown names and unvalidated user ids never reach the database ─────────────────

Deno.test("an unknown paged read throws (never returns [])", async () => {
  for (const bad of ["nope", "constructor", "__proto__", "toString", ""]) {
    const db = makeDb({});
    await assertRejects(() => read(db, ME, bad), Error, "unknown paged read");
    assertEquals(db.calls.length, 0);
  }
});

Deno.test("an unvalidated user id never reaches the database", async () => {
  for (const bad of ["", "abc", "11111111-1111-4111-8111-11111111111", null as unknown as string, `${ME}\n`, ` ${ME}`, `${ME}\u0000`]) {
    const db = makeDb({});
    await assertRejects(() => read(db, bad, "workout_logs"), Error, "not a validated uuid");
    await assertRejects(() => readCoachNewest(db, bad), Error, "not a validated uuid");
    assertEquals(db.calls.length, 0);
  }
});

Deno.test("UUID_RE is anchored: a trailing newline, a prefix and a missing hyphen all fail", () => {
  assert(UUID_RE.test(ME));
  assert(HEX.toUpperCase() !== HEX); // the case test below must actually change the string
  assert(UUID_RE.test(HEX.toUpperCase())); // a uuid is a uuid in either case (see scopeEmbed)
  for (const bad of [`${ME}\n`, `x${ME}`, ME.replace(/-/g, ""), `${ME},${ME}`, ""]) assert(!UUID_RE.test(bad), bad);
});

// ── 4. the coach window: NEWEST 1000, ascending, scoped, throws on error ────────────────────────

Deno.test("coach: over 1000 rows returns the NEWEST 1000 in ascending order", async () => {
  const mine: Row[] = Array.from({ length: 1200 }, (_, i) => ({
    id: uuid(i, 1), user_id: ME, created_at: iso(i),
  }));
  // The other user's rows are NEWER than every one of mine: a dropped scope would return them.
  const theirs: Row[] = Array.from({ length: 300 }, (_, i) => ({
    id: uuid(i, 2), user_id: OTHER, created_at: iso(5000 + i),
  }));
  const db = makeDb({ [COACH_TABLE]: [...mine, ...theirs] });
  const rows = (await readCoachNewest(db, ME)) as Row[];
  assertEquals(rows.map((r) => r.id), mine.slice(200).map((r) => r.id));
  assertAllScoped(db.calls, ME);
  assertEquals(db.calls.length, 1);
  const c = db.calls[0];
  assertEquals(c.filters[1], { op: "gte", column: "created_at", value: SINCE });
  assertEquals(c.orders, [{ column: "created_at", ascending: false }, { column: "id", ascending: false }]);
  assertEquals(c.limit, COACH_LIMIT);
});

Deno.test("coach: rows tied on created_at are cut deterministically by id", async () => {
  const mine: Row[] = Array.from({ length: 1500 }, (_, i) => ({
    id: uuid(i, 1), user_id: ME, created_at: iso(0),
  }));
  const db = makeDb({ [COACH_TABLE]: mine });
  const rows = (await readCoachNewest(db, ME)) as Row[];
  assertEquals(rows.map((r) => r.id), mine.slice(500).map((r) => r.id));
});

Deno.test("coach: a failing read rejects (no empty chat history with a 200)", async () => {
  const db = makeDb({ [COACH_TABLE]: [] }, { failOnRequest: 1 });
  await assertRejects(() => readCoachNewest(db, ME), Error, "query_failed:ai_coach_interactions");
});

// ── 5. the template embed is owner-scoped (Hermes C13) ───────────────────────────────────────────

Deno.test("scheduled_workouts: a foreign template embed comes back null, an owned one without user_id", async () => {
  const tpl = (owner: string, name: string) => ({
    id: `t-${name}`, name, workout_type: "strength", deleted_at: null, user_id: owner,
    template_exercises: [{ id: `e-${name}` }],
  });
  const rows: Row[] = [
    { id: uuid(1), user_id: ME, scheduled_date: "2024-02-01", template: tpl(ME, "Push") },
    { id: uuid(2), user_id: ME, scheduled_date: "2024-02-02", template: tpl(OTHER, "SECRET-OTHER-USERS-TEMPLATE") },
    { id: uuid(3), user_id: ME, scheduled_date: "2024-02-03", template: null },
    { id: uuid(4), user_id: ME, scheduled_date: "2024-02-04" },
  ];
  const db = makeDb({ scheduled_workouts: rows });
  const out = (await read(db, ME, "scheduled_workouts")) as Row[];
  assertEquals(out.length, 4);
  assertEquals(out[0].template, {
    id: "t-Push", name: "Push", workout_type: "strength", deleted_at: null,
    template_exercises: [{ id: "e-Push" }],
  });
  assertEquals(out[1].template, null);
  assertEquals(out[2].template, null);
  assert(!("template" in out[3]));
  assert(!JSON.stringify(out).includes("SECRET-OTHER-USERS-TEMPLATE"));
  // the embed asks PostgREST for the template owner, only to scope it
  assertStringIncludes(db.calls[0].select, "template:template_id(id, name, workout_type, deleted_at, user_id, template_exercises(*))");
});

Deno.test("scopeEmbed never passes an untrusted embed through (array / string / number / missing owner)", () => {
  const mk = (template: unknown): Row[] => [{ id: "r", template }];
  const owned = { id: "t", name: "Push", user_id: ME };
  assertEquals(scopeEmbed(mk(owned), ME, { path: "template", column: "user_id" })[0].template, { id: "t", name: "Push" });
  for (const hostile of [[owned], "SECRET", 7, true, { id: "t", name: "x" }, { id: "t", user_id: 5 }, { id: "t", user_id: null }, { id: "t", user_id: OTHER }]) {
    assertEquals(
      scopeEmbed(mk(hostile), ME, { path: "template", column: "user_id" })[0].template,
      null,
      `embed ${JSON.stringify(hostile)} must become null`,
    );
  }
  // absent / null stay as they are (a schedule day with no template is legitimate)
  assertEquals(scopeEmbed(mk(null), ME, { path: "template", column: "user_id" })[0].template, null);
  assert(!("template" in scopeEmbed([{ id: "r" }], ME, { path: "template", column: "user_id" })[0]));
});

Deno.test("scopeEmbed compares the owner case-insensitively: an uppercase caller id keeps its OWN template", () => {
  const rows: Row[] = [{ id: "r", template: { id: "t", user_id: HEX } }];
  assertEquals(scopeEmbed(rows, HEX.toUpperCase(), { path: "template", column: "user_id" })[0].template, { id: "t" });
  const upperOwner: Row[] = [{ id: "r", template: { id: "t", user_id: HEX.toUpperCase() } }];
  assertEquals(scopeEmbed(upperOwner, HEX, { path: "template", column: "user_id" })[0].template, { id: "t" });
  // ...and another user's template is still dropped whatever the casing
  const foreign: Row[] = [{ id: "r", template: { id: "t", user_id: HEX_OTHER.toUpperCase() } }];
  assertEquals(scopeEmbed(foreign, HEX, { path: "template", column: "user_id" })[0].template, null);
});

// ── 6. the log line: table names and counts only ────────────────────────────────────────────────

Deno.test("rowCountLogLine carries table names and row counts, never a row value", () => {
  const tables: Record<string, unknown> = {};
  for (const n of [...PAGED_READ_NAMES, COACH_TABLE]) tables[n] = [{ secret: "PII-VALUE" }, { secret: "PII-VALUE" }];
  tables["user_profile"] = [{ full_name: "PII-NAME" }];
  const line = rowCountLogLine("ab12cd34", tables);
  assert(/^\[restore-user-snapshot\] request_id=[0-9a-f]+ rows( [a-z_]+=\d+)+$/.test(line), line);
  assert(!line.includes("PII"));
  assert(line.includes("workout_log_sets=2") && line.includes("ai_coach_interactions=2"));
  assert(!line.includes("user_profile"));
});

// ── 7. the manifest against the OLD chains (extracted from the old source, never retyped) ───────

const fixture = JSON.parse(
  await Deno.readTextFile(new URL("./old_chains.fixture.json", import.meta.url)),
) as {
  chains: Record<string, {
    select: string;
    gte: { column: string; constant: string } | null;
    order: { column: string; ascending: boolean }[];
    range: string | null;
    limit: number | null;
    eqUserId: boolean;
  }>;
};

for (const name of PAGED_READ_NAMES) {
  Deno.test(`${name}: keeps the old select, filter and primary sort; adds only created_at/id tiebreaks`, () => {
    const old = fixture.chains[name];
    const now = PAGED_READS[name];
    assert(old.eqUserId, `${name}: the old chain was user-scoped`);
    // scheduled_workouts is the one deliberate select change: `user_id` added INSIDE the embed.
    const expectedSelect = name === "scheduled_workouts"
      ? now.select.replace(", user_id,", ",")
      : now.select;
    assertEquals(expectedSelect, old.select);
    if (old.gte) {
      assertEquals(now.gte, {
        column: old.gte.column,
        value: old.gte.constant === "SINCE" ? SINCE : SINCE_DATE,
      });
    } else {
      assertEquals(now.gte, undefined);
    }
    // the old primary sort terms come first, with EXPLICIT directions equal to the old defaults
    for (let i = 0; i < old.order.length; i++) {
      assertEquals(now.order[i], { column: old.order[i].column, ascending: old.order[i].ascending });
    }
    const added = now.order.slice(old.order.length);
    assert(added.every((t) => t.column === "created_at" || t.column === "id"));
    assertEquals(now.order[now.order.length - 1], { column: "id", ascending: true });
    assert(now.order.every((t) => typeof t.ascending === "boolean"));
  });
}

Deno.test("the coach window keeps the old filter and the old 1000 cap (and flips to newest)", () => {
  const old = fixture.chains[COACH_TABLE];
  assertEquals(old.gte, { column: "created_at", constant: "SINCE" });
  assertEquals(old.limit, COACH_LIMIT);
  assertEquals(old.order, [{ column: "created_at", ascending: true }]); // the OLDEST 1000 (the defect)
});

Deno.test("the thirteen reads are exactly the thirteen the old function paged or left unbounded", () => {
  assertEquals(
    [...PAGED_READ_NAMES].sort(),
    Object.keys(fixture.chains).filter((n) => n !== COACH_TABLE).sort(),
  );
  assertEquals(PAGED_READ_NAMES.length, 13);
});

// ── 8. every manifest column exists in the live schema (a variable .from() escapes the gate) ────

Deno.test("every manifest select/filter/order column exists in backups/live_schema_columns.json", async () => {
  const live = JSON.parse(
    await Deno.readTextFile(new URL("../../../backups/live_schema_columns.json", import.meta.url)),
  ).tables as Record<string, string[]>;
  for (const name of PAGED_READ_NAMES) {
    const cols = live[name];
    assert(cols, `${name}: table missing from the live schema snapshot`);
    const spec = PAGED_READS[name];
    assert(cols.includes("user_id"), `${name}: no user_id column to scope by`);
    if (spec.gte) assert(cols.includes(spec.gte.column), `${name}: gte column ${spec.gte.column}`);
    for (const t of spec.order) assert(cols.includes(t.column), `${name}: order column ${t.column}`);
  }
  // the one embed with an explicit column list
  const m = /template:template_id\(([^()]*?),\s*template_exercises\(\*\)\)/.exec(PAGED_READS.scheduled_workouts.select);
  assert(m, "template embed not found");
  for (const col of m![1].split(",").map((s) => s.trim())) {
    assert(live["workout_templates"].includes(col), `workout_templates has no column ${col}`);
  }
  assert(live[COACH_TABLE].includes("user_id") && live[COACH_TABLE].includes("created_at") && live[COACH_TABLE].includes("id"));
});
