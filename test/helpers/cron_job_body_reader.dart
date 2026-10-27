// Reads the LIVE-AUTHORITATIVE command body of a pg_cron job from the
// migrations tree: the latest numbered migration that `cron.schedule`s the
// job, or `cron.alter_job`s it by jobname, under any dollar-quote tag.
//
// Used by the alert contract tests (b4c8e2 / f7a3d2). Extracted so both read
// the job the same way — a `$$`-only or schedule-only reader goes stale
// silently the day someone re-defines the job another way (145 R2 P3-7).
import 'dart:io';

import 'package:test/test.dart';

/// Known limit: a `--` inside a string literal or dollar-quoted body is also
/// cut. No migration defining an alert job has one (145 R3 P3-5).
String stripSqlLineComments(String sql) => sql
    .split('\n')
    .map((l) {
      final i = l.indexOf('--');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

List<File> numberedMigrations() {
  final re = RegExp(r'^(\d{3})[a-z]?_.*\.sql$');
  return Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => re.hasMatch(f.uri.pathSegments.last))
      .toList()
    ..sort((a, b) =>
        a.uri.pathSegments.last.compareTo(b.uri.pathSegments.last));
}

typedef CronJobBody = ({String cadence, String body, String file});

/// The latest definition of [job]. Throws a [TestFailure] if no migration
/// schedules it, or if a migration mentions it next to a cron change this
/// reader cannot parse: an unschedule (a retirement must not leave a test
/// asserting a body that no longer runs), or a direct `UPDATE cron.job`
/// (146 R1 P3-4). Also throws if ANY migration calls alter_job with a literal
/// numeric id, whether or not it names the job, because the reader cannot tell
/// which job that was (0 such migrations exist). Known limits: a file that
/// never names the job and changes it through a computed id is not detected,
/// e.g. `UPDATE cron.job … WHERE jobid = <n>` or a loop-variable
/// `alter_job(r.jobid, command := …)` (107's shape, which predates every
/// alert job).
CronJobBody latestCronJobBody(String job) {
  final schedule = RegExp(
      "cron\\.schedule\\(\\s*'$job'\\s*,\\s*'([^']*)'\\s*,\\s*"
      r'\$([A-Za-z_]*)\$(.*?)\$\2\$',
      dotAll: true);
  final alter = RegExp(
      "cron\\.alter_job\\([^;]*?jobname\\s*=\\s*'$job'[^;]*?command\\s*:=\\s*"
      r'\$([A-Za-z_]*)\$(.*?)\$\1\$',
      dotAll: true);
  CronJobBody? latest;
  // A numeric-id alter_job names no job, so the reader cannot tell whose body
  // it replaced — fail loudly for every reader rather than guess (0 today).
  final numericAlter = RegExp(r'alter_job\(\s*(job_id\s*(:=|=>)\s*)?[0-9]');
  for (final f in numberedMigrations()) {
    final src = stripSqlLineComments(f.readAsStringSync());
    if (numericAlter.hasMatch(src)) {
      throw TestFailure('${f.path} alters a cron job by NUMERIC id — alter it '
          'by jobname subquery so alert contract tests can follow it');
    }
    final s = schedule.firstMatch(src);
    final a = alter.firstMatch(src);
    if (s != null) {
      latest = (cadence: s.group(1)!, body: s.group(3)!, file: f.path);
    } else if (a != null) {
      latest = (cadence: latest?.cadence ?? '', body: a.group(2)!, file: f.path);
    } else if (src.contains(job) &&
        RegExp(r'cron\.(un)?schedule|cron\.alter_job|UPDATE\s+cron\.job\b',
                caseSensitive: false)
            .hasMatch(src)) {
      throw TestFailure(
          '${f.path} mentions $job next to a cron call this reader cannot '
          'parse — extend it rather than reading a stale body');
    }
  }
  if (latest == null) throw TestFailure('no migration schedules $job');
  return latest;
}

/// Whitespace-normalised copy, so assertions do not depend on SQL layout.
String normSql(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// The value of `key:` inside the `  <entry>:` block of alerts/_thresholds.yaml,
/// with a clear failure naming the key when it is missing (145 R3 P3-6).
String thresholdsField(String entry, String key) {
  final yaml = File('alerts/_thresholds.yaml').readAsStringSync();
  expect(yaml, contains('  $entry:'),
      reason: 'alerts/_thresholds.yaml has no $entry entry');
  final block = yaml.split('  $entry:').last.split('\n\n').first;
  final m = RegExp('^\\s+$key:\\s*"?([^"#\\n]+?)"?\\s*(#.*)?\$', multiLine: true)
      .firstMatch(block);
  expect(m, isNotNull, reason: 'yaml $entry.$key missing');
  return m!.group(1)!.trim();
}
