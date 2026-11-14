// Tests for _shared/promo_rules.ts (OI-366, payment-hardening U3): the rule table, IST boundaries, both date
// formats and every malformed input.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { promoUsableAt } from "./promo_rules.ts";

const live = { is_active: true, valid_until: "2026-10-24", max_uses: null, used_count: 0 };
// 2026-10-24 23:59 IST = 18:29 UTC; 2026-10-25 00:01 IST = 18:31 UTC.
const LAST_MINUTE_IST = new Date("2026-10-24T18:29:00Z");
const NEXT_DAY_IST = new Date("2026-10-24T18:31:00Z");

Deno.test("valid_until is usable THROUGH its IST day: 23:59 IST ok, 00:01 IST next day expired", () => {
  assertEquals(promoUsableAt(live, LAST_MINUTE_IST), "ok");
  assertEquals(promoUsableAt(live, NEXT_DAY_IST), "expired");
});

Deno.test("the IST day, not the UTC day: at 00:01 IST the UTC date is still the 24th, yet the code is expired", () => {
  assertEquals([NEXT_DAY_IST.getUTCMonth() + 1, NEXT_DAY_IST.getUTCDate()], [10, 24]); // still the 24th in UTC
  assertEquals(promoUsableAt(live, NEXT_DAY_IST), "expired");
});

Deno.test("both date formats: the live 'YYYY-MM-DD' and a timestamp string", () => {
  assertEquals(promoUsableAt({ ...live, valid_until: "2099-01-01T00:00:00Z" }, NEXT_DAY_IST), "ok");
  assertEquals(promoUsableAt({ ...live, valid_until: "2026-10-24T00:00:00Z" }, NEXT_DAY_IST), "expired");
  assertEquals(promoUsableAt({ ...live, valid_until: "2026-10-24T00:00:00Z" }, LAST_MINUTE_IST), "ok");
});

Deno.test("a valid_until that is not a plain date is EXPIRED (never open for ever)", () => {
  for (const v of ["infinity", "abc", "", null, undefined, "2026-1-24", "99999-01-01", 20261024]) {
    assertEquals(promoUsableAt({ ...live, valid_until: v }, LAST_MINUTE_IST), "expired", JSON.stringify(v));
  }
});

Deno.test("is_active: only an explicit true is active (null, undefined, 'true', 1 are inactive)", () => {
  for (const v of [false, null, undefined, "true", 1]) {
    assertEquals(promoUsableAt({ ...live, is_active: v }, LAST_MINUTE_IST), "inactive", JSON.stringify(v));
  }
});

Deno.test("exhaustion: used_count >= max_uses; a missing max_uses is unlimited; a null used_count counts as 0", () => {
  assertEquals(promoUsableAt({ ...live, max_uses: 5, used_count: 4 }, LAST_MINUTE_IST), "ok");
  assertEquals(promoUsableAt({ ...live, max_uses: 5, used_count: 5 }, LAST_MINUTE_IST), "exhausted");
  assertEquals(promoUsableAt({ ...live, max_uses: 5, used_count: 6 }, LAST_MINUTE_IST), "exhausted");
  assertEquals(promoUsableAt({ ...live, max_uses: 0, used_count: null }, LAST_MINUTE_IST), "exhausted");
  assertEquals(promoUsableAt({ ...live, max_uses: 5, used_count: null }, LAST_MINUTE_IST), "ok");
  assertEquals(promoUsableAt({ ...live, max_uses: undefined, used_count: 999 }, LAST_MINUTE_IST), "ok");
  assertEquals(promoUsableAt({ ...live, max_uses: null, used_count: 999 }, LAST_MINUTE_IST), "ok");
});

Deno.test("order of the checks: inactive before expired before exhausted", () => {
  const all = { is_active: false, valid_until: "2000-01-01", max_uses: 1, used_count: 1 };
  assertEquals(promoUsableAt(all, LAST_MINUTE_IST), "inactive");
  assertEquals(promoUsableAt({ ...all, is_active: true }, LAST_MINUTE_IST), "expired");
  assertEquals(promoUsableAt({ ...all, is_active: true, valid_until: "2099-01-01" }, LAST_MINUTE_IST), "exhausted");
});
