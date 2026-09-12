// test/scripts/oi_numbering_gate_e2e_test.dart
//
// END-TO-END coverage for scripts/check_oi_numbering_unique.dart's two 2026-09-12
// additions: Check B' (the working-tree arm, OI-176) and Check C (reservation
// required). Real bare remote, real clones, the real gate spawned with the SDK
// dart. The pure three-point predicate stays covered by oi_numbering_lib_test.

@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) => k.toUpperCase().startsWith('GIT_'));
  return env;
}

ProcessResult _run(String exe, List<String> args, String cwd) => Process.runSync(
      exe, args,
      workingDirectory: cwd,
      environment: _cleanEnv(),
      includeParentEnvironment: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

String _fwd(String p) => p.replaceAll('\\', '/');
String _fileUri(String p) => 'file:///${_fwd(p)}';

/// See test/scripts/cron_registry_snapshot_gate_test.dart:26-58 for why this is
/// NOT Platform.resolvedExecutable (flutter_tester => the suite hangs).
String _dartBin() {
  final override = Platform.environment['DART_BIN_OVERRIDE'];
  if (override != null && File(override).existsSync()) return override;
  final which = Process.runSync(Platform.isWindows ? 'where' : 'which', ['dart'],
      stdoutEncoding: utf8);
  if (which.exitCode == 0) {
    final first = (which.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (first.isNotEmpty) {
      final dir = _fwd(File(first).parent.path);
      for (final c in ['$dir/cache/dart-sdk/bin/dart.exe', '$dir/cache/dart-sdk/bin/dart']) {
        if (File(c).existsSync()) return c;
      }
    }
  }
  return 'dart';
}

const _open = 'docs/audit/open_issues.md';
const _closed = 'docs/audit/closed_issues.md';

String _entry(int n, String title) =>
    '\n## OI-$n — $title\n\n- **Status**: OPEN\n- **Blocked on**: none\n- **Verified**: never\n';

class _Fx {
  _Fx(this.tmp, this.remote, this.integration, this.session);
  final Directory tmp;
  final String remote;
  final String integration; // acts as main's owner
  final String session;     // a fresh session clone, zero commits

  static final _src = Directory.current.path;
  static final _dart = _dartBin();

  static void _must(ProcessResult r, String what) {
    if (r.exitCode != 0) throw StateError('$what (${r.exitCode}):\n${r.stdout}\n${r.stderr}');
  }

  static void _cfg(String repo) {
    _run('git', ['config', 'user.email', 't@example.invalid'], repo);
    _run('git', ['config', 'user.name', 'T'], repo);
  }

  /// main = seed(OI-1..3) -> feature merged with --no-ff, so main's TIP IS A
  /// MERGE COMMIT: the exact HEAD shape a fresh worktree cut from main has
  /// (OI-176). Then a session clone is cut at that tip with zero commits.
  static _Fx create(String tag) {
    final tmp = Directory.systemTemp.createTempSync('oi_gate_${tag}_');
    final remote = '${tmp.path}/remote.git';
    Directory(remote).createSync(recursive: true);
    _must(_run('git', ['init', '-q', '--bare', '-b', 'main', '.'], remote), 'bare');

    final integ = '${tmp.path}/integration';
    Directory(integ).createSync();
    _must(_run('git', ['clone', '-q', _fileUri(remote), '.'], integ), 'clone integ');
    _cfg(integ);
    File('$integ/$_open').createSync(recursive: true);
    File('$integ/$_open').writeAsStringSync(
        '# Open Issues — fixture\n${_entry(1, 'one')}${_entry(2, 'two')}${_entry(3, 'three')}');
    File('$integ/$_closed').writeAsStringSync('# Closed issues\n');
    _must(_run('git', ['add', '-A'], integ), 'add');
    _must(_run('git', ['commit', '-q', '-m', 'seed'], integ), 'seed');
    _must(_run('git', ['checkout', '-q', '-b', 'feature'], integ), 'branch');
    File('$integ/feature.txt').writeAsStringSync('x\n');
    _must(_run('git', ['add', '-A'], integ), 'add2');
    _must(_run('git', ['commit', '-q', '-m', 'feature'], integ), 'feat');
    _must(_run('git', ['checkout', '-q', 'main'], integ), 'co main');
    _must(_run('git', ['merge', '-q', '--no-ff', '-m', 'Merge feature', 'feature'], integ), 'merge');
    _must(_run('git', ['push', '-q', '-u', 'origin', 'main'], integ), 'push');

    final session = '${tmp.path}/session';
    Directory(session).createSync();
    _must(_run('git', ['clone', '-q', _fileUri(remote), '.'], session), 'clone session');
    _cfg(session);
    _must(_run('git', ['checkout', '-q', '-b', 'session'], session), 'session branch');
    return _Fx(tmp, remote, integ, session);
  }

  /// origin/main moves ahead with a new entry; the session fetches so its
  /// origin/main is current while its HEAD is still the merge commit.
  void mainFiles(int n, String title) {
    File('$integration/$_open').writeAsStringSync(
        File('$integration/$_open').readAsStringSync() + _entry(n, title));
    _must(_run('git', ['add', '-A'], integration), 'add main');
    _must(_run('git', ['commit', '-q', '-m', 'file OI-$n'], integration), 'commit main');
    _must(_run('git', ['push', '-q', 'origin', 'main'], integration), 'push main');
    _must(_run('git', ['fetch', '-q', 'origin'], session), 'session fetch');
  }

  void sessionTypes(int n, String title) {
    File('$session/$_open').writeAsStringSync(
        File('$session/$_open').readAsStringSync() + _entry(n, title));
  }

  void reserve(int n) {
    _must(_run('git', ['push', '-q', 'origin', 'HEAD:refs/heads/oi/$n'], session), 'reserve');
    _must(_run('git', ['fetch', '-q', 'origin', '+refs/heads/oi/*:refs/remotes/origin/oi/*'], session),
        'fetch oi');
  }

  ProcessResult gate() =>
      _run(_dart, ['run', '$_src/scripts/check_oi_numbering_unique.dart'], session);

  void dispose() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }
}

void main() {
  test('OI-176 shape: zero-commit worktree whose HEAD is a merge commit, uncommitted board collides with origin/main -> FAIL',
      () {
    final f = _Fx.create('oi176');
    addTearDown(f.dispose);
    f.mainFiles(4, 'main filed four');
    f.sessionTypes(4, 'session filed a different four');
    final r = f.gate();
    final all = '${r.stdout}\n${r.stderr}';
    expect(r.exitCode, isNot(0), reason: all);
    expect(all, contains('OI-4 names two different issues'));
    expect(all, isNot(contains('PASS (vacuous): merge commit')),
        reason: 'the merge-commit arm must not be the one answering about an uncommitted edit');
  });

  test('a title-only edit of an existing entry on the working board is NOT a collision', () {
    final f = _Fx.create('titleedit');
    addTearDown(f.dispose);
    f.mainFiles(4, 'main filed four');
    final p = '${f.session}/$_open';
    File(p).writeAsStringSync(
        File(p).readAsStringSync().replaceFirst('## OI-2 — two', '## OI-2 — two, reworded'));
    final r = f.gate();
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
  });

  test('Check C: a LOCAL-ONLY tracking ref refs/remotes/origin/oi/N satisfies the check with no network', () {
    final f = _Fx.create('localref');
    addTearDown(f.dispose);
    f.sessionTypes(4, 'reserved four');
    // Only the local tracking ref -- nothing on the remote. Pins the
    // no-network short-circuit: step 1 answers, step 2 (ls-remote) never runs.
    expect(_run('git', ['update-ref', 'refs/remotes/origin/oi/4', 'HEAD'], f.session).exitCode, 0);
    final r = f.gate();
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect('${r.stdout}${r.stderr}', isNot(contains('NO reservation')));
  });

  test('Check C: a reservation that exists ONLY on the remote (another clone made it) is found by ls-remote', () {
    final f = _Fx.create('remoteref');
    addTearDown(f.dispose);
    f.sessionTypes(4, 'reserved elsewhere');
    // Reserved from the OTHER clone; the session has NOT fetched oi/*.
    expect(_run('git', ['push', '-q', 'origin', 'HEAD:refs/heads/oi/4'], f.integration).exitCode, 0);
    expect(_run('git', ['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/oi/4'], f.session).exitCode,
        isNot(0), reason: 'fixture: the session must not already hold the ref locally');
    final r = f.gate();
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
  });

  test('Check C at pre-merge-commit (mid-merge, MERGE_HEAD set): an unreserved number on the branch being merged FAILS', () {
    final f = _Fx.create('midmerge');
    addTearDown(f.dispose);
    // The cloud-branch backstop: the branch commits an unreserved number and is
    // merged on the "laptop" (the integration clone) with --no-commit, which is
    // exactly the state the pre-merge-commit hook sees.
    f.sessionTypes(4, 'cloud typed four');
    _run('git', ['add', '-A'], f.session);
    expect(_run('git', ['commit', '-q', '-m', 'file OI-4 unreserved'], f.session).exitCode, 0);
    expect(_run('git', ['push', '-q', 'origin', 'session'], f.session).exitCode, 0);
    expect(_run('git', ['fetch', '-q', 'origin'], f.integration).exitCode, 0);
    expect(_run('git', ['merge', '--no-ff', '--no-commit', 'origin/session'], f.integration).exitCode, 0);
    expect(File('${f.integration}/.git/MERGE_HEAD').existsSync(), isTrue, reason: 'fixture: must be mid-merge');
    final r = _run(_Fx._dart, ['run', '${_Fx._src}/scripts/check_oi_numbering_unique.dart'], f.integration);
    final all = '${r.stdout}\n${r.stderr}';
    expect(r.exitCode, isNot(0), reason: all);
    expect(all, contains('OI-4 is on this board but has NO reservation'));
  });

  test('Check C: a number new on the branch with NO reservation fails, naming the --reserve repair', () {
    final f = _Fx.create('unreserved');
    addTearDown(f.dispose);
    f.sessionTypes(4, 'typed by hand');
    final r = f.gate();
    final all = '${r.stdout}\n${r.stderr}';
    expect(r.exitCode, isNot(0), reason: all);
    expect(all, contains('OI-4 is on this board but has NO reservation'));
    expect(all, contains('mint_oi.sh --reserve 4'));
  });

  test('Check C: no local reservation ref AND remote unreachable -> SKIPPED naming the reservation check (exit 0, UNDETERMINED, no PASS anywhere on stdout)', () {
    final f = _Fx.create('offline');
    addTearDown(f.dispose);
    f.sessionTypes(4, 'cannot be checked');
    Directory(f.remote).renameSync('${f.remote}.gone');
    addTearDown(() {
      try {
        Directory('${f.remote}.gone').renameSync(f.remote);
      } catch (_) {}
    });
    final r = f.gate();
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stderr as String, contains('UNDETERMINED'));
    expect(r.stdout as String, isNot(contains('PASS')),
        reason: 'the vacuous collision PASS must not co-print with a skipped reservation check');
    expect(r.stdout as String, contains('SKIPPED (reservation check)'));
    expect(r.stdout as String, contains('collision check ran'));
    expect('${r.stdout}${r.stderr}', isNot(contains('CI re-runs')),
        reason: 'no later placement re-checks a reservation once the number is published');
  });

  test('Check C: a number already PUBLISHED on origin/main (same title) is exempt — no reservation needed, no collision', () {
    final f = _Fx.create('published');
    addTearDown(f.dispose);
    f.mainFiles(4, 'shared four');
    f.sessionTypes(4, 'shared four'); // same title: the branch carries main's entry
    final r = f.gate();
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect('${r.stdout}${r.stderr}', isNot(contains('NO reservation')));
  });
}
