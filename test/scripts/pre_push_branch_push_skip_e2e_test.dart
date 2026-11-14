// test/scripts/pre_push_branch_push_skip_e2e_test.dart
//
// END-TO-END: runs the REAL scripts/pre-push.sh (a verbatim copy inside a
// scratch git repo) with stub `flutter` + `dart` on PATH and a git-style
// pre-push STDIN fixture, and asserts which flutter subcommands it invokes.
//
// WHY this file exists (OI-275, docs/plans/2026-10-10-release-cycle-speedup.md
// B1): pre-push used to drain stdin and run the ~39-minute local suite at every
// >= account tier. It now classifies the pushed refs and skips that suite for a
// BRANCH push (CI on the open PR is the gate, scripts/safe_pr_merge.sh the merge
// control). The existing harness (pre_push_analyze_always_e2e_test.dart) always
// feeds `< /dev/null`, which is the empty-stdin FAIL-SAFE path, so it cannot see
// the new branch at all. This file feeds real ref lines.
//
// The contract has two halves and BOTH are tested:
//   SKIP    only a well-formed push whose every ref is a non-main/develop
//           refs/heads/* branch, at a KNOWN risky tier (or delete-only).
//   RUN     everything else -- main, develop, tag, a main ref mixed in with
//           branches, malformed or empty stdin, an unknown tier, PRE_PUSH_FULL=1.
// The RUN half is the mirror: a predicate that is too wide skips the suite on a
// push that lands on main, which is the failure that matters.
//
// `flutter analyze` must happen on EVERY row (it is the only compile check for a
// PR-less branch) -- asserted as the first call in each case.

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

const Set<String> _setOnPurpose = {'CONTRACT_SWEEP_SKIP', 'PRE_PUSH_FULL'};

/// `C:\a\b` -> `/c/a/b`; Git Bash ignores Windows-form PATH entries (see the
/// header of pre_push_analyze_always_e2e_test.dart).
String _toPosixPath(String p) {
  var s = p.replaceAll('\\', '/');
  final m = RegExp(r'^([A-Za-z]):/').firstMatch(s);
  if (m != null) s = '/${m.group(1)!.toLowerCase()}/${s.substring(3)}';
  return s;
}

final String _zeros = '0' * 40;
final String _sha = 'a' * 40;

/// One pre-push stdin line: `<local ref> <local sha> <remote ref> <remote sha>`.
String _update(String ref, {String? remoteRef}) =>
    '$ref $_sha ${remoteRef ?? ref} $_zeros';
String _delete(String remoteRef) => '(delete) $_zeros $remoteRef $_sha';

class _Run {
  _Run(this.exitCode, this.calls, this.stdout, this.stderr);
  final int exitCode;
  final List<String> calls;
  final String stdout;
  final String stderr;
}

void main() {
  late Directory nonEmptyRange; // origin/main..HEAD has a commit
  late Directory emptyRange; // origin/main == HEAD
  late Directory noOrigin; // no refs/remotes/origin/main at all
  late Directory stubDir;

  String git(Directory repo, List<String> args) {
    final r = runSpawn('git', args,
        why: 'pre-push branch-skip fixture: git ${args.join(' ')}',
        workingDirectory: repo.path,
        extraEnv: {'CONTRACT_SWEEP_SKIP': '1'},
        allowControl: _setOnPurpose);
    expect(r.exitCode, 0, reason: 'git ${args.join(' ')}: ${r.stderr}');
    return (r.stdout as String).trim();
  }

  Directory makeRepo(String prefix, {required bool commitAheadOfOrigin, bool withOriginMain = true}) {
    final repo = Directory.systemTemp.createTempSync(prefix);
    git(repo, ['init', '--quiet']);
    git(repo, ['config', 'user.email', 'test@example.com']);
    git(repo, ['config', 'user.name', 'test']);
    File('${repo.path}/seed.txt').writeAsStringSync('seed\n');
    git(repo, ['add', '-A']);
    git(repo, ['commit', '--quiet', '--no-verify', '-m', 'seed']);
    if (withOriginMain) git(repo, ['update-ref', 'refs/remotes/origin/main', 'HEAD']);
    if (commitAheadOfOrigin) {
      Directory('${repo.path}/docs').createSync();
      File('${repo.path}/docs/note.md').writeAsStringSync('note\n');
      git(repo, ['add', '-A']);
      git(repo, ['commit', '--quiet', '--no-verify', '-m', 'docs: note']);
    }
    Directory('${repo.path}/scripts').createSync();
    // The hook under test, copied VERBATIM.
    File('scripts/pre-push.sh').copySync('${repo.path}/scripts/pre-push.sh');
    return repo;
  }

  setUpAll(() {
    nonEmptyRange = makeRepo('prepush_skip_a_', commitAheadOfOrigin: true);
    emptyRange = makeRepo('prepush_skip_b_', commitAheadOfOrigin: false);
    noOrigin = makeRepo('prepush_skip_c_', commitAheadOfOrigin: false, withOriginMain: false);

    stubDir = Directory.systemTemp.createTempSync('prepush_skip_stubs_');
    // flutter: record the subcommand. dart: print the tier named by TIER_STUB
    // (with the `dart run` build-hooks preamble the hook's grep tolerates), or
    // NOTHING when TIER_STUB is empty -- which is how an unknown tier is made.
    File('${stubDir.path}/flutter').writeAsStringSync(
        '#!/bin/sh\necho "\$1" >> "\$FLUTTER_STUB_LOG"\nexit 0\n');
    File('${stubDir.path}/dart').writeAsStringSync('#!/bin/sh\ncat > /dev/null\n'
        'if [ -n "\$TIER_STUB" ]; then printf "Running build hooks...Blast-radius: %s\\n" "\$TIER_STUB"; fi\n'
        'exit 0\n');
    runSpawn('chmod', ['+x', '${stubDir.path}/flutter', '${stubDir.path}/dart'],
        why: 'pre-push branch-skip: chmod stubs');
  });

  tearDownAll(() {
    for (final d in [nonEmptyRange, emptyRange, noOrigin, stubDir]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  var seq = 0;

  /// Runs the copied hook with [refs] as the pre-push stdin.
  _Run runHook(
    List<String> refs, {
    String? tier,
    bool prePushFull = false,
    Directory? repo,
  }) {
    final dir = repo ?? nonEmptyRange;
    final id = seq++;
    final log = File('${stubDir.path}/calls_$id.log')..writeAsStringSync('');
    final stdinFile = File('${stubDir.path}/refs_$id.txt')
      ..writeAsStringSync(refs.isEmpty ? '' : '${refs.join('\n')}\n');
    final r = runSpawn(
      'sh',
      [
        '-c',
        'PATH="${_toPosixPath(stubDir.path)}:\$PATH"; export PATH; '
            'exec sh scripts/pre-push.sh < "${_toPosixPath(stdinFile.path)}"',
      ],
      why: 'copied scripts/pre-push.sh, refs=$refs tier=$tier full=$prePushFull',
      workingDirectory: dir.path,
      extraEnv: {
        'CONTRACT_SWEEP_SKIP': '1',
        'FLUTTER_STUB_LOG': _toPosixPath(log.path),
        'TIER_STUB': tier ?? '',
        if (prePushFull) 'PRE_PUSH_FULL': '1',
      },
      allowControl: _setOnPurpose,
    );
    final calls = log
        .readAsStringSync()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return _Run(r.exitCode, calls, r.stdout.toString(), r.stderr.toString());
  }

  void expectSkips(_Run r, String what) {
    expect(r.exitCode, 0, reason: '$what\nstdout:\n${r.stdout}\nstderr:\n${r.stderr}');
    expect(r.calls, ['analyze'],
        reason: '$what: the local suite must be SKIPPED but analyze must still run. '
            'Got ${r.calls}\nstdout:\n${r.stdout}');
  }

  void expectRunsSuite(_Run r, String what) {
    expect(r.exitCode, 0, reason: '$what\nstdout:\n${r.stdout}\nstderr:\n${r.stderr}');
    expect(r.calls.first, 'analyze', reason: '$what: analyze must come first. Got ${r.calls}');
    expect(r.calls, contains('test'),
        reason: '$what: the full suite MUST still run here (fail-safe half of the '
            'contract). Got ${r.calls}\nstdout:\n${r.stdout}');
  }

  group('SKIP half: a branch push at a known risky tier', () {
    for (final tier in ['account', 'platform', 'catastrophic']) {
      test('branch-only push at $tier skips the suite, still analyzes', () {
        final r = runHook([_update('refs/heads/speedup-b1')], tier: tier);
        expectSkips(r, 'branch-only at $tier');
        expect(r.stdout, contains('CI on the open PR is the full-suite gate'));
        expect(r.stdout, contains('safe_pr_merge.sh'));
      });
    }

    test('several non-main branches in one push also skip', () {
      final r = runHook(
          [_update('refs/heads/a'), _update('refs/heads/b'), _delete('refs/heads/old')],
          tier: 'platform');
      expectSkips(r, 'update+update+delete of non-main branches');
    });

    test('delete-only push skips even when the pushed range is EMPTY', () {
      // The empty-range guard answers "cannot tell" with the full suite; the
      // delete-only check must sit before it. emptyRange makes origin/main..HEAD
      // empty, which is exactly what a deletion looks like.
      final r = runHook([_delete('refs/heads/stale-branch')], tier: 'platform', repo: emptyRange);
      expectSkips(r, 'delete-only, empty range');
      expect(r.stdout, contains('delete-only'));
    });

    test('the skip message says NO suite has run until a PR exists (no false backstop)', () {
      final r = runHook([_update('refs/heads/speedup-b1')], tier: 'platform');
      expectSkips(r, 'branch-only at platform');
      expect(r.stdout, contains('NO test suite has run'));
      expect(r.stdout, contains('PR into main/develop'));
    });

    test('delete-only push skips even when origin/main does not exist at all', () {
      // The DELETE_ONLY block must sit above the absent-origin/main fail-safe too,
      // not only above the empty-range one.
      final r = runHook([_delete('refs/heads/stale-branch')], tier: 'platform', repo: noOrigin);
      expectSkips(r, 'delete-only, no origin/main');
    });

    test('a 64-zero (sha256) delete is a delete', () {
      final r = runHook(['(delete) ${'0' * 64} refs/heads/stale-branch ${'b' * 64}'],
          tier: 'platform', repo: emptyRange);
      expectSkips(r, '64-zero delete');
    });

    test('feature tier still skips (unchanged behaviour)', () {
      final r = runHook([_update('refs/heads/docs-only')], tier: 'feature');
      expectSkips(r, 'feature tier');
      expect(r.stdout, contains('blast-radius=feature'));
    });
  });

  group('RUN half (the mirror): anything else keeps the full suite', () {
    test('push to main at platform tier runs the suite', () {
      expectRunsSuite(
          runHook([_update('refs/heads/main')], tier: 'platform'), 'push to main');
    });

    test('push to a differently-named local branch INTO remote main runs the suite', () {
      // local ref is a feature branch, REMOTE ref is main: the remote ref is the
      // one that decides.
      expectRunsSuite(
          runHook([_update('refs/heads/speedup-b1', remoteRef: 'refs/heads/main')],
              tier: 'platform'),
          'feature branch pushed to remote main');
    });

    test('push to develop runs the suite', () {
      expectRunsSuite(
          runHook([_update('refs/heads/develop')], tier: 'platform'), 'push to develop');
    });

    test('a tag push runs the suite', () {
      expectRunsSuite(
          runHook([_update('refs/tags/v1.0.0')], tier: 'platform'), 'tag push');
    });

    test('a main ref MIXED in with branches runs the suite', () {
      expectRunsSuite(
          runHook([_update('refs/heads/a'), _update('refs/heads/main')], tier: 'platform'),
          'branch + main');
    });

    test('a sha that merely STARTS with 0 is an update, not a delete (anchor of the zero test)', () {
      // About 1 in 16 real commits start with 0. If the delete detector were
      // unanchored (/^0+/ instead of /^0+$/) an all-such push would classify
      // DELETE_ONLY and skip the suite at ANY tier, including an unknown one.
      for (final sha in ['0${'a' * 39}', '${'0' * 39}1']) {
        final r = runHook(['refs/heads/a $sha refs/heads/a ${'0' * 40}'], tier: null, repo: emptyRange);
        expectRunsSuite(r, 'sha $sha is an update; unknown tier + empty range must run the suite');
      }
    });

    test('a MIXED update+delete push at an unknown tier / empty range runs the suite (not DELETE_ONLY)', () {
      final refs = [_update('refs/heads/a'), _delete('refs/heads/old')];
      expectRunsSuite(runHook(refs, tier: null), 'mixed, unknown tier');
      expectRunsSuite(runHook(refs, tier: 'platform', repo: emptyRange),
          'mixed + empty range: BRANCH_ONLY, and the empty-range guard answers "cannot tell" with the suite');
    });

    test('deleting main is not delete-only-skipped', () {
      expectRunsSuite(
          runHook([_delete('refs/heads/main')], tier: 'platform'), 'delete of main');
    });

    test('empty stdin (the old harness shape) runs the suite', () {
      expectRunsSuite(runHook([], tier: 'platform'), 'empty stdin');
    });

    test('a malformed line (3 fields) runs the suite', () {
      expectRunsSuite(
          runHook(['refs/heads/a $_sha refs/heads/a'], tier: 'platform'), 'malformed line');
    });

    test('a malformed line mixed with a good branch line runs the suite', () {
      expectRunsSuite(
          runHook([_update('refs/heads/a'), 'garbage'], tier: 'platform'),
          'good + garbage');
    });

    test('an UNKNOWN tier on a branch push runs the suite (never skip on uncertainty)', () {
      expectRunsSuite(runHook([_update('refs/heads/a')], tier: null), 'unknown tier');
    });

    test('PRE_PUSH_FULL=1 forces the suite on a branch push', () {
      expectRunsSuite(
          runHook([_update('refs/heads/a')], tier: 'platform', prePushFull: true),
          'PRE_PUSH_FULL=1');
    });

    test('PRE_PUSH_FULL=1 forces the suite even for a delete-only push', () {
      expectRunsSuite(
          runHook([_delete('refs/heads/a')],
              tier: 'platform', prePushFull: true, repo: emptyRange),
          'PRE_PUSH_FULL=1 + delete-only');
    });
  });
}
