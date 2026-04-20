import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { modifyWorkoutForInjuryTool } from "../workout/modifyWorkoutForInjury.ts";

Deno.test("modifyWorkoutForInjury — schema accepts valid args", () => {
  const result = modifyWorkoutForInjuryTool.schema.safeParse({
    bodyPart: "shoulder",
    severity: "moderate",
  });
  assertEquals(result.success, true);
});

Deno.test("modifyWorkoutForInjury — schema accepts daysAhead", () => {
  const result = modifyWorkoutForInjuryTool.schema.safeParse({
    bodyPart: "knee",
    severity: "mild",
    daysAhead: 3,
  });
  assertEquals(result.success, true);
});

Deno.test("modifyWorkoutForInjury — schema rejects invalid bodyPart", () => {
  const result = modifyWorkoutForInjuryTool.schema.safeParse({
    bodyPart: "spleen",
    severity: "mild",
  });
  assertEquals(result.success, false);
});

Deno.test("modifyWorkoutForInjury — schema rejects invalid severity", () => {
  const result = modifyWorkoutForInjuryTool.schema.safeParse({
    bodyPart: "shoulder",
    severity: "extreme",
  });
  assertEquals(result.success, false);
});

Deno.test("modifyWorkoutForInjury — schema rejects daysAhead < 1", () => {
  const result = modifyWorkoutForInjuryTool.schema.safeParse({
    bodyPart: "shoulder",
    severity: "mild",
    daysAhead: 0,
  });
  assertEquals(result.success, false);
});

Deno.test("modifyWorkoutForInjury — schema rejects daysAhead > 14", () => {
  const result = modifyWorkoutForInjuryTool.schema.safeParse({
    bodyPart: "shoulder",
    severity: "mild",
    daysAhead: 15,
  });
  assertEquals(result.success, false);
});

Deno.test("modifyWorkoutForInjury — intentBuilder defaults daysAhead to 7", () => {
  const intent = modifyWorkoutForInjuryTool.intentBuilder!({
    bodyPart: "shoulder",
    severity: "moderate",
  });
  assertEquals(intent.type, "modify_workout_for_injury");
  assertEquals(intent.payload.bodyPart, "shoulder");
  assertEquals(intent.payload.severity, "moderate");
  assertEquals(intent.payload.daysAhead, 7);
  assertEquals(intent.confirmationClass, "destructive");
  assertEquals(intent.previewSummary, "Modify next 7 days for moderate shoulder injury");
});

Deno.test("modifyWorkoutForInjury — intentBuilder uses supplied daysAhead", () => {
  const intent = modifyWorkoutForInjuryTool.intentBuilder!({
    bodyPart: "knee",
    severity: "severe",
    daysAhead: 14,
  });
  assertEquals(intent.payload.daysAhead, 14);
  assertEquals(intent.previewSummary, "Modify next 14 days for severe knee injury");
});

Deno.test("modifyWorkoutForInjury — metadata", () => {
  assertEquals(modifyWorkoutForInjuryTool.tier, "pro");
  assertEquals(modifyWorkoutForInjuryTool.kind, "write");
  assertEquals(modifyWorkoutForInjuryTool.family, "workout");
  assertEquals(modifyWorkoutForInjuryTool.confirmationClass, "destructive");
});
