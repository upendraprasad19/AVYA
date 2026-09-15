@Timeout(Duration(minutes: 6))
library;

// End-to-end coverage for scripts/check_closes_oi_performed.dart against REAL
// git repositories with REAL merge commits.
//
// WHY THIS FILE EXISTS AND THE UNIT TESTS ARE NOT ENOUGH. The predicate living
// in oi_closure_lib.dart can be perfect while the gate never reaches it — that
// is the Gate-44 class this repo names explicitly (a gate whose own test never
// invoked `main()`). Everything interesting here is in the wiring: detecting a
// merge commit at all, resolving HEAD^1..HEAD^2, and reading the board AT the
// merge rather than from the working tree. None of that is unit-testable.
//
// @Timeout, per the documented class: this file spawns `git` and a real
// `dart run` child repeatedly. Each `dart run` pays the flutter/bin/dart
// wrapper cost (3.4-10.5s for a no-op), and two sequential spawns fit inside
// the 30s default when the file runs ALONE and do not when the full suite runs
// ~40 files concurrently. A targeted run is a different input set, not a subset.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/regression_catalog_lib.dart' show scrubbedChildEnvironment;

late final String _repoRoot;
late final String _gate;

/// Runs git in [cwd] with the hook variables scrubbed.
///
/// The scrub is NOT optional. GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE override
/// BOTH `workingDirectory:` and `-C`, so when this suite runs inside pre-commit
/// every command below would silently operate on the REAL repository instead of
/// the throwaway fixture — building branches and merge commits in the live tree.
/// Same class as feedback_mistake_git_hook_env_leak.
/// ⚠ NO `runInShell` HERE, deliberately, and it is not a style choice. With a
/// shell in the path on Windows the arguments are re-parsed by cmd.exe, and a
/// `-m "Merge branch 'feature'"` carrying embedded quotes came back mangled —
/// git then fast-forwarded instead of honouring `--no-ff`, producing a
/// SINGLE-parent commit. The gate correctly skipped it as "not a merge", so
/// four tests failed with empty output and exit 0 while the gate was working
/// perfectly. `dart` still needs the shell for PATHEXT resolution (see
/// [_runGate]); `git` does not.
ProcessResult _git(List<String> args, String cwd) => Process.runSync(
      'git',
      args,
      workingDirectory: cwd,
      environment: scrubbedChildEnvironment(Platform.environment),
      includeParentEnvironment: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

/// One `## OI-NN — title` section with the given status, in the real shape.
String _entry(String oi, String status) =>
    '## $oi — a real-shaped heading with an em-dash\n\n'
    '- **Status**: $status\n'
    '- **Blocked on**: nothing\n'
    '- **Verified**: never\n';

/// Builds a fixture repo, a branch whose commit cites [citation], and merges it
/// `--no-ff` into the default branch. Returns the repo path.
///
/// [openBoard] / [closedBoard] are written at the MERGE, so a caller can stage
/// the "fix shipped, board never moved" state exactly as it shipped.
String _mergedRepo({
  required Directory tmp,
  required String citation,
  required String openBoard,
  String closedBoard = '',
}) {
  final repo = Directory('${tmp.path}/repo')..createSync(recursive: true);
  final p = repo.path;

  expect(_git(['init'], p).exitCode, 0, reason: 'fixture init failed');
  _git(['config', 'user.email', 't@example.com'], p);
  _git(['config', 'user.name', 'Fixture'], p);
  // Deterministic across git versions that default to `master` vs `main`.
  _git(['checkout', '-b', 'trunk'], p);

  Directory('$p/docs/audit').createSync(recursive: true);
  File('$p/docs/audit/open_issues.md').writeAsStringSync(openBoard);
  File('$p/docs/audit/closed_issues.md').writeAsStringSync(closedBoard);
  File('$p/seed.txt').writeAsStringSync('seed\n');
  _git(['add', '-A'], p);
  expect(_git(['commit', '-m', 'seed'], p).exitCode, 0);

  expect(_git(['checkout', '-b', 'feature'], p).exitCode, 0);
  File('$p/work.txt').writeAsStringSync('the fix\n');
  _git(['add', '-A'], p);
  expect(
      _git(['commit', '-m', 'fix(x): ship the thing\n\n$citation'], p).exitCode,
      0);

  expect(_git(['checkout', 'trunk'], p).exitCode, 0);
  // The board state at the merge is whatever the branch left it as — the
  // fix-shipped-board-untouched shape needs no extra step, which is precisely
  // why the bug was so easy to commit.
  expect(_git(['merge', '--no-ff', 'feature', '-m', 'Merge branch feature'], p)
      .exitCode, 0);

  // THE FIXTURE VALIDATES ITSELF, and this assertion has already earned its
  // place: the first version of this helper produced a FAST-FORWARD, so HEAD
  // had one parent, the gate correctly skipped, and four tests failed with
  // empty output — which reads as a broken gate rather than a broken fixture.
  // A fixture that does not manufacture the state under test asserts nothing,
  // and the cheapest way to know is to check the state, not the exit code.
  final parents =
      (_git(['log', '-1', '--format=%P'], p).stdout as String).trim().split(' ');
  expect(parents.length, 2,
      reason: 'fixture must produce a real MERGE commit — got ${parents.length} '
          'parent(s), so --no-ff did not take effect');
  return p;
}

/// Invokes the REAL gate script with [cwd] as the repo under test.
ProcessResult _runGate(String cwd, {List<String> args = const []}) =>
    Process.runSync(
      'dart',
      ['run', _gate, ...args],
      workingDirectory: cwd,
      environment: scrubbedChildEnvironment(Platform.environment),
      includeParentEnvironment: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
      runInShell: true,
    );

void main() {
  late Directory tmp;

  setUpAll(() {
    _repoRoot = Directory.current.path;
    _gate = '$_repoRoot/scripts/check_closes_oi_performed.dart';
    expect(File(_gate).existsSync(), isTrue,
        reason: 'the gate must exist where this test spawns it from');
  });

  setUp(() => tmp = Directory.systemTemp.createTempSync('closes_oi_perf_'));

  tearDown(() {
    // NEVER throws. A timed-out child still holds a Windows handle into the
    // temp dir, so deleteSync raises PathAccessException and stacks a SECOND
    // failure that HIDES the real one. Cleanup is hygiene, not an assertion;
    // %TEMP% is reaped by the OS regardless.
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // deliberately ignored — see above
    }
  });

  // THE SHIPPED BUG, REPRODUCED. This is the OI-150 state exactly: the fix
  // merged, the commit cited the close, the board never moved.
  test('FAILS when a merged commit cites a close the board never performed',
      () {
    final repo = _mergedRepo(
      tmp: tmp,
      citation: 'closes-oi: OI-150',
      openBoard: _entry('OI-150', 'OPEN'),
    );
    final r = _runGate(repo);
    expect(r.exitCode, 1,
        reason: 'the whole point of the gate — a citation the board contradicts');
    expect('${r.stdout}${r.stderr}', contains('OI-150'));
  });

  test('PASSES when the citation was actually performed', () {
    final repo = _mergedRepo(
      tmp: tmp,
      citation: 'closes-oi: OI-150',
      openBoard: _entry('OI-1', 'OPEN'),
      closedBoard: _entry('OI-150', 'CLOSED'),
    );
    final r = _runGate(repo);
    expect(r.exitCode, 0,
        reason: 'an OI correctly moved to closed_issues.md must not be flagged '
            '— reading only the open board would fail every correct close');
    expect(r.stdout, contains('OK'));
  });

  test('a dangling citation WARNS but does not block', () {
    final repo = _mergedRepo(
      tmp: tmp,
      citation: 'closes-oi: OI-999',
      openBoard: _entry('OI-1', 'OPEN'),
    );
    final r = _runGate(repo);
    expect(r.exitCode, 0,
        reason: 'OI numbers have been renumbered on a branch six times here, '
            'so a message can name a number that no longer exists; blocking on '
            'that would create the false-positive class that trains bypasses');
    expect(r.stdout, contains('WARN'));
    expect(r.stdout, contains('OI-999'));
  });

  test('SKIPS SILENTLY (not merely exit 0) when HEAD is not a merge commit',
      () {
    final repo = _mergedRepo(
      tmp: tmp,
      citation: 'closes-oi: OI-150',
      openBoard: _entry('OI-150', 'OPEN'),
    );
    // Step off the merge onto a single-parent commit — the pre-commit shape.
    File('$repo/after.txt').writeAsStringSync('later\n');
    _git(['add', '-A'], repo);
    expect(_git(['commit', '-m', 'chore: unrelated'], repo).exitCode, 0);

    final r = _runGate(repo);
    expect(r.exitCode, 0,
        reason: 'at pre-commit HEAD has one parent; the gate must be a no-op '
            'there or it would block every ordinary commit on a branch');

    // ⚠ EXIT CODE ALONE DOES NOT PROVE THE GUARD RAN. `HEAD^2` cannot resolve
    // off ANY single-parent HEAD, guard present or not — so with the guard
    // removed, the gate falls through to the `HEAD^1..HEAD^2` git call, THAT
    // call fails for the unrelated reason "no such parent", and the existing
    // _skip() path fires anyway. Confirmed by actually neutering the guard: 6
    // of 6 tests in this file, including this one, stayed green — an ABSORBED
    // mutation, not a passing one. The observable difference is OUTPUT: the
    // real guard exits with NOTHING (the code's own comment calls it
    // "silent-ish by design"); the fallen-through path prints a SKIPPED line.
    expect('${r.stdout}${r.stderr}'.trim(), isEmpty,
        reason: 'a non-empty SKIPPED message here means the merge-detection '
            'guard did not fire and a DIFFERENT guard caught it instead — '
            'exit code 0 is not enough to tell the two apart');
  });

  test('--warn-only reports the same finding without blocking', () {
    final repo = _mergedRepo(
      tmp: tmp,
      citation: 'closes-oi: OI-150',
      openBoard: _entry('OI-150', 'OPEN'),
    );
    final r = _runGate(repo, args: ['--warn-only']);
    expect(r.exitCode, 0);
    expect(r.stdout, contains('OI-150'));
    expect(r.stdout, contains('WARN'));
  });

  test('reads the board AT THE MERGE, not from the working tree', () {
    final repo = _mergedRepo(
      tmp: tmp,
      citation: 'closes-oi: OI-150',
      openBoard: _entry('OI-150', 'OPEN'),
    );
    // Make the WORKING TREE look correct without committing it. If the gate
    // read the tree it would now pass, and the check would be defeated by the
    // most natural mistake there is. This is the exact defect the B-pass found
    // in safe_merge.sh's precheck on 2026-08-30.
    File('$repo/docs/audit/open_issues.md').writeAsStringSync('');
    File('$repo/docs/audit/closed_issues.md')
        .writeAsStringSync(_entry('OI-150', 'CLOSED'));

    final r = _runGate(repo);
    expect(r.exitCode, 1,
        reason: 'an uncommitted board edit must not satisfy a gate that judges '
            'a commit — the merge is what CI sees and what history keeps');
  });
}
