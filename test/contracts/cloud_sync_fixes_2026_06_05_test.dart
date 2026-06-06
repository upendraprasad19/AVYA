// test/contracts/cloud_sync_fixes_2026_06_05_test.dart
//
// Part B of the 2026-06-05 cloud-sync batch — three live-audit fixes on the
// founder's account (d7a67a37). Source-grep contracts (comments stripped first,
// per feedback_source_grep_strip_comments_first) plus one behavioral check.
//
//   #2 reps silent-drop (e7b3c9): the logging_type repair migrator must NOT move
//      duration_seconds into reps; the exercise-log sync must clamp reps to the
//      wle_reps_realistic bound + emit wle_reps_out_of_range telemetry.
//   #3 user_progress.updated_at frozen (a2d8f4): _syncUserProgress must stamp
//      updated_at on every push.
//   #4 _TypeError on check_and_sync (c5e1b7): the health-sync completer must be
//      completed via a null-safe guard, never a bare `!`.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Strip block + line comments so assertions check CODE, not the explanatory
/// prose (the migrator's new comments literally mention "duration -> reps").
String _stripComments(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

void main() {
  final syncWorkoutSrc = _stripComments(
      File('lib/core/services/sync/sync_workout.dart').readAsStringSync());
  final syncProfileSrc = _stripComments(
      File('lib/core/services/sync/sync_profile.dart').readAsStringSync());
  final syncServiceSrc = _stripComments(
      File('lib/core/services/sync_service.dart').readAsStringSync());

  group('#2 reps silent-drop — constraint + clamp (e7b3c9)', () {
    // NOTE: the logging_type_repair_migrator's duration->reps move is
    // INTENTIONAL (APK Test #12.5 / logging_type_repair_migrator_test "v3").
    // The fix for the >1000 silent-drop is NOT to change the migrator but to
    // widen the cap (migration 084) and clamp + telemetry-log at the sync sink.
    test('exercise-log sync clamps reps to the wle bound + logs out-of-range',
        () {
      expect(syncWorkoutSrc.contains('clampedReps'), isTrue);
      expect(syncWorkoutSrc.contains('clamp(0, 10000)'), isTrue,
          reason: 'reps must be clamped to the wle_reps_realistic bound (<=10000)');
      expect(syncWorkoutSrc.contains('wle_reps_out_of_range'), isTrue,
          reason: 'an out-of-range reps value must be captured in telemetry, '
              'not silently rejected by Postgres (23514)');
      expect(syncWorkoutSrc.contains("'reps': log['reps_completed']"), isFalse,
          reason: 'the upsert must write the clamped value, not the raw one');
    });

    test('migration 084 widens wle_reps_realistic to <= 10000', () {
      final sql = File(
        'supabase/migrations/084_widen_wle_reps_realistic_high_volume.sql',
      ).readAsStringSync();
      final liveDdl = sql
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('--'))
          .join('\n');
      expect(RegExp(r'reps\s*<=\s*10000').hasMatch(liveDdl), isTrue,
          reason: 'the live ADD CONSTRAINT must allow cumulative totals <= 10000 '
              '(diagnose e7b3c9)');
    });
  });

  group('#3 user_progress.updated_at frozen (a2d8f4)', () {
    test('_syncUserProgress stamps updated_at on every push', () {
      // The user_progress upsert (no DB trigger) must set updated_at to now.
      expect(syncProfileSrc.contains('_syncUserProgress'), isTrue);
      expect(
          syncProfileSrc.contains(
              "'updated_at': DateTime.now().toUtc().toIso8601String()"),
          isTrue,
          reason: 'user_progress upsert must stamp updated_at — otherwise the '
              'column stays frozen at created_at and changed-since logic breaks');
    });
  });

  group('#4 check_and_sync null-check (c5e1b7)', () {
    test('health-sync completer is completed null-safe, not via a bare `!`', () {
      expect(syncServiceSrc.contains('_healthSyncCompleter!.complete()'), isFalse,
          reason: 'a concurrent user-switch nulls _healthSyncCompleter, so the '
              'bare `!` throws _TypeError on the check_and_sync path');
      expect(
          syncServiceSrc.contains('final hsc = _healthSyncCompleter') &&
              syncServiceSrc.contains('hsc.complete()'),
          isTrue,
          reason: 'must read the field into a local + guard null/isCompleted');
    });
  });

  group('#2b wls per-set reps silent-drop — sets table (d9a4f2)', () {
    test('per-set sync clamps reps to the wls bound + logs out-of-range', () {
      expect(syncWorkoutSrc.contains('clampedSetReps'), isTrue);
      expect(syncWorkoutSrc.contains("'reps': clampedSetReps"), isTrue,
          reason: 'the per-set upsert must write the clamped value');
      expect(syncWorkoutSrc.contains('wls_reps_out_of_range'), isTrue,
          reason: 'an out-of-range per-set reps value must be captured in '
              'telemetry, not silently rejected (23514)');
      expect(syncWorkoutSrc.contains("'reps': sm['reps']"), isFalse,
          reason: 'the per-set upsert must not write the raw value');
    });

    test('migration 085 widens wls_reps_realistic to <= 10000', () {
      final sql = File(
        'supabase/migrations/085_widen_wls_reps_realistic.sql',
      ).readAsStringSync();
      final liveDdl = sql
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('--'))
          .join('\n');
      expect(liveDdl.contains('workout_log_sets'), isTrue);
      expect(RegExp(r'reps\s*<=\s*10000').hasMatch(liveDdl), isTrue,
          reason: 'the live ADD CONSTRAINT must allow per-set totals <= 10000 '
              '(diagnose d9a4f2)');
    });

    test('migrator gates the duration->reps move by a plausible-reps threshold',
        () {
      final migratorSrc = _stripComments(File(
        'lib/core/services/logging_type_repair_migrator.dart',
      ).readAsStringSync());
      expect(migratorSrc.contains('_kMaxPlausibleReps'), isTrue,
          reason: 'the bodyweight_reps duration->reps move must be gated by the '
              'plausible-reps threshold so a large duration is not fabricated '
              'into a per-set rep count (d9a4f2)');
    });
  });
}
