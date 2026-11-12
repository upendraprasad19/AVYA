import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { logMealByTextTool } from "../nutrition/logMealByText.ts";
import { zodToGeminiSchema } from "../zodToGemini.ts";
import { istDateStr } from "../../ist_date.ts";

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
    // OI-493 Landing A: only today's IST date passes (was a fixed 2026-04-20).
    date: istDateStr(),
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

// ---- OI-493 Landing A (founder F3, "today only") ------------------------
// The app logs a coach meal on the IST day the intent was created and ignores
// the payload date, so a non-today date is refused at the schema, with a
// message the model reads back (tool-loop invalid_args) and can tell the user.

const DAY_MS = 24 * 60 * 60 * 1000;
const TODAY_ONLY =
  "Only today's meals can be logged. Ask the user to add an earlier meal from the Nutrition tab.";

function refusalMessages(date: string): string[] {
  const r = logMealByTextTool.schema.safeParse({
    description: "dal chawal 2 katoris",
    date,
  });
  assertEquals(r.success, false, `date=${date} must be refused`);
  return r.success ? [] : r.error.issues.map((i) => i.message);
}

Deno.test("logMealByText — yesterday (IST) is refused with the today-only message", () => {
  const yesterday = istDateStr(new Date(Date.now() - DAY_MS));
  assertEquals(refusalMessages(yesterday), [TODAY_ONLY]);
});

Deno.test("logMealByText — tomorrow (IST) is refused with the today-only message", () => {
  const tomorrow = istDateStr(new Date(Date.now() + DAY_MS));
  assertEquals(refusalMessages(tomorrow), [TODAY_ONLY]);
});

Deno.test("logMealByText — today (IST) and an absent date are accepted", () => {
  for (const args of [
    { description: "dal chawal 2 katoris", date: istDateStr() },
    { description: "dal chawal 2 katoris" },
  ]) {
    const r = logMealByTextTool.schema.safeParse(args);
    assertEquals(r.success, true, JSON.stringify(args));
  }
});

Deno.test("logMealByText — the model is told to omit date and mealType", () => {
  // deno-lint-ignore no-explicit-any
  const props = zodToGeminiSchema(logMealByTextTool.schema as any).properties!;
  assertEquals(props.date.description, "Only today's meals can be logged; omit it.");
  assertEquals(props.date.type, "STRING");
  assertEquals(
    props.mealType.description,
    "Omit unless the user named the meal; the app picks it from the time of day.",
  );
  // The old "default to 'snacks'" promise is gone (the app infers the slot).
  assert(!JSON.stringify(props).includes("snacks' if omitted"));
  assertStringIncludes(logMealByTextTool.description, "log it to the user's nutrition");
});
