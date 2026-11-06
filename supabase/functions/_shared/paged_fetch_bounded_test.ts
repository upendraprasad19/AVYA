import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { fetchPagesBounded } from "./paged_fetch_bounded.ts";

// Fake builder over `total` rows; `counts` records withCount per makeQuery call.
function fake(total: number, opts: { countNull?: boolean; shrinkTo?: number; cap?: number } = {}) {
  const log: { withCount: boolean; from: number; to: number }[] = [];
  const make = (withCount: boolean) => {
    const b = {
      order() { return b; },
      range(from: number, to: number) {
        log.push({ withCount, from, to });
        const live = opts.shrinkTo !== undefined && log.length > 1 ? opts.shrinkTo : total;
        const n = Math.max(0, Math.min(to + 1, live) - from);
        const data = Array.from({ length: Math.min(n, opts.cap ?? 1000) }, (_, i) => ({ id: from + i }));
        return Promise.resolve({
          data,
          error: null,
          count: withCount && !opts.countNull ? total : null,
        });
      },
    };
    return b;
  };
  return { make, log };
}
const O = { orderBy: [{ column: "id" }], maxPages: 10, label: "t" };

Deno.test("2,350 rows in 1,000-row pages: stops on count, three pages, count only on page 0", async () => {
  const f = fake(2350);
  const r = await fetchPagesBounded<{ id: number }>(f.make, O);
  assertEquals(r.rows.length, 2350);
  assertEquals(r.truncated, false);
  assertEquals(f.log.map((l) => l.withCount), [true, false, false]);
});

Deno.test("exact multiple: stops on count without an extra empty page", async () => {
  const f = fake(2000);
  const r = await fetchPagesBounded(f.make, O);
  assertEquals(r.rows.length, 2000);
  assertEquals(f.log.length, 2);
});

Deno.test("null count falls back to the empty-page rule", async () => {
  const f = fake(1500, { countNull: true });
  const r = await fetchPagesBounded(f.make, O);
  assertEquals(r.rows.length, 1500);
  assertEquals(r.truncated, false);
  assertEquals(f.log.length, 3); // 1000, 500, empty
});

Deno.test("count shrinking between pages ends on the empty page, not truncated", async () => {
  const f = fake(2350, { shrinkTo: 1200 });
  const r = await fetchPagesBounded(f.make, O);
  assertEquals(r.rows.length, 1200);
  assertEquals(r.truncated, false);
});

Deno.test("maxPages reached with a full last page => truncated", async () => {
  const f = fake(5000);
  const r = await fetchPagesBounded(f.make, { ...O, maxPages: 2 });
  assertEquals(r.rows.length, 2000);
  assertEquals(r.truncated, true);
});

Deno.test("a page error throws, never partial rows", async () => {
  const make = () => {
    const b = { order() { return b; }, range() { return Promise.resolve({ data: null, error: { message: "boom" } }); } };
    return b;
  };
  await assertRejects(() => fetchPagesBounded(make, O), Error, "boom");
});

Deno.test("orderBy is required", async () => {
  await assertRejects(() => fetchPagesBounded(() => ({}), { ...O, orderBy: [] }), Error, "orderBy");
});

Deno.test("a server cap BELOW the page size (db-max-rows 500): offsets advance by rows RECEIVED, no row skipped", async () => {
  const f = fake(1300, { cap: 500 });
  const r = await fetchPagesBounded<{ id: number }>(f.make, O);
  assertEquals(r.rows.length, 1300);
  assertEquals(new Set(r.rows.map((x) => x.id)).size, 1300);
  assertEquals(f.log.map((l) => l.from), [0, 500, 1000]);
});
