// scripts/check_blast_radius_stdin_usage.dart
//
// Blocks a STAGED ADDED line that pipes into
// `scripts/blast_radius_from_diff.dart` without the trailing bare `-`.
// See blast_radius_stdin_usage_lib.dart for the bug class
// (feedback_mistake_blast_radius_positional_mode.md, 5 recorded recurrences)
// and why this is the one shape the script cannot self-detect at runtime.
//
// Scope: `*.sh`, `*.md`, `*.dart` staged additions only — the misuse shows up
// in hook scripts, plan docs, and (rarely) dart tooling that shells out.
//
// Exit 0 = pass. Exit 1 = fail. `--warn-only` never fails.

import 'dart:convert';
import 'dart:io';

import 'blast_radius_stdin_usage_lib.dart';

const _tag = '[blast-radius-stdin]';

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');

  final result = Process.runSync(
    'git',
    [
      'diff',
      '--cached',
      '--unified=0',
      '--no-color',
      '--',
      '*.sh',
      '*.md',
      '*.dart',
      // Self-exclusion (see check_analyze_narrower_than_lib_in_tooling.dart
      // for the general note): this gate's own usage-example message and
      // its test file's fixture strings necessarily quote the exact piped
      // shape it detects, both good and bad forms.
      ':!scripts/check_blast_radius_stdin_usage.dart',
      ':!scripts/blast_radius_stdin_usage_lib.dart',
      ':!test/scripts/blast_radius_stdin_usage_lib_test.dart',
    ],
    stdoutEncoding: utf8,
  );
  if (result.exitCode != 0) {
    stdout.writeln('$_tag NOTE: git diff --cached unavailable — skipped.');
    exit(0);
  }

  final violations = <String>[];
  var currentFile = '';
  for (final raw in const LineSplitter().convert(result.stdout.toString())) {
    if (raw.startsWith('+++ b/')) {
      currentFile = raw.substring('+++ b/'.length).trim();
      continue;
    }
    if (!raw.startsWith('+') || raw.startsWith('+++')) continue;
    final added = raw.substring(1);
    if (isPositionalMisuse(added)) {
      violations.add('$currentFile:  ${added.trim()}');
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('$_tag PASS: no piped-without-dash blast_radius_from_diff.dart calls.');
    exit(0);
  }

  final tag = warnOnly ? '[blast-radius-stdin WARN]' : '[blast-radius-stdin]';
  stderr.writeln('$tag FAIL: ${violations.length} invocation(s) pipe into '
      'blast_radius_from_diff.dart without the trailing bare `-`:');
  for (final v in violations) {
    stderr.writeln('  $v');
  }
  stderr.writeln(
    '\n  Without `-`, the piped content is discarded and the script silently\n'
    '  falls back to `git diff --cached --name-only` (often empty). Fix:\n'
    '      <producer> | dart run scripts/blast_radius_from_diff.dart -',
  );
  exit(warnOnly ? 0 : 1);
}
