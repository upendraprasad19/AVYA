// Contract for migration 145 — alert_sql_job_failures (OI-178, diagnose b4c8e2).
//
// Before 145 a pure-SQL pg_cron job that failed emitted nothing any alert read:
// alerting read only cron_call_log, which only Edge Functions write, so
// db_maintenance_nightly failed 5/5 nights unseen (d6b2f9).
//
// Source-level, like disk_io_audit_cleanup_batch_test: the job body is SQL run
// by pg_cron, with no Dart runtime path, and CI has no Supabase credentials.
// Each assertion pins one DESIGN DECISION that plan-review R1/R2 derived from
// live data — the behavioural evidence is the 30-day hourly replay recorded in
// the diagnose doc (5 criticals, all real; 4 warns), not this file.
import 'package:test/test.dart';

import '../helpers/cron_job_body_reader.dart';

const _job = 'alert_sql_job_failures';

void main() {
  late CronJobBody job;
  late String body;
  setUpAll(() {
    job = latestCronJobBody(_job);
    body = normSql(job.body);
  });

  group('b4c8e2 — alert_sql_job_failures (OI-178)', () {
    test('reads failed runs from cron.job_run_details (the table SQL jobs write)',
        () {
      expect(body, contains('FROM cron.job_run_details d'));
      expect(body, contains("d.status = 'failed'"));
    });

    test('windows on END time — a row reads failed only once the run ends '
        '(R2 P1-1)', () {
      expect(body,
          contains("coalesce(d.end_time, d.start_time) > now() - interval '65 minutes'"));
      expect(body, isNot(contains('d.start_time >')),
          reason: 'a start_time window missed 9 of 100 failed runs in 30 d');
    });

    test('is ONE statement (pg_cron runs a command as one transaction, d6b2f9)',
        () {
      // Drop '…' literals first (SQL escapes a quote as ''): the
      // suggested_action text legitimately contains a ';'.
      final statements = body
          .replaceAll(RegExp(r"'(?:[^']|'')*'"), "''")
          .split(';')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty);
      expect(statements, hasLength(1));
    });

    test('emits ONE aggregated alert per run, not one per job (R1 P1-2: '
        '14 jobs failed on 2026-09-21)', () {
      expect(body, contains('HAVING count(*) > 0'));
      expect(body, isNot(contains('GROUP BY')),
          reason: 'a GROUP BY would produce one alert row per group');
    });

    test('capacity failures alone are warn; any real error is critical', () {
      expect(
          body,
          contains("~* '(job startup timeout|connection failed|"
              "remaining connection slots|server restarted|could not connect)'"));
      expect(
          body,
          contains("CASE WHEN count(*) FILTER (WHERE NOT f.capacity_failure) > 0 "
              "THEN 'critical' ELSE 'warn' END"));
    });

    test('NULL-safe for since-unscheduled jobids (summary is NOT NULL)', () {
      expect(body, contains('LEFT JOIN cron.job j'));
      expect(body, contains("coalesce(j.jobname, 'jobid ' || d.jobid)"));
      expect(body, contains("coalesce(d.return_message, '')"));
    });

    test('dedup: per severity, 23 h, and a critical only suppressed by an open '
        'alert that already names every failing job (R2 P2-4 / P3-5)', () {
      expect(body, contains('WHERE NOT EXISTS ( SELECT 1 FROM public.alerts x'));
      expect(body, contains("x.source = 'alert_sql_job_failures'"));
      expect(body, contains('x.acknowledged = false'));
      expect(body, contains('x.severity = a.severity'));
      expect(
          body,
          contains("(a.severity = 'warn' OR "
              "x.context_json -> 'sql_jobs' @> a.sql_jobs)"),
          reason: 'containment on the REAL-error job set only — the mixed '
              'jobs set can hide a new real failure and re-page hourly in a '
              'saturation storm (R3 P2-1)');
      expect(
          body,
          contains('jsonb_agg(DISTINCT f.jobkey) FILTER '
              '(WHERE NOT f.capacity_failure) AS sql_jobs'));
      expect(body, contains("x.detected_at > now() - interval '23 hours'"));
      expect(body, contains("'sql_jobs', a.sql_jobs"),
          reason: 'the dedup reads the sql_jobs key this INSERT writes');
    });

    test('alerts/_thresholds.yaml entry agrees with the SQL it documents', () {
      String field(String k) => thresholdsField('sql_job_failures', k);
      expect(field('defined_in_migration'), job.file.split('/').last);
      expect(field('cron_cadence'), job.cadence);
      expect(body,
          contains("interval '${field('window_minutes')} minutes'"));
      expect(body, contains("'window_minutes', ${field('window_minutes')}"));
      expect(body,
          contains("interval '${field('dedup_window_hours')} hours'"));
    });
  });
}
