// test/contracts/rank_year_simulation_test.dart
//
// Headless year-simulation of the rank ladder (Phase B4, audit-2026-05-29).
//
// The founder's core concern: "from start through rank promotions and new
// phase generation for at least one year — make sure nothing is breaking."
// This test fast-forwards the rank-gate evaluation week-by-week across the
// FULL ladder horizon (0..260 weeks = 5 years, well past the 1-year ask)
// WITHOUT a device, Hive, or Supabase — using the pure seams
// RankService.testQualify (gate logic from explicit inputs) and
// RankService.shouldPromote (the monotonic no-demotion guard).
//
// It pins three properties:
//   A. TIME-GATED CLIMB — with all non-time gates satisfied, the qualified
//      rank steps up exactly at each rank's minWeeks boundary and is strictly
//      monotonic non-decreasing every week.
//   B. NO DEMOTION ON STREAK BREAK — the 3a7b9f regression in a year context:
//      after climbing, a broken streak lowers the *qualifying ceiling* but the
//      shouldPromote-guarded current rank never drops.
//   C. MONOTONIC GUARD UNDER A VOLATILE YEAR — across a full year of
//      streak ups and downs, the guarded current rank is non-decreasing on
//      every single simulated week.
//
// Phase generation (client-side, Hive + plan_generator) is NOT simulated here
// — it is covered by the existing phase tests (phase_unlock_*_test.dart) and
// the C2 web spot-check. This harness is the RANK year-sim.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';

/// Highest qualifying rank code at [week], mirroring the private
/// `_qualifiedRankCode`: the top-ordinal rank whose gate passes. Driven
/// entirely through the public test seam so no Hive/Supabase is touched.
String qualifiedRankAt(
  int week, {
  required int streak,
  required int totalWorkouts,
  required int deployments,
  required int longestGapDays,
  required double completionRate,
}) {
  var winner = 'SD2';
  for (final r in kRankLadder) {
    final ok = RankService.instance.testQualify(
      code: r.code,
      streak: streak,
      totalWorkouts: totalWorkouts,
      weeksSinceSignup: week,
      deploymentsComplete: deployments,
      longestGapDays: longestGapDays,
      completionRateOverride: completionRate,
    );
    if (ok) winner = r.code;
  }
  return winner;
}

int ordinalOf(String code) => rankByCode(code)!.ordinal;

void main() {
  group('B4 — rank year-simulation (pure, no device)', () {
    // A "maximal" trajectory: every non-time gate satisfied, so the only
    // binding constraint each week is the minWeeks/minWeeksSinceSignup gate.
    String maxQualifiedAt(int week) => qualifiedRankAt(
          week,
          streak: 9999,
          totalWorkouts: 9999,
          deployments: 9999,
          longestGapDays: 0,
          completionRate: 1.0,
        );

    test('A — qualified rank steps up exactly at each minWeeks boundary', () {
      // Expected (code, firstWeekEligible) per kRankGates.
      const milestones = <MapEntry<int, String>>[
        MapEntry(0, 'SD2'),
        MapEntry(1, 'SD1'),
        MapEntry(4, 'LS'),
        MapEntry(12, 'PO'),
        MapEntry(26, 'CPO'),
        MapEntry(52, 'MCPO'),
        MapEntry(104, 'SubLt'),
        MapEntry(130, 'Lt'),
        MapEntry(156, 'LtCdr'),
        MapEntry(208, 'Cdr'),
        MapEntry(260, 'Capt'),
      ];
      for (var i = 0; i < milestones.length; i++) {
        final boundary = milestones[i].key;
        final code = milestones[i].value;
        // At the boundary week, this rank qualifies.
        expect(maxQualifiedAt(boundary), code,
            reason: 'week $boundary should qualify $code');
        // The week BEFORE the boundary must be the PRIOR rank (strict step).
        if (i > 0) {
          expect(maxQualifiedAt(boundary - 1), milestones[i - 1].value,
              reason: 'week ${boundary - 1} should still be '
                  '${milestones[i - 1].value} (no early promotion)');
        }
      }
    });

    test('A2 — qualified ordinal is monotonic non-decreasing every week '
        '(0..260)', () {
      var prev = -1;
      for (var w = 0; w <= 260; w++) {
        final ord = ordinalOf(maxQualifiedAt(w));
        expect(ord, greaterThanOrEqualTo(prev),
            reason: 'qualified rank went DOWN at week $w');
        prev = ord;
      }
      // By the end of the horizon the user is Captain (terminal).
      expect(maxQualifiedAt(260), 'Capt');
    });

    test('B — broken streak lowers the ceiling but shouldPromote never demotes',
        () {
      // Climb to LS by week 4 (streak high), then snap the streak at week 10.
      const reachedAt = 4;
      final current = qualifiedRankAt(
        reachedAt,
        streak: 100,
        totalWorkouts: 100,
        deployments: 0,
        longestGapDays: 0,
        completionRate: 1.0,
      );
      expect(current, 'LS', reason: 'precondition: reached LS by week 4');

      // Week 10: streak broken to 0. The qualifying ceiling recomputes.
      final ceilingAfterBreak = qualifiedRankAt(
        10,
        streak: 0, // broke the streak
        totalWorkouts: 100,
        deployments: 0,
        longestGapDays: 0,
        completionRate: 1.0,
      );
      // SD1 (streak>=7) and LS (streak>=14) both fail now → ceiling drops.
      expect(ordinalOf(ceilingAfterBreak), lessThan(ordinalOf('LS')),
          reason: 'with streak 0 the qualifying CEILING must drop below LS');

      // But the permanent rank must NOT demote. shouldPromote(current=LS,
      // qualified=ceiling) must be false → current stays LS.
      final qualifiedEntry = rankByCode(ceilingAfterBreak)!;
      expect(RankService.shouldPromote('LS', qualifiedEntry), isFalse,
          reason: '3a7b9f: rank is permanent — a dropped ceiling must not '
              'demote the recorded rank.');
    });

    test('C — guarded current rank is monotonic across a volatile year', () {
      // A realistic-ish year: streak climbs, breaks at week 18, recovers,
      // breaks again at week 40. Deployments + completion stay strong so the
      // ONLY volatility is the sailor-track streak gate.
      String current = 'SD2';
      final trail = <String>[];
      for (var w = 0; w <= 52; w++) {
        // Streak model: grows ~7/week, snaps to 0 at weeks 18 and 40.
        int streak;
        if (w < 18) {
          streak = w * 7;
        } else if (w < 40) {
          streak = (w - 18) * 7; // recovering after the week-18 break
        } else {
          streak = (w - 40) * 7; // recovering after the week-40 break
        }
        final ceiling = qualifiedRankAt(
          w,
          streak: streak,
          totalWorkouts: w * 4,
          deployments: w ~/ 12,
          longestGapDays: 0,
          completionRate: 1.0,
        );
        // Apply the monotonic guard the way RankService does.
        if (RankService.shouldPromote(current, rankByCode(ceiling)!)) {
          current = ceiling;
        }
        trail.add('w$w=$current');
        // Invariant: current never decreases.
        if (w > 0) {
          final prevCode = trail[w - 1].split('=')[1];
          expect(ordinalOf(current), greaterThanOrEqualTo(ordinalOf(prevCode)),
              reason: 'guarded rank demoted at week $w: $prevCode -> $current');
        }
      }
      // Despite two streak breaks, the user retains the highest rank ever
      // reached (at least LS, achieved before the week-18 break).
      expect(ordinalOf(current), greaterThanOrEqualTo(ordinalOf('LS')));
    });

    test('milestone table (informational) — week -> qualified rank', () {
      // Emits the table C1 wants. Asserts the year-1 endpoint as a sanity gate.
      final buf = StringBuffer('\n  week | qualified rank\n');
      for (final w in [0, 1, 4, 12, 26, 52]) {
        buf.writeln('  ${w.toString().padLeft(4)} | ${maxQualifiedAt(w)}');
      }
      // ignore: avoid_print
      print(buf.toString());
      // A maximal trainer is MCPO by the end of year 1.
      expect(maxQualifiedAt(52), 'MCPO');
    });
  });
}
