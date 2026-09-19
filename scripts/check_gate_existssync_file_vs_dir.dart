// scripts/check_gate_existssync_file_vs_dir.dart
//
// Blocks a STAGED, newly-added `File(...).existsSync()` call inside
// gate/validator-authoring code (scripts/check_*.dart, scripts/*_lib.dart,
// scripts/validate_*.dart) — `File.existsSync()` answers FALSE for a
// directory, so a citation/path check built on it silently misreads a real
// directory as "missing". See gate_existssync_file_vs_dir_lib.dart for the
// full incident history (OI-195) and the deliberate 220-existing-calls
// scoping rationale — this file only gathers the git facts.
//
// Escape hatch: append `// file-only: <reason>` on the same line for a
// deliberate, justified file-only check.
//
// Exit 0 = pass. Exit 1 = fail. `--warn-only` never fails.

import 'dart:convert';
import 'dart:io';
import 'gate_existssync_file_vs_dir_lib.dart';

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final tag = warnOnly ? '[gate-existssync-dir-blind WARN]' : '[gate-existssync-dir-blind]';

  // Staged additions only, no color, zero context lines, scoped to the three
  // gate-authoring globs. stdoutEncoding: utf8 is load-bearing on Windows —
  // see check_no_deferral_euphemism.dart's identical note.
  final result = Process.runSync(
    'git',
    [
      'diff',
      '--cached',
      '--unified=0',
      '--no-color',
      '--',
      'scripts/check_*.dart',
      'scripts/*_lib.dart',
      'scripts/validate_*.dart',
      // Self-exclusion: this gate's own doc comments and user-facing
      // messages necessarily quote `File(...).existsSync()` / `File().
      // existsSync()` in prose to describe the pattern being detected — a
      // line-based regex scan cannot tell a comment/string mention from a
      // real call. Same self-referential class as every sibling gate in
      // this batch (feedback_mistake_guard_without_its_mirror.md's
      // "sibling shape" note).
      ':!scripts/check_gate_existssync_file_vs_dir.dart',
      ':!scripts/gate_existssync_file_vs_dir_lib.dart',
    ],
    stdoutEncoding: utf8,
  );

  if (result.exitCode != 0) {
    // Fail OPEN — never wedge a commit on a git problem (house convention;
    // see check_worktree_config_integrity.dart, check_no_deferral_euphemism.dart).
    stdout.writeln('$tag NOTE: git diff --cached unavailable — scan did not run.');
    exit(0);
  }

  final violations = findDirBlindExistsSyncCalls(result.stdout as String);

  if (violations.isEmpty) {
    stdout.writeln('$tag PASS: no directory-blind File().existsSync() added to gate-authoring code.');
    exit(0);
  }

  stderr.writeln('$tag FAIL: ${violations.length} directory-blind File().existsSync() '
      'call(s) added to gate/validator-authoring code:');
  for (final v in violations) {
    stderr.writeln('  $v');
  }
  stderr.writeln(
    '\n  File(path).existsSync() answers FALSE for a DIRECTORY — a citation or\n'
    '  spec path that legitimately points at a directory (e.g. "test/sql/")\n'
    '  reads as missing even though it exists (OI-195).\n'
    '\n'
    '  Fix: use FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound\n'
    '  for a check that must be agnostic to file-vs-directory.\n'
    '\n'
    '  If this call is deliberately file-only, add a trailing justification:\n'
    '      File(path).existsSync()  // file-only: <reason>',
  );
  exit(warnOnly ? 0 : 1);
}
