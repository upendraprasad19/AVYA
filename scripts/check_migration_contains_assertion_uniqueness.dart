// scripts/check_migration_contains_assertion_uniqueness.dart
//
// WARN-ONLY. Never exits 1. See migration_contains_uniqueness_lib.dart for
// the bug class (feedback_mistake_guard_without_its_mirror.md #22) and the
// deliberate scope (only test files calling `latestMigrationDefining(`).
//
// Unlike every other gate in this batch, this one is a heuristic advisory,
// not a hard block: resolving which migration file a `.contains()` assertion
// is REALLY checking against would require replicating
// test/helpers/migration_cap_reader.dart's own resolution logic exactly, and
// the literal-from-regex extraction is approximate by construction. A false
// positive here has real cost (blocking an unrelated commit on a guess), so
// it only ever prints a warning and exits 0. `--warn-only` is accepted for
// interface consistency with the rest of the `check_*.dart` loop but has no
// effect (the gate is already warn-mode unconditionally).
//
// Exit: always 0.

import 'dart:convert';
import 'dart:io';

import 'migration_contains_uniqueness_lib.dart';

const _tag = '[migration-contains-uniqueness]';
const _migrationsDir = 'supabase/migrations';

void main(List<String> args) {
  final diffResult = Process.runSync(
    'git',
    ['diff', '--cached', '--unified=0', '--no-color', '--', 'test/**/*.dart'],
    stdoutEncoding: utf8,
  );
  if (diffResult.exitCode != 0) {
    stdout.writeln('$_tag NOTE: git diff --cached unavailable — skipped.');
    exit(0);
  }
  final diffText = diffResult.stdout.toString();
  if (diffText.trim().isEmpty) {
    stdout.writeln('$_tag PASS: no staged test-file additions.');
    exit(0);
  }

  final dir = Directory(_migrationsDir);
  if (!dir.existsSync()) {
    stdout.writeln('$_tag NOTE: $_migrationsDir not found — skipped.');
    exit(0);
  }

  final migrationContents = <String, String>{};
  for (final f in dir.listSync().whereType<File>()) {
    if (!f.path.endsWith('.sql')) continue;
    migrationContents[f.path] = f.readAsStringSync();
  }

  final warnings = findAmbiguousMigrationAssertions(
    diffText: diffText,
    migrationContents: migrationContents,
  );

  if (warnings.isEmpty) {
    stdout.writeln('$_tag PASS: no ambiguous .contains() assertions found.');
    exit(0);
  }

  stderr.writeln('$_tag WARN: ${warnings.length} possibly-ambiguous '
      '.contains() assertion(s) against migration SQL:');
  for (final w in warnings) {
    stderr.writeln('  $w');
  }
  exit(0);
}
