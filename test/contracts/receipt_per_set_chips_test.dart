// APK Test #12.6 — receipt per-set chip contract.
//
// Pins the contract that every receipt-build path produces a populated
// [ReceiptExercise.perSetBreakdown] with one entry per logged set, AND
// that the resulting card uses [WardSetChips] (the shared per-set chip
// primitive) rather than a single summary chip.
//
// Founder observation 2026-05-07: post-completion receipt rendered
// "[3 sets · 30 reps · 80 kg]" (one summary chip) instead of
// "[80 kg × 10 reps] [80 kg × 10 reps] [80 kg × 10 reps]" (three per-set
// chips). Root cause: [WorkoutReceiptData.fromActiveWorkout] never
// populated [perSetBreakdown], so [WardSetChips] fell back to its
// fallbackLabel single-chip path. Same primitive, wrong input.
//
// Volume math is also pinned: a 3 × 80 kg × 10 reps log MUST produce
// totalVolumeKg = 2400 derived from per-set sums, not the cached
// top-level field (which can drift if sets[] gets repopulated).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/widgets/workout_receipt_card.dart';

import '../workout_write_service/helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Receipt builders populate perSetBreakdown', () {
    setUp(() async {
      await wwsTestSetup();
    });

    tearDown(() async {
      await wwsTestTeardown();
    });

    test(
      'fromExerciseLogs: 3-set Bench produces 3-element perSetBreakdown',
      () async {
        final date = DateTime(2026, 5, 7);
        final result = await WorkoutWriteService.instance.logExercise(
          date: date,
          exerciseName: 'Bench Press',
          sets: const [
            ExerciseSet(weightKg: 80, reps: 10),
            ExerciseSet(weightKg: 80, reps: 10),
            ExerciseSet(weightKg: 80, reps: 10),
          ],
          source: WriteSource.activeWorkout,
        );
        expect(result.success, isTrue);

        final receipt = WorkoutReceiptData.fromExerciseLogs(date);
        expect(receipt, isNotNull);
        expect(receipt!.exercises, hasLength(1));

        final ex = receipt.exercises.first;
        expect(ex.perSetBreakdown, hasLength(3),
            reason:
                'each completed set must surface in perSetBreakdown so WardSetChips renders one chip per set');
        for (final s in ex.perSetBreakdown) {
          expect(s.weightKg, 80);
          expect(s.reps, 10);
        }
      },
    );

    test(
      'fromExerciseLogs: volume math derives from per-set sum (not cached field)',
      () async {
        // Pin: 3 × 80 kg × 10 reps → 2400 kg of volume. The receipt MUST
        // reflect the per-set sum even when the cached `volume_kg` field
        // is stale or wrong.
        final date = DateTime(2026, 5, 7);
        final result = await WorkoutWriteService.instance.logExercise(
          date: date,
          exerciseName: 'Leg Press',
          sets: const [
            ExerciseSet(weightKg: 80, reps: 10),
            ExerciseSet(weightKg: 80, reps: 10),
            ExerciseSet(weightKg: 80, reps: 10),
          ],
          source: WriteSource.activeWorkout,
        );
        expect(result.success, isTrue);

        // Tamper with the cached `volume_kg` field to confirm the
        // receipt re-derives from sets[] rather than blindly trusting
        // the stored aggregate.
        final box = HiveService.instance.workoutBox;
        final key = WorkoutWriteService.exlogKey(date, 'Leg Press');
        final entry = (box.get(key) as Map).cast<String, dynamic>();
        entry['volume_kg'] = 0.0; // intentionally wrong cached value
        await box.put(key, entry);

        final receipt = WorkoutReceiptData.fromExerciseLogs(date);
        expect(receipt, isNotNull);
        expect(receipt!.totalVolumeKg, 2400.0,
            reason:
                'volume must be summed from per-set entries (80 × 10 × 3), not read from the corrupted cached `volume_kg` field');
      },
    );
  });

  group('fromActiveWorkout populates perSetBreakdown (no Hive)', () {
    test(
      'in-memory builder yields one ReceiptSet per checked working set',
      () {
        // Three completed working sets at 80 kg × 10 reps for one
        // exercise. Mirrors the data shape ActiveWorkoutNotifier holds
        // in memory at the moment SHARE YOUR SESSION is tapped, BEFORE
        // any Hive read could service the receipt.
        const exercise = ExerciseData(
          name: 'Bench Press',
          loggingType: 'weight_reps',
          sets: '3',
          reps: '10',
          rest: '90s',
        );
        final data = ActiveWorkoutData(
          workoutDay: WorkoutDayData(
            dayNumber: 1,
            name: 'Push Day',
            date: DateTime(2026, 5, 7),
          ),
          exercises: const [exercise],
          checkedSets: const {
            '0-0': true,
            '0-1': true,
            '0-2': true,
          },
          warmUpSets: const {},
          setInputValues: const {
            '0-0': SetInputValues(weight: 80, reps: 10),
            '0-1': SetInputValues(weight: 80, reps: 10),
            '0-2': SetInputValues(weight: 80, reps: 10),
          },
        );

        final receipt = WorkoutReceiptData.fromActiveWorkout(data);
        expect(receipt.exercises, hasLength(1));

        final ex = receipt.exercises.first;
        expect(ex.perSetBreakdown, hasLength(3),
            reason:
                'fromActiveWorkout must collect one ReceiptSet per checked working set');
        for (final s in ex.perSetBreakdown) {
          expect(s.weightKg, 80);
          expect(s.reps, 10);
        }
        expect(receipt.totalVolumeKg, 2400.0);
        expect(receipt.totalSets, 3);
      },
    );
  });

  group('WorkoutReceiptCard source uses WardSetChips primitive', () {
    test(
      'workout_receipt_card.dart imports + delegates to WardSetChips',
      () {
        // Source-grep contract: locks the receipt card to the shared
        // chip primitive so a future refactor can't accidentally
        // resurrect the inline summary-chip widget that hid per-set
        // progression. Founder feedback APK Test #12.5: receipt
        // rendered "[3 sets · 30 reps · 80 kg]" instead of
        // "[80 kg × 10 reps] [80 kg × 10 reps] [80 kg × 10 reps]"
        // because [WorkoutReceiptData.fromActiveWorkout] never
        // populated [perSetBreakdown] — WardSetChips fell back to
        // its single summary chip path.
        final source = File(
          'lib/features/train/widgets/workout_receipt_card.dart',
        ).readAsStringSync();

        expect(
          source.contains("import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart'"),
          isTrue,
          reason:
              'workout_receipt_card.dart must import the Wardroom barrel which re-exports WardSetChips',
        );
        expect(
          source.contains('WardSetChips('),
          isTrue,
          reason:
              'WorkoutReceiptCard MUST delegate per-set chip rendering to the shared WardSetChips primitive (Theme E)',
        );
        // Pin: the inline _SetChip widget that used to live here was
        // removed in Theme E-3. Resurrecting it would split the chip
        // rendering across two surfaces again.
        expect(
          source.contains('class _SetChip'),
          isFalse,
          reason:
              'inline _SetChip class was removed in Theme E-3 — chip rendering belongs to WardSetChips alone',
        );
      },
    );
  });
}
