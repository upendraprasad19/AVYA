import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { generateLocalPrediction } from "./index.ts";

Deno.test("generateLocalPrediction is exported and still callable with the existing (profile, progress) signature", () => {
  const result = generateLocalPrediction(
    { current_weight_kg: 80, target_weight_kg: 75, primary_goal: "lose_fat", days_per_week: 4 },
    { detected_experience_level: "intermediate", total_workouts_done: 20, current_streak_weeks: 3, current_phase: 2 },
  );
  assertEquals(typeof result.predicted_weight_kg, "number");
  assertEquals(result.source, "local");
});

Deno.test("future-prediction no longer calls Gemini for predictions — generatePrediction and the isPro AI branch are gone", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes("async function generatePrediction")) {
    throw new Error("expected generatePrediction to be removed from future-prediction/index.ts");
  }
  if (src.includes("geminiChat(")) {
    throw new Error("expected geminiChat( to be gone from future-prediction/index.ts");
  }
  if (/isPro\s*\|\|\s*trigger\s*===\s*"onboarding"/.test(src)) {
    throw new Error("expected the isPro-gates-AI branch to be gone");
  }
});
