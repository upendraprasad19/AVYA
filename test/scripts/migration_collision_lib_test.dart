// test/scripts/migration_collision_lib_test.dart
//
// Pure unit tests for scripts/migration_collision_lib.dart (OI-255): the
// bare-prefix collision detector Gate 14 now runs before its existing
// "unapplied" check, which cannot see this class at all (`a.startsWith(prefix)`
// is satisfied by EITHER colliding file's applied-snapshot entry).
//
// Mutation proof (rule 21): neutering `findMigrationPrefixCollisions` to
// always return `{}` reddens the "a real NEW collision is detected" test
// below; neutering the grandfather exclusion (removing the
// `!grandfathered.contains(...)` clause) reddens the "known 145/146
// grandfathered pairs are NOT re-flagged" test. Both were run by hand before
// this file was committed — see the diagnose-doc for the exact counts.

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/migration_collision_lib.dart';

void main() {
  group('findMigrationPrefixCollisions', () {
    test('no collision when every prefix is unique', () {
      final result = findMigrationPrefixCollisions([
        '100_rls_initplan_select_wrap.sql',
        '101_admin_dashboard_metrics_functions.sql',
        '147_alert_client_errors_spike_breadth.sql',
      ]);
      expect(result, isEmpty);
    });

    test('a single file never collides with itself', () {
      final result =
          findMigrationPrefixCollisions(['147_alert_client_errors_spike_breadth.sql']);
      expect(result, isEmpty);
    });

    test('THE OI-255 SCENARIO: two files sharing an un-grandfathered prefix '
        'are flagged, naming both', () {
      final result = findMigrationPrefixCollisions([
        '148_coach_extraction_locked_fields.sql',
        '148_alert_sql_job_failures_v2.sql',
        '149_unrelated_unique.sql',
      ]);
      expect(result.keys, {'148'});
      expect(
        result['148'],
        {
          '148_alert_sql_job_failures_v2.sql',
          '148_coach_extraction_locked_fields.sql',
        }.toList()..sort(),
        reason: 'both colliding filenames must be named so the reader knows '
            'which two files to reconcile, not just that a collision exists',
      );
    });

    test('the known 145/146 grandfathered pairs are NOT re-flagged (both '
        'pairs are already live and immutable per OI-255)', () {
      final result = findMigrationPrefixCollisions([
        '145_alert_sql_job_failures.sql',
        '145_workout_templates_stable_delete.sql',
        '146_alert_cron_job_silent.sql',
        '146_workout_templates_delete_trigger_insert_path.sql',
        '147_alert_client_errors_spike_breadth.sql',
      ]);
      expect(result, isEmpty,
          reason: 'these four files are permanently immutable once applied — '
              'grandfathering them is the only option, not a bug');
    });

    test('a grandfathered prefix collision is still visible to an explicit '
        'narrower grandfathered set (the override parameter genuinely '
        'narrows, it does not silently widen)', () {
      final result = findMigrationPrefixCollisions(
        [
          '145_alert_sql_job_failures.sql',
          '145_workout_templates_stable_delete.sql',
        ],
        grandfathered: <String>{}, // deliberately empty override
      );
      expect(result.keys, {'145'},
          reason: 'passing an explicit empty grandfather set must not '
              'silently fall back to the default constant');
    });

    test('three files sharing one prefix are all named, not just two', () {
      final result = findMigrationPrefixCollisions([
        '150_a.sql',
        '150_b.sql',
        '150_c.sql',
      ]);
      expect(result['150']!.length, 3);
    });

    test('a prefix with a letter suffix does not collide with the bare '
        'numeric prefix (letter suffixes are a deliberate disambiguation '
        'scheme, not a mistake to flag)', () {
      final result = findMigrationPrefixCollisions([
        '145_alert_sql_job_failures.sql',
        '145a_disambiguated_variant.sql',
      ]);
      expect(result, isEmpty);
    });
  });
}
