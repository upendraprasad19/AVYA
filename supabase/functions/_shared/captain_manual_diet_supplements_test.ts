// Diet plan Unit 4 (2026-11-15, docs/plans/diet-supplements.md §6): the
// SUPPLEMENTS passage of the captain manual and the dose vector it shares
// with the app. Run:
//   deno test --no-check --allow-all --node-modules-dir=none supabase/functions/_shared/captain_manual_diet_supplements_test.ts
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  CAPTAIN_MANUAL,
  CAPTAIN_MANUAL_LEGACY_FOOD,
  captainManual,
  captainPrompt,
  DIET_STRATEGY_MANUAL_PASSAGE,
  DIET_SUPPLEMENTS_MANUAL_PASSAGE,
} from "./captain_manual.ts";
import { FOOD_TYPE_KEYS } from "./food_types.ts";

const FOOD = "DISABLE_FOOD_TYPE_MANUAL_RULES";
const STRAT = "DISABLE_DIET_STRATEGY_MANUAL_RULES";
const SUPP = "DISABLE_DIET_SUPPLEMENTS_MANUAL_RULES";
const SWITCHES = [FOOD, STRAT, SUPP];

// Clears every DISABLE_* switch of this file first (an ambient value would
// make the plain calls and the false branches lie), sets [env], and restores
// every prior value afterwards, also on a throw.
function withEnv<T>(env: Record<string, string>, fn: () => T): T {
  const before = SWITCHES.map((k) => [k, Deno.env.get(k)] as const);
  for (const k of SWITCHES) Deno.env.delete(k);
  for (const [k, v] of Object.entries(env)) Deno.env.set(k, v);
  try {
    return fn();
  } finally {
    for (const [k, v] of before) v === undefined ? Deno.env.delete(k) : Deno.env.set(k, v);
  }
}

const count = (hay: string, needle: string) => hay.split(needle).length - 1;

const s5Start = CAPTAIN_MANUAL.indexOf("## SECTION 5");
const s5End = CAPTAIN_MANUAL.indexOf("## SECTION 6");
assert(s5Start >= 0 && s5End > s5Start, "SECTION 5 and SECTION 6 headers are both found, in order");
const s5 = CAPTAIN_MANUAL.slice(s5Start, s5End);
assert(s5.length < 4000, `SECTION 5 stays one section (${s5.length} chars)`);

const vector = JSON.parse(
  Deno.readTextFileSync(new URL("./testdata/supplement_card.json", import.meta.url)),
) as { manualTokens: Record<string, string>; cardRows: Record<string, string[]> };

Deno.test("the passage is in the manual once, inside SECTION 5, as its last block", () => {
  assertEquals(count(CAPTAIN_MANUAL, DIET_SUPPLEMENTS_MANUAL_PASSAGE), 1);
  assertEquals(count(CAPTAIN_MANUAL_LEGACY_FOOD, DIET_SUPPLEMENTS_MANUAL_PASSAGE), 1);
  assertEquals(count(s5, DIET_SUPPLEMENTS_MANUAL_PASSAGE), 1);
  const at = s5.indexOf(DIET_SUPPLEMENTS_MANUAL_PASSAGE);
  assert(at > s5.indexOf("- Endorse herbal/ayurvedic supplements without specific evidence"), "after the Never list");
  assert(at < s5.indexOf("\n---"), "before the rule that closes SECTION 5: it is the last block");
});

Deno.test("every line of the passage hangs off the snapshot key, and the header bounds its own scope", () => {
  const lines = DIET_SUPPLEMENTS_MANUAL_PASSAGE.split("\n").filter((l) => l.trim() !== "");
  const header = lines[0];
  assert(header.startsWith("If snapshot.profile.diet_supplements is true"), header);
  assert(header.includes("snapshot.profile.age is 18 or more"), "the server repeats the age condition");
  assert(header.includes("absent = off"), "absent means none of the bullets apply");
  assert(
    header.includes("none of the bullets directly below, up to the next --- line"),
    "the scope ends at the next rule, not at the end of the manual",
  );
  for (const l of lines.slice(1)) assert(l.startsWith("- "), l);
  assertEquals(lines.length, 6);
  for (const s of [
    "Multivitamin: the one item with no band above",
    "one cup 30-45 min before training is fine",
    "or who is pregnant or breastfeeding, checks with their doctor",
    "one scoop a day in total: the plan's shake or a post-workout scoop, not both",
    "(whey; plant protein for a vegan; fine on keto)",
  ]) {
    assert(DIET_SUPPLEMENTS_MANUAL_PASSAGE.includes(s), s);
    assertEquals(count(CAPTAIN_MANUAL, s), 1, `${s} appears once in the manual`);
  }
  // The doctor line comes BEFORE the coffee line and names the coffee.
  const p = DIET_SUPPLEMENTS_MANUAL_PASSAGE;
  assert(p.indexOf("Before starting any of this, including the coffee below") < p.indexOf("Black coffee"));
  assert(!/`|\$\{|\\/.test(p), "no template-literal hazard");
});

Deno.test("the switch removes the passage byte-exactly (the pre-Unit-4 text returns)", () => {
  assertEquals(withEnv({}, captainManual), CAPTAIN_MANUAL);
  const off = withEnv({ [SUPP]: "true" }, captainManual);
  assertEquals(off.length, CAPTAIN_MANUAL.length - DIET_SUPPLEMENTS_MANUAL_PASSAGE.length);
  assert(
    off.includes("- Endorse herbal/ayurvedic supplements without specific evidence\n\n---\n"),
    "the blank line and rule are restored",
  );
  for (const l of ["diet_supplements", "Multivitamin: the one item", "Black coffee, no sugar"]) {
    assert(!off.includes(l), l);
  }
  assert(off.includes("Diet strategy (snapshot.profile.diet_strategy"), "the strategy passage stays");
  for (const v of ["TRUE", "1", "yes", " true", ""]) {
    assertEquals(withEnv({ [SUPP]: v }, captainManual), CAPTAIN_MANUAL, JSON.stringify(v));
  }
});

Deno.test("the three switches compose independently (all eight combinations)", () => {
  for (const food of [false, true]) {
    for (const strat of [false, true]) {
      for (const supp of [false, true]) {
        const env: Record<string, string> = {};
        if (food) env[FOOD] = "true";
        if (strat) env[STRAT] = "true";
        if (supp) env[SUPP] = "true";
        let want = food ? CAPTAIN_MANUAL_LEGACY_FOOD : CAPTAIN_MANUAL;
        if (strat) want = want.replace(DIET_STRATEGY_MANUAL_PASSAGE, "");
        if (supp) want = want.replace(DIET_SUPPLEMENTS_MANUAL_PASSAGE, "");
        const got = withEnv(env, captainManual);
        assertEquals(got, want, JSON.stringify(env));
        // Independent of the replace the code uses:
        assertEquals(got.includes("diet_supplements"), !supp, JSON.stringify(env));
        assertEquals(got.includes("Diet strategy (snapshot"), !strat, JSON.stringify(env));
      }
    }
  }
});

Deno.test("every prompt builder serves the switched manual (captainPrompt goes through captainManual)", () => {
  const off = withEnv({ [SUPP]: "true" }, () => captainPrompt("chat"));
  assert(off.startsWith(CAPTAIN_MANUAL.replace(DIET_SUPPLEMENTS_MANUAL_PASSAGE, "")));
  assert(!off.includes("diet_supplements"));
  assert(withEnv({}, () => captainPrompt("chat")).includes(DIET_SUPPLEMENTS_MANUAL_PASSAGE));
});

Deno.test("the dose vector: every manual token (value AND unit) is in SECTION 5 exactly once", () => {
  assertEquals(Object.keys(vector.manualTokens).sort(), ["b12", "creatine", "omega3", "vitamin_d3"]);
  // Tokens carry the unit and frequency, so a change of either reddens one place.
  assertEquals(vector.manualTokens.b12, "500-1000 mcg/wk");
  assertEquals(vector.manualTokens.vitamin_d3, "1000-2000 IU/day");
  for (const [k, token] of Object.entries(vector.manualTokens)) {
    assertEquals(count(s5, token), 1, `${k}: "${token}" appears once in SECTION 5`);
  }
});

Deno.test("the vector's card rows follow the food-type keys and the clause the passage states", () => {
  assertEquals(Object.keys(vector.cardRows).sort(), [...FOOD_TYPE_KEYS].sort());
  // The expected split is PARSED from the passage, not typed here.
  const m = DIET_SUPPLEMENTS_MANUAL_PASSAGE.match(
    /B12 and an algal omega-3 are for ([a-z_, ]+) users; ([a-z_, ]+) users take fish oil or oily fish\./,
  );
  assert(m, "the passage states the mapping in the expected form");
  const keys = (t: string) => t.split(/,\s*|\s+and\s+/).map((x) => x.trim()).filter(Boolean).sort();
  const plant = keys(m![1]);
  const fish = keys(m![2].replace(/\s+/g, " "));
  assertEquals(plant, ["eggetarian", "veg", "vegan"]);
  assertEquals(fish, ["non_veg", "pescatarian"]);
  for (const t of plant) {
    const rows = vector.cardRows[t];
    assert(rows.includes("b12") && rows.includes("omega3_algal") && !rows.includes("omega3_fish"), t);
  }
  for (const t of fish) {
    const rows = vector.cardRows[t];
    assert(!rows.includes("b12") && rows.includes("omega3_fish") && !rows.includes("omega3_algal"), t);
  }
  for (const rows of Object.values(vector.cardRows)) {
    assert(rows.includes("creatine") && rows.includes("vitamin_d3") && rows.includes("multivitamin"));
  }
});

Deno.test("no brand name, no number but the coffee window, no dose written in words", () => {
  const p = DIET_SUPPLEMENTS_MANUAL_PASSAGE;
  for (const brand of ["MyProtein", "Optimum", "MuscleBlaze", "GNC", "Dymatize"]) assert(!p.includes(brand), brand);
  assertEquals(p.replaceAll("B12", "").replaceAll("D3", "").replaceAll("omega-3", "").replaceAll("18 or more", "").match(/\d+/g), ["30", "45"]);
  // A dose in words ("five grams", "two scoops") would pass the digit scan.
  assert(
    !/\b(one|two|three|four|five|ten|twenty|\d+)\s*(g|mg|mcg|iu|grams?|scoops?|capsules?|tablets?|pills?)\b/i.test(
      p.replace("one scoop a day in total", "").replace("one standard multivitamin a day", ""),
    ),
    "no dose in words outside the two allowed phrases",
  );
});
