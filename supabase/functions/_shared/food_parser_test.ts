// OI-493 Landing A: the per-item rules of the coach meal parser.
// parseFoodText has no Gemini seam, so its pure helper is what is covered.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { normaliseParsedItems } from "./food_parser.ts";

Deno.test("normaliseParsedItems — a non-array becomes []", () => {
  for (const raw of [undefined, null, "dal", 3, { name: "Dal" }]) {
    assertEquals(normaliseParsedItems(raw), [], String(raw));
  }
});

Deno.test("normaliseParsedItems — fibre is kept when a finite number >= 0", () => {
  const items = normaliseParsedItems([
    { name: "Dal", quantity: "2 katori", calories: 250, protein_g: 12, carbs_g: 30, fat_g: 6, fiber_g: 8 },
    { name: "Ghee", quantity: "1 tsp", calories: 45, protein_g: 0, carbs_g: 0, fat_g: 5, fiber_g: 0 },
    { name: "Oats", quantity: "40 g", calories: 150, protein_g: 5, carbs_g: 27, fat_g: 3, fiber_g: 4.2 },
  ]);
  assertEquals(items.map((i) => i.fiber_g), [8, 0, 4.2]);
});

Deno.test("normaliseParsedItems — missing, NaN, Infinity, negative or non-number fibre becomes 0", () => {
  const bad: unknown[] = [undefined, null, NaN, Infinity, -1, "8", { g: 8 }];
  const items = normaliseParsedItems(
    bad.map((fiber_g) => ({ name: "X", quantity: "1", calories: 100, protein_g: 1, carbs_g: 1, fat_g: 1, fiber_g })),
  );
  assertEquals(items.map((i) => i.fiber_g), bad.map(() => 0));
});

Deno.test("normaliseParsedItems — Atwater recompute unchanged (0 or missing calories)", () => {
  const items = normaliseParsedItems([
    { name: "A", quantity: "1", calories: 0, protein_g: 10, carbs_g: 20, fat_g: 5 },
    { name: "B", quantity: "1", protein_g: "4", carbs_g: 0, fat_g: 0 },
    { name: "C", quantity: "1", calories: 300, protein_g: 10, carbs_g: 20, fat_g: 5 },
  ]);
  // 4*10 + 4*20 + 9*5 = 165; 4*4 = 16; a positive value is kept as is.
  assertEquals(items.map((i) => i.calories), [165, 16, 300]);
  // Macros are coerced to numbers.
  assertEquals(items[1].protein_g, 4);
});
