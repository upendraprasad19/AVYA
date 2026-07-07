// scripts/check_commit_from_worktree.dart
//
// Worktree-per-session enforcement (codified 2026-07-07 after 2 cross-session
// file-mixing incidents). ROOT CAUSE: multiple Claude sessions running in the
// SHARED main folder (`C:/Upendra/Claude Code/Fitness App`) share ONE git index
// (`.git/index`). Concurrent `git add` from two sessions accumulates BOTH
// sessions' staged files in that one index, so a commit from either can sweep in
// the other's work. A git WORKTREE has its OWN index — so working in a dedicated
// worktree makes the mixing structurally impossible.
//
// This gate BLOCKS a normal (non-merge) commit made in the PRIMARY worktree (the
// shared main folder), forcing feature work into an isolated worktree. It runs at
// pre-commit (LOCAL only — the mixing happens locally), auto-wired via the
// `for GATE in scripts/check_*.dart` loop in scripts/pre-commit.sh.
//
// PRIMARY-vs-LINKED detection is deterministic: in the primary worktree
// `git rev-parse --git-dir` == `--git-common-dir`; in a linked worktree
// `--git-dir` is `.git/worktrees/<name>` and `--git-common-dir` is the shared
// `.git`, so they DIFFER.
//
// Decision precedence + PASS/FAIL conditions live in scripts/worktree_guard_lib.dart
// (pure, git-free, unit-tested). This file only gathers the git/env facts.
//
// Exit 0 = pass. Exit 1 = fail. `--warn-only` never fails (soft-rollout window).

import 'dart:io';
import 'worktree_guard_lib.dart';

String _git(List<String> args) {
  final r = Process.runSync('git', args);
  return r.exitCode == 0 ? (r.stdout as String).trim() : '';
}

bool _gitOk(List<String> args) => Process.runSync('git', args).exitCode == 0;

String _norm(String p) =>
    p.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '').toLowerCase();

const _fixHint =
    'Its git index is shared with any other Claude session working in this\n'
    '  folder, so a commit here can MIX your files with another session\'s\n'
    '  (2 cross-session mixing incidents 2026-07-07). Work in your own worktree:\n'
    '      sh scripts/new-worktree.sh <slug>\n'
    '      cd .claude/worktrees/<slug>     # then edit + commit there\n'
    '  The main worktree is INTEGRATION-ONLY: `git merge <branch>` + `git push`\n'
    '  + `/build-apk` + reads.\n'
    '  Rare solo exception (you are CERTAIN no other session is active in this\n'
    '  folder): ALLOW_MAIN_COMMIT=1 git commit ...';

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final tag = warnOnly ? '[worktree-guard WARN]' : '[worktree-guard]';
  final env = Platform.environment;

  final gitDir = _git(['rev-parse', '--git-dir']);
  final commonDir = _git(['rev-parse', '--git-common-dir']);
  if (gitDir.isEmpty || commonDir.isEmpty) {
    // Not a git repo / introspection hiccup — fail OPEN (never wedge a commit).
    stdout.writeln('$tag PASS: could not resolve git dirs (fail-open).');
    exit(0);
  }

  final result = evaluateWorktreeGuard(
    isCi: env['CI'] == 'true' || env['GITHUB_ACTIONS'] == 'true',
    allowOverride: env['ALLOW_MAIN_COMMIT'] == '1',
    hasStaged: _git(['diff', '--cached', '--name-only']).isNotEmpty,
    mergeInProgress: _gitOk(['rev-parse', '-q', '--verify', 'MERGE_HEAD']),
    isLinkedWorktree: _norm(gitDir) != _norm(commonDir),
  );

  if (!result.blocked) {
    stdout.writeln('$tag PASS: ${result.reason}');
    exit(0);
  }

  stderr.writeln(
    '$tag FAIL: do NOT commit feature work in the SHARED main worktree.\n'
    '  $_fixHint',
  );
  exit(warnOnly ? 0 : 1);
}
