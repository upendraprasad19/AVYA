import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  countPartialDay,
  partialDayKillSwitchOn,
  partialDayWorkoutName,
} from "./partial_day_count.ts";

const row = (over: Record<string, unknown> = {}) => ({
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

Deno.test("countPartialDay: 1 of 3 logged -> planned 3, logged 1, left 2", () => {
  assertEquals(countPartialDay(row(), ["Bench Press"]), { planned: 3, logged: 1, left: 2 });
});

Deno.test("countPartialDay: 2 of 3 logged -> left 1", () => {
  assertEquals(countPartialDay(row(), ["Bench Press", "Overhead Press"]), {
    planned: 3,
    logged: 2,
    left: 1,
  });
});

Deno.test("countPartialDay: a swapped exercise counts through swapped_from", () => {
  const r = row({
    exercises: [
      { exercise_name: "Dumbbell Press", swapped_from: "Bench Press" },
      { exercise_name: "Overhead Press" },
    ],
  });
  assertEquals(countPartialDay(r, ["Bench Press"]), { planned: 2, logged: 1, left: 1 });
  assertEquals(countPartialDay(r, ["Dumbbell Press"]), { planned: 2, logged: 1, left: 1 });
});

Deno.test("countPartialDay: case and whitespace are normalised on both sides", () => {
  const r = row({ exercises: [{ exercise_name: "  Bench PRESS " }, { exercise_name: "Row" }] });
  assertEquals(countPartialDay(r, ["bench press"]), { planned: 2, logged: 1, left: 1 });
  assertEquals(countPartialDay(r, ["  BENCH press  "]), { planned: 2, logged: 1, left: 1 });
});

Deno.test("countPartialDay: duplicates in the logged iterable count once", () => {
  assertEquals(countPartialDay(row(), ["Bench Press", "bench press", "Bench Press"]), {
    planned: 3,
    logged: 1,
    left: 2,
  });
});

Deno.test("countPartialDay: accepts any Iterable (a Set)", () => {
  assertEquals(countPartialDay(row(), new Set(["Bench Press"])), { planned: 3, logged: 1, left: 2 });
});

Deno.test("countPartialDay: maps only; non-object exercise elements are not planned exercises", () => {
  const r = row({ exercises: [{ exercise_name: "Bench Press" }, "Row", 7, null, ["x"], { exercise_name: "Fly" }] });
  assertEquals(countPartialDay(r, ["Bench Press"]), { planned: 2, logged: 1, left: 1 });
});

Deno.test("countPartialDay: 0 logged -> null (today's line)", () => {
  assertEquals(countPartialDay(row(), []), null);
});

Deno.test("countPartialDay: matched == planned -> null (M55)", () => {
  assertEquals(countPartialDay(row(), ["Bench Press", "Overhead Press", "Triceps Pushdown"]), null);
});

Deno.test("countPartialDay: rest / moved / dropped / completed rows -> null (M21, M55)", () => {
  for (const over of [{ type: "rest" }, { status: "moved" }, { status: "dropped" }, { status: "completed" }]) {
    assertEquals(countPartialDay(row(over), ["Bench Press"]), null, JSON.stringify(over));
  }
});

Deno.test("countPartialDay: a null or absent status is treated as absent (not terminal)", () => {
  assertEquals(countPartialDay(row({ status: null }), ["Bench Press"]), { planned: 3, logged: 1, left: 2 });
  const r = row();
  delete (r as Record<string, unknown>).status;
  assertEquals(countPartialDay(r, ["Bench Press"]), { planned: 3, logged: 1, left: 2 });
});

Deno.test("countPartialDay: empty / zero-planned exercises -> null (M55)", () => {
  assertEquals(countPartialDay(row({ exercises: [] }), ["Bench Press"]), null);
  assertEquals(countPartialDay(row({ exercises: ["x", 3] }), ["Bench Press"]), null);
});

Deno.test("countPartialDay: a non-object row -> null", () => {
  for (const bad of [null, undefined, "x", 42, [], true]) {
    assertEquals(countPartialDay(bad, ["Bench Press"]), null);
  }
});

Deno.test("countPartialDay: stale-plan fixture [Squat, Bench] vs logged [Squat, Deadlift] -> null (M37)", () => {
  const r = row({ exercises: [{ exercise_name: "Squat" }, { exercise_name: "Bench" }] });
  assertEquals(countPartialDay(r, ["Squat", "Deadlift"]), null);
  // Without the unknown name the same plan is a plain partial day.
  assertEquals(countPartialDay(r, ["Squat"]), { planned: 2, logged: 1, left: 1 });
});

Deno.test("countPartialDay: malformed rows return null and never throw", () => {
  const bad = [
    row({ status: 5 }),
    row({ status: {} }),
    row({ exercises: "Bench Press" }),
    row({ exercises: { 0: { exercise_name: "Bench Press" } } }),
    "{\"exercises\":[{\"exercise_name\":\"Bench Press\"}]}", // double-encoded JSON-string row
    row({ exercises: [{ exercise_name: 7 }, { exercise_name: ["x"] }, { exercise_name: null }] }),
  ];
  for (const b of bad) assertEquals(countPartialDay(b, ["Bench Press"]), null);
});

Deno.test("countPartialDay: non-string logged names are ignored", () => {
  const names = ["Bench Press", 5 as unknown as string, null as unknown as string];
  assertEquals(countPartialDay(row(), names), { planned: 3, logged: 1, left: 2 });
});

Deno.test("partialDayWorkoutName: trimmed plan-day name", () => {
  assertEquals(partialDayWorkoutName({ workout_name: "  Push Day " }), "Push Day");
});

Deno.test("partialDayWorkoutName: placeholders and empty/missing -> 'your workout'", () => {
  for (const n of ["Workout", " chat workout ", "", "   ", undefined, null]) {
    assertEquals(partialDayWorkoutName({ workout_name: n }), "your workout", String(n));
  }
  assertEquals(partialDayWorkoutName({}), "your workout");
  assertEquals(partialDayWorkoutName(null), "your workout");
});

Deno.test("partialDayWorkoutName: non-string workout_name never throws (M42)", () => {
  for (const n of [42, {}, [], ["Push"], true]) {
    assertEquals(partialDayWorkoutName({ workout_name: n }), "your workout", JSON.stringify(n));
  }
});

Deno.test("partialDayWorkoutName: a name that sanitises to nothing -> fallback", () => {
  const onlyControls = String.fromCharCode(0x01, 0x02, 0x7f);
  const lineSeps = String.fromCharCode(0x2028, 0x2029, 0x85);
  assertEquals(partialDayWorkoutName({ workout_name: `${onlyControls}${lineSeps}` }), "your workout");
  assertEquals(partialDayWorkoutName({ workout_name: onlyControls }), "your workout");
});

Deno.test("partialDayWorkoutName: control characters stripped and >40 chars capped", () => {
  const name = partialDayWorkoutName({ workout_name: `Push${String.fromCharCode(0x0a)}Day` });
  assert(!name.includes(String.fromCharCode(0x0a)));
  const long = partialDayWorkoutName({ workout_name: "A".repeat(80) });
  assert(long.length <= 40, `capped, got ${long.length}`);
  assert(long.length > 0);
});

Deno.test("partialDayKillSwitchOn: exactly lowercase 'true' (M36)", () => {
  assertEquals(partialDayKillSwitchOn("true"), true);
  for (const v of ["TRUE", "True", "1", "false", "", undefined, " true"]) {
    assertEquals(partialDayKillSwitchOn(v), false, String(v));
  }
});
