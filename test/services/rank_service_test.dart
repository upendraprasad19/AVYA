import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';
import 'package:icanbefitter/core/services/rank_service.dart';

/// Unit-level coverage of the eligibility table.
///
/// We test the *static* qualification function — the Hive-/Supabase-
/// reading paths are exercised by `rank_service_idempotent_test.dart`
/// as a regex contract (since they need a live Hive box to run).
void main() {
  test('SD2 always qualifies', () {
    expect(_qualifies('SD2', streak: 0, totalWorkouts: 0, weeks: 0,
                     deploymentsComplete: 0, longestGapDays: 0), isTrue);
  });

  test('SD1 needs streak 7 + 1 week', () {
    expect(_qualifies('SD1', streak: 6, totalWorkouts: 6, weeks: 1,
                     deploymentsComplete: 0, longestGapDays: 0), isFalse);
    expect(_qualifies('SD1', streak: 7, totalWorkouts: 7, weeks: 0,
                     deploymentsComplete: 0, longestGapDays: 0), isFalse);
    expect(_qualifies('SD1', streak: 7, totalWorkouts: 7, weeks: 1,
                     deploymentsComplete: 0, longestGapDays: 0), isTrue);
  });

  // LS: streakAtLeast=14, minWeeksSinceSignup=4 (kRankGates['LS']).
  // Previous test mistakenly used streak=16 (old gate value before Test #6
  // hybrid-model rebalance). The actual threshold is 14.
  test('LS needs streak 14 + 4 weeks (kRankGates LS: streakAtLeast=14, minWeeks=4)', () {
    // streak one short — fails
    expect(_qualifies('LS', streak: 13, totalWorkouts: 13, weeks: 4,
                     deploymentsComplete: 0, longestGapDays: 0), isFalse);
    // weeks one short — fails
    expect(_qualifies('LS', streak: 14, totalWorkouts: 14, weeks: 3,
                     deploymentsComplete: 0, longestGapDays: 0), isFalse);
    // exactly at threshold — passes
    expect(_qualifies('LS', streak: 14, totalWorkouts: 14, weeks: 4,
                     deploymentsComplete: 0, longestGapDays: 0), isTrue);
  });

  // PO: streakAtLeast=30, minWeeksSinceSignup=12, deploymentsCompleteAtLeast=2
  // (kRankGates['PO']). Previous test used deploymentsCompleteAtLeast=1
  // which is wrong — the actual gate requires 2 completed deployments.
  test('PO needs streak 30 + 12 weeks + 2 deployments (kRankGates PO: deploymentsCompleteAtLeast=2)', () {
    // missing one deployment — fails
    expect(_qualifies('PO', streak: 30, totalWorkouts: 30, weeks: 12,
                     deploymentsComplete: 1, longestGapDays: 0), isFalse);
    // all gates met — passes
    expect(_qualifies('PO', streak: 30, totalWorkouts: 30, weeks: 12,
                     deploymentsComplete: 2, longestGapDays: 0), isTrue);
  });

  // SubLt: minWeeksSinceSignup=104, completionRateMinimum=0.80 over 26 weeks.
  // No totalWorkoutsAtLeast gate (that field is null on SubLt).
  // The mirror _qualifies function does not evaluate completionRateMinimum
  // (no I/O available in a unit test), so it only enforces minWeeks=104.
  // Use RankService.instance.testQualify (the @visibleForTesting entry point)
  // with completionRateOverride to exercise the completion-rate half.
  test('SubLt needs 104 weeks + 80% completion rate (kRankGates SubLt: minWeeks=104, completionRate=0.80)', () {
    // Below minWeeks — fails even with good completion
    expect(RankService.instance.testQualify(
      code: 'SubLt',
      weeksSinceSignup: 103,
      completionRateOverride: 0.90,
    ), isFalse);
    // Meets weeks but completion rate too low — fails
    expect(RankService.instance.testQualify(
      code: 'SubLt',
      weeksSinceSignup: 104,
      completionRateOverride: 0.79,
    ), isFalse);
    // Both gates met — passes
    expect(RankService.instance.testQualify(
      code: 'SubLt',
      weeksSinceSignup: 104,
      completionRateOverride: 0.80,
    ), isTrue);
  });

  test('Capt is terminal — last lookup', () {
    expect(rankByCode('Capt')!.isTerminal, isTrue);
    final next = kRankLadder
        .where((r) => r.ordinal > rankByCode('Capt')!.ordinal)
        .toList();
    expect(next, isEmpty);
  });
}

/// Mirrors `RankService._qualifies` minus IO. Same semantics; if the
/// service-side helper is renamed/rewritten, update this mirror.
bool _qualifies(String code, {
  required int streak,
  required int totalWorkouts,
  required int weeks,
  required int deploymentsComplete,
  required int longestGapDays,
}) {
  final entry = rankByCode(code);
  if (entry == null) return false;
  if (weeks < entry.minWeeks) return false;
  final gate = kRankGates[code]!;
  if (gate.streakAtLeast != null && streak < gate.streakAtLeast!) {
    return false;
  }
  if (gate.totalWorkoutsAtLeast != null &&
      totalWorkouts < gate.totalWorkoutsAtLeast!) {
    return false;
  }
  if (gate.minWeeksSinceSignup != null &&
      weeks < gate.minWeeksSinceSignup!) {
    return false;
  }
  if (gate.deploymentsCompleteAtLeast != null &&
      deploymentsComplete < gate.deploymentsCompleteAtLeast!) {
    return false;
  }
  if (gate.maxGapDays != null && longestGapDays > gate.maxGapDays!) {
    return false;
  }
  return true;
}
