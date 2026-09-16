import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { generateLocalPrediction } from "./index.ts";
import {
  linearRegressionForecast,
  predictLift,
  predictStreakWeeks,
  predictWeight,
} from "./trend.ts";

Deno.test("linearRegressionForecast: perfect line, forecast beyond the data", () => {
  // y = 70 - 0.1*x  (losing 0.1kg per day)
  const points = [{ x: 0, y: 70 }, { x: 10, y: 69 }, { x: 20, y: 68 }, { x: 30, y: 67 }];
  const result = linearRegressionForecast(points, 90 - 30); // 90 days from the LAST point (x=30)
  // forecast at x=90: 70 - 0.1*90 = 61
  assertEquals(result !== null && Math.abs(result - 61) < 0.01, true);
});

Deno.test("linearRegressionForecast: fewer than 2 points returns null", () => {
  assertEquals(linearRegressionForecast([{ x: 0, y: 70 }], 90), null);
  assertEquals(linearRegressionForecast([], 90), null);
});

Deno.test("predictWeight: sufficient history (>=5 rows, >=14 days) uses the regression, not the fallback", () => {
  const rows = [
    { date: "2026-08-01", weight_kg: 80 },
    { date: "2026-08-06", weight_kg: 79.5 },
    { date: "2026-08-11", weight_kg: 79 },
    { date: "2026-08-16", weight_kg: 78.5 },
    { date: "2026-08-21", weight_kg: 78 },
  ];
  const result = predictWeight(rows, 999 /* obviously-not-fallback sentinel */);
  assertEquals(result === 999, false);
});

Deno.test("predictWeight: insufficient history (only 3 rows) returns the fallback verbatim", () => {
  const rows = [
    { date: "2026-08-01", weight_kg: 80 },
    { date: "2026-08-06", weight_kg: 79.5 },
    { date: "2026-08-11", weight_kg: 79 },
  ];
  assertEquals(predictWeight(rows, 76.5), 76.5);
});

Deno.test("predictWeight: enough ROWS but spanning under 14 days still falls back (dense logging over a short window is not a trend)", () => {
  const rows = [
    { date: "2026-08-01", weight_kg: 80 },
    { date: "2026-08-02", weight_kg: 79.9 },
    { date: "2026-08-03", weight_kg: 79.8 },
    { date: "2026-08-04", weight_kg: 79.7 },
    { date: "2026-08-05", weight_kg: 79.6 },
  ];
  assertEquals(predictWeight(rows, 76.5), 76.5);
});

Deno.test("predictLift: 2 PRs spanning >=7 days uses the regression", () => {
  const rows = [
    { completed_at: "2026-07-01T00:00:00Z", weight_kg: 80 },
    { completed_at: "2026-08-01T00:00:00Z", weight_kg: 85 },
  ];
  const result = predictLift(rows, 999);
  assertEquals(result === 999, false);
});

Deno.test("predictLift: fewer than 2 PRs falls back", () => {
  assertEquals(predictLift([{ completed_at: "2026-08-01T00:00:00Z", weight_kg: 80 }], 60), 60);
  assertEquals(predictLift([], 60), 60);
});

Deno.test("predictWeight: a plausible short-term dip does not extrapolate to a physically impossible 90-day forecast", () => {
  // B-pass finding 2 (247d945d1ba0): this exact fixture (5 weigh-ins, 70->65kg
  // over 14 days) extrapolated UNCLAMPED to 32.2kg -- below any realistic
  // human body weight. Clamp bounds it to within 30% of the LAST observed
  // weight (65kg): floor 45.5kg.
  const rows = [
    { date: "2026-08-01", weight_kg: 70 },
    { date: "2026-08-04", weight_kg: 68.7 },
    { date: "2026-08-08", weight_kg: 67.2 },
    { date: "2026-08-11", weight_kg: 66.0 },
    { date: "2026-08-15", weight_kg: 65.0 },
  ];
  const result = predictWeight(rows, 999);
  assertEquals(result, 45.5);
});

Deno.test("predictLift: a plausible short-term decline does not extrapolate to a negative lift", () => {
  // B-pass finding 2 (247d945d1ba0): this exact fixture (2 PRs, 100->80kg
  // 8 days apart) extrapolated UNCLAMPED to -145kg. Clamp floors at 0.
  const rows = [
    { completed_at: "2026-08-01T00:00:00Z", weight_kg: 100 },
    { completed_at: "2026-08-09T00:00:00Z", weight_kg: 80 },
  ];
  const result = predictLift(rows, 60);
  assertEquals(result, 0);
  assertEquals(result >= 0, true);
});

Deno.test("predictStreakWeeks: maps adherence rate onto the existing 13-week ceiling", () => {
  assertEquals(predictStreakWeeks(1.0), 13);
  assertEquals(predictStreakWeeks(0.5), 7); // round(0.5*13) = round(6.5) = 7
  assertEquals(predictStreakWeeks(0), 0);
});

Deno.test("predictStreakWeeks: null (insufficient data / error sentinel) falls back to the given flat value", () => {
  assertEquals(predictStreakWeeks(null, 8), 8);
});

Deno.test("generateLocalPrediction falls back to the static formulas when there is no history at all", async () => {
  let call = 0;
  const stubSupabase = {
    from() {
      return {
        select() { return this; },
        eq() { return this; },
        gte() { return this; },
        ilike() { return this; },
        order() { call++; return Promise.resolve({ data: [] }); },
      };
    },
  } as unknown as Parameters<typeof generateLocalPrediction>[0];

  const result = await generateLocalPrediction(
    stubSupabase,
    "u1",
    { current_weight_kg: 80, target_weight_kg: 75, primary_goal: "lose_fat", days_per_week: 4 },
    { detected_experience_level: "intermediate" },
  );
  assertEquals(result.predicted_weight_kg, 78.5); // 80 + (75-80)*0.3
  assertEquals(result.source, "local");
  assertEquals(call > 0, true);
  // A brand-new user (onboarding trigger, zero scheduled_workouts rows in
  // the trailing 4 weeks) must fall back to the flat streak heuristic, NOT
  // the 0-weeks that predictStreakWeeks(0.0, fallback) would compute if the
  // "zero scheduled rows" case were mistaken for a real 0% adherence rate.
  assertEquals(result.predicted_streak_weeks, 10); // streakFallback for days_per_week=4
});

Deno.test("generateLocalPrediction is now async and calls the trend helpers (source-shape — the real DB-backed path needs live env)", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (!/export\s+async\s+function\s+generateLocalPrediction/.test(src)) {
    throw new Error("expected generateLocalPrediction to be async");
  }
  if (!src.includes("predictWeight(") || !src.includes("predictLift(") || !src.includes("predictStreakWeeks(")) {
    throw new Error("expected generateLocalPrediction to call all three trend.ts helpers");
  }
  if (!src.includes("completionRateOverWindow(")) {
    throw new Error("expected generateLocalPrediction to reuse the existing completionRateOverWindow helper, not reimplement adherence-rate math");
  }
});

Deno.test("the schedule-existence probe reuses windowSinceDateUtc (raw-UTC), not istDateStr, so its window cutoff can never drift from completionRateOverWindow's own", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (!src.includes("windowSinceDateUtc(4)")) {
    throw new Error(
      "expected the schedule-existence probe to compute its cutoff via windowSinceDateUtc(4), " +
        "the same raw-UTC helper completionRateOverWindow uses internally — an istDateStr()-shifted " +
        "cutoff here would disagree with completionRateOverWindow's raw-UTC one by up to a day",
    );
  }
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
