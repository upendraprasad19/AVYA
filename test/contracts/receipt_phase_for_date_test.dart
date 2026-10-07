import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';

/// Obs 1 (2026-06-05): the workout receipt / share card rendered a hardcoded
/// "PHASE 1" because `WorkoutReceiptData.phase` defaulted to 1 and no caller
/// passed it. `fromExerciseLogs` now resolves the phase via
/// `WorkoutScheduleReadService.phaseForDate(date)` — current_phase for in-window
/// dates, else the 1-based past-phase-block index for historical dates. The
/// title widget renders `'PHASE ${data.phase}'`, so a correct `phase` field is
/// the load-bearing assertion (proven by the pure cases below).

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('phaseForDatePure (Obs 1 — receipt phase resolution)', () {
    final planStart = DateTime(2026, 5, 25); // current-phase window start
    // Two completed past blocks, oldest-first: block0=phase1, block1=phase2.
    final blocks = [DateTime(2026, 3, 30), DateTime(2026, 4, 27)];

    test('in-window date → current_phase', () {
      expect(
        WorkoutScheduleReadService.phaseForDatePure(
            3, planStart, DateTime(2026, 5, 30), blocks),
        3,
      );
    });

    test('date == planStart (boundary) → current_phase', () {
      expect(
        WorkoutScheduleReadService.phaseForDatePure(
            3, planStart, planStart, blocks),
        3,
      );
    });

    test('past date in first block → phase 1', () {
      expect(
        WorkoutScheduleReadService.phaseForDatePure(
            3, planStart, DateTime(2026, 4, 1), blocks),
        1,
      );
    });

    test('past date in second block → phase 2', () {
      expect(
        WorkoutScheduleReadService.phaseForDatePure(
            3, planStart, DateTime(2026, 5, 1), blocks),
        2,
      );
    });

    test('past date before all blocks → phase 1', () {
      expect(
        WorkoutScheduleReadService.phaseForDatePure(
            3, planStart, DateTime(2026, 1, 1), blocks),
        1,
      );
    });

    test('no plan window (planStart null) → current_phase', () {
      expect(
        WorkoutScheduleReadService.phaseForDatePure(
            2, null, DateTime(2026, 4, 1), const []),
        2,
      );
    });
  });

  group('wiring — receipt resolves the real phase (not the hardcoded default)',
      () {
    final card = _strip(
        File('lib/features/train/widgets/workout_receipt_card.dart')
            .readAsStringSync());

    test('fromExerciseLogs derives phase via phaseForDate', () {
      expect(
        card.contains('phaseForDate('),
        isTrue,
        reason: 'fromExerciseLogs must resolve the receipt phase via '
            'WorkoutScheduleReadService.phaseForDate(date) — not the hardcoded '
            'default 1 (Obs 1 2026-06-05).',
      );
    });

    test('completion in-memory fallback passes phase to fromActiveWorkout', () {
      final completion = _strip(File(
              'lib/features/train/screens/active_workout/completion_sheet.dart')
          .readAsStringSync());
      expect(
        completion.contains('phaseForDate('),
        isTrue,
        reason: 'the no-logs fallback receipt must also carry the real phase, '
            'not default to PHASE 1.',
      );
    });
  });
}
