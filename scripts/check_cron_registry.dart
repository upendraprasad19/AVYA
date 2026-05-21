// scripts/check_cron_registry.dart
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
// This gate enforces parity:
//   - registry exists
//   - every `cron.schedule('NAME',...)` in migrations has a `NAME` mention
//     in the registry
//
// Exit 0 = pass.
// Exit 1 = fail.

import 'dart:io';

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final registry = File('docs/operations/CRON_REGISTRY.md');
  if (!registry.existsSync()) {
    stderr.writeln('[Gate 31] FAIL: docs/operations/CRON_REGISTRY.md missing');
    stderr.writeln('  Spec: central registry of every active pg_cron job + owner + vault deps.');
    exit(warnOnly ? 0 : 1);
  }
  final registryContent = registry.readAsStringSync();

  final migrationsDir = Directory('supabase/migrations');
  if (!migrationsDir.existsSync()) {
    stdout.writeln('[Gate 31] SKIP: supabase/migrations not present.');
    exit(0);
  }

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
  final activeJobs = <String>{};
  for (final j in scheduledOrder) {
    if (!unscheduled.contains(j)) activeJobs.add(j);
  }

  final missing = activeJobs.where((j) => !registryContent.contains(j)).toList();
  final tag = warnOnly ? '[Gate 31 WARN]' : '[Gate 31]';
  if (missing.isEmpty) {
    stdout.writeln('$tag PASS: ${activeJobs.length} active cron job(s) all in registry.');
    exit(0);
  }
  stderr.writeln('$tag FAIL: ${missing.length} job(s) not registered:');
  for (final m in missing) {
    stderr.writeln('  - $m');
  }
  exit(warnOnly ? 0 : 1);
}
