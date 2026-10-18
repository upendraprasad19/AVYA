// Deno tests for the PLAN STATUS section of the Captain's Manual (PRO gap policy, Piece B).
// Run: deno test --allow-all supabase/functions/_shared/captain_manual_plan_status_test.ts
//
// The manual is one long template literal: importing it proves the section's backticks are
// escaped (an unescaped one stops the module parsing and ai-proxy 503s at boot).

import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { CAPTAIN_MANUAL } from "./captain_manual.ts";

Deno.test("the manual parses and carries a PLAN STATUS section", () => {
  assertStringIncludes(CAPTAIN_MANUAL, "PLAN STATUS");
  assertStringIncludes(CAPTAIN_MANUAL, "snapshot.plan_status");
});

Deno.test("it names every field the client snapshot emits", () => {
  for (
    const k of [
      "days_since_last_workout",
      "missed_days_in_phase",
      "blank_gap_days_before_phase",
      "current_phase",
      "phase_started_on",
    ]
  ) {
    assertStringIncludes(CAPTAIN_MANUAL, k);
  }
});

Deno.test("an ABSENT plan_status means nothing applies", () => {
  const i = CAPTAIN_MANUAL.indexOf("PLAN STATUS");
  const sec = CAPTAIN_MANUAL.slice(i, i + 900);
  assertStringIncludes(sec, "ABSENT");
  assertStringIncludes(sec, "never invent");
});

Deno.test("blank-gap days are not scolded as missed workouts", () => {
  const i = CAPTAIN_MANUAL.indexOf("blank_gap_days_before_phase");
  const sec = CAPTAIN_MANUAL.slice(i, i + 400);
  assertStringIncludes(sec, "not \"missed workouts\"");
});

Deno.test("it does not restart the user at Phase 1", () => {
  assertStringIncludes(CAPTAIN_MANUAL, "do not call it a restart from Phase 1");
  assert(CAPTAIN_MANUAL.includes("Quote only numbers present in"));
});
