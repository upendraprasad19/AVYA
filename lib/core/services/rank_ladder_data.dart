/// Static mirror of the `rank_ladder` Postgres table seeded by
/// migration 039. Order MUST match `ordinal` ascending.
///
/// When migration 039 ladder rows change, update this file and the
/// `_shared/rank_engine.ts` mirror in lockstep. The list is immutable.
library;

class RankLadderEntry {
  final String code;
  final String displayName;
  final String shortName;
  final int ordinal;
  final int minWeeks;
  final String insigniaAsset;
  final String category; // 'sailor' | 'officer'
  final bool isTerminal;

  const RankLadderEntry({
    required this.code,
    required this.displayName,
    required this.shortName,
    required this.ordinal,
    required this.minWeeks,
    required this.insigniaAsset,
    required this.category,
    required this.isTerminal,
  });
}

/// Streak + total-workout + completion-rate gates per rank.
///
/// Sailor track (SD1..CPO) — streak primary (`streakAtLeast`).
/// Officer track (SubLt..Capt) — completion-rate primary
/// (`completionRateMinimum` over `completionRateWindowWeeks`).
/// MCPO is a transition rank using completion rate alongside `maxGapDays`.
///
/// `streak` is the current workout-day streak from
/// `WorkoutRepository.calculateCurrentStreak()` — schedule-aware,
/// rest days invisible, resets on missed scheduled workouts only.
///
/// `completionRate` is computed by
/// `WorkoutRepository.completionRateOverWindow(windowWeeks)`:
/// fraction of scheduled workout days completed in the rolling window.
/// Rest days + pre-onboarding days excluded from the denominator.
///
/// `totalWorkouts` reads from `progress['total_workouts_done']`.
///
/// `minWeeksSinceSignup` is calendar weeks since signup
/// (auth.users.created_at; mirrored locally as `phase_started_at` IST)
/// truncated. Always required alongside any other gates.
class RankGate {
  final int? streakAtLeast;
  final int? totalWorkoutsAtLeast;
  final int? deploymentsCompleteAtLeast;
  final int? minWeeksSinceSignup;
  final int? maxGapDays; // for MCPO 1-year-active-streak gate
  final double? completionRateMinimum; // 0.0-1.0 inclusive
  final int? completionRateWindowWeeks; // lookback window in weeks

  const RankGate({
    this.streakAtLeast,
    this.totalWorkoutsAtLeast,
    this.deploymentsCompleteAtLeast,
    this.minWeeksSinceSignup,
    this.maxGapDays,
    this.completionRateMinimum,
    this.completionRateWindowWeeks,
  });
}

/// 10-rung ladder, ordinal 0..9. Captain is terminal.
const List<RankLadderEntry> kRankLadder = [
  RankLadderEntry(
    code: 'SD2',
    displayName: 'Seaman 2nd Class',
    shortName: 'Seaman 2nd',
    ordinal: 0,
    minWeeks: 0,
    insigniaAsset: 'rank/sd2.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'SD1',
    displayName: 'Seaman 1st Class',
    shortName: 'Seaman 1st',
    ordinal: 1,
    minWeeks: 1,
    insigniaAsset: 'rank/sd1.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'LS',
    displayName: 'Leading Seaman',
    shortName: 'Leading',
    ordinal: 2,
    minWeeks: 4,
    insigniaAsset: 'rank/ls.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'PO',
    displayName: 'Petty Officer',
    shortName: 'Petty Off.',
    ordinal: 3,
    minWeeks: 12,
    insigniaAsset: 'rank/po.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'CPO',
    displayName: 'Chief Petty Officer',
    shortName: 'Chief PO',
    ordinal: 4,
    minWeeks: 26,
    insigniaAsset: 'rank/cpo.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'MCPO',
    displayName: 'Master Chief Petty Officer',
    shortName: 'Master Ch.',
    ordinal: 5,
    minWeeks: 52,
    insigniaAsset: 'rank/mcpo.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'SubLt',
    displayName: 'Sub Lieutenant',
    shortName: 'Sub Lt',
    ordinal: 6,
    minWeeks: 104,
    insigniaAsset: 'rank/sublt.svg',
    category: 'officer',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'LtCdr',
    displayName: 'Lieutenant Commander',
    shortName: 'Lt Cdr',
    ordinal: 7,
    minWeeks: 156,
    insigniaAsset: 'rank/ltcdr.svg',
    category: 'officer',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'Cdr',
    displayName: 'Commander',
    shortName: 'Cdr',
    ordinal: 8,
    minWeeks: 208,
    insigniaAsset: 'rank/cdr.svg',
    category: 'officer',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'Capt',
    displayName: 'Captain',
    shortName: 'Captain',
    ordinal: 9,
    minWeeks: 260,
    insigniaAsset: 'rank/capt.svg',
    category: 'officer',
    isTerminal: true,
  ),
];

/// Spec gates table, ordinal-keyed. Each rank requires BOTH the
/// `RankLadderEntry.minWeeks` gate AND its `RankGate` payload.
const Map<String, RankGate> kRankGates = {
  'SD2': RankGate(),
  'SD1': RankGate(streakAtLeast: 7, minWeeksSinceSignup: 1),
  'LS': RankGate(streakAtLeast: 16, minWeeksSinceSignup: 4),
  'PO': RankGate(streakAtLeast: 60, minWeeksSinceSignup: 12,
      deploymentsCompleteAtLeast: 1),
  'CPO': RankGate(streakAtLeast: 100, minWeeksSinceSignup: 26,
      deploymentsCompleteAtLeast: 2),
  'MCPO': RankGate(minWeeksSinceSignup: 52, maxGapDays: 14),
  'SubLt': RankGate(totalWorkoutsAtLeast: 100, minWeeksSinceSignup: 104),
  'LtCdr': RankGate(totalWorkoutsAtLeast: 200, minWeeksSinceSignup: 156),
  'Cdr': RankGate(totalWorkoutsAtLeast: 300, minWeeksSinceSignup: 208),
  'Capt': RankGate(
    totalWorkoutsAtLeast: 500,
    minWeeksSinceSignup: 260,
    deploymentsCompleteAtLeast: 3,
  ),
};

/// Lookup by code. Returns null for unknown codes.
RankLadderEntry? rankByCode(String code) {
  for (final r in kRankLadder) {
    if (r.code == code) return r;
  }
  return null;
}
