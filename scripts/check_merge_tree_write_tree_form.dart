// scripts/check_merge_tree_write_tree_form.dart
//
// Gate: flag the legacy `git merge-tree <base> <a> <b>` (3-arg) form in
// STAGED ADDED lines of any file. That form is silently useless for conflict
// detection -- it NEVER emits `<<<<<<<` conflict markers, so a script or a
// human grepping its output for conflicts always reports zero, in the same
// colour as "no conflicts" (feedback_green_check_input_set_width.md,
// 2026-08-10 instance #2: a session read that zero as "PR will auto-merge
// cleanly"; `git merge-tree --write-tree <base> <a> <b>` on the same refs
// found 3 real conflicts). The fix is the `--write-tree` form. This gate
// only stops a NEW bad invocation from being committed -- it cannot see
// interactive shell commands, which is where the original incident
// happened.
//
// Scope: staged ADDED lines only (`git diff --cached --unified=0`), no
// domain-specific path filter -- the bad shape can land in a script, a
// skill doc, or a runbook. Self-excludes its own 2 authoring files,
// test/** (fixtures legitimately contain example invocations as string
// data), and the 2 generated/ledger docs that echo gate headers verbatim
// (docs/audit/GATE_INDEX.md, docs/audit/gate_test_ledger.yaml) -- a
// line-based textual scan cannot tell a real invocation from a prose
// example or a test fixture quoting one (feedback_mistake_guard_without_
// its_mirror.md's "sibling shape" note).
// Detection logic (invocation-vs-prose distinction) lives in
// scripts/merge_tree_write_tree_form_lib.dart (pure, git-free, unit-tested).
//
// Known residual: a comment that WARNS about the bad pattern using
// ref-like placeholder words (e.g. "don't run merge-tree base a b") and is
// not wrapped in backticks will still be flagged -- narrow, and the fix
// (wrap it in backticks, or write `--write-tree` in the same breath) is
// itself good practice.
//
// Exit 0 = pass. Exit 1 = fail. `--warn-only` never fails.

import 'dart:convert';
import 'dart:io';

import 'merge_tree_write_tree_form_lib.dart';

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final tag = warnOnly ? '[merge-tree-form WARN]' : '[merge-tree-form]';

  // stdoutEncoding: utf8 is load-bearing on Windows -- see
  // check_no_deferral_euphemism.dart's identical note (diagnose d3f1a7).
  final result = Process.runSync(
    'git',
    [
      'diff',
      '--cached',
      '--unified=0',
      '--no-color',
      '--',
      '.',
      // Self-exclusion (see check_analyze_narrower_than_lib_in_tooling.dart
      // for the general note): this gate's own doc comments and test-file
      // fixtures necessarily contain example invocations with 2+ ref-like
      // tokens after "merge-tree", and generated/ledger docs echo gate
      // headers verbatim -- none of these are real shell usage.
      ':!scripts/check_merge_tree_write_tree_form.dart',
      ':!scripts/merge_tree_write_tree_form_lib.dart',
      ':!test/**',
      ':!docs/audit/GATE_INDEX.md',
      ':!docs/audit/gate_test_ledger.yaml',
    ],
    stdoutEncoding: utf8,
  );

  if (result.exitCode != 0) {
    // Fail OPEN -- never wedge a commit on a git problem (matches
    // check_worktree_config_integrity.dart's stated convention).
    stderr.writeln('$tag NOTE (passing): git diff --cached unavailable; '
        'the staged-diff scan did not run.');
    exit(0);
  }

  final violations = findLegacyMergeTreeInvocations(result.stdout as String);

  if (violations.isEmpty) {
    stdout.writeln('$tag PASS: no legacy 3-arg `git merge-tree` invocations '
        'in staged additions.');
    exit(0);
  }

  final levelTag = warnOnly ? '$tag WARN' : '$tag FAIL';
  stderr.writeln('$levelTag: ${violations.length} legacy `git merge-tree` '
      'invocation(s) in staged additions -- these emit NO conflict markers, '
      'ever, so grepping their output for `<<<<<<<` always reports zero.');
  stderr.writeln('Use `git merge-tree --write-tree <base> <a> <b>` instead.');
  stderr.writeln('');
  for (final v in violations.take(15)) {
    stderr.writeln('  - $v');
  }
  if (violations.length > 15) {
    stderr.writeln('  ... and ${violations.length - 15} more');
  }
  exit(warnOnly ? 0 : 1);
}
