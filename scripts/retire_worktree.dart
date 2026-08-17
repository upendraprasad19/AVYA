// scripts/retire_worktree.dart
//
// The missing counterpart to scripts/new-worktree.sh: retires worktrees whose
// work is finished. §4.13 mandated creation and defined no end of life, so the
// count reached 106 directories / 17 GB (2026-08-09).
//
//   dart run scripts/retire_worktree.dart                 # dry-run (DEFAULT)
//   dart run scripts/retire_worktree.dart --execute        # actually remove
//   dart run scripts/retire_worktree.dart --execute <slug> # one worktree
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
/// Deliberately a hardcoded floor UNDER the four-leg predicate, not a
/// replacement for it — belt and braces on the one operation that can destroy
/// uncommitted work.
/// Status of each entry, VERIFIED 2026-08-17 against a freshly fetched
/// `origin/main` — not a stale local `main`, and not `git worktree list` alone,
/// which answers a different question than "is this protecting anything".
///
/// - `post38-auth-fixes` — ACTIVELY LOAD-BEARING. Its worktree exists and holds
///   4 untracked diagnose-docs (2026-08-06-*-e5c2d1 / d3a7c9 / a4f1c8 / c9e2b7),
///   and `git merge-base --is-ancestor HEAD origin/main` is FALSE for that
///   worktree's HEAD even though the branch REF of the same name IS merged.
///   Those two facts differ, and only the first one matters here.
/// - `train-signout-notif-bugs` — REMOVED 2026-08-17. Branch merged into
///   origin/main, no directory, no `git worktree list` entry: it protects
///   nothing. A concurrent session parked exactly this removal on the session
///   that owns this file, and the evidence supports that half.
///
/// The request as parked was "_protected removal" — i.e. BOTH. Half of it was
/// wrong, and only re-checking each entry separately showed which half. A
/// hand-off that names a FILE cannot carry per-entry evidence; that is the
/// cross-session blind spot OI-130 exists for. Before pruning the remaining
/// entry, re-run both checks above: a floor removed because nothing is standing
/// on it is not a floor.
const _protected = <String>{
  'post38-auth-fixes',
};

/// Parent env minus git's own vars.
///
/// git exports GIT_DIR / GIT_WORK_TREE into every hook, and they override BOTH
/// `workingDirectory:` and `-C <path>`. This command DELETES, so a leaked
/// GIT_WORK_TREE pointing elsewhere is not a cosmetic problem — round 1 showed
/// it defeats the primary-worktree detection below.
Map<String, String> _cleanEnv() {
  final e = Map<String, String>.from(Platform.environment);
  e.removeWhere((k, _) => k.toUpperCase().startsWith('GIT_'));
  return e;
}

ProcessResult? _git(List<String> args, {String? cwd}) {
  try {
    // List<String> args, never a shell string — this repo's path contains a
    // space ("Claude Code").
    return Process.runSync('git', args,
        workingDirectory: cwd,
        environment: _cleanEnv(),
        includeParentEnvironment: false);
  } on ProcessException {
    return null; // git missing / cwd gone
  }
}

/// Raw `git worktree list --porcelain` output ('' when git could not answer).
String _porcelain() {
  final r = _git(['worktree', 'list', '--porcelain']);
  return (r == null || r.exitCode != 0) ? '' : r.stdout as String;
}

String _norm(String p) =>
    p.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '').toLowerCase();

/// Count of ENTRIES (not just files) under [d].
///
/// Deliberately counts directories too. An earlier version counted only Files,
/// so a tree of empty subdirectories — and a directory holding only a symlink /
/// NTFS junction to a real tree — both measured 0 and were classified "empty
/// husk", which is not what `classifyOrphan` documents. Returns -1 when
/// unreadable; the caller maps that to "not empty" so it can never be deleted.
int _countEntries(Directory d) {
  var n = 0;
  try {
    for (final _ in d.listSync(recursive: true, followLinks: false)) {
      n++;
    }
  } on FileSystemException {
    return -1;
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

  var retired = 0, kept = 0, failed = 0, matched = 0;

  for (final w in parseWorktreePorcelain(_porcelain())) {
    final path = w.path;
    final branch = w.branch;
    final name = _norm(path).split('/').last;
    if (only != null && name != _norm(only)) continue;
    matched++;

    final isPrimary = _norm(path) == _norm(root);

    // Naming the PRIMARY as a slug must not look like success. Its output line
    // is suppressed below (it is never a retirement candidate), so without this
    // `--execute "Fitness App"` printed nothing and exited 0 — indistinguishable
    // from "retired it".
    if (isPrimary && only != null) {
      stderr.writeln('[retire] FAIL: "$only" is the PRIMARY worktree — it is '
          'the integration folder and is never retired.');
      exit(1);
    }

    // Gather facts. A worktree whose directory is gone, or whose status call
    // fails, is UNREADABLE — never conflated with clean.
    var readable = Directory(path).existsSync();
    var dirty = 0, unpushed = 0, ignored = 0;
    var upstream = true;
    if (readable) {
      // PER-WORKTREE core.worktree check. The global guard above reads only the
      // primary's config scopes; a `core.worktree` in
      // .git/worktrees/<name>/config.worktree is invisible to it and silently
      // redirects THIS worktree's status at another directory — the a4f7c2
      // inversion one scope over. Assert this worktree resolves to itself
      // before trusting anything it reports.
      final top = _git(['rev-parse', '--show-toplevel'], cwd: path);
      if (top == null ||
          top.exitCode != 0 ||
          _norm((top.stdout as String).trim()) != _norm(path)) {
        readable = false;
      }
    }
    if (readable) {
      // --ignored=matching: `git status --porcelain` EXCLUDES ignored files and
      // `git worktree remove` does not refuse on them, so without this an
      // ignored file is destroyed silently (verified 2026-08-09).
      final st = _git(['status', '--porcelain', '--ignored=matching'], cwd: path);
      if (st == null || st.exitCode != 0) {
        readable = false;
      } else {
        for (final l in (st.stdout as String).split('\n')) {
          final line = l.trimRight();
          if (line.trim().isEmpty) continue;
          final isIgnored = line.startsWith('!!');
          final p = line.length > 3 ? line.substring(3).trim() : '';
          if (isIgnored) {
            if (!isRegenerableIgnored(p)) ignored++;
          } else {
            dirty++;
          }
        }
        // NO UPSTREAM is not "nothing unpushed" (round-1 F2). `git log @{u}..`
        // exits 128 when no tracking branch exists. Distinguish the two rather
        // than reading 128 as 0: the branch is still retirable (leg 1 already
        // proved it merged, so its commits are reachable from main), but the
        // reason string must not claim a leg it never evaluated.
        final hasUp = _git(['rev-parse', '--abbrev-ref', '@{u}'], cwd: path);
        upstream = hasUp != null && hasUp.exitCode == 0;
        if (upstream) {
          final up = _git(['log', '@{u}..', '--oneline'], cwd: path);
          if (up == null || up.exitCode != 0) {
            readable = false;
          } else {
            unpushed = (up.stdout as String)
                .split('\n')
                .where((l) => l.trim().isNotEmpty)
                .length;
          }
        }
      }
    }

    final d = classifyWorktree(
      isPrimary: isPrimary,
      isProtected: _protected.contains(name) || w.locked,
      factsReadable: readable,
      merged: branch.isNotEmpty && merged.contains(branch),
      dirtyFiles: dirty,
      unpushed: unpushed,
      ignoredFiles: ignored,
      upstreamConfigured: upstream,
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
  // SCOPED BY SLUG. Round-1 F4: `only` filtered the registered loop but not
  // this one, so `--execute <slug-that-matches-nothing>` still deleted an
  // orphan the operator never named. A scoped invocation must touch exactly
  // what it names.
  final wtDir = Directory('$root/.claude/worktrees');
  var orphanKept = 0, orphanRemoved = 0;
  if (wtDir.existsSync() && only == null) {
    final registered =
        parseWorktreePorcelain(_porcelain()).map((e) => _norm(e.path)).toSet();
    for (final e in wtDir.listSync().whereType<Directory>()) {
      if (registered.contains(_norm(e.path))) continue;
      // Dot-directories are tooling artifacts, not worktrees. `new-worktree.sh`
      // creates `.claude/worktrees/<slug>` from an operator-supplied slug, and
      // no slug starts with a dot — but `dart`/`flutter` drop a `.dart_tool/`
      // here when a command is run from this directory, and it was being
      // reported as "an orphan with 2 entries and no git to vouch for them".
      // Harmless while non-empty (only a 0-entry orphan is auto-removed), and
      // still wrong: it trains the operator to ignore ORPHAN lines, which is
      // the one category that requires a human to actually look.
      if (_norm(e.path).split('/').last.startsWith('.')) continue;
      final n = _countEntries(e);
      final d = classifyOrphan(entryCount: n < 0 ? 1 : n);
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

  // A named slug that matched nothing is an ERROR, not a silent success.
  // Silently doing nothing while reporting exit 0 is how an operator believes a
  // worktree was retired when it never existed under that name.
  if (only != null && matched == 0) {
    stderr.writeln('[retire] FAIL: no registered worktree named "$only". '
        'Nothing was examined or removed.');
    exit(1);
  }

  stdout.writeln('');
  stdout.writeln('[retire] retire=$retired keep=$kept failed=$failed '
      'orphan_removed=$orphanRemoved orphan_kept=$orphanKept');
  if (only != null) {
    stdout.writeln('[retire] scoped to "$only" — orphan sweep skipped.');
  }
  if (!execute) {
    stdout.writeln('[retire] dry-run only — re-run with --execute to remove.');
  }
  exit(failed > 0 ? 1 : 0);
}
