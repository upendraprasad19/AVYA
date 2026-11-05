import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/cron_call_log_windows.dart';
import '../helpers/cron_job_body_reader.dart';
import '../helpers/migration_cap_reader.dart';

/// OI-179 (diagnose c9e2a7): `alert_cron_function_dead` asked `cron_call_log`
/// for 8 days of silence while `cleanup_cron_call_log()` pruned it at 7, so the
/// alert was unsatisfiable by construction and fired 0 times since creation.
///
/// The CLASS this pins: an alert that reads a pruned table needs
/// `threshold < min(its own lookback, the table's retention)`. A lookback
/// LARGER than retention is benign (a cap); a threshold at or above either bound
/// is not. The pure readers live in `test/helpers/cron_call_log_windows.dart`
/// so the mutation cases below can feed them fixture SQL.
void main() {
  late final double retentionDays;

  setUpAll(() {
    final file = latestMigrationDefining('cleanup_cron_call_log');
    expect(file, isNotNull, reason: 'no migration defines cleanup_cron_call_log');
    final r = readRetentionDays(file!.readAsStringSync());
    expect(r, isNotNull,
        reason: '${file.path}: cannot read the retention interval');
    retentionDays = r!;
  });

  group('live definitions', () {
    test('retention is read from the LAST definition (169: 10 days)', () {
      expect(retentionDays, 10.0);
    });

    test('alert_cron_function_dead: lookback 14 d, threshold 8 d, satisfiable',
        () {
      final w = extractCronCallLogWindows(
          latestCronJobBody('alert_cron_function_dead').body);
      expect(w.lookbackDays, [14.0], reason: 'non-vacuity: exact lookback');
      expect(w.thresholdDays, [8.0], reason: 'non-vacuity: exact threshold');
      expect(violations(w, retentionDays), isEmpty);
    });

    test('alert_cron_silence: thresholds 2 h and 6 h, no lookback', () {
      // latestCronJobBody cannot follow this job: migration 110 names it inside
      // a string literal beside ANOTHER job's schedule, which that reader
      // refuses to guess about. 109 is its only definition (no alter_job).
      final src = stripSqlLineComments(
          File('supabase/migrations/109_cron_silence_alert_and_log_cleanup.sql')
              .readAsStringSync());
      final body = RegExp(r"cron\.schedule\(\s*'alert_cron_silence'.*?\$job\$(.*?)\$job\$",
              dotAll: true)
          .firstMatch(src);
      expect(body, isNotNull, reason: '109 must schedule alert_cron_silence');
      final w = extractCronCallLogWindows(body!.group(1)!);
      expect(w.lookbackDays, isEmpty);
      expect(w.thresholdDays..sort(), [2 / 24.0, 6 / 24.0]);
      expect(violations(w, retentionDays), isEmpty);
    });

    test('ops_alerts_30min: cron_call_log lookbacks are 30 min, 1 h, 6 h only',
        () {
      final w = extractCronCallLogWindows(
          latestCronJobBody('ops_alerts_30min').body);
      final set = w.lookbackDays
          .map((d) => (d * 1440).round())
          .toSet(); // minutes
      expect(set, {30, 60, 360},
          reason: 'the 24 h / 1 h dedup intervals on public.alerts must NOT be '
              'counted; only intervals inside a cron_call_log sub-select are');
      expect(violations(w, retentionDays), isEmpty);
    });

    test('the PRE-FIX state (7-day retention) is a violation: regression pin',
        () {
      final w = extractCronCallLogWindows(
          latestCronJobBody('alert_cron_function_dead').body);
      expect(violations(w, 7.0), isNotEmpty,
          reason: 'threshold 8 d >= retention 7 d is the OI-179 defect');
    });
  });

  group('tripwire: a new alert that reads cron_call_log', () {
    test('every migration with an alert body that reads cron_call_log is known',
        () {
      // The live pins above cover the jobs named in them. A NEW alert (or a
      // rewrite of one) that reads the pruned table would otherwise be
      // checked by nothing: a threshold spelled `age_days >= 8` yields an empty
      // list and a silent green (B-pass finding 3a). This list is the tripwire:
      // when it fails, a migration now defines an alert reading cron_call_log;
      // read its threshold against retention, add the job to the live pins
      // above, THEN add the file here.
      final found = <String>[];
      for (final f in numberedMigrations()) {
        final src = stripSqlLineComments(f.readAsStringSync());
        if (RegExp(r'FROM\s+public\.cron_call_log\b', caseSensitive: false)
                .hasMatch(src) &&
            RegExp(r'INTO\s+public\.alerts\b', caseSensitive: false)
                .hasMatch(src)) {
          found.add(f.uri.pathSegments.last);
        }
      }
      expect(found, [
        '076_alert_detection_crons.sql',
        '077_fix_alert_edge_function_health_columns.sql',
        '109_cron_silence_alert_and_log_cleanup.sql',
        '110_cron_silence_per_function_and_cleanup_null_guard.sql',
        '139_alert_cron_failures.sql',
        '140_hermes_pass_fixes_138_139.sql',
        '141_disk_io_audit_cleanup_batch.sql',
        '143_restore_alert_cron_failures_stuck_job_bound.sql',
        '144_split_vacuum_out_of_db_maintenance_nightly.sql',
        '147_alert_client_errors_spike_breadth.sql',
      ]);
    });
  });

  group('violations()', () {
    CronCallLogWindows win(List<double> l, List<double> t) =>
        (lookbackDays: l, thresholdDays: t);

    test('threshold above retention is a violation', () {
      expect(violations(win([14], [30]), 10), isNotEmpty);
    });

    test('threshold EQUAL to retention is a violation (strict <)', () {
      expect(violations(win([14], [10]), 10), isNotEmpty);
    });

    test('threshold at or above its own lookback is a violation', () {
      expect(violations(win([6], [8]), 10), isNotEmpty);
    });

    test('threshold EQUAL to its own lookback is a violation (strict <)', () {
      // age >= 8 against a window holding only rows younger than 8 days can
      // never match (B-pass finding 2: the `>=` -> `>` mutant survived).
      expect(violations(win([8], [8]), 10), isNotEmpty);
    });

    test('a lookback larger than retention is benign', () {
      expect(violations(win([14], [8]), 10), isEmpty);
    });
  });

  group('extractCronCallLogWindows() fixtures', () {
    test('a dedup interval on public.alerts is not a lookback', () {
      final w = extractCronCallLogWindows('''
        SELECT 1 FROM (
          SELECT MAX(started_at) FROM public.cron_call_log
          WHERE started_at > now() - interval '14 days'
        ) d WHERE d.days_silent >= 8
          AND NOT EXISTS (SELECT 1 FROM public.alerts a
            WHERE a.detected_at > now() - interval '24 hours');''');
      expect(w.lookbackDays, [14.0]);
    });

    test('a sub-select ending in `) c` (no GROUP BY) is still bounded', () {
      final w = extractCronCallLogWindows('''
        FROM (SELECT COUNT(*) FROM public.cron_call_log
              WHERE started_at >= now() - interval '1 hour') c
        WHERE c.cnt >= 1 AND x > now() - interval '9 days';''');
      expect(w.lookbackDays, [1 / 24.0],
          reason: 'the 9 d interval sits after the closing paren');
    });

    test('a paren inside a string literal does not end the sub-select', () {
      final w = extractCronCallLogWindows('''
        FROM (SELECT 'a ) b' AS x, COUNT(*) FROM public.cron_call_log
              WHERE msg = 'it''s ) odd' AND started_at > now() - interval '3 days'
              AND y > now() - interval '5 days') c;''');
      expect(w.lookbackDays, [3.0, 5.0],
          reason: 'a `)` inside a quoted literal must not close the scan');
    });

    test('a commented-out interval is ignored', () {
      final w = extractCronCallLogWindows('''
        SELECT 1 FROM public.cron_call_log
        -- WHERE started_at > now() - interval '99 days'
        WHERE started_at > now() - interval '2 days';''');
      expect(w.lookbackDays, [2.0]);
    });
  });

  group('readRetentionDays() fixtures', () {
    const live = r'''
      CREATE OR REPLACE FUNCTION public.cleanup_cron_call_log()
      RETURNS void LANGUAGE sql AS $fn$
        -- was: WHERE started_at < now() - interval '7 days' (kept for history)
        DELETE FROM public.cron_call_log
        WHERE started_at < now() - interval '10 days';
      $fn$;
      -- Rollback: ... WHERE started_at < now() - interval '3 days';
    ''';

    test('a history comment INSIDE the body, above the live statement, is not read', () {
      expect(readRetentionDays(live), 10.0);
    });

    test('an unparseable body returns null, never a guess', () {
      expect(readRetentionDays('SELECT 1;'), isNull);
    });
  });

  group('latestMigrationDefining() picks the highest number', () {
    test('a newer, smaller-interval redefinition wins', () {
      final dir = Directory.systemTemp.createTempSync('oi179_mig_');
      addTearDown(() => dir.deleteSync(recursive: true));
      String body(int days) => '''
        CREATE OR REPLACE FUNCTION public.cleanup_cron_call_log()
        RETURNS void LANGUAGE sql AS \$fn\$
          DELETE FROM public.cron_call_log
          WHERE started_at < now() - interval '$days days';
        \$fn\$;''';
      File('${dir.path}/100_a.sql').writeAsStringSync(body(21));
      File('${dir.path}/200_b.sql').writeAsStringSync(body(3));
      final f = latestMigrationDefining('cleanup_cron_call_log',
          migrationsDir: dir.path);
      expect(readRetentionDays(f!.readAsStringSync()), 3.0);
    });
  });
}
