// test/scripts/discipline_hook_oi_line_e2e_test.dart
//
// The SessionStart hook must tell every session the next free OI number (as
// of the last sync -- it reads LOCAL refs only, no fetch: spec §3.4/§7.4) and
// the one command to mint with, and must stay SILENT (not wrong) when there is
// no origin/main to read.

@Timeout(Duration(minutes: 6))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) => k.toUpperCase().startsWith('GIT_'));
  return env;
}

ProcessResult _git(List<String> args, String cwd) => Process.runSync('git', args,
    workingDirectory: cwd,
    environment: _cleanEnv(),
    includeParentEnvironment: false,
    stdoutEncoding: utf8,
    stderrEncoding: utf8);

String _fwd(String p) => p.replaceAll('\\', '/');

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

String _entry(int n, String t) =>
    '\n## OI-$n — $t\n\n- **Status**: OPEN\n- **Blocked on**: none\n- **Verified**: never\n';

Future<String> _hookOutput(String dart, String src, String cwd, String stdinJson) async {
  final p = await Process.start(dart, ['run', '$src/scripts/discipline_hook.dart'],
      workingDirectory: cwd, environment: _cleanEnv(), includeParentEnvironment: false);
  p.stdin.write(stdinJson);
  await p.stdin.close();
  final out = p.stdout.transform(utf8.decoder).join();
  unawaited(p.stderr.drain<void>());
  await p.exitCode;
  return out;
}

void main() {
  final src = Directory.current.path;
  final dart = _dartBin();
  const startup = '{"hook_event_name":"SessionStart","source":"startup"}';

  late Directory tmp;
  late String remote;
  late String clone;
  late String other;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('hook_oi_');
    remote = '${tmp.path}/remote.git';
    clone = '${tmp.path}/clone';
    other = '${tmp.path}/other';
    Directory(remote).createSync();
    expect(_git(['init', '-q', '--bare', '-b', 'main', '.'], remote).exitCode, 0);
    for (final c in [clone, other]) {
      Directory(c).createSync();
      expect(_git(['clone', '-q', 'file:///${_fwd(remote)}', '.'], c).exitCode, 0);
      _git(['config', 'user.email', 't@example.invalid'], c);
      _git(['config', 'user.name', 'T'], c);
    }
    File('$clone/docs/audit/open_issues.md').createSync(recursive: true);
    File('$clone/docs/audit/open_issues.md')
        .writeAsStringSync('# board\n${_entry(1, 'a')}${_entry(2, 'b')}${_entry(3, 'c')}${_entry(4, 'd')}');
    File('$clone/docs/audit/closed_issues.md').writeAsStringSync('# closed\n');
    expect(_git(['add', '-A'], clone).exitCode, 0);
    expect(_git(['commit', '-q', '-m', 'seed'], clone).exitCode, 0);
    expect(_git(['push', '-q', '-u', 'origin', 'main'], clone).exitCode, 0);
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('prints next free = max(published board, working board, LOCAL reservation refs)+1 and the unfiled list', () async {
    // A reservation made from THIS clone: git updates refs/remotes/origin/oi/5
    // on a successful push, so it is local without any fetch.
    expect(_git(['push', '-q', 'origin', 'HEAD:refs/heads/oi/5'], clone).exitCode, 0);
    expect(_git(['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/oi/5'], clone).exitCode, 0,
        reason: 'fixture: the push must have updated the local tracking ref');
    final out = await _hookOutput(dart, src, clone, startup);
    expect(out, contains('OI board: next free number is at least 6'));
    expect(out, contains('Reserved-but-unfiled: oi/5 ['));
    expect(out, contains('sh scripts/mint_oi.sh'));
  });

  test('a reservation filed on a SIBLING local branch is not listed as unfiled', () async {
    expect(_git(['checkout', '-q', '-b', 'sib'], clone).exitCode, 0);
    expect(_git(['push', '-q', 'origin', 'HEAD:refs/heads/oi/9'], clone).exitCode, 0);
    File('$clone/docs/audit/open_issues.md')
        .writeAsStringSync(File('$clone/docs/audit/open_issues.md').readAsStringSync() + _entry(9, 'sib nine'));
    expect(_git(['add', '-A'], clone).exitCode, 0);
    expect(_git(['commit', '-q', '-m', 'sib files 9'], clone).exitCode, 0);
    expect(_git(['checkout', '-q', 'main'], clone).exitCode, 0);
    final out = await _hookOutput(dart, src, clone, startup);
    expect(out, contains('Reserved-but-unfiled: none'));
    expect(out, contains('next free number is at least 10'));
  });

  test('does NOT fetch: a reservation made from ANOTHER clone is invisible until the next sync (and the line says so)', () async {
    // `other` was cloned from the still-EMPTY remote, so its HEAD is unborn;
    // fetch main first and reserve from the fetched ref (review round 2).
    expect(_git(['fetch', '-q', 'origin'], other).exitCode, 0);
    expect(_git(['push', '-q', 'origin', 'refs/remotes/origin/main:refs/heads/oi/7'], other).exitCode, 0);
    final out = await _hookOutput(dart, src, clone, startup);
    expect(out, contains('next free number is at least 5'),
        reason: 'local-only read: oi/7 on the remote is not consulted');
    expect(out, contains('as of the last sync'));
  });

  test('stays silent about the board when there is no origin/main to read', () async {
    final lone = '${tmp.path}/lone';
    Directory(lone).createSync();
    expect(_git(['init', '-q', '-b', 'main', '.'], lone).exitCode, 0);
    File('$lone/docs/audit/open_issues.md').createSync(recursive: true);
    File('$lone/docs/audit/open_issues.md').writeAsStringSync('# board\n${_entry(1, 'a')}');
    final out = await _hookOutput(dart, src, lone, startup);
    expect(out, isNot(contains('OI board')));
  });
}
