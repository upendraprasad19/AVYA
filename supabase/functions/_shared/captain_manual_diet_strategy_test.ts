// Diet plan Unit 3b-2 (2026-11-14, docs/plans/diet-strategy-3b.md §5): the
// DIET STRATEGY passage of the captain manual. It sits outside every
// food-type string, so the two switches compose: four env combinations.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  CAPTAIN_MANUAL,
  CAPTAIN_MANUAL_LEGACY_FOOD,
  captainManual,
  captainPrompt,
  DIET_STRATEGY_MANUAL_PASSAGE,
  FOOD_TYPE_MANUAL_RULES_LEGACY,
  FOOD_TYPE_MANUAL_RULES_NEW,
} from "./captain_manual.ts";

const FOOD = "DISABLE_FOOD_TYPE_MANUAL_RULES";
const STRAT = "DISABLE_DIET_STRATEGY_MANUAL_RULES";

function withEnv<T>(env: Record<string, string>, fn: () => T): T {
  for (const [k, v] of Object.entries(env)) Deno.env.set(k, v);
  try {
    return fn();
  } finally {
    for (const k of Object.keys(env)) Deno.env.delete(k);
  }
}

const count = (hay: string, needle: string) => hay.split(needle).length - 1;

Deno.test("the passage is in the manual once, outside every food-type string, after the food-type lines", () => {
  assertEquals(count(CAPTAIN_MANUAL, DIET_STRATEGY_MANUAL_PASSAGE), 1);
  assertEquals(count(CAPTAIN_MANUAL_LEGACY_FOOD, DIET_STRATEGY_MANUAL_PASSAGE), 1);
  for (const s of [...FOOD_TYPE_MANUAL_RULES_NEW, ...FOOD_TYPE_MANUAL_RULES_LEGACY]) {
    assert(!s.includes("Diet strategy"), "no food-type string holds the passage");
  }
  const at = CAPTAIN_MANUAL.indexOf(DIET_STRATEGY_MANUAL_PASSAGE);
  assert(at > CAPTAIN_MANUAL.indexOf(FOOD_TYPE_MANUAL_RULES_NEW[1]), "after the food-type lines");
  assert(at < CAPTAIN_MANUAL.indexOf("- Festival eating:"), "inside SECTION 7 DIET");
});

Deno.test("the passage says what the plan says", () => {
  for (const s of [
    "snapshot.profile.diet_strategy: balanced, low_carb or keto; absent = balanced",
    "snapshot.daily_targets.carbs and fat; calories and protein do not change",
    "keto: no rice, roti, bread, fruit, sugar or gravy curries",
    "eggs, paneer, cheese, meat, fish, plain vegetables, ghee, nuts and seeds",
    "Vegan with keto: plan low_carb meals from plant foods",
    "low_carb: one grain portion at lunch, none at dinner",
    "Never change the diet strategy or the food type in chat",
    "diabetes medicine, is pregnant or breastfeeding, or has kidney disease",
  ]) {
    assert(DIET_STRATEGY_MANUAL_PASSAGE.includes(s), s);
  }
});

Deno.test("the Older values line is reworded in BOTH copies (template and the food-type string)", () => {
  const now =
    "- Older values: vegetarian = veg; keto or low_carb = non_veg (a food type; the diet strategy is a separate field, below); empty or missing = non_veg.";
  assertEquals(count(CAPTAIN_MANUAL, now), 1);
  assert(FOOD_TYPE_MANUAL_RULES_NEW[1].includes(now));
  assert(!CAPTAIN_MANUAL.includes("non_veg with a low-carb emphasis"));
});

Deno.test("the four switch combinations (each exactly \"true\")", () => {
  const noPassage = (s: string) => s.replace(DIET_STRATEGY_MANUAL_PASSAGE, "");
  assertEquals(captainManual(), CAPTAIN_MANUAL);
  assertEquals(withEnv({ [FOOD]: "true" }, captainManual), CAPTAIN_MANUAL_LEGACY_FOOD);
  assertEquals(withEnv({ [STRAT]: "true" }, captainManual), noPassage(CAPTAIN_MANUAL));
  assertEquals(
    withEnv({ [FOOD]: "true", [STRAT]: "true" }, captainManual),
    noPassage(CAPTAIN_MANUAL_LEGACY_FOOD),
  );
  assert(!withEnv({ [FOOD]: "true", [STRAT]: "true" }, captainManual).includes("Diet strategy ("));
  for (const v of ["TRUE", "1", ""]) {
    assertEquals(withEnv({ [STRAT]: v }, captainManual), CAPTAIN_MANUAL, JSON.stringify(v));
  }
  // Every channel's prompt starts with the composed manual.
  assert(withEnv({ [STRAT]: "true" }, () => captainPrompt("chat")).startsWith(noPassage(CAPTAIN_MANUAL)));
});
