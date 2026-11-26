// test/scripts/discipline_hook_main_sync_e2e_test.dart
//
// The SessionStart hook must warn, on EVERY session start, when local `main`
// is behind, ahead of, or diverged from `origin/main` -- closing the gap
// that let a VPS clone's local `main` silently drift 300 commits behind
// `origin/main` with no warning until someone happened to run `git status`
// (incident 2026-09-24). Unlike the OI board line (local-read-only, see
// discipline_hook_oi_line_e2e_test.dart), this check DOES perform its own
// short, bounded fetch of origin/main so the answer is live at the one
// moment that matters -- session start -- and falls back to the last-known
// local comparison (with a staleness caveat) when that fetch fails or times
// out, rather than blocking the session.
//
// Real subprocess / real git, same pattern as discipline_hook_oi_line_e2e_test.dart.

@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

/// A global git config holding ONLY `user.useConfigOnly = true`.
///
/// HERMETIC by design (diagnose d9e4b1). `main` went red for 4 CI runs because
/// the `lone` fixture committed with no identity: it passed on every developer
/// machine (a global `~/.gitconfig` identity was inherited through `HOME`) and
/// exited 128 on the CI runner, which has none. Pointing `GIT_CONFIG_GLOBAL`
/// here and setting `GIT_CONFIG_NOSYSTEM=1` makes a local run see exactly what
/// the runner sees. `useConfigOnly` matters on its own: without it, a host with
/// a real FQDN auto-detects an identity from the hostname and a missing
/// `user.email` still commits — so the fixture bug would stay invisible there.
final String _hermeticGlobalConfig = () {
  final dir = Directory.systemTemp.createTempSync('hook_sync_gitcfg_');
  final f = File('${dir.path}/gitconfig')
    ..writeAsStringSync('[user]\n\tuseConfigOnly = true\n');
  return f.path;
}();

// The canonical scrub (spawn helper) strips the GIT_* family AND `EMAIL` (git falls
// back to $EMAIL for the author identity; a machine that sets it would pass a commit
// the CI runner refuses). The hermetic global config is set on purpose, AFTER the scrub.
Map<String, String> _gitCfgEnv() => <String, String>{
      'GIT_CONFIG_GLOBAL': _hermeticGlobalConfig,
      'GIT_CONFIG_NOSYSTEM': '1',
    };
const Set<String> _gitCfgControl = <String>{'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM'};

ProcessResult _git(List<String> args, String cwd) => runSpawn('git', args,
    why: 'git ${args.join(' ')} (fixture)',
    workingDirectory: cwd,
    extraEnv: _gitCfgEnv(),
    allowControl: _gitCfgControl,
    stdoutEncoding: utf8,
    stderrEncoding: utf8);

String _fwd(String p) => p.replaceAll('\\', '/');

Future<String> _hookOutput(String dart, String src, String cwd, String stdinJson) async {
  final r = await runSpawnWithInput(dart, ['run', '$src/scripts/discipline_hook.dart'],
      why: 'discipline_hook SessionStart in $cwd',
      stdin: stdinJson,
      workingDirectory: cwd,
      extraEnv: _gitCfgEnv(),
      allowControl: _gitCfgControl,
      stdoutEncoding: utf8,
      stderrEncoding: utf8);
  return r.stdout;
}

void _commit(String cwd, String fileName, String content, String message) {
  File('$cwd/$fileName').writeAsStringSync(content);
  expect(_git(['add', '-A'], cwd).exitCode, 0);
  expect(_git(['commit', '-q', '-m', message], cwd).exitCode, 0);
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
    tmp = Directory.systemTemp.createTempSync('hook_sync_');
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
    _commit(clone, 'seed.txt', 'seed\n', 'seed');
    expect(_git(['push', '-q', '-u', 'origin', 'main'], clone).exitCode, 0);
    // `other` cloned from the still-empty remote has an unborn HEAD -- fetch
    // the now-real main before it does anything (same pattern as the OI e2e).
    expect(_git(['fetch', '-q', 'origin'], other).exitCode, 0);
    expect(_git(['checkout', '-q', 'main'], other).exitCode, 0);
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('in-sync clone: no MAIN BEHIND/AHEAD/DIVERGED in output', () async {
    final out = await _hookOutput(dart, src, clone, startup);
    expect(out, isNot(contains('MAIN BEHIND')));
    expect(out, isNot(contains('MAIN AHEAD')));
    expect(out, isNot(contains('MAIN DIVERGED')));
  });

  test('behind: the hook\'s OWN internal fetch picks up a push from another '
      'clone, with no fetch by the test beforehand', () async {
    _commit(other, 'other.txt', 'from other\n', 'other pushes');
    expect(_git(['push', '-q', 'origin', 'main'], other).exitCode, 0);

    // Deliberately no `git fetch` here in `clone` -- proves the hook's own
    // internal fetch is what surfaces this, not a stale local ref.
    final out = await _hookOutput(dart, src, clone, startup);
    expect(out, contains('MAIN BEHIND'));
    expect(out, contains('1 commit(s) behind'));
    expect(out, contains('git pull origin main'));
    expect(out, isNot(contains('offline/fetch failed')));
  });

  test('ahead: a local unpushed commit', () async {
    _commit(clone, 'local.txt', 'local only\n', 'local commit');
    final out = await _hookOutput(dart, src, clone, startup);
    expect(out, contains('MAIN AHEAD'));
    expect(out, contains('1 commit(s) ahead'));
    expect(out, contains('git push origin main'));
  });

  test('diverged: differing commits on both sides', () async {
    _commit(other, 'other.txt', 'from other\n', 'other pushes');
    expect(_git(['push', '-q', 'origin', 'main'], other).exitCode, 0);
    _commit(clone, 'local.txt', 'local only\n', 'local commit');

    final out = await _hookOutput(dart, src, clone, startup);
    expect(out, contains('MAIN DIVERGED'));
    expect(out, contains('1 ahead'));
    expect(out, contains('1 behind'));
  });

  test('offline/fetch-failure fallback: a broken remote URL falls back to '
      'the last-known local comparison with a staleness caveat', () async {
    // The initial clone already populated refs/remotes/origin/main and
    // FETCH_HEAD. Now break the remote so the hook's own fetch attempt fails,
    // and create local divergence so there is something to report.
    _commit(clone, 'local.txt', 'local only\n', 'local commit');
    expect(
        _git(['remote', 'set-url', 'origin', 'file:///${_fwd(tmp.path)}/does-not-exist.git'],
                clone)
            .exitCode,
        0);

    final out = await _hookOutput(dart, src, clone, startup);
    expect(out, contains('MAIN AHEAD'));
    expect(out, contains('1 commit(s) ahead'));
    expect(out, contains('offline/fetch failed'));
  });

  test('stays silent when there is no origin/main to read (no remote at all)', () async {
    final lone = '${tmp.path}/lone';
    Directory(lone).createSync();
    expect(_git(['init', '-q', '-b', 'main', '.'], lone).exitCode, 0);
    // Same identity setUp gives `clone`/`other`. This repo is built here, not in
    // setUp, and until diagnose d9e4b1 it had none — green wherever a global
    // identity existed, exit 128 on the CI runner.
    _git(['config', 'user.email', 't@example.invalid'], lone);
    _git(['config', 'user.name', 'T'], lone);
    _commit(lone, 'seed.txt', 'seed\n', 'seed');
    final out = await _hookOutput(dart, src, lone, startup);
    expect(out, isNot(contains('MAIN BEHIND')));
    expect(out, isNot(contains('MAIN AHEAD')));
    expect(out, isNot(contains('MAIN DIVERGED')));
  });

  test('kill switch DISCIPLINE_HOOK_SYNC_SKIP=1 disables the check entirely', () async {
    _commit(other, 'other.txt', 'from other\n', 'other pushes');
    expect(_git(['push', '-q', 'origin', 'main'], other).exitCode, 0);

    final result = await runSpawnWithInput(dart, ['run', '$src/scripts/discipline_hook.dart'],
        why: 'discipline_hook SessionStart with DISCIPLINE_HOOK_SYNC_SKIP=1',
        stdin: startup,
        workingDirectory: clone,
        extraEnv: {..._gitCfgEnv(), 'DISCIPLINE_HOOK_SYNC_SKIP': '1'},
        allowControl: {..._gitCfgControl, 'DISCIPLINE_HOOK_SYNC_SKIP'},
        stdoutEncoding: utf8,
        stderrEncoding: utf8);
    final out = result.stdout;

    // Would be MAIN BEHIND without the kill switch -- proven by the sibling
    // "behind" test above using the identical fixture shape.
    expect(out, isNot(contains('MAIN BEHIND')));
    expect(out, isNot(contains('MAIN AHEAD')));
    expect(out, isNot(contains('MAIN DIVERGED')));
  });

  test(
    'a hanging `git fetch` is actually KILLED on timeout, not orphaned '
    '(B-pass finding 2026-09-24: Process.run().timeout() does not kill the '
    'child; regression-tests the Process.start()+kill() fix)',
    () async {
      // A fake `git` on PATH: `fetch` execs into a long sleep (so killing the
      // wrapper's own pid kills the sleep directly, no grandchild to leak);
      // every other subcommand delegates to the real git unchanged.
      final whichGit = runSpawn('which', ['git'], why: 'locate the real git for the fake-fetch wrapper', stdoutEncoding: utf8);
      expect(whichGit.exitCode, 0, reason: 'fixture requires a resolvable git on PATH');
      final realGit = (whichGit.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty);
      final fakeBin = Directory('${tmp.path}/fakebin')..createSync();
      final pidFile = File('${tmp.path}/fake_git_fetch.pid');
      final wrapper = File('${fakeBin.path}/git');
      wrapper.writeAsStringSync('#!/bin/sh\n'
          'if [ "\$1" = "fetch" ]; then\n'
          '  echo \$\$ > "${_fwd(pidFile.path)}"\n'
          '  exec sleep 300\n'
          'fi\n'
          'exec "${_fwd(realGit)}" "\$@"\n');
      runSpawn('chmod', ['+x', wrapper.path], why: 'make the fake git wrapper executable');

      final stopwatch = Stopwatch()..start();
      // Stays startSpawn (plan D3 closed exemption): the subject is a hung child that
      // must be killed on timeout, so the test owns the lifecycle. The stub-first PATH
      // is a PREFIX of the parent's (indexed read).
      final p = await startSpawn(dart, ['run', '$src/scripts/discipline_hook.dart'],
          workingDirectory: clone,
          extraEnv: {
            ..._gitCfgEnv(),
            'PATH': '${fakeBin.path}:${Platform.environment['PATH']}',
          },
          allowControl: _gitCfgControl);
      final outF = p.stdout.transform(utf8.decoder).join();
      final errF = p.stderr.transform(utf8.decoder).join();
      p.stdin.write(startup);
      await p.stdin.close();
      final hookOut = await outF;
      final hookErr = await errF;
      final hookExit = await p.exitCode;
      stopwatch.stop();
      reportSpawn(hookExit, hookOut, hookErr, 'discipline_hook SessionStart against a hanging fake `git fetch`');

      // Bounded by the ~4s internal timeout, not by the 300s fake fetch --
      // generous margin for CI/VPS scheduling noise, still far below 300s.
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 20)),
          reason: 'the hook must not block on the hung fetch');

      expect(pidFile.existsSync(), isTrue,
          reason: 'fixture check: the fake fetch must actually have been invoked');
      final fetchPid = int.parse(pidFile.readAsStringSync().trim());

      // Give the OS a moment to reap the killed process, then confirm it is
      // actually gone -- this is the assertion that distinguishes "the
      // Future gave up waiting" (the pre-fix bug: the process lives on) from
      // "the process was killed" (the fix).
      await Future<void>.delayed(const Duration(seconds: 1));
      final stillAlive =
          runSpawn('kill', ['-0', '$fetchPid'], why: 'probe whether the fake fetch pid $fetchPid is still alive')
                  .exitCode ==
              0;
      expect(stillAlive, isFalse,
          reason: 'the hung git-fetch process (pid $fetchPid) must be killed on '
              'timeout, not orphaned');
    },
    skip: Platform.isWindows
        ? 'POSIX-only fixture (exec/kill -0/sh script); the underlying fix is '
            'platform-independent, only this reproduction is not'
        : null,
  );
}
