// Regression test for audit 2026-05-16 / E.12 (dead column migration).
//
// Bug: 17 cloud columns across 7 tables were 100% NULL across all live
// rows (audit Agent 3 / Cluster 4 live SQL verification 2026-05-16). They
// had no client writer, no client reader (only the sync projection that
// silently wrote NULL on every upsert), and no UI surface to populate
// them.
//
// Fix: migration 067 drops them. Client sync projections in
// `sync_workout.dart` + `sync_profile.dart` are trimmed to the surviving
// columns so the post-migration upserts don't error with "column does
// not exist".
//
// This is a source-grep test that asserts the projections no longer
// reference the dropped column names. If a future edit re-adds a
// projection of a dropped column, the test fails before the next sync
// errors out in prod.
//
// closes-diagnose: 2026-05-16-dead-columns-dropped

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Audit-2026-05-16 / E.12 — sync projections trimmed of dropped columns',
      () {
    late String syncWorkout;
    late String syncProfile;

    setUpAll(() {
      syncWorkout =
          File('lib/core/services/sync/sync_workout.dart').readAsStringSync();
      syncProfile =
          File('lib/core/services/sync/sync_profile.dart').readAsStringSync();
    });

    test('workout_logs projection does NOT write dropped columns', () {
      // _syncWorkoutLogs upsert block. Dropped columns: sets_completed, rpe,
      // and the pre-existing dead ones (scheduled_workout_id, template_id,
      // exercise_id, reps_completed, weight_kg, distance_km).
      final upsertIdx = syncWorkout.indexOf("from('workout_logs').upsert(");
      expect(upsertIdx, isNot(-1));
      // Block is short — 600 chars covers the upsert body.
      final block = syncWorkout.substring(upsertIdx, upsertIdx + 600);
      for (final col in [
        "'sets_completed':",
        "'rpe':",
        "'scheduled_workout_id':",
        "'template_id':",
      ]) {
        expect(block.contains(col), isFalse,
            reason:
                "workout_logs upsert must not project $col — migration 067 "
                "dropped it. Hive field name may still exist (for restore "
                "round-trip + legacy migrators) but the cloud projection "
                "must NOT write it.");
      }
    });

    test('template_exercises projection does NOT write dropped columns', () {
      // The template_exercises projection lives inside _syncWorkoutTemplates.
      // Dropped: exercise_id, rest_seconds, prescribed_weight,
      // prescribed_time_secs, notes (column on template_exercises specifically).
      final upsertIdx =
          syncWorkout.indexOf("from('template_exercises').upsert(");
      // template_exercises upsert is buried deep; find via prescribed_sets
      // which is a unique projection key in that block.
      final blockIdx = syncWorkout.indexOf("'prescribed_sets'");
      expect(blockIdx, isNot(-1),
          reason: 'template_exercises upsert block must exist');
      // Look ~400 chars around it.
      final start = (blockIdx - 400).clamp(0, syncWorkout.length);
      final end = (blockIdx + 400).clamp(0, syncWorkout.length);
      final block = syncWorkout.substring(start, end);
      for (final col in [
        "'rest_seconds':",
        "'prescribed_weight':",
        "'prescribed_time_secs':",
        "if (ex['notes'] != null) 'notes':",
      ]) {
        expect(block.contains(col), isFalse,
            reason:
                'template_exercises upsert must not project $col — '
                'migration 067 dropped it.');
      }
      // Anti-regression: dropped `if (isUuid) 'exercise_id':` line.
      expect(block.contains("if (isUuid) 'exercise_id':"), isFalse,
          reason:
              "template_exercises.exercise_id dropped; the `if (isUuid)` "
              'gate that wrote it is gone.');
      // ignore: unused_local_variable
      final _ = upsertIdx; // upsert anchor used implicitly
    });

    test('workout_templates projection does NOT write dropped columns', () {
      final upsertIdx =
          syncWorkout.indexOf("from('workout_templates').upsert(");
      expect(upsertIdx, isNot(-1));
      final block = syncWorkout.substring(upsertIdx, upsertIdx + 800);
      for (final col in [
        "'description':",
        "'estimated_duration_mins':",
      ]) {
        expect(block.contains(col), isFalse,
            reason:
                "workout_templates upsert must not project $col — "
                'migration 067 dropped it.');
      }
    });

    test('user_preferences projection does NOT write biggest_obstacle', () {
      expect(syncProfile.contains("'biggest_obstacle':"), isFalse,
          reason:
              'user_preferences.biggest_obstacle dropped by migration 067. '
              'Projection in _syncUserPreferences must not write it.');
    });

    test('applied_migrations.json lists migration 067', () {
      final src = File('backups/applied_migrations.json').readAsStringSync();
      expect(src.contains('"067"'), isTrue,
          reason:
              'applied_migrations.json must list migration 067 (pair-update '
              'rule per `feedback_migration_apply_record_pair.md`).');
    });
  });
}
