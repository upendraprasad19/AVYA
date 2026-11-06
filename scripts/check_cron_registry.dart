// scripts/check_cron_registry.dart
//
// Gate: 31
//
// Gate 31 (Tech-debt audit 2026-05-20, finding I5): assert that every
// `cron.schedule(...)` call in `supabase/migrations/*.sql` is also recorded
// in `docs/operations/CRON_REGISTRY.md`.
//
// The audit finding: 16+ cron jobs defined inline across 9-10 migration
// files. No single doc lists active jobs, owner, expected cadence, expected
// output. `morning_alert_deliver_early` (jobid 17) silently broke (401)
// and was discovered only by accident.
//
// This gate enforces parity from TWO independent inputs. The second exists
// because the first has a structural blind spot that cost five days of
// undocumented destructive cron on prod (OI-132):
//
//   A. every `cron.schedule('NAME',...)` in `supabase/migrations/*.sql` has a
//      `NAME` mention in the registry;
//   B. every jobname in `backups/live_cron_jobs.json` has a `NAME` mention in
//      the registry.
//
// WHY B IS NOT REDUNDANT. Input A is the migration FILES. On 2026-08-15 a
// migration named `log_table_retention` ran on prod and left no .sql file at
// all — so its four `cron.schedule` calls were not merely un-gated, they were
// UNSEEABLE, and this gate reported green while two row-destructive jobs ran
// daily. A missing file does not skip the gate; it defeats it by construction,
// and no amount of tightening the scan fixes that, because the scan's input is
// the thing that is absent. Measured that day: 28 live jobs, 24 registered,
// 4 missing — Gate 31's blind spot was 100% of the gap.
//
// WHY A SNAPSHOT AND NOT A LIVE QUERY. CI has no Supabase credentials (OI-105 —
// the repo has zero Actions secrets), so a live query would silently skip
// there: a gate that passes because it never ran, which is the failure this
// gate is being hardened against, reintroduced one layer up. A committed
// snapshot runs identically everywhere. Same precedent as
// `backups/live_schema_columns.json`.
//
// REGENERATE THE SNAPSHOT in the same commit as any migration that schedules or
// unschedules a job:
//   select jobid, jobname, schedule, active from cron.job order by jobname;
// A stale snapshot is a KNOWN limitation, stated rather than hidden: this gate
// proves registry-vs-snapshot parity, not snapshot-vs-live freshness. Nothing
// in CI can prove the latter without credentials.
//
// Exit 0 = pass.
// Exit 1 = fail.

import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final tag = warnOnly ? '[Gate 31 WARN]' : '[Gate 31]';

  final registry = File('docs/operations/CRON_REGISTRY.md');
  if (!registry.existsSync()) {
    stderr.writeln('$tag FAIL: docs/operations/CRON_REGISTRY.md missing');
    stderr.writeln('  Spec: central registry of every active pg_cron job + owner + vault deps.');
    exit(warnOnly ? 0 : 1);
  }
  final registryContent = registry.readAsStringSync();

  // ---- Input B, read FIRST -----------------------------------------------
  // Ordering is load-bearing, not stylistic. Input A's own
  // "supabase/migrations absent -> SKIP, exit 0" used to sit above this read,
  // so a tree without that directory exited green having consulted NEITHER
  // input — the same never-ran-so-it-passed shape input B exists to close,
  // reintroduced by the very edit that added it. Input B is the only input
  // that can see a migration applied without a file, so nothing may exit
  // before it has been read.
  final snapshotJobs = _readSnapshot(tag, warnOnly);

  // ---- Input A: the migration files --------------------------------------
  final migrationsDir = Directory('supabase/migrations');
  final activeJobs = <String>{};
  if (!migrationsDir.existsSync()) {
    stdout.writeln('$tag NOTE: supabase/migrations not present — input A '
        '(migration scan) has nothing to read; input B (live snapshot) is '
        'still enforced below.');
  } else {
    final schedulePattern = RegExp(r"""cron\.schedule\s*\(\s*['"]([^'"]+)['"]""");
    final unschedulePattern = RegExp(r"""cron\.unschedule\s*\(\s*['"]([^'"]+)['"]""");
    // Track active jobs: scheduled - unscheduled (last-wins).
    final scheduledOrder = <String>[];
    final unscheduled = <String>{};

    for (final entity in migrationsDir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.sql')) continue;
      final content = entity.readAsStringSync();
      for (final m in schedulePattern.allMatches(content)) {
        scheduledOrder.add(m.group(1)!);
      }
      for (final m in unschedulePattern.allMatches(content)) {
        unscheduled.add(m.group(1)!);
      }
    }
    // De-dupe but keep order of first appearance.
    for (final j in scheduledOrder) {
      if (!unscheduled.contains(j)) activeJobs.add(j);
    }
  }

  final missingFromMigrations =
      activeJobs.where((j) => !registryContent.contains(j)).toList();
  final missingFromSnapshot =
      snapshotJobs.where((j) => !registryContent.contains(j)).toList()..sort();

  if (missingFromMigrations.isEmpty && missingFromSnapshot.isEmpty) {
    stdout.writeln('$tag PASS: ${activeJobs.length} job(s) from migrations and '
        '${snapshotJobs.length} from the live snapshot are all in the registry.');
    exit(0);
  }

  // Count the UNION, not the sum: a job that is both declared in a migration
  // and live in the snapshot is one unregistered job, not two.
  final distinct = <String>{...missingFromMigrations, ...missingFromSnapshot};
  stderr.writeln('$tag FAIL: ${distinct.length} unregistered job(s).');
  for (final m in missingFromMigrations) {
    stderr.writeln('  - $m  (declared in a migration file)');
  }
  for (final m in missingFromSnapshot) {
    stderr.writeln('  - $m  (LIVE on the project but absent from the registry — '
        'if it is also absent from every migration file, its migration was '
        'applied without one: see OI-132)');
  }
  exit(warnOnly ? 0 : 1);
}

/// Reads `backups/live_cron_jobs.json` — input B.
///
/// Every failure here is a HARD failure under the normal (non-warn-only)
/// invocation: missing, unparseable, or parsed-but-empty. Failing open on any
/// of them would restore the exact hole this input closes — a gate reporting
/// green because one of its two inputs quietly vanished. Under `--warn-only`
/// (the in-branch debugging flag) it reports and returns an empty set so the
/// rest of the gate still runs, rather than exiting 0 mid-way and skipping
/// input A as well.
Set<String> _readSnapshot(String tag, bool warnOnly) {
  final snapshotFile = File('backups/live_cron_jobs.json');
  if (!snapshotFile.existsSync()) {
    stderr.writeln('$tag FAIL: backups/live_cron_jobs.json missing.');
    stderr.writeln('  It is the ONLY input that can see a migration applied without a file.');
    stderr.writeln('  Regenerate: select jobid, jobname, schedule, active from cron.job order by jobname;');
    if (!warnOnly) exit(1);
    return <String>{};
  }
  final jobs = <String>{};
  try {
    final decoded = jsonDecode(snapshotFile.readAsStringSync());
    final list = (decoded as Map<String, dynamic>)['jobs'] as List<dynamic>;
    for (final j in list) {
      final name = (j as Map<String, dynamic>)['jobname'] as String?;
      if (name != null && name.isNotEmpty) jobs.add(name);
    }
  } catch (e) {
    stderr.writeln('$tag FAIL: backups/live_cron_jobs.json unreadable: $e');
    if (!warnOnly) exit(1);
    return <String>{};
  }
  if (jobs.isEmpty) {
    // An empty snapshot would make every snapshot assertion vacuous — the
    // Gate-44 shape. Refuse it rather than reporting a green built on nothing.
    stderr.writeln('$tag FAIL: snapshot parsed but contains zero jobs.');
    stderr.writeln('  A vacuous snapshot would make this gate pass by checking nothing.');
    if (!warnOnly) exit(1);
  }
  return jobs;
}
