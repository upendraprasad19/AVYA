// scripts/check_worktree_config_integrity.dart
//
// Asserts that NO `core.worktree` is configured in any git scope for this repo.
//
// WHY (live incident 2026-08-09): `.git/config` — shared by all 102 linked
// worktrees — carried `[core] worktree = .../worktrees/post38-auth-fixes`, so
// `git rev-parse --show-toplevel` returned that one path from EVERY worktree
// and from the shared main folder. A `git add` from any other worktree would
// have staged post38's files into its own index: the §4.13 cross-session
// mixing incident, one level below where check_commit_from_worktree.dart
// watches. That gate classifies primary-vs-linked by comparing `--git-dir` to
// `--git-common-dir` and passes cleanly while this substrate is corrupt.
//
// WHY "any core.worktree at all" is the right rule HERE (and not in general):
// git legitimately sets core.worktree for `clone/init --separate-git-dir` and
// for submodule git-dirs. Neither applies to this repo — verified 2026-08-09:
// `.git` is a real directory, `core.bare=false`, no `.gitmodules`, and
// `find .git -maxdepth 3 -name config.worktree` returns ZERO across all
// worktrees. An earlier draft of this gate allowed an exception for origins
// under `.git/worktrees/<name>/config.worktree`; that was wrong on both ends —
// git's own docs place a legitimate per-worktree core.worktree in the MAIN
// worktree's `.git/config.worktree`, never there, so the exception whitelisted
// a location git never produces (a re-injection hole) while omitting the only
// one that could ever be legitimate. Simplest correct rule: allow no origin.
//
// Checks ALL scopes, not just the shared file: `--show-origin --get-all` covers
// system, global (~/.gitconfig), local (.git/config) and any worktree config.
// A `core.worktree` in ANY of them produces identical corruption, so a check
// scoped to `--file <common-dir>/config` would have a false-negative class —
// and a false negative here recreates the exact bug the gate exists to catch.
//
// Decision logic + the `--show-origin` parser live in
// scripts/worktree_config_integrity_lib.dart (pure, git-free, unit-tested).
// This file only gathers the git facts.
//
// Exit 0 = pass. Exit 1 = fail. `--warn-only` never fails.

import 'dart:io';
import 'worktree_config_integrity_lib.dart';

/// Run git, returning null if the binary could not be spawned at all.
///
/// Process.runSync THROWS ProcessException when the executable is missing (it
/// does NOT return a non-zero exit code) — verified 2026-08-09. Left uncaught,
/// this gate died with an unhandled exception and exit 255, which also defeated
/// `--warn-only`. Caught here so every failure mode routes through the normal
/// verdict path.
ProcessResult? _tryRun(List<String> args) {
  try {
    return Process.runSync('git', args);
  } on ProcessException {
    return null;
  }
}

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final tag = warnOnly ? '[worktree-config WARN]' : '[worktree-config]';

  // List<String> args to Process.runSync — NEVER a shell string. This repo's
  // path contains a space ("Claude Code"), and shell-quoting it is a footgun.
  //
  // Positive repo assertion FIRST: `git config` exits 1 both when the key is
  // absent AND when we are not in a repository at all, so without this the
  // gate would print "healthy" from any random directory.
  final repoProbe = _tryRun(['rev-parse', '--git-common-dir']);
  final inRepo = repoProbe != null && repoProbe.exitCode == 0;

  final r = _tryRun(['config', '--show-origin', '--get-all', 'core.worktree']);

  final result = r == null
      ? const WorktreeConfigResult(
          violation: false,
          indeterminate: true,
          reason: 'could not execute git (binary missing or not on PATH).',
        )
      : evaluateWorktreeConfig(
          exitCode: r.exitCode,
          stdout: r.stdout as String,
          inRepo: inRepo,
        );

  if (result.indeterminate) {
    // FAIL OPEN, loudly.
    //
    // This gate runs on EVERY commit in EVERY worktree. Hard-failing when git
    // merely could not answer would wedge all work on an environment quirk
    // (a `safe.directory`/dubious-ownership refusal in a container, a broken
    // PATH, a malformed config elsewhere in the file). That is the ship-stop
    // class this repo has been bitten by before — required status checks
    // blocking every direct push, 2026-07-25/26.
    //
    // Matches the sibling gate's explicit convention
    // (check_commit_from_worktree.dart:62-67: "fail OPEN — never wedge a
    // commit on a git problem"). A missed detection is recoverable; a repo
    // nobody can commit to is not.
    stderr.writeln('$tag WARNING (passing): ${result.reason}');
    if (r != null) {
      final e = (r.stderr as String).trim();
      if (e.isNotEmpty) stderr.writeln('  git stderr: $e');
    }
    exit(0);
  }

  if (!result.violation) {
    stdout.writeln('$tag PASS: ${result.reason}');
    exit(0);
  }

  stderr.writeln('$tag FAIL: ${result.reason}');
  for (final e in result.entries) {
    stderr.writeln('  origin: ${e.origin.isEmpty ? '(unknown)' : e.origin}');
    stderr.writeln('  value : ${e.value}');
  }
  stderr.writeln(
    '\n  A linked worktree must NEVER inherit a global core.worktree — git\n'
    '  derives each worktree\'s path from its own gitdir pointer. While this\n'
    '  key is set, every worktree resolves against the path above, so a commit\n'
    '  from any of them can stage another branch\'s files (CLAUDE.md §4.13).\n'
    '\n'
    '  Repair (run from anywhere; --file makes cwd irrelevant, which matters\n'
    '  because rev-parse itself is currently misdirected):\n'
    '      git config --file "<repo>/.git/config" --unset-all core.worktree\n'
    '  If the origin above is a global/system file, unset it there instead.\n'
    '\n'
    '  Then verify BOTH — the main-folder check alone misses the blast radius:\n'
    '      git config --show-origin --get-all core.worktree   # expect empty\n'
    '      git rev-parse --show-toplevel                      # from a LINKED worktree',
  );
  exit(warnOnly ? 0 : 1);
}
