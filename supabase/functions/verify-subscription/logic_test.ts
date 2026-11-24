// OI-519 U4: verify-subscription's additive Play display fields, and their wiring in index.ts.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { playDisplayFields } from "./logic.ts";

const NONE = { store: null, auto_renew: null, store_expires_at: null };

Deno.test("not PRO, or any non-Play row: all three null", () => {
  assertEquals(playDisplayFields(null), NONE);
  assertEquals(playDisplayFields({}), NONE);
  assertEquals(playDisplayFields({ store: null, auto_renew: null }), NONE);
  // A stray auto_renew on a non-Play row never reads as "renews".
  assertEquals(playDisplayFields({ store: "razorpay", auto_renew: true, store_expires_at: "x" }), NONE);
});

Deno.test("an active Play row: the three fields as stored", () => {
  const t = "2026-12-24T06:00:00+00:00";
  assertEquals(playDisplayFields({ store: "play", auto_renew: true, store_expires_at: t }), {
    store: "play", auto_renew: true, store_expires_at: t,
  });
  assertEquals(playDisplayFields({ store: "play", auto_renew: false, store_expires_at: t }).auto_renew, false);
  assertEquals(playDisplayFields({ store: "play" }), { store: "play", auto_renew: null, store_expires_at: null });
});

Deno.test("index.ts selects the columns and spreads the fields on every 200 body; the inactive row gets none", async () => {
  const src = (await Deno.readTextFile(new URL("./index.ts", import.meta.url))).replace(/\s+/g, " ");
  assertEquals(src.includes('.select("plan, status, end_date, store, auto_renew, store_expires_at")'), true);
  // the two not-PRO bodies and the final body
  assertEquals(src.split("...playDisplayFields(null)").length - 1, 2);
  assertEquals(src.includes("...playDisplayFields(isActive ? subscription : null),"), true);
});
