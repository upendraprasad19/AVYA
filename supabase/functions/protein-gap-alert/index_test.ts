import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { buildProteinGapMessage, pickQuickFix } from "./message.ts";

// Diet plan Unit 2b (2026-11-14, plan diet-food-type-server §2.3, T3): the
// whole 5 x 3 table, written out (not derived from message.ts), plus the
// legacy spellings every writer has stored.
const TABLE: Record<string, [string, string, string]> = {
  veg: [
    "Quick fix: 200g paneer + a glass of milk.",
    "Quick fix: 100g paneer or a scoop of whey.",
    "Quick fix: a glass of milk + 30g almonds.",
  ],
  eggetarian: [
    "Quick fix: 4 boiled eggs + 100g paneer.",
    "Quick fix: 3 boiled eggs + a glass of milk.",
    "Quick fix: 2 boiled eggs.",
  ],
  pescatarian: [
    "Quick fix: 200g fish (rohu, tuna) or 3 boiled eggs + a glass of milk.",
    "Quick fix: 100g fish + a glass of milk.",
    "Quick fix: 2 boiled eggs.",
  ],
  vegan: [
    "Quick fix: 200g firm tofu + a cup of soy milk, or 50g dry soya chunks.",
    "Quick fix: 50g dry soya chunks or a cup of roasted chana.",
    "Quick fix: 30g roasted peanuts + a cup of soy milk.",
  ],
  non_veg: [
    "Quick fix: 150g chicken breast or 4 boiled eggs.",
    "Quick fix: 100g chicken or 3 boiled eggs.",
    "Quick fix: 2 boiled eggs.",
  ],
};

Deno.test("pickQuickFix: the 5 x 3 table at each band edge", () => {
  for (const [key, cells] of Object.entries(TABLE)) {
    assertEquals(pickQuickFix(45, key), cells[0], `${key} >= 40`);
    assertEquals(pickQuickFix(40, key), cells[0], `${key} = 40`);
    assertEquals(pickQuickFix(39, key), cells[1], `${key} 39`);
    assertEquals(pickQuickFix(20, key), cells[1], `${key} = 20`);
    assertEquals(pickQuickFix(19, key), cells[2], `${key} 19`);
  }
});

Deno.test("pickQuickFix: legacy and unknown spellings read through the one normaliser", () => {
  // 'vegetarian' (Edit Profile) and 'veg ' with a space are Veg — the a2b-2
  // P1 regression stays pinned.
  assertEquals(pickQuickFix(45, "vegetarian"), TABLE.veg[0]);
  assertEquals(pickQuickFix(45, "veg "), TABLE.veg[0]);
  // keto (a strategy stored as a food type) and never-chosen are Non-veg.
  assertEquals(pickQuickFix(5, "keto"), TABLE.non_veg[2]);
  assertEquals(pickQuickFix(20, null), TABLE.non_veg[1]);
  // An unknown deliberate value is Veg: never chicken by mistake.
  assertEquals(pickQuickFix(45, "xyz"), TABLE.veg[0]);
});

Deno.test("pickQuickFix: vegan never gets an animal product; eggetarian/pescatarian never meat", () => {
  for (const gap of [45, 25, 5]) {
    const vegan = pickQuickFix(gap, "vegan").toLowerCase();
    for (const w of ["paneer", "a glass of milk", "whey", "egg", "chicken", "fish", "curd"]) {
      assertEquals(vegan.includes(w), false, `vegan ${gap}: ${w}`);
    }
    for (const k of ["eggetarian", "pescatarian"]) {
      const t = pickQuickFix(gap, k).toLowerCase();
      assertEquals(t.includes("chicken") || t.includes("mutton"), false, `${k} ${gap}`);
    }
    assertEquals(pickQuickFix(gap, "eggetarian").toLowerCase().includes("fish"), false);
  }
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
