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
// touches a board or a diagnose doc. `git add -u -- <index>` stages a TRACKED
// index (so today's tracked world is unchanged) and is a silent no-op for an
// untracked one.
//
// Each case names the mutant it kills (rule 21):
//   1a/1b  tracked index is staged            [drop the add; `-u` -> nothing]
//   2a/2b  ignored+untracked index: exit 0,   [`git add -u` -> `git add`, applied
//          built, NOT staged                   separately at the diagnose line
//                                              and at the board line]
//   3      a duplicate `## OI-N` still blocks [builder failure no longer fatal]
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

  setUpAll(() {
    repoRoot = Directory.current.path;
    realDart = _realDart();
    tmp = Directory.systemTemp.createTempSync('precommit_idx_');
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  var n = 0;

  /// A repo with the real hook + builders, a seed commit, and (when [tracked])
  /// stale committed indexes. When not [tracked] both indexes are `.gitignore`d
  /// and absent from the commit.
  String fixture({required bool tracked}) {
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

    // Real dart only for the two builders; every other gate "passes".
    final stub = File('$work/bin/dart');
    stub.writeAsStringSync('#!/bin/sh\n'
        'case "\$*" in\n'
        '  *scripts/build_oi_index.dart*|*scripts/build_bug_index.dart*) exec "$realDart" "\$@" ;;\n'
        'esac\n'
        'exit 0\n');
    _run('chmod', ['+x', stub.path], work);

    File('$work/docs/audit/open_issues.md').writeAsStringSync(_board([1]));
    File('$work/docs/diagnoses/2026-10-01-seed-aaaaaa.md')
        .writeAsStringSync(_diagnoseDoc('aaaaaa', 'seed symptom'));
    if (tracked) {
      File('$work/$_oiIndex').writeAsStringSync('stale oi index\n');
      File('$work/$_bugIndex').writeAsStringSync('stale bug index\n');
    } else {
      File('$work/.gitignore').writeAsStringSync('$_oiIndex\n$_bugIndex\n');
    }
    File('$work/other.txt').writeAsStringSync('committed\n');
    File('$work/docs/audit/other_audit.md').writeAsStringSync('committed\n');
    File('$work/docs/diagnoses/2026-10-01-wip-cccccc.md')
        .writeAsStringSync(_diagnoseDoc('cccccc', 'wip symptom'));
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

  ProcessResult hook(String work) => _run(
        'sh',
        ['scripts/pre-commit.sh'],
        work,
        env: {'PATH': '$work/bin:/usr/bin:/bin'},
      );

  Set<String> staged(String work) => (_run('git', ['diff', '--cached', '--name-only'], work).stdout as String)
      .split('\n')
      .where((l) => l.isNotEmpty)
      .toSet();

  String diag(ProcessResult r) => 'exit=${r.exitCode}\nstdout:\n${r.stdout}\nstderr:\n${r.stderr}';

  void expectWipStaysUnstaged(String work, ProcessResult r) {
    for (final f in const ['other.txt', 'docs/audit/other_audit.md', 'docs/diagnoses/2026-10-01-wip-cccccc.md']) {
      expect(staged(work), isNot(contains(f)),
          reason: 'the exact -- <path> of `git add -u -- <path>` keeps unrelated unstaged edits ($f) out of the commit\n${diag(r)}');
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

  test('1a: board staged, index TRACKED -> OPEN_INDEX.md is staged', () {
    final w = fixture(tracked: true);
    stageBoard(w, [1, 2]);
    final r = hook(w);
    expect(r.exitCode, 0, reason: diag(r));
    expect(staged(w), contains(_oiIndex), reason: 'a tracked index must ride along in the commit\n${diag(r)}');
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
    expectWipStaysUnstaged(w, r);
    expect(_run('git', ['ls-files', '--', _bugIndex], w).stdout, isEmpty);
  });

  for (final tracked in [true, false]) {
    test('3: a duplicate ## OI-N blocks the commit (index ${tracked ? 'tracked' : 'ignored'})', () {
      final w = fixture(tracked: tracked);
      stageBoard(w, [1, 2, 2]);
      final r = hook(w);
      expect(r.exitCode, 1, reason: diag(r));
      expect('${r.stdout}${r.stderr}', contains('build_oi_index.dart errored'), reason: diag(r));
    });
  }
}
