// scripts/ci_sweep_scope.dart
//
// Usage:  git diff --no-renames --name-only HEAD^1 HEAD | dart scripts/ci_sweep_scope.dart
//
// Reads a pull request's changed paths on stdin (one per line) and prints EXACTLY one
// line on stdout: `run=true` (the plan-generator sweeps must run) or `run=false`
// (no changed path can affect them). The reasons go to stderr. Used by the scope step
// of the `sweep-test` matrix in .github/workflows/test.yml.
//
// It ALWAYS exits 0 and ALWAYS prints one of the two lines: any failure in here
// prints `run=true`. The rule and its fail-safe direction: scripts/ci_sweep_scope_lib.dart.
// Run it with plain `dart`, NOT `dart run` (a "Running build hooks..." line on stdout
// would not be one of the two lines the workflow accepts).

import 'dart:convert';
import 'dart:io';

import 'ci_sweep_scope_lib.dart';

void main(List<String> args) {
  var run = true;
  var reasons = <String>['the decision did not complete'];
  try {
    final changed = <String>[];
    String? line;
    while ((line = stdin.readLineSync(encoding: utf8)) != null) {
      changed.add(line!);
    }
    final root = Directory.current;
    final read = diskReader(root);
    final closure = closureOf(sweepRoots(root), read);
    final d = decideSweeps(
      changed: changed,
      closure: closure,
      exists: (p) => FileSystemEntity.isFileSync('${root.path}/$p'),
    );
    run = d.run;
    reasons = d.reasons;
  } catch (e) {
    // `run` is assigned ONLY by a decision that completed (above), so it is still its
    // initial `true` here: there is no line in this branch that could say "skip".
    reasons = ['::warning::ci_sweep_scope failed, running the sweeps: $e'];
  }
  for (final r in reasons.take(40)) {
    stderr.writeln(r);
  }
  if (reasons.length > 40) stderr.writeln('... and ${reasons.length - 40} more');
  stdout.writeln('run=$run');
  exit(0);
}
