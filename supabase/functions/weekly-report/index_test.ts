// supabase/functions/weekly-report/index_test.ts
//
// OI-238 (sibling of A5/OI-226, f7a2c9) — weekly-report's own geminiChat()
// call had no reportGeminiExhaustion wiring at all: `lastError` was never
// even destructured from GeminiResult, so the !aiContent branch structurally
// could not alert on total Gemini exhaustion.
//
// index.ts calls `serve(...)` at module scope with no `import.meta.main`
// guard (same shape as assess-body-composition/index.ts and
// rolling-context/index.ts — see either file's own index_test.ts header;
// daily-snapshot/index.ts GAINED this guard in the single-owner-a2a batch,
// 2026-09-27, so it is no longer a same-shaped sibling here), so importing
// this file directly would boot a real HTTP server. This is a SOURCE-GREP
// wiring test, position-scoped to the
// `!aiContent` branch and comment-stripped before any `.includes()` check —
// the exact discipline `gemini_retry_coverage_lib.dart`'s `stripComments()`
// and this same batch's sibling diagnose-doc (f7a2c9) both document, after a
// raw `.contains()` check was found to stay falsely green against a
// commented-out (not deleted) call.
//
// Run:
//   deno test --no-check --allow-all --node-modules-dir=none supabase/functions/weekly-report/

import { assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

const source = Deno.readTextFileSync(
  new URL("./index.ts", import.meta.url),
);

function stripComments(s: string): string {
  return s.replace(/\/\*[\s\S]*?\*\//g, " ").replace(/\/\/[^\n]*/g, " ");
}

Deno.test("weekly-report imports reportGeminiExhaustion", () => {
  assert(
    source.includes(
      'import { reportGeminiExhaustion } from "../_shared/gemini_failure_alert.ts";',
    ),
    "index.ts must import reportGeminiExhaustion",
  );
});

Deno.test("weekly-report destructures lastError from its geminiChat call (OI-238)", () => {
  const callIdx = source.indexOf("await geminiChat({");
  assert(callIdx >= 0, "geminiChat call not found");
  const destructureLine = source.slice(Math.max(0, callIdx - 200), callIdx);
  assert(
    destructureLine.includes("lastError"),
    `expected the geminiChat destructure to include lastError, got: ${destructureLine}`,
  );
});

Deno.test(
  "weekly-report reports Gemini exhaustion on the !aiContent branch, BEFORE the 502 return (OI-238)",
  () => {
    const branchIdx = source.indexOf("if (!aiContent)");
    assert(branchIdx >= 0, "!aiContent branch not found");
    const nextFnEnd = source.indexOf("\n    }\n", branchIdx);
    assert(nextFnEnd >= 0, "could not bound the !aiContent block");
    const rawBlock = source.slice(branchIdx, nextFnEnd);
    const block = stripComments(rawBlock);

    assert(
      block.includes("reportGeminiExhaustion("),
      "the !aiContent branch must call reportGeminiExhaustion",
    );
    assert(
      block.includes('"ai_proxy_gemini_exhausted"'),
      "must reuse the shared ai-proxy dedup source (live user traffic, same quota)",
    );
    assert(
      block.includes('"weekly_report"'),
      'must tag this call site with endpoint "weekly_report"',
    );
    assert(
      block.includes("lastError ?? null"),
      "must forward the real lastError (or null), not a fabricated value",
    );

    const reportIdx = block.indexOf("reportGeminiExhaustion(");
    const jsonResponseIdx = block.indexOf("jsonResponse(");
    assert(
      reportIdx >= 0 && jsonResponseIdx >= 0 && reportIdx < jsonResponseIdx,
      "the alert must fire BEFORE the 502 jsonResponse is returned",
    );
  },
);

// Unit 3b-3 B-pass seat A finding 2: the report reads the strategy (behind the
// manual switch) and puts the line right under the protein target. The line's
// own text is tested on weeklyReportDietStrategyLine (_shared/diet_strategies_test.ts).
Deno.test("weekly-report reads diet_strategy; the line only with the switch on", () => {
  const code = stripComments(source);
  assert(
    code.includes("const dietStrategyOn = !dietStrategyManualRulesOff();"),
    "the switch is read once",
  );
  assert(
    /\.from\("user_profile"\)\s*\.select\(\s*"[^"]*, diet_strategy",/.test(code),
    "the profile read selects diet_strategy",
  );
  assert(
    code.includes("const dietStrategyLine = dietStrategyOn\n      ? weeklyReportDietStrategyLine(userProfile?.diet_strategy, Boolean(hasPro))\n      : \"\";"),
    "the line uses the stored strategy and the PRO answer, empty with the switch off",
  );
});

// 3b-3 B-pass seat D finding 1: these tests run with --no-check and read the
// source as text, so a deleted import would stay green here; pin both.
Deno.test("weekly-report imports the strategy line and its switch", () => {
  const code = stripComments(source);
  assert(
    /import \{[^}]*\bdietStrategyManualRulesOff\b[^}]*\} from "\.\.\/_shared\/captain_manual\.ts";/
      .test(code),
    "dietStrategyManualRulesOff is imported from the captain manual",
  );
  assert(
    code.includes(
      'import { weeklyReportDietStrategyLine } from "../_shared/diet_strategies.ts";',
    ),
    "weeklyReportDietStrategyLine is imported",
  );
});

Deno.test("weekly-report puts the strategy line under the protein target", () => {
  const code = stripComments(source);
  const at = code.indexOf("- Daily protein target: ${proteinTarget}g${dietStrategyLine ? `\\n${dietStrategyLine}` : \"\"}\n\n**THIS WEEK'S NUTRITION");
  assert(at >= 0, "the line sits right after the protein target, nothing when empty");
  assert(code.indexOf("const dietStrategyLine =") < at, "computed before the message");
});

// Diet plan Unit 4 (B-pass seat C finding 6): the weekly report bundles the
// captain manual, whose SUPPLEMENTS passage is conditional on
// snapshot.profile.diet_supplements. The report sends no snapshot, so the
// passage is inert here ONLY while nothing in this function mentions the key.
// Presence-only pin: a later edit that adds the key to the weekly message
// must also decide the gate on purpose.
Deno.test("weekly-report never sends diet_supplements (the manual passage stays inert here)", () => {
  assert(!stripComments(source).includes("diet_supplements"));
});

// ── Unit 3D-a (OI-175 / FOB-4): the hold week line ─────────────────────────────
// The behavioural proof is `_shared/hold_week_test.ts` (the pure builders, the fail-closed phase filter and the
// never-throwing read against a stub client). These pins (presence only) prove this file calls them the way the
// plan says: today's IST date as both bounds, the phase filter on the progress row, and the built line in the prompt.

Deno.test("weekly-report reads the hold for today only, through the fail-closed phase filter", () => {
  const code = stripComments(source);
  assert(
    code.includes('import { fetchHoldOrdinals, phaseOneUserIds, reportWeekLine } from "../_shared/hold_week.ts";'),
    "index.ts must import the hold helpers",
  );
  assert(
    code.includes("phaseOneUserIds([{ user_id: targetUserId, current_phase: userProgress.current_phase }])"),
    "the hold read must be gated by phaseOneUserIds on the progress row",
  );
  assert(
    code.includes("? phaseOneUserIds(") && code.includes(": [];"),
    "no progress row must ask for no holds (fail closed)",
  );
  assert(
    code.includes("fetchHoldOrdinals(supabase, holdUserIds, todayStr, todayStr)"),
    "the hold read must use today's IST date as both bounds (where the user is now, as the app shows)",
  );
});

Deno.test("weekly-report's prompt prints the built week line, not the raw current_week", () => {
  const code = stripComments(source);
  assert(code.includes("reportWeekLine("), "the week line must be built by reportWeekLine");
  assert(code.includes("- ${weekLine}"), "the prompt must print the built week line");
  assert(
    !code.includes("- Current week: ${userProgress?.current_week ?? 1}"),
    "the raw current_week line must be gone from the prompt",
  );
});
