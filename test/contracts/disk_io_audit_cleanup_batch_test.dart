// Regression test for the 2026-09-22 disk-IO-budget-exhaustion fix batch
// (diagnose e8b4a1). Source-grep, presence-only — these are Postgres
// config/schedule changes with no Dart runtime path, so a live-Postgres
// behavioral assertion would require real Supabase credentials in the test
// environment; this pins the migration content and registry parity instead.
// Fails before migration 141 existed with the expected content.
//
// NOTE: Fix A (cron.log_run=off) is NOT covered here. It was drafted as
// migration 140 and discovered non-viable as SQL — pg_settings shows
// cron.log_run has context=postmaster, meaning ALTER DATABASE ... SET cannot
// apply it at all (Postgres refuses outright); it requires a full server
// restart via Supabase's dashboard/support, a materially different action
// than a reversible migration. Migration 140 was deleted rather than left as
// a permanently-unapplied file. See the diagnose-doc's Notes section.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('disk-IO audit cleanup batch (diagnose e8b4a1)', () {
    late String migration141;
    late String migration141Active; // excludes the commented rollback block
    late String registry;

    setUpAll(() {
      migration141 = File(
        'supabase/migrations/141_disk_io_audit_cleanup_batch.sql',
      ).readAsStringSync();
      // The rollback block legitimately contains the OLD values (lists=100,
      // */15 cadences, etc.) as commented-out restore DDL — assertions about
      // the ACTIVE fix must not be satisfied by that block, or a reverted fix
      // would still read as present.
      migration141Active = migration141.split('-- Rollback (commented')[0];
      registry = File('docs/operations/CRON_REGISTRY.md').readAsStringSync();
    });

    test(
      'migration 142 restores the FK-support index migration 141 wrongly dropped',
      () {
        final migration142 = File(
          'supabase/migrations/142_restore_nutrition_log_items_food_id_index.sql',
        ).readAsStringSync();
        expect(migration142, contains('idx_nutrition_log_items_food_id'));
        expect(migration142, contains('nutrition_log_items'));
        expect(migration142, contains('food_id'));
        // IF NOT EXISTS is the fix for the sibling robustness gap this same
        // review found in migration 141's unguarded cron.unschedule() calls —
        // practicing the lesson in the migration that documents it.
        expect(migration142, contains('CREATE INDEX IF NOT EXISTS'));
      },
    );

    test('migration 141 retunes memory_embeddings ivfflat for actual row count', () {
      expect(migration141Active, contains('idx_memory_embeddings_ivfflat'));
      // Boundary on the closing paren: 'lists = 10' is also a substring of
      // 'lists = 100', so without the boundary a mutation to 100 would not
      // redden this assertion (verified — see diagnose e8b4a1 mutation proof).
      expect(migration141Active, contains('lists = 10)'));
      expect(migration141Active, isNot(contains('lists = 100)')));
    });

    test('migration 141 fixes readiness_daily RLS auth-initplan', () {
      expect(migration141, contains('users_own_readiness_daily'));
      expect(migration141, contains('(select auth.uid())'));
    });

    test('migration 141 drops the two verified-dead indexes', () {
      expect(
        migration141,
        contains('idx_ai_coach_interactions_tool_calls_failed'),
      );
      expect(migration141, contains('idx_nutrition_log_items_food_id'));
    });

    test('migration 141 consolidates housekeeping jobs into db_maintenance_nightly', () {
      expect(migration141, contains('db_maintenance_nightly'));
      for (final oldJob in [
        'cron_call_log_cleanup_daily',
        'usage_counters_retention_daily',
        'jrd_retention_daily',
        'client_errors_retention_daily',
        'jrd_vacuum_daily',
        'client_errors_vacuum_daily',
      ]) {
        expect(migration141, contains("cron.unschedule('$oldJob')"));
      }
    });

    test('migration 141 consolidates ops alerts into ops_alerts_30min at 30min cadence', () {
      expect(migration141, contains("'ops_alerts_30min'"));
      expect(migration141, contains("'*/30 * * * *'"));
      for (final oldJob in [
        'alert_edge_function_health',
        'alert_client_errors_spike',
        'alert_cron_failures',
      ]) {
        expect(migration141, contains("cron.unschedule('$oldJob')"));
      }
    });

    test('migration 141 moves proactive_pr_detection to hourly via alter_job', () {
      expect(migration141, contains('cron.alter_job'));
      expect(migration141, contains("jobname = 'proactive_pr_detection'"));
      expect(migration141, contains("schedule := '0 * * * *'"));
    });

    test('CRON_REGISTRY.md lists the new consolidated jobs as active', () {
      expect(registry, contains('`db_maintenance_nightly`'));
      expect(registry, contains('`ops_alerts_30min`'));
    });

    test('CRON_REGISTRY.md moves all 8 consolidated jobs to Deprecated', () {
      final deprecatedSection = registry.split('## Deprecated / unscheduled')[1];
      for (final oldJob in [
        'cron_call_log_cleanup_daily',
        'usage_counters_retention_daily',
        'jrd_retention_daily',
        'client_errors_retention_daily',
        'jrd_vacuum_daily',
        'client_errors_vacuum_daily',
        'alert_edge_function_health',
        'alert_client_errors_spike',
      ]) {
        expect(
          deprecatedSection,
          contains('`$oldJob`'),
          reason: '$oldJob should be listed in the Deprecated section',
        );
      }
    });
  });
}
