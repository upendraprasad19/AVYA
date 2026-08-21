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

// ── ROW-DERIVED LABELS (Hermes 2026-08-20 P1-A) ─────────────────────────────
//
// The five formatters above take `holdOrdinal` from `weekIdentityProvider`, and
// that framing hid a whole class of surface. `holdWeek()` ALSO stamps the row
// itself (`workout_schedule_write_service.dart:285-289`):
//
//     copy['week']         = 4 + n;      // <- the dishonest number, persisted
//     copy['is_hold']      = true;
//     copy['hold_ordinal'] = n;
//
// Two surfaces render `row['week']` straight out — the Home today-card
// (`home_screen.dart`) and the day-detail sheet (`day_detail_sheet.dart`) — so
// at flip-on a holder would read "Week 5" roughly 40px under the eyebrow that
// this same batch fixed to say "HOLDING · H1". The FOB-1 sweep missed them
// because it enumerated callers of getCurrentWeekNumber()/getProgramWeek();
// these read the STAMPED FIELD and never call either.
//
// They take the ROW, not a week int, deliberately: a caller cannot reach
// `4 + ordinal` through these because the raw `week` value is never a parameter.
// That is the same "no projected number by construction" property WeekIdentity
// has, applied one layer down. Row-derived rather than provider-derived so a
// bottom sheet needs no provider dependency, and so a restored row labels
// itself correctly offline.

/// The hold ordinal stamped on a schedule row, or null when it is not a hold.
int? rowHoldOrdinal(Map<dynamic, dynamic>? scheduleRow) {
  final raw = scheduleRow?['hold_ordinal'];
  return raw is int && raw > 0 ? raw : null;
}

/// Whether a schedule row is a hold-week row.
///
/// Accepts `is_hold` as a fallback discriminator ONLY so that a row with a
/// corrupt/missing ordinal still SUPPRESSES the week number rather than
/// printing `4 + n`. The ordinal remains the discriminator for what is shown;
/// this is purely the fail-safe direction.
bool rowIsHold(Map<dynamic, dynamic>? scheduleRow) =>
    scheduleRow?['is_hold'] == true || rowHoldOrdinal(scheduleRow) != null;

/// Home today-card mode line — `Week 4` / `Holding · H1`.
/// Sentence case, matching the card's existing `Week $week` string.
String todayCardWeekLabel(Map<dynamic, dynamic>? scheduleRow) {
  if (rowIsHold(scheduleRow)) {
    final ordinal = rowHoldOrdinal(scheduleRow);
    return ordinal != null ? 'Holding · H$ordinal' : 'Holding';
  }
  final week = scheduleRow?['week'] as int? ?? 1;
  return 'Week $week';
}

/// Day-detail sheet header line — `WEEK 4` / `HOLDING · H1`.
///
/// Returns null when there is nothing honest to show, preserving the caller's
/// existing `if (week > 0)` suppression for rows that carry no week at all.
String? dayDetailWeekLabel(Map<dynamic, dynamic>? scheduleRow) {
  if (rowIsHold(scheduleRow)) {
    final ordinal = rowHoldOrdinal(scheduleRow);
    return ordinal != null ? 'HOLDING · H$ordinal' : 'HOLDING';
  }
  final week = scheduleRow?['week'] as int? ?? 0;
  return week > 0 ? 'WEEK $week' : null;
}
