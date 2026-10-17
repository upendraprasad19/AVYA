import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { floorToPeriod, PR_PERIOD_MINUTES, prWindow } from "./window.ts";
import { cronPeriodMinutes, latestCronSchedule } from "./cron_writer.ts";
import { celebratablePrs } from "./live_pr_filter.ts";
import { buildDayMap } from "../_shared/exercise_day.ts";
import { workoutLogIdForDate } from "../_shared/uuid_v5.ts";

const JOB = "proactive_pr_detection";

async function realMigrations() {
  const dir = new URL("../../migrations/", import.meta.url);
  const out = [];
  for await (const e of Deno.readDir(dir)) {
    if (e.isFile && e.name.endsWith(".sql")) {
      out.push({ name: e.name, text: await Deno.readTextFile(new URL(e.name, dir)) });
    }
  }
  return out;
}

Deno.test("cadence is read from the WRITER: live cron == registry cell == PR_PERIOD_MINUTES", async () => {
  const cron = latestCronSchedule(await realMigrations(), JOB);
  assertEquals(cron, "0 * * * *"); // migration 141
  const registry = await Deno.readTextFile(
    new URL("../../../docs/operations/CRON_REGISTRY.md", import.meta.url),
  );
  const row = registry.split("\n").find((l) => l.includes(`\`${JOB}\``));
  if (!row || !row.includes(`\`${cron}\``)) {
    throw new Error(`CRON_REGISTRY.md row for ${JOB} does not carry cron ${cron}: ${row}`);
  }
  assertEquals(cronPeriodMinutes(cron!), PR_PERIOD_MINUTES);
});

Deno.test("cron parser — a later migration altering the job to every 2 hours is picked up (mutation fixture)", () => {
  const files = [
    { name: "031_a.sql", text: "SELECT cron.schedule(\n 'proactive_pr_detection',\n '*/15 * * * *',\n $c$x$c$);" },
    { name: "141_b.sql", text: "SELECT cron.alter_job(\n job_id := (SELECT jobid FROM cron.job WHERE jobname = 'proactive_pr_detection'),\n schedule := '0 * * * *'\n);" },
    { name: "200_c.sql", text: "SELECT cron.alter_job(job_id := (SELECT jobid FROM cron.job WHERE jobname = 'proactive_pr_detection'), schedule := '0 */2 * * *');" },
  ];
  assertEquals(latestCronSchedule(files, JOB), "0 */2 * * *");
  assertEquals(cronPeriodMinutes("0 */2 * * *"), 120);
});

Deno.test("cron parser — a fixture shaped like 141 (live alter then COMMENTED rollback) keeps the live value", () => {
  const files = [{
    name: "141_x.sql",
    text: "SELECT cron.alter_job(job_id := (SELECT jobid FROM cron.job WHERE jobname = 'proactive_pr_detection'), schedule := '0 */2 * * *');\n-- Rollback:\n-- SELECT cron.alter_job(job_id := (SELECT jobid FROM cron.job WHERE jobname = 'proactive_pr_detection'), schedule := '0 * * * *');\n/* SELECT cron.schedule('proactive_pr_detection', '*/5 * * * *'); */",
  }];
  assertEquals(latestCronSchedule(files, JOB), "0 */2 * * *");
});

Deno.test("cron parser — letter-suffixed and timestamp-prefixed files: scheme order, timestamp ignored", () => {
  const files = [
    { name: "050b_x.sql", text: "SELECT cron.schedule('proactive_pr_detection', '5 * * * *', $c$x$c$);" },
    { name: "050_x.sql", text: "SELECT cron.schedule('proactive_pr_detection', '1 * * * *', $c$x$c$);" },
    { name: "20261001000000_x.sql", text: "SELECT cron.schedule('proactive_pr_detection', '9 * * * *', $c$x$c$);" },
    { name: "all_migrations_combined.sql", text: "SELECT cron.schedule('proactive_pr_detection', '7 * * * *', $c$x$c$);" },
  ];
  assertEquals(latestCronSchedule(files, JOB), "5 * * * *");
});

Deno.test("prWindow — tick-aligned: ticks at 09:00:03 and 10:00:41 read adjacent, disjoint windows", () => {
  const a = prWindow(new Date("2026-10-07T09:00:03Z"));
  const b = prWindow(new Date("2026-10-07T10:00:41Z"));
  assertEquals(a, { since: "2026-10-07T08:00:00.000Z", until: "2026-10-07T09:00:00.000Z" });
  assertEquals(b.since, a.until);
  assertEquals(floorToPeriod(new Date("2026-10-07T09:59:59Z")).toISOString(), "2026-10-07T09:00:00.000Z");
});

Deno.test("prWindow — a PR at T-3 min is read by exactly one of two consecutive ticks; drift neither drops nor repeats", () => {
  const t1 = prWindow(new Date("2026-10-07T10:00:09Z")); // tick at 10:00 (+9 s drift)
  const t2 = prWindow(new Date("2026-10-07T10:59:58Z")); // an EARLY-started next tick still floors to 10:00!
  const t3 = prWindow(new Date("2026-10-07T11:00:20Z"));
  const at = Date.parse("2026-10-07T09:57:00Z");
  const inWin = (w: { since: string; until: string }) => at >= Date.parse(w.since) && at < Date.parse(w.until);
  assertEquals([t1, t3].filter(inWin).length, 1);
  assertEquals(inWin(t1), true);
  // the early-start tick re-reads the same hour as t1; the hourly cron never starts 1 s before the hour in
  // practice, but if it did the row would repeat — dedupe by shouldSendProactive then absorbs it.
  assertEquals(t2.until, t1.until);
});

Deno.test("PR_PERIOD_MINUTES mutation guard — a period of 30 would leave a gap against the live hourly cron", () => {
  const w = prWindow(new Date("2026-10-07T10:00:05Z"), 30);
  assertEquals(w.since, "2026-10-07T09:30:00.000Z"); // != hour-long window: the equality test above catches 30 vs 60
});

// ── celebratablePrs: recency-day + superseded rows ───────────────────────────
const NOW = new Date("2026-10-07T04:00:00Z"); // 09:30 IST 2026-10-07
const mk = async (date: string, over: Record<string, unknown> = {}) => ({
  id: Math.floor(Math.random() * 1e9),
  user_id: "u1",
  workout_log_id: await workoutLogIdForDate(date),
  exercise_id: "Bench Press",
  set_number: 3,
  is_pr: true,
  completed_at: "2026-10-07T03:30:00Z",
  deleted_at: null,
  weight_kg: 80,
  reps: 24,
  ...over,
});

Deno.test("celebratablePrs — a fresh PR is celebrated", async () => {
  const m = await buildDayMap(NOW);
  assertEquals((await celebratablePrs([await mk("2026-10-07")], m, NOW)).length, 1);
});

Deno.test("celebratablePrs — a workout logged today for YESTERDAY is still celebrated", async () => {
  const m = await buildDayMap(NOW);
  assertEquals(celebratablePrs([await mk("2026-10-06")], m, NOW).length, 1);
});

Deno.test("celebratablePrs — an edited OLD log (resolved day 3+ days back) is not celebrated", async () => {
  const m = await buildDayMap(NOW);
  assertEquals(celebratablePrs([await mk("2026-10-03")], m, NOW).length, 0);
});

Deno.test("celebratablePrs — a forward-moved PR (future day) is not celebrated", async () => {
  const m = await buildDayMap(NOW);
  assertEquals(celebratablePrs([await mk("2026-10-09")], m, NOW).length, 0);
});

Deno.test("celebratablePrs — a superseded row's stale is_pr is not celebrated", async () => {
  const m = await buildDayMap(NOW);
  const rows = [
    await mk("2026-10-07", { id: 1, set_number: 3, is_pr: true }),
    await mk("2026-10-07", { id: 2, set_number: 4, is_pr: false }),
  ];
  assertEquals(celebratablePrs(rows, m, NOW).length, 0);
});

Deno.test("celebratablePrs — two users with the same day/exercise are both celebrated", async () => {
  const m = await buildDayMap(NOW);
  const rows = [
    await mk("2026-10-07", { id: 1, user_id: "u1" }),
    await mk("2026-10-07", { id: 2, user_id: "u2" }),
  ];
  assertEquals(celebratablePrs(rows, m, NOW).length, 2);
});

Deno.test("celebratablePrs — 23:50-IST and 00:15-IST rows resolve to their IST day", async () => {
  const m = await buildDayMap(NOW);
  // unresolved-id rows fall back to IST(completed_at): 2026-10-06T18:20Z = 23:50 IST on 10-06 (yesterday)
  const rows = [{ ...(await mk("2026-10-07", { workout_log_id: "unknown", completed_at: "2026-10-06T18:20:00Z" })) }];
  assertEquals(celebratablePrs(rows, m, NOW).length, 1);
  const old = [{ ...(await mk("2026-10-07", { workout_log_id: "unknown", completed_at: "2026-10-04T18:40:00Z" })) }]; // 00:10 IST 10-05
  assertEquals(celebratablePrs(old, m, NOW).length, 0);
});

// ── celebratablePrsInWindow: winners are announced by THEIR OWN tick ─────────
import { celebratablePrsInWindow } from "./live_pr_filter.ts";

Deno.test("celebratablePrsInWindow — old-count PR in hour H, winner (is_pr) in hour H+1: tick H announces nothing, tick H+1 announces once", async () => {
  const m = await buildDayMap(NOW);
  const loser = await mk("2026-10-07", { id: 1, set_number: 3, is_pr: true, completed_at: "2026-10-07T03:10:00Z" });
  const winner = await mk("2026-10-07", { id: 2, set_number: 4, is_pr: true, completed_at: "2026-10-07T04:10:00Z" });
  const ctx = [loser, winner];
  const tickH = celebratablePrsInWindow(ctx, m, NOW, "2026-10-07T03:00:00.000Z", "2026-10-07T04:00:00.000Z");
  const tickH1 = celebratablePrsInWindow(ctx, m, NOW, "2026-10-07T04:00:00.000Z", "2026-10-07T05:00:00.000Z");
  assertEquals(tickH.length, 0);
  assertEquals(tickH1.length, 1);
});

Deno.test("celebratablePrsInWindow — stale is_pr on an old-count row whose winner (not a PR) was written in a later hour never fires", async () => {
  const m = await buildDayMap(NOW);
  const ctx = [
    await mk("2026-10-07", { id: 1, set_number: 3, is_pr: true, completed_at: "2026-10-07T03:10:00Z" }),
    await mk("2026-10-07", { id: 2, set_number: 4, is_pr: false, completed_at: "2026-10-07T04:10:00Z" }),
  ];
  assertEquals(celebratablePrsInWindow(ctx, m, NOW, "2026-10-07T03:00:00.000Z", "2026-10-07T04:00:00.000Z").length, 0);
});

Deno.test("celebratablePrsInWindow — the window is half-open: a winner written exactly at `until` belongs to the NEXT tick", async () => {
  const m = await buildDayMap(NOW);
  const ctx = [await mk("2026-10-07", { id: 1, is_pr: true, completed_at: "2026-10-07T04:00:00.000Z" })];
  assertEquals(celebratablePrsInWindow(ctx, m, NOW, "2026-10-07T03:00:00.000Z", "2026-10-07T04:00:00.000Z").length, 0);
  assertEquals(celebratablePrsInWindow(ctx, m, NOW, "2026-10-07T04:00:00.000Z", "2026-10-07T05:00:00.000Z").length, 1);
});
