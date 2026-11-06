// Deno unit tests for ceremony_text.ts formatter.
// Run: deno test supabase/functions/_shared/ceremony_text_test.ts

import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { formatPromotionCeremony, rankAddressFor, rankDisplayFor } from "./ceremony_text.ts";

Deno.test("rankAddressFor — known codes", () => {
  assertEquals(rankAddressFor("SD2"), "Recruit");
  assertEquals(rankAddressFor("SD1"), "Sailor");
  assertEquals(rankAddressFor("LS"), "Sailor");
  assertEquals(rankAddressFor("PO"), "Petty Officer");
  assertEquals(rankAddressFor("CPO"), "Chief");
  assertEquals(rankAddressFor("MCPO"), "Master Chief");
  assertEquals(rankAddressFor("SubLt"), "Lieutenant");
  assertEquals(rankAddressFor("LtCdr"), "Lieutenant Commander");
  assertEquals(rankAddressFor("Cdr"), "Commander");
  assertEquals(rankAddressFor("Capt"), "Captain");
});

Deno.test("rankAddressFor — unknown code falls back to Sailor", () => {
  assertEquals(rankAddressFor("UNKNOWN"), "Sailor");
});

Deno.test("rankDisplayFor — known codes", () => {
  assertEquals(rankDisplayFor("SD2"), "Seaman 2nd Class");
  assertEquals(rankDisplayFor("SD1"), "Seaman 1st Class");
  assertEquals(rankDisplayFor("SubLt"), "Sub Lieutenant");
  assertEquals(rankDisplayFor("Capt"), "Captain");
});

Deno.test("formatPromotionCeremony — SD2 → SD1 standard", () => {
  const out = formatPromotionCeremony({
    oldRankAddress: "Recruit",
    oldRankCode: "SD2",
    newRankCode: "SD1",
    newRankDisplay: "Seaman 1st Class",
    newRankAddress: "Sailor",
    totalWorkouts: 7,
    weeksHeld: 1,
  });
  assertEquals(
    out,
    "Recruit, you've completed 7 sessions and held the line 1 weeks. " +
    "Promotion: Seaman 1st Class. Address change: Sailor. Carry on.",
  );
});

Deno.test("formatPromotionCeremony — SD1 → LS standard", () => {
  const out = formatPromotionCeremony({
    oldRankAddress: "Sailor",
    oldRankCode: "SD1",
    newRankCode: "LS",
    newRankDisplay: "Leading Seaman",
    newRankAddress: "Sailor",
    totalWorkouts: 18,
    weeksHeld: 4,
  });
  assertEquals(
    out,
    "Sailor, you've completed 18 sessions and held the line 4 weeks. " +
    "Promotion: Leading Seaman. Address change: Sailor. Carry on.",
  );
});

Deno.test("formatPromotionCeremony — officer-track crossing PO → SubLt", () => {
  const out = formatPromotionCeremony({
    oldRankAddress: "Petty Officer",
    oldRankCode: "PO",
    newRankCode: "SubLt",
    newRankDisplay: "Sub Lieutenant",
    newRankAddress: "Lieutenant",
    totalWorkouts: 100,
    weeksHeld: 14,
  });
  assertEquals(
    out,
    "Petty Officer, 14 weeks on the line, 100 sessions logged straight. " +
    "You've crossed onto the officer track. " +
    "Promotion: Sub Lieutenant. Carry on.",
  );
});

Deno.test("formatPromotionCeremony — officer-track crossing SD2 → SubLt (edge)", () => {
  const out = formatPromotionCeremony({
    oldRankAddress: "Recruit",
    oldRankCode: "SD2",
    newRankCode: "SubLt",
    newRankDisplay: "Sub Lieutenant",
    newRankAddress: "Lieutenant",
    totalWorkouts: 100,
    weeksHeld: 2,
  });
  assertEquals(
    out,
    "Recruit, 2 weeks on the line, 100 sessions logged straight. " +
    "You've crossed onto the officer track. " +
    "Promotion: Sub Lieutenant. Carry on.",
  );
});

Deno.test("formatPromotionCeremony — LtCdr contract milestone", () => {
  const out = formatPromotionCeremony({
    oldRankAddress: "Lieutenant",
    oldRankCode: "SubLt",
    newRankCode: "LtCdr",
    newRankDisplay: "Lieutenant Commander",
    newRankAddress: "Lieutenant Commander",
    totalWorkouts: 200,
    weeksHeld: 104,
  });
  assertEquals(
    out,
    "Lieutenant, 104 weeks on the line, 200 sessions logged honest. " +
    "The contract is met. " +
    "Promotion: Lieutenant Commander. " +
    "Address change: Lieutenant Commander. Carry on.",
  );
});

Deno.test("formatPromotionCeremony — Cdr standard", () => {
  const out = formatPromotionCeremony({
    oldRankAddress: "Lieutenant Commander",
    oldRankCode: "LtCdr",
    newRankCode: "Cdr",
    newRankDisplay: "Commander",
    newRankAddress: "Commander",
    totalWorkouts: 300,
    weeksHeld: 156,
  });
  assertEquals(
    out,
    "Lieutenant Commander, you've completed 300 sessions and held the line 156 weeks. " +
    "Promotion: Commander. Address change: Commander. Carry on.",
  );
});
