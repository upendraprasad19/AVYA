// Table-backed fake Supabase client for coach-tool handler tests (L1b).
// Applies eq / in / is(null) / gte / lte / neq filters, order, range and the
// optional {count:"exact"} so the real fetchPagesBounded / fetchAllPages loops
// run against it. Records every filter applied per from() for assertions.

// deno-lint-ignore-file no-explicit-any
export interface FakeCall {
  table: string;
  filters: Array<[string, string, unknown]>;
}

export function fakeSb(tables: Record<string, any[]>, opts: { pageCap?: number } = {}) {
  const calls: FakeCall[] = [];
  const client = {
    from(table: string) {
      const call: FakeCall = { table, filters: [] };
      calls.push(call);
      let wantCount = false;
      let orderCols: Array<[string, boolean]> = [];
      let rangeFrom = 0;
      let rangeTo = Number.MAX_SAFE_INTEGER;
      let limitN: number | null = null;
      const b: any = {};
      const run = () => {
        let rows = (tables[table] ?? []).filter((r) =>
          call.filters.every(([op, col, val]) => {
            const v = r[col];
            switch (op) {
              case "eq": return v === val;
              case "neq": return v !== val;
              case "in": return (val as unknown[]).includes(v);
              case "is": return val === null ? (v === null || v === undefined) : v === val;
              case "ilike": return new RegExp("^" + String(val).replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/%/g, ".*") + "$", "i").test(String(v ?? ""));
              case "gte": return v !== null && v !== undefined && String(v) >= String(val);
              case "gt": return v !== null && v !== undefined && String(v) > String(val);
              case "lte": return v !== null && v !== undefined && String(v) <= String(val);
              case "lt": return v !== null && v !== undefined && String(v) < String(val);
              default: return true;
            }
          })
        );
        for (const [c, asc] of [...orderCols].reverse()) {
          rows = [...rows].sort((a, z) => {
            const x = a[c], y = z[c];
            const r = x < y ? -1 : x > y ? 1 : 0;
            return asc ? r : -r;
          });
        }
        const total = rows.length;
        const cap = opts.pageCap ?? 1000;
        let end = Math.min(rangeTo + 1, rangeFrom + cap);
        if (limitN !== null) end = Math.min(end, rangeFrom + limitN);
        const page = rows.slice(rangeFrom, end);
        return { data: page, error: null, count: wantCount ? total : null };
      };
      b.select = (_c?: string, o?: { count?: string }) => { wantCount = o?.count === "exact"; return b; };
      for (const op of ["eq", "neq", "in", "is", "ilike", "gte", "gt", "lte", "lt"]) {
        b[op] = (col: string, val: unknown) => { call.filters.push([op, col, val]); return b; };
      }
      b.order = (c: string, o?: { ascending?: boolean }) => { orderCols.push([c, o?.ascending ?? true]); return b; };
      b.range = (f: number, t: number) => { rangeFrom = f; rangeTo = t; return b; };
      b.limit = (n: number) => { limitN = n; return b; };
      b.then = (resolve: (r: unknown) => void, reject?: (e: unknown) => void) =>
        Promise.resolve(run()).then(resolve, reject);
      return b;
    },
  };
  return { sb: client, calls };
}
