// test/scripts/contract_sweep_e2e_test.dart
//
// END-TO-END for scripts/contract_sweep.dart (OI-220): builds a throwaway
// clone with a real origin/main, a one-concept registry and two contract
// tests, then runs the REAL runner against it with a stub `flutter` that only
// records its argv. Asserts what gets selected, what gets spawned, and every
// exit-code/guard contract the pre-push wiring relies on.
//
// The stub is a `.bat` on Windows because the runner spawns flutter with
// runInShell: true, which routes through cmd.exe -- and cmd.exe cannot execute
// an extensionless POSIX stub (it finds the REAL flutter instead; that is the
// recursion the CONTRACT_SWEEP_NESTED guard below exists for).
//
// ENV SCRUBBING: every subprocess here -- the fixture's git calls AND the
// runner -- gets a filtered environment (GIT_*, GITHUB_*, PUSH_BEFORE removed,
// includeParentEnvironment: false). Run inside a git hook, a leaked GIT_DIR
// overrides `workingDirectory:` and would point the fixture's `git branch -D`
// at the REAL repo (feedback_mistake_git_hook_env_leak). Registered in
// test/contracts/gate_e2e_env_hermetic_test.dart.

@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// The Dart binary to spawn the runner with.
///
/// NOT `Platform.resolvedExecutable`: under `flutter test` that resolves to
/// the flutter_tester binary, not dart, so the spawn never returns and the
/// suite HANGS rather than failing. The repo already documents this trap at
/// test/scripts/oi_numbering_lib_test.dart:284 after it cost that suite a
/// >10-minute hang — and it cost this one another before the note was found.
/// Prefer the SDK exe beside the Flutter wrapper (the wrapper takes the SDK
/// update lock and shells out to git on EVERY call); fall back to `dart`.
/// Copied verbatim from test/scripts/cron_registry_snapshot_gate_test.dart:33-57.
String dartBinOf() {
  final override = Platform.environment['DART_BIN_OVERRIDE'];
  if (override != null && File(override).existsSync()) return override;
  final which = Process.runSync(
    Platform.isWindows ? 'where' : 'which',
    ['dart'],
    stdoutEncoding: utf8,
  );
  if (which.exitCode == 0) {
    final first = (which.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (first.isNotEmpty) {
      final dir = File(first).parent.path.replaceAll(r'\', '/');
      for (final c in [
        '$dir/cache/dart-sdk/bin/dart.exe',
        '$dir/cache/dart-sdk/bin/dart',
      ]) {
        if (File(c).existsSync()) return c;
      }
    }
  }
  return 'dart';
}

/// Hermetic env for EVERY subprocess in this file (fixture git calls included):
/// a leaked GIT_DIR would point a fixture's `git branch -D` at the REAL repo.
Map<String, String> _env({String record = '', String stubExit = '0', Map<String, String> extra = const {}}) {
  final env = Map<String, String>.from(Platform.environment)
    ..removeWhere((k, _) {
      final u = k.toUpperCase();
      return u.startsWith('GIT_') || u.startsWith('GITHUB_') || u == 'PUSH_BEFORE';
    });
  env['SWEEP_RECORD'] = record;
  env['SWEEP_STUB_EXIT'] = stubExit;
  env.addAll(extra);
  return env;
}

ProcessResult _git(List<String> args, String cwd) => Process.runSync('git', args, workingDirectory: cwd,
    environment: _env(), includeParentEnvironment: false, runInShell: true);

class _Repo {
  late String tmp;    // the temp root holding origin.git + work/ + the stub
  late String dir;    // the clone (HEAD has one unpushed commit = the "push range")
  late String stub;   // stub flutter path (flutter.bat on Windows)
  late String record; // where the stub writes its argv
}

/// Stub `flutter`: records its argv and exits with SWEEP_STUB_EXIT.
/// Windows -> flutter.bat (cmd.exe cannot run an extensionless POSIX stub);
/// elsewhere -> a chmod +x sh script.
String _writeStub(String dir) {
  if (Platform.isWindows) {
    final f = File('$dir/flutter.bat')
      ..writeAsStringSync('@echo off\r\n'
          'echo %* > "%SWEEP_RECORD%"\r\n'
          'exit /b %SWEEP_STUB_EXIT%\r\n');
    return f.path;
  }
  final f = File('$dir/flutter')
    ..writeAsStringSync('#!/bin/sh\n'
        'echo "\$@" > "\$SWEEP_RECORD"\n'
        'exit "\$SWEEP_STUB_EXIT"\n');
  Process.runSync('chmod', ['+x', f.path]);
  return f.path;
}

void main() {
  final repoRoot = Directory.current.path.replaceAll(r'\', '/');
  final runner = '$repoRoot/scripts/contract_sweep.dart';
  final dartBin = dartBinOf();
  late _Repo r;

  void write(String rel, String content) {
    final f = File('${r.dir}/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  void git(List<String> args) {
    final res = _git(args, r.dir);
    expect(res.exitCode, 0, reason: 'git ${args.join(' ')}: ${res.stderr}');
  }

  setUp(() {
    r = _Repo();
    r.tmp = Directory.systemTemp.createTempSync('sweep_').path.replaceAll(r'\', '/');
    // 1. Bare origin + a clone-shaped work repo whose origin/main is a REAL
    //    remote-tracking ref (pushed), not a synthetic update-ref -- the
    //    three-dot range the runner computes is the one a real push range has.
    final originRes = _git(['init', '--quiet', '--bare', '-b', 'main', '${r.tmp}/origin.git'], r.tmp);
    expect(originRes.exitCode, 0, reason: 'git init --bare: ${originRes.stderr}');
    r.dir = '${r.tmp}/work';
    Directory(r.dir).createSync();
    git(['init', '--quiet', '-b', 'main']);
    git(['config', 'user.email', 'test@example.com']);
    git(['config', 'user.name', 'test']);
    git(['remote', 'add', 'origin', '${r.tmp}/origin.git']);

    // 2. First commit, pushed: this is origin/main.
    write('lib/a.dart', 'int a() => 1;\n');
    write('lib/lonely.dart', 'int lonely() => 1;\n'); // NO test references it
    write('test/contracts/a_test.dart',
        "import 'package:x/a.dart';\nvoid main() {}\n"); // arm (b): basename match
    write('test/contracts/a_registry_test.dart',
        '// registry-selected only: never names its subject\nvoid main() {}\n'); // arm (a)
    write('docs/sot_registry.yaml', '''
concepts:

  - concept: a_concept
    domain: test
    behavioral_test_path: test/contracts/a_registry_test.dart  # pinned by the fixture
    writers:
      - file: lib/a.dart
        line_range: 1-1
''');
    git(['add', '-A']);
    git(['commit', '--quiet', '--no-verify', '-m', 'seed']);
    git(['push', '--quiet', '-u', 'origin', 'main']);

    // 3. SECOND commit, NOT pushed: the push range origin/main...HEAD.
    write('lib/a.dart', 'int a() => 2;\n');
    write('lib/lonely.dart', 'int lonely() => 2;\n');
    git(['add', '-A']);
    git(['commit', '--quiet', '--no-verify', '-m', 'change a + lonely']);

    // 4. The stub and its argv record (absent until the stub runs).
    r.stub = _writeStub(r.tmp);
    r.record = '${r.tmp}/argv.txt';
  });
  tearDown(() {
    // Cleanup is hygiene, never an assertion: a timed-out child can still hold
    // a Windows handle into the temp dir, and a throw here would HIDE the real
    // failure (playbook: e2e teardown never throws).
    try {
      Directory(r.tmp).deleteSync(recursive: true);
    } catch (_) {}
  });

  ProcessResult run(List<String> extra, {String stubExit = '0', Map<String, String> env = const {}}) => Process.runSync(
      dartBin, ['run', runner, '--flutter-bin', r.stub, ...extra],
      workingDirectory: r.dir, environment: _env(record: r.record, stubExit: stubExit, extra: env),
      includeParentEnvironment: false, runInShell: true);

  test('selects the registry test AND the importing test; reports lonely.dart as unmapped; spawns flutter with them', () {
    final res = run([]);
    expect(res.exitCode, 0, reason: '${res.stdout}${res.stderr}');
    final argv = File(r.record).readAsStringSync();
    expect(argv, contains('test/contracts/a_test.dart'));
    expect(argv, contains('test/contracts/a_registry_test.dart'));
    expect(argv, contains('--exclude-tags golden'));
    expect(res.stdout, contains('unmapped lib/lonely.dart'));
  });
  test('RED PATH: a failing flutter run fails the sweep', () {
    final res = run([], stubExit: '1');
    expect(res.exitCode, 1, reason: '${res.stdout}${res.stderr}');
  });
  test('--warn-only turns that failure into exit 0 and names the verdict', () {
    final res = run(['--warn-only'], stubExit: '1');
    expect(res.exitCode, 0);
    expect('${res.stdout}${res.stderr}', contains('WARN: flutter test exit 1'));
  });
  test('--dry-run prints the selection and never spawns flutter', () {
    final res = run(['--dry-run']);
    expect(res.exitCode, 0);
    expect(File(r.record).existsSync(), isFalse);
    expect(res.stdout, contains('test/contracts/a_test.dart'));
  });
  test('RED PATH: an unresolvable origin/main falls back to the whole contracts subset', () {
    _git(['branch', '-D', '-r', 'origin/main'], r.dir);
    final res = run([]);
    expect(res.exitCode, 0, reason: '${res.stdout}${res.stderr}');
    expect('${res.stdout}${res.stderr}', contains('fallback'));
    expect(File(r.record).readAsStringSync(), contains('test/contracts/'));
  });
  test('CONTRACT_SWEEP_SKIP=1 skips before any git or flutter work', () {
    final res = run([], env: {'CONTRACT_SWEEP_SKIP': '1'});
    expect(res.exitCode, 0);
    expect(res.stdout, contains('skipped'));
    expect(File(r.record).existsSync(), isFalse);
  });
  test('CONTRACT_SWEEP_NESTED=1 (set by the sweep on its own flutter spawn) skips — the recursion guard', () {
    final res = run([], env: {'CONTRACT_SWEEP_NESTED': '1'});
    expect(res.exitCode, 0);
    expect(res.stdout, contains('nested'));
    expect(File(r.record).existsSync(), isFalse);
  });
}
