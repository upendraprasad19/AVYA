import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { generateFreeAlert, generateProLightAlert } from "./message.ts";

Deno.test("generateFreeAlert: 7-day streak milestone", () => {
  const msg = generateFreeAlert("Rahul", { current_streak_days: 7, today_workout_name: "Push Day" });
  assertStringIncludes(msg, "Rahul, you just hit 7 DAYS straight!");
  assertStringIncludes(msg, "Push Day is up today.");
});

Deno.test("generateFreeAlert: 30-day streak milestone", () => {
  const msg = generateFreeAlert("Rahul", { current_streak_days: 30 });
  assertStringIncludes(msg, "30 DAYS, Rahul!");
});

Deno.test("generateFreeAlert: 100 total workouts milestone", () => {
  const msg = generateFreeAlert("Rahul", { total_workouts_done: 100 });
  assertStringIncludes(msg, "100 WORKOUTS, Rahul!");
});

Deno.test("generateFreeAlert: recent PR with weight", () => {
  const msg = generateFreeAlert("Rahul", { recent_pr_exercise: "Bench Press", recent_pr_weight: 82.5 });
  assertStringIncludes(msg, "You hit a new PR on Bench Press (82.5kg) recently!");
});

Deno.test("generateFreeAlert: near goal weight", () => {
  const msg = generateFreeAlert("Rahul", { current_weight_kg: 70, target_weight_kg: 71 });
  assertStringIncludes(msg, "you're within 2kg of your goal weight!");
});

Deno.test("generateFreeAlert: default path with no milestone still returns a full greeting", () => {
  const msg = generateFreeAlert("Rahul", null);
  assertStringIncludes(msg, "Good morning Rahul!");
  assertStringIncludes(msg, "Ready to crush your goals today?");
});

Deno.test("generateProLightAlert: build_muscle goal", () => {
  const msg = generateProLightAlert("Rahul", "build_muscle");
  assertStringIncludes(msg, "Muscle is built one rep at a time");
});

Deno.test("generateProLightAlert: unrecognised goal falls back to the generic line", () => {
  const msg = generateProLightAlert("Rahul", "something_unrecognised");
  assertStringIncludes(msg, "Today is another opportunity to show up for the goals you set.");
});

Deno.test("morning-alert no longer calls generateProAlert or Gemini", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes("generateProAlert")) {
    throw new Error("expected generateProAlert to be fully removed from morning-alert/index.ts");
  }
  if (src.includes("geminiChat(")) {
    throw new Error("expected geminiChat( to be gone from morning-alert/index.ts");
  }
  if (src.includes("aiSucceeded") || src.includes("proAlerts")) {
    throw new Error("expected the dead aiSucceeded/proAlerts bookkeeping to be removed, not left at a permanent 0/false");
  }
});
