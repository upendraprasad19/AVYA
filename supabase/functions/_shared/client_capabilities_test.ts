import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseClientCapabilities } from "./client_capabilities.ts";

Deno.test("non-array inputs -> empty set", () => {
  assertEquals(parseClientCapabilities(undefined).size, 0);
  assertEquals(parseClientCapabilities(null).size, 0);
  assertEquals(parseClientCapabilities("swap_workout_days").size, 0);
  assertEquals(parseClientCapabilities({ swap_workout_days: true }).size, 0);
  assertEquals(parseClientCapabilities(42).size, 0);
});

Deno.test("valid entries are kept", () => {
  const caps = parseClientCapabilities(["swap_workout_days", "some_other_cap"]);
  assertEquals(caps.has("swap_workout_days"), true);
  assertEquals(caps.has("some_other_cap"), true);
  assertEquals(caps.size, 2);
});

Deno.test("invalid entries are dropped, valid ones survive", () => {
  const caps = parseClientCapabilities([
    "swap_workout_days", // valid
    "Swap_Workout_Days", // uppercase -> invalid
    "swap-workout-days", // hyphen -> invalid
    "swap workout days", // space -> invalid
    "123abc", // digits -> invalid
    "", // empty -> invalid
    "a".repeat(49), // too long -> invalid
    "a".repeat(48), // exactly 48 -> valid
    42, // not a string -> invalid
    null, // not a string -> invalid
  ]);
  assertEquals(caps.has("swap_workout_days"), true);
  assertEquals(caps.has("a".repeat(48)), true);
  assertEquals(caps.size, 2);
});

Deno.test("more than 32 entries: only the first 32 are considered", () => {
  const alphabet = "abcdefghijklmnopqrstuvwxyz";
  // 40 distinct, all-lowercase, regex-valid ([a-z_]+) capability strings:
  // single letters a..z (26) then double letters aa..an (14) = 40 total.
  const labels: string[] = [];
  for (const c of alphabet) labels.push(`cap_${c}`);
  for (let i = 0; labels.length < 40; i++) {
    labels.push(`cap_a${alphabet[i]}`);
  }
  const raw = labels;
  const caps = parseClientCapabilities(raw);
  assertEquals(caps.size, 32);
  assertEquals(caps.has(raw[0]), true);
  assertEquals(caps.has(raw[31]), true);
  assertEquals(caps.has(raw[32]), false);
  assertEquals(caps.has(raw[39]), false);
});

Deno.test("duplicate entries dedupe", () => {
  const caps = parseClientCapabilities(["swap_workout_days", "swap_workout_days"]);
  assertEquals(caps.size, 1);
});

Deno.test("absent capability by default (empty array)", () => {
  assertEquals(parseClientCapabilities([]).size, 0);
});
