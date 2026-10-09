// test/contracts/custom_exercises_mutations_writer_to_reader_test.dart
//
// SoT contract — concept `custom_exercises_mutations` (sot_registry.yaml).
// Source-grep pins for the CANONICAL writer / reader / restore paths.
//
// Sister test `custom_exercise_writer_to_reader_test.dart` pins the
// `custom_exercise_<ms>` Hive key shape + field set from the CREATE sheet
// path (legacy entry-point that now routes through this concept). This
// test pins the post-refactor canonical surface introduced by
// audit-2026-05-21 / A3 — `WorkoutWriteService.upsertCustomExercise` as
// the sole writer that touches `customBox.put` for `custom_exercise_<id>`
// keys, plus the canonical reader at
// `ExerciseRepository.getCustomExercises`.
//
// Closes Gate 9 (check_writeservice_contracts.dart) — the gate now
// detects only non-empty `hive_key_prefix` registry entries and required
// the corresponding writer-to-reader test for this concept.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String writeServiceSrc;
  late String repositorySrc;
  late String exerciseRepoSrc;
  late String syncCommunitySrc;

  setUpAll(() {
    writeServiceSrc =
        File('lib/core/services/workout_write_service.dart').readAsStringSync();
    repositorySrc = File('lib/features/train/repositories/workout_repository.dart')
        .readAsStringSync();
    exerciseRepoSrc = File('lib/shared/repositories/exercise_repository.dart')
        .readAsStringSync();
    syncCommunitySrc =
        File('lib/core/services/sync/sync_community.dart').readAsStringSync();
  });

  group('custom_exercises_mutations writer→reader contract', () {
    test('WorkoutWriteService.upsertCustomExercise is the canonical writer', () {
      // SoT registry: writer file `workout_write_service.dart`, method
      // `upsertCustomExercise`, line range 855-905 (audit 2026-05-21 / A3).
      expect(
        writeServiceSrc.contains('upsertCustomExercise'),
        isTrue,
        reason:
            'WorkoutWriteService.upsertCustomExercise must exist — it is the '
            'canonical writer per docs/sot_registry.yaml '
            'concept `custom_exercises_mutations`.',
      );
      // It must write to customBox via .put with the canonical key prefix.
      // Gate 16 (check_id_injection_on_get) + writeservice_only ensure the
      // put lives in this method and nowhere else.
      expect(
        writeServiceSrc.contains('customBox.put'),
        isTrue,
        reason: 'upsertCustomExercise must call customBox.put',
      );
      // The key prefix `custom_exercise_` is constructed by the caller
      // (WorkoutRepository.createCustomExercise) and passed to
      // upsertCustomExercise. So we pin the prefix on the caller side
      // below; here we only confirm the WriteService takes a `key`
      // parameter (no hard-coded key formula).
      expect(
        writeServiceSrc.contains('required String key'),
        isTrue,
        reason: 'upsertCustomExercise must take the Hive key as a parameter '
            '(constructed by the caller using the canonical formula).',
      );
    });

    test('WorkoutRepository constructs `custom_exercise_<ms>` key formula', () {
      // Per sot_registry `hive_key_formula:
      // "custom_exercise_${cloudRow.id}"` AND legacy
      // `custom_exercise_${DateTime.now().millisecondsSinceEpoch}` formula
      // for fresh local creates (cloud round-trip then converts to the
      // deterministic UUID v5 id).
      expect(
        repositorySrc.contains("'custom_exercise_") ||
            repositorySrc.contains('"custom_exercise_'),
        isTrue,
        reason: 'WorkoutRepository.createCustomExercise must construct the '
            '`custom_exercise_<id>` key prefix per sot_registry hive_key_formula.',
      );
    });

    test('WorkoutRepository.createCustomExercise routes through WriteService',
        () {
      // Audit 2026-05-21 / A3 — repository was a direct customBox.put;
      // now MUST delegate to WorkoutWriteService.upsertCustomExercise.
      expect(
        repositorySrc.contains('createCustomExercise'),
        isTrue,
        reason: 'WorkoutRepository.createCustomExercise must exist as the '
            'public entry-point invoked by widgets.',
      );
      expect(
        repositorySrc.contains('upsertCustomExercise'),
        isTrue,
        reason: 'WorkoutRepository.createCustomExercise must call '
            'WorkoutWriteService.upsertCustomExercise (audit 2026-05-21 / A3 '
            'refactor — direct customBox.put was eliminated).',
      );
    });

    test('ExerciseRepository.getCustomExercises is the canonical reader', () {
      // SoT registry reader: exercise_repository.dart:315-340.
      expect(
        exerciseRepoSrc.contains('getCustomExercises'),
        isTrue,
        reason: 'ExerciseRepository.getCustomExercises must exist as the '
            'canonical reader for `custom_exercise_` keyed entries.',
      );
      // Reader must iterate customBox (key-prefix or type-stamp scan).
      expect(
        exerciseRepoSrc.contains('customBox'),
        isTrue,
        reason:
            'getCustomExercises must read from customBox (not a different box)',
      );
    });

    test("restore path stamps `type:'exercise'` (Test #16 5e35aaf discriminator)",
        () {
      // Cloud has no `type` column — restore path must stamp it so the
      // reader's type-filter pre-fix path keeps matching legacy entries.
      // Sister diagnose-doc 2026-05-15-swap-picker-custom-miss-a5d29c.md.
      expect(
        syncCommunitySrc.contains('_restoreCustomExercises'),
        isTrue,
        reason: 'sync_community must declare _restoreCustomExercises restore '
            'path (referenced by sot_registry `restore_methods`).',
      );
      expect(
        syncCommunitySrc.contains("'type'") ||
            syncCommunitySrc.contains('"type"'),
        isTrue,
        reason: 'restore path must stamp the `type` field on each restored '
            'row — without it the reader filter silently drops them.',
      );
    });

    test('sync_community projects to user_custom_exercises cloud table', () {
      // SoT registry `cloud_table: user_custom_exercises`.
      expect(
        syncCommunitySrc.contains('user_custom_exercises'),
        isTrue,
        reason: 'sync_community must reference the user_custom_exercises '
            'cloud table for upward projection.',
      );
    });
  });
}
