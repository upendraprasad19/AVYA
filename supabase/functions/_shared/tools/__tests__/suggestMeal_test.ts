import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { suggestMealTool } from "../nutrition/suggestMeal.ts";

// Note: handler integration tests against a real Supabase client are deferred
// (would require a seeded test DB). Schema + metadata coverage only.

Deno.test("suggestMeal — schema accepts minimal valid args", () => {
  const result = suggestMealTool.schema.safeParse({
    remainingKcal: 600,
  });
  assertEquals(result.success, true);
});

Deno.test("suggestMeal — schema accepts full valid args", () => {
  const result = suggestMealTool.schema.safeParse({
    remainingKcal: 800,
    remainingProteinG: 40,
    isVeg: true,
    cuisine: "indian",
    mealType: "dinner",
    excludeIngredients: ["peanut", "shellfish"],
  });
  assertEquals(result.success, true);
});

Deno.test("suggestMeal — schema rejects remainingKcal below 50", () => {
  const result = suggestMealTool.schema.safeParse({ remainingKcal: 49 });
  assertEquals(result.success, false);
});

Deno.test("suggestMeal — schema rejects remainingKcal above 3000", () => {
  const result = suggestMealTool.schema.safeParse({ remainingKcal: 3001 });
  assertEquals(result.success, false);
});

Deno.test("suggestMeal — schema accepts remainingKcal at boundaries", () => {
  const min = suggestMealTool.schema.safeParse({ remainingKcal: 50 });
  assertEquals(min.success, true);
  const max = suggestMealTool.schema.safeParse({ remainingKcal: 3000 });
  assertEquals(max.success, true);
});

Deno.test("suggestMeal — schema rejects non-integer remainingKcal", () => {
  const result = suggestMealTool.schema.safeParse({ remainingKcal: 600.5 });
  assertEquals(result.success, false);
});

Deno.test("suggestMeal — schema rejects remainingProteinG below 0", () => {
  const result = suggestMealTool.schema.safeParse({
    remainingKcal: 600,
    remainingProteinG: -1,
  });
  assertEquals(result.success, false);
});

Deno.test("suggestMeal — schema rejects remainingProteinG above 150", () => {
  const result = suggestMealTool.schema.safeParse({
    remainingKcal: 600,
    remainingProteinG: 151,
  });
  assertEquals(result.success, false);
});

Deno.test("suggestMeal — schema accepts remainingProteinG at boundaries", () => {
  const min = suggestMealTool.schema.safeParse({
    remainingKcal: 600,
    remainingProteinG: 0,
  });
  assertEquals(min.success, true);
  const max = suggestMealTool.schema.safeParse({
    remainingKcal: 600,
    remainingProteinG: 150,
  });
  assertEquals(max.success, true);
});

Deno.test("suggestMeal — schema rejects bad cuisine enum", () => {
  const result = suggestMealTool.schema.safeParse({
    remainingKcal: 600,
    cuisine: "italian",
  });
  assertEquals(result.success, false);
});

Deno.test("suggestMeal — schema accepts each valid cuisine", () => {
  for (const cuisine of ["indian", "asian", "mediterranean", "western", "any"]) {
    const result = suggestMealTool.schema.safeParse({
      remainingKcal: 600,
      cuisine,
    });
    assertEquals(result.success, true, `cuisine=${cuisine} should be valid`);
  }
});

Deno.test("suggestMeal — schema rejects bad mealType enum", () => {
  const result = suggestMealTool.schema.safeParse({
    remainingKcal: 600,
    mealType: "brunch",
  });
  assertEquals(result.success, false);
});

Deno.test("suggestMeal — schema accepts each valid mealType", () => {
  for (const mealType of ["breakfast", "lunch", "dinner", "snack"]) {
    const result = suggestMealTool.schema.safeParse({
      remainingKcal: 600,
      mealType,
    });
    assertEquals(result.success, true, `mealType=${mealType} should be valid`);
  }
});

Deno.test("suggestMeal — schema rejects excludeIngredients > 10 items", () => {
  const result = suggestMealTool.schema.safeParse({
    remainingKcal: 600,
    excludeIngredients: Array.from({ length: 11 }, (_, i) => `item${i}`),
  });
  assertEquals(result.success, false);
});

Deno.test("suggestMeal — schema accepts excludeIngredients with exactly 10 items", () => {
  const result = suggestMealTool.schema.safeParse({
    remainingKcal: 600,
    excludeIngredients: Array.from({ length: 10 }, (_, i) => `item${i}`),
  });
  assertEquals(result.success, true);
});

Deno.test("suggestMeal — metadata", () => {
  assertEquals(suggestMealTool.tier, "pro");
  assertEquals(suggestMealTool.kind, "read");
  assertEquals(suggestMealTool.family, "nutrition");
  assertEquals(suggestMealTool.name, "suggestMeal");
  assertEquals(suggestMealTool.maxLatencyMs, 4000);
});

Deno.test("suggestMeal — description present and non-empty", () => {
  assertEquals(typeof suggestMealTool.description, "string");
  assertEquals(suggestMealTool.description.length > 0, true);
});

Deno.test("suggestMeal — handler is defined (read tool)", () => {
  assertEquals(typeof suggestMealTool.handler, "function");
});

// ── Diet plan Unit 2b (2026-11-14, plan diet-food-type-server §2.6, T5):
// the handler against a table-backed fake (fake_sb.ts) ─────────────────────
import { assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { fakeSb } from "./fake_sb.ts";
import {
  animalRowAllowed,
  EGG_RE,
  LEGACY_IS_VEG_DESCRIPTION,
  MEAT_RE,
  veganRowAllowed,
} from "../nutrition/suggestMeal.ts";

let nextId = 0;
function food(name: string, isVeg: boolean, isVegan = false, kcal = 300, protein = 15) {
  nextId++;
  return {
    id: `f${nextId}`,
    name,
    category: "x",
    calories_std: kcal,
    protein_std: protein,
    carbs_std: 20,
    fat_std: 8,
    standard_serving_desc: "1 serving",
    standard_serving_g: 150,
    is_indian: true,
    is_veg: isVeg,
    is_vegan: isVegan,
  };
}

const FOODS = [
  food("Moong Dal", true, true),
  food("Paneer Bhurji", true),
  food("Egg Plant Curry", true, true),
  food("Eggless Cake", true),
  food("Honey", true, true),
  food("Honey Chilli Potato", true, true),
  food("Cold Coffee", true, true),
  food("Pav Bhaji", true, true),
  food("Black Coffee", true, true, 60, 1),
  food("Cashew Milk", true, true),
  food("Almond Butter", true, true),
  food("Egg Bhurji", false),
  food("Chicken Egg Roll", false),
  food("Murgh Tikka", false),
  food("Prawn Curry", false),
  food("Fish Cake", false),
  food("Chicken and Prawn Curry", false),
  food("Macher Jhol", false),
  food("Cod", false),
  food("Fish Tikka", false),
  food("Crab Meat (canned)", false),
  food("Duck Egg", false),
  food("Quail Egg", false),
  food("Fish Oil Capsule", false),
  food("McChicken", false),
  food("Spare Ribs", false),
  food("Mutton Rogan Josh", false),
  food("Huge Thali", true, false, 2000, 60), // over budget
];

function ctxFor(diet: unknown, opts: { profileRows?: unknown[] } = {}) {
  const { sb, calls } = fakeSb({
    user_profile: opts.profileRows ?? [{ user_id: "u1", diet_preference: diet }],
    food_database: FOODS,
  });
  return { ctx: { userId: "u1", isPro: true, sb, requestId: "r" }, calls };
}

// deno-lint-ignore no-explicit-any
async function namesFor(diet: unknown, extra: Record<string, unknown> = {}): Promise<{ names: Set<string>; res: any }> {
  const { ctx } = ctxFor(diet);
  // deno-lint-ignore no-explicit-any
  const res: any = await suggestMealTool.handler!(ctx as any, { remainingKcal: 800, ...extra } as any);
  // top_picks is capped at 5; read every surviving candidate through a
  // budget-wide query: rank is irrelevant here, membership is.
  return { names: new Set(res.top_picks.map((p: { name: string }) => p.name)), res };
}

// The handler returns 5 picks; membership tests run the filter helpers on the
// whole fixture and one handler call per type checks wiring + counts.
Deno.test("Unit 2b: eggetarian keeps egg rows (incl. Quail Egg) and drops meat and fish", () => {
  const keep = ["Egg Bhurji", "Quail Egg", "Duck Egg"];
  const drop = ["Chicken Egg Roll", "Murgh Tikka", "Prawn Curry", "Fish Cake", "McChicken", "Spare Ribs", "Fish Oil Capsule", "Cod"];
  for (const n of keep) assert(animalRowAllowed(n, "eggetarian"), n);
  for (const n of drop) assert(!animalRowAllowed(n, "eggetarian"), n);
});

Deno.test("Unit 2b: pescatarian keeps egg, fish and seafood rows; drops meat and the capsule", () => {
  const keep = ["Egg Bhurji", "Prawn Curry", "Fish Cake", "Macher Jhol", "Cod", "Fish Tikka", "Crab Meat (canned)", "Duck Egg"];
  const drop = ["Chicken and Prawn Curry", "Chicken Egg Roll", "Murgh Tikka", "McChicken", "Spare Ribs", "Fish Oil Capsule", "Mutton Rogan Josh"];
  for (const n of keep) assert(animalRowAllowed(n, "pescatarian"), n);
  for (const n of drop) assert(!animalRowAllowed(n, "pescatarian"), n);
});

Deno.test("Unit 2b: a dish with egg or fish AND meat is dropped for both types (hand list, one meat word each)", () => {
  // Each name's only disqualifier is its meat word, so dropping that word
  // from the meat rule turns its row green (mutation B9 and siblings).
  const mixed = [
    "Murgh Anda Curry", "Chicken Egg Roll", "Mutton Egg Biryani", "Egg Keema Paratha",
    "Egg Kheema Pav", "Seekh Egg Roll", "Egg Kabab", "Egg Kebab Platter", "Gosht Anda Curry",
    "Bacon and Eggs", "Ham and Egg Sandwich", "Sausage Egg Muffin", "Turkey Egg White Wrap",
    "Beef and Egg Fried Rice", "Pork Egg Roll", "Salami Omelette", "Pepperoni Omelette",
    "Lamb and Fish Stew", "Goat and Fish Curry", "Tangdi Egg Masala", "Nihari with Egg",
    "Haleem with Egg", "Rogan Egg Curry", "Duck and Egg Noodles", "Quail and Egg Salad",
    "Veal Egg Schnitzel", "Goose and Egg Pie", "Ribs and Eggs", "Lard Fried Egg",
    "Egg and Meat Pie", "Surf and Turf (Beef, Prawn)",
  ];
  for (const n of mixed) {
    assert(!animalRowAllowed(n, "eggetarian"), `eggetarian kept ${n}`);
    assert(!animalRowAllowed(n, "pescatarian"), `pescatarian kept ${n}`);
  }
});

Deno.test("Unit 2b: the egg rule is whole-word (Eggplant / Eggless are not eggs)", () => {
  assert(!EGG_RE.test("Eggplant Curry"));
  assert(!EGG_RE.test("Eggless Cake"));
  assert(EGG_RE.test("Boiled Eggs"));
  assert(MEAT_RE.test("McChicken"), "meat matches inside a chain name");
});

Deno.test("Unit 2b: handler per stored food type (candidate counts over the whole fixture)", async () => {
  const within = FOODS.filter((f) => f.calories_std <= 880);
  const vegCount = within.filter((f) => f.is_veg).length;
  // veg: every is_veg row, incl. Egg Plant Curry and Eggless Cake.
  {
    const { res } = await namesFor("vegetarian");
    assertEquals(res.total_candidates_searched, vegCount);
    assert(res.notes.includes("Filtered for food type: Veg."));
  }
  // vegan: is_vegan rows minus the dairy/honey deny-list.
  {
    const { res } = await namesFor("vegan");
    const vegan = within.filter((f) => f.is_vegan);
    const denied = ["Honey", "Honey Chilli Potato", "Cold Coffee", "Pav Bhaji"];
    assertEquals(res.total_candidates_searched, vegan.length - denied.length);
    for (const p of res.top_picks) assert(!denied.includes(p.name), p.name);
  }
  // eggetarian: veg rows + 3 egg rows.
  {
    const { res } = await namesFor("eggetarian");
    assertEquals(res.total_candidates_searched, vegCount + 3);
  }
  // pescatarian: veg rows + egg (3) + fish/seafood (Prawn Curry, Fish Cake,
  // Macher Jhol, Cod, Fish Tikka, Crab Meat) = 9.
  {
    const { res } = await namesFor("pescatarian");
    assertEquals(res.total_candidates_searched, vegCount + 9);
  }
  // non_veg (and never chosen, and keto): everything within budget.
  for (const d of ["non_veg", null, "keto"]) {
    const { res } = await namesFor(d);
    assertEquals(res.total_candidates_searched, within.length, String(d));
  }
});

Deno.test("Unit 2b: the model's isVeg narrows a non-veg user to the is_veg column (not a name list)", async () => {
  const { res, names } = await namesFor("non_veg", { isVeg: true });
  const vegCount = FOODS.filter((f) => f.calories_std <= 880 && f.is_veg).length;
  assertEquals(res.total_candidates_searched, vegCount);
  for (const n of names) assert(FOODS.find((f) => f.name === n)!.is_veg, n);
  // isVeg never widens a vegan.
  const vegan = await namesFor("vegan", { isVeg: true });
  for (const p of vegan.res.top_picks) assert(FOODS.find((f) => f.name === p.name)!.is_vegan, p.name);
});

Deno.test("Unit 2b: the calorie cap compares numbers (fake_sb lte is numeric now)", async () => {
  const { res } = await namesFor("non_veg");
  for (const p of res.top_picks) assert(p.calories <= 880, `${p.name} ${p.calories}`);
  assert(!res.top_picks.some((p: { name: string }) => p.name === "Huge Thali"));
});

Deno.test("Unit 2b B-pass 1: an egg word no longer admits fish, a hot dog or a McMuffin for an eggetarian", () => {
  // Each name has an egg word, so before the fix the egg rule admitted it.
  for (const n of ["Tuna Egg Salad", "Egg and Prawn Fried Rice", "Egg Roll (Fish)", "Egg Sushi Roll"]) {
    assert(!animalRowAllowed(n, "eggetarian"), `eggetarian kept fish: ${n}`);
    assert(animalRowAllowed(n, "pescatarian"), `pescatarian dropped: ${n}`);
  }
  for (const n of ["Egg Hot Dog", "Egg Hotdog", "Egg McMuffin", "Egg and Frankfurter", "Egg Jerky Bowl"]) {
    assert(!animalRowAllowed(n, "eggetarian"), `eggetarian kept meat: ${n}`);
    assert(!animalRowAllowed(n, "pescatarian"), `pescatarian kept meat: ${n}`);
  }
  // A capsule is never a meal, even with an egg word.
  assert(!animalRowAllowed("Egg Yolk Lecithin Capsule", "eggetarian"));
  assert(!animalRowAllowed("Egg Yolk Lecithin Capsule", "pescatarian"));
  // Sushi with fish stays for a pescatarian.
  assert(animalRowAllowed("Sushi Roll (Salmon)", "pescatarian"));
});

Deno.test("Unit 2b B-pass 2: vegan deny words are absolute; the plant rescue needs the plant word right before", () => {
  const drop = [
    "Curd Rice", "Ghee Rice", "Rice with Ghee", "Honey Oat Bar", "Peanut Butter with Honey",
    "Cheese Nut Sandwich", "Rice Kheer", "Lassi", "Buttermilk", "Rasmalai", "Masala Chaas",
    "Boondi Raita", "Kulfi", "Vanilla Ice Cream", "Veg Mayo Sandwich", "Egg Fried Rice",
    "Coconut Malai Curry", "Oats with Milk", "Butter Naan", "Paneer Tikka", "Whey Shake",
    "Cream of Mushroom Soup", "Gelatin Dessert", "Khoya Barfi", "Rabri", "Shrikhand",
    "Greek Yogurt", "Dahi Vada", "Almond Cheese Milk Cake",
  ];
  const keep = [
    "Almond Milk", "Soy Milk", "Oat Milk Latte", "Peanut Butter", "Cashew Cheese", "Soy Curd",
    "Coconut Yogurt", "Rice Milk", "Moong Dal", "Rajma", "Banana", "Cocoa Butter",
    "Egg Plant Curry", // eggplant written as two words is not an egg
  ];
  for (const n of drop) assert(!veganRowAllowed(n), `vegan kept ${n}`);
  for (const n of keep) assert(veganRowAllowed(n), `vegan dropped ${n}`);
});

Deno.test("Unit 2b B-pass 2: on the bundled asset the stricter vegan rule keeps every row the old rule kept", async () => {
  const asset = JSON.parse(
    await Deno.readTextFile(new URL("../../../../../assets/data/food_database.json", import.meta.url)),
  ) as Array<{ name: string; is_vegan?: boolean }>;
  const vegan = asset.filter((r) => r.is_vegan === true).map((r) => r.name);
  // The pre-B-pass rule, frozen here as the oracle: a deny word dropped the
  // row unless a plant word appeared anywhere in the name.
  const oldDeny = /\b(honey|ghee|paneer|curd|dahi|whey|cheese|malai|butter|milk|cold coffee|pav)\b/i;
  const oldPlant = /\b(soy|almond|oat|coconut|peanut|cashew|rice|hemp|nut|cocoa)\b/i;
  const oldKept = vegan.filter((n) => !oldDeny.test(n) || oldPlant.test(n));
  const kept = vegan.filter(veganRowAllowed);
  const dropped = vegan.filter((n) => !veganRowAllowed(n));
  console.log(`[vegan scan] ${kept.length} of ${vegan.length} kept; dropped: ${dropped.join(" | ")}`);
  // Measured 2026-11-14 (643 is_vegan rows after Unit 1's asset, 637 before):
  // both rules keep the same rows, so the stricter rule loses no real plant row.
  assert(vegan.length >= 600, `precondition: the asset's vegan rows (${vegan.length})`);
  assertEquals(kept, oldKept);
  assert(dropped.includes("Honey") && dropped.includes("Pav Bhaji"), "positive control: the tagged dairy/honey rows drop");
});

Deno.test("Unit 2b B-pass 3: a profile read error shows vegan options (they suit every food type)", async () => {
  // deno-lint-ignore no-explicit-any
  const sb: any = {
    from(t: string) {
      if (t === "user_profile") {
        const b: any = { select: () => b, eq: () => b, limit: () => Promise.resolve({ data: null, error: { message: "boom" } }) };
        return b;
      }
      return fakeSb({ food_database: FOODS }).sb.from(t);
    },
  };
  for (const extra of [{}, { isVeg: true }]) {
    // deno-lint-ignore no-explicit-any
    const res: any = await suggestMealTool.handler!({ userId: "u1", isPro: true, sb, requestId: "r" } as any, { remainingKcal: 800, ...extra } as any);
    assert(res.notes.includes("Could not read the user's food type; showing vegan options, which suit every food type."));
    assert(res.top_picks.length > 0, "precondition: vegan picks exist");
    for (const p of res.top_picks) {
      assert(FOODS.find((f) => f.name === p.name)!.is_vegan, p.name);
      assert(veganRowAllowed(p.name), p.name);
    }
    assertEquals(res.query_summary, "800 kcal budget, vegan");
  }
});

Deno.test("Unit 2b B-pass 4: the kill switch restores the pre-2b isVeg description the model reads", () => {
  // deno-lint-ignore no-explicit-any
  const desc = () => (suggestMealTool.schema as any).shape.isVeg.description as string;
  assert(desc().includes("the tool already applies the user's stored food type"));
  Deno.env.set("DISABLE_SUGGESTMEAL_STORED_FOOD_TYPE", "true");
  try {
    assertEquals(desc(), LEGACY_IS_VEG_DESCRIPTION);
    assertEquals(
      LEGACY_IS_VEG_DESCRIPTION,
      "Set to true to restrict to vegetarian options. Omit if no preference. (Approximated by excluding common non-veg keywords from the food name — the food_database has no explicit is_veg flag.)",
    );
  } finally {
    Deno.env.delete("DISABLE_SUGGESTMEAL_STORED_FOOD_TYPE");
  }
});

Deno.test("Unit 2b B-pass 6: past the 500-row limit, the most protein-rich veg rows are kept", async () => {
  // 520 low-protein veg rows first, then 5 high-protein ones: an unordered
  // limit(500) would never see the last five.
  const rows = [
    ...Array.from({ length: 520 }, (_, i) => ({
      id: `L${i}`, name: `Plain Veg ${i}`, category: "x", calories_std: 200, protein_std: 1,
      carbs_std: 40, fat_std: 2, standard_serving_desc: null, standard_serving_g: 100,
      is_indian: true, is_veg: true, is_vegan: true,
    })),
    ...Array.from({ length: 5 }, (_, i) => ({
      id: `H${i}`, name: `Dal Power ${i}`, category: "x", calories_std: 200, protein_std: 20 + i,
      carbs_std: 20, fat_std: 2, standard_serving_desc: null, standard_serving_g: 100,
      is_indian: true, is_veg: true, is_vegan: true,
    })),
  ];
  const { sb } = fakeSb({ user_profile: [{ user_id: "u1", diet_preference: "veg" }], food_database: rows });
  // deno-lint-ignore no-explicit-any
  const res: any = await suggestMealTool.handler!({ userId: "u1", isPro: true, sb, requestId: "r" } as any, { remainingKcal: 800, remainingProteinG: 15 } as any);
  assert(res.top_picks.some((p: { name: string }) => p.name.startsWith("Dal Power")), JSON.stringify(res.top_picks.map((p: { name: string }) => p.name)));
});

Deno.test("Unit 2b: a profile read error falls back to the request only, with a note [superseded by B-pass 3]", async () => {
  // deno-lint-ignore no-explicit-any
  const sb: any = {
    from(t: string) {
      if (t === "user_profile") {
        const b: any = { select: () => b, eq: () => b, limit: () => Promise.resolve({ data: null, error: { message: "boom" } }) };
        return b;
      }
      return fakeSb({ food_database: FOODS }).sb.from(t);
    },
  };
  // deno-lint-ignore no-explicit-any
  const res: any = await suggestMealTool.handler!({ userId: "u1", isPro: true, sb, requestId: "r" } as any, { remainingKcal: 800, isVeg: true } as any);
  assert(res.notes.includes("Could not read the user's food type; showing vegan options, which suit every food type."));
  for (const p of res.top_picks) assert(FOODS.find((f) => f.name === p.name)!.is_vegan, p.name);
  assert(res.query_summary.includes("vegan"));
});

Deno.test("Unit 2b: an absent profile row is the default (non_veg)", async () => {
  const { ctx } = ctxFor(undefined, { profileRows: [] });
  // deno-lint-ignore no-explicit-any
  const res: any = await suggestMealTool.handler!(ctx as any, { remainingKcal: 800 } as any);
  assert(res.notes.includes("Filtered for food type: Non-veg."));
});

Deno.test("Unit 2b: the user_profile read is scoped to the caller", async () => {
  const { ctx, calls } = ctxFor("veg");
  // deno-lint-ignore no-explicit-any
  await suggestMealTool.handler!(ctx as any, { remainingKcal: 800 } as any);
  const profileCall = calls.find((c) => c.table === "user_profile")!;
  assertEquals(profileCall.filters, [["eq", "user_id", "u1"]]);
});

Deno.test("Unit 2b: DISABLE_SUGGESTMEAL_STORED_FOOD_TYPE=true runs today's handler (golden)", async () => {
  Deno.env.set("DISABLE_SUGGESTMEAL_STORED_FOOD_TYPE", "true");
  try {
    const { ctx, calls } = ctxFor("vegan");
    // deno-lint-ignore no-explicit-any
    const res: any = await suggestMealTool.handler!(ctx as any, { remainingKcal: 800, isVeg: true } as any);
    assert(!calls.some((c) => c.table === "user_profile"), "today's handler never reads the profile");
    // Today's name-keyword list: drops every name containing "egg" (incl.
    // Egg Plant Curry and Eggless Cake) and keeps the is_vegan-ignorant rest.
    const legacyKept = FOODS.filter((f) =>
      f.calories_std <= 880 &&
      !["chicken","mutton","lamb","beef","pork","bacon","ham","sausage","fish","tuna","salmon","prawn","shrimp","crab","lobster","egg","anchovy","sardine","mackerel","turkey","duck","venison","kebab","keema","biryani"]
        .some((k) => f.name.toLowerCase().includes(k))
    );
    assertEquals(res.total_candidates_searched, legacyKept.length);
    assertEquals(res.query_summary, "800 kcal budget, veg");
    assert(res.notes.some((n: string) => n.startsWith("Vegetarian filter is heuristic")));
  } finally {
    Deno.env.delete("DISABLE_SUGGESTMEAL_STORED_FOOD_TYPE");
  }
});

Deno.test("Unit 2b: seed scan of the bundled asset's is_veg = false rows (kept rows listed, no meat)", async () => {
  const asset = JSON.parse(
    await Deno.readTextFile(new URL("../../../../../assets/data/food_database.json", import.meta.url)),
  ) as Array<{ name: string; is_veg?: boolean }>;
  const nonVeg = asset.filter((r) => r.is_veg === false).map((r) => r.name);
  assert(nonVeg.length >= 150, "precondition: the asset's non-veg rows");
  // An oracle written independently of MEAT_RE: plain words a reviewer
  // would call meat, checked on the whole lower-cased name.
  const meatWords = ["chicken", "mutton", "beef", "pork", "lamb", "goat", "turkey", "bacon", "salami",
    "pepperoni", "sausage", "keema", "kebab", "kabab", "liver", "lard", "veal", "ribs", "jerky", "hot dog",
    "duck breast", "goose breast", "quail (cooked)", "ham (", "brisket"];
  for (const type of ["eggetarian", "pescatarian"] as const) {
    const kept = nonVeg.filter((n) => animalRowAllowed(n, type));
    console.log(`[seed scan] ${type}: ${kept.length} of ${nonVeg.length} kept: ${kept.join(" | ")}`);
    for (const n of kept) {
      const l = n.toLowerCase();
      assert(!meatWords.some((w) => l.includes(w)), `${type} kept meat: ${n}`);
      if (type === "eggetarian") {
        assert(EGG_RE.test(n), `eggetarian kept a non-egg row: ${n}`);
      }
    }
    // Positive controls.
    assert(kept.includes("Egg Bhurji"), `${type}: Egg Bhurji`);
    assert(kept.length >= 30, `${type}: kept ${kept.length}`);
  }
  assert(nonVeg.filter((n) => animalRowAllowed(n, "pescatarian")).includes("Rohu Fish Curry"));
});

// ── Diet plan Unit 3b-2 (2026-11-14, docs/plans/diet-strategy-3b.md §5): a
// PRO caller's stored diet strategy caps carbs per standard serving ──────────
import {
  carbsStdCapFor,
  KETO_CARBS_STD_CAP,
  LOW_CARB_CARBS_STD_CAP,
} from "../nutrition/suggestMeal.ts";

function carbFood(name: string, carbs: number, isVeg = true, isVegan = true, category = "x", protein = 15) {
  return { ...food(name, isVeg, isVegan, 300, protein), carbs_std: carbs, category };
}
// Rows AT each cap and just over it (B-pass seat C finding 1), and a
// protein powder under the keto cap that would out-rank every food
// (seat B finding 2).
const CARB_FOODS = [
  carbFood("Paneer Tikka", 4, true, false),
  carbFood("Tofu Scramble", 5),
  carbFood("Cheese Cubes", 6, true, false),
  carbFood("Masala Peanuts", 6.1),
  carbFood("Chana Salad", 18),
  carbFood("Rajma", 24),
  carbFood("Sprouts Chaat", 25),
  carbFood("Moong Dal Khichdi", 26),
  carbFood("Veg Pulao", 45),
  carbFood("Egg Bhurji", 2, false, false),
  carbFood("Egg Fried Rice", 40, false, false),
  carbFood("Chicken Tikka", 3, false, false),
  carbFood("Fish Curry", 4, false, false),
  carbFood("Soy Protein Isolate", 3, true, true, "supplements", 80),
];
const carbsOf = (name: string) => CARB_FOODS.find((f) => f.name === name)!.carbs_std;

// deno-lint-ignore no-explicit-any
async function strategyRun(profile: Record<string, unknown>, opts: { isPro?: boolean; args?: Record<string, unknown> } = {}): Promise<{ res: any; calls: any[] }> {
  const { sb, calls } = fakeSb({
    user_profile: [{ user_id: "u1", ...profile }],
    food_database: CARB_FOODS,
  });
  // deno-lint-ignore no-explicit-any
  const res: any = await suggestMealTool.handler!(
    { userId: "u1", isPro: opts.isPro ?? true, sb, requestId: "r" } as any,
    { remainingKcal: 800, ...(opts.args ?? {}) } as any,
  );
  return { res, calls };
}
const names = (res: { top_picks: { name: string }[] }) => res.top_picks.map((p) => p.name);
const pickedCarbs = (res: { top_picks: { name: string }[] }) => names(res).map(carbsOf);
const foodCalls = (calls: { table: string; filters: unknown[][] }[]) => calls.filter((c) => c.table === "food_database");
const hasFilter = (c: { filters: unknown[][] }, op: string, col: string, val?: unknown) =>
  c.filters.some((f) => f[0] === op && f[1] === col && (val === undefined || f[2] === val));
const KETO_NOTE = "Filtered for diet strategy: Keto (at most 6 g carbs per serving; protein powders left out).";
const LOW_CARB_NOTE = "Filtered for diet strategy: Low carb (at most 25 g carbs per serving; protein powders left out).";

Deno.test("Unit 3b-2: the cap per strategy and food type", () => {
  assertEquals(carbsStdCapFor("balanced", "non_veg"), null);
  for (const t of ["non_veg", "veg", "eggetarian", "pescatarian"] as const) {
    assertEquals(carbsStdCapFor("keto", t), KETO_CARBS_STD_CAP, t);
    assertEquals(carbsStdCapFor("low_carb", t), LOW_CARB_CARBS_STD_CAP, t);
    assertEquals(carbsStdCapFor("balanced", t), null, t);
  }
  assertEquals(carbsStdCapFor("keto", "vegan"), LOW_CARB_CARBS_STD_CAP);
  assertEquals(carbsStdCapFor("low_carb", "vegan"), LOW_CARB_CARBS_STD_CAP);
  assertEquals([KETO_CARBS_STD_CAP, LOW_CARB_CARBS_STD_CAP], [6, 25]);
});

Deno.test("Unit 3b-2: PRO keto caps at 6 g on the query (a row AT 6 g kept, 6.1 g not), no powders, with a note", async () => {
  const { res, calls } = await strategyRun({ diet_preference: "veg", diet_strategy: "keto" });
  assert(names(res).includes("Cheese Cubes"), "precondition: the row at exactly 6 g is kept");
  assert(!names(res).includes("Masala Peanuts"), "6.1 g is over the cap");
  for (const c of pickedCarbs(res)) assert(c <= 6, String(c));
  assert(!names(res).includes("Soy Protein Isolate"), "protein powders are left out under a cap");
  assertEquals(foodCalls(calls).length, 1);
  for (const c of foodCalls(calls)) {
    assert(hasFilter(c, "lte", "carbs_std", 6));
    assert(hasFilter(c, "neq", "category", "supplements"));
  }
  assert(res.notes.includes(KETO_NOTE));
});

Deno.test("Unit 3b-2: PRO low carb caps at 25 g (a row AT 25 g kept, 26 g not); vegan keto gets the low carb cap and is told so", async () => {
  {
    const { res, calls } = await strategyRun({ diet_preference: "veg", diet_strategy: "low_carb" }, {
      args: { remainingProteinG: 0 },
    });
    for (const c of foodCalls(calls)) assert(hasFilter(c, "lte", "carbs_std", 25));
    const rows = (await strategyRun({ diet_preference: "veg", diet_strategy: "low_carb" })).calls;
    assert(foodCalls(rows).length === 1);
    for (const c of pickedCarbs(res)) assert(c <= 25, String(c));
    assert(res.notes.includes(LOW_CARB_NOTE));
  }
  {
    // The boundary on the rows the query returns, not only the picks: the
    // fake applies the filters, so read what reached the ranking.
    const { res } = await strategyRun({ diet_preference: "veg", diet_strategy: "low_carb" });
    assertEquals(res.total_candidates_searched, CARB_FOODS.filter((f) => f.is_veg && f.carbs_std <= 25 && f.category !== "supplements").length);
  }
  {
    const { res, calls } = await strategyRun({ diet_preference: "vegan", diet_strategy: "keto" });
    for (const c of foodCalls(calls)) assert(hasFilter(c, "lte", "carbs_std", 25));
    for (const c of pickedCarbs(res)) assert(c <= 25, String(c));
    assert(pickedCarbs(res).some((c) => c > 6), "the low carb cap, not keto's");
    assert(res.notes.includes(LOW_CARB_NOTE));
  }
});

Deno.test("Unit 3b-2: eggetarian and pescatarian keto cap BOTH queries (veg rows and the is_veg = false rows)", async () => {
  {
    const { res, calls } = await strategyRun({ diet_preference: "eggetarian", diet_strategy: "keto" });
    assertEquals(foodCalls(calls).length, 2);
    for (const c of foodCalls(calls)) {
      assert(hasFilter(c, "lte", "carbs_std", 6));
      assert(hasFilter(c, "neq", "category", "supplements"));
    }
    assert(names(res).includes("Egg Bhurji"));
    assert(!names(res).includes("Egg Fried Rice"));
  }
  {
    const { res, calls } = await strategyRun({ diet_preference: "pescatarian", diet_strategy: "keto" });
    assertEquals(foodCalls(calls).length, 2);
    for (const c of foodCalls(calls)) assert(hasFilter(c, "lte", "carbs_std", 6));
    assert(names(res).includes("Fish Curry"));
    assert(!names(res).includes("Chicken Tikka"), "pescatarian: no meat");
  }
});

Deno.test("Unit 3b-2: the cap composes with cuisine indian", async () => {
  const { res, calls } = await strategyRun({ diet_preference: "veg", diet_strategy: "keto" }, { args: { cuisine: "indian" } });
  assert(res.top_picks.length > 0, "precondition");
  for (const c of foodCalls(calls)) {
    assert(hasFilter(c, "lte", "carbs_std", 6));
    assert(hasFilter(c, "eq", "is_indian", true));
  }
});

Deno.test("Unit 3b-2: an empty capped answer still names the cap (B-pass seat A finding 1)", async () => {
  const { res } = await strategyRun({ diet_preference: "veg", diet_strategy: "keto" }, { args: { remainingKcal: 1 } });
  assertEquals(res.top_picks.length, 0, "precondition: nothing under 1 kcal");
  assert(res.notes.includes(KETO_NOTE));
});

Deno.test("Unit 3b-2: no cap for a free caller, Balanced, an unknown value, or the kill switch", async () => {
  const uncapped = async (profile: Record<string, unknown>, isPro = true) => {
    const { res, calls } = await strategyRun(profile, { isPro });
    assert(foodCalls(calls).length > 0, "precondition: the food query ran");
    for (const c of foodCalls(calls)) {
      assert(!c.filters.some((f) => f[1] === "carbs_std"), JSON.stringify(profile));
      assert(!c.filters.some((f) => f[1] === "category"), JSON.stringify(profile));
    }
    assert(!res.notes.some((n: string) => n.startsWith("Filtered for diet strategy")));
    assert(pickedCarbs(res).some((c) => c > 25) || names(res).includes("Soy Protein Isolate"));
  };
  await uncapped({ diet_preference: "non_veg", diet_strategy: "keto" }, false);
  await uncapped({ diet_preference: "non_veg", diet_strategy: "balanced" });
  await uncapped({ diet_preference: "non_veg", diet_strategy: "paleo" });
  await uncapped({ diet_preference: "non_veg" });
  Deno.env.set("DISABLE_SUGGESTMEAL_DIET_STRATEGY", "true");
  try {
    await uncapped({ diet_preference: "non_veg", diet_strategy: "keto" });
  } finally {
    Deno.env.delete("DISABLE_SUGGESTMEAL_DIET_STRATEGY");
  }
  // "TRUE" is not the switch.
  Deno.env.set("DISABLE_SUGGESTMEAL_DIET_STRATEGY", "TRUE");
  try {
    const { calls } = await strategyRun({ diet_preference: "non_veg", diet_strategy: "keto" });
    assert(foodCalls(calls).length > 0, "precondition");
    for (const c of foodCalls(calls)) assert(hasFilter(c, "lte", "carbs_std", 6));
  } finally {
    Deno.env.delete("DISABLE_SUGGESTMEAL_DIET_STRATEGY");
  }
});

Deno.test("Unit 3b-2: the food-type switch runs the verbatim pre-2b handler, which applies no strategy (accepted, B-pass finding 1)", async () => {
  Deno.env.set("DISABLE_SUGGESTMEAL_STORED_FOOD_TYPE", "true");
  try {
    const { res, calls } = await strategyRun({ diet_preference: "veg", diet_strategy: "keto" });
    assertEquals(calls.filter((c: { table: string }) => c.table === "user_profile").length, 0, "no profile read");
    for (const c of foodCalls(calls)) assert(!c.filters.some((f) => f[1] === "carbs_std"));
    assert(!res.notes.some((n: string) => n.startsWith("Filtered for diet strategy")));
  } finally {
    Deno.env.delete("DISABLE_SUGGESTMEAL_STORED_FOOD_TYPE");
  }
});

Deno.test("Unit 3b-2: a profile read error keeps the vegan fail-safe and applies no strategy", async () => {
  const foods = fakeSb({ food_database: CARB_FOODS });
  // deno-lint-ignore no-explicit-any
  const sb: any = {
    from(t: string) {
      if (t === "user_profile") {
        // deno-lint-ignore no-explicit-any
        const b: any = { select: () => b, eq: () => b, limit: () => Promise.resolve({ data: null, error: { message: "boom" } }) };
        return b;
      }
      return foods.sb.from(t);
    },
  };
  // deno-lint-ignore no-explicit-any
  const res: any = await suggestMealTool.handler!({ userId: "u1", isPro: true, sb, requestId: "r" } as any, { remainingKcal: 800 } as any);
  assert(res.top_picks.length > 0, "precondition: an answer");
  assert(foodCalls(foods.calls).length > 0, "precondition: the food query ran");
  for (const c of foodCalls(foods.calls)) assert(!c.filters.some((f) => f[1] === "carbs_std" || f[1] === "category"));
  assert(!res.notes.some((n: string) => n.startsWith("Filtered for diet strategy")));
  assert(res.notes.includes("Could not read the user's food type; showing vegan options, which suit every food type."));
});

Deno.test("Unit 3b-2: the profile read selects diet_strategy only when the strategy can apply (B-pass seat B finding 3)", async () => {
  const selectsFor = async (isPro: boolean) => {
    const selects: string[] = [];
    const base = fakeSb({ user_profile: [{ user_id: "u1", diet_preference: "veg" }], food_database: CARB_FOODS }).sb;
    // deno-lint-ignore no-explicit-any
    const sb: any = {
      from(t: string) {
        const b = base.from(t);
        const orig = b.select;
        // deno-lint-ignore no-explicit-any
        b.select = (c?: string, o?: any) => { if (t === "user_profile") selects.push(c ?? ""); return orig(c, o); };
        return b;
      },
    };
    // deno-lint-ignore no-explicit-any
    await suggestMealTool.handler!({ userId: "u1", isPro, sb, requestId: "r" } as any, { remainingKcal: 800 } as any);
    return selects;
  };
  assertEquals(await selectsFor(true), ["diet_preference, diet_strategy"]);
  assertEquals(await selectsFor(false), ["diet_preference"]);
  Deno.env.set("DISABLE_SUGGESTMEAL_DIET_STRATEGY", "true");
  try {
    assertEquals(await selectsFor(true), ["diet_preference"], "the switch restores the pre-3b-2 read");
  } finally {
    Deno.env.delete("DISABLE_SUGGESTMEAL_DIET_STRATEGY");
  }
});
