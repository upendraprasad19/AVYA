// APK Test #15.3 / Bug 4c (6e1b45) — timed-exercise per-set render contract.
//
// Founder observation 2026-05-11: on Train screen day card for Monday
// 2026-05-11, Handstand Hold rendered as "3 sets · 0s" (Jump Rope
// "2 sets · 0s") instead of the per-set duration chips the user had
// logged (10s × 3 / 30s × 2).
//
// Cloud `workout_log_sets.duration_secs` HAS correct values; cloud
// `workout_log_exercises` summary lacks `duration_seconds` (the writer
// never writes top-level aggregate duration). Local Hive `exlog_*.sets[]`
// after restore is the contract this test pins.
//
// The "3 sets · 0s" format is the WardSetChips fallbackLabel — it fires
// when `perSetBreakdown.isEmpty`. So the failure mode is: per-set chip
// data must reach WardSetChips with `durationSeconds` populated so the
// chip Wrap renders "10 secs" × N rather than the fallback "N sets · 0s".
//
// Three contract layers pinned here:
//
//   1. Writer contract (WorkoutWriteService.logExercise):
//      For a timed exercise (library-resolved), per-set entries must
//      persist `duration_sec` so downstream readers can render
//      per-set chips.
//
//   2. Restore contract (SyncService._restoreExerciseLogs):
//      Cloud `workout_log_sets.duration_secs` round-trips into Hive
//      per-set entries with a field name the readers accept
//      (`duration_seconds` is written by restore; readers accept either
//      field name).
//
//   3. Reader → WardSetChips contract:
//      WorkoutReceiptData.fromExerciseLogs populates
//      `perSetBreakdown[].durationSeconds` from the per-set Hive entries
//      so WardSetChips renders timed chips (not the fallback summary).
//
// If any layer drops the duration, the relevant test fails with a
// pointer to the layer that broke the contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/features/train/widgets/workout_receipt_card.dart';

import '../workout_write_service/helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await wwsTestSetup();

    // Seed exercise library entries so the writer's library-strict path
    // resolves to 'timed'. exerciseBox is a SHARED (not user-scoped) box;
    // wwsTestSetup doesn't open it because most tests don't need it.
    if (!Hive.isBoxOpen(HiveService.exerciseBoxName)) {
      await Hive.openBox(HiveService.exerciseBoxName);
    }
    final exb = HiveService.instance.exerciseBox;
    await exb.put('handstand_hold', {
      'name': 'Handstand Hold',
      'logging_type': 'timed',
    });
    await exb.put('jump_rope', {
      'name': 'Jump Rope',
      'logging_type': 'timed',
    });
  });

  tearDown(() async {
    await wwsTestTeardown();
  });

  group('Layer 1: writer persists duration_sec for timed per-set entries', () {
    test(
      'Handstand Hold (library timed) with durationSec=10 ×3 → per-set sets[] '
      'carries duration_sec=10 for each entry',
      () async {
        // Mirrors the active-workout path: user typed 10 into the duration
        // input for each of 3 sets. The reps controller still held its
        // pre-filled midpoint (10) — that bleed is fine, _stripPhantomFields
        // clears it post-resolve.
        final date = DateTime(2026, 5, 11);
        final result = await WorkoutWriteService.instance.logExercise(
          date: date,
          exerciseName: 'Handstand Hold',
          sets: const [
            ExerciseSet(weightKg: 0, reps: 10, durationSec: 10),
            ExerciseSet(weightKg: 0, reps: 10, durationSec: 10),
            ExerciseSet(weightKg: 0, reps: 10, durationSec: 10),
          ],
          source: WriteSource.activeWorkout,
        );
        expect(result.success, isTrue);

        final box = HiveService.instance.workoutBox;
        final key = box.keys
            .firstWhere((k) => k.toString().startsWith('exlog_'));
        final row = box.get(key) as Map;

        expect(row['logging_type'], 'timed',
            reason: 'library says timed — must override data shape');
        expect(row['set_number'], 3);

        final sets = row['sets'] as List;
        expect(sets, hasLength(3));
        for (final raw in sets) {
          final m = raw as Map;
          expect(m['duration_sec'], 10,
              reason:
                  'per-set duration_sec MUST persist so receipt + train view '
                  'render timed chips (not "0 secs" fallback)');
          expect(m['reps'], 0,
              reason: '_stripPhantomFields(timed) clears reps from per-set');
          expect((m['weight_kg'] as num).toDouble(), 0.0);
        }
      },
    );
  });

  group('Layer 2: restore reconstructs per-set duration into readable shape',
      () {
    test(
      'restored sets[] with field name duration_seconds is read correctly '
      'by WorkoutReceiptData (reader accepts both field names)',
      () async {
        // Mirrors the restore-from-cloud projection in
        // SyncService._restoreExerciseLogs (line ~2852): cloud
        // workout_log_sets.duration_secs → per-set map field
        // 'duration_seconds' (legacy name). Reader must accept both
        // 'duration_sec' and 'duration_seconds' on the per-set map.
        final date = DateTime(2026, 5, 11);
        final box = HiveService.instance.workoutBox;
        final dateStr = '2026-05-11';
        final logKey = 'exlog_${date.millisecondsSinceEpoch}_jumprope';

        // Build the restored shape by hand (matches restore output).
        await box.put(logKey, {
          'exercise_name': 'Jump Rope',
          'date': dateStr,
          'logging_type': 'timed',
          'set_number': 2,
          'reps_completed': 0,
          'weight_kg': 0.0,
          'sets': [
            {
              'set_number': 1,
              'weight_kg': 0.0,
              'reps': 0,
              'duration_seconds': 30, // ← restore writes legacy field name
            },
            {
              'set_number': 2,
              'weight_kg': 0.0,
              'reps': 0,
              'duration_seconds': 30,
            },
          ],
        });

        // Date index so fromExerciseLogs finds the row via the O(1) path.
        await box.put('exercise_log_index_$dateStr', [logKey]);

        final receipt = WorkoutReceiptData.fromExerciseLogs(date);
        expect(receipt, isNotNull,
            reason: 'restored exlog must be visible to receipt builder');
        expect(receipt!.exercises, hasLength(1));

        final ex = receipt.exercises.first;
        expect(ex.loggingType, 'timed');
        expect(ex.perSetBreakdown, hasLength(2),
            reason:
                'receipt MUST surface every restored set; an empty perSet '
                'breakdown forces WardSetChips into "N sets · 0s" fallback');

        for (final s in ex.perSetBreakdown) {
          expect(s.durationSeconds, 30,
              reason:
                  'receipt reader MUST accept the legacy duration_seconds '
                  'field name on restored per-set entries — otherwise the '
                  'duration is dropped between cloud and screen');
        }
      },
    );
  });

  group('Layer 3: writer→receipt end-to-end produces non-empty perSet for timed',
      () {
    test(
      'Jump Rope timed write → receipt.perSetBreakdown has populated '
      'durationSeconds (NOT empty → WardSetChips fallback)',
      () async {
        final date = DateTime(2026, 5, 11);
        final result = await WorkoutWriteService.instance.logExercise(
          date: date,
          exerciseName: 'Jump Rope',
          sets: const [
            ExerciseSet(weightKg: 0, reps: 0, durationSec: 30),
            ExerciseSet(weightKg: 0, reps: 0, durationSec: 30),
          ],
          source: WriteSource.activeWorkout,
        );
        expect(result.success, isTrue);

        final receipt = WorkoutReceiptData.fromExerciseLogs(date);
        expect(receipt, isNotNull);
        expect(receipt!.exercises, hasLength(1));

        final ex = receipt.exercises.first;
        expect(ex.loggingType, 'timed');

        // CRITICAL: perSetBreakdown MUST be non-empty so WardSetChips
        // renders per-set chips. An empty list forces the fallbackLabel
        // path → "2 sets · 0s" (the founder's bug report).
        expect(ex.perSetBreakdown, hasLength(2),
            reason:
                'timed writes MUST produce a populated perSetBreakdown — '
                'an empty list is the WardSetChips fallback trigger that '
                'rendered "2 sets · 0s" in the Bug 4c report');

        for (final s in ex.perSetBreakdown) {
          expect(s.durationSeconds, 30,
              reason:
                  'WardSetChips reads durationSeconds for loggingType=timed; '
                  'a null/0 value renders "0 secs" per chip');
        }
      },
    );
  });

  group(
      'Layer 4: ExerciseSet.fromMap accepts BOTH duration_sec and '
      'duration_seconds field names (cross-writer field-name contract)', () {
    test(
      'restored per-set entries with duration_seconds round-trip through '
      'logExercise re-merge WITHOUT losing duration',
      () async {
        // Reproduces the founder-bug data flow:
        //   1. Active workout logs Jump Rope timed → cloud workout_log_sets
        //      gets duration_secs=30 per row.
        //   2. Cloud restore writes Hive sets[] with field name
        //      'duration_seconds' (LEGACY), not 'duration_sec' (canonical).
        //   3. AI coach tool-dispatcher or 60s-dedup re-merge calls
        //      WorkoutWriteService.logExercise for the same date+exercise.
        //   4. WriteService parses existing sets via `ExerciseSet.fromMap`,
        //      which (pre-fix) reads ONLY 'duration_sec' → duration drops
        //      to null → next persist writes per-set without duration →
        //      Train day card shows "2 sets · 0s" fallback.
        //
        // This test pre-seeds Hive with the restore-shape exlog, then
        // calls logExercise with a fresh (different ms timestamp, so no
        // dedup) set. After the merge, the ORIGINAL restored sets MUST
        // still carry their duration values.
        final date = DateTime(2026, 5, 11);
        final dateStr = '2026-05-11';
        final box = HiveService.instance.workoutBox;
        final logKey = WorkoutWriteService.exlogKey(date, 'Jump Rope');

        // Pre-seed restore-shape: per-set uses legacy 'duration_seconds'
        // (matches sync_service._restoreExerciseLogs line ~2853).
        await box.put(logKey, {
          'exercise_name': 'Jump Rope',
          'date': dateStr,
          'logging_type': 'timed',
          'set_number': 2,
          'reps_completed': 0,
          'weight_kg': 0.0,
          'sets': [
            {
              'set_number': 1,
              'weight_kg': 0.0,
              'reps': 0,
              'duration_seconds': 30, // ← legacy field name from restore
              'logged_at_ms': 1000,
            },
            {
              'set_number': 2,
              'weight_kg': 0.0,
              'reps': 0,
              'duration_seconds': 30,
              'logged_at_ms': 2000,
            },
          ],
        });
        await box.put('exercise_log_index_$dateStr', [logKey]);

        // Now re-merge via a fresh logExercise (different loggedAtMs so
        // dedup window doesn't swallow it). This is the path AI
        // tool-dispatcher uses when the user says "I did one more set of
        // jump rope."
        final result = await WorkoutWriteService.instance.logExercise(
          date: date,
          exerciseName: 'Jump Rope',
          sets: [
            ExerciseSet(
              weightKg: 0,
              reps: 0,
              durationSec: 30,
              loggedAtMs: 9_999_999_999, // far outside 60s dedup window
            ),
          ],
          source: WriteSource.aiCoach,
        );
        expect(result.success, isTrue);

        // Read back. All 3 sets (2 restored + 1 freshly merged) must have
        // duration_sec populated.
        final row = box.get(logKey) as Map;
        final sets = row['sets'] as List;
        expect(sets, hasLength(3),
            reason: 'restored + new should merge to 3 sets total');

        for (var i = 0; i < sets.length; i++) {
          final s = sets[i] as Map;
          // After WriteService persists, the canonical field is
          // 'duration_sec' (toMap output). The restore-shape's
          // 'duration_seconds' MUST be picked up by fromMap on re-merge
          // so the round-trip preserves the value.
          final dCanonical = (s['duration_sec'] as num?)?.toInt();
          final dLegacy = (s['duration_seconds'] as num?)?.toInt();
          final d = dCanonical ?? dLegacy;
          expect(d, 30,
              reason:
                  'set $i lost duration on re-merge. ExerciseSet.fromMap '
                  'must accept BOTH duration_sec AND duration_seconds '
                  'field names so restored data survives a subsequent '
                  'logExercise call. This is the root-tier failure that '
                  'produced "N sets · 0s" in the founder report.');
        }
      },
    );

    test(
      'ExerciseSet.fromMap directly accepts duration_seconds (legacy)',
      () {
        // Tightest possible unit pin — direct fromMap call to demonstrate
        // the universal field-name acceptance contract.
        final fromLegacy = ExerciseSet.fromMap({
          'weight_kg': 0,
          'reps': 0,
          'duration_seconds': 45,
          'logged_at_ms': 1000,
        });
        expect(fromLegacy.durationSec, 45,
            reason:
                'fromMap must read legacy duration_seconds; restored sets '
                'use this field name (see sync_service._restoreExerciseLogs)');

        final fromCanonical = ExerciseSet.fromMap({
          'weight_kg': 0,
          'reps': 0,
          'duration_sec': 45,
          'logged_at_ms': 1000,
        });
        expect(fromCanonical.durationSec, 45,
            reason: 'fromMap must keep reading canonical duration_sec');
      },
    );
  });
}
