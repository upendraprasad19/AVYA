import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { buildProteinGapMessage, pickQuickFix } from "./message.ts";

Deno.test("pickQuickFix: >=40g gap, veg", () => {
  assertEquals(pickQuickFix(45, "veg"), "Quick fix: 200g paneer + a glass of milk.");
});
Deno.test("pickQuickFix: >=40g gap, vegan counts as veg", () => {
  assertEquals(pickQuickFix(40, "vegan"), "Quick fix: 200g paneer + a glass of milk.");
});
Deno.test("pickQuickFix: >=40g gap, non-veg", () => {
  assertEquals(pickQuickFix(50, "non_veg"), "Quick fix: 150g chicken breast or 4 boiled eggs.");
});
Deno.test("pickQuickFix: >=20g gap, veg", () => {
  assertEquals(pickQuickFix(25, "veg"), "Quick fix: 100g paneer or a scoop of whey.");
});
Deno.test("pickQuickFix: >=20g gap, non-veg", () => {
  assertEquals(pickQuickFix(20, null), "Quick fix: 100g chicken or 3 boiled eggs.");
});
Deno.test("pickQuickFix: <20g gap, veg", () => {
  assertEquals(pickQuickFix(10, "veg"), "Quick fix: a glass of milk + 30g almonds.");
});
Deno.test("pickQuickFix: <20g gap, non-veg", () => {
  // Corrected 2026-09-27 (a2b-2): the prior version of this test asserted
  // "eggetarian", a value that has never existed anywhere in this app's
  // diet_preference vocabulary (confirmed by grep across lib/ + supabase/)
  // — an asserted_fixture_value defect (code-review lens 8), not a real
  // coverage case. "pescatarian" is a REAL value the client's Edit Profile
  // chips write and correctly falls to the non-veg branch.
  assertEquals(pickQuickFix(5, "pescatarian"), "Quick fix: 2 boiled eggs.");
});
Deno.test("pickQuickFix: >=40g gap, vegetarian counts as veg (a2b-2 regression — the P1 vocabulary bug)", () => {
  // Real bug, not hypothetical: onboarding writes diet_preference='veg' by
  // default, but the client's own Edit Profile chips write 'vegetarian' —
  // the value most users who explicitly picked a diet preference actually
  // carry. Pre-fix, isVeg checked only "veg"/"vegan", so every vegetarian
  // user who had edited their profile got the non-veg suggestion.
  assertEquals(pickQuickFix(45, "vegetarian"), "Quick fix: 200g paneer + a glass of milk.");
});
Deno.test("pickQuickFix: keto falls to non-veg branch", () => {
  assertEquals(pickQuickFix(5, "keto"), "Quick fix: 2 boiled eggs.");
});

Deno.test("buildProteinGapMessage assembles greeting + gap + quick-fix + CTA", () => {
  const msg = buildProteinGapMessage("Rahul", 45, "veg");
  assertEquals(
    msg,
    "Rahul — 45g short on protein today. Quick fix: 200g paneer + a glass of milk. Want a dinner suggestion?",
  );
});

Deno.test("buildProteinGapMessage: null name omits greeting", () => {
  const msg = buildProteinGapMessage(null, 10, "non_veg");
  assertEquals(msg, "10g short on protein today. Quick fix: 2 boiled eggs. Want a dinner suggestion?");
});

Deno.test("protein-gap-alert no longer calls Gemini", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes("geminiChat(")) {
    throw new Error("expected geminiChat( to be gone from protein-gap-alert/index.ts");
  }
});
