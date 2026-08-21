// Deno tests for the HOLD WEEKS section of the Captain's Manual (FOB-3 / OI-60).
// Run: deno test --allow-all supabase/functions/_shared/captain_manual_hold_test.ts
//
// The manual is one long template literal, so the FIRST thing importing it
// proves is that the section's many backticks (`snapshot.hold`, `hold.label`…)
// are ESCAPED. An unescaped one terminates the literal and the module stops
// parsing — which does not fail loudly on deploy: ai-proxy 503s at boot while
// the previous bundle keeps serving until the next request pool turns over.
// That is the deploy-skill 6.5 shape and it nearly shipped here.
//
// The rest pins the instruction the client half cannot enforce. The Dart
// snapshot can put `hold` in front of the model; only this text stops the model
// reading `current_week: 4` beside `tier: free` and synthesizing "final week of
// Phase I / upgrade now" at the user who just chose to stay.

import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { CAPTAIN_MANUAL } from "./captain_manual.ts";

Deno.test("the manual parses and carries a HOLD WEEKS section", () => {
  assert(CAPTAIN_MANUAL.length > 1000, "manual should be substantial");
  assertStringIncludes(CAPTAIN_MANUAL, "HOLD WEEKS");
});

Deno.test("it names the snapshot key the coach must read", () => {
  assertStringIncludes(CAPTAIN_MANUAL, "snapshot.hold");
  assertStringIncludes(CAPTAIN_MANUAL, "hold.label");
});

Deno.test("it tells the coach to IGNORE the projected week fields", () => {
  // Both are emitted on every snapshot and both carry the same clamped number
  // on every hold day at every ordinal. Naming them explicitly is the point:
  // "read hold" alone leaves the false number in play.
  assertStringIncludes(CAPTAIN_MANUAL, "snapshot.progress.current_week");
  assertStringIncludes(CAPTAIN_MANUAL, "snapshot.current_plan_summary.week");
  const ignoreAt = CAPTAIN_MANUAL.indexOf("IGNORE");
  assert(ignoreAt > 0, "the instruction must be an explicit IGNORE");
});

Deno.test("it forbids the false milestone by name", () => {
  assertStringIncludes(CAPTAIN_MANUAL, "final week of Phase I");
  // …and forbids rather than merely mentions it.
  const idx = CAPTAIN_MANUAL.indexOf("final week of Phase I");
  const window = CAPTAIN_MANUAL.slice(Math.max(0, idx - 200), idx);
  assert(
    window.includes("NEVER"),
    "the phrase must appear under a NEVER, not as a suggestion",
  );
});

Deno.test("the PRO-unlock line carries the holder caveat", () => {
  // "free locks at Phase I after 4 weeks" is TRUE for an advancing user and
  // FALSE for a holder. Left unqualified it is the premise the model reasons
  // from, several hundred lines above the hold section.
  const idx = CAPTAIN_MANUAL.indexOf("free locks at Phase I after 4 weeks");
  assert(idx > 0, "the PRO-unlock line must still be present");
  const after = CAPTAIN_MANUAL.slice(idx, idx + 200);
  assertStringIncludes(after, "NOT TRUE OF A HOLDER");
});

Deno.test("it says an ABSENT hold key means not holding", () => {
  // Without this the model may hunt for a hold in unrelated fields; the key is
  // absent for almost every user, which is the ship-dark default.
  assertStringIncludes(CAPTAIN_MANUAL, "ABSENT");
});
