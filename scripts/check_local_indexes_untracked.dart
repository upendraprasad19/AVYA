// scripts/check_local_indexes_untracked.dart
//
// Assert that neither generated index, docs/audit/OPEN_INDEX.md or docs/diagnoses/INDEX.md, is
// tracked by git. Takes no gate number: a new gate's filename is its identity (rule 24).
//
// The two indexes are LOCAL BUILD PRODUCTS (landing A2 of the merge-conflict-treadmill plan).
// They are gitignored; this gate fails when either one is TRACKED again.
//
// WHY A GATE. A `.gitignore` line does not stop a tracked file: `git add -f`, a merge that
// brings the path back, or a branch cut before A2 that edited an index and is now merged
// (a modify/delete conflict resolved the wrong way) all re-track it, silently, and the next
// two branches that add an OI or a diagnose doc conflict in a file nobody wrote by hand
// again, which is the whole treadmill this landing removes (47 of 52 replayed main-sync
// merges conflicted, 20 of them in OPEN_INDEX.md and 13 in diagnoses/INDEX.md).
//
// WHAT IT READS: `git ls-files -- <both paths>` (the index, so a STAGED add is caught at
// commit time and a conflicted merge shows its unmerged entries until it is resolved). It
// runs in the pre-commit gate loop and in CI's Audit Gates job on the PR merge ref.
//
// FAILS OPEN when git cannot answer (no git on PATH, not a repository, a `git archive` tree):
// a hygiene gate must never wedge a commit on a git problem (house convention).
//
// Exit 0 = pass (or git unavailable). Exit 1 = a path is tracked. `--warn-only` never fails.

import 'dart:convert';
import 'dart:io';

import 'local_indexes_lib.dart' show kBugIndexPath, kOiIndexPath;

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final tag = warnOnly
      ? '[local-indexes-untracked WARN]'
      : '[local-indexes-untracked]';

  final ProcessResult r;
  try {
    r = Process.runSync('git', ['ls-files', '--', kOiIndexPath, kBugIndexPath],
        stdoutEncoding: utf8);
  } catch (_) {
    stdout.writeln('$tag NOTE: git is not available; the tracked-index scan did not run.');
    exit(0);
  }
  if (r.exitCode != 0) {
    stdout.writeln('$tag NOTE: `git ls-files` failed (exit ${r.exitCode}); the scan did not run.');
    exit(0);
  }

  // `git ls-files` prints an UNMERGED path once per stage (a conflicted merge), so the list is
  // de-duplicated; its order is the index's bytewise path order, which needs no sort.
  final tracked = (r.stdout as String)
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toSet()
      .toList();
  if (tracked.isEmpty) {
    stdout.writeln('$tag PASS: both generated indexes are untracked.');
    exit(0);
  }

  stderr.writeln('$tag FAIL: ${tracked.length} generated index(es) are TRACKED by git:');
  for (final t in tracked) {
    stderr.writeln('  - $t');
  }
  stderr.writeln('');
  stderr.writeln('  These are local build products (gitignored). A tracked copy brings back the');
  stderr.writeln('  merge conflicts they were untracked to remove.');
  stderr.writeln('  Fix: git rm --cached -- ${tracked.join(' ')}');
  stderr.writeln('  then rebuild them locally: dart run scripts/build_local_indexes.dart --lenient');
  stderr.writeln('  (never `git add -f` them; in a merge conflict on one of them, take the');
  stderr.writeln('  deletion and rebuild).');
  exit(warnOnly ? 0 : 1);
}
