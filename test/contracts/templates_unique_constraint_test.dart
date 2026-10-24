// APK Test #12.7 — pin migration 050 contract.
//
// Founder install of APK 12.6 surfaced 8 duplicate `workout_templates`
// rows because the table had no UNIQUE constraint on (user_id, name) and
// `SyncService` retried the upsert with a fresh non-deterministic UUID
// each time. Migration 050 dedups historical rows + adds the constraint;
// this test source-greps the migration to make sure it stays that way.
//
// We don't connect to Postgres in CI — we just assert the SQL contains
// the four load-bearing pieces:
//   (a) FK re-point UPDATEs for the 3 dependent tables
//       (template_exercises, scheduled_workouts, workout_logs),
//   (b) DELETE FROM public.workout_templates,
//   (c) ADD CONSTRAINT ... UNIQUE (user_id, name),
//   (d) wrapped in a transaction (BEGIN/COMMIT) for atomicity.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('migration 050 — workout_templates unique (user_id, name)', () {
    late final String sql;

    setUpAll(() {
      // audit-2026-05-11 H-33 — file renamed to 050b because of a
      // numeric-prefix collision with 050_streak_freezes_default_one.
      // See supabase/migrations/README_RECONCILIATION_2026-05-11.md.
      final f = File(
        'supabase/migrations/050b_workout_templates_unique_user_name.sql',
      );
      expect(f.existsSync(), isTrue,
          reason: 'migration 050b must exist at the expected path');
      sql = f.readAsStringSync();
    });

    test('adds UNIQUE constraint on (user_id, name)', () {
      // Allow flexible whitespace/formatting around the constraint def.
      final pat = RegExp(
        r'UNIQUE\s*\(\s*user_id\s*,\s*name\s*\)',
        caseSensitive: false,
      );
      expect(pat.hasMatch(sql), isTrue,
          reason:
              'migration must add UNIQUE (user_id, name) on workout_templates');
    });

    test('uses ADD CONSTRAINT (not just CREATE UNIQUE INDEX)', () {
      // The constraint form gives us a named conkey we can detect from
      // pg_constraint and surface 23505 nicely from upserts.
      expect(
        sql.toUpperCase().contains('ADD CONSTRAINT'),
        isTrue,
        reason: 'must use ADD CONSTRAINT for proper conkey integration',
      );
    });

    test('re-points FK rows from template_exercises', () {
      final pat = RegExp(
        r'UPDATE\s+public\.template_exercises',
        caseSensitive: false,
      );
      expect(pat.hasMatch(sql), isTrue,
          reason:
              'must re-point template_exercises.template_id before deleting dups');
    });

    test('re-points FK rows from scheduled_workouts', () {
      final pat = RegExp(
        r'UPDATE\s+public\.scheduled_workouts',
        caseSensitive: false,
      );
      expect(pat.hasMatch(sql), isTrue,
          reason:
              'must re-point scheduled_workouts.template_id before deleting dups');
    });

    test('re-points FK rows from workout_logs', () {
      final pat = RegExp(
        r'UPDATE\s+public\.workout_logs',
        caseSensitive: false,
      );
      expect(pat.hasMatch(sql), isTrue,
          reason:
              'must re-point workout_logs.template_id before deleting dups');
    });

    test('deletes dup workout_templates rows', () {
      final pat = RegExp(
        r'DELETE\s+FROM\s+public\.workout_templates',
        caseSensitive: false,
      );
      expect(pat.hasMatch(sql), isTrue,
          reason: 'must delete the dup rows after re-pointing FKs');
    });

    test('runs inside an explicit transaction', () {
      expect(sql.toUpperCase().contains('BEGIN'), isTrue);
      expect(sql.toUpperCase().contains('COMMIT'), isTrue);
    });

    test('idempotent: guards constraint creation with IF NOT EXISTS check',
        () {
      // Postgres does not support "ADD CONSTRAINT IF NOT EXISTS" directly.
      // We accept either an explicit pg_constraint NOT EXISTS guard or a
      // `WHERE conname = 'workout_templates_user_id_name_key'` lookup.
      final hasGuard = sql.contains('IF NOT EXISTS') ||
          sql.contains('workout_templates_user_id_name_key');
      expect(hasGuard, isTrue,
          reason:
              'must be safe to re-run — guard the ADD CONSTRAINT step against '
              're-application');
    });
  });
}
