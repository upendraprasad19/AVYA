import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { suggestMealTool } from "../nutrition/suggestMeal.ts";

// Note: handler integration tests against a real Supabase client are deferred
// (would require a seeded test DB). Schema + metadata coverage only.

Deno.test("suggestMeal — schema accepts minimal valid args", () => {
  const result = suggestMealTool.schema.safeParse({
    remainingKcal: 600,
  });
  assertEquals(result.success, true);
});

Deno.test("suggestMeal — schema accepts full valid args", () => {
  const result = suggestMealTool.schema.safeParse({
    remainingKcal: 800,
    remainingProteinG: 40,
    isVeg: true,
    cuisine: "indian",
    mealType: "dinner",
    excludeIngredients: ["peanut", "shellfish"],
  });
  assertEquals(result.success, true);
});

Deno.test("suggestMeal — schema rejects remainingKcal below 50", () => {
  const result = suggestMealTool.schema.safeParse({ remainingKcal: 49 });
  assertEquals(result.success, false);
});

Deno.test("suggestMeal — schema rejects remainingKcal above 3000", () => {
  const result = suggestMealTool.schema.safeParse({ remainingKcal: 3001 });
  assertEquals(result.success, false);
});

Deno.test("suggestMeal — schema accepts remainingKcal at boundaries", () => {
  const min = suggestMealTool.schema.safeParse({ remainingKcal: 50 });
  assertEquals(min.success, true);
  const max = suggestMealTool.schema.safeParse({ remainingKcal: 3000 });
  assertEquals(max.success, true);
});

Deno.test("suggestMeal — schema rejects non-integer remainingKcal", () => {
  const result = suggestMealTool.schema.safeParse({ remainingKcal: 600.5 });
  assertEquals(result.success, false);
});

Deno.test("suggestMeal — schema rejects remainingProteinG below 0", () => {
  const result = suggestMealTool.schema.safeParse({
    remainingKcal: 600,
    remainingProteinG: -1,
  });
  assertEquals(result.success, false);
});

Deno.test("suggestMeal — schema rejects remainingProteinG above 150", () => {
  const result = suggestMealTool.schema.safeParse({
    remainingKcal: 600,
    remainingProteinG: 151,
  });
  assertEquals(result.success, false);
});

Deno.test("suggestMeal — schema accepts remainingProteinG at boundaries", () => {
  const min = suggestMealTool.schema.safeParse({
    remainingKcal: 600,
    remainingProteinG: 0,
  });
  assertEquals(min.success, true);
  const max = suggestMealTool.schema.safeParse({
    remainingKcal: 600,
    remainingProteinG: 150,
  });
  assertEquals(max.success, true);
});

Deno.test("suggestMeal — schema rejects bad cuisine enum", () => {
  const result = suggestMealTool.schema.safeParse({
    remainingKcal: 600,
    cuisine: "italian",
  });
  assertEquals(result.success, false);
});

Deno.test("suggestMeal — schema accepts each valid cuisine", () => {
  for (const cuisine of ["indian", "asian", "mediterranean", "western", "any"]) {
    const result = suggestMealTool.schema.safeParse({
      remainingKcal: 600,
      cuisine,
    });
    assertEquals(result.success, true, `cuisine=${cuisine} should be valid`);
  }
});

Deno.test("suggestMeal — schema rejects bad mealType enum", () => {
  const result = suggestMealTool.schema.safeParse({
    remainingKcal: 600,
    mealType: "brunch",
  });
  assertEquals(result.success, false);
});

Deno.test("suggestMeal — schema accepts each valid mealType", () => {
  for (const mealType of ["breakfast", "lunch", "dinner", "snack"]) {
    const result = suggestMealTool.schema.safeParse({
      remainingKcal: 600,
      mealType,
    });
    assertEquals(result.success, true, `mealType=${mealType} should be valid`);
  }
});

Deno.test("suggestMeal — schema rejects excludeIngredients > 10 items", () => {
  const result = suggestMealTool.schema.safeParse({
    remainingKcal: 600,
    excludeIngredients: Array.from({ length: 11 }, (_, i) => `item${i}`),
  });
  assertEquals(result.success, false);
});

Deno.test("suggestMeal — schema accepts excludeIngredients with exactly 10 items", () => {
  const result = suggestMealTool.schema.safeParse({
    remainingKcal: 600,
    excludeIngredients: Array.from({ length: 10 }, (_, i) => `item${i}`),
  });
  assertEquals(result.success, true);
});

Deno.test("suggestMeal — metadata", () => {
  assertEquals(suggestMealTool.tier, "pro");
  assertEquals(suggestMealTool.kind, "read");
  assertEquals(suggestMealTool.family, "nutrition");
  assertEquals(suggestMealTool.name, "suggestMeal");
  assertEquals(suggestMealTool.maxLatencyMs, 4000);
});

Deno.test("suggestMeal — description present and non-empty", () => {
  assertEquals(typeof suggestMealTool.description, "string");
  assertEquals(suggestMealTool.description.length > 0, true);
});

Deno.test("suggestMeal — handler is defined (read tool)", () => {
  assertEquals(typeof suggestMealTool.handler, "function");
});
