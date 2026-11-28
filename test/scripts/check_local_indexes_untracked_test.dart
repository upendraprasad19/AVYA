// test/scripts/check_local_indexes_untracked_test.dart
//
// Executes the REAL scripts/check_local_indexes_untracked.dart in a throwaway git repo (landing
// A2 of the merge-conflict-treadmill plan). The gate fails when docs/audit/OPEN_INDEX.md or
// docs/diagnoses/INDEX.md is TRACKED again: a `.gitignore` line does not stop `git add -f`, a
// merge that brings the path back, or a pre-A2 branch that edited an index and was merged
// (a modify/delete conflict resolved the wrong way), and a tracked copy brings back the very
// conflicts the untracking removed.
//
// Each case names the mutant it kills (rule 21):
//   untracked (and ignored)                   -> 0 PASS    [the gate always fails]
//   OI index tracked / bug index tracked      -> 1, naming ONLY that path   [one path dropped]
//   both tracked                              -> 1, naming both
//   UNMERGED (a conflicted merge)             -> 1, ONE path   [the de-duplication dropped: one line per stage]
//   STAGED add, not yet committed             -> 1         [reads HEAD instead of the index]
//   the untracking commit (`git rm --cached`) -> 0         [reads HEAD instead of the index]
//   a look-alike name tracked                 -> 0         [a prefix / substring match]
//   `--warn-only`                             -> 0 + WARN  [the flag ignored]
//   no git repository                         -> 0 + NOTE  [fails closed on a git problem]
//   no git binary on PATH (index tracked)     -> 0 + NOTE  [the `catch` arm made fatal: only the
//                                                           exit-code arm was exercised before]
//
// The gate lives in the pre-commit loop and in CI's Audit Gates, so a case is also the proof that
// it passes on a clean tree. The ledger entry (docs/audit/gate_test_ledger.yaml) names this file.

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/script_closure_fixture.dart';
import '../helpers/spawn.dart';

const _oi = 'docs/audit/OPEN_INDEX.md';
const _bug = 'docs/diagnoses/INDEX.md';

ProcessResult _run(String exe, List<String> args, String cwd, {Map<String, String> env = const {}}) =>
    runSpawn(
      exe,
      args,
      why: 'check_local_indexes_untracked_test: $exe ${args.join(' ')}',
      workingDirectory: cwd,
      extraEnv: env,
      stdoutEncoding: systemEncoding,
      stderrEncoding: systemEncoding,
    );

String _diag(ProcessResult r) => 'exit=${r.exitCode}\nstdout:\n${r.stdout}\nstderr:\n${r.stderr}';

void main() {
  late String repoRoot;
  late Directory tmp;
  var n = 0;

  setUpAll(() {
    repoRoot = Directory.current.path;
    tmp = Directory.systemTemp.createTempSync('untracked_gate_');
  });
  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// A repo with the gate (and what it imports) copied in, one seed commit, and the two index
  /// files on disk and IGNORED, as they are after an A2 build.
  String fixture({bool git = true}) {
    final w = '${tmp.path}/w${n++}';
    Directory(w).createSync(recursive: true);
    copyScriptClosure(repoRoot, w, const ['scripts/check_local_indexes_untracked.dart']);
    for (final f in const [_oi, _bug]) {
      File('$w/$f')
        ..createSync(recursive: true)
        ..writeAsStringSync('built\n');
    }
    File('$w/.gitignore').writeAsStringSync('$_oi\n$_bug\n');
    File('$w/other.txt').writeAsStringSync('x\n');
    if (git) {
      for (final a in const [
        ['init', '-b', 'main', '.'],
        ['config', 'user.email', 't@t.t'],
        ['config', 'user.name', 't'],
        ['config', 'commit.gpgsign', 'false'],
        ['add', '-A'],
        ['commit', '-m', 'seed'],
      ]) {
        final r = _run('git', a, w);
        if (r.exitCode != 0) throw StateError('git ${a.join(' ')}: ${_diag(r)}');
      }
    }
    return w;
  }

  ProcessResult gate(String w, [List<String> args = const []]) =>
      _run(dartBin(), ['run', 'scripts/check_local_indexes_untracked.dart', ...args], w);

  void forceAdd(String w, String path) {
    final r = _run('git', ['add', '-f', path], w);
    if (r.exitCode != 0) throw StateError(_diag(r));
  }

  test('both indexes untracked (and ignored) -> exit 0, PASS', () {
    final w = fixture();
    final r = gate(w);
    expect(r.exitCode, 0, reason: _diag(r));
    expect('${r.stdout}', contains('PASS'));
  });

  test('the OI index tracked -> exit 1, naming that path and not the other', () {
    final w = fixture();
    forceAdd(w, _oi);
    final r = gate(w);
    expect(r.exitCode, 1, reason: _diag(r));
    expect('${r.stderr}', contains(_oi));
    expect(RegExp(r'^\s+- ' + RegExp.escape(_bug) + r'$', multiLine: true).hasMatch('${r.stderr}'), isFalse);
  });

  test('the diagnose index tracked -> exit 1, naming that path and not the other', () {
    final w = fixture();
    forceAdd(w, _bug);
    final r = gate(w);
    expect(r.exitCode, 1, reason: _diag(r));
    expect(RegExp(r'^\s+- ' + RegExp.escape(_bug) + r'$', multiLine: true).hasMatch('${r.stderr}'), isTrue,
        reason: _diag(r));
    expect(RegExp(r'^\s+- ' + RegExp.escape(_oi) + r'$', multiLine: true).hasMatch('${r.stderr}'), isFalse);
  });

  test('both tracked -> exit 1, naming both, with the one-line fix', () {
    final w = fixture();
    forceAdd(w, _oi);
    forceAdd(w, _bug);
    final r = gate(w);
    expect(r.exitCode, 1, reason: _diag(r));
    expect('${r.stderr}', contains('2 generated index(es) are TRACKED'));
    expect('${r.stderr}', contains('git rm --cached -- $_oi $_bug'),
        reason: 'the message must carry the exact fix, in index order');
  });

  test('an UNMERGED index (a conflicted merge) is reported once, not once per stage', () {
    final w = fixture();
    forceAdd(w, _oi);
    expect(_run('git', ['commit', '-m', 'main tracks it'], w).exitCode, 0);
    for (final a in const [
      ['checkout', '-q', '-b', 'other', 'HEAD~1'],
    ]) {
      final c = _run('git', a, w);
      if (c.exitCode != 0) throw StateError('git ${a.join(' ')}: ${_diag(c)}');
    }
    File('$w/$_oi')
      ..createSync(recursive: true)
      ..writeAsStringSync('the other branch\n');
    forceAdd(w, _oi);
    expect(_run('git', ['commit', '-m', 'other tracks it'], w).exitCode, 0);
    expect(_run('git', ['checkout', '-q', 'main'], w).exitCode, 0);
    final merge = _run('git', ['merge', '--no-edit', 'other'], w);
    expect(merge.exitCode, isNot(0), reason: 'the fixture must be an add/add conflict\n${_diag(merge)}');
    final unmerged = (_run('git', ['ls-files', '-u', '--', _oi], w).stdout as String)
        .trim()
        .split('\n');
    expect(unmerged.length, greaterThan(1), reason: 'the fixture must hold SEVERAL stages of the path');
    final r = gate(w);
    expect(r.exitCode, 1, reason: _diag(r));
    expect('${r.stderr}', contains('1 generated index(es) are TRACKED'),
        reason: 'one path, however many stages it has\n${_diag(r)}');
    expect(RegExp(r'^\s+- ' + RegExp.escape(_oi) + r'$', multiLine: true).allMatches('${r.stderr}'),
        hasLength(1));
    expect('${r.stderr}', contains('git rm --cached -- $_oi\n'),
        reason: 'the fix names the path once');
  });

  test('a STAGED add that is not committed yet is caught (the gate reads the index, not HEAD)', () {
    final w = fixture();
    forceAdd(w, _oi);
    expect((_run('git', ['status', '--porcelain'], w).stdout as String), contains('A  $_oi'));
    final r = gate(w);
    expect(r.exitCode, 1, reason: _diag(r));
  });

  test('the UNTRACKING commit: a tracked index with its deletion staged -> exit 0', () {
    final w = fixture();
    forceAdd(w, _oi);
    expect(_run('git', ['commit', '-m', 'track it'], w).exitCode, 0);
    expect(gate(w).exitCode, 1, reason: 'tracked in HEAD and in the index');
    final rm = _run('git', ['rm', '--cached', '-q', '--', _oi], w);
    expect(rm.exitCode, 0, reason: _diag(rm));
    final r = gate(w);
    expect(r.exitCode, 0,
        reason: 'the commit that untracks must be able to pass its own gate (HEAD still has the path)\n${_diag(r)}');
  });

  test('a look-alike name is not the index (exact paths only)', () {
    final w = fixture();
    File('$w/$_oi.bak').writeAsStringSync('x');
    File('$w/docs/audit/OPEN_INDEX.md.d').createSync();
    final r1 = _run('git', ['add', '-f', '$_oi.bak', 'docs/audit/OPEN_INDEX.md.d'], w);
    expect(r1.exitCode, 0, reason: _diag(r1));
    final r = gate(w);
    expect(r.exitCode, 0, reason: _diag(r));
  });

  test('--warn-only never fails, and says WARN', () {
    final w = fixture();
    forceAdd(w, _oi);
    final r = gate(w, const ['--warn-only']);
    expect(r.exitCode, 0, reason: _diag(r));
    expect('${r.stderr}', contains('[local-indexes-untracked WARN]'));
    expect('${r.stderr}', contains(_oi));
  });

  test('outside a git repository the gate fails OPEN with a NOTE', () {
    final w = fixture(git: false);
    final r = gate(w);
    expect(r.exitCode, 0, reason: _diag(r));
    expect('${r.stdout}', contains('NOTE'));
  });

  test('with NO git on PATH at all the gate fails OPEN with a NOTE (the `catch` arm, not the exit-code arm)', () {
    // `git ls-files` failing and `git` not existing are two different branches of the gate. Even a
    // TRACKED index must not wedge a commit on a machine that cannot run git: the hook that runs
    // this gate is itself run by git, but CI images and archive trees are not.
    final w = fixture();
    forceAdd(w, _oi);
    final emptyBin = Directory('${tmp.path}/emptybin${n++}')..createSync();
    final r = _run(dartBin(), ['run', 'scripts/check_local_indexes_untracked.dart'], w,
        env: {'PATH': emptyBin.path});
    expect(r.exitCode, 0,
        reason: 'a tracked index is invisible without git, and the gate must say so rather than fail\n${_diag(r)}');
    expect('${r.stdout}', contains('git is not available'));
  });
}
