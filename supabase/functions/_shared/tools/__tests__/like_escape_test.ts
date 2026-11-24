// escapeLike (OI-507): the unit-level contract of the shared ilike-pattern escaper.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { escapeLike } from "../../like_escape.ts";

Deno.test("escapeLike — % _ and backslash are escaped, backslash FIRST (no doubled escapes)", () => {
  assertEquals(escapeLike("50%"), "50\\%");
  assertEquals(escapeLike("a_b"), "a\\_b");
  assertEquals(escapeLike("x\\y"), "x\\\\y");
  assertEquals(escapeLike("\\%"), "\\\\\\%"); // backslash then %: \\ then \%
});

Deno.test("escapeLike — * is removed (PostgREST reads it as %, and it cannot be escaped)", () => {
  assertEquals(escapeLike("a*b"), "ab");
  assertEquals(escapeLike("***"), "");
});

Deno.test("escapeLike — ordinary names pass through untouched", () => {
  assertEquals(escapeLike("Dip (Parallel Bars)"), "Dip (Parallel Bars)");
  assertEquals(escapeLike("V-Up"), "V-Up");
});
