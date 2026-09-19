import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { composeMessage } from "./message.ts";

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
  assertStringIncludes(msg, "Pull-up 15 reps PR");
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
