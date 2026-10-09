import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { composeMessage } from "./message.ts";
import { excludeDeletedPrs } from "./live_pr_filter.ts";

Deno.test("composeMessage: single PR with weight uses the approved copy", () => {
  const msg = composeMessage("Rahul", [
    { exercise_id: "Bench Press", weight_kg: 82.5, reps: null },
  ]);
  assertEquals(msg, "Rahul — new Bench Press 82.5kg PR. Keep going 💪.");
});

Deno.test("composeMessage: single PR with reps only (no weight) falls back to reps phrasing", () => {
  const msg = composeMessage("Rahul", [
    { exercise_id: "Pull-up", weight_kg: null, reps: 15 },
  ]);
  assertStringIncludes(msg, "Pull-up 15 total reps PR");
});

Deno.test("composeMessage: two PRs uses the approved two-PR copy", () => {
  const msg = composeMessage("Rahul", [
    { exercise_id: "Bench Press", weight_kg: 82.5, reps: null },
    { exercise_id: "Squat", weight_kg: 110, reps: null },
  ]);
  assertEquals(msg, "Rahul — new PRs: Bench Press 82.5kg, Squat 110kg. Strong session.");
});

Deno.test("composeMessage: three or more PRs shows the +N more tail", () => {
  const msg = composeMessage("Rahul", [
    { exercise_id: "Bench Press", weight_kg: 82.5, reps: null },
    { exercise_id: "Squat", weight_kg: 110, reps: null },
    { exercise_id: "Deadlift", weight_kg: 140, reps: null },
  ]);
  assertEquals(msg, "Rahul — new PRs: Bench Press 82.5kg, Squat 110kg +1 more. Strong session.");
});

Deno.test("composeMessage: empty PR list returns empty string", () => {
  assertEquals(composeMessage("Rahul", []), "");
});

Deno.test("pr-detection no longer calls Gemini — the geminiChat import and call are gone", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes("geminiChat(")) {
    throw new Error("expected geminiChat( to be gone from pr-detection/index.ts");
  }
  if (src.includes("import { geminiChat")) {
    throw new Error("expected the geminiChat import to be removed from pr-detection/index.ts");
  }
});

// OI-246 follow-up (B-pass review A, round 3, 2026-09-29). Mirrors
// weekly-recalc/index_test.ts's excludeDeletedLogs test group exactly.

Deno.test("excludeDeletedPrs: drops a row with a non-null deleted_at", () => {
  const rows = [
    { id: "live-1", deleted_at: null },
    { id: "dead-1", deleted_at: "2026-09-29T00:00:00Z" },
  ];
  const kept = excludeDeletedPrs(rows);
  assertEquals(kept.map((r) => r.id), ["live-1"]);
});

Deno.test("excludeDeletedPrs: keeps every row when none are deleted", () => {
  const rows = [
    { id: "a", deleted_at: null },
    { id: "b", deleted_at: null },
  ];
  assertEquals(excludeDeletedPrs(rows).length, 2);
});

Deno.test("excludeDeletedPrs: drops every row when all are deleted", () => {
  const rows = [
    { id: "a", deleted_at: "2026-09-29T00:00:00Z" },
    { id: "b", deleted_at: "2026-09-28T00:00:00Z" },
  ];
  assertEquals(excludeDeletedPrs(rows), []);
});

Deno.test("excludeDeletedPrs: empty input yields empty output", () => {
  assertEquals(excludeDeletedPrs([]), []);
});

// Wiring — the fetch must select deleted_at, and the fetched rows must be
// routed through excludeDeletedPrs before grouping/composing. Source-grep
// because the main handler makes a live Supabase call and is not otherwise
// unit-tested at the Deno level (same scope note as weekly-recalc's own
// wiring test).
Deno.test("pr-detection: selects deleted_at and filters through excludeDeletedPrs before grouping", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (!src.includes("deleted_at: string | null")) {
    throw new Error("expected the workout_log_exercises fetch to select+type deleted_at");
  }
  if (!src.includes("completed_at, deleted_at\"")) {
    throw new Error("expected the workout_log_exercises select column list to include deleted_at");
  }
  if (!src.includes("excludeDeletedPrs(rawRows)")) {
    throw new Error("expected rawRows to be routed through excludeDeletedPrs(rawRows) before grouping");
  }
  const filterIdx = src.indexOf("celebratablePrsInWindow(");
  const groupIdx = src.indexOf("const prsByUser = new Map");
  if (filterIdx === -1 || groupIdx === -1 || filterIdx > groupIdx) {
    throw new Error("expected excludeDeletedPrs to run BEFORE grouping by user, not after");
  }
});

// PRESENCE-ONLY pin (index.ts calls Deno.serve at import; the window arithmetic itself is
// behaviourally tested in window_test.ts): the read is bounded by the tick-aligned half-open
// window — `>= since` and `< until`, never `<= until`, which would let two ticks read one row.
Deno.test("pr-detection: the read is bounded by [since, until) from prWindow(now)", async () => {
  const src = (await Deno.readTextFile(new URL("./index.ts", import.meta.url)))
    .replace(/\/\*[\s\S]*?\*\//g, "").split("\n").map((l) => l.replace(/\/\/.*$/, "")).join("\n");
  if (!src.includes("prWindow(now)")) throw new Error("expected the window to come from prWindow(now)");
  if (!src.includes('.gte("completed_at", since)')) throw new Error("expected .gte(completed_at, since)");
  if (!src.includes('.lt("completed_at", until)')) throw new Error("expected the half-open .lt(completed_at, until)");
  if (src.includes('.lte("completed_at"')) throw new Error("until must be exclusive");
  if (src.includes('.eq("is_pr", true)')) throw new Error("is_pr must not be filtered server-side (dedupe first)");
});
