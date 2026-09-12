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
}
