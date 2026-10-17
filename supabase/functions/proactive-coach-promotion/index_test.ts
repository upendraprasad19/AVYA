import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { composeCongrats } from "./congrats.ts";

const CTX = {
  full_name: "Rahul Sharma",
  total_workouts_done: 34,
  current_streak_weeks: 6,
  primary_goal: "build_muscle",
};

Deno.test("composeCongrats: variant 0 uses the approved copy, interpolated", () => {
  const msg = composeCongrats(CTX, "LS", 0);
  assertEquals(
    msg,
    "Rahul — you've been promoted to Leading Seaman. 34 sessions and a 6-week streak got you here. Every rung on this ladder is earned, not given. Keep training toward muscle gain — the next rank is already waiting.",
  );
});

Deno.test("composeCongrats: variant 1 uses the approved copy", () => {
  const msg = composeCongrats(CTX, "LS", 1);
  assertStringIncludes(msg, "Well earned, Rahul. Leading Seaman now");
});

Deno.test("composeCongrats: variant 2 uses the approved copy (with the founder's edit applied)", () => {
  const msg = composeCongrats(CTX, "LS", 2);
  assertStringIncludes(msg, "Rahul, your new rank: Leading Seaman.");
  // The approved edit dropped the word "report" — pin its absence so a
  // regression can't silently reintroduce the pre-edit wording.
  if (msg.includes("report your new rank")) {
    throw new Error("expected the approved edit (dropped 'report') to be present");
  }
});

Deno.test("composeCongrats: unknown rank code falls back to the raw code as the label", () => {
  const msg = composeCongrats(CTX, "ZZZ", 0);
  assertStringIncludes(msg, "promoted to ZZZ");
});

Deno.test("composeCongrats: null full_name falls back to 'soldier'", () => {
  const msg = composeCongrats({ ...CTX, full_name: null }, "LS", 0);
  assertStringIncludes(msg, "soldier —");
});

Deno.test("composeCongrats: with no variantIndex given, still returns one of the 3 approved variants deterministically", () => {
  const a = composeCongrats(CTX, "LS");
  const b = composeCongrats(CTX, "LS");
  assertEquals(a, b, "same ctx + rankCode with no explicit variantIndex must be deterministic, not random per call");
});

Deno.test("proactive-coach-promotion no longer calls Gemini — no fetch to generativelanguage.googleapis.com", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes("generativelanguage.googleapis.com")) {
    throw new Error("expected the raw Gemini fetch endpoint to be gone from proactive-coach-promotion/index.ts");
  }
  if (src.includes("GEMINI_API_KEY")) {
    throw new Error("expected the now-unused GEMINI_API_KEY reference to be removed");
  }
});

Deno.test("the ai_coach_interactions insert no longer mislabels model_used as gemini-2.5-flash, since composeCongrats is now template-only", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes('model_used: "gemini-2.5-flash"')) {
    throw new Error(
      'expected model_used: "gemini-2.5-flash" to be gone — composeCongrats no longer calls ' +
        "Gemini, so this mislabels every promotion event in any future audit that greps model_used",
    );
  }
  if (!src.includes('model_used: "congrats_template"')) {
    throw new Error(
      'expected model_used: "congrats_template" — matching the sibling convention in ' +
        'evaluate-rank-promotions ("ceremony_template") and i-see-you-callout ("i_see_you_template")',
    );
  }
});
