// Generator Unit 3D-a (OI-175 / FOB-4): the server's hold-week signal. Behavioural proof of `hold_week.ts`: the pure
// functions, and `fetchHoldOrdinals` against a hand-written client stub (`postgrest_fake_fetch.ts` models no
// `gte` / `lte` / `in` and ignores ranges) that records every filter, serves one page per chunk and then an empty
// page (`fetchAllPages` stops only on an empty page).
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  fetchHoldOrdinals,
  holdOrdinalFromWeekNumbers,
  istWeekBounds,
  phaseOneUserIds,
  recapMessage,
  reportWeekLine,
} from "./hold_week.ts";

Deno.test("holdOrdinalFromWeekNumbers: max(week - 4) over integers above 4", () => {
  assertEquals(holdOrdinalFromWeekNumbers([5, 5, 5]), 1);
  assertEquals(holdOrdinalFromWeekNumbers([5, 6, 7]), 3);
  assertEquals(holdOrdinalFromWeekNumbers([8, 6]), 4);
});

Deno.test("holdOrdinalFromWeekNumbers: weeks 1-4, empty and non-integers give null", () => {
  assertEquals(holdOrdinalFromWeekNumbers([1, 2, 3, 4]), null);
  assertEquals(holdOrdinalFromWeekNumbers([]), null);
  assertEquals(holdOrdinalFromWeekNumbers(["6", null, 5.5, undefined, NaN]), null);
  assertEquals(holdOrdinalFromWeekNumbers(["6", 6]), 2);
});

Deno.test("istWeekBounds: the Sunday 20:00 IST cron (14:30 UTC) reads this IST week", () => {
  assertEquals(istWeekBounds(new Date("2026-11-15T14:30:00Z")), { monday: "2026-11-09", sunday: "2026-11-15" });
});

Deno.test("istWeekBounds: Sunday 18:40 UTC is Monday 00:10 IST, the NEXT IST week", () => {
  assertEquals(istWeekBounds(new Date("2026-11-15T18:40:00Z")), { monday: "2026-11-16", sunday: "2026-11-22" });
});

Deno.test("istWeekBounds: a Monday across a month end", () => {
  assertEquals(istWeekBounds(new Date("2026-12-02T06:00:00Z")), { monday: "2026-11-30", sunday: "2026-12-06" });
});

Deno.test("phaseOneUserIds: only a present row with current_phase exactly 1 counts (fails closed)", () => {
  const rows: Record<string, unknown>[] = [
    { user_id: "a", current_phase: 1 },
    { user_id: "b", current_phase: 2 },
    { user_id: "c", current_phase: null },
    { user_id: "d" },
    { user_id: "e", current_phase: "1" },
    { current_phase: 1 },
    { user_id: "", current_phase: 1 },
    { user_id: "f", current_phase: 1 },
  ];
  assertEquals(phaseOneUserIds(rows), ["a", "f"]);
  assertEquals(phaseOneUserIds([]), []);
});

Deno.test("recapMessage: a holder gets the hold's name, everyone else today's text", () => {
  assertEquals(recapMessage("Asha", 4, 2), "Asha — Hold H2 debrief ready. Stand to.");
  assertEquals(recapMessage("Asha", 4, null), "Asha — Week 4 debrief ready. Stand to.");
  assertEquals(recapMessage("Ravi", 3, null), "Ravi — Week 3 debrief ready. Stand to.");
});

Deno.test("reportWeekLine: a holder gets the hold with no Peak / Deload claim, everyone else today's line", () => {
  const hold = reportWeekLine(4, 1);
  assertEquals(
    hold,
    "Current week: hold week H1 (the user chose to keep training Phase I; a repeat of a Phase I week)",
  );
  assert(!/peak|deload/i.test(hold));
  assertEquals(reportWeekLine(4, null), "Current week: 4");
});

// ── fetchHoldOrdinals against a stub client ──────────────────────────────────

interface Call {
  table: string;
  select: string;
  inCol?: string;
  inIds?: string[];
  gte?: [string, unknown];
  lte?: [string, unknown];
  gt?: [string, unknown];
  order: string[];
  ranges: [number, number][];
}

type Row = { id: string; user_id: string; week_number: unknown };

/** A client whose `scheduled_workouts` holds [rows]; it applies the recorded filters itself, so a dropped filter
 *  changes the answer (not only the recorded call). `failOn` makes a page return an error or the range throw. */
function stubClient(rows: Row[], failOn?: "error" | "throw") {
  const calls: Call[] = [];
  const client = {
    from(table: string) {
      const call: Call = { table, select: "", order: [], ranges: [] };
      calls.push(call);
      const b = {
        select(cols: string) {
          call.select = cols;
          return b;
        },
        in(col: string, ids: string[]) {
          call.inCol = col;
          call.inIds = [...ids];
          return b;
        },
        gte(col: string, v: unknown) {
          call.gte = [col, v];
          return b;
        },
        lte(col: string, v: unknown) {
          call.lte = [col, v];
          return b;
        },
        gt(col: string, v: unknown) {
          call.gt = [col, v];
          return b;
        },
        order(col: string) {
          call.order.push(col);
          return b;
        },
        range(from: number, to: number) {
          call.ranges.push([from, to]);
          if (failOn === "throw") throw new Error("boom");
          if (failOn === "error") return Promise.resolve({ data: null, error: { message: "page failed" } });
          // One page per chunk, then an empty page. The stub filters by the RECORDED chunk and filters, so each
          // chunk answers for its own users.
          if (from > 0) return Promise.resolve({ data: [], error: null });
          const ids = new Set(call.inIds ?? []);
          const out = rows.filter((r) =>
            ids.has(r.user_id) &&
            (call.gt == null || (typeof r.week_number === "number" && r.week_number > (call.gt[1] as number)))
          );
          return Promise.resolve({ data: out, error: null });
        },
      };
      return b;
    },
  };
  return { client, calls };
}

Deno.test("fetchHoldOrdinals: the query names the table, the window, week_number > 4 and orders by id", async () => {
  const { client, calls } = stubClient([{ id: "1", user_id: "u1", week_number: 5 }]);
  const res = await fetchHoldOrdinals(client, ["u1"], "2026-11-09", "2026-11-15");
  assertEquals(res.failed, false);
  assertEquals([...res.map], [["u1", 1]]);
  // fetchAllPages builds a fresh query per page: page 0, then the empty page that ends the read.
  assertEquals(calls.length, 2);
  assertEquals(calls.map((x) => x.ranges[0][0]), [0, 1]);
  const c = calls[0];
  assertEquals(c.table, "scheduled_workouts");
  assertEquals(c.inCol, "user_id");
  assertEquals(c.gte, ["scheduled_date", "2026-11-09"]);
  assertEquals(c.lte, ["scheduled_date", "2026-11-15"]);
  assertEquals(c.gt, ["week_number", 4]);
  assertEquals(c.order, ["id"]);
  assert(c.select.includes("week_number") && c.select.includes("user_id"));
});

Deno.test("fetchHoldOrdinals: per-user max over the user's own rows; a user with no hold row is absent", async () => {
  const { client } = stubClient([
    { id: "1", user_id: "a", week_number: 5 },
    { id: "2", user_id: "a", week_number: 6 },
    { id: "3", user_id: "b", week_number: 4 },
    { id: "4", user_id: "c", week_number: 8 },
  ]);
  const res = await fetchHoldOrdinals(client, ["a", "b", "c", "d"], "2026-11-09", "2026-11-15");
  assertEquals(res.failed, false);
  assertEquals(res.map.get("a"), 2);
  assertEquals(res.map.has("b"), false);
  assertEquals(res.map.get("c"), 4);
  assertEquals(res.map.has("d"), false);
});

Deno.test("fetchHoldOrdinals: 101+ ids cross the 100-id chunk; each chunk answers for its own users", async () => {
  const ids = Array.from({ length: 150 }, (_, i) => `u${i}`);
  // Hold rows only in the SECOND chunk (u120), none in the first: the first chunk's page is empty.
  const { client, calls } = stubClient([{ id: "x", user_id: "u120", week_number: 7 }]);
  const res = await fetchHoldOrdinals(client, ids, "2026-11-09", "2026-11-15");
  assertEquals(res.failed, false);
  assertEquals([...res.map], [["u120", 3]]);
  const firstPages = calls.filter((x) => x.ranges[0][0] === 0);
  assertEquals(firstPages.length, 2);
  assertEquals(firstPages[0].inIds?.length, 100);
  assertEquals(firstPages[1].inIds?.length, 50);
});

Deno.test("fetchHoldOrdinals: no users asks nothing", async () => {
  const { client, calls } = stubClient([]);
  const res = await fetchHoldOrdinals(client, [], "2026-11-09", "2026-11-15");
  assertEquals(res, { map: new Map(), failed: false });
  assertEquals(calls.length, 0);
});

Deno.test("fetchHoldOrdinals: a page error never throws, reports failed, and the texts keep today's wording", async () => {
  const { client } = stubClient([{ id: "1", user_id: "a", week_number: 5 }], "error");
  const res = await fetchHoldOrdinals(client, ["a"], "2026-11-09", "2026-11-15");
  assertEquals(res.failed, true);
  assertEquals(res.map.size, 0);
  assertEquals(recapMessage("Asha", 4, res.map.get("a") ?? null), "Asha — Week 4 debrief ready. Stand to.");
  assertEquals(reportWeekLine(4, res.map.get("a") ?? null), "Current week: 4");
});

Deno.test("fetchHoldOrdinals: a throwing builder never throws and reports failed", async () => {
  const { client } = stubClient([{ id: "1", user_id: "a", week_number: 5 }], "throw");
  const res = await fetchHoldOrdinals(client, ["a"], "2026-11-09", "2026-11-15");
  assertEquals(res.failed, true);
  assertEquals(res.map.size, 0);
});

Deno.test("fetchHoldOrdinals: a client that throws on from() never throws", async () => {
  const client = {
    from() {
      throw new Error("no client");
    },
  };
  const res = await fetchHoldOrdinals(client, ["a"], "2026-11-09", "2026-11-15");
  assertEquals(res.failed, true);
});
