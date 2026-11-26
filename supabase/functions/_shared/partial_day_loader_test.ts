// deno-lint-ignore-file no-explicit-any
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  defaultComputeUser,
  loadPartialDays,
  type LoaderDeps,
  PLAN_FALLBACK_CHUNK_SIZE,
  realLoaderDeps,
} from "./partial_day_loader.ts";
import { workoutLogIdForDate } from "./uuid_v5.ts";

const TODAY = "2026-11-10";
const YESTERDAY = "2026-11-09";
const TOMORROW = "2026-11-11";

interface Recorded {
  table: string;
  select: string;
  filters: Array<[string, string, unknown]>;
}

/**
 * Loader-local RECORDING fake: records, per query, the select string and every
 * filter argument, AND applies eq / in / is / gte / lte to its seeded rows (so
 * a removed filter changes the output as well as the recording). `throwOn`
 * makes a table's reads throw.
 */
function recordingFake(
  tables: Record<string, any[]>,
  opts: { throwOn?: string } = {},
) {
  const queries: Recorded[] = [];
  const client = {
    from(table: string) {
      const rec: Recorded = { table, select: "", filters: [] };
      queries.push(rec);
      let rangeFrom = 0;
      let rangeTo = Number.MAX_SAFE_INTEGER;
      const b: any = {};
      b.select = (c: string) => {
        rec.select = c;
        return b;
      };
      for (const op of ["eq", "in", "is", "gte", "lte"]) {
        b[op] = (col: string, val: unknown) => {
          rec.filters.push([op, col, val]);
          return b;
        };
      }
      b.order = () => b;
      b.range = (f: number, t: number) => {
        rangeFrom = f;
        rangeTo = t;
        return b;
      };
      b.then = (resolve: (r: unknown) => void, reject?: (e: unknown) => void) => {
        if (opts.throwOn === table) {
          return Promise.resolve({ data: null, error: { message: "boom" } }).then(resolve, reject);
        }
        const rows = (tables[table] ?? []).filter((r) =>
          rec.filters.every(([op, col, val]) => {
            const v = r[col];
            if (op === "eq") return v === val;
            if (op === "in") return (val as unknown[]).includes(v);
            if (op === "is") return val === null ? v === null || v === undefined : v === val;
            if (op === "gte") return String(v) >= String(val);
            return String(v) <= String(val);
          })
        );
        const page = rows.slice(rangeFrom, Math.min(rangeTo + 1, rangeFrom + 1000));
        return Promise.resolve({ data: page, error: null }).then(resolve, reject);
      };
      return b;
    },
  };
  return { sb: client, queries };
}

const plan = (over: Record<string, unknown> = {}) => ({
  workout_name: "Push Day",
  type: "strength",
  status: "planned",
  exercises: [
    { exercise_name: "Bench Press" },
    { exercise_name: "Overhead Press" },
    { exercise_name: "Triceps Pushdown" },
  ],
  ...over,
});

async function wle(userId: string, name: string, id: number, over: Record<string, unknown> = {}) {
  return {
    id,
    user_id: userId,
    workout_log_id: await workoutLogIdForDate(TODAY),
    exercise_id: name,
    exercise_name: name,
    deleted_at: null,
    ...over,
  };
}

/** Capture console.log / console.error for a block. */
async function captureConsole<T>(fn: () => Promise<T>): Promise<{ out: T; logs: string[]; errors: string[] }> {
  const logs: string[] = [];
  const errors: string[] = [];
  const log = console.log;
  const err = console.error;
  console.log = (...a: unknown[]) => void logs.push(a.join(" "));
  console.error = (...a: unknown[]) => void errors.push(a.join(" "));
  try {
    return { out: await fn(), logs, errors };
  } finally {
    console.log = log;
    console.error = err;
  }
}

async function withEnv<T>(name: string, value: string | undefined, fn: () => Promise<T>): Promise<T> {
  const prev = Deno.env.get(name);
  if (value === undefined) Deno.env.delete(name);
  else Deno.env.set(name, value);
  try {
    return await fn();
  } finally {
    if (prev === undefined) Deno.env.delete(name);
    else Deno.env.set(name, prev);
  }
}

Deno.test("loader: one plan read and one wle read per chunk, both user-scoped; wle read has the tombstone filter and today's v5 id", async () => {
  const todayId = await workoutLogIdForDate(TODAY);
  const { sb, queries } = recordingFake({
    user_progress: [{ id: 1, user_id: "u1", today_row: plan() }],
    workout_log_exercises: [await wle("u1", "Bench Press", 10)],
  });
  const { out } = await captureConsole(() => loadPartialDays(sb, ["u1"], TODAY));
  assertEquals(out.get("u1"), { planned: 3, logged: 1, left: 2, workoutName: "Push Day" });
  // fetchAllPages reads until an EMPTY page, so each logical read is 2 requests:
  // what matters is that every request is for the ONE chunk (no second chunk).
  assertEquals(new Set(queries.map((q) => q.table)), new Set(["user_progress", "workout_log_exercises"]));
  assertEquals(
    new Set(queries.map((q) => JSON.stringify(q.filters.find((f) => f[0] === "in")![2]))).size,
    1,
  );
  const planQ = queries.find((q) => q.table === "user_progress")!;
  const wleQ = queries.find((q) => q.table === "workout_log_exercises")!;
  assertEquals(planQ.filters.find((f) => f[0] === "in")?.slice(1), ["user_id", ["u1"]]);
  assertEquals(wleQ.filters.find((f) => f[0] === "in")?.slice(1), ["user_id", ["u1"]]);
  assertEquals(wleQ.filters.find((f) => f[0] === "is"), ["is", "deleted_at", null]);
  assertEquals(wleQ.filters.find((f) => f[0] === "eq"), ["eq", "workout_log_id", todayId]);
});

Deno.test("loader: >100 users are chunked; EVERY recorded query carries .in(user_id, exactly that chunk) (M17, M31)", async () => {
  const ids = Array.from({ length: 230 }, (_, i) => `u${i}`);
  const { sb, queries } = recordingFake({ user_progress: [], workout_log_exercises: [] });
  await captureConsole(() => loadPartialDays(sb, ids, TODAY));
  const planQs = queries.filter((q) => q.table === "user_progress");
  const wleQs = queries.filter((q) => q.table === "workout_log_exercises");
  assert(planQs.length >= 3 && wleQs.length >= 3, "230 users = 3 chunks of 100");
  const expectedChunks = [ids.slice(0, 100), ids.slice(100, 200), ids.slice(200)];
  for (const qs of [planQs, wleQs]) {
    for (const q of qs) {
      const inF = q.filters.find((f) => f[0] === "in" && f[1] === "user_id");
      assert(inF, `${q.table} query lacks .in("user_id", chunk)`);
      assert(
        expectedChunks.some((c) => JSON.stringify(c) === JSON.stringify(inF![2])),
        `${q.table} .in(user_id) is not exactly one of the chunks`,
      );
    }
  }
});

Deno.test("loader: a non-requested user and a user outside the chunk never appear (rows under the SAME workout_log_id)", async () => {
  const { sb } = recordingFake({
    user_progress: [
      { id: 1, user_id: "u1", today_row: plan() },
      { id: 2, user_id: "stranger", today_row: plan() },
    ],
    workout_log_exercises: [await wle("u1", "Bench Press", 10), await wle("stranger", "Bench Press", 11)],
  });
  const { out } = await captureConsole(() => loadPartialDays(sb, ["u1"], TODAY));
  assertEquals([...out.keys()], ["u1"]);
});

Deno.test("loader: a tombstoned wle row never counts (M16)", async () => {
  const { sb } = recordingFake({
    user_progress: [{ id: 1, user_id: "u1", today_row: plan() }],
    workout_log_exercises: [
      await wle("u1", "Bench Press", 10),
      await wle("u1", "Overhead Press", 11, { deleted_at: "2026-11-10T12:00:00Z" }),
    ],
  });
  const { out } = await captureConsole(() => loadPartialDays(sb, ["u1"], TODAY));
  assertEquals(out.get("u1")?.logged, 1);
  assertEquals(out.get("u1")?.left, 2);
});

Deno.test("loader: another day's wle rows never count (workout_log_id of today, M30)", async () => {
  const { sb } = recordingFake({
    user_progress: [{ id: 1, user_id: "u1", today_row: plan() }],
    workout_log_exercises: [
      await wle("u1", "Bench Press", 10),
      await wle("u1", "Overhead Press", 11, { workout_log_id: await workoutLogIdForDate(YESTERDAY) }),
    ],
  });
  const { out } = await captureConsole(() => loadPartialDays(sb, ["u1"], TODAY));
  assertEquals(out.get("u1")?.logged, 1);
});

Deno.test("loader: exercise_id is the name when exercise_name is empty", async () => {
  const { sb } = recordingFake({
    user_progress: [{ id: 1, user_id: "u1", today_row: plan() }],
    workout_log_exercises: [await wle("u1", "x", 10, { exercise_name: "", exercise_id: "Bench Press" })],
  });
  const { out } = await captureConsole(() => loadPartialDays(sb, ["u1"], TODAY));
  assertEquals(out.get("u1")?.logged, 1);
});

Deno.test("loader: per-user attribution (M48): distinct left/workoutName per user in ONE chunk; a no-plan-row user is absent", async () => {
  const { sb } = recordingFake({
    user_progress: [
      { id: 1, user_id: "u1", today_row: plan({ workout_name: "Push Day" }) },
      {
        id: 2,
        user_id: "u2",
        today_row: plan({
          workout_name: "Pull Day",
          exercises: [{ exercise_name: "Row" }, { exercise_name: "Curl" }],
        }),
      },
    ],
    workout_log_exercises: [
      await wle("u1", "Bench Press", 10),
      await wle("u2", "Row", 11),
      await wle("u3", "Row", 12),
    ],
  });
  const { out } = await captureConsole(() => loadPartialDays(sb, ["u1", "u2", "u3"], TODAY));
  assertEquals(out.get("u1"), { planned: 3, logged: 1, left: 2, workoutName: "Push Day" });
  assertEquals(out.get("u2"), { planned: 2, logged: 1, left: 1, workoutName: "Pull Day" });
  assertEquals(out.has("u3"), false);
});

Deno.test("loader: the log line carries users / counted / null, right numbers", async () => {
  const { sb } = recordingFake({
    user_progress: [
      { id: 1, user_id: "u1", today_row: plan() },
      { id: 2, user_id: "u2", today_row: plan() },
    ],
    workout_log_exercises: [await wle("u1", "Bench Press", 10)],
  });
  const { logs } = await captureConsole(() => loadPartialDays(sb, ["u1", "u2", "u3"], TODAY));
  assert(logs.includes("[partial-day] users=3 counted=1 null=2"), logs.join("|"));
  assert(!logs.some((l) => l.includes("count-threw")));
});

Deno.test("loader: a malformed row for ONE user does not affect the others", async () => {
  const { sb } = recordingFake({
    user_progress: [
      { id: 1, user_id: "u1", today_row: plan() },
      { id: 2, user_id: "u2", today_row: plan({ exercises: "nope", status: 5 }) },
      { id: 3, user_id: "u3", today_row: "{\"double\":\"encoded\"}" },
    ],
    workout_log_exercises: [
      await wle("u1", "Bench Press", 10),
      await wle("u2", "Bench Press", 11),
      await wle("u3", "Bench Press", 12),
    ],
  });
  const { out } = await captureConsole(() => loadPartialDays(sb, ["u1", "u2", "u3"], TODAY));
  assertEquals([...out.keys()], ["u1"]);
});

Deno.test("loader: workout_name 42 and {} yield the 'your workout' fallback name (M42)", async () => {
  const { sb } = recordingFake({
    user_progress: [
      { id: 1, user_id: "u1", today_row: plan({ workout_name: 42 }) },
      { id: 2, user_id: "u2", today_row: plan({ workout_name: {} }) },
    ],
    workout_log_exercises: [await wle("u1", "Bench Press", 10), await wle("u2", "Bench Press", 11)],
  });
  const { out } = await captureConsole(() => loadPartialDays(sb, ["u1", "u2"], TODAY));
  assertEquals(out.get("u1")?.workoutName, "your workout");
  assertEquals(out.get("u2")?.workoutName, "your workout");
});

Deno.test("loader: an injected computeUser that throws for ONE user leaves the others intact and counts count-threw (M38)", async () => {
  const deps: LoaderDeps = {
    ...realLoaderDeps(),
    computeUser: (row, names) => {
      if ((row as any).__boom) throw new Error("x");
      return defaultComputeUser(row, names);
    },
  };
  const seeded = recordingFake({
    user_progress: [
      { id: 1, user_id: "u1", today_row: plan() },
      { id: 2, user_id: "boom", today_row: { ...plan(), __boom: true } },
      { id: 3, user_id: "u3", today_row: plan() },
    ],
    workout_log_exercises: [
      await wle("u1", "Bench Press", 10),
      await wle("boom", "Bench Press", 11),
      await wle("u3", "Bench Press", 12),
    ],
  });
  const { out, logs } = await captureConsole(() => loadPartialDays(seeded.sb, ["u1", "boom", "u3"], TODAY, deps));
  assertEquals([...out.keys()].sort(), ["u1", "u3"]);
  assert(logs.includes("[partial-day] users=3 counted=2 null=1"), logs.join("|"));
  assert(logs.includes("[partial-day] count-threw=1"), logs.join("|"));
});

Deno.test("loader: a throwing read returns an empty map (no throw) and logs once without row data (M29)", async () => {
  for (const throwOn of ["user_progress", "workout_log_exercises"]) {
    const { sb } = recordingFake({
      user_progress: [{ id: 1, user_id: "u1", today_row: plan() }],
      workout_log_exercises: [await wle("u1", "Bench Press", 10)],
    }, { throwOn });
    const { out, errors } = await captureConsole(() => loadPartialDays(sb, ["u1"], TODAY));
    assertEquals(out.size, 0, throwOn);
    assertEquals(errors.length, 1);
    assert(errors[0].startsWith("[partial-day] read failed:"));
    assert(!errors[0].includes("u1"));
  }
});

Deno.test("loader: a throw from workoutLogIdForDate and from the grouping step also yields an empty map, not a rejection (B4-F4)", async () => {
  const { sb } = recordingFake({
    user_progress: [{ id: 1, user_id: "u1", today_row: plan() }],
    workout_log_exercises: [await wle("u1", "Bench Press", 10)],
  });
  const idThrows: LoaderDeps = {
    ...realLoaderDeps(),
    workoutLogIdForDate: () => Promise.reject(new Error("no id")),
  };
  const { out } = await captureConsole(() => loadPartialDays(sb, ["u1"], TODAY, idThrows));
  assertEquals(out.size, 0);

  // Grouping step: a plan row whose user_id getter throws.
  const poisoned = {
    id: 1,
    get user_id(): string {
      throw new Error("poisoned row");
    },
    today_row: plan(),
  };
  const { sb: sb2 } = recordingFake({ user_progress: [poisoned], workout_log_exercises: [] });
  const { out: out2 } = await captureConsole(() => loadPartialDays(sb2, ["u1"], TODAY));
  assertEquals(out2.size, 0);
});

Deno.test("loader: the kill switch returns an empty map without any read (M27); TRUE and 1 do not switch it off", async () => {
  const seed = async () => ({
    user_progress: [{ id: 1, user_id: "u1", today_row: plan() }],
    workout_log_exercises: [await wle("u1", "Bench Press", 10)],
  });
  const on = recordingFake(await seed());
  const r1 = await withEnv("DISABLE_PARTIAL_DAY_REMINDER", "true", () => loadPartialDays(on.sb, ["u1"], TODAY));
  assertEquals(r1.size, 0);
  assertEquals(on.queries.length, 0);
  for (const v of ["TRUE", "1", "false", ""]) {
    const f = recordingFake(await seed());
    const r = await withEnv(
      "DISABLE_PARTIAL_DAY_REMINDER",
      v,
      () => captureConsole(() => loadPartialDays(f.sb, ["u1"], TODAY)),
    );
    assertEquals(r.out.size, 1, `value ${JSON.stringify(v)} must leave the loader ON`);
  }
});

Deno.test("loader: empty userIds returns an empty map with no read", async () => {
  const { sb, queries } = recordingFake({});
  const out = await loadPartialDays(sb, [], TODAY);
  assertEquals(out.size, 0);
  assertEquals(queries.length, 0);
});

// ── date key (A4-F1, M47) ──────────────────────────────────────────────────

Deno.test("loader: the PRIMARY select string contains schedule_<todayIST> exactly (M47)", async () => {
  const { sb, queries } = recordingFake({ user_progress: [], workout_log_exercises: [] });
  await captureConsole(() => loadPartialDays(sb, ["u1"], TODAY));
  const sel = queries.find((q) => q.table === "user_progress")!.select;
  assert(sel.includes(`schedule_${TODAY}`), sel);
  assert(!sel.includes(`schedule_${YESTERDAY}`) && !sel.includes(`schedule_${TOMORROW}`), sel);
});

Deno.test("loader: FALLBACK path picks TODAY's key from a multi-day schedules object; yesterday-only gives no entry", async () => {
  const fallback: LoaderDeps = { ...realLoaderDeps(), planRead: "fallback" };
  const { sb, queries } = recordingFake({
    user_progress: [
      {
        id: 1,
        user_id: "u1",
        schedules: {
          [`schedule_${YESTERDAY}`]: plan({ workout_name: "Yesterday" }),
          [`schedule_${TODAY}`]: plan({ workout_name: "Today" }),
          [`schedule_${TOMORROW}`]: plan({ workout_name: "Tomorrow" }),
        },
      },
      { id: 2, user_id: "u2", schedules: { [`schedule_${YESTERDAY}`]: plan() } },
    ],
    workout_log_exercises: [await wle("u1", "Bench Press", 10), await wle("u2", "Bench Press", 11)],
  });
  const { out } = await captureConsole(() => loadPartialDays(sb, ["u1", "u2"], TODAY, fallback));
  assertEquals(out.get("u1")?.workoutName, "Today");
  assertEquals(out.has("u2"), false);
  assert(queries.find((q) => q.table === "user_progress")!.select.includes("plan_json->schedules"));
});

Deno.test("loader: the fallback reads at most PLAN_FALLBACK_CHUNK_SIZE (10) users per request", async () => {
  assertEquals(PLAN_FALLBACK_CHUNK_SIZE, 10);
  const ids = Array.from({ length: 25 }, (_, i) => `u${i}`);
  const fallback: LoaderDeps = { ...realLoaderDeps(), planRead: "fallback" };
  const { sb, queries } = recordingFake({ user_progress: [], workout_log_exercises: [] });
  await captureConsole(() => loadPartialDays(sb, ids, TODAY, fallback));
  const planQs = queries.filter((q) => q.table === "user_progress");
  assertEquals(planQs.length, 3);
  for (const q of planQs) {
    const inF = q.filters.find((f) => f[0] === "in")!;
    assert((inF[2] as string[]).length <= 10);
  }
});

Deno.test("loader: the default deps are the primary read, the default compute fn and the real v5 id", () => {
  const d = realLoaderDeps();
  assertEquals(d.planRead, "primary");
  assert(d.computeUser === defaultComputeUser);
  assert(d.workoutLogIdForDate === workoutLogIdForDate);
});
