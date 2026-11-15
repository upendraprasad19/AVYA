// Regression test for diagnose d6b2f9 / OI-247: a pg_cron command that puts
// VACUUM beside any other statement FAILS EVERY RUN, and — because pg_cron runs
// a multi-statement command as ONE transaction — rolls the other statements
// back with it.
//
// Migration 141 folded four `SELECT cleanup_*()` calls and two
// `VACUUM (ANALYZE)` statements into `db_maintenance_nightly`. Live
// `cron.job_run_details` (jobid 41): 5/5 runs failed 2026-09-22 → 09-26 with
// `VACUUM cannot run inside a transaction block`, and the four cleanups had
// not run since 09-21. The same two VACUUMs had succeeded every night
// 09-06 → 09-20 as their own single-statement jobs. Migration 144 restores
// that shape.
//
// This pins the CLASS, not just 144: every dollar-quoted body (`$$` and tagged
// `$job$`-style) in every
// migration is scanned, so a future consolidation that repeats 141's shape
// fails here at commit time instead of on the first nightly run. Migration 141
// is the one enumerated exception (immutable once applied) and is admitted
// only while a LATER migration demonstrably repairs its job.
//
// Scope, stated: this reads migration FILES. It cannot see a job created or
// altered outside a migration (Gate 31 input B covers that for names only).
// Live verification is the post-apply query in 144's own footer.
import 'dart:io';

import 'package:test/test.dart';

/// Migration files, numeric scheme only, in apply order.
List<File> _migrations() {
  final re = RegExp(r'^(\d{3})[a-z]?_.*\.sql$');
  final files = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => re.hasMatch(f.uri.pathSegments.last))
      .toList()
    ..sort((a, b) => a.uri.pathSegments.last.compareTo(b.uri.pathSegments.last));
  return files;
}

/// Removes `--` line comments, so a commented rollback block (which quotes the
/// OLD, broken command on purpose) can never satisfy or trip an assertion.
String _stripLineComments(String sql) => sql
    .split('\n')
    .map((l) {
      final i = l.indexOf('--');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

/// Every dollar-quoted body in the comment-stripped SQL — `$$ … $$` AND
/// tagged `$job$ … $job$` / `$cron$ … $cron$` (the tag must match; plan-review
/// R1 F1: tagged quotes are this repo's MAJORITY style for cron commands —
/// 121, which created these very VACUUM jobs, used `$job$` — and an untagged
/// regex scanned none of them).
List<String> _dollarBodies(String sql) =>
    RegExp(r'\$([A-Za-z_][A-Za-z0-9_]*)?\$(.*?)\$\1\$', dotAll: true)
        .allMatches(_stripLineComments(sql))
        .map((m) => m.group(2)!)
        .toList();

/// Non-empty statements in a command body.
List<String> _statements(String body) => body
    .split(';')
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

bool _hasVacuum(String body) =>
    RegExp(r'\bVACUUM\b', caseSensitive: false).hasMatch(body);

/// Returns "<file>: <n> statements" for every body that mixes VACUUM with any
/// other statement.
List<String> vacuumMixViolations(Map<String, String> filesToSql) {
  final out = <String>[];
  filesToSql.forEach((name, sql) {
    for (final body in _dollarBodies(sql)) {
      if (!_hasVacuum(body)) continue;
      final n = _statements(body).length;
      if (n > 1) out.add('$name: $n statements in a VACUUM command');
    }
  });
  return out;
}

/// Migrations whose VACUUM-mix is admitted because they are applied (hence
/// immutable) AND a later migration repairs the job. Adding a name here needs
/// the same two facts.
const _admitted = {'141_disk_io_audit_cleanup_batch.sql'};

void main() {
  final all = {
    for (final f in _migrations())
      f.uri.pathSegments.last: f.readAsStringSync(),
  };

  group('d6b2f9 — pg_cron VACUUM must run as a single-statement command', () {
    test('the detector sees the real defect in 141 (so the scan is not vacuous)',
        () {
      final v = vacuumMixViolations(
          {'141': all['141_disk_io_audit_cleanup_batch.sql']!});
      expect(v, hasLength(1),
          reason: '141 schedules db_maintenance_nightly with 4 cleanups + '
              '2 VACUUMs — the scan must flag exactly that body');
    });

    test('the detector reads TAGGED dollar quotes (\$job\$), not just \$\$',
        () {
      const tagged = r"SELECT cron.schedule('x', '0 3 * * *', "
          r"$job$ SELECT public.cleanup_client_errors(); "
          r"VACUUM (ANALYZE) public.client_errors; $job$);";
      const taggedSingle = r"SELECT cron.schedule('y', '0 3 * * *', "
          r"$job$ VACUUM (ANALYZE) public.client_errors; $job$);";
      expect(vacuumMixViolations({'synthetic_tagged': tagged}), hasLength(1));
      expect(vacuumMixViolations({'synthetic_single': taggedSingle}), isEmpty,
          reason: '121-style single-statement VACUUM is the CORRECT shape');
    });

    test('no migration outside the admitted set mixes VACUUM with another '
        'statement', () {
      final scanned = Map.of(all)..removeWhere((k, _) => _admitted.contains(k));
      expect(vacuumMixViolations(scanned), isEmpty);
    });

    test('141 is admitted only because 144 repairs db_maintenance_nightly', () {
      final m144 = all.entries
          .firstWhere((e) => e.key.startsWith('144_'),
              orElse: () => throw TestFailure(
                  '141 is admitted on the strength of migration 144, '
                  'which does not exist'))
          .value;
      final active = _stripLineComments(m144);
      expect(active, contains("jobname = 'db_maintenance_nightly'"));
      final cleanupBody = _dollarBodies(m144)
          .firstWhere((b) => b.contains('cleanup_cron_call_log'));
      expect(_hasVacuum(cleanupBody), isFalse,
          reason: 'the repaired db_maintenance_nightly command must hold no '
              'VACUUM');
      expect(_statements(cleanupBody), hasLength(4),
          reason: 'all four cleanups must survive the split');
      for (final job in ['jrd_vacuum_daily', 'client_errors_vacuum_daily']) {
        expect(active, contains("cron.schedule('$job'"),
            reason: '$job must be restored as its own job');
      }
    });

    test('alert_cron_function_dead excludes alert-critical-notify INSIDE its '
        'own cron_call_log subquery (OI-179 R2-11)', () {
      final m144 = all.entries.firstWhere((e) => e.key.startsWith('144_')).value;
      expect(_stripLineComments(m144),
          contains("jobname = 'alert_cron_function_dead'"));
      final alertBody = _dollarBodies(m144)
          .firstWhere((b) => b.contains("'alert_cron_function_dead'"));
      // The span is the LAST `FROM public.cron_call_log` before the GROUP BY
      // (R2 F2: a first-match could be fooled by an earlier CTE naming the
      // same table), and the predicate must be AND-ed (an `OR` would widen,
      // not narrow, the rows the alert reads).
      final groupBy = alertBody.indexOf('GROUP BY function_name');
      expect(groupBy, greaterThan(-1));
      final from = alertBody.lastIndexOf('FROM public.cron_call_log', groupBy);
      expect(from, greaterThan(-1));
      expect(alertBody.substring(from, groupBy),
          contains("AND function_name <> 'alert-critical-notify'"),
          reason: 'the exclusion must filter the success rows the alert '
              'reads, not sit anywhere else in the migration');
    });

    test('every trigger-dispatched function that writes cron_call_log is '
        'excluded from alert_cron_function_dead (R1 F3)', () {
      // The roster is the repo's own list of non-cron-scheduled functions
      // (cron_auth_adoption_test.dart). A function on it that calls
      // logCronStart writes success rows whose silence is HEALTHY — if the
      // alert can see it, a critical about it dispatches it and resets its
      // own clock. A new roster entry therefore fails here until excluded.
      final roster = File('test/contracts/cron_auth_adoption_test.dart')
          .readAsStringSync();
      final block = RegExp(
              r'_triggerDispatchedFunctions = <String>\[(.*?)\];',
              dotAll: true)
          .firstMatch(roster)!
          .group(1)!;
      // Comments stripped first, then EVERY quoted token counted — an entry
      // sharing a line with another must not be silently dropped (R2 F3).
      final code = block
          .split('\n')
          .map((l) => l.contains('//') ? l.substring(0, l.indexOf('//')) : l)
          .join('\n');
      final names = RegExp(r"'([a-z0-9-]+)'")
          .allMatches(code)
          .map((m) => m.group(1)!)
          .toList();
      expect(names, contains('alert-critical-notify'),
          reason: 'roster parse must see the known entry (non-vacuous)');
      final alertBody = _dollarBodies(
              all.entries.firstWhere((e) => e.key.startsWith('144_')).value)
          .firstWhere((b) => b.contains("'alert_cron_function_dead'"));
      for (final fn in names) {
        final src = File('supabase/functions/$fn/index.ts');
        if (!src.existsSync() ||
            !src.readAsStringSync().contains('logCronStart(')) {
          continue;
        }
        expect(alertBody, contains("AND function_name <> '$fn'"),
            reason: '$fn is trigger-dispatched and writes cron_call_log');
      }
    });
  });
}
