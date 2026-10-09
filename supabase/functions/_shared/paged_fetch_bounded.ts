// supabase/functions/_shared/paged_fetch_bounded.ts
//
// `fetchPagesBounded` — a bounded, count-aware pager for CLIENT-INVOKED coach
// tools (L1b plan B4). `paged_fetch.ts` (imported by ~20 functions) stays
// untouched; it reads until an empty page and throws at its runaway guard,
// which is right for crons and wrong for a tool a user is waiting on.
//
// Page 0 asks for `count: 'exact'` (only page 0 — a count on a page past the
// total returns PGRST103). Stop when rows >= count, on an empty page, or on a
// null count (falls back to the empty-page rule). `truncated` = maxPages
// reached with a full last page.

import { POSTGREST_MAX_ROWS } from "./paged_fetch.ts";

export interface BoundedOrderKey {
  column: string;
  ascending?: boolean;
}

interface BoundedBuilder {
  order(column: string, opts: { ascending: boolean }): BoundedBuilder;
  range(
    from: number,
    to: number,
  ): PromiseLike<{ data: unknown; error: unknown; count?: number | null }>;
}

export interface BoundedFetchOptions {
  /** REQUIRED: ORDER BY terms; the last must be unique (a primary key). */
  orderBy: BoundedOrderKey[];
  maxPages: number;
  label: string;
  pageSize?: number;
}

export interface BoundedFetchResult<T> {
  rows: T[];
  truncated: boolean;
}

/**
 * `makeQuery(withCount)` returns a fresh builder; when `withCount` is true it
 * must select with `{ count: "exact" }`. Throws on a page error (a tool that
 * cannot read its inputs must not answer from half of them).
 */
export async function fetchPagesBounded<T>(
  makeQuery: (withCount: boolean) => unknown,
  opts: BoundedFetchOptions,
): Promise<BoundedFetchResult<T>> {
  if (!Array.isArray(opts.orderBy) || opts.orderBy.length === 0) {
    throw new Error(`paged_fetch_bounded[${opts.label}]: orderBy is required`);
  }
  if (!Number.isInteger(opts.maxPages) || opts.maxPages < 1) {
    throw new Error(`paged_fetch_bounded[${opts.label}]: maxPages must be a positive integer`);
  }
  const pageSize = opts.pageSize ?? POSTGREST_MAX_ROWS;
  if (!Number.isInteger(pageSize) || pageSize < 1 || pageSize > POSTGREST_MAX_ROWS) {
    throw new Error(`paged_fetch_bounded[${opts.label}]: bad pageSize ${pageSize}`);
  }

  const all: T[] = [];
  let total: number | null = null;
  let lastFull = false;

  for (let page = 0; page < opts.maxPages; page++) {
    const from = all.length; // advance by rows RECEIVED (server cap may be < pageSize)
    const to = from + pageSize - 1;
    let q = makeQuery(page === 0) as BoundedBuilder;
    for (const k of opts.orderBy) q = q.order(k.column, { ascending: k.ascending ?? true });
    const { data, error, count } = await q.range(from, to);
    if (error) {
      throw new Error(
        `paged_fetch_bounded[${opts.label}]: query failed on page ${page}: ` +
          `${(error as { message?: string } | null)?.message ?? String(error)}`,
      );
    }
    if (page === 0 && typeof count === "number") total = count;
    const rows = (data ?? []) as T[];
    all.push(...rows);
    lastFull = rows.length > 0;
    if (rows.length === 0) return { rows: all, truncated: false };
    if (total !== null && all.length >= total) return { rows: all, truncated: false };
  }
  return { rows: all, truncated: lastFull };
}
