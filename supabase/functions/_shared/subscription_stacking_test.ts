// OI-341 Piece A: unit tests of the stacking module. The query tests run the
// REAL supabase-js client over the fetch-level fake (postgrest_fake_fetch.ts),
// so the filters are asserted as the exact query string AND as SQL semantics.
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import {
  isValidPaymentId,
  readLatestActiveEnd,
  resolveEndDate,
  STACKING_ENABLE_ENV,
  stackedEndDate,
} from "./subscription_stacking.ts";
import { FAKE_ORIGIN, FakeServer, jsonResponse, type Row } from "./postgrest_fake_fetch.ts";

const NOW = new Date("2026-10-17T10:00:00.000Z");
const NOW_ISO = NOW.toISOString();
const USER = "11111111-1111-4111-8111-111111111111";
const OTHER = "22222222-2222-4222-8222-222222222222";
const PAY = "pay_NEW0000000001";

const on = (name: string) => (name === STACKING_ENABLE_ENV ? "true" : undefined);
const off = (_: string) => undefined;

// LOCAL-time day arithmetic, like the module: the test oracle must not differ from it across a DST change
// (a UTC-millisecond oracle failed 29 of the suite's tests under America/New_York). The TZ-equivalence test
// below is what compares the module with the old inline code.
function iso(daysFromNow: number): string {
  const d = new Date(NOW);
  d.setDate(d.getDate() + daysFromNow);
  return d.toISOString();
}

function plus(isoStr: string, days: number): string {
  const d = new Date(isoStr);
  d.setDate(d.getDate() + days);
  return d.toISOString();
}

function sub(over: Row): Row {
  return {
    user_id: USER,
    status: "active",
    plan: "monthly",
    start_date: iso(-1),
    end_date: iso(3),
    razorpay_payment_id: null,
    ...over,
  };
}

function client(server: FakeServer) {
  server.install();
  return createClient(FAKE_ORIGIN, "service-role", {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}

async function withServer<T>(rows: Row[], fn: (db: ReturnType<typeof client>, s: FakeServer) => Promise<T>): Promise<T> {
  const server = new FakeServer({ tables: { subscriptions: rows } });
  const db = client(server);
  try {
    return await fn(db, server);
  } finally {
    server.restore();
  }
}

// ── stackedEndDate ──────────────────────────────────────────────────────────

Deno.test("stackedEndDate: no active row -> now + days (monthly 30, yearly 365)", () => {
  assertEquals(stackedEndDate(null, NOW, 30).toISOString(), iso(30));
  assertEquals(stackedEndDate(null, NOW, 365).toISOString(), iso(365));
});

Deno.test("stackedEndDate: a trial ending in 3 days -> trialEnd + days", () => {
  assertEquals(stackedEndDate(new Date(iso(3)), NOW, 30).toISOString(), plus(iso(3), 30));
  assertEquals(stackedEndDate(new Date(iso(3)), NOW, 365).toISOString(), plus(iso(3), 365));
});

Deno.test("stackedEndDate: an end at or before now is not a base (boundary and past)", () => {
  assertEquals(stackedEndDate(new Date(NOW_ISO), NOW, 30).toISOString(), iso(30));
  assertEquals(stackedEndDate(new Date(iso(-5)), NOW, 30).toISOString(), iso(30));
});

Deno.test("stackedEndDate: does not mutate its inputs", () => {
  const latest = new Date(iso(3));
  const before = latest.getTime();
  const nowBefore = NOW.getTime();
  stackedEndDate(latest, NOW, 30);
  assertEquals(latest.getTime(), before);
  assertEquals(NOW.getTime(), nowBefore);
});

// ── TZ equivalence with the old inline code (a month-end / DST regression check,
// NOT mutation proof of the arithmetic; the table above and the handler cases carry that).

Deno.test("stackedEndDate(null, ...) equals the old inline setDate code under several TZ values", async () => {
  const modulePath = new URL("./subscription_stacking.ts", import.meta.url).href;
  const script = `
    import { stackedEndDate } from ${JSON.stringify(modulePath)};
    const bases = ["2026-01-31T10:00:00Z","2026-02-28T23:30:00Z","2026-03-08T06:30:00Z","2026-03-29T00:30:00Z",
      "2026-10-04T15:30:00Z","2026-10-31T20:00:00Z","2026-11-01T05:30:00Z","2028-02-29T12:00:00Z","2026-12-31T18:45:00Z"];
    let bad = 0;
    for (const b of bases) for (const days of [30, 365]) {
      const now = new Date(b);
      const old = new Date(now); old.setDate(old.getDate() + days);
      if (stackedEndDate(null, now, days).toISOString() !== old.toISOString()) bad++;
    }
    console.log(bad === 0 ? "equivalent" : "DIFFERS " + bad);
  `;
  for (const tz of ["UTC", "Asia/Kolkata", "America/New_York", "Australia/Lord_Howe"]) {
    const out = await new Deno.Command(Deno.execPath(), {
      args: ["eval", "--no-check", script],
      env: { TZ: tz },
      stdout: "piped",
      stderr: "piped",
    }).output();
    const text = new TextDecoder().decode(out.stdout).trim();
    assertEquals(text, "equivalent", `TZ=${tz}: ${new TextDecoder().decode(out.stderr)}`);
  }
});

// ── isValidPaymentId ────────────────────────────────────────────────────────

Deno.test("isValidPaymentId: real Razorpay ids pass; structural characters and bad shapes fail", () => {
  assert(isValidPaymentId("pay_NEW0000000001"));
  assert(isValidPaymentId("pay_" + "a".repeat(64)));
  for (const bad of ["", "pay_", "pay_" + "a".repeat(65), "pay_X?y=1", "pay_X/capture", "pay_X#1", "../x",
    "pay_a,b", "pay_a)", "pay_a(", "xpay_abc", "pay_abc ", "pay_ab\n", "manual_grant_123"]) {
    assertEquals(isValidPaymentId(bad), false, JSON.stringify(bad));
  }
  assertEquals(isValidPaymentId(undefined), false);
  assertEquals(isValidPaymentId(12), false);
});

// ── readLatestActiveEnd ─────────────────────────────────────────────────────

Deno.test("readLatestActiveEnd: sends exactly the planned filters (query string pin)", async () => {
  await withServer([], async (db, s) => {
    await readLatestActiveEnd(db, USER, PAY, NOW_ISO);
    const reads = s.to("/rest/v1/subscriptions", "GET");
    assertEquals(reads.length, 1);
    assertEquals(reads[0].query, [
      ["select", "end_date"],
      ["user_id", `eq.${USER}`],
      ["status", "eq.active"],
      ["end_date", `gt.${NOW_ISO}`],
      ["or", `(razorpay_payment_id.is.null,razorpay_payment_id.neq.${PAY})`],
      ["order", "end_date.desc"],
      ["limit", "1"],
    ]);
  });
});

Deno.test("readLatestActiveEnd: no rows -> ok with end null", async () => {
  await withServer([], async (db) => {
    assertEquals(await readLatestActiveEnd(db, USER, PAY, NOW_ISO), { ok: true, end: null });
  });
});

Deno.test("readLatestActiveEnd: the LATEST of several active rows wins (array read, never maybeSingle)", async () => {
  await withServer(
    [sub({ end_date: iso(3) }), sub({ end_date: iso(20), razorpay_payment_id: "pay_OLD0000000001" }), sub({ end_date: iso(9) })],
    async (db) => {
      const r = await readLatestActiveEnd(db, USER, PAY, NOW_ISO);
      assertEquals(r, { ok: true, end: new Date(iso(20)) });
    },
  );
});

Deno.test("readLatestActiveEnd: expired and non-active rows are ignored", async () => {
  await withServer(
    [sub({ end_date: iso(-2) }), sub({ end_date: iso(40), status: "cancelled" }), sub({ end_date: iso(40), status: "expired" })],
    async (db) => {
      assertEquals(await readLatestActiveEnd(db, USER, PAY, NOW_ISO), { ok: true, end: null });
    },
  );
});

Deno.test("readLatestActiveEnd: another user's longer PRO is never a base", async () => {
  await withServer([sub({ user_id: OTHER, end_date: iso(300) }), sub({ end_date: iso(3) })], async (db) => {
    assertEquals(await readLatestActiveEnd(db, USER, PAY, NOW_ISO), { ok: true, end: new Date(iso(3)) });
  });
});

Deno.test("readLatestActiveEnd: the caller's OWN payment row is excluded", async () => {
  await withServer(
    [sub({ end_date: iso(33), razorpay_payment_id: PAY }), sub({ end_date: iso(3) })],
    async (db) => {
      assertEquals(await readLatestActiveEnd(db, USER, PAY, NOW_ISO), { ok: true, end: new Date(iso(3)) });
    },
  );
});

Deno.test("readLatestActiveEnd: a NULL-payment-id trial row is KEPT (SQL NULL semantics)", async () => {
  await withServer([sub({ end_date: iso(3), razorpay_payment_id: null })], async (db) => {
    assertEquals(await readLatestActiveEnd(db, USER, PAY, NOW_ISO), { ok: true, end: new Date(iso(3)) });
  });
});

Deno.test("readLatestActiveEnd: instants compare as instants (+00:00 rendering)", async () => {
  const plus = new Date(iso(3)).toISOString().replace("Z", "+00:00");
  await withServer([sub({ end_date: plus })], async (db) => {
    assertEquals(await readLatestActiveEnd(db, USER, PAY, NOW_ISO), { ok: true, end: new Date(iso(3)) });
  });
});

Deno.test("readLatestActiveEnd: a database error is ok:false with the code, never a guess", async () => {
  const server = new FakeServer({
    intercept: (r) =>
      r.path === "/rest/v1/subscriptions"
        ? jsonResponse(500, { code: "57014", message: "canceling statement due to statement timeout" })
        : undefined,
  });
  const db = client(server);
  try {
    assertEquals(await readLatestActiveEnd(db, USER, PAY, NOW_ISO), { ok: false, code: "57014" });
  } finally {
    server.restore();
  }
});

Deno.test("readLatestActiveEnd: an unparseable end_date is ok:false (no RangeError later)", async () => {
  await withServer([sub({ end_date: "not-a-date" })], async (db) => {
    // 'not-a-date' is not an instant, so gt compares as text: 'n' > '2' keeps the row.
    assertEquals(await readLatestActiveEnd(db, USER, PAY, NOW_ISO), { ok: false, code: "bad_end_date" });
  });
});

Deno.test("readLatestActiveEnd: a payment id that fails the format check is refused BEFORE any request", async () => {
  await withServer([], async (db, s) => {
    for (const bad of ["pay_a,b", "pay_x)", "", "pay_" + "a".repeat(65)]) {
      assertEquals(await readLatestActiveEnd(db, USER, bad, NOW_ISO), { ok: false, code: "bad_payment_id" });
    }
    assertEquals(s.requests.length, 0);
  });
});

// ── resolveEndDate ──────────────────────────────────────────────────────────

Deno.test("resolveEndDate: switch absent / 'false' / empty / ' TRUE ' / 'TRUE' / '1' -> old value and NO read", async () => {
  for (const v of [undefined, "false", "", " TRUE ", "TRUE", "True", "1", "yes", "true "]) {
    await withServer([sub({ end_date: iso(3) })], async (db, s) => {
      const r = await resolveEndDate(db, USER, PAY, NOW, 30, (n) => (n === STACKING_ENABLE_ENV ? v : undefined));
      assertEquals(r, { ok: true, endDate: new Date(iso(30)) }, `value ${JSON.stringify(v)}`);
      assertEquals(s.requests.length, 0, `value ${JSON.stringify(v)} must not query`);
    });
  }
});

Deno.test("resolveEndDate: exactly 'true' stacks on the latest active end", async () => {
  await withServer([sub({ end_date: iso(3) }), sub({ end_date: iso(9), razorpay_payment_id: "pay_OLD0000000001" })], async (db, s) => {
    const monthly = await resolveEndDate(db, USER, PAY, NOW, 30, on);
    assertEquals(monthly, { ok: true, endDate: new Date(plus(iso(9), 30)) });
    const yearly = await resolveEndDate(db, USER, PAY, NOW, 365, on);
    assertEquals(yearly, { ok: true, endDate: new Date(plus(iso(9), 365)) });
    assertEquals(s.to("/rest/v1/subscriptions", "GET").length, 2);
  });
});

Deno.test("resolveEndDate: enabled with no active row -> exactly now + days", async () => {
  await withServer([], async (db) => {
    assertEquals(await resolveEndDate(db, USER, PAY, NOW, 30, on), { ok: true, endDate: new Date(iso(30)) });
  });
});

Deno.test("resolveEndDate: a database error -> ok:false with the code (no fallback to now + days)", async () => {
  const server = new FakeServer({ intercept: () => jsonResponse(500, { code: "XX000", message: "boom" }) });
  const db = client(server);
  try {
    assertEquals(await resolveEndDate(db, USER, PAY, NOW, 30, on), { ok: false, code: "XX000" });
  } finally {
    server.restore();
  }
});

Deno.test("resolveEndDate: a THROWN rejection -> ok:false, never escapes", async () => {
  const server = new FakeServer({ intercept: () => "throw" });
  const db = client(server);
  try {
    const r = await resolveEndDate(db, USER, PAY, NOW, 30, on);
    assertEquals(r.ok, false);
  } finally {
    server.restore();
  }
  // A client whose from() itself throws synchronously also lands in ok:false.
  const throwing = { from: () => { throw new Error("sync boom"); } };
  const r2 = await resolveEndDate(throwing, USER, PAY, NOW, 30, on);
  assertEquals(r2.ok, false);
});

Deno.test("resolveEndDate: switch OFF never touches the client at all", async () => {
  const exploding = { from: () => { throw new Error("must not be called"); } };
  assertEquals(await resolveEndDate(exploding, USER, PAY, NOW, 30, off), { ok: true, endDate: new Date(iso(30)) });
});

Deno.test("resolveEndDate: a base near the Date limit is ok:false bad_end_date, never an Invalid Date that throws later", async () => {
  // A chain stub: every filter returns itself, limit() resolves with one row whose end is the maximum Date.
  const chain = {
    select: () => chain, eq: () => chain, gt: () => chain, or: () => chain, order: () => chain,
    limit: () => Promise.resolve({ data: [{ end_date: "+275760-09-13T00:00:00.000Z" }], error: null }),
  };
  const r = await resolveEndDate({ from: () => chain }, USER, PAY, NOW, 30, on);
  assertEquals(r, { ok: false, code: "bad_end_date" });
});
