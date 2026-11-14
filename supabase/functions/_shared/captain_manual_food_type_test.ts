// Diet plan Unit 2b (2026-11-14, plan diet-food-type-server §2.5, T4/T6):
// the manual names the five food types; the pre-2b text is served only when
// DISABLE_FOOD_TYPE_MANUAL_RULES is exactly "true"; every prompt builder
// calls captainManual(), never the bare constant.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  CAPTAIN_MANUAL,
  CAPTAIN_MANUAL_LEGACY_FOOD,
  captainManual,
  captainPrompt,
  FOOD_TYPE_MANUAL_RULES_LEGACY,
  FOOD_TYPE_MANUAL_RULES_NEW,
} from "./captain_manual.ts";

Deno.test("the manual names every food type and the older spellings", () => {
  for (const s of [
    "veg (no meat, fish or eggs)",
    "non_veg (anything)",
    "eggetarian (veg plus eggs)",
    "pescatarian (veg plus eggs, fish and seafood)",
    "vegan (no animal products: no dairy, eggs, meat, fish, honey or whey",
    "Never suggest a food outside it.",
    "Older values: vegetarian = veg; keto or low_carb = non_veg",
    "empty or missing = non_veg",
  ]) {
    assert(CAPTAIN_MANUAL.includes(s), s);
  }
  assert(!CAPTAIN_MANUAL.includes("Vegetarian-first"));
  assert(!CAPTAIN_MANUAL.includes("where eggetarian"));
  // Kept lines.
  assert(CAPTAIN_MANUAL.includes("Jain restrictions: no root vegetables"));
  assert(CAPTAIN_MANUAL.includes("B12: 500-1000 mcg/wk sublingual"));
});

Deno.test("the legacy text is exactly today's: both passages swapped back, nothing else", () => {
  assertEquals(FOOD_TYPE_MANUAL_RULES_NEW.length, 2);
  for (let i = 0; i < 2; i++) {
    assert(CAPTAIN_MANUAL.includes(FOOD_TYPE_MANUAL_RULES_NEW[i]), `new ${i} present`);
    assert(!CAPTAIN_MANUAL.includes(FOOD_TYPE_MANUAL_RULES_LEGACY[i]), `old ${i} absent`);
    assert(CAPTAIN_MANUAL_LEGACY_FOOD.includes(FOOD_TYPE_MANUAL_RULES_LEGACY[i]), `legacy has old ${i}`);
    assert(!CAPTAIN_MANUAL_LEGACY_FOOD.includes(FOOD_TYPE_MANUAL_RULES_NEW[i]), `legacy lacks new ${i}`);
  }
  assert(CAPTAIN_MANUAL_LEGACY_FOOD.includes("Vegetarian-first. ~40% of users vegetarian."));
  // Round trip: putting the new passages back gives the new manual exactly.
  assertEquals(
    CAPTAIN_MANUAL_LEGACY_FOOD
      .replace(FOOD_TYPE_MANUAL_RULES_LEGACY[0], FOOD_TYPE_MANUAL_RULES_NEW[0])
      .replace(FOOD_TYPE_MANUAL_RULES_LEGACY[1], FOOD_TYPE_MANUAL_RULES_NEW[1]),
    CAPTAIN_MANUAL,
  );
});

Deno.test("captainManual() / captainPrompt() follow the switch, exactly \"true\"", () => {
  assertEquals(captainManual(), CAPTAIN_MANUAL);
  for (const v of ["TRUE", "1", ""]) {
    Deno.env.set("DISABLE_FOOD_TYPE_MANUAL_RULES", v);
    try {
      assertEquals(captainManual(), CAPTAIN_MANUAL, JSON.stringify(v));
    } finally {
      Deno.env.delete("DISABLE_FOOD_TYPE_MANUAL_RULES");
    }
  }
  Deno.env.set("DISABLE_FOOD_TYPE_MANUAL_RULES", "true");
  try {
    assertEquals(captainManual(), CAPTAIN_MANUAL_LEGACY_FOOD);
    assert(captainPrompt("weekly").startsWith(CAPTAIN_MANUAL_LEGACY_FOOD));
  } finally {
    Deno.env.delete("DISABLE_FOOD_TYPE_MANUAL_RULES");
  }
  assert(captainPrompt("chat").startsWith(CAPTAIN_MANUAL));
});

Deno.test("PRESENCE: ai-proxy and weekly-report call captainManual(), never the constant", async () => {
  const strip = (s: string) => s.replace(/\/\/.*$/gm, "");
  const proxy = strip(await Deno.readTextFile(new URL("../ai-proxy/index.ts", import.meta.url)));
  const report = strip(await Deno.readTextFile(new URL("../weekly-report/index.ts", import.meta.url)));
  for (const [name, src] of [["ai-proxy", proxy], ["weekly-report", report]]) {
    assert(src.includes("captainManual()"), name);
    assert(!/\bCAPTAIN_MANUAL\b/.test(src), `${name} must not read the constant`);
  }
  // weekly-report's diet line: the closed label set, the legacy line only
  // under the switch.
  assert(report.includes("foodTypeManualRulesOff()"));
  assert(report.includes(": dietPreferenceLine(userProfile?.diet_preference)"));
});
