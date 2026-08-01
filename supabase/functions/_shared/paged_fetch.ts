/**
 * paged_fetch — bounded reads for cron Edge Functions (OI-79).
 *
 * ## The bug this exists to prevent
 *
 * PostgREST caps every response at `db-max-rows` (1000 on this project) and
 * **supabase-js gives you no way to notice**. Measured live 2026-08-01 against
 * `dedsavbjuwgarrhphgnl`, `food_database` (1431 rows):
 *
 * | request                                   | status | Content-Range | rows |
 * |-------------------------------------------|--------|---------------|------|
 * | `?select=id` (what `.select()` sends)      | 200 OK | `0-999/*`     | 1000 |
 * | `Range: 0-1499`                            | 200 OK | `0-999/*`     | 1000 |
 * | `Range: 1000-1999`                         | 200 OK | `1000-1430/*` |  431 |
 * | `Prefer: count=exact`                      | 206    | `0-999/1431`  | 1000 |
 *
 * Three things follow, and each one is load-bearing:
 *
 * 1. **It is a 200, not a 206.** OI-79 was filed saying truncation shows up as
 *    `206 Partial Content`. That is only true when the caller asks for a count,
 *    and no cron function here does. In the shape our code actually sends, the
 *    response is a plain `200 OK` with a short body and `error === null`. There
 *    is no status, no error, and no total (`/*`) to compare against — a
 *    truncated read is *byte-for-byte indistinguishable* from a small one. The
 *    only available signal is `rows.length === pageSize`.
 * 2. **`.range()` cannot raise the cap.** Asking for 0-1499 still yields 1000.
 *    So `pageSize` MUST be <= the cap; a larger value does not fetch more, it
 *    silently breaks the loop (you ask for 1500, get 1000, read that as a short
 *    page, and stop early — dropping every row after the first page).
 * 3. **Paging past the cap works.** Offset 1000-1999 returns the remainder.
 *    A `.range()` loop is therefore a real fix, not a workaround.
 *
 * ## Why `orderBy` is required and has no default
 *
 * Postgres guarantees no row order without an `ORDER BY`, and PostgREST adds
 * none. Two `.range()` calls against an unordered relation may return
 * overlapping or disjoint slices, so a paginated loop without a stable sort key
 * can **duplicate or skip rows** — silently, and only under load. Three loops in
 * this repo shipped that way (`morning-alert`, `weekly-recap-ready`,
 * `weekly-recalc`); `i-see-you-callout` got it right with
 * `.order("id", { ascending: true })`. Making `orderBy` a required parameter
 * with no default is how that mistake becomes unconstructible here.
 *
 * Pick a key that is **unique and immutable** — a primary key. A non-unique key
 * (`date`, `status`) does not fully order the rows, so ties can shuffle between
 * page requests and reintroduce the same skip/duplicate bug.
 *
 * ## RPCs
 *
 * `.order()` / `.range()` are accepted on `/rpc/` set-returning functions, so
 * both helpers work with `() => supabase.rpc(...)`. Whether `db-max-rows` also
 * caps RPC responses could not be settled from here: the only anon-executable
 * set-returning functions on this project are not `SECURITY DEFINER`, so RLS
 * returns 0 rows to `anon` and the probe is inconclusive. It does not change
 * anything — these helpers page unconditionally, which is correct either way
 * (if the cap does not apply, the loop simply ends on the first short page).
 *
 * @see docs/audit/open_issues.md OI-79
 */

// deno-lint-ignore-file no-explicit-any

/**
 * PostgREST's server-side `db-max-rows` for this project, confirmed live
 * (table above). A response can never exceed this many rows regardless of the
 * requested `Range`.
 */
export const POSTGREST_MAX_ROWS = 1000;

/** Default page size. Sits at the cap: the largest value that is still safe. */
export const DEFAULT_PAGE_SIZE = 1000;

/**
 * Default `.in()` chunk size. Bounds the **request URL**, which is a different
 * constraint from `pageSize` (which bounds the *response*). A uuid costs ~37
 * bytes in `in.(...)`, so 100 ids is ~3.7KB and stays clear of the ~4-8KB URL
 * limits proxies impose. Matches the existing `BATCH_SIZE = 100` precedent in
 * `evaluate-rank-promotions`.
 */
export const DEFAULT_CHUNK_SIZE = 100;

/**
 * Runaway guard. At the default page size this permits 10M rows, far beyond any
 * legitimate cron scan — it exists to turn "PostgREST keeps returning full
 * pages forever" (an unstable sort key, a clock-skewed filter) into a loud
 * failure instead of an Edge Function that runs until the platform kills it.
 */
export const DEFAULT_MAX_PAGES = 10_000;

/** Minimal structural shape we need from a supabase-js query builder. */
interface RangeableBuilder {
  order(column: string, opts: { ascending: boolean }): RangeableBuilder;
  range(from: number, to: number): PromiseLike<{ data: unknown; error: unknown }>;
}

/** One ORDER BY term. */
export interface OrderKey {
  column: string;
  ascending?: boolean;
}

export interface PagedFetchOptions {
  /**
   * REQUIRED. Sort key — must be unique and immutable (a primary key). See the
   * header note on why this has no default.
   *
   * Pass an array to sort by several columns, e.g. to page a "most recent row
   * per user" read while preserving its ordering semantics:
   * `[{ column: "snapshot_date", ascending: false }, { column: "id" }]`.
   * The **last** term must be unique — the earlier ones can tie, and ties
   * without a unique tiebreaker are exactly the unstable-page bug.
   */
  orderBy: string | OrderKey[];
  /**
   * Sort direction for the single-column form. Ignored when `orderBy` is an
   * array (each term carries its own).
   */
  ascending?: boolean;
  /** Rows per request. MUST be <= {@link POSTGREST_MAX_ROWS}; see header note 2. */
  pageSize?: number;
  /** Runaway guard, see {@link DEFAULT_MAX_PAGES}. */
  maxPages?: number;
  /** Prefix for the saturation log line. Defaults to "paged_fetch". */
  label?: string;
}

/** Normalises the `orderBy` union into a non-empty list of ORDER BY terms. */
function orderKeys(opts: PagedFetchOptions): OrderKey[] {
  const bad = () => {
    throw new Error(
      "paged_fetch: `orderBy` is required and must be a non-empty column name " +
        "(or a non-empty array of them). A .range() loop without a stable sort " +
        "key can skip or duplicate rows (OI-79).",
    );
  };

  if (typeof opts.orderBy === "string") {
    if (!opts.orderBy.trim()) bad();
    return [{ column: opts.orderBy, ascending: opts.ascending ?? true }];
  }
  if (!Array.isArray(opts.orderBy) || opts.orderBy.length === 0) bad();
  const keys = (opts.orderBy as OrderKey[]).map((k) => {
    if (!k || typeof k.column !== "string" || !k.column.trim()) bad();
    return { column: k.column, ascending: k.ascending ?? true };
  });
  return keys;
}

function validate(opts: PagedFetchOptions): { pageSize: number; maxPages: number } {
  orderKeys(opts); // throws when the sort key is missing or malformed
  const pageSize = opts.pageSize ?? DEFAULT_PAGE_SIZE;
  if (!Number.isInteger(pageSize) || pageSize < 1) {
    throw new Error(`paged_fetch: pageSize must be a positive integer, got ${pageSize}`);
  }
  if (pageSize > POSTGREST_MAX_ROWS) {
    throw new Error(
      `paged_fetch: pageSize ${pageSize} exceeds PostgREST's db-max-rows ` +
        `(${POSTGREST_MAX_ROWS}). A larger page does not fetch more rows — it makes the ` +
        `first full page look short and silently ends the loop, dropping everything after ` +
        `it. Use a pageSize <= ${POSTGREST_MAX_ROWS} (OI-79).`,
    );
  }
  const maxPages = opts.maxPages ?? DEFAULT_MAX_PAGES;
  if (!Number.isInteger(maxPages) || maxPages < 1) {
    throw new Error(`paged_fetch: maxPages must be a positive integer, got ${maxPages}`);
  }
  return { pageSize, maxPages };
}

/**
 * Reads **every** row matching a query, paging until a short page arrives.
 *
 * `makeQuery` must return a fresh builder each call — supabase-js builders are
 * single-use thenables, so reusing one across pages does not work. Apply your
 * filters there and let this apply `.order()` and `.range()`:
 *
 * ```ts
 * const rows = await fetchAllPages<{ user_id: string }>(
 *   () => supabase.from("coach_memory").select("user_id").gte("dropout_risk_score", 0.5),
 *   { orderBy: "user_id", label: "re-engagement path A" },
 * );
 * ```
 *
 * Throws on the first page error rather than returning partial rows. That is
 * deliberate: silently proceeding with an incomplete candidate set is the exact
 * failure this module exists to prevent, and a cron tick that cannot read its
 * inputs should fail loudly and retry on the next tick.
 */
export async function fetchAllPages<T>(
  makeQuery: () => unknown,
  opts: PagedFetchOptions,
): Promise<T[]> {
  const { pageSize, maxPages } = validate(opts);
  const keys = orderKeys(opts);
  const label = opts.label ?? "paged_fetch";
  const keyDesc = keys.map((k) => `${k.column}${k.ascending ? "" : " desc"}`).join(", ");

  const all: T[] = [];

  for (let page = 0; ; page++) {
    if (page >= maxPages) {
      throw new Error(
        `paged_fetch[${label}]: exceeded maxPages=${maxPages} (${all.length} rows read). ` +
          `Every page came back full — check that orderBy='${keyDesc}' ends in a unique, ` +
          `immutable column; an unstable sort key can loop forever.`,
      );
    }

    // Offset by rows ACTUALLY received, never by `page * pageSize`. The two
    // agree only while the server serves full pages, and `db-max-rows` is a
    // dashboard setting (Settings -> API -> Max rows), not a platform
    // invariant. Lower it to 500 and the old arithmetic broke completely:
    // page 0 asked 0-999, got 500, and `500 < pageSize` read as end-of-data —
    // so every one of the reads this module was written to fix would silently
    // return 500 rows with error === null. Advancing by `all.length` makes the
    // loop correct for ANY server cap without having to know what it is.
    const from = all.length;
    const to = from + pageSize - 1;

    let q = makeQuery() as RangeableBuilder;
    for (const k of keys) q = q.order(k.column, { ascending: k.ascending ?? true });
    const builder = q.range(from, to);

    const { data, error } = await builder;
    if (error) {
      throw new Error(
        `paged_fetch[${label}]: page ${page} (rows ${from}-${to}) failed: ` +
          `${(error as { message?: string } | null)?.message ?? String(error)}`,
      );
    }

    const rows = (data ?? []) as T[];
    all.push(...rows);

    // Only an EMPTY page proves end-of-data. A SHORT page does not: it is
    // equally the signature of a server cap below `pageSize` (see the offset
    // note above), and treating it as "done" is exactly the silent truncation
    // this module exists to prevent. Costs one extra round-trip per read — the
    // same one the exact-multiple case already paid — in exchange for being
    // correct at any `db-max-rows`.
    if (rows.length === 0) break;
  }

  return all;
}

/**
 * Reads every row for a set of ids, chunking the `.in()` list **and** paging
 * within each chunk.
 *
 * Chunking alone is not enough, and that distinction is the whole point of this
 * function. `evaluate-rank-promotions` already had a `fetchInChunks` helper that
 * split `userIds` into batches of 100 — but a chunk bounds the *request*, not
 * the *response*. One 100-id chunk against a table holding N rows per user
 * returns 100xN rows, so it truncates at 10 rows/user no matter how small the
 * chunk is. This pages inside each chunk, which bounds both.
 *
 * ```ts
 * const logs = await fetchAllByIds<{ user_id: string }>(
 *   (chunk) => supabase.from("nutrition_logs")
 *                      .select("user_id, total_protein")
 *                      .eq("date", todayIST)
 *                      .in("user_id", chunk),
 *   proUserIds,
 *   { orderBy: "id", label: "protein-gap-alert nutrition" },
 * );
 * ```
 */
export async function fetchAllByIds<T>(
  makeQuery: (idChunk: string[]) => unknown,
  ids: string[],
  opts: PagedFetchOptions & { chunkSize?: number },
): Promise<T[]> {
  validate(opts);

  const chunkSize = opts.chunkSize ?? DEFAULT_CHUNK_SIZE;
  if (!Number.isInteger(chunkSize) || chunkSize < 1) {
    throw new Error(`paged_fetch: chunkSize must be a positive integer, got ${chunkSize}`);
  }

  if (ids.length === 0) return [];

  const all: T[] = [];
  for (let i = 0; i < ids.length; i += chunkSize) {
    const chunk = ids.slice(i, i + chunkSize);
    const rows = await fetchAllPages<T>(() => makeQuery(chunk), {
      ...opts,
      label: `${opts.label ?? "paged_fetch"} chunk@${i}`,
    });
    all.push(...rows);
  }
  return all;
}
