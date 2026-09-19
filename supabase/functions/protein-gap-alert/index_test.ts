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
  assertEquals(pickQuickFix(5, "eggetarian"), "Quick fix: 2 boiled eggs.");
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
