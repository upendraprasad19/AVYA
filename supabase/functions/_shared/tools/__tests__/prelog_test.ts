import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { prelogTool } from "../nutrition/prelog.ts";

// Note: intentBuilder is async + parses each meal via Gemini (parseFoodText).
// Don't exercise it here — schema + metadata coverage only.
// Integration test deferred until a parseFoodText stub exists.

Deno.test("prelog — schema accepts a single valid meal", () => {
  const result = prelogTool.schema.safeParse({
    meals: [
      { description: "dal chawal", date: "2026-04-20" },
    ],
  });
  assertEquals(result.success, true);
});

Deno.test("prelog — schema accepts max (21) meals", () => {
  const meals = Array.from({ length: 21 }, (_, i) => ({
    description: `meal ${i}`,
    date: "2026-04-20",
  }));
  const result = prelogTool.schema.safeParse({ meals });
  assertEquals(result.success, true);
});

Deno.test("prelog — schema accepts meals with optional mealType", () => {
  const result = prelogTool.schema.safeParse({
    meals: [
      { description: "poha", date: "2026-04-20", mealType: "breakfast" },
      { description: "rajma chawal", date: "2026-04-20", mealType: "lunch" },
    ],
  });
  assertEquals(result.success, true);
});

Deno.test("prelog — schema rejects 0 meals", () => {
  const result = prelogTool.schema.safeParse({ meals: [] });
  assertEquals(result.success, false);
});

Deno.test("prelog — schema rejects 22 meals (above max)", () => {
  const meals = Array.from({ length: 22 }, (_, i) => ({
    description: `meal ${i}`,
    date: "2026-04-20",
  }));
  const result = prelogTool.schema.safeParse({ meals });
  assertEquals(result.success, false);
});

Deno.test("prelog — schema rejects meal with empty description", () => {
  const result = prelogTool.schema.safeParse({
    meals: [{ description: "", date: "2026-04-20" }],
  });
  assertEquals(result.success, false);
});

Deno.test("prelog — schema rejects meal with description shorter than 3 chars", () => {
  const result = prelogTool.schema.safeParse({
    meals: [{ description: "ab", date: "2026-04-20" }],
  });
  assertEquals(result.success, false);
});

Deno.test("prelog — schema rejects meal with description >300 chars", () => {
  const result = prelogTool.schema.safeParse({
    meals: [{ description: "x".repeat(301), date: "2026-04-20" }],
  });
  assertEquals(result.success, false);
});

Deno.test("prelog — schema rejects meal missing date", () => {
  const result = prelogTool.schema.safeParse({
    meals: [{ description: "dal chawal" }],
  });
  assertEquals(result.success, false);
});

Deno.test("prelog — schema rejects meal with malformed date", () => {
  const result = prelogTool.schema.safeParse({
    meals: [{ description: "dal chawal", date: "20-04-2026" }],
  });
  assertEquals(result.success, false);
});

Deno.test("prelog — schema rejects meal with bad mealType enum", () => {
  const result = prelogTool.schema.safeParse({
    meals: [{ description: "dal chawal", date: "2026-04-20", mealType: "brunch" }],
  });
  assertEquals(result.success, false);
});

Deno.test("prelog — schema accepts each valid mealType per meal", () => {
  for (const mealType of ["breakfast", "lunch", "dinner", "snacks"]) {
    const result = prelogTool.schema.safeParse({
      meals: [{ description: "dal chawal", date: "2026-04-20", mealType }],
    });
    assertEquals(result.success, true, `mealType=${mealType} should be valid`);
  }
});

Deno.test("prelog — metadata", () => {
  assertEquals(prelogTool.tier, "pro");
  assertEquals(prelogTool.kind, "write");
  assertEquals(prelogTool.family, "nutrition");
  assertEquals(prelogTool.name, "prelog");
  // Static default is destructive (multi-day worst case); intent may downgrade
  // to 'reviewable' for single-day batches.
  assertEquals(prelogTool.confirmationClass, "destructive");
});

Deno.test("prelog — description present and non-empty", () => {
  assertEquals(typeof prelogTool.description, "string");
  assertEquals(prelogTool.description.length > 0, true);
});
