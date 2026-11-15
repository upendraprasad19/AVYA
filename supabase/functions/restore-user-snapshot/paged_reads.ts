// supabase/functions/restore-user-snapshot/paged_reads.ts
//
// The paged reads of `restore-user-snapshot`, extracted so they can be tested without booting
// `index.ts` (which reads env and calls `serve()` at module scope).
//
// ── Why this exists (diagnose: restore-user-snapshot returns every row) ──
//   PostgREST caps every response at `db-max-rows` (1000 on this project) with HTTP 200 and
//   `error === null` (see `_shared/paged_fetch.ts`). Nine reads in `index.ts` used ONE
//   `.range(0, 49999)`, `scheduled_workouts` used `.range(0, 999)`, `workout_schedule_completions`
//   had no limit and the two `user_custom_*` reads were bare selects, so every one silently
//   returned at most 1000 rows; `ai_coach_interactions` kept the OLDEST 1000. The legacy client
//   restore pages; the single-call path did not. Every read here now pages until an empty page
//   arrives, through `fetchAllPages`.
//
// ── SECURITY (catastrophic — service_role BYPASSES RLS; the function body is the ONLY guard) ──
//   • `readPaged` / `readCoachNewest` apply `.eq("user_id", vUid)` THEMSELVES, FIRST, on every
//     page. The scope is code-owned, NEVER manifest data, so a manifest entry cannot forget it.
//   • `vUid` is re-validated here (non-empty, UUID-shaped) before any query is built. `index.ts`
//     validates the token-derived id first, with the SAME exported `UUID_RE`; this is defence in
//     depth, not a replacement.
//   • ONE request may issue at most `TOTAL_PAGE_BUDGET` page requests across all thirteen reads (a
//     shared `PageBudget`, REQUIRED by `readPaged`): a user can write unbounded rows of their own
//     (RLS only pins `user_id`), and the function holds every row in memory. Beyond the budget a
//     read throws, which `index.ts` turns into the 500 that sends the client down its own legacy
//     per-user-JWT restore (fail-closed, never a partial bundle).
//   • An unknown table name THROWS (never returns `[]`), so a typo is a loud 500, not a silent
//     empty section.
//   • The `scheduled_workouts.template` embed is scoped only by a foreign key and
//     `workout_templates` is not filtered by user, so a row pointing at ANOTHER user's template
//     would leak that template's name and exercises (Hermes C13, open since 2026-07-30). The
//     embed selects the template's `user_id`; a foreign embed is replaced with `null`, and an
//     owned one has `user_id` stripped again so the bundle keeps its legacy shape.
//
// This module imports only `../_shared/paged_fetch.ts`: never `index.ts`, never a bare
// supabase-js specifier (the deploy payload ships no import map).

import { fetchAllPages, type OrderKey } from "../_shared/paged_fetch.ts";

// Full-history restore window — UNCHANGED from the legacy client. ONE owner (index.ts imports it).
export const SINCE = "2020-01-01T00:00:00Z";
// '2020-01-01' for date-typed columns (daily_steps / water_logs / scheduled_workouts).
export const SINCE_DATE = SINCE.substring(0, 10);

// 50 full pages (50,000 rows = the legacy client's `_fetchAllRows` ceiling) plus the one confirming
// EMPTY page. `fetchAllPages` THROWS beyond it, which `index.ts` turns into the same 500 envelope as
// any other read failure, which the client treats as "fall back to the legacy path".
export const MAX_PAGES = 51;
export const PAGE_SIZE = 1000;

// The coach read keeps the newest rows: the legacy client's default order is descending, so a
// `.limit(1000)` there already keeps the newest 1000; supabase-js defaults to ASCENDING, which kept
// the OLDEST 1000 once a user passed 1000 rows.
export const COACH_LIMIT = 1000;

// RFC-4122 UUID shape, anchored (no `m` flag: a trailing newline fails). The ONE definition:
// `index.ts` imports it for its own pre-query check, so the two guards cannot drift apart.
export const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// A request's page budget. A read costs ONE request for an empty table, otherwise one per 1000 rows
// plus the confirming empty page: 13 x 2 = 26 for a user with a few hundred rows per table, 13 x 4 =
// 52 at 3,000 rows each. 120 covers about 100,000 rows in total. One table at the legacy 50,000-row
// ceiling costs 51, so two of them (102) fit only if at most 7 of the other eleven tables hold any
// rows. Past the budget a read throws and the client's own legacy restore runs. The budget bounds
// REQUESTS, not bytes: a worker killed for memory also answers non-200 (the same fallback).
export const TOTAL_PAGE_BUDGET = 120;

export interface PageBudget {
  /** Page requests this request may still issue across ALL paged reads. */
  remaining: number;
}

/** A fresh budget: ONE per request (never module state: requests run concurrently). */
export function createPageBudget(): PageBudget {
  return { remaining: TOTAL_PAGE_BUDGET };
}

// deno-lint-ignore no-explicit-any
export type DbLike = { from(table: string): any };

export interface PagedReadSpec {
  /** The EXACT select string of the read this replaces (embeds included). */
  select: string;
  /** Optional lower bound, `gte(column, value)`. */
  gte?: { column: string; value: string };
  /**
   * ORDER BY terms, each with an EXPLICIT direction (supabase-js defaults to ascending, the Dart
   * client to descending; nothing here relies on a default). The LAST term must be unique (`id`).
   */
  order: OrderKey[];
  /** A to-one embed whose owner must equal the caller (see SECURITY above). */
  embedScope?: { path: string; column: string };
}

/**
 * The thirteen paged reads, in bundle order. Every entry reproduces its legacy select string,
 * filter column and primary sort column; the added terms (`created_at`, `id`) are tie-breakers so
 * two page requests can never skip or duplicate a row that shares the primary sort key.
 */
export const PAGED_READS: Record<string, PagedReadSpec> = {
  // The legacy reads had NO order (physical order, roughly insertion order). The client keeps the
  // FIRST row per lower-cased name, so `created_at` comes before the page-seam-only `id`.
  user_custom_exercises: {
    select: "*",
    order: [
      { column: "created_at", ascending: true },
      { column: "id", ascending: true },
    ],
  },
  user_custom_foods: {
    select: "*",
    order: [
      { column: "created_at", ascending: true },
      { column: "id", ascending: true },
    ],
  },
  workout_logs: {
    select: "*",
    gte: { column: "created_at", value: SINCE },
    order: [
      { column: "created_at", ascending: true },
      { column: "id", ascending: true },
    ],
  },
  workout_log_exercises: {
    select: "*",
    gte: { column: "completed_at", value: SINCE },
    // created_at is a fair insertion-order proxy (one single-row upsert per row sets it
    // server-side); `id` is a random uuid and only guarantees page-seam stability.
    order: [
      { column: "completed_at", ascending: true },
      { column: "created_at", ascending: true },
      { column: "id", ascending: true },
    ],
  },
  workout_log_sets: {
    select: "*",
    gte: { column: "completed_at", value: SINCE },
    order: [
      { column: "completed_at", ascending: true },
      { column: "created_at", ascending: true },
      { column: "id", ascending: true },
    ],
  },
  workout_schedule_completions: {
    select: "*",
    // Filters `completed_at` but sorts `scheduled_date`: preserved exactly as the legacy read had it.
    gte: { column: "completed_at", value: SINCE },
    order: [
      { column: "scheduled_date", ascending: true },
      { column: "id", ascending: true },
    ],
  },
  weight_logs: {
    select: "*",
    gte: { column: "created_at", value: SINCE },
    order: [
      { column: "created_at", ascending: true },
      { column: "id", ascending: true },
    ],
  },
  daily_steps: {
    select: "*",
    gte: { column: "date", value: SINCE_DATE },
    order: [
      { column: "date", ascending: true },
      { column: "id", ascending: true },
    ],
  },
  nutrition_logs: {
    select: "*, nutrition_log_items(*)",
    gte: { column: "created_at", value: SINCE },
    order: [
      { column: "created_at", ascending: true },
      { column: "id", ascending: true },
    ],
  },
  body_measurements: {
    select: "*",
    gte: { column: "created_at", value: SINCE },
    order: [
      { column: "created_at", ascending: true },
      { column: "id", ascending: true },
    ],
  },
  water_logs: {
    select: "*",
    gte: { column: "date", value: SINCE_DATE },
    order: [
      { column: "date", ascending: true },
      { column: "id", ascending: true },
    ],
  },
  sleep_logs: {
    select: "*",
    gte: { column: "created_at", value: SINCE },
    order: [
      { column: "created_at", ascending: true },
      { column: "id", ascending: true },
    ],
  },
  // OI-252: `deleted_at` is in the embed so the client can tell a deleted template's schedule day
  // apart from a merely-missing embed. `user_id` is added to the embed ONLY to scope it (stripped
  // again by readPaged); every other column is the legacy projection.
  scheduled_workouts: {
    select:
      "*, template:template_id(id, name, workout_type, deleted_at, user_id, template_exercises(*))",
    gte: { column: "scheduled_date", value: SINCE_DATE },
    order: [
      { column: "scheduled_date", ascending: true },
      { column: "id", ascending: true },
    ],
    embedScope: { path: "template", column: "user_id" },
  },
};

/** The bundle keys read through this module, in the order `index.ts` assigns them. */
export const PAGED_READ_NAMES: string[] = Object.keys(PAGED_READS);
export const COACH_TABLE = "ai_coach_interactions";

function assertUserId(vUid: unknown): asserts vUid is string {
  if (typeof vUid !== "string" || !UUID_RE.test(vUid)) {
    // Never build a query for an unvalidated id: a null/empty id must not become an unscoped read.
    throw new Error("paged_reads: user id is not a validated uuid");
  }
}

/**
 * Scopes a to-one embed to the caller. `row[path]` is the embedded object (or null/absent).
 * A foreign owner yields `null`; an owned embed loses its `user_id` so the shape is the legacy one.
 * Anything that is not a plain object (an array, a string, a number) is NOT trusted: it becomes
 * `null`, never passed through. The owner comparison is case-insensitive (a uuid is the same uuid
 * in either case, and `UUID_RE` accepts both), so an owned template is never nulled by casing.
 */
export function scopeEmbed(
  rows: Record<string, unknown>[],
  vUid: string,
  scope: { path: string; column: string },
): Record<string, unknown>[] {
  const me = vUid.toLowerCase();
  return rows.map((row) => {
    const embed = row[scope.path];
    if (embed === null || embed === undefined) return row;
    // Explicit, though the owner check below would also null these shapes (defence in depth).
    if (typeof embed !== "object" || Array.isArray(embed)) {
      return { ...row, [scope.path]: null };
    }
    const e = embed as Record<string, unknown>;
    const owner = e[scope.column];
    if (typeof owner !== "string" || owner.toLowerCase() !== me) {
      return { ...row, [scope.path]: null };
    }
    const { [scope.column]: _owner, ...rest } = e;
    return { ...row, [scope.path]: rest };
  });
}

/**
 * Reads EVERY row of one paged table for `vUid`. Throws on any page error (no partial result), on
 * an unknown name, on an unvalidated user id, beyond `MAX_PAGES` pages for this table, and when the
 * REQUEST's shared `budget` is spent (the budget is required: a call that forgot it would be
 * unbounded). Each page request taken is charged to the budget, success or failure.
 */
export async function readPaged(
  db: DbLike,
  vUid: string,
  name: string,
  budget: PageBudget,
): Promise<unknown[]> {
  assertUserId(vUid);
  if (!Object.hasOwn(PAGED_READS, name)) {
    throw new Error(`paged_reads: unknown paged read '${name}'`);
  }
  if (!budget || !Number.isInteger(budget.remaining) || budget.remaining < 1) {
    throw new Error(`paged_reads: page budget exhausted before '${name}'`);
  }
  const spec = PAGED_READS[name];

  // This table may take at most what the request has left, capped at the per-table ceiling.
  const maxPages = Math.min(MAX_PAGES, budget.remaining);
  let pagesTaken = 0;
  try {
    const rows = await fetchAllPages<Record<string, unknown>>(
      () => {
        pagesTaken++;
        // The user scope is applied HERE, first, on every page: fetchAllPages calls this factory
        // once per page, so no page can ever be unscoped.
        let q = db.from(name).select(spec.select).eq("user_id", vUid);
        if (spec.gte) q = q.gte(spec.gte.column, spec.gte.value);
        return q;
      },
      {
        orderBy: spec.order,
        pageSize: PAGE_SIZE,
        maxPages,
        label: `restore-user-snapshot ${name}`,
      },
    );
    return spec.embedScope ? scopeEmbed(rows, vUid, spec.embedScope) : rows;
  } catch (e) {
    // fetchAllPages words a maxPages throw as a SORT-KEY problem ("an unstable sort key can loop
    // forever"). When the request budget, not the per-table ceiling, was the limit, say so: an
    // operator reading the log must not chase a sort key that is fine.
    if (maxPages < MAX_PAGES && e instanceof Error && e.message.includes("exceeded maxPages")) {
      throw new Error(
        `paged_reads: page budget exhausted at '${name}' (this read was allowed ${maxPages} pages)`,
      );
    }
    throw e;
  } finally {
    budget.remaining -= pagesTaken;
  }
}

/**
 * The newest `COACH_LIMIT` coach interactions for `vUid`, returned in ASCENDING `created_at` order
 * (the bundle's legacy shape; the client keys each row by `created_at`, so order is not relied on).
 * Not paged: it is a bounded recency window, so it bypasses `fetchAllPages` — and therefore owns
 * its own throw-on-error and its own user scope.
 */
export async function readCoachNewest(
  db: DbLike,
  vUid: string,
): Promise<unknown[]> {
  assertUserId(vUid);
  const { data, error } = await db
    .from(COACH_TABLE)
    .select("*")
    .eq("user_id", vUid)
    .gte("created_at", SINCE)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(COACH_LIMIT);
  if (error) {
    const msg = (error as { message?: string })?.message ?? String(error);
    throw new Error(`query_failed:${COACH_TABLE}:${msg}`);
  }
  return [...((data ?? []) as unknown[])].reverse();
}

/**
 * The per-request log line: table names and row COUNTS only — never a row value — so the live
 * behaviour can be read from the function logs without a user token.
 */
export function rowCountLogLine(
  requestId: string,
  tables: Record<string, unknown>,
): string {
  const names = [...PAGED_READ_NAMES, COACH_TABLE];
  const counts = names.map((n) => {
    const v = tables[n];
    return `${n}=${Array.isArray(v) ? v.length : "n/a"}`;
  });
  return `[restore-user-snapshot] request_id=${requestId} rows ${counts.join(" ")}`;
}
