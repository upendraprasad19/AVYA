// scripts/retire-worktree.dart
//
// The missing counterpart to scripts/new-worktree.sh: retires worktrees whose
// work is finished. §4.13 mandated creation and defined no end of life, so the
// count reached 106 directories / 17 GB (2026-08-09).
//
//   dart run scripts/retire-worktree.dart                 # dry-run (DEFAULT)
//   dart run scripts/retire-worktree.dart --execute        # actually remove
//   dart run scripts/retire-worktree.dart --execute <slug> # one worktree
//
// DRY-RUN IS THE DEFAULT and --execute is opt-in, because removal is
// irreversible for exactly the work legs 2-3 exist to catch.
//
// Decision logic lives in scripts/retire_worktree_lib.dart (pure, git-free,
// unit-tested). This file only gathers git facts and performs removal — it
// never decides. Same split as worktree_guard_lib.dart /
// check_commit_from_worktree.dart.
//
// WRITTEN IN DART, NOT SHELL, deliberately. The 2026-08-09 session produced
// THREE consecutive broken shell instruments on this exact task — a `sed` whose
// backslash escaping silently emptied the registered-worktree list, an `awk`
// `gsub` that failed identically, and a `comm` that consequently reported every
// directory as an orphan. Each returned confident, wrong output that looked
// like data. Dart also puts this in reach of the normal test harness.
//
// NOT a `check_*.dart` gate, by name and by intent: retirement is an
// operator-invoked action, not something that runs on every commit. Blocking a
// commit because unrelated old worktrees exist would be a ship-stop for a
// hygiene problem — the same error class as the 2026-07-25/26 required-checks
// incident.

import 'dart:io';
import 'retire_worktree_lib.dart';

/// Worktrees never retired automatically regardless of their git state.
/// Deliberately a hardcoded floor UNDER the three-leg predicate, not a
/// replacement for it — belt and braces on the one operation that can destroy
/// uncommitted work.
const _protected = <String>{
  'post38-auth-fixes',
  'train-signout-notif-bugs',
};

ProcessResult? _git(List<String> args, {String? cwd}) {
  try {
    // List<String> args, never a shell string — this repo's path contains a
    // space ("Claude Code").
    return Process.runSync('git', args, workingDirectory: cwd);
  } on ProcessException {
    return null; // git missing / cwd gone
  }
}

String _norm(String p) =>
    p.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '').toLowerCase();

/// (path, branch) for every registered worktree.
List<(String, String)> _worktrees() {
  final r = _git(['worktree', 'list', '--porcelain']);
  if (r == null || r.exitCode != 0) return const [];
  final out = <(String, String)>[];
  String? path;
  for (final line in (r.stdout as String).split('\n')) {
    final l = line.trimRight();
    if (l.startsWith('worktree ')) {
      path = l.substring(9).trim();
    } else if (l.startsWith('branch ') && path != null) {
      out.add((path, l.substring(7).trim().replaceFirst('refs/heads/', '')));
      path = null;
    } else if (l.startsWith('detached') && path != null) {
      // Detached worktrees carry no branch, so leg 1 can never be satisfied.
      // Emitted with an empty branch so they are COUNTED and reported rather
      // than silently skipped by the parser — an unlisted worktree reads as
      // "handled" when it was never examined.
      out.add((path, ''));
      path = null;
    }
  }
  return out;
}

int _countFiles(Directory d) {
  var n = 0;
  try {
    for (final e in d.listSync(recursive: true, followLinks: false)) {
      if (e is File) n++;
    }
  } on FileSystemException {
    return -1; // unreadable -> caller treats as "not empty"
  }
  return n;
}

void main(List<String> args) {
  final execute = args.contains('--execute');
  final only = args.where((a) => !a.startsWith('--')).firstOrNull;

  final repoRoot = _git(['rev-parse', '--path-format=absolute', '--show-toplevel']);
  if (repoRoot == null || repoRoot.exitCode != 0) {
    stderr.writeln('[retire] not a git repository.');
    exit(1);
  }
  final root = (repoRoot.stdout as String).trim();

  // MUST run from the PRIMARY worktree: removing the tree you are standing in
  // is undefined behaviour.
  final gd = _git(['rev-parse', '--path-format=absolute', '--git-dir']);
  final gc = _git(['rev-parse', '--path-format=absolute', '--git-common-dir']);
  if (gd == null || gc == null) {
    stderr.writeln('[retire] could not resolve git dirs.');
    exit(1);
  }
  if (_norm((gd.stdout as String).trim()) !=
      _norm((gc.stdout as String).trim())) {
    stderr.writeln('[retire] refusing: run from the PRIMARY worktree, not a '
        'linked one (removing the tree you stand in is undefined).');
    exit(1);
  }

  // PRECONDITION: core.worktree must be absent, or every dirty-check below
  // resolves against the WRONG working tree and reports garbage. During the
  // 2026-08-09 incident (diagnose a4f7c2) every worktree's `git status`
  // returned post38-auth-fixes' files — a sweep run then would have read
  // "clean" for worktrees that were not. Guarded by
  // check_worktree_config_integrity.dart on every commit; asserted again here
  // because this is the one operation that deletes.
  final cw = _git(['config', '--show-origin', '--get-all', 'core.worktree']);
  if (cw != null && cw.exitCode == 0) {
    stderr.writeln('[retire] ABORT: core.worktree is set — dirty-state checks '
        'would be unreliable and this command DELETES.\n'
        '  ${(cw.stdout as String).trim()}\n'
        '  Repair first (diagnose a4f7c2), then re-run.');
    exit(1);
  }

  final mergedR = _git(['branch', '--merged', 'main', '--format=%(refname:short)']);
  final merged = <String>{
    if (mergedR != null && mergedR.exitCode == 0)
      ...(mergedR.stdout as String)
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty),
  };

  stdout.writeln('[retire] mode: ${execute ? "EXECUTE" : "DRY-RUN"}');
  stdout.writeln('');

  var retired = 0, kept = 0, failed = 0;

  for (final (path, branch) in _worktrees()) {
    final name = _norm(path).split('/').last;
    if (only != null && name != _norm(only)) continue;

    final isPrimary = _norm(path) == _norm(root);

    // Gather facts. A worktree whose directory is gone, or whose status call
    // fails, is UNREADABLE — never conflated with clean.
    var readable = Directory(path).existsSync();
    var dirty = 0, unpushed = 0;
    if (readable) {
      final st = _git(['status', '--porcelain'], cwd: path);
      if (st == null || st.exitCode != 0) {
        readable = false;
      } else {
        dirty = (st.stdout as String)
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .length;
        final up = _git(['log', '@{u}..', '--oneline'], cwd: path);
        if (up != null && up.exitCode == 0) {
          unpushed = (up.stdout as String)
              .split('\n')
              .where((l) => l.trim().isNotEmpty)
              .length;
        }
      }
    }

    final d = classifyWorktree(
      isPrimary: isPrimary,
      isProtected: _protected.contains(name),
      factsReadable: readable,
      merged: branch.isNotEmpty && merged.contains(branch),
      dirtyFiles: dirty,
      unpushed: unpushed,
    );

    if (!d.shouldRetire) {
      if (!isPrimary) {
        stdout.writeln('  KEEP    $name  [${d.reason}]');
        kept++;
      }
      continue;
    }

    if (!execute) {
      stdout.writeln('  RETIRE  $name  [${d.reason}]');
      retired++;
      continue;
    }

    final rm = _git(['worktree', 'remove', path]);
    if (rm != null && rm.exitCode == 0) {
      stdout.writeln('  RETIRED $name');
      retired++;
    } else {
      stdout.writeln('  FAILED  $name  [${rm == null ? "git error" : (rm.stderr as String).trim()}]');
      failed++;
    }
  }

  // Orphans: directories git does not know about. Reported ALWAYS, removed only
  // when genuinely empty (see classifyOrphan).
  final wtDir = Directory('$root/.claude/worktrees');
  var orphanKept = 0, orphanRemoved = 0;
  if (wtDir.existsSync()) {
    final registered = _worktrees().map((e) => _norm(e.$1)).toSet();
    for (final e in wtDir.listSync().whereType<Directory>()) {
      if (registered.contains(_norm(e.path))) continue;
      final n = _countFiles(e);
      final d = classifyOrphan(fileCount: n < 0 ? 1 : n);
      final nm = _norm(e.path).split('/').last;
      if (!d.shouldRetire) {
        stdout.writeln('  ORPHAN  $nm  [${d.reason}]');
        orphanKept++;
      } else if (!execute) {
        stdout.writeln('  ORPHAN  $nm  [would remove — ${d.reason}]');
        orphanRemoved++;
      } else {
        try {
          e.deleteSync(recursive: true);
          stdout.writeln('  ORPHAN  $nm  [removed — ${d.reason}]');
          orphanRemoved++;
        } on FileSystemException catch (err) {
          stdout.writeln('  ORPHAN  $nm  [delete failed: ${err.message}]');
          failed++;
        }
      }
    }
  }

  stdout.writeln('');
  stdout.writeln('[retire] retire=$retired keep=$kept failed=$failed '
      'orphan_removed=$orphanRemoved orphan_kept=$orphanKept');
  if (!execute) {
    stdout.writeln('[retire] dry-run only — re-run with --execute to remove.');
  }
  exit(failed > 0 ? 1 : 0);
}
