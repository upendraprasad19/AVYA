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

/// 11-rung ladder, ordinal 0..10. Captain is terminal.
///
/// Lt (ordinal 7, W130) inserted between SubLt and LtCdr per spec §10.1.
/// Insignia (`2 thick stripes`) painted by `WardRankInsignia` per Plan D.
const List<RankLadderEntry> kRankLadder = [
  RankLadderEntry(
    code: 'SD2',
    displayName: 'Seaman 2nd Class',
    shortName: 'SEAMAN 2',
    ordinal: 0,
    minWeeks: 0,
    insigniaAsset: 'rank/sd2.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'SD1',
    displayName: 'Seaman 1st Class',
    shortName: 'SEAMAN 1',
    ordinal: 1,
    minWeeks: 1,
    insigniaAsset: 'rank/sd1.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'LS',
    displayName: 'Leading Seaman',
    shortName: 'LEADING SEAMAN',
    ordinal: 2,
    minWeeks: 4,
    insigniaAsset: 'rank/ls.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'PO',
    displayName: 'Petty Officer',
    shortName: 'PETTY OFFICER',
    ordinal: 3,
    minWeeks: 12,
    insigniaAsset: 'rank/po.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'CPO',
    displayName: 'Chief Petty Officer',
    shortName: 'CHIEF PO',
    ordinal: 4,
    minWeeks: 26,
    insigniaAsset: 'rank/cpo.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'MCPO',
    displayName: 'Master Chief Petty Officer',
    shortName: 'MASTER CHIEF',
    ordinal: 5,
    minWeeks: 52,
    insigniaAsset: 'rank/mcpo.svg',
    category: 'sailor',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'SubLt',
    displayName: 'Sub Lieutenant',
    shortName: 'SUB LT',
    ordinal: 6,
    minWeeks: 104,
    insigniaAsset: 'rank/sublt.svg',
    category: 'officer',
    isTerminal: false,
  ),
  // NEW: Lt inserted at ordinal 7 (W130). Two thick stripes.
  RankLadderEntry(
    code: 'Lt',
    displayName: 'Lieutenant',
    shortName: 'LIEUTENANT',
    ordinal: 7,
    minWeeks: 130,
    insigniaAsset: 'rank/lt.svg',
    category: 'officer',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'LtCdr',
    displayName: 'Lieutenant Commander',
    shortName: 'LT CDR',
    ordinal: 8,
    minWeeks: 156,
    insigniaAsset: 'rank/ltcdr.svg',
    category: 'officer',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'Cdr',
    displayName: 'Commander',
    shortName: 'CDR',
    ordinal: 9,
    minWeeks: 208,
    insigniaAsset: 'rank/cdr.svg',
    category: 'officer',
    isTerminal: false,
  ),
  RankLadderEntry(
    code: 'Capt',
    displayName: 'Captain',
    shortName: 'CAPTAIN',
    ordinal: 10,
    minWeeks: 260,
    insigniaAsset: 'rank/capt.svg',
    category: 'officer',
    isTerminal: true,
  ),
];

/// Spec gates table, code-keyed. Each rank requires the
/// `RankLadderEntry.minWeeks` gate AND its `RankGate` payload.
///
/// Sailor track (SD1..CPO) — streak primary; relaxed for realism per
/// spec §10.2.
/// MCPO — transition rank: completion rate primary + 14-day max gap.
/// Officer track (SubLt..Capt) — completion-rate primary, no streak.
const Map<String, RankGate> kRankGates = {
  'SD2': RankGate(),
  // SD1: STRICT 7-day streak (Q27=α). 1 week elapsed clock starts ticking
  // from onboarding date (phase_started_at, IST).
  'SD1': RankGate(streakAtLeast: 7, minWeeksSinceSignup: 1),

  // Sailor track — streak primary, re-balanced for realism
  'LS': RankGate(streakAtLeast: 14, minWeeksSinceSignup: 4),
  'PO': RankGate(
    streakAtLeast: 30,
    minWeeksSinceSignup: 12,
    deploymentsCompleteAtLeast: 2,
  ),
  'CPO': RankGate(
    streakAtLeast: 50,
    minWeeksSinceSignup: 26,
    deploymentsCompleteAtLeast: 3,
  ),

  // MCPO transition rank — completion-rate primary (smooths sailor → officer)
  'MCPO': RankGate(
    minWeeksSinceSignup: 52,
    completionRateMinimum: 0.80,
    completionRateWindowWeeks: 12,
    maxGapDays: 14,
  ),

  // Officer track — completion-rate primary, no streak requirement
  'SubLt': RankGate(
    minWeeksSinceSignup: 104,
    completionRateMinimum: 0.80,
    completionRateWindowWeeks: 26,
  ),
  'Lt': RankGate(
    minWeeksSinceSignup: 130,
    completionRateMinimum: 0.80,
    completionRateWindowWeeks: 26,
  ),
  'LtCdr': RankGate(
    minWeeksSinceSignup: 156,
    completionRateMinimum: 0.80,
    completionRateWindowWeeks: 52,
  ),
  'Cdr': RankGate(
    minWeeksSinceSignup: 208,
    completionRateMinimum: 0.80,
    completionRateWindowWeeks: 52,
  ),
  'Capt': RankGate(
    minWeeksSinceSignup: 260,
    completionRateMinimum: 0.85,
    completionRateWindowWeeks: 104,
  ),
};

/// Lookup by code. Returns null for unknown codes.
RankLadderEntry? rankByCode(String code) {
  for (final r in kRankLadder) {
    if (r.code == code) return r;
  }
  return null;
}
