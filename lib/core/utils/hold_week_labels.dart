// Pure display formatters for the hold-week identity (FOB-1 / OI-60).
//
// WHY THESE EXIST AS FUNCTIONS. They started as ternaries inlined in five
// widgets, whose only coverage was a source-grep for the token ("does this file
// still mention `stats.isHolding`?"). The B-pass on this batch defeated that
// coverage in one edit: it INVERTED the ternary in profile_content.dart — a
// real defect that shows "Holding · Hnull" to every non-holding user and
// "Week 4" to every holder — and all 16 tests still passed. A grep cannot see a
// logic inversion. Extracted here so the label LOGIC has behavioral assertions
// (test/contracts/hold_week_labels_test.dart, table-driven over both arms of
// every one of them).
//
// THE RULE THEY ALL ENCODE: a hold week sits outside the phase's four weeks, so
// there is no honest week counter for it — `getCurrentWeekNumber()` clamps to
// [1,4] and a hold starts at plan_start+28, so every surface printed week 4 to a
// holder at every ordinal, forever. A hold SUPPRESSES the week number; Hn is the
// identity.
//
// `holdOrdinal` is the SINGLE discriminator in every function here — never a
// separate `isHolding` bool. Two inputs that can disagree ("holding, ordinal
// null") is a state these functions should not be able to represent.
//
// None of these projects `4 + ordinal`. That manufactures the value the UI ruled
// dishonest and demotes a phase-2 holder from program week 8 to 5 (c9f4a2).

/// Home's DAILY eyebrow segment — `WK 4` / `HOLDING · H1`.
///
/// Home carries no HOLDING pill, so unlike the Train header (which DROPS the
/// segment because its pill states the identity ~40px away, c8b3f2 D1) this
/// SUBSTITUTES the hold identity into the segment.
String homeWeekSegment({required int? holdOrdinal, required int? weekInPhase}) =>
    holdOrdinal != null ? 'HOLDING · H$holdOrdinal' : 'WK $weekInPhase';

/// Profile header subtitle segment — `Week 4` / `Holding · H1`.
/// Sentence case here, not the eyebrow's all-caps, matching its surrounding
/// `Phase 1 · … · Build muscle` string.
String profileWeekSegment(
        {required int? holdOrdinal, required int weekInPhase}) =>
    holdOrdinal != null ? 'Holding · H$holdOrdinal' : 'Week $weekInPhase';

/// Journey-timeline header label — `WEEK 4 OF 4` / `HOLDING · H1`.
String journeyWeekLabel(
        {required int? holdOrdinal, required int weekInPhase}) =>
    holdOrdinal != null
        ? 'HOLDING · H$holdOrdinal'
        : 'WEEK $weekInPhase OF 4';

/// Journey-timeline Phase-1 milestone line.
///
/// Renders only when `current_phase == 1`, which is exactly the free-tier
/// holder — so the pre-fix countdown resolved to a flat "0 weeks to complete
/// Phase 1" on the surface a holder sees most. State where they actually are.
String journeyPhaseOneMilestone(
        {required int? holdOrdinal, required int weekInPhase}) =>
    holdOrdinal != null
        ? 'Phase 1 complete · holding at H$holdOrdinal'
        : '${(4 - weekInPhase).clamp(0, 4)} weeks to complete Phase 1';

/// Roadmap deployment header — `WK 4 / 12  —  33% complete` /
/// `HOLDING · H1  —  33% complete`.
///
/// Only the COUNTER is suppressed. [completePct] stays derived from the program
/// week and is passed through unchanged in both arms: four of twelve program
/// weeks genuinely ARE done during a phase-1 hold, so the percentage is honest
/// and branching it would make it wrong.
String roadmapWeekLabel({
  required int? holdOrdinal,
  required int programWeek,
  required int completePct,
}) =>
    holdOrdinal != null
        ? 'HOLDING · H$holdOrdinal  —  $completePct% complete'
        : 'WK $programWeek / 12  —  $completePct% complete';
