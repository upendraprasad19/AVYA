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

/**
 * fake_sb has no maybeSingle; this LOCAL wrapper adds it (pattern: getPromotionStatus_test.ts).
 * It also gives `.neq("name_aliases", "{}")` its PostgREST meaning (keep only rows with a
 * non-empty array): fake_sb's own `neq` is `v !== val` and would keep every row. The base
 * `.neq` is still called, so the recorded filter list shows the call (T8).
 */
function withMaybeSingle(base: { from(t: string): any }): any {
  return {
    from(t: string) {
      const b = base.from(t);
      let aliasedOnly = false;
      const origNeq = b.neq;
      b.neq = (col: string, val: unknown) => {
        if (col === "name_aliases" && val === "{}") aliasedOnly = true;
        return origNeq(col, val);
      };
      const origThen = b.then;
      b.then = (resolve: (r: any) => void, reject?: (e: unknown) => void) =>
        origThen((r: { data: any[] }) => {
          if (!aliasedOnly) return resolve(r);
          return resolve({
            ...r,
            data: r.data.filter((x: any) => Array.isArray(x.name_aliases) && x.name_aliases.length > 0),
          });
        }, reject);
      b.maybeSingle = () =>
        b.then((r: { data: any[] }) => ({ data: r.data?.[0] ?? null, error: null }));
      return b;
    },
  };
}

function row(name: string, is_active: boolean, cue: string, name_aliases?: string[] | null) {
  return {
    name,
    name_aliases: name_aliases ?? null,
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

Deno.test("getFormCues — every exercise_library read carries the is_active filter (3 reads on the partial path)", async () => {
  // Reaches stage 2 (no exact row, no alias), so exact + alias + partial reads are recorded.
  const { calls } = await run([row("Stretch Test Beta", true, "ACTIVE")], "Stretch Test");
  const reads = calls.filter((c: FakeCall) => c.table === "exercise_library");
  assertEquals(reads.length, 3);
  for (const c of reads) {
    assert(
      c.filters.some(([op, col, val]) => op === "eq" && col === "is_active" && val === true),
      `a getFormCues read lacks eq is_active true: ${JSON.stringify(c.filters)}`,
    );
  }
});

// ---- OI-507 follow-ups (diagnose 2026-11-23-getformcues-lookup-followups) ----

function ilikeValues(calls: FakeCall[]): string[] {
  return calls
    .filter((c) => c.table === "exercise_library")
    .flatMap((c) => c.filters.filter(([op, col]) => op === "ilike" && col === "name").map(([, , v]) => String(v)));
}

Deno.test("T1 getFormCues — an alias beats the partial stage (Quad Stretch)", async () => {
  const { result } = await run(
    [
      row("Banded Quad Stretch", true, "BANDED"),
      row("Standing Quad Stretch", true, "STANDING", ["Quad Stretch"]),
    ],
    "Quad Stretch",
  );
  assertEquals(result.found, true);
  assertEquals(result.matched_via, "alias");
  assertEquals(result.exercise_name, "Standing Quad Stretch");
  assertEquals(result.coaching_cues, ["STANDING"]);
});

Deno.test("T2 getFormCues — the partial stage is deterministic (alphabetical first, listed worst-first)", async () => {
  const { result } = await run(
    [row("Goblet Squat", true, "G"), row("Squat Jump", true, "J"), row("Front Squat", true, "F")],
    "squat",
  );
  assertEquals(result.matched_via, "partial");
  assertEquals(result.exercise_name, "Front Squat");
});

Deno.test("T3 getFormCues — wildcards are escaped on BOTH ilike stages (3+ character queries)", async () => {
  const cases: Array<[string, string]> = [
    ["50%", "50\\%"],
    ["a_b", "a\\_b"],
    ["x\\y", "x\\\\y"],
    ["a*bc", "abc"],
  ];
  for (const [input, escaped] of cases) {
    const { calls } = await run([row("Zzz Unrelated", true, "U")], input);
    assertEquals(ilikeValues(calls), [escaped, `%${escaped}%`], `query ${input}`);
  }
});

Deno.test("T3 getFormCues — a 1-character % is not found and reads no partial; only-* is the required-name error", async () => {
  const rows = [row("Zzz Unrelated", true, "U")];
  const pct = await run(rows, "%");
  assertEquals(pct.result.found, false);
  assertEquals(ilikeValues(pct.calls), ["\\%"]);
  const star = await run(rows, "***");
  assertEquals(star.result.found, false);
  assertEquals(star.result.error, "exercise_name is required");
  // a 3-char query that becomes 2 characters after the * strip is stage-1-only
  const short = await run(rows, "a*b");
  assertEquals(ilikeValues(short.calls), ["ab"]);
});

Deno.test("T4 getFormCues — alias lookup: case-insensitive, padded names, null and [] tolerated, retired skipped", async () => {
  const rows = [
    row("Retired Calf Raise", false, "RETIRED", ["Donkey Calf Raise"]),
    row("Plain Row", true, "P", null),
    row("Empty Alias Row", true, "E", []),
    row("Bodyweight Standing Calf Raise", true, "CALF", ["  Donkey Calf Raise "]),
  ];
  for (const q of ["donkey calf raise", "  Donkey Calf Raise "]) {
    const { result } = await run(rows, q);
    assertEquals(result.matched_via, "alias", q);
    assertEquals(result.exercise_name, "Bodyweight Standing Calf Raise");
  }
  const blank = await run(rows, "   ");
  assertEquals(blank.result.error, "exercise_name is required");
});

/** Runs `fn` with console.error captured; restores it even when `fn` throws. */
async function captureErrors<T>(fn: () => Promise<T>): Promise<{ value: T; errors: string[] }> {
  const errors: string[] = [];
  const orig = console.error;
  console.error = (...a: unknown[]) => { errors.push(a.map(String).join(" ")); };
  try {
    return { value: await fn(), errors };
  } finally {
    console.error = orig;
  }
}

Deno.test("T4 getFormCues — the alias stage fails OPEN and says so (200-row cap, read error)", async () => {
  // 200 aliased rows: the alias read is capped, so it is SKIPPED even though "Alias 5" IS one of the
  // aliases. The answer must then come from stage 2 (the non-aliased partial target), not the alias.
  // The target sorts LAST ("Zz"): fake_sb slices to the limit before the wrapper filters, so the 200
  // aliased rows must be the first 200 by name for the capped read to see exactly 200.
  const many = Array.from({ length: 200 }, (_, i) => row(`Aliased ${String(i).padStart(3, "0")}`, true, "A", [`Alias ${i}`]));
  const capped = await captureErrors(() => run([...many, row("Zz Alias 5 Partial Target", true, "T")], "Alias 5"));
  assertEquals(capped.value.result.matched_via, "partial");
  assertEquals(capped.value.result.exercise_name, "Zz Alias 5 Partial Target");
  assert(capped.errors.some((e) => e.includes("cap")), `cap not logged: ${JSON.stringify(capped.errors)}`);

  const { sb } = fakeSb({ exercise_library: [row("Stage Two Target", true, "T")] });
  const wrapped = withMaybeSingle(sb as any);
  const failing = {
    from(t: string) {
      const b = wrapped.from(t);
      const origNeq = b.neq;
      b.neq = (c: string, v: unknown) => {
        if (c === "name_aliases") {
          const e: any = { then: (res: any) => Promise.resolve({ data: null, error: { message: "boom" } }).then(res) };
          for (const k of ["eq", "neq", "order", "limit", "select"]) e[k] = () => e;
          return e;
        }
        return origNeq(c, v);
      };
      return b;
    },
  };
  const ctx = { userId: "u1", isPro: false, sb: failing, requestId: "t" } as ToolContext;
  const failed = await captureErrors(() => getFormCuesTool.handler!(ctx, { exercise_name: "Stage Two" }));
  assertEquals(failed.value.matched_via, "partial");
  assert(failed.errors.some((e) => e.includes("alias read failed")), `error not logged: ${JSON.stringify(failed.errors)}`);
});

Deno.test("T5 getFormCues — a 2-character query reads no partial stage", async () => {
  const { result, calls } = await run([row("Rdl Test", true, "R")], "rd");
  assertEquals(result.found, false);
  assertEquals(ilikeValues(calls), ["rd"]); // exact only; no %rd% read
});

Deno.test("T6 getFormCues — not found carries the general-cues hint; found carries none", async () => {
  const miss = await run([row("Sissy Squat", true, "S")], "Zzz Nothing");
  assertEquals(miss.result.found, false);
  assert(miss.result.hint?.includes("general"), "hint names general knowledge");
  assert(miss.result.hint?.includes("same short style"), "hint names the library style");
  const hit = await run([row("Sissy Squat", true, "S")], "Sissy Squat");
  assertEquals(hit.result.hint, undefined);
});

Deno.test("T7 getFormCues — ordering per stage (pins fake_sb's code-unit order, not Postgres collation)", async () => {
  // exact: two case variants listed in the wrong order
  const exact = await run([row("Row", true, "MIXED"), row("ROW", true, "UPPER")], "row");
  assertEquals(exact.result.exercise_name, "ROW"); // "R","O","W" < "R","o","w" in code units
  // alias: two rows sharing one alias, listed in the wrong order
  const alias = await run(
    [row("Zeta Press", true, "Z", ["Shared Name"]), row("Alpha Press", true, "A", ["Shared Name"])],
    "Shared Name",
  );
  assertEquals(alias.result.exercise_name, "Alpha Press");
});

Deno.test("T8 getFormCues — the alias read carries neq name_aliases {} and eq is_active true", async () => {
  const { calls } = await run([row("Zzz Unrelated", true, "U")], "Nothing Here");
  const aliasRead = calls.find((c) => c.filters.some(([op, col]) => op === "neq" && col === "name_aliases"));
  assert(aliasRead, "no alias read recorded");
  assert(aliasRead!.filters.some(([op, col, v]) => op === "neq" && col === "name_aliases" && v === "{}"));
  assert(aliasRead!.filters.some(([op, col, v]) => op === "eq" && col === "is_active" && v === true));
});

Deno.test("T9 getFormCues — the tool description tells the model to name the matched exercise on a partial/alias match", () => {
  const d = getFormCuesTool.description;
  assert(d.includes("matched_via is 'partial' or 'alias'"), "description lacks the partial/alias sentence");
  assert(d.includes("which exercise's cues you are giving"), "description lacks the name-the-exercise instruction");
});
