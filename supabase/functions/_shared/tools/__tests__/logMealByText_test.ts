import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { logMealByTextTool } from "../nutrition/logMealByText.ts";

// Note: intentBuilder is async and calls Gemini via parseFoodText.
// We don't exercise it here — schema + metadata coverage only.
// A separate intentBuilder test would need to stub parseFoodText (deferred).

Deno.test("logMealByText — schema accepts valid description only", () => {
  const result = logMealByTextTool.schema.safeParse({
    description: "dal chawal 2 katoris",
  });
  assertEquals(result.success, true);
});

Deno.test("logMealByText — schema accepts valid description + date + mealType", () => {
  const result = logMealByTextTool.schema.safeParse({
    description: "paneer tikka 6 pieces with naan",
    date: "2026-04-20",
    mealType: "lunch",
  });
  assertEquals(result.success, true);
});

Deno.test("logMealByText — schema rejects empty description", () => {
  const result = logMealByTextTool.schema.safeParse({
    description: "",
  });
  assertEquals(result.success, false);
});

Deno.test("logMealByText — schema rejects description shorter than 3 chars", () => {
  const result = logMealByTextTool.schema.safeParse({
    description: "ab",
  });
  assertEquals(result.success, false);
});

Deno.test("logMealByText — schema rejects description >500 chars", () => {
  const result = logMealByTextTool.schema.safeParse({
    description: "x".repeat(501),
  });
  assertEquals(result.success, false);
});

Deno.test("logMealByText — schema rejects malformed date", () => {
  const result = logMealByTextTool.schema.safeParse({
    description: "biryani plate",
    date: "20-04-2026",
  });
  assertEquals(result.success, false);
});

Deno.test("logMealByText — schema rejects partial date", () => {
  const result = logMealByTextTool.schema.safeParse({
    description: "biryani plate",
    date: "2026-04",
  });
  assertEquals(result.success, false);
});

Deno.test("logMealByText — schema rejects bad mealType enum", () => {
  const result = logMealByTextTool.schema.safeParse({
    description: "biryani plate",
    mealType: "brunch",
  });
  assertEquals(result.success, false);
});

Deno.test("logMealByText — schema accepts each valid mealType", () => {
  for (const mealType of ["breakfast", "lunch", "dinner", "snacks"]) {
    const result = logMealByTextTool.schema.safeParse({
      description: "biryani plate",
      mealType,
    });
    assertEquals(result.success, true, `mealType=${mealType} should be valid`);
  }
});

Deno.test("logMealByText — metadata", () => {
  assertEquals(logMealByTextTool.tier, "free");
  assertEquals(logMealByTextTool.kind, "write");
  assertEquals(logMealByTextTool.family, "nutrition");
  assertEquals(logMealByTextTool.confirmationClass, "trivial");
  assertEquals(logMealByTextTool.name, "logMealByText");
});

Deno.test("logMealByText — description present and non-empty", () => {
  assertEquals(typeof logMealByTextTool.description, "string");
  assertEquals(logMealByTextTool.description.length > 0, true);
});
