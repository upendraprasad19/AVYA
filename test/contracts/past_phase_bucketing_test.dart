import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';

/// F-B (2026-06-05): `pastPhaseBlocks` over-counted when a single phase's rows
/// spanned >28 calendar days (gaps/overlaps) — the 28-day window split it into
/// two blocks, so the reconciler could over-advance `current_phase`. Fix: group
/// by the explicit stamped `phase` via carry-forward when ANY row carries it (an
/// unstamped row inherits the nearest preceding stamped phase — B-pass F-2, so a
/// lone swapped/legacy row can't collapse the dataset); only when NO row is
/// stamped fall back to the 28-day bucketing (which correctly collapses the
/// founder's legacy duplicate-week residue into one block — a naive week-reset
/// inference would over-count it).

void main() {
  (DateTime, Map<String, dynamic>) row(String date,
      {int? phase, int week = 1}) {
    final m = <String, dynamic>{'date': date, 'week': week};
    if (phase != null) m['phase'] = phase;
    return (DateTime.parse(date), m);
  }

  group('bucketPastRows — phase-identity (all rows stamped)', () {
    test('one phase spanning >28 days (gaps) → ONE block', () {
      final rows = [
        row('2026-04-01', phase: 1),
        row('2026-04-15', phase: 1),
        row('2026-05-20', phase: 1), // 49 days span → 2 buckets at 28d
      ];
      final blocks = WorkoutScheduleReadService.bucketPastRows(rows);
      expect(blocks.length, 1,
          reason: 'phase identity collapses the calendar span');
      expect(blocks.first.startDate, DateTime.parse('2026-04-01'));
      expect(blocks.first.endDate, DateTime.parse('2026-05-20'));
    });

    test('two stamped phases → two blocks, oldest-first', () {
      final rows = [
        row('2026-04-01', phase: 1),
        row('2026-04-20', phase: 1),
        row('2026-04-28', phase: 2),
        row('2026-05-15', phase: 2),
      ];
      final blocks = WorkoutScheduleReadService.bucketPastRows(rows);
      expect(blocks.length, 2);
      expect(blocks[0].startDate, DateTime.parse('2026-04-01'));
      expect(blocks[1].startDate, DateTime.parse('2026-04-28'));
    });
  });

  group('bucketPastRows — 28-day fallback (legacy / unstamped)', () {
    test('legacy duplicate-week residue in one window → ONE block (founder)',
        () {
      // The founder's data: "Phase 1" Apr27–May18 with a duplicate week_number
      // mid-span; NO phase stamp. 28-day window keeps it as ONE block → correct
      // (reconciler advances to phase 2, not 3 — week-reset would over-count).
      final rows = [
        row('2026-04-27', week: 1),
        row('2026-05-04', week: 2),
        row('2026-05-11', week: 3),
        row('2026-05-18', week: 1), // duplicate reset, same 28-day window
      ];
      final blocks = WorkoutScheduleReadService.bucketPastRows(rows);
      expect(blocks.length, 1,
          reason: '28-day fallback collapses duplicate-week residue into one '
              'block — does NOT over-count via week-reset inference');
    });

    test('B-pass F-2: an unstamped row inherits the surrounding phase', () {
      // Two stamped phases >28 days apart + an UNSTAMPED row (e.g. a swapped
      // day) inside phase 2 — carry-forward keeps it TWO blocks; the old
      // all-or-nothing guard would have collapsed everything to 28-day.
      final rows = [
        row('2026-03-01', phase: 1),
        row('2026-03-20', phase: 1),
        row('2026-04-10', phase: 2),
        row('2026-04-18'), // unstamped swap row → inherits phase 2
        row('2026-04-25', phase: 2),
      ];
      final blocks = WorkoutScheduleReadService.bucketPastRows(rows);
      expect(blocks.length, 2,
          reason: 'one unstamped row must not collapse to 28-day');
      expect(blocks[1].endDate, DateTime.parse('2026-04-25'));
    });

    test('two legacy phases >28 days apart → two fallback blocks', () {
      final rows = [
        row('2026-03-01', week: 1),
        row('2026-03-20', week: 4),
        row('2026-04-10', week: 1), // 40 days after first → new 28-day bucket
        row('2026-04-25', week: 4),
      ];
      expect(WorkoutScheduleReadService.bucketPastRows(rows).length, 2);
    });

    test('empty → no blocks', () {
      expect(WorkoutScheduleReadService.bucketPastRows(const []), isEmpty);
    });
  });
}
