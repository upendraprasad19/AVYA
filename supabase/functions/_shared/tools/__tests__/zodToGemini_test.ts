import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { z } from "https://deno.land/x/zod@v3.23.8/mod.ts";
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
