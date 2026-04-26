import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';

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

  test('LS needs streak 16 + 4 weeks', () {
    expect(_qualifies('LS', streak: 15, totalWorkouts: 15, weeks: 4,
                     deploymentsComplete: 0, longestGapDays: 0), isFalse);
    expect(_qualifies('LS', streak: 16, totalWorkouts: 16, weeks: 3,
                     deploymentsComplete: 0, longestGapDays: 0), isFalse);
    expect(_qualifies('LS', streak: 16, totalWorkouts: 16, weeks: 4,
                     deploymentsComplete: 0, longestGapDays: 0), isTrue);
  });

  test('PO needs streak 60 + 12 weeks + deployment 1', () {
    expect(_qualifies('PO', streak: 60, totalWorkouts: 60, weeks: 12,
                     deploymentsComplete: 0, longestGapDays: 0), isFalse);
    expect(_qualifies('PO', streak: 60, totalWorkouts: 60, weeks: 12,
                     deploymentsComplete: 1, longestGapDays: 0), isTrue);
  });

  test('SubLt needs 100 total workouts AND 104 weeks', () {
    expect(_qualifies('SubLt', streak: 0, totalWorkouts: 99, weeks: 104,
                     deploymentsComplete: 0, longestGapDays: 0), isFalse);
    expect(_qualifies('SubLt', streak: 0, totalWorkouts: 100, weeks: 103,
                     deploymentsComplete: 0, longestGapDays: 0), isFalse);
    expect(_qualifies('SubLt', streak: 0, totalWorkouts: 100, weeks: 104,
                     deploymentsComplete: 0, longestGapDays: 0), isTrue);
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
