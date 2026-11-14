// Diet plan Unit 2b (plan diet-food-type-server §4 T1): every row of the
// shared fixture through both readers; the same fixture pins the Dart
// foodTypeOf (test/core/food_types_test.dart).
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  DEFAULT_FOOD_TYPE,
  dietPreferenceLine,
  FOOD_TYPE_KEYS,
  foodTypeLabel,
  knownFoodType,
  normalizeFoodType,
} from "./food_types.ts";

type Row = { input: string | null; expected: string; known: string | null };

const fixture = JSON.parse(
  await Deno.readTextFile(
    new URL("./testdata/food_type_vocabulary.json", import.meta.url),
  ),
) as { rows: Row[] };

Deno.test("fixture is non-trivial and covers every key", () => {
  assertEquals(fixture.rows.length >= 30, true);
  for (const k of FOOD_TYPE_KEYS) {
    assertEquals(fixture.rows.some((r) => r.expected === k), true, k);
  }
});

Deno.test("normalizeFoodType: every fixture row", () => {
  for (const r of fixture.rows) {
    assertEquals(normalizeFoodType(r.input), r.expected, JSON.stringify(r.input));
  }
});

Deno.test("knownFoodType: every fixture row", () => {
  for (const r of fixture.rows) {
    assertEquals(knownFoodType(r.input), r.known, JSON.stringify(r.input));
  }
});

Deno.test("non-string input: tolerant = default, strict = null", () => {
  for (const v of [undefined, 3, true, {}, ["veg"]]) {
    assertEquals(normalizeFoodType(v), DEFAULT_FOOD_TYPE);
    assertEquals(knownFoodType(v), null);
  }
  assertEquals(DEFAULT_FOOD_TYPE, "non_veg");
});

Deno.test("labels and the weekly-report line", () => {
  assertEquals(FOOD_TYPE_KEYS.map(foodTypeLabel), [
    "Veg",
    "Non-veg",
    "Eggetarian",
    "Pescatarian",
    "Vegan",
  ]);
  assertEquals(dietPreferenceLine("vegetarian"), "Veg");
  assertEquals(dietPreferenceLine(null), "Non-veg");
  assertEquals(dietPreferenceLine("keto"), "Non-veg");
  assertEquals(dietPreferenceLine("eggetarian"), "Eggetarian");
  assertEquals(dietPreferenceLine("xyz"), "Veg");
});
