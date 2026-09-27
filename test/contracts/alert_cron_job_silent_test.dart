// Contract for migration 146 — alert_cron_job_silent (OI-178 second half,
// diagnose f7a3d2).
//
// 145 sees a pg_cron job that ran and FAILED. A job that is deactivated
// (cron.job.active = false) or that pg_cron stops launching writes no run row
// at all, so before 146 nothing could see it. On 2026-09-21 two hourly alert
// jobs were not launched for 5 h (DB saturation, e8b4a1) and nothing said so.
//
// Source-level, like its sibling alert_sql_job_failures_test: the job body is
// SQL run by pg_cron, with no Dart runtime path, and CI has no Supabase
// credentials. Each assertion pins one design decision; the behavioural
// evidence is the live replay in the diagnose doc (2 flags over all retained
// history, both real).
import 'package:test/test.dart';

import '../helpers/cron_job_body_reader.dart';

const _job = 'alert_cron_job_silent';

void main() {
  late CronJobBody job;
  late String body;
  setUpAll(() {
    job = latestCronJobBody(_job);
    body = normSql(job.body);
  });

  group('f7a3d2 — alert_cron_job_silent (OI-178)', () {
    test('is ONE statement (pg_cron runs a command as one transaction, d6b2f9)',
        () {
      final statements = body
          .replaceAll(RegExp(r"'(?:[^']|'')*'"), "''")
          .split(';')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty);
      expect(statements, hasLength(1));
    });

    test('emits ONE aggregated alert per run, not one per job', () {
      expect(body, contains('HAVING count(*) > 0'));
      expect(body, isNot(contains('GROUP BY')));
    });

    test('a deactivated job is INACTIVE (warn); the kill switch writes no run row',
        () {
      // End-anchored on the UNION ALL: a prefix match let `WHERE NOT j.active
      // AND false` (a dead warn path) stay green (R2 P3-2).
      expect(
          body,
          contains("'inactive' AS kind, 'active=false' AS why FROM cron.job j "
              "WHERE NOT j.active UNION ALL SELECT e.jobkey, 'silent',"));
      expect(
          body,
          contains("CASE WHEN count(*) FILTER (WHERE s.kind = 'silent') > 0 "
              "THEN 'critical' ELSE 'warn' END"));
    });

    test('silence is judged against the SCHEDULE, not run history — retention '
        'keeps only each job\'s newest run past 14 d', () {
      expect(body,
          contains('(SELECT max(d.start_time) FROM cron.job_run_details d WHERE d.jobid = j.jobid)'));
      // Shapes no fixed gap bounds are not judged, and come BEFORE the month
      // arm (R2 P3-1): pg_cron ANDs the day fields when either starts with *.
      expect(
          body,
          contains("WHEN p.f[3] <> '*' AND p.f[5] <> '*' AND (p.f[3] LIKE '*%' "
              "OR p.f[5] LIKE '*%') THEN NULL "
              "WHEN p.f[4] <> '*' AND p.f[3] ~ '(29|30|31)' THEN NULL "
              "WHEN p.f[4] <> '*' THEN interval '366 days'"));
      // ORDER is the contract: each branch must give a gap >= reality for
      // every schedule it catches (R1 P1: month first — a yearly or
      // quarterly job under a 31 d guess false-pages at ~39 d).
      expect(
          body,
          contains("WHEN p.f[4] <> '*' THEN interval '366 days' "
              "WHEN p.f[5] <> '*' THEN interval '7 days' "
              "WHEN p.f[3] <> '*' THEN interval '62 days' "
              "WHEN p.f[2] <> '*' THEN interval '1 day'"));
      expect(
          body,
          contains("WHEN p.f[1] ~ '^[*]/[0-9]+\$' THEN make_interval(mins => "
              'substring(p.f[1] from 3)::int)'));
      expect(body, contains("ELSE interval '1 hour'"));
      expect(body,
          contains('WHEN coalesce(array_length(p.f, 1), 0) <> 5 THEN NULL'),
          reason: 'an unrecognised schedule shape must not be judged at all');
      expect(body, contains("WHEN trim(j.schedule) = '@weekly' THEN interval '7 days'"));
    });

    test('SILENT = active, launched at least once, and overdue by '
        'expected x 1.25 + 1 h (a failed launch still counts as a launch)', () {
      expect(body, contains('WHERE j.active'));
      expect(body, contains('e.expected IS NOT NULL'));
      expect(body, contains('e.last_start IS NOT NULL'));
      expect(body, contains("coalesce(e.last_status, '?')"),
          reason: "a job still RUNNING past its threshold must read as "
              "'running', not as not-launched (R1 P3-5)");
      expect(
          body,
          contains('ORDER BY d.start_time DESC NULLS LAST, d.runid DESC LIMIT 1) '
              'AS last_status'),
          reason: 'the status shown must be the NEWEST run\'s (R2 P3-2 M4)');
      expect(body,
          contains("now() - e.last_start > e.expected * 1.25 + interval '1 hour'"));
      expect(body, isNot(contains("status = 'succeeded'")),
          reason: 'filtering on succeeded would page for a FAILING job, which '
              'is 145\'s alert, not this one');
    });

    test('dedup: critical by the SILENT job set within 23 h (unacknowledged); '
        'warn by the INACTIVE job set within 7 d (acknowledged or not)', () {
      expect(body, contains('WHERE NOT EXISTS ( SELECT 1 FROM public.alerts x'));
      expect(body, contains("x.source = 'alert_cron_job_silent'"));
      expect(body, contains('x.severity = a.severity'));
      expect(
          body,
          contains("(a.severity = 'critical' AND x.acknowledged = false "
              "AND x.detected_at > now() - interval '23 hours' "
              "AND x.context_json -> 'silent_jobs' @> a.silent_jobs)"));
      expect(
          body,
          contains("(a.severity = 'warn' AND x.detected_at > now() - interval '7 days' "
              "AND x.context_json -> 'inactive_jobs' @> a.inactive_jobs)"));
      // The OR ITSELF, not just each branch's existence, is part of the
      // contract: each branch above is still a literal substring of the body
      // even if OR became AND, which would make `x.severity = a.severity AND
      // (critical-branch AND warn-branch)` unsatisfiable for any row (a row
      // cannot be both severities) — NOT EXISTS would always be true and
      // dedup would be disabled for BOTH severities (B-pass P1).
      expect(
          body,
          contains("AND x.context_json -> 'silent_jobs' @> a.silent_jobs) "
              "OR (a.severity = 'warn'"));
      expect(body, contains("'silent_jobs', a.silent_jobs"));
      expect(body, contains("'inactive_jobs', a.inactive_jobs"));
      // What the aggregates PUT in those keys is part of the dedup contract:
      // filtering silent_jobs on the wrong kind makes it NULL, `@> NULL` is
      // NULL, NOT EXISTS is always true, and every :33 pages (R2 P3-2 M3).
      expect(
          body,
          contains("jsonb_agg(DISTINCT s.jobkey) FILTER (WHERE s.kind = 'silent') "
              'AS silent_jobs'));
      expect(
          body,
          contains("jsonb_agg(DISTINCT s.jobkey) FILTER (WHERE s.kind = 'inactive') "
              'AS inactive_jobs'));
    });

    test('alerts/_thresholds.yaml entry agrees with the SQL it documents', () {
      String field(String k) => thresholdsField('cron_job_silent', k);
      expect(field('defined_in_migration'), job.file.split('/').last);
      expect(field('cron_cadence'), job.cadence);
      expect(field('overdue_factor'), '1.25');
      expect(body, contains('e.expected * ${field('overdue_factor')} + '
          "interval '${field('overdue_grace_hours')} hour'"));
      expect(body,
          contains("interval '${field('critical_dedup_window_hours')} hours'"));
      expect(body,
          contains("interval '${field('warn_dedup_window_days')} days'"));
    });
  });
}
