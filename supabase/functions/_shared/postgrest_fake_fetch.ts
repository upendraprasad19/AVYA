// supabase/functions/_shared/postgrest_fake_fetch.ts
//
// Test helper (NOT a test - no `_test` suffix): a fetch-level fake of the three
// services the payment writers talk to - Supabase Auth (`/auth/v1/user`),
// PostgREST (`/rest/v1/<table>` and `/rest/v1/rpc/<fn>`) and the Razorpay REST
// API. The REAL supabase-js client runs on top of it, so the REAL query strings
// are generated and recorded; the in-memory evaluator then answers them with
// SQL three-valued logic (a NULL column never satisfies `eq`/`neq`/`gt`), so a
// filter that is wrong in SQL is wrong here too (OI-341 Piece A, plan 2.3).
//
// Stated gap: it proves the query STRING and its SEMANTICS for the subset the
// code uses (eq, neq, gt, is.null, or, order, limit, select); it does not prove
// that LIVE PostgREST accepts the string. That is the first enabled call.

export type Row = Record<string, unknown>;

export interface RecordedRequest {
  method: string;
  /** Path after the origin, e.g. `/rest/v1/subscriptions`. */
  path: string;
  /** Query parameters as an ordered list of [key, value] (decoded). */
  query: Array<[string, string]>;
  // deno-lint-ignore no-explicit-any
  body: any;
  host: string;
}

/** `Response` to answer with, `"throw"` to reject the fetch, undefined to fall through. */
export type Intercept = (
  req: RecordedRequest,
) => Response | Promise<Response> | "throw" | undefined;

export interface FakeServerOptions {
  origin?: string;
  tables?: Record<string, Row[]>;
  /** Bearer token -> auth user. */
  users?: Record<string, { id: string; email?: string }>;
  /** A handler may return a `Response` to choose the status itself (e.g. a PostgREST error body). */
  rpcs?: Record<string, (args: Row) => unknown>;
  /** Answers any RPC not named in `rpcs` (the handlers' rate-limit counter call). */
  fallbackRpc?: (name: string, args: Row) => unknown;
  /** Handler for `https://api.razorpay.com/*`. */
  razorpay?: (req: RecordedRequest) => Response;
  intercept?: Intercept;
  /** Runs just BEFORE an insert is evaluated (lets a test play the sibling writer). */
  beforeInsert?: (table: string, row: Row, server: FakeServer) => void;
}

export const FAKE_ORIGIN = "https://fake-project.supabase.test";

export class FakeServer {
  readonly origin: string;
  readonly tables: Record<string, Row[]>;
  readonly users: Record<string, { id: string; email?: string }>;
  readonly rpcs: Record<string, (args: Row) => unknown>;
  fallbackRpc?: (name: string, args: Row) => unknown;
  readonly requests: RecordedRequest[] = [];
  razorpay: (req: RecordedRequest) => Response;
  intercept?: Intercept;
  beforeInsert?: (table: string, row: Row, server: FakeServer) => void;
  private original: typeof fetch | null = null;
  private nextId = 1;

  constructor(o: FakeServerOptions = {}) {
    this.origin = o.origin ?? FAKE_ORIGIN;
    this.tables = o.tables ?? {};
    this.users = o.users ?? {};
    this.rpcs = o.rpcs ?? {};
    this.fallbackRpc = o.fallbackRpc;
    this.razorpay = o.razorpay ??
      (() => json(404, { error: { description: "unrouted razorpay call" } }));
    this.intercept = o.intercept;
    this.beforeInsert = o.beforeInsert;
  }

  install(): this {
    this.original = globalThis.fetch;
    globalThis.fetch = ((input: unknown, init?: RequestInit) =>
      this.handle(input, init)) as typeof fetch;
    return this;
  }

  restore(): void {
    if (this.original) globalThis.fetch = this.original;
    this.original = null;
  }

  /** Requests whose path matches (and optionally method). */
  to(pathPrefix: string, method?: string): RecordedRequest[] {
    return this.requests.filter((r) =>
      r.path.startsWith(pathPrefix) && (method === undefined || r.method === method)
    );
  }

  private async handle(input: unknown, init?: RequestInit): Promise<Response> {
    const req0 = input instanceof Request ? input : null;
    const url = new URL(req0 ? req0.url : String(input));
    const method = (init?.method ?? req0?.method ?? "GET").toUpperCase();
    const headers = new Headers(init?.headers ?? req0?.headers);
    let raw: string | null = null;
    if (typeof init?.body === "string") raw = init.body;
    else if (req0 && method !== "GET") raw = await req0.clone().text();
    let body: unknown = null;
    if (raw) {
      try {
        body = JSON.parse(raw);
      } catch {
        body = raw;
      }
    }
    const rec: RecordedRequest = {
      method,
      path: url.pathname,
      query: [...url.searchParams.entries()],
      body,
      host: url.origin,
    };
    this.requests.push(rec);

    const hooked = this.intercept?.(rec);
    if (hooked === "throw") throw new TypeError("fake network failure");
    if (hooked) return hooked;

    if (url.origin === "https://api.razorpay.com") return this.razorpay(rec);
    if (url.origin !== this.origin) {
      throw new Error(`FakeServer: unrouted fetch ${method} ${url.href}`);
    }
    if (url.pathname === "/auth/v1/user") {
      const token = (headers.get("authorization") ?? "").replace("Bearer ", "");
      const user = this.users[token];
      if (!user) {
        return json(401, { code: 401, msg: "invalid JWT", error_code: "bad_jwt" });
      }
      return json(200, { id: user.id, email: user.email ?? "u@example.test", aud: "authenticated" });
    }
    const rpc = /^\/rest\/v1\/rpc\/(.+)$/.exec(url.pathname);
    if (rpc) {
      const fn = this.rpcs[rpc[1]];
      if (fn) {
        const answer = fn((body ?? {}) as Row);
        return answer instanceof Response ? answer : json(200, answer);
      }
      if (this.fallbackRpc) return json(200, this.fallbackRpc(rpc[1], (body ?? {}) as Row));
      return json(404, { code: "PGRST202", message: `no rpc ${rpc[1]}` });
    }
    const tbl = /^\/rest\/v1\/([^/]+)$/.exec(url.pathname);
    if (tbl) return this.table(tbl[1], method, url, body, headers);
    throw new Error(`FakeServer: unrouted path ${method} ${url.pathname}`);
  }

  private table(
    name: string,
    method: string,
    url: URL,
    body: unknown,
    headers: Headers,
  ): Response {
    const rows = (this.tables[name] ??= []);
    if (method === "GET") {
      let hits = rows.filter((r) => matches(r, url.searchParams));
      const order = url.searchParams.get("order");
      if (order) {
        const [col, dir] = order.split(".");
        const sign = dir === "desc" ? -1 : 1;
        hits = [...hits].sort((a, b) => sign * compare(a[col], b[col]));
      }
      const limit = url.searchParams.get("limit");
      if (limit !== null) hits = hits.slice(0, Number(limit));
      const select = url.searchParams.get("select");
      const projected = hits.map((r) => project(r, select));
      if ((headers.get("accept") ?? "").includes("vnd.pgrst.object")) {
        if (projected.length !== 1) {
          return json(406, {
            code: "PGRST116",
            details: `The result contains ${projected.length} rows`,
            hint: null,
            message: "JSON object requested, multiple (or no) rows returned",
          });
        }
        return json(200, projected[0]);
      }
      return json(200, projected);
    }
    if (method === "POST") {
      const incoming = (Array.isArray(body) ? body : [body]) as Row[];
      for (const row of incoming) {
        this.beforeInsert?.(name, row, this);
        const dupe = uniqueViolation(name, rows, row);
        if (dupe) return json(409, dupe);
        rows.push({ id: `row-${this.nextId++}`, ...row });
      }
      return new Response(null, { status: 201 });
    }
    if (method === "PATCH") {
      for (const r of rows.filter((x) => matches(x, url.searchParams))) {
        Object.assign(r, body as Row);
      }
      return new Response(null, { status: 204 });
    }
    return json(405, { message: `fake: ${method} not modelled` });
  }
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export function jsonResponse(status: number, body: unknown): Response {
  return json(status, body);
}

/** The UNIQUE constraints the code relies on (migration 010). */
function uniqueViolation(table: string, rows: Row[], row: Row): Row | null {
  if (table === "subscriptions" && row.razorpay_payment_id != null) {
    if (rows.some((r) => r.razorpay_payment_id === row.razorpay_payment_id)) {
      return {
        code: "23505",
        details: `Key (razorpay_payment_id)=(${row.razorpay_payment_id}) already exists.`,
        hint: null,
        message:
          'duplicate key value violates unique constraint "unique_razorpay_payment_id"',
      };
    }
  }
  return null;
}

const CONTROL = new Set(["select", "order", "limit", "offset", "on_conflict", "columns"]);

/** Three-valued truth: true / false / null (SQL unknown). */
type Tri = boolean | null;

function matches(row: Row, params: URLSearchParams): boolean {
  for (const [key, value] of params.entries()) {
    if (CONTROL.has(key)) continue;
    if (key === "or") {
      if (orGroup(row, value) !== true) return false;
      continue;
    }
    if (condition(row, key, value) !== true) return false;
  }
  return true;
}

function orGroup(row: Row, raw: string): Tri {
  const inner = raw.replace(/^\(/, "").replace(/\)$/, "");
  let unknown = false;
  for (const part of inner.split(",")) {
    const m = /^([^.]+)\.(.+)$/.exec(part);
    if (!m) throw new Error(`FakeServer: bad or() arm ${part}`);
    const r = condition(row, m[1], m[2]);
    if (r === true) return true;
    if (r === null) unknown = true;
  }
  return unknown ? null : false;
}

/** `value` is `<op>.<operand>` (e.g. `eq.x`, `is.null`, `neq.pay_1`, `gt.2026-...`). */
function condition(row: Row, col: string, value: string): Tri {
  const dot = value.indexOf(".");
  const op = value.slice(0, dot);
  const operand = value.slice(dot + 1);
  const cell = row[col];
  if (op === "is") {
    if (operand === "null") return cell === null || cell === undefined;
    throw new Error(`FakeServer: is.${operand} not modelled`);
  }
  if (cell === null || cell === undefined) return null; // NULL op x = unknown
  switch (op) {
    case "eq":
      return String(cell) === operand;
    case "neq":
      return String(cell) !== operand;
    case "gt":
      return compare(cell, operand) > 0;
    default:
      throw new Error(`FakeServer: operator ${op} not modelled`);
  }
}

/** Instants compare as instants (PostgREST may render `+00:00` or `Z`). */
function compare(a: unknown, b: unknown): number {
  const ta = instant(a);
  const tb = instant(b);
  if (ta !== null && tb !== null) return ta - tb;
  const sa = String(a);
  const sb = String(b);
  return sa < sb ? -1 : sa > sb ? 1 : 0;
}

function instant(v: unknown): number | null {
  if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}T/.test(v)) return null;
  const t = Date.parse(v);
  return Number.isNaN(t) ? null : t;
}

function project(row: Row, select: string | null): Row {
  if (!select || select === "*") return { ...row };
  const out: Row = {};
  for (const c of select.split(",").map((s) => s.trim())) out[c] = row[c];
  return out;
}
