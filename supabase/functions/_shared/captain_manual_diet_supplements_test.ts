// Diet plan Unit 4 (2026-11-15, docs/plans/diet-supplements.md §6): the
// SUPPLEMENTS passage of the captain manual and the dose vector it shares
// with the app. Run:
//   deno test --no-check --allow-all --node-modules-dir=none supabase/functions/_shared/captain_manual_diet_supplements_test.ts
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  CAPTAIN_MANUAL,
  CAPTAIN_MANUAL_LEGACY_FOOD,
  captainManual,
  DIET_STRATEGY_MANUAL_PASSAGE,
  DIET_SUPPLEMENTS_MANUAL_PASSAGE,
} from "./captain_manual.ts";

const FOOD = "DISABLE_FOOD_TYPE_MANUAL_RULES";
const STRAT = "DISABLE_DIET_STRATEGY_MANUAL_RULES";
const SUPP = "DISABLE_DIET_SUPPLEMENTS_MANUAL_RULES";

function withEnv<T>(env: Record<string, string>, fn: () => T): T {
  const before = Object.keys(env).map((k) => [k, Deno.env.get(k)] as const);
  for (const [k, v] of Object.entries(env)) Deno.env.set(k, v);
  try {
    return fn();
  } finally {
    for (const [k, v] of before) v === undefined ? Deno.env.delete(k) : Deno.env.set(k, v);
  }
}

const count = (hay: string, needle: string) => hay.split(needle).length - 1;

const s5 = CAPTAIN_MANUAL.slice(
  CAPTAIN_MANUAL.indexOf("## SECTION 5"),
  CAPTAIN_MANUAL.indexOf("## SECTION 6"),
);

const vector = JSON.parse(
  Deno.readTextFileSync(new URL("./testdata/supplement_stack.json", import.meta.url)),
) as { manualTokens: Record<string, string>; cardRows: Record<string, string[]> };

Deno.test("the passage is in the manual once, inside SECTION 5, after the Never list", () => {
  assertEquals(count(CAPTAIN_MANUAL, DIET_SUPPLEMENTS_MANUAL_PASSAGE), 1);
  assertEquals(count(CAPTAIN_MANUAL_LEGACY_FOOD, DIET_SUPPLEMENTS_MANUAL_PASSAGE), 1);
  assertEquals(count(s5, DIET_SUPPLEMENTS_MANUAL_PASSAGE), 1);
  assert(
    s5.indexOf(DIET_SUPPLEMENTS_MANUAL_PASSAGE) >
      s5.indexOf("- Endorse herbal/ayurvedic supplements without specific evidence"),
    "after the Never list",
  );
  assert(!CAPTAIN_MANUAL.includes(DIET_STRATEGY_MANUAL_PASSAGE.trim() + DIET_SUPPLEMENTS_MANUAL_PASSAGE));
});

Deno.test("every line of the passage hangs off the snapshot key (nothing is standing text)", () => {
  const lines = DIET_SUPPLEMENTS_MANUAL_PASSAGE.split("\n").filter((l) => l.trim() !== "");
  assert(lines[0].startsWith("If snapshot.profile.diet_supplements is true"), lines[0]);
  assert(lines[0].includes("absent = off"), "absent means none of the lines apply");
  for (const l of lines.slice(1)) assert(l.startsWith("- "), l);
  // No line of the passage is a bare rule outside the conditional header: the
  // passage is ONE block, and the multivitamin / coffee lines are in it.
  for (const s of ["Multivitamin: optional", "Black coffee, no sugar, 30-45 min", "or who is pregnant or breastfeeding, checks with their doctor first"]) {
    assert(DIET_SUPPLEMENTS_MANUAL_PASSAGE.includes(s), s);
    assertEquals(count(CAPTAIN_MANUAL, s), 1, `${s} appears once in the manual`);
  }
  assert(!/`|\$\{/.test(DIET_SUPPLEMENTS_MANUAL_PASSAGE));
});

Deno.test("the switch removes the passage byte-exactly (the pre-Unit-4 text returns)", () => {
  assertEquals(captainManual(), CAPTAIN_MANUAL);
  const off = withEnv({ [SUPP]: "true" }, captainManual);
  assertEquals(off.length, CAPTAIN_MANUAL.length - DIET_SUPPLEMENTS_MANUAL_PASSAGE.length);
  // The text around the passage is exactly the original SECTION 5 tail.
  assert(
    off.includes("- Endorse herbal/ayurvedic supplements without specific evidence\n\n---\n"),
    "the blank line and rule are restored",
  );
  for (const l of ["diet_supplements", "Multivitamin: optional", "Black coffee, no sugar"]) {
    assert(!off.includes(l), l);
  }
  assert(off.includes("Diet strategy (snapshot.profile.diet_strategy"), "the strategy passage stays");
  // Only exactly "true" is the switch.
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
        assertEquals(withEnv(env, captainManual), want, JSON.stringify(env));
        const got = withEnv(env, captainManual);
        assertEquals(got.includes("diet_supplements"), !supp, JSON.stringify(env));
        assertEquals(got.includes("Diet strategy (snapshot"), !strat, JSON.stringify(env));
      }
    }
  }
});

Deno.test("the dose vector: every manual token is in SECTION 5 (token level, not the card's sentences)", () => {
  assertEquals(Object.keys(vector.manualTokens).sort(), ["b12", "creatine", "omega3", "vitamin_d3"]);
  for (const [k, token] of Object.entries(vector.manualTokens)) {
    assert(s5.includes(token), `${k}: "${token}" must be in SECTION 5`);
    assertEquals(count(s5, token), 1, `${k}: appears once, so a changed dose reddens exactly one place`);
  }
});

Deno.test("the vector's B12 / algal omega-3 food types equal the mapping the passage states", () => {
  assert(
    DIET_SUPPLEMENTS_MANUAL_PASSAGE.includes(
      "B12 and an algal omega-3 are for vegetarians, eggetarians and vegans; non-veg and pescatarian users take fish oil or oily fish.",
    ),
  );
  const plant = ["veg", "eggetarian", "vegan"];
  const fish = ["non_veg", "pescatarian"];
  assertEquals(Object.keys(vector.cardRows).sort(), [...plant, ...fish].sort());
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

Deno.test("no brand names and no dose outside the manual bands appear in the passage", () => {
  const p = DIET_SUPPLEMENTS_MANUAL_PASSAGE;
  for (const brand of ["MyProtein", "Optimum", "MuscleBlaze", "GNC", "Dymatize"]) assert(!p.includes(brand), brand);
  // The only numbers (ignoring the names "B12" and "omega-3") are the coffee
  // window; every dose stays in SECTION 5's bands.
  assertEquals(p.replaceAll("B12", "").replaceAll("omega-3", "").match(/\d+/g), ["30", "45"]);
});
