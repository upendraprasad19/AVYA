// Piece B (lapse gap policy) — the PURE start-date rule and blank-gap count.
// Plan: docs/plans/2026-10-18-pro-gap-policy-and-streak.md
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/gap_policy.dart';

void main() {
  // Old phase 2026-09-07 (Mon) .. 2026-10-04 (Sun).
  final planEnd = DateTime(2026, 10, 4);

  DateTime start(DateTime today,
          {bool gapStart = true, bool policyEnabled = true}) =>
      phaseStartAfterGap(
          planEnd: planEnd,
          today: today,
          gapStart: gapStart,
          policyEnabled: policyEnabled);

  group('phaseStartAfterGap', () {
    test('returns the day after the old phase on the day it ends', () {
      expect(start(DateTime(2026, 10, 5, 9)), DateTime(2026, 10, 5));
    });

    test('a 3-week return keeps the gap start (days in between are missed)',
        () {
      expect(start(DateTime(2026, 10, 28, 9)), DateTime(2026, 10, 5));
    });

    test('last day of the next phase still counts as inside it (day 27)', () {
      // 2026-10-05 + 27 days = 2026-11-01 (Sun).
      expect(start(DateTime(2026, 11, 1, 23)), DateTime(2026, 10, 5));
    });

    test('the day after the next phase ended falls back to this Monday', () {
      // 2026-11-02 is a Monday: the whole next phase is in the past.
      expect(start(DateTime(2026, 11, 2, 9)), DateTime(2026, 11, 2));
      // Wed 2026-11-11 -> Monday 2026-11-09, not the gap start.
      expect(start(DateTime(2026, 11, 11, 9)), DateTime(2026, 11, 9));
    });

    test('a 6-month return starts this Monday', () {
      expect(start(DateTime(2027, 4, 7, 9)), DateTime(2027, 4, 5));
    });

    test('graduation (gapStart false) keeps the original max(today, end+1)',
        () {
      expect(start(DateTime(2026, 10, 28, 9), gapStart: false),
          DateTime(2026, 10, 26));
      // Not yet expired: the phase after the current one.
      expect(start(DateTime(2026, 10, 1, 9), gapStart: false),
          DateTime(2026, 10, 5));
    });

    test('policy OFF reproduces the original rule for every return day', () {
      expect(start(DateTime(2026, 10, 28, 9), policyEnabled: false),
          DateTime(2026, 10, 26));
      expect(start(DateTime(2026, 10, 1, 9), policyEnabled: false),
          DateTime(2026, 10, 5));
    });

    test('a non-Monday plan end is still Monday-snapped', () {
      final s = phaseStartAfterGap(
          planEnd: DateTime(2026, 10, 7), // Wed -> candidate Thu 8th
          today: DateTime(2026, 10, 9),
          policyEnabled: true);
      expect(s.weekday, DateTime.monday);
      expect(s, DateTime(2026, 10, 5));
    });
  });

  group('blankGapDays', () {
    test('back to back is 0', () {
      expect(
          blankGapDays(planEnd: planEnd, newStart: DateTime(2026, 10, 5)), 0);
    });
    test('starting earlier than the end is 0, never negative', () {
      expect(
          blankGapDays(planEnd: planEnd, newStart: DateTime(2026, 9, 28)), 0);
    });
    test('counts the rowless days in between', () {
      expect(
          blankGapDays(planEnd: planEnd, newStart: DateTime(2026, 11, 9)), 35);
    });
  });

  group('freezeResetGapDays', () {
    test('7 blank days is the smallest reset (3-day plan = cap 3)', () {
      expect(freezeResetGapDays(7, policyEnabled: true), 7);
      expect(freezeResetGapDays(6, policyEnabled: true), 0);
      expect(freezeResetGapDays(0, policyEnabled: true), 0);
    });
    test('policy off never resets', () {
      expect(freezeResetGapDays(42, policyEnabled: false), 0);
    });
  });

  test('a mid-week (non-Sunday) plan end snaps back to its own Monday', () {
    // plan_end Wed 2026-10-28 -> candidate Thu 29th -> Monday 26th; the new
    // phase overlaps the last 3 days of the old one (completed days are kept
    // by the upsert guard). Pre-existing snap, kept; pinned here.
    final s = phaseStartAfterGap(
        planEnd: DateTime(2026, 10, 28),
        today: DateTime(2026, 11, 3),
        policyEnabled: true);
    expect(s, DateTime(2026, 10, 26));
  });
}
