// OI-79 — behavioral tests for paged_fetch.ts.
//
// These are not shape assertions. The fake builder below reproduces the exact
// PostgREST behaviour measured live on 2026-08-01 (see paged_fetch.ts header):
// a request is served at most `db-max-rows` rows, with HTTP 200 and
// `error === null`, so a truncated read is indistinguishable from a small one.
// The central test (`recovers every row past the cap`) fails without the
// pagination loop and passes with it.
//
// Run: deno test supabase/functions/

import {
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  DEFAULT_PAGE_SIZE,
  fetchAllByIds,
  fetchAllPages,
  POSTGREST_MAX_ROWS,
} from "./paged_fetch.ts";

interface Row {
  id: number;
}

interface RecordedCall {
  orderBy: string;
  ascending: boolean;
  /** Every ORDER BY term applied, in order — for the compound-key tests. */
  orderTerms: { column: string; ascending: boolean }[];
  from: number;
  to: number;
  idChunk?: string[];
}

/**
 * Stands in for a supabase-js query builder over a table of `total` rows.
 *
 * `serverCap` reproduces `db-max-rows`: however wide a Range is requested, no
 * more than `serverCap` rows come back — and, exactly as in production, the
 * result carries `error: null` so the caller cannot tell it was clipped.
 */
function makeFake(opts: {
  total: number;
  serverCap?: number;
  calls: RecordedCall[];
  failOnCall?: number;
  idChunk?: string[];
}) {
  const serverCap = opts.serverCap ?? POSTGREST_MAX_ROWS;
  return () => {
    let orderBy = "";
    let ascending = true;
    const orderTerms: { column: string; ascending: boolean }[] = [];
    const builder = {
      order(column: string, o: { ascending: boolean }) {
        orderBy = column;
        ascending = o.ascending;
        orderTerms.push({ column, ascending: o.ascending });
        return builder;
      },
      range(from: number, to: number) {
        opts.calls.push({
          orderBy,
          ascending,
          orderTerms: [...orderTerms],
          from,
          to,
          idChunk: opts.idChunk,
        });
        if (opts.failOnCall !== undefined && opts.calls.length === opts.failOnCall) {
          return Promise.resolve({ data: null, error: { message: "boom" } });
        }
        const requested = to - from + 1;
        const served = Math.min(requested, serverCap);
        const rows: Row[] = [];
        for (let i = from; i < Math.min(from + served, opts.total); i++) {
          rows.push({ id: i });
        }
        // Mirrors production: truncation surfaces as a 200 with no error.
        return Promise.resolve({ data: rows, error: null });
      },
      then(res: (v: unknown) => unknown) {
        return Promise.resolve(builder).then(res);
      },
    };
    return builder;
  };
}

// ── The core regression: without the loop you get 1000 of 1431 ──────────────

Deno.test("NEGATIVE CONTROL: a single un-ranged read silently returns 1000 of 1431", async () => {
  // This is the pre-fix behaviour, pinned so the test below is demonstrably a
  // regression test and not just an assertion about the helper. One request
  // against 1431 rows yields 1000, `error` is null, and there is nothing in the
  // response a caller could branch on to discover the other 431 are missing.
  const calls: RecordedCall[] = [];
  const { data, error } = await makeFake({ total: 1431, calls })()
    .order("id", { ascending: true })
    .range(0, POSTGREST_MAX_ROWS - 1);

  assertEquals((data as Row[]).length, 1000);
  assertEquals(error, null, "the truncation is not reported as an error");
  assertEquals(calls.length, 1);
});

Deno.test("fetchAllPages recovers every row past the db-max-rows cap", async () => {
  const calls: RecordedCall[] = [];
  // 1431 rows — the real `food_database` count used for the live measurement.
  const rows = await fetchAllPages<Row>(makeFake({ total: 1431, calls }), {
    orderBy: "id",
  });

  // A single un-ranged .select() would have returned exactly 1000 here, with
  // error === null, and nothing downstream could have detected the loss.
  assertEquals(rows.length, 1431);
  assertEquals(rows[0].id, 0);
  assertEquals(rows[1430].id, 1430);
  // 3 requests: 1000 rows, then 431, then an empty page to prove the end.
  // Only an EMPTY page proves end-of-data — a short page is equally the
  // signature of a server cap below pageSize.
  assertEquals(calls.length, 3);
  assertEquals(calls[0].from, 0);
  assertEquals(calls[0].to, 999);
  assertEquals(calls[0].orderTerms, [{ column: "id", ascending: true }]);
  assertEquals(calls[1].from, 1000);
  assertEquals(calls[1].to, 1999);
  assertEquals(calls[1].orderTerms, [{ column: "id", ascending: true }]);
  assertEquals(calls[2].from, 1431, "offset advances by rows RECEIVED");
});

Deno.test("fetchAllPages confirms a short page with one more request", async () => {
  // Deliberately NOT "stops after one request". A short page is ambiguous —
  // end-of-data, or a server cap below pageSize — so it costs one confirming
  // request to tell those apart. See the serverCap test below for the case
  // that ambiguity used to break.
  const calls: RecordedCall[] = [];
  const rows = await fetchAllPages<Row>(makeFake({ total: 18, calls }), { orderBy: "id" });
  assertEquals(rows.length, 18);
  assertEquals(calls.length, 2);
  assertEquals(calls[1].from, 18);
});

Deno.test("fetchAllPages survives a server cap BELOW pageSize", async () => {
  // REGRESSION (round-1 review): `db-max-rows` is a dashboard setting, not a
  // platform invariant. With the old `from = page * pageSize` + short-page
  // break, a cap of 500 under a pageSize of 1000 made page 0 return 500,
  // which read as end-of-data — every converted read would have silently
  // returned 500 of 2300 rows with error === null. Fails without the fix.
  const calls: RecordedCall[] = [];
  const rows = await fetchAllPages<Row>(
    makeFake({ total: 2300, serverCap: 500, calls }),
    { orderBy: "id" },
  );
  assertEquals(rows.length, 2300, "must recover every row despite the lower cap");
  assertEquals(new Set(rows.map((r) => r.id)).size, 2300, "no duplicates");
  assertEquals(calls[1].from, 500, "offset follows the SERVER's page size, not ours");
});

Deno.test("fetchAllPages handles a total that is an exact multiple of pageSize", async () => {
  // An exactly-full final page looks identical to "there is more", so one
  // extra request is needed to discover the end. This is the cost the
  // empty-page termination rule pays on every read, not just this boundary.
  const calls: RecordedCall[] = [];
  const rows = await fetchAllPages<Row>(makeFake({ total: 20, calls }), {
    orderBy: "id",
    pageSize: 10,
  });
  assertEquals(rows.length, 20);
  assertEquals(calls.length, 3);
  assertEquals(calls[2].from, 20);
});

Deno.test("fetchAllPages applies the requested sort column and direction", async () => {
  const calls: RecordedCall[] = [];
  await fetchAllPages<Row>(makeFake({ total: 5, calls }), {
    orderBy: "user_id",
    ascending: false,
  });
  assertEquals(calls[0].orderBy, "user_id");
  assertEquals(calls[0].ascending, false);
});

// ── Compound sort keys (the notification_prefs shape) ───────────────────────

Deno.test("fetchAllPages applies a compound sort key in order", async () => {
  // notification_prefs needs `snapshot_date DESC` to keep "first row per user
  // wins = most recent", plus a unique `id` tiebreaker to make paging stable.
  // Both terms must reach the query, in that order.
  const calls: RecordedCall[] = [];
  await fetchAllPages<Row>(makeFake({ total: 5, calls }), {
    orderBy: [
      { column: "snapshot_date", ascending: false },
      { column: "id", ascending: true },
    ],
  });
  assertEquals(calls[0].orderTerms, [
    { column: "snapshot_date", ascending: false },
    { column: "id", ascending: true },
  ]);
});

Deno.test("fetchAllPages defaults a compound term's direction to ascending", async () => {
  const calls: RecordedCall[] = [];
  await fetchAllPages<Row>(makeFake({ total: 5, calls }), {
    orderBy: [{ column: "snapshot_date", ascending: false }, { column: "id" }],
  });
  assertEquals(calls[0].orderTerms[1], { column: "id", ascending: true });
});

Deno.test("fetchAllPages rejects an empty compound sort key", async () => {
  const calls: RecordedCall[] = [];
  await assertRejects(
    () => fetchAllPages<Row>(makeFake({ total: 5, calls }), { orderBy: [] }),
    Error,
    "`orderBy` is required",
  );
  assertEquals(calls.length, 0);
});

Deno.test("fetchAllPages rejects a compound term with a blank column", async () => {
  const calls: RecordedCall[] = [];
  await assertRejects(
    () =>
      fetchAllPages<Row>(makeFake({ total: 5, calls }), {
        orderBy: [{ column: "snapshot_date" }, { column: "  " }],
      }),
    Error,
    "`orderBy` is required",
  );
  assertEquals(calls.length, 0);
});

// ── Guards that make the Class-4 mistake unconstructible ────────────────────

Deno.test("fetchAllPages rejects a missing orderBy", async () => {
  const calls: RecordedCall[] = [];
  await assertRejects(
    () =>
      fetchAllPages<Row>(makeFake({ total: 5, calls }), {
        orderBy: "",
      }),
    Error,
    "`orderBy` is required",
  );
  assertEquals(calls.length, 0, "must reject before issuing any request");
});

Deno.test("fetchAllPages rejects a pageSize above db-max-rows", async () => {
  // The trap: 1500 does not fetch 1500. The server serves 1000, the loop reads
  // that as a short page and stops, silently dropping everything after it.
  const calls: RecordedCall[] = [];
  await assertRejects(
    () =>
      fetchAllPages<Row>(makeFake({ total: 5000, calls }), {
        orderBy: "id",
        pageSize: POSTGREST_MAX_ROWS + 500,
      }),
    Error,
    "exceeds PostgREST's db-max-rows",
  );
  assertEquals(calls.length, 0);
});

Deno.test("fetchAllPages rejects a non-positive pageSize", async () => {
  const calls: RecordedCall[] = [];
  await assertRejects(
    () => fetchAllPages<Row>(makeFake({ total: 5, calls }), { orderBy: "id", pageSize: 0 }),
    Error,
    "pageSize must be a positive integer",
  );
});

Deno.test("fetchAllPages throws on a page error instead of returning partial rows", async () => {
  const calls: RecordedCall[] = [];
  const err = await assertRejects(
    () =>
      fetchAllPages<Row>(makeFake({ total: 5000, calls, failOnCall: 2 }), {
        orderBy: "id",
        label: "unit-test",
      }),
    Error,
  );
  // Partial data from a candidate scan is the bug, not a graceful degradation.
  assertStringIncludes(err.message, "unit-test");
  assertStringIncludes(err.message, "page 1");
  assertStringIncludes(err.message, "boom");
});

Deno.test("fetchAllPages trips the runaway guard when every page stays full", async () => {
  // Simulates an unstable sort key: the server never returns a short page.
  const calls: RecordedCall[] = [];
  const err = await assertRejects(
    () =>
      fetchAllPages<Row>(makeFake({ total: Number.MAX_SAFE_INTEGER, calls }), {
        orderBy: "status",
        maxPages: 3,
      }),
    Error,
    "exceeded maxPages=3",
  );
  assertStringIncludes(err.message, "unique, immutable column");
  assertEquals(calls.length, 3, "must stop at the cap, not run away");
});

// ── fetchAllByIds: bounds the request AND the response ──────────────────────

Deno.test("fetchAllByIds pages within each chunk, not just across chunks", async () => {
  // This is the failure `evaluate-rank-promotions`' fetchInChunks had: it split
  // the id list into 100s, which bounds the URL but not the row count. A chunk
  // of 100 users against a table with 15 rows each returns 1500 rows and gets
  // clipped to 1000. Chunking alone would issue 1 request here and lose 500.
  const calls: RecordedCall[] = [];
  const ids = Array.from({ length: 250 }, (_, i) => `user-${i}`);
  const perChunkRows = 1500;

  const rows = await fetchAllByIds<Row>(
    (chunk) => makeFake({ total: perChunkRows, calls, idChunk: chunk })(),
    ids,
    { orderBy: "id", chunkSize: 100 },
  );

  // 3 chunks (100/100/50), each needing 3 requests to drain 1500 rows:
  // 1000, then 500, then an empty page to prove that chunk is exhausted.
  assertEquals(rows.length, perChunkRows * 3);
  assertEquals(calls.length, 9);
  assertEquals(calls[0].idChunk?.length, 100);
  assertEquals(calls[0].from, 0);
  assertEquals(calls[1].from, 1000, "second page of the SAME chunk");
  assertEquals(calls[2].from, 1500, "confirming page of the SAME chunk");
  assertEquals(calls[3].idChunk?.length, 100);
  assertEquals(calls[3].from, 0, "offset resets per chunk");
  assertEquals(calls[6].idChunk?.length, 50, "final chunk is the remainder");
});

Deno.test("fetchAllByIds issues no request for an empty id list", async () => {
  const calls: RecordedCall[] = [];
  const rows = await fetchAllByIds<Row>(
    (chunk) => makeFake({ total: 10, calls, idChunk: chunk })(),
    [],
    { orderBy: "id" },
  );
  assertEquals(rows, []);
  assertEquals(calls.length, 0);
});

Deno.test("fetchAllByIds inherits the orderBy guard", async () => {
  const calls: RecordedCall[] = [];
  await assertRejects(
    () =>
      fetchAllByIds<Row>((chunk) => makeFake({ total: 10, calls, idChunk: chunk })(), ["a"], {
        orderBy: "",
      }),
    Error,
    "`orderBy` is required",
  );
  assertEquals(calls.length, 0);
});

Deno.test("default page size sits at the measured cap", () => {
  // If db-max-rows is ever lowered on the project, DEFAULT_PAGE_SIZE must move
  // with it — a default above the cap is the silent-early-stop trap.
  assertEquals(DEFAULT_PAGE_SIZE, POSTGREST_MAX_ROWS);
});
