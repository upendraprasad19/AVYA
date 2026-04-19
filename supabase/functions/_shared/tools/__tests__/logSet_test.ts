import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { logSetTool } from "../workout/logSet.ts";

Deno.test("logSet — schema accepts valid args", () => {
  const result = logSetTool.schema.safeParse({
    exerciseId: "ex_bench",
    weightKg: 80,
    reps: 10,
    sets: 4,
  });
  assertEquals(result.success, true);
});

Deno.test("logSet — schema accepts bodyweight (weightKg=0)", () => {
  const result = logSetTool.schema.safeParse({
    exerciseId: "ex_pushup",
    weightKg: 0,
    reps: 20,
    sets: 3,
  });
  assertEquals(result.success, true);
});

Deno.test("logSet — schema rejects negative weight", () => {
  const result = logSetTool.schema.safeParse({
    exerciseId: "ex_bench",
    weightKg: -10,
    reps: 10,
    sets: 4,
  });
  assertEquals(result.success, false);
});

Deno.test("logSet — schema rejects weight > 500", () => {
  const result = logSetTool.schema.safeParse({
    exerciseId: "ex_bench",
    weightKg: 501,
    reps: 10,
    sets: 4,
  });
  assertEquals(result.success, false);
});

Deno.test("logSet — schema rejects reps < 1", () => {
  const result = logSetTool.schema.safeParse({
    exerciseId: "ex_bench",
    weightKg: 80,
    reps: 0,
    sets: 4,
  });
  assertEquals(result.success, false);
});

Deno.test("logSet — schema rejects non-integer reps", () => {
  const result = logSetTool.schema.safeParse({
    exerciseId: "ex_bench",
    weightKg: 80,
    reps: 10.5,
    sets: 4,
  });
  assertEquals(result.success, false);
});

Deno.test("logSet — intentBuilder produces correct shape", () => {
  const intent = logSetTool.intentBuilder!({
    exerciseId: "ex_bench",
    weightKg: 80,
    reps: 10,
    sets: 4,
  });
  assertEquals(intent.type, "log_set");
  assertEquals(intent.payload, {
    exerciseId: "ex_bench",
    weightKg: 80,
    reps: 10,
    sets: 4,
  });
  assertEquals(intent.confirmationClass, "trivial");
});

Deno.test("logSet — metadata", () => {
  assertEquals(logSetTool.tier, "free");
  assertEquals(logSetTool.kind, "write");
});
