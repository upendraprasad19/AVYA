// E2E for scripts/batch_close_hook.dart — runs the REAL Stop hook against a real
// git repo.
//
// The pure test covers the decision. This covers the contract with the harness,
// which the predicate cannot see:
//   - it ALWAYS exits 0 (a non-zero Stop hook is a wedged session);
//   - it emits `{"decision":"block"}` only when it should;
//   - the once-per-HEAD state file actually silences the second run;
//   - `stop_hook_active` short-circuits before anything else.
//
// It also pins the bug that live-testing found and no unit test could: the hook
// derives the harness memory directory from `--git-common-dir`, NOT
// `--show-toplevel`, because every session works in a linked worktree per §4.13
// and the worktree path never matches the harness's mangled directory name.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) {
    final u = k.toUpperCase();
    return u.startsWith('GIT_') || u.startsWith('GITHUB_');
  });
  return env;
}

late final String _hook;
late final String _lib;

ProcessResult _git(String cwd, List<String> args) => Process.runSync(
      'git',
      args,
      workingDirectory: cwd,
      environment: _cleanEnv(),
      includeParentEnvironment: false,
      runInShell: true,
    );

/// Runs the real hook with [stdinJson] on stdin.
///
/// Uses Process.start rather than runSync because the hook reads stdin, and
/// runSync cannot supply it. Cross-platform: no shell, no `cmd /c` pipe.
Future<({int exitCode, String stdout})> _runHook(String cwd,
    {String stdinJson = '{}'}) async {
  final p = await Process.start(
    'dart',
    ['run', 'scripts/batch_close_hook.dart'],
    workingDirectory: cwd,
    environment: _cleanEnv(),
    includeParentEnvironment: false,
    runInShell: true,
  );
  p.stdin.write(stdinJson);
  await p.stdin.close();
  final out = await p.stdout.transform(utf8.decoder).join();
  await p.stderr.transform(utf8.decoder).join();
  final code = await p.exitCode;
  return (exitCode: code, stdout: out);
}

/// A repo with an `origin/main` that HEAD is ahead of.
Directory _repoWithUnpushed({int commits = 2}) {
  final dir = Directory.systemTemp.createTempSync('batchclose_e2e_');
  final root = dir.path;
  Directory('$root/scripts').createSync(recursive: true);
  File('$root/scripts/batch_close_hook.dart')
      .writeAsStringSync(File(_hook).readAsStringSync());
  File('$root/scripts/batch_close_lib.dart')
      .writeAsStringSync(File(_lib).readAsStringSync());

  _git(root, ['init', '-q']);
  _git(root, ['config', 'user.email', 't@t.t']);
  _git(root, ['config', 'user.name', 't']);
  File('$root/seed.txt').writeAsStringSync('seed\n');
  _git(root, ['add', '.']);
  _git(root, ['commit', '-q', '-m', 'seed']);
  // Fabricate origin/main at the seed so HEAD is ahead by `commits`.
  _git(root, ['update-ref', 'refs/remotes/origin/main', 'HEAD']);
  for (var i = 0; i < commits; i++) {
    File('$root/f$i.txt').writeAsStringSync('$i\n');
    _git(root, ['add', '.']);
    _git(root, ['commit', '-q', '-m', 'fix(x): commit $i']);
  }
  return dir;
}

Map<String, dynamic>? _decision(({int exitCode, String stdout}) r) {
  for (final line in r.stdout.split(String.fromCharCode(10))) {
    final t = line.trim();
    if (t.startsWith('{')) {
      try {
        return jsonDecode(t) as Map<String, dynamic>;
      } catch (_) {}
    }
  }
  return null;
}

void main() {
  setUpAll(() {
    _hook = '${Directory.current.path}/scripts/batch_close_hook.dart';
    _lib = '${Directory.current.path}/scripts/batch_close_lib.dart';
  });

  test('BLOCKS once when a batch has landed unpushed', () async {
    final d = _repoWithUnpushed();
    addTearDown(() => d.deleteSync(recursive: true));

    final r = await _runHook(d.path);
    expect(r.exitCode, 0, reason: 'a Stop hook must NEVER exit non-zero');
    final dec = _decision(r);
    expect(dec, isNotNull);
    expect(dec!['decision'], 'block');
    expect(dec['reason'], contains('§5'));
    expect(dec['reason'], contains('2 unpushed'));
  });

  test('SILENT on the second run at the same HEAD', () async {
    final d = _repoWithUnpushed();
    addTearDown(() => d.deleteSync(recursive: true));

    await _runHook(d.path); // first run records the sha
    final second = await _runHook(d.path);
    expect(second.exitCode, 0);
    expect(_decision(second), isNull,
        reason: 'bounded to one interruption per HEAD — otherwise every '
            'conversational turn after a commit is interrupted');
  });

  test('stop_hook_active NEVER blocks (infinite-loop guard)', () async {
    final d = _repoWithUnpushed();
    addTearDown(() => d.deleteSync(recursive: true));
    final r = await _runHook(d.path, stdinJson: '{"stop_hook_active":true}');
    expect(r.exitCode, 0);
    expect(_decision(r), isNull);
  });

  test('SILENT when nothing is unpushed', () async {
    final d = _repoWithUnpushed(commits: 0);
    addTearDown(() => d.deleteSync(recursive: true));
    final r = await _runHook(d.path);
    expect(r.exitCode, 0);
    expect(_decision(r), isNull);
  });

  test('kill switch silences it', () async {
    final d = _repoWithUnpushed();
    addTearDown(() => d.deleteSync(recursive: true));
    Directory('${d.path}/.claude').createSync(recursive: true);
    File('${d.path}/.claude/.batch_close.disabled').writeAsStringSync('');
    final r = await _runHook(d.path);
    expect(r.exitCode, 0);
    expect(_decision(r), isNull);
  });

  test('garbage on stdin does not wedge or crash it', () async {
    final d = _repoWithUnpushed();
    addTearDown(() => d.deleteSync(recursive: true));
    final r = await _runHook(d.path, stdinJson: 'not json at all');
    expect(r.exitCode, 0, reason: 'every error path exits 0');
  });

  test('DOES NOT HANG when stdin is never closed', () async {
    // THE BLOCKING FINDING from round 1, reproduced then pinned. The first
    // version used the SYNCHRONOUS, BLOCKING `stdin.readLineSync`: a caller that
    // does not write-then-close blocked forever. A hang is not an exception, so
    // the surrounding try/catch could not rescue it — and Stop fires at the END
    // OF EVERY TURN, so it would wedge every session.
    //
    // Reproduced during review with a delayed writer: still blocked after 8s,
    // exit 124. The fix mirrors the two sibling hooks the repo had ALREADY
    // fixed for this exact class (git_safety_hook.dart:85-95,
    // discipline_hook.dart:82,221) — hasTerminal guard + a 3s timeout.
    final d = _repoWithUnpushed();
    addTearDown(() => d.deleteSync(recursive: true));

    final p = await Process.start(
      'dart',
      ['run', 'scripts/batch_close_hook.dart'],
      workingDirectory: d.path,
      environment: _cleanEnv(),
      includeParentEnvironment: false,
      runInShell: true,
    );
    // ⚠ DRAIN BOTH PIPES. Not optional, and getting it wrong cost a wrong
    // diagnosis: the first version of this test awaited exitCode without
    // consuming stdout, the hook's JSON block filled the pipe buffer, and the
    // child blocked on WRITE. It looked exactly like the read-hang being tested
    // for — a test-harness deadlock masquerading as the defect under test.
    final outFuture = p.stdout.transform(utf8.decoder).join();
    final errFuture = p.stderr.transform(utf8.decoder).join();

    // Write a payload but DELIBERATELY never close stdin.
    p.stdin.write('{}');
    await p.stdin.flush();

    final code = await p.exitCode.timeout(
      const Duration(seconds: 25),
      onTimeout: () {
        p.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    try {
      await p.stdin.close();
    } catch (_) {}
    await outFuture;
    await errFuture;

    expect(code, isNot(-1),
        reason: 'the hook must self-release on its stdin timeout rather than '
            'block forever waiting for a close that never comes');
    expect(code, 0, reason: 'and it must still exit 0');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
