// test/scripts/pre_commit_index_add_e2e_test.dart
//
// Executes the REAL scripts/pre-commit.sh (and the two REAL index builders it
// calls) in a throwaway repo, with a PATH-stub `dart` that runs the real dart
// ONLY for the two builders and exits 0 for every other gate.
//
// WHAT IT PINS. The hook regenerates `docs/diagnoses/INDEX.md` and
// `docs/audit/OPEN_INDEX.md` and stages them. It used to `git add <index>`;
// that exits 1 for a path that is ignored AND untracked, and under `set -e` the
// whole commit dies. The merge-conflict-treadmill plan untracks both indexes
// (they are local build products), and hooks are COPIES, so a machine whose
// installed hook still says plain `git add` would block every commit that
// touches a board or a diagnose doc. The hook now stages an index only when it is
// TRACKED (`git ls-files --error-unmatch` guard, then `git add -u -- <index>`), so
// today's tracked world is unchanged and an untracked one is a silent no-op.
//
// WHY A GUARD AND NOT JUST `git add -u -- <index>`. CI caught it: on the runner's
// git 2.55.0 `git add -u -- <path>` exits 128 ("pathspec ... did not match any
// file(s) known to git") for an ignored, untracked path that exists on disk (the
// one shape CI exercised); this machine's git 2.43.0 exits 0. A fixture that runs
// only the machine's git therefore cannot see the guard being deleted. The hook
// runs with a PATH-stub `git` that reproduces the 2.55.0 answer for that shape,
// passes a plain `git add <path>` to the real git, REFUSES (exit 99) every other
// spelling of `add` it does not model, and logs every call to
// `.git/stub-git.log`, so a case can assert that the hook really went through it.
//
// Each case names the mutant it kills (rule 21):
//   0      the stub git: 128 for `add -u` of an untracked path, 99 for spellings it does not model,
//          the rest passed on
//   1a/1b  tracked index is staged            [drop the add; `-u` -> nothing; the guard inverted;
//          through the stub (log)              the stub dropped from the hook's PATH]
//   2a/2b  ignored+untracked index: exit 0,   [guard removed (always true); `git add -u` -> `git add`,
//          built, NOT staged, no git noise,    each applied separately at the diagnose line and at the
//          guard asked and add never called    board line; the guard's stderr left visible]
//   3      a duplicate `## OI-N` still blocks [builder failure no longer fatal]
//   3b     a failing diagnose builder blocks  [`exit 1` -> `:` at the diagnose builder]
//   4a-4d  ONE index tracked, the other not   [the guard testing the OTHER site's path: both
//                                              sites, both directions]
//   5a/5b  the UNTRACKING commit (deletion    [a guard keyed on HEAD (`git cat-file -e HEAD:<path>`)]
//          staged, path ignored): exit 0,
//          deletion kept
//   5c     untracked and NOT ignored: exit 0, [a guard keyed on `git check-ignore`]
//          never staged
//   6a/6b  a failing add stays FATAL (held    [`git add -u -- <index> || true`]
//          .git/index.lock)
//   7a/7b  tracked index whose rebuilt        [`git add -u` on an unmodified tracked path failing]
//          content is unchanged: exit 0
//
// The fixture deliberately does NOT copy scripts/_dart_bin.sh, so the guard at
// the top of pre-commit.sh falls through to the PATH `dart` (the stub).

@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

const _oiIndex = 'docs/audit/OPEN_INDEX.md';
const _bugIndex = 'docs/diagnoses/INDEX.md';

ProcessResult _run(String exe, List<String> args, String cwd,
    {Map<String, String> env = const {}}) {
  return runSpawn(
    exe,
    args,
    why: 'pre_commit_index_add_e2e: $exe ${args.join(' ')}',
    workingDirectory: cwd,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
    extraEnv: env,
  );
}

void _git(String cwd, List<String> args) {
  final r = _run('git', args, cwd);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed in $cwd:\n${r.stdout}\n${r.stderr}');
  }
}

/// An absolute path to a real dart (the stub execs it for the builders). dartBin() returns an
/// absolute path whenever a dart exists on PATH; a bare name would make the stub exec itself.
String _realDart() {
  final b = dartBin();
  if (!b.contains('/')) throw StateError('no absolute dart path from dartBin(): $b');
  return b;
}

/// An absolute path to the machine's real git (the PATH-stub `git` execs it).
String _realGit(String cwd) {
  final r = _run('sh', ['-c', 'command -v git'], cwd);
  final p = (r.stdout as String).trim();
  if (r.exitCode != 0 || !p.startsWith('/')) throw StateError('no absolute git path: "$p"');
  return p;
}

/// The PATH-stub `git` (see the header). [realGit] is the machine's git; [log] gets one line per call.
String _gitStubSource(String realGit, String log) => '#!/bin/sh\n'
    'printf \'%s\\n\' "\$*" >> "$log"\n'
    'case " \$* " in\n'
    '  *" add "*)\n'
    '    if [ "\$1" != add ]; then\n'
    '      echo "stub git: unmodelled options before add: \$*" >&2\n'
    '      exit 99\n'
    '    fi\n'
    '    if [ "\$2" = -u ] && [ "\$3" = -- ]; then\n'
    '      shift 3\n'
    '      for p in "\$@"; do\n'
    '        "$realGit" ls-files --error-unmatch -- "\$p" >/dev/null 2>&1 || {\n'
    '          echo "error: pathspec \'\$p\' did not match any file(s) known to git" >&2\n'
    '          exit 128\n'
    '        }\n'
    '      done\n'
    '      exec "$realGit" add -u -- "\$@"\n'
    '    fi\n'
    '    case "\$2" in\n'
    '      -*)\n'
    '        echo "stub git: unmodelled add spelling: \$*" >&2\n'
    '        exit 99\n'
    '        ;;\n'
    '    esac\n'
    '    ;;\n'
    'esac\n'
    'exec "$realGit" "\$@"\n';

String _board(List<int> ids, {String note = ''}) {
  final b = StringBuffer('# Open issues\n\n');
  for (final id in ids) {
    b.writeln('## OI-$id — issue $id$note');
    b.writeln();
    b.writeln('- **Status**: OPEN');
    b.writeln('- **Blocked on**: nothing');
    b.writeln('- **Verified**: never');
    b.writeln();
  }
  return b.toString();
}

String _diagnoseDoc(String id, String symptom) => '---\n'
    'bug_id: $id\n'
    'date: 2026-10-01\n'
    'symptom: $symptom\n'
    '---\n'
    '# $id\n';

void main() {
  if (Platform.isWindows) {
    test('POSIX-only (PATH stub dart)', () {}, skip: 'POSIX-only fixture');
    return;
  }

  late Directory tmp;
  late String repoRoot;
  late String realDart;
  late String realGit;

  setUpAll(() {
    repoRoot = Directory.current.path;
    realDart = _realDart();
    tmp = Directory.systemTemp.createTempSync('precommit_idx_');
    realGit = _realGit(tmp.path);
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  var n = 0;

  /// A repo with the real hook + builders, a seed commit, and (when tracked)
  /// stale committed indexes. An index that is not tracked is `.gitignore`d
  /// (unless [ignoreUntracked] is false) and absent from the commit. [tracked] sets
  /// both; [trackedOi] / [trackedBug] override one (the mixed fixtures of cases
  /// 4a-4d). [seedBuilt] commits the REAL builder output instead of stale text, so
  /// a rebuild can come out identical. [breakBugBuilder] makes the diagnose builder
  /// fail to compile.
  String fixture({
    bool tracked = true,
    bool? trackedOi,
    bool? trackedBug,
    bool ignoreUntracked = true,
    bool seedBuilt = false,
    bool breakBugBuilder = false,
  }) {
    final oiTracked = trackedOi ?? tracked;
    final bugTracked = trackedBug ?? tracked;
    final work = '${tmp.path}/w${n++}';
    Directory(work).createSync(recursive: true);
    _git(work, ['init', '-b', 'main', '.']);
    _git(work, ['config', 'user.email', 't@t.t']);
    _git(work, ['config', 'user.name', 't']);
    _git(work, ['config', 'commit.gpgsign', 'false']);

    Directory('$work/scripts').createSync(recursive: true);
    Directory('$work/docs/audit').createSync(recursive: true);
    Directory('$work/docs/diagnoses').createSync(recursive: true);
    Directory('$work/bin').createSync(recursive: true);
    for (final f in const [
      'scripts/pre-commit.sh',
      'scripts/build_oi_index.dart',
      'scripts/build_bug_index.dart',
      'scripts/bug_index_lib.dart',
    ]) {
      File('$repoRoot/$f').copySync('$work/$f');
    }
    if (breakBugBuilder) {
      File('$work/scripts/bug_index_lib.dart').writeAsStringSync('this is not dart\n');
    }

    // Real dart only for the two builders; every other gate "passes".
    final stub = File('$work/bin/dart');
    stub.writeAsStringSync('#!/bin/sh\n'
        'case "\$*" in\n'
        '  *scripts/build_oi_index.dart*|*scripts/build_bug_index.dart*) exec "$realDart" "\$@" ;;\n'
        'esac\n'
        'exit 0\n');
    _run('chmod', ['+x', stub.path], work);

    // The git stub (see _gitStubSource and the header).
    final gitStub = File('$work/bin/git');
    gitStub.writeAsStringSync(_gitStubSource(realGit, '$work/.git/stub-git.log'));
    _run('chmod', ['+x', gitStub.path], work);

    File('$work/docs/audit/open_issues.md').writeAsStringSync(_board([1]));
    File('$work/docs/diagnoses/2026-10-01-seed-aaaaaa.md')
        .writeAsStringSync(_diagnoseDoc('aaaaaa', 'seed symptom'));
    File('$work/other.txt').writeAsStringSync('committed\n');
    File('$work/docs/audit/other_audit.md').writeAsStringSync('committed\n');
    File('$work/docs/diagnoses/2026-10-01-wip-cccccc.md')
        .writeAsStringSync(_diagnoseDoc('cccccc', 'wip symptom'));
    final ignored = <String>[];
    if (oiTracked) {
      if (seedBuilt) {
        final r = _run(realDart, ['run', 'scripts/build_oi_index.dart'], work);
        if (r.exitCode != 0) throw StateError('seed build_oi_index failed:\n${r.stdout}\n${r.stderr}');
      } else {
        File('$work/$_oiIndex').writeAsStringSync('stale oi index\n');
      }
    } else {
      ignored.add(_oiIndex);
    }
    if (bugTracked) {
      if (seedBuilt) {
        final r = _run(realDart, ['run', 'scripts/build_bug_index.dart'], work);
        if (r.exitCode != 0) throw StateError('seed build_bug_index failed:\n${r.stdout}\n${r.stderr}');
      } else {
        File('$work/$_bugIndex').writeAsStringSync('stale bug index\n');
      }
    } else {
      ignored.add(_bugIndex);
    }
    if (ignored.isNotEmpty && ignoreUntracked) {
      File('$work/.gitignore').writeAsStringSync('${ignored.join('\n')}\n');
    }
    _git(work, ['add', '-A']);
    _git(work, ['commit', '-m', 'seed']);
    // Unrelated WIP on TRACKED files, left unstaged, in the repo root AND in both index
    // directories: a bare `git add -u` sweeps the first, a pathspec widened to the directory
    // (`git add -u -- docs/audit`) sweeps the others. The diagnose WIP edit keeps valid frontmatter.
    File('$work/other.txt').writeAsStringSync('unstaged work in progress\n');
    File('$work/docs/audit/other_audit.md').writeAsStringSync('unstaged audit edit\n');
    File('$work/docs/diagnoses/2026-10-01-wip-cccccc.md')
        .writeAsStringSync('${_diagnoseDoc('cccccc', 'wip symptom')}unstaged body edit\n');
    return work;
  }

  // LC_ALL=C: the no-noise assertions below look for git's English wording.
  ProcessResult hook(String work) => _run(
        'sh',
        ['scripts/pre-commit.sh'],
        work,
        env: {'PATH': '$work/bin:/usr/bin:/bin', 'LC_ALL': 'C'},
      );

  Set<String> staged(String work) => (_run('git', ['diff', '--cached', '--name-only'], work).stdout as String)
      .split('\n')
      .where((l) => l.isNotEmpty)
      .toSet();

  /// Every call the hook made through the stub git, one argv per line.
  List<String> stubCalls(String work) {
    final f = File('$work/.git/stub-git.log');
    return f.existsSync() ? f.readAsLinesSync() : const [];
  }

  String diag(ProcessResult r) => 'exit=${r.exitCode}\nstdout:\n${r.stdout}\nstderr:\n${r.stderr}';

  /// The hook went through the stub, ASKED whether [index] is tracked, and called `git add -u`
  /// on it exactly when it is.
  void expectGuardCalls(String work, ProcessResult r, String index, {required bool tracked}) {
    final calls = stubCalls(work);
    expect(calls, contains('ls-files --error-unmatch -- $index'),
        reason: 'the hook must ask git whether the index is tracked, THROUGH the stub\ncalls: $calls\n${diag(r)}');
    if (tracked) {
      expect(calls, contains('add -u -- $index'), reason: 'a tracked index is staged with add -u\ncalls: $calls\n${diag(r)}');
    } else {
      expect(calls.where((c) => c.startsWith('add ')), isEmpty,
          reason: 'an untracked index must never reach git add\ncalls: $calls\n${diag(r)}');
    }
  }

  void expectWipStaysUnstaged(String work, ProcessResult r) {
    for (final f in const ['other.txt', 'docs/audit/other_audit.md', 'docs/diagnoses/2026-10-01-wip-cccccc.md']) {
      expect(staged(work), isNot(contains(f)),
          reason: 'the exact -- <path> of `git add -u -- <path>` keeps unrelated unstaged edits ($f) out of the commit\n${diag(r)}');
    }
  }

  /// The guard asks git "is this tracked?" and must swallow the answer: a normal untracked index
  /// is not an error, and a line saying so in every commit's output would read as one.
  void expectNoGitNoise(ProcessResult r) {
    final out = '${r.stdout}${r.stderr}';
    for (final noise in const ['pathspec', 'did not match', 'Did you forget to']) {
      expect(out, isNot(contains(noise)), reason: 'git noise leaked from the tracked-only guard\n${diag(r)}');
    }
  }

  void stageBoard(String work, List<int> ids) {
    File('$work/docs/audit/open_issues.md').writeAsStringSync(_board(ids));
    _git(work, ['add', 'docs/audit/open_issues.md']);
  }

  void stageDiagnose(String work) {
    File('$work/docs/diagnoses/2026-10-02-second-bbbbbb.md')
        .writeAsStringSync(_diagnoseDoc('bbbbbb', 'second symptom'));
    _git(work, ['add', 'docs/diagnoses/2026-10-02-second-bbbbbb.md']);
  }

  test('0: the stub git: 128 for `add -u` of an untracked path, 99 for spellings it does not model, the rest passed on', () {
    final w = fixture(tracked: false);
    // The ignored, untracked index exists on disk, as it does once the hook has built it.
    File('$w/$_oiIndex').writeAsStringSync('built\n');
    final stub = '$w/bin/git';
    final bad = _run(stub, ['add', '-u', '--', _oiIndex], w);
    expect(bad.exitCode, 128, reason: diag(bad));
    expect('${bad.stderr}', contains("pathspec '$_oiIndex' did not match any file(s) known to git"));
    final ok = _run(stub, ['add', '-u', '--', 'other.txt'], w);
    expect(ok.exitCode, 0, reason: diag(ok));
    expect(staged(w), contains('other.txt'), reason: 'a tracked path is passed to the real git');
    // Spellings the stub does not model fail LOUDLY (99) instead of passing untouched.
    for (final args in const [
      ['add', '--update', '--', 'other.txt'],
      ['add', '-uv', '--', 'other.txt'],
      ['add', '-u', 'other.txt'],
      ['-C', '.', 'add', '-u', '--', 'other.txt'],
    ]) {
      final r = _run(stub, args, w);
      expect(r.exitCode, 99, reason: 'unmodelled spelling ${args.join(' ')} must trip the stub\n${diag(r)}');
    }
    // A plain `git add <path>` and any other command go to the real git.
    final plain = _run(stub, ['add', 'other.txt'], w);
    expect(plain.exitCode, 0, reason: diag(plain));
    final rev = _run(stub, ['rev-parse', '--is-inside-work-tree'], w);
    expect(rev.exitCode, 0, reason: diag(rev));
    expect((rev.stdout as String).trim(), 'true');
    expect(stubCalls(w), contains('add -u -- other.txt'), reason: 'the stub logs every call it receives');
  });

  test('1a: board staged, index TRACKED -> OPEN_INDEX.md is staged', () {
    final w = fixture(tracked: true);
    stageBoard(w, [1, 2]);
    final r = hook(w);
    expect(r.exitCode, 0, reason: diag(r));
    expect(staged(w), contains(_oiIndex), reason: 'a tracked index must ride along in the commit\n${diag(r)}');
    expectGuardCalls(w, r, _oiIndex, tracked: true);
    expectWipStaysUnstaged(w, r);
    expect(File('$w/$_oiIndex').readAsStringSync(), isNot('stale oi index\n'),
        reason: 'the index must have been REBUILT, not just staged stale');
  });

  test('1b: diagnose doc staged, index TRACKED -> INDEX.md is staged', () {
    final w = fixture(tracked: true);
    stageDiagnose(w);
    final r = hook(w);
    expect(r.exitCode, 0, reason: diag(r));
    expect(staged(w), contains(_bugIndex), reason: diag(r));
    expectGuardCalls(w, r, _bugIndex, tracked: true);
    expectWipStaysUnstaged(w, r);
    expect(File('$w/$_bugIndex').readAsStringSync(), contains('second symptom'));
  });

  test('2a: board staged, OPEN_INDEX.md ignored+untracked -> exit 0, built, NOT staged', () {
    final w = fixture(tracked: false);
    stageBoard(w, [1, 2]);
    final r = hook(w);
    expect(r.exitCode, 0,
        reason: 'a plain `git add` of an ignored path exits 1 and kills the commit\n${diag(r)}');
    expect(File('$w/$_oiIndex').existsSync(), isTrue, reason: 'the index is still built locally\n${diag(r)}');
    expect(staged(w), isNot(contains(_oiIndex)));
    expectGuardCalls(w, r, _oiIndex, tracked: false);
    expectNoGitNoise(r);
    expectWipStaysUnstaged(w, r);
    expect(_run('git', ['ls-files', '--', _oiIndex], w).stdout, isEmpty);
  });

  test('2b: diagnose doc staged, INDEX.md ignored+untracked -> exit 0, built, NOT staged', () {
    final w = fixture(tracked: false);
    stageDiagnose(w);
    final r = hook(w);
    expect(r.exitCode, 0, reason: diag(r));
    expect(File('$w/$_bugIndex').existsSync(), isTrue, reason: diag(r));
    expect(staged(w), isNot(contains(_bugIndex)));
    expectGuardCalls(w, r, _bugIndex, tracked: false);
    expectNoGitNoise(r);
    expectWipStaysUnstaged(w, r);
    expect(_run('git', ['ls-files', '--', _bugIndex], w).stdout, isEmpty);
  });

  // 4a-4d: ONE index tracked and the other not. With both tracked (or both untracked) a guard that
  // tests the OTHER site's path still behaves; only a mixed fixture tells the two sites apart.
  for (final c in const [
    (id: '4a', board: true, oiTracked: true, bugTracked: false),
    (id: '4b', board: true, oiTracked: false, bugTracked: true),
    (id: '4c', board: false, oiTracked: false, bugTracked: true),
    (id: '4d', board: false, oiTracked: true, bugTracked: false),
  ]) {
    final what = c.board ? 'board' : 'diagnose doc';
    test('${c.id}: $what staged, OPEN_INDEX.md ${c.oiTracked ? 'tracked' : 'ignored'}, '
        'INDEX.md ${c.bugTracked ? 'tracked' : 'ignored'}', () {
      final w = fixture(trackedOi: c.oiTracked, trackedBug: c.bugTracked);
      if (c.board) {
        stageBoard(w, [1, 2]);
      } else {
        stageDiagnose(w);
      }
      final r = hook(w);
      expect(r.exitCode, 0, reason: diag(r));
      final index = c.board ? _oiIndex : _bugIndex;
      final indexTracked = c.board ? c.oiTracked : c.bugTracked;
      expect(File('$w/$index').existsSync(), isTrue, reason: 'built either way\n${diag(r)}');
      if (indexTracked) {
        expect(staged(w), contains(index), reason: 'a tracked index rides along\n${diag(r)}');
      } else {
        expect(staged(w), isNot(contains(index)), reason: 'an untracked index is not staged\n${diag(r)}');
      }
      expectGuardCalls(w, r, index, tracked: indexTracked);
      expectNoGitNoise(r);
      expectWipStaysUnstaged(w, r);
    });
  }

  // 5a/5b: the commit that UNTRACKS the indexes (landing A2's own commit): the deletion is staged, the
  // path is ignored, HEAD still has the file. A guard keyed on HEAD would call `git add -u` on a path the
  // index no longer holds.
  for (final board in [true, false]) {
    test('5${board ? 'a' : 'b'}: the untracking commit, ${board ? 'board' : 'diagnose doc'} staged -> exit 0, '
        'deletions stay staged', () {
      final w = fixture(tracked: true);
      _git(w, ['rm', '--cached', '-q', _oiIndex, _bugIndex]);
      File('$w/.gitignore').writeAsStringSync('$_oiIndex\n$_bugIndex\n');
      if (board) {
        stageBoard(w, [1, 2]);
      } else {
        stageDiagnose(w);
      }
      final r = hook(w);
      expect(r.exitCode, 0, reason: diag(r));
      final status = _run('git', ['diff', '--cached', '--name-status'], w).stdout as String;
      expect(status, contains('D\t$_oiIndex'), reason: 'the staged deletion must survive\n$status\n${diag(r)}');
      expect(status, contains('D\t$_bugIndex'), reason: 'the staged deletion must survive\n$status\n${diag(r)}');
      final index = board ? _oiIndex : _bugIndex;
      expect(File('$w/$index').existsSync(), isTrue, reason: 'still built locally\n${diag(r)}');
      expect(_run('git', ['ls-files', '--', index], w).stdout, isEmpty);
      expectGuardCalls(w, r, index, tracked: false);
      expectNoGitNoise(r);
      expectWipStaysUnstaged(w, r);
    });
  }

  // 5c: untracked and NOT ignored. The old plain `git add` would have staged it; the hook never adds an
  // untracked index (they are local build products). A guard keyed on `git check-ignore` calls add here.
  test('5c: index untracked and NOT ignored -> exit 0, built, never staged', () {
    final w = fixture(tracked: false, ignoreUntracked: false);
    stageBoard(w, [1, 2]);
    final r = hook(w);
    expect(r.exitCode, 0, reason: diag(r));
    expect(File('$w/$_oiIndex').existsSync(), isTrue, reason: diag(r));
    expect(staged(w), isNot(contains(_oiIndex)), reason: diag(r));
    expect(_run('git', ['ls-files', '--', _oiIndex], w).stdout, isEmpty);
    expectGuardCalls(w, r, _oiIndex, tracked: false);
    expectNoGitNoise(r);
    expectWipStaysUnstaged(w, r);
  });

  // 6a/6b: the guard decides WHETHER to stage; a `git add` that then fails (here: a held index.lock)
  // must still kill the commit, as it did before the guard. `... || true` would swallow it and commit a
  // stale index.
  for (final board in [true, false]) {
    test('6${board ? 'a' : 'b'}: ${board ? 'board' : 'diagnose doc'} staged, index tracked, '
        '.git/index.lock held -> the failing add stays FATAL', () {
      final w = fixture(tracked: true);
      if (board) {
        stageBoard(w, [1, 2]);
      } else {
        stageDiagnose(w);
      }
      File('$w/.git/index.lock').createSync();
      final r = hook(w);
      expect(r.exitCode, isNot(0), reason: 'a failing git add must not be swallowed\n${diag(r)}');
      expect('${r.stdout}${r.stderr}', contains('index.lock'), reason: diag(r));
      expectGuardCalls(w, r, board ? _oiIndex : _bugIndex, tracked: true);
    });
  }

  for (final tracked in [true, false]) {
    test('3: a duplicate ## OI-N blocks the commit (index ${tracked ? 'tracked' : 'ignored'})', () {
      final w = fixture(tracked: tracked);
      stageBoard(w, [1, 2, 2]);
      final r = hook(w);
      expect(r.exitCode, 1, reason: diag(r));
      expect('${r.stdout}${r.stderr}', contains('build_oi_index.dart errored'), reason: diag(r));
    });

    test('3b: a diagnose builder that fails blocks the commit (index ${tracked ? 'tracked' : 'ignored'})', () {
      final w = fixture(tracked: tracked, breakBugBuilder: true);
      stageDiagnose(w);
      final r = hook(w);
      expect(r.exitCode, 1, reason: diag(r));
      expect('${r.stdout}${r.stderr}', contains('build_bug_index.dart errored'), reason: diag(r));
    });
  }

  // 7a/7b: the commonest real case: the index is tracked and the rebuild comes out IDENTICAL to the
  // committed one, so `git add -u` has nothing to stage. It must still exit 0.
  test('7a: board staged (comment only), tracked index rebuilds IDENTICAL -> exit 0, nothing staged for it', () {
    final w = fixture(tracked: true, seedBuilt: true);
    final seeded = File('$w/$_oiIndex').readAsStringSync();
    File('$w/docs/audit/open_issues.md').writeAsStringSync('${_board([1])}\n<!-- a comment, not an issue -->\n');
    _git(w, ['add', 'docs/audit/open_issues.md']);
    final r = hook(w);
    expect(r.exitCode, 0, reason: diag(r));
    expect(File('$w/$_oiIndex').readAsStringSync(), seeded, reason: 'the premise: the rebuild is identical\n${diag(r)}');
    expect(staged(w), isNot(contains(_oiIndex)), reason: diag(r));
    expectGuardCalls(w, r, _oiIndex, tracked: true);
    expectWipStaysUnstaged(w, r);
  });

  test('7b: diagnose doc body edited (frontmatter unchanged), tracked index rebuilds IDENTICAL -> exit 0', () {
    final w = fixture(tracked: true, seedBuilt: true);
    final seeded = File('$w/$_bugIndex').readAsStringSync();
    final doc = File('$w/docs/diagnoses/2026-10-01-seed-aaaaaa.md');
    doc.writeAsStringSync('${doc.readAsStringSync()}a body line that the index does not carry\n');
    _git(w, ['add', 'docs/diagnoses/2026-10-01-seed-aaaaaa.md']);
    final r = hook(w);
    expect(r.exitCode, 0, reason: diag(r));
    expect(File('$w/$_bugIndex').readAsStringSync(), seeded, reason: 'the premise: the rebuild is identical\n${diag(r)}');
    expect(staged(w), isNot(contains(_bugIndex)), reason: diag(r));
    expectGuardCalls(w, r, _bugIndex, tracked: true);
    expectWipStaysUnstaged(w, r);
  });
}
