// OI-519 U4: fetchRenewingPlayUserIds, the reader expiry-reminder uses to skip a Play subscriber whose
// subscription renews by itself. The fake EVALUATES every .eq / .gte filter against real rows, so a wrong
// column, a wrong value or a dropped filter changes the answer.
//
// Run: deno test --allow-read supabase/functions/_shared/subscription_play_renewing_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { fetchRenewingPlayUserIds } from "./subscription.ts";

type Row = {
  id: number;
  user_id: string;
  status: string;
  end_date: string;
  store: string | null;
  auto_renew: boolean | null;
};

function client(rows: Row[], fail?: "error" | "throw") {
  return {
    from(_t: string) {
      const filters: Array<[string, string, unknown]> = [];
      const b = {
        select(_c: string) {
          return b;
        },
        eq(c: string, v: unknown) {
          filters.push([c, "eq", v]);
          return b;
        },
        gte(c: string, v: unknown) {
          filters.push([c, "gte", v]);
          return b;
        },
        order(_c: string) {
          return b;
        },
        range(from: number, to: number) {
          if (fail === "throw") throw new Error("reset");
          if (fail === "error") return Promise.resolve({ data: null, error: { message: "boom" } });
          const m = rows.filter((r) =>
            filters.every(([c, op, v]) => {
              const cell = (r as unknown as Record<string, unknown>)[c];
              return op === "eq" ? cell === v : String(cell) >= String(v);
            })
          ).sort((a, z) => a.id - z.id);
          return Promise.resolve({ data: m.slice(from, to + 1).map((r) => ({ user_id: r.user_id })), error: null });
        },
      };
      return b;
    },
  };
}

const SINCE = "2026-11-24T00:00:00Z";
const LATER = "2026-12-20T00:00:00Z";

Deno.test("only an ACTIVE Play row with auto_renew TRUE, not ended", async () => {
  const rows: Row[] = [
    { id: 1, user_id: "renews", status: "active", end_date: LATER, store: "play", auto_renew: true },
    { id: 2, user_id: "play-off", status: "active", end_date: LATER, store: "play", auto_renew: false },
    { id: 3, user_id: "play-null", status: "active", end_date: LATER, store: "play", auto_renew: null },
    { id: 4, user_id: "web", status: "active", end_date: LATER, store: null, auto_renew: null },
    { id: 5, user_id: "web-flag", status: "active", end_date: LATER, store: "razorpay", auto_renew: true },
    { id: 6, user_id: "expired", status: "expired", end_date: LATER, store: "play", auto_renew: true },
    { id: 7, user_id: "ended", status: "active", end_date: "2026-11-01T00:00:00Z", store: "play", auto_renew: true },
  ];
  assertEquals([...(await fetchRenewingPlayUserIds(client(rows), SINCE))!], ["renews"]);
});

Deno.test("a renewing Play row plus a LATER referral row: still renewing (PRO continues past the referral end)", async () => {
  const rows: Row[] = [
    { id: 1, user_id: "u", status: "active", end_date: "2026-11-26T00:00:00Z", store: "play", auto_renew: true },
    { id: 2, user_id: "u", status: "active", end_date: LATER, store: null, auto_renew: null },
  ];
  assertEquals((await fetchRenewingPlayUserIds(client(rows), SINCE))!.has("u"), true);
});

Deno.test("null, never an empty set, on a page error or a throw", async () => {
  assertEquals(await fetchRenewingPlayUserIds(client([], "error"), SINCE), null);
  assertEquals(await fetchRenewingPlayUserIds(client([], "throw"), SINCE), null);
});

Deno.test("expiry-reminder: a null read fails the run; the set filters the window before any send", async () => {
  const src = (await Deno.readTextFile(new URL("../expiry-reminder/index.ts", import.meta.url))).replace(/\s+/g, " ");
  assertEquals(src.includes('if (renewingPlay === null) throw new Error('), true);
  assertEquals(
    src.includes("usersWithLatestEndIn(latestEnd, now, threeDaysFromNow, true) .filter(([user_id]) => !renewingPlay.has(user_id))"),
    true,
  );
});
