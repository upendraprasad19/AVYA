// Contract test for OI-02 (closes-diagnose: 2026-05-17-oi-02-read-services).
//
// Pins the per-set MAX semantic on `WorkoutReadService` directly.
// Mirrors the assertions in
// `test/contracts/load_all_exercise_prs_per_set_semantic_test.dart`
// but invokes the canonical service (not the repository wrapper), so
// any reader that delegates here is automatically covered by the same
// guarantees.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/workout_read_service.dart';

void main() {
  group('WorkoutReadService.bestPerSetReps', () {
    test('returns MAX reps across sets[], not SUM', () {
      final log = <String, dynamic>{
        'sets': [
          {'reps': 30},
          {'reps': 25},
          {'reps': 20},
          {'reps': 15},
          {'reps': 10},
        ],
        'set_number': 5,
        'reps_completed': 100, // SUM — must NOT surface
      };
      expect(WorkoutReadService.bestPerSetReps(log), 30);
    });

    test('falls back to top-level reps_completed when sets[] missing AND set_number<=1', () {
      final log = <String, dynamic>{
        'set_number': 1,
        'reps_completed': 25,
      };
      expect(WorkoutReadService.bestPerSetReps(log), 25);
    });

    test('returns 0 when sets[] missing AND multi-set legacy row', () {
      final log = <String, dynamic>{
        'set_number': 5,
        'reps_completed': 100, // cumulative — unrecoverable
      };
      expect(WorkoutReadService.bestPerSetReps(log), 0);
    });

    test('returns 0 when sets[] is an empty list and no top-level', () {
      final log = <String, dynamic>{
        'sets': const [],
        'set_number': 0,
      };
      expect(WorkoutReadService.bestPerSetReps(log), 0);
    });

    test('handles non-Map entries inside sets[] gracefully', () {
      final log = <String, dynamic>{
        'sets': [
          {'reps': 10},
          null,
          'garbage',
          {'reps': 25},
        ],
      };
      expect(WorkoutReadService.bestPerSetReps(log), 25);
    });
  });

  group('WorkoutReadService.bestPerSetDuration', () {
    test('returns MAX duration across sets[] using duration_sec', () {
      final log = <String, dynamic>{
        'sets': [
          {'duration_sec': 60},
          {'duration_sec': 80},
          {'duration_sec': 40},
        ],
        'set_number': 3,
        'duration_seconds': 180, // SUM
      };
      expect(WorkoutReadService.bestPerSetDuration(log), 80);
    });

    test('reads legacy duration_seconds per-set alias', () {
      final log = <String, dynamic>{
        'sets': [
          {'duration_seconds': 30},
          {'duration_seconds': 90},
        ],
      };
      expect(WorkoutReadService.bestPerSetDuration(log), 90);
    });

    test('falls back to top-level for legacy single-set', () {
      final log = <String, dynamic>{
        'set_number': 1,
        'duration_seconds': 45,
      };
      expect(WorkoutReadService.bestPerSetDuration(log), 45);
    });

    test('multi-set legacy without sets[] returns 0 (unrecoverable)', () {
      final log = <String, dynamic>{
        'set_number': 4,
        'duration_seconds': 330, // cumulative — must NOT surface
      };
      expect(WorkoutReadService.bestPerSetDuration(log), 0);
    });
  });

  group('WorkoutReadService.bestPerSetWeight', () {
    test('returns MAX weight across sets[]', () {
      final log = <String, dynamic>{
        'sets': [
          {'weight_kg': 60.0},
          {'weight_kg': 70.0},
          {'weight_kg': 80.0},
        ],
        'weight_kg': 80.0,
      };
      expect(WorkoutReadService.bestPerSetWeight(log), 80.0);
    });

    test('falls back to top-level weight_kg (writer-contract MAX) when sets[] missing', () {
      final log = <String, dynamic>{
        'weight_kg': 100.0,
      };
      expect(WorkoutReadService.bestPerSetWeight(log), 100.0);
    });

    test('returns 0 when both sources empty', () {
      expect(WorkoutReadService.bestPerSetWeight(<String, dynamic>{}), 0.0);
    });
  });

  group('WorkoutReadService.istDateForExlogRow', () {
    test('reads top-level date field', () {
      final log = <String, dynamic>{'date': '2026-05-15'};
      expect(WorkoutReadService.istDateForExlogRow(log), '2026-05-15');
    });

    test('falls back to created_at parsing', () {
      final log = <String, dynamic>{'created_at': '2026-05-15T10:00:00.000Z'};
      // 2026-05-15 10:00 UTC + 5:30 = 15:30 IST same day
      expect(WorkoutReadService.istDateForExlogRow(log), '2026-05-15');
    });

    test('returns null when neither field present', () {
      expect(
          WorkoutReadService.istDateForExlogRow(<String, dynamic>{}), isNull);
    });
  });
}
