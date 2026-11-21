// deno-lint-ignore-file no-explicit-any
// getFormCues must never answer from a retired exercise_library row
// (is_active = false) — OI-438 / OI-469, diagnose 2026-11-13-getformcues-inactive-rows.
//
// Retired rows are hidden, never deleted (workout_logs / template_exercises hold
// FKs to them), so the READER has to skip them on BOTH stages. Every fixture lists
// the RETIRED row FIRST: an unfiltered `limit(1)` returns it, so a missing filter
// shows up as the retired row's cues. The two rows' cues differ so the result names
// its source row.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { getFormCuesTool } from "../exercise/getFormCues.ts";
import { fakeSb, type FakeCall } from "./fake_sb.ts";
import type { ToolContext } from "../types.ts";

/** fake_sb has no maybeSingle; this LOCAL wrapper adds it (pattern: getPromotionStatus_test.ts). */
function withMaybeSingle(base: { from(t: string): any }): any {
  return {
    from(t: string) {
      const b = base.from(t);
      b.maybeSingle = () =>
        b.then((r: { data: any[] }) => ({ data: r.data?.[0] ?? null, error: null }));
      return b;
    },
  };
}

function row(name: string, is_active: boolean, cue: string) {
  return {
    name,
    is_active,
    coaching_cues: [cue],
    common_mistakes: [],
    instructions: null,
    primary_muscles: [],
    secondary_muscles: [],
    difficulty_level: null,
    logging_type: null,
  };
}

function run(rows: any[], exercise_name: string) {
  const { sb, calls } = fakeSb({ exercise_library: rows });
  const ctx = { userId: "u1", isPro: false, sb: withMaybeSingle(sb as any), requestId: "t" } as ToolContext;
  return getFormCuesTool.handler!(ctx, { exercise_name }).then((result) => ({ result, calls }));
}

Deno.test("getFormCues — exact name with a retired twin returns the ACTIVE row", async () => {
  const { result } = await run(
    [row("Sissy Squat", false, "RETIRED"), row("Sissy Squat", true, "ACTIVE")],
    "Sissy Squat",
  );
  assertEquals(result.found, true);
  assertEquals(result.matched_via, "exact");
  assertEquals(result.coaching_cues, ["ACTIVE"]);
});

Deno.test("getFormCues — a retired-only name is not found on either stage", async () => {
  const { result } = await run([row("Pigeon Pose", false, "RETIRED")], "Pigeon Pose");
  assertEquals(result.found, false);
});

Deno.test("getFormCues — retired exact name falls through to the live containing name", async () => {
  const { result } = await run(
    [row("Lat Stretch", false, "RETIRED"), row("Kneeling Lat Stretch", true, "ACTIVE")],
    "Lat Stretch",
  );
  assertEquals(result.found, true);
  assertEquals(result.matched_via, "partial");
  assertEquals(result.exercise_name, "Kneeling Lat Stretch");
  assertEquals(result.coaching_cues, ["ACTIVE"]);
});

Deno.test("getFormCues — partial stage skips a retired match listed first", async () => {
  const { result } = await run(
    [row("Stretch Test Alpha", false, "RETIRED"), row("Stretch Test Beta", true, "ACTIVE")],
    "Stretch Test",
  );
  assertEquals(result.found, true);
  assertEquals(result.matched_via, "partial");
  assertEquals(result.exercise_name, "Stretch Test Beta");
});

Deno.test("getFormCues — no match at all is not found", async () => {
  const { result } = await run([row("Sissy Squat", true, "ACTIVE")], "Zzz Nothing");
  assertEquals(result.found, false);
});

Deno.test("getFormCues — both queries carry the is_active filter", async () => {
  // Reaches stage 2 (no exact row), so BOTH exercise_library reads are recorded.
  const { calls } = await run([row("Stretch Test Beta", true, "ACTIVE")], "Stretch Test");
  const reads = calls.filter((c: FakeCall) => c.table === "exercise_library");
  assertEquals(reads.length, 2);
  for (const c of reads) {
    assert(
      c.filters.some(([op, col, val]) => op === "eq" && col === "is_active" && val === true),
      `a getFormCues read lacks eq is_active true: ${JSON.stringify(c.filters)}`,
    );
  }
});
