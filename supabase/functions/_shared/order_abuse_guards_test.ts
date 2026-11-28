// Tests for _shared/order_abuse_guards.ts (payment-hardening hermes pass, H2/H3).
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ORDER_ABUSE_GUARDS_DISABLE_ENV, retryMinutes, secondsLeftInBucket } from "./order_abuse_guards.ts";

Deno.test("the switch name is the one SECRET_INVENTORY documents", () => {
  assertEquals(ORDER_ABUSE_GUARDS_DISABLE_ENV, "DISABLE_ORDER_ABUSE_GUARDS");
});

Deno.test("retryMinutes names whole minutes, rounded up, never 0", () => {
  assertEquals(retryMinutes(0), "1 minute");
  assertEquals(retryMinutes(1), "1 minute");
  assertEquals(retryMinutes(60), "1 minute");
  assertEquals(retryMinutes(61), "2 minutes");
  assertEquals(retryMinutes(2220), "37 minutes");
  assertEquals(retryMinutes(3600), "60 minutes");
});

Deno.test("secondsLeftInBucket: the rest of the bucket, at least 1", () => {
  const hour = 3_600_000;
  const start = Date.parse("2026-10-24T10:00:00Z");
  assertEquals(secondsLeftInBucket(start, hour, Date.parse("2026-10-24T10:23:00Z")), 2220);
  assertEquals(secondsLeftInBucket(start, hour, Date.parse("2026-10-24T10:59:59.500Z")), 1);
  assertEquals(secondsLeftInBucket(start, hour, start), 3600);
  assertEquals(secondsLeftInBucket(start, hour, start + hour + 5), 1);
});
