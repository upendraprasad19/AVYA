// scripts/check_usage_counter_source.dart
//
// Blocks a TENTH quota counter being derived from `ai_coach_interactions`.
//
// Context: that table is a conversation LOG that doubles as a usage LEDGER, and
// `rolling-context` prunes it nightly — so every quota derived from its row
// count is resettable (OI-162). Slice 1 introduces `usage_counters` +
// `consume_quota()` as the replacement; the nine existing call sites migrate
// slice by slice. This gate holds the line while that happens.
//
// Ships BEFORE the refactor it protects, per CLAUDE.md §4.11, and starts in
// --warn-only so the baseline is visible before it can block anything.
//
// Usage:
//   dart run scripts/check_usage_counter_source.dart              # hard-fail
//   dart run scripts/check_usage_counter_source.dart --warn-only  # report, exit 0
//   dart run scripts/check_usage_counter_source.dart --list       # show the baseline
//
// Exit codes: 0 clean (or --warn-only / --list), 1 violation.

import 'dart:io';

import 'usage_counter_source_lib.dart';

const _tag = '[usage-counter-source]';

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final listMode = args.contains('--list');

  final root = Directory.current.path;
  final efDir = Directory('$root/supabase/functions');
  final migDir = Directory('$root/supabase/migrations');

  // Fail OPEN when the tree is not where we expect. A gate that cannot see its
  // subject must not block every commit in the repo — the same posture
  // check_worktree_config_integrity.dart takes.
  if (!efDir.existsSync() || !migDir.existsSync()) {
    stdout.writeln(
        '$_tag SKIPPED — supabase/functions or supabase/migrations not found '
        '(cwd=$root). Not treating an unreadable tree as a pass or a failure.');
    exit(0);
  }

  final efSources = <String, String>{};
  for (final e in efDir.listSync()) {
    if (e is! Directory) continue;
    final f = File('${e.path}/index.ts');
    if (!f.existsSync()) continue;
    final rel = 'supabase/functions/${e.uri.pathSegments.where((s) => s.isNotEmpty).last}/index.ts';
    efSources[rel] = f.readAsStringSync();
  }

  final migrationSources = <String, String>{};
  for (final e in migDir.listSync()) {
    if (e is! File || !e.path.endsWith('.sql')) continue;
    final base = e.uri.pathSegments.last;
    // The combined dump is a concatenation of files already covered individually.
    if (base.contains('all_migrations_combined')) continue;
    migrationSources[base] = e.readAsStringSync();
  }

  final result = sweep(
    efSources: efSources,
    migrationSources: migrationSources,
  );

  if (listMode) {
    stdout.writeln('$_tag BASELINE');
    stdout.writeln('  Edge Function quota counters (${result.edgeFunctionSites.length}):');
    for (final s in result.edgeFunctionSites) {
      stdout.writeln('    $s');
    }
    stdout.writeln('  Migrations counting ai_coach_interactions '
        '(${result.offendingMigrations.length}):');
    for (final m in (result.offendingMigrations..sort())) {
      stdout.writeln('    $m');
    }
    exit(0);
  }

  if (result.isClean) {
    stdout.writeln(
        '$_tag PASS — ${result.edgeFunctionSites.length} known EF quota counter(s), '
        '${result.offendingMigrations.length} known migration(s), no new ones.');
    exit(0);
  }

  final label = warnOnly ? 'WARN' : 'FAIL';
  stderr.writeln('$_tag $label — ${result.violations.length} violation(s):');
  for (final v in result.violations) {
    stderr.writeln('  - $v');
  }
  stderr.writeln('');
  stderr.writeln('  A quota must not be derived from a row count on '
      'ai_coach_interactions: rolling-context prunes that table, so the count '
      'resets. Use consume_quota() against usage_counters (OI-162).');
  stderr.writeln('  Baseline: dart run scripts/check_usage_counter_source.dart --list');

  exit(warnOnly ? 0 : 1);
}
