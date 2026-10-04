// OI-202 -- behavioural tests for the `subscriptions`-derived expiry helpers in
// subscription.ts (fetchLatestActiveEndByUser + its two pure reducers).
//
// The fake below EVALUATES the .eq / .gte filters against real rows and applies
// PostgREST's db-max-rows cap, so a wrong column, a wrong operator or a missing
// pagination loop changes the answer. A recording-only fake would pass for any
// of those.
//
// Run: deno test supabase/functions/_shared/subscription_test.ts

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  fetchLatestActiveEndByUser,
  reduceLatestEndByUser,
  usersWithLatestEndIn,
} from "./subscription.ts";

interface SubRow {
  id: number;
  user_id: string;
  status: string;
  end_date: string;
}

interface Recorded {
  table: string;
  select: string;
  filters: Array<[string, string, unknown]>;
  order: string;
  ranges: Array<[number, number]>;
}

function makeClient(
  rows: SubRow[],
  rec: Recorded,
  opts: { serverCap?: number; failWith?: "error" | "throw" } = {},
) {
  const cap = opts.serverCap ?? 1000;
  return {
    from(table: string) {
      rec.table = table;
      const filters: Array<[string, string, unknown]> = [];
      const builder = {
        select(cols: string) {
          rec.select = cols;
          return builder;
        },
        eq(col: string, v: unknown) {
          filters.push([col, "eq", v]);
          return builder;
        },
        gte(col: string, v: unknown) {
          filters.push([col, "gte", v]);
          return builder;
        },
        order(col: string) {
          rec.order = col;
          return builder;
        },
        range(from: number, to: number) {
          rec.filters = filters;
          rec.ranges.push([from, to]);
          if (opts.failWith === "throw") throw new Error("transport reset");
          if (opts.failWith === "error") {
            return Promise.resolve({ data: null, error: { message: "boom" } });
          }
          const matched = rows
            .filter((r) =>
              filters.every(([col, op, v]) => {
                const cell = (r as unknown as Record<string, unknown>)[col];
                if (op === "eq") return cell === v;
                // ISO timestamps compare lexically only when same format; the
                // fixtures below all use the same `Z` form on purpose.
                return String(cell) >= String(v);
              })
            )
            .sort((a, b) => a.id - b.id);
          const want = to - from + 1;
          const served = Math.min(want, cap);
          return Promise.resolve({
            data: matched.slice(from, from + served).map((r) => ({
              user_id: r.user_id,
              end_date: r.end_date,
            })),
            error: null,
          });
        },
        then(res: (v: unknown) => unknown) {
          return Promise.resolve(builder).then(res);
        },
      };
      return builder;
    },
  };
}

const newRec = (): Recorded => ({
  table: "",
  select: "",
  filters: [],
  order: "",
  ranges: [],
});

// ── pure reducer ────────────────────────────────────────────────────────────

Deno.test("reduceLatestEndByUser keeps the MAX end_date per user, not the first or last row seen", () => {
  // A renewal leaves two active rows for one user. Both orders are asserted:
  // a reducer that kept "last seen" passes one, "first seen" passes the other.
  const a = reduceLatestEndByUser([
    { user_id: "u1", end_date: "2026-10-01T00:00:00Z" },
    { user_id: "u1", end_date: "2026-12-01T00:00:00Z" },
  ]);
  const b = reduceLatestEndByUser([
    { user_id: "u1", end_date: "2026-12-01T00:00:00Z" },
    { user_id: "u1", end_date: "2026-10-01T00:00:00Z" },
  ]);
  assertEquals(a.get("u1"), "2026-12-01T00:00:00Z");
  assertEquals(b.get("u1"), "2026-12-01T00:00:00Z");
});

Deno.test("reduceLatestEndByUser compares INSTANTS, not strings (+00:00 vs Z)", () => {
  // Lexically "...T10:00:00+00:00" < "...T09:00:00Z" is false but the instants
  // are 10:00 and 09:00 -- the +00:00 one is LATER. A string compare picks the
  // wrong one only in some digit positions; this pair makes it wrong.
  const m = reduceLatestEndByUser([
    { user_id: "u1", end_date: "2026-11-01T09:00:00Z" },
    { user_id: "u1", end_date: "2026-11-01T10:00:00+00:00" },
  ]);
  assertEquals(m.get("u1"), "2026-11-01T10:00:00+00:00");
  // Offset form: 12:00+05:30 is 06:30Z, i.e. EARLIER than 09:00Z although
  // "12:00" > "09:00" lexically.
  const n = reduceLatestEndByUser([
    { user_id: "u2", end_date: "2026-11-01T09:00:00Z" },
    { user_id: "u2", end_date: "2026-11-01T12:00:00+05:30" },
  ]);
  assertEquals(n.get("u2"), "2026-11-01T09:00:00Z");
});

Deno.test("reduceLatestEndByUser skips an unparseable end_date instead of letting NaN win", () => {
  const m = reduceLatestEndByUser([
    { user_id: "u1", end_date: "not-a-date" },
    { user_id: "u1", end_date: "2026-10-01T00:00:00Z" },
  ]);
  assertEquals(m.get("u1"), "2026-10-01T00:00:00Z");
  // A user whose ONLY row is unparseable is absent, not present-with-garbage.
  assertEquals(reduceLatestEndByUser([{ user_id: "u9", end_date: "x" }]).size, 0);
});

Deno.test("reduceLatestEndByUser keeps users independent (multi-user fixture)", () => {
  const m = reduceLatestEndByUser([
    { user_id: "a", end_date: "2026-10-01T00:00:00Z" },
    { user_id: "b", end_date: "2026-11-01T00:00:00Z" },
    { user_id: "a", end_date: "2026-09-01T00:00:00Z" },
    { user_id: "b", end_date: "2026-10-15T00:00:00Z" },
  ]);
  assertEquals(m.get("a"), "2026-10-01T00:00:00Z");
  assertEquals(m.get("b"), "2026-11-01T00:00:00Z");
  assertEquals(m.size, 2);
});

// ── range selection ─────────────────────────────────────────────────────────

Deno.test("usersWithLatestEndIn: half-open [from,to) by default, closed with toInclusive", () => {
  const m = new Map([
    ["at-from", "2026-10-01T00:00:00Z"],
    ["inside", "2026-10-02T00:00:00Z"],
    ["at-to", "2026-10-03T00:00:00Z"],
    ["before", "2026-09-30T23:59:59Z"],
    ["after", "2026-10-03T00:00:01Z"],
  ]);
  const from = new Date("2026-10-01T00:00:00Z");
  const to = new Date("2026-10-03T00:00:00Z");
  assertEquals(
    usersWithLatestEndIn(m, from, to).map(([u]) => u).sort(),
    ["at-from", "inside"],
  );
  assertEquals(
    usersWithLatestEndIn(m, from, to, true).map(([u]) => u).sort(),
    ["at-from", "at-to", "inside"],
  );
});

Deno.test("a renewed user is NOT reported as lapsing: latest end wins over the old row", () => {
  // Old row lapses inside yesterday's window; a newer row runs to December.
  // The mirror-column reader would have reported this user as lapsed.
  const latest = reduceLatestEndByUser([
    { user_id: "renewed", end_date: "2026-09-28T10:00:00Z" },
    { user_id: "renewed", end_date: "2026-12-28T10:00:00Z" },
    { user_id: "lapsed", end_date: "2026-09-28T11:00:00Z" },
  ]);
  const yStart = new Date("2026-09-28T00:00:00Z");
  const tStart = new Date("2026-09-29T00:00:00Z");
  assertEquals(
    usersWithLatestEndIn(latest, yStart, tStart).map(([u]) => u),
    ["lapsed"],
  );
});

// ── fetch: filters, paging, failure ─────────────────────────────────────────

Deno.test("fetchLatestActiveEndByUser sends the right table/columns/filters and applies them", async () => {
  const rows: SubRow[] = [
    { id: 1, user_id: "u1", status: "active", end_date: "2026-10-10T00:00:00Z" },
    { id: 2, user_id: "u1", status: "active", end_date: "2026-12-10T00:00:00Z" },
    // cancelled rows must never count, however late they end:
    { id: 3, user_id: "u2", status: "cancelled", end_date: "2027-01-01T00:00:00Z" },
    // active but ended BEFORE the floor:
    { id: 4, user_id: "u3", status: "active", end_date: "2026-01-01T00:00:00Z" },
    { id: 5, user_id: "u4", status: "active", end_date: "2026-10-20T00:00:00Z" },
  ];
  const rec = newRec();
  const map = await fetchLatestActiveEndByUser(
    makeClient(rows, rec),
    "2026-09-01T00:00:00Z",
  );
  assertEquals(rec.table, "subscriptions");
  assertEquals(rec.select, "user_id, end_date");
  assertEquals(rec.order, "id");
  assertEquals(rec.filters, [
    ["status", "eq", "active"],
    ["end_date", "gte", "2026-09-01T00:00:00Z"],
  ]);
  assertEquals(
    [...map!.entries()].sort(),
    [["u1", "2026-12-10T00:00:00Z"], ["u4", "2026-10-20T00:00:00Z"]],
  );
});

Deno.test("fetchLatestActiveEndByUser pages past db-max-rows: 1431 rows, 1431 users", async () => {
  const rows: SubRow[] = [];
  for (let i = 0; i < 1431; i++) {
    rows.push({
      id: i,
      user_id: `user-${i}`,
      status: "active",
      end_date: "2026-11-01T00:00:00Z",
    });
  }
  const rec = newRec();
  const map = await fetchLatestActiveEndByUser(
    makeClient(rows, rec, { serverCap: 1000 }),
    "2026-09-01T00:00:00Z",
  );
  // Without the paging loop a single request yields 1000 rows with error=null.
  assertEquals(map!.size, 1431);
  assertEquals(rec.ranges.length >= 2, true, "must have requested more than one page");
});

Deno.test("fetchLatestActiveEndByUser returns null (NOT an empty map) on a page error", async () => {
  const map = await fetchLatestActiveEndByUser(
    makeClient([], newRec(), { failWith: "error" }),
    "2026-09-01T00:00:00Z",
  );
  assertEquals(map, null);
});

Deno.test("fetchLatestActiveEndByUser returns null on a transport-level throw", async () => {
  const map = await fetchLatestActiveEndByUser(
    makeClient([], newRec(), { failWith: "throw" }),
    "2026-09-01T00:00:00Z",
  );
  assertEquals(map, null);
});

Deno.test("fetchLatestActiveEndByUser: no matching rows is an EMPTY map, distinct from null", async () => {
  const map = await fetchLatestActiveEndByUser(
    makeClient([], newRec()),
    "2026-09-01T00:00:00Z",
  );
  assertEquals(map, new Map());
});

Deno.test("fetchLatestActiveEndByUser warns loudly at the 5000-row sanity ceiling, and only there", async () => {
  const mk = (n: number): SubRow[] =>
    Array.from({ length: n }, (_, i) => ({
      id: i,
      user_id: `user-${i}`,
      status: "active",
      end_date: "2026-11-01T00:00:00Z",
    }));
  const warns: string[] = [];
  const origWarn = console.warn;
  console.warn = (...a: unknown[]) => void warns.push(a.join(" "));
  try {
    const under = await fetchLatestActiveEndByUser(makeClient(mk(4999), newRec()), "2026-09-01T00:00:00Z");
    assertEquals(under!.size, 4999);
    assertEquals(warns.length, 0, "no warning below the ceiling");
    const at = await fetchLatestActiveEndByUser(makeClient(mk(5000), newRec()), "2026-09-01T00:00:00Z");
    assertEquals(at!.size, 5000, "the warning must not truncate the result");
    assertEquals(warns.length, 1);
    assertEquals(warns[0].includes("sanity ceiling"), true);
  } finally {
    console.warn = origWarn;
  }
});
