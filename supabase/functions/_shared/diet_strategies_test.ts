// Diet plan Unit 3b-2 (B-pass seat C finding 3, seat B finding 7): the
// server read of user_profile.diet_strategy against the vocabulary vector
// the Dart test reads too (test/core/diet_strategy_vocabulary_test.dart).
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { normalizeDietStrategy } from "./diet_strategies.ts";

const fixture = JSON.parse(
  Deno.readTextFileSync(new URL("./testdata/diet_strategy_vocabulary.json", import.meta.url)),
) as { rows: { input: string; expected: string }[] };

Deno.test("the vector is non-trivial and covers every strategy", () => {
  assert(fixture.rows.length >= 10);
  const seen = new Set(fixture.rows.map((r) => r.expected));
  for (const k of ["balanced", "low_carb", "keto"]) assert(seen.has(k), k);
});

Deno.test("normalizeDietStrategy matches the vector", () => {
  for (const r of fixture.rows) {
    assertEquals(normalizeDietStrategy(r.input), r.expected, JSON.stringify(r.input));
  }
});

Deno.test("a non-string value is balanced", () => {
  for (const v of [null, undefined, 5, {}, ["keto"], true]) {
    assertEquals(normalizeDietStrategy(v), "balanced", String(v));
  }
});
