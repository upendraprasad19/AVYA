import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { z } from "npm:zod@3.25.76";
import { toolToFunctionDeclaration, zodToGeminiSchema } from "../zodToGemini.ts";

Deno.test("zodToGeminiSchema — string", () => {
  const result = zodToGeminiSchema(z.string());
  assertEquals(result, { type: "STRING" });
});

Deno.test("zodToGeminiSchema — number", () => {
  const result = zodToGeminiSchema(z.number());
  assertEquals(result, { type: "NUMBER" });
});

Deno.test("zodToGeminiSchema — integer", () => {
  const result = zodToGeminiSchema(z.number().int());
  assertEquals(result, { type: "INTEGER" });
});

Deno.test("zodToGeminiSchema — boolean", () => {
  const result = zodToGeminiSchema(z.boolean());
  assertEquals(result, { type: "BOOLEAN" });
});

Deno.test("zodToGeminiSchema — enum", () => {
  const result = zodToGeminiSchema(z.enum(["a", "b", "c"]));
  assertEquals(result, { type: "STRING", enum: ["a", "b", "c"] });
});

Deno.test("zodToGeminiSchema — array of strings", () => {
  const result = zodToGeminiSchema(z.array(z.string()));
  assertEquals(result, { type: "ARRAY", items: { type: "STRING" } });
});

Deno.test("zodToGeminiSchema — object with required + optional fields", () => {
  const result = zodToGeminiSchema(z.object({
    name: z.string(),
    age: z.number().int().optional(),
  }));
  assertEquals(result.type, "OBJECT");
  assertEquals(result.properties?.name, { type: "STRING" });
  // Optional fields wrapped as nullable
  assertEquals(result.properties?.age?.type, "INTEGER");
  assertEquals(result.properties?.age?.nullable, true);
  assertEquals(result.required, ["name"]);
});

Deno.test("zodToGeminiSchema — propagates description from .describe()", () => {
  const result = zodToGeminiSchema(z.string().describe("user's preferred name"));
  assertEquals(result.description, "user's preferred name");
});

Deno.test("zodToGeminiSchema — throws on unsupported type", () => {
  assertThrows(
    () => zodToGeminiSchema(z.bigint()),
    Error,
    "unsupported Zod type",
  );
});

// Task 27 fix round (F3): swapWorkoutDays.ts's real-calendar-date validation
// uses `.refine()`, which wraps a ZodString in ZodEffects. zodToGemini must
// unwrap it to the PRE-effect shape (Gemini describes the wire shape, not
// the refinement) rather than throwing "unsupported Zod type: ZodEffects".
Deno.test("zodToGeminiSchema — unwraps ZodEffects (.refine()) to its pre-effect shape", () => {
  const result = zodToGeminiSchema(z.string().regex(/^\d+$/).refine(() => true));
  assertEquals(result, { type: "STRING" });
});

Deno.test("zodToGeminiSchema — ZodEffects preserves an outer .describe()", () => {
  const result = zodToGeminiSchema(
    z.string().refine(() => true).describe("a refined string"),
  );
  assertEquals(result, { type: "STRING", description: "a refined string" });
});

Deno.test("zodToGeminiSchema — an object field using .refine() still produces a valid OBJECT schema", () => {
  const result = zodToGeminiSchema(z.object({
    dateA: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(() => true),
  }));
  assertEquals(result.type, "OBJECT");
  assertEquals(result.properties?.dateA, { type: "STRING" });
  assertEquals(result.required, ["dateA"]);
});

Deno.test("toolToFunctionDeclaration — happy path", () => {
  const result = toolToFunctionDeclaration({
    name: "logSet",
    description: "Log an exercise set.",
    schema: z.object({ weightKg: z.number(), reps: z.number().int() }),
  });
  assertEquals(result.name, "logSet");
  assertEquals(result.description, "Log an exercise set.");
  assertEquals(result.parameters.type, "OBJECT");
});

Deno.test("toolToFunctionDeclaration — throws if schema not object at top", () => {
  assertThrows(
    () => toolToFunctionDeclaration({
      name: "bad",
      description: "x",
      schema: z.string(),
    }),
    Error,
    "must be a Zod object at the top level",
  );
});
