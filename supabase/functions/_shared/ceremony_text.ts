// Promotion ceremony text formatter — single source for the Captain's
// voice on rank advances. Used by evaluate-rank-promotions Edge Function.
//
// Source: Captain Manual §4 + APK Test #4 Plan C / C2.
//
// NOTE: rank codes match rank_engine.ts (SD2, SD1, LS, PO, CPO, MCPO,
// SubLt, LtCdr, Cdr, Capt). Update both files in lockstep.

export interface CeremonyInput {
  oldRankAddress: string; // e.g., "Recruit", "Sailor", "Petty Officer"
  oldRankCode: string;    // e.g., "SD2", "PO"
  newRankCode: string;    // e.g., "SD1", "SubLt"
  newRankDisplay: string; // e.g., "Seaman 1st Class", "Sub Lieutenant"
  newRankAddress: string; // e.g., "Sailor", "Lieutenant"
  totalWorkouts: number;
  weeksHeld: number;
}

const RANK_ADDRESS: Record<string, string> = {
  SD2:   "Recruit",
  SD1:   "Sailor",
  LS:    "Sailor",
  PO:    "Petty Officer",
  CPO:   "Chief",
  MCPO:  "Master Chief",
  SubLt: "Lieutenant",
  LtCdr: "Lieutenant Commander",
  Cdr:   "Commander",
  Capt:  "Captain",
};

const RANK_DISPLAY: Record<string, string> = {
  SD2:   "Seaman 2nd Class",
  SD1:   "Seaman 1st Class",
  LS:    "Leading Seaman",
  PO:    "Petty Officer",
  CPO:   "Chief Petty Officer",
  MCPO:  "Master Chief Petty Officer",
  SubLt: "Sub Lieutenant",
  LtCdr: "Lieutenant Commander",
  Cdr:   "Commander",
  Capt:  "Captain",
};

export function rankAddressFor(code: string): string {
  return RANK_ADDRESS[code] ?? "Sailor";
}

export function rankDisplayFor(code: string): string {
  return RANK_DISPLAY[code] ?? code;
}

export function formatPromotionCeremony(input: CeremonyInput): string {
  const {
    oldRankAddress,
    oldRankCode,
    newRankCode,
    newRankDisplay,
    newRankAddress,
    totalWorkouts,
    weeksHeld,
  } = input;

  // Officer-track entry: Sub Lieutenant promotion from any enlisted rank
  // (PO, CPO, MCPO — 100 total workouts threshold).
  const officerCrossing =
    newRankCode === "SubLt" &&
    (oldRankCode === "PO" ||
      oldRankCode === "CPO" ||
      oldRankCode === "MCPO" ||
      oldRankCode === "SD1" ||
      oldRankCode === "LS" ||
      oldRankCode === "SD2");

  if (officerCrossing) {
    return (
      `${oldRankAddress}, ${totalWorkouts} workouts on the books. ` +
      `You've crossed onto the officer track. ` +
      `Promotion: ${newRankDisplay}. Carry on.`
    );
  }

  // Lt Cdr = 200 workouts — the Contract milestone.
  if (newRankCode === "LtCdr") {
    return (
      `${oldRankAddress}, ${totalWorkouts} workouts. ` +
      `The contract is met. 200 sessions — done straight, logged honest. ` +
      `Promotion: ${newRankDisplay}. Address change: ${newRankAddress}. Carry on.`
    );
  }

  // Standard format for all other promotions.
  return (
    `${oldRankAddress}, you've completed ${totalWorkouts} sessions and ` +
    `held the line ${weeksHeld} weeks. ` +
    `Promotion: ${newRankDisplay}. ` +
    `Address change: ${newRankAddress}. Carry on.`
  );
}
