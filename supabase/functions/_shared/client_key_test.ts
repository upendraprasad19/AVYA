import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { sanitizeClientKey } from "./client_key.ts";

Deno.test("a well-formed key is kept", () => {
  assertEquals(sanitizeClientKey("coach_1763000000000"), "coach_1763000000000");
  assertEquals(sanitizeClientKey("coach_1234567890"), "coach_1234567890"); // 10 digits
  assertEquals(sanitizeClientKey("coach_1234567890123456"), "coach_1234567890123456"); // 16
});

Deno.test("a wrong prefix or length is dropped", () => {
  assertEquals(sanitizeClientKey("chat_1763000000000"), null);
  assertEquals(sanitizeClientKey("Coach_1763000000000"), null);
  assertEquals(sanitizeClientKey("coach_123456789"), null); // 9 digits
  assertEquals(sanitizeClientKey("coach_12345678901234567"), null); // 17 digits
  assertEquals(sanitizeClientKey("coach_"), null);
  assertEquals(sanitizeClientKey(""), null);
});

Deno.test("hex, whitespace and injection text are dropped", () => {
  assertEquals(sanitizeClientKey("coach_17630abc0000"), null);
  assertEquals(sanitizeClientKey("coach_memory"), null);
  assertEquals(sanitizeClientKey(" coach_1763000000000"), null);
  assertEquals(sanitizeClientKey("coach_1763000000000\n"), null);
  assertEquals(sanitizeClientKey("coach_1763000000000'; drop table x;--"), null);
});

Deno.test("a non-string is dropped and nothing throws", () => {
  for (const v of [undefined, null, 1763000000000, true, {}, ["coach_1763000000000"]]) {
    assertEquals(sanitizeClientKey(v), null);
  }
});
