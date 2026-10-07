// test/scripts/discipline_hook_oi_line_e2e_test.dart
//
// The SessionStart hook must tell every session the next free OI number (as
// of the last sync -- it reads LOCAL refs only, no fetch: spec §3.4/§7.4) and
// the one command to mint with, and must stay SILENT (not wrong) when there is
// no origin/main to read.

@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

ProcessResult _git(List<String> args, String cwd) => runSpawn('git', args,
    why: 'git ${args.join(' ')} (fixture)',
    workingDirectory: cwd,
    stdoutEncoding: utf8,
    stderrEncoding: utf8);

String _fwd(String p) => p.replaceAll('\\', '/');

String _entry(int n, String t) =>
    '\n## OI-$n — $t\n\n- **Status**: OPEN\n- **Blocked on**: none\n- **Verified**: never\n';

Future<String> _hookOutput(String dart, String src, String cwd, String stdinJson) async {
  final r = await runSpawnWithInput(dart, ['run', '$src/scripts/discipline_hook.dart'],
      why: 'discipline_hook SessionStart in $cwd',
      stdin: stdinJson,
      workingDirectory: cwd,
      stdoutEncoding: utf8,
      stderrEncoding: utf8);
  return r.stdout;
}

void main() {
  final src = Directory.current.path;
  final dart = dartBin();
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
