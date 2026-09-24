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

void _commit(String cwd, String fileName, String content, String message) {
  File('$cwd/$fileName').writeAsStringSync(content);
  expect(_git(['add', '-A'], cwd).exitCode, 0);
  expect(_git(['commit', '-q', '-m', message], cwd).exitCode, 0);
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
    _commit(lone, 'seed.txt', 'seed\n', 'seed');
    final out = await _hookOutput(dart, src, lone, startup);
    expect(out, isNot(contains('MAIN BEHIND')));
    expect(out, isNot(contains('MAIN AHEAD')));
    expect(out, isNot(contains('MAIN DIVERGED')));
  });
}
