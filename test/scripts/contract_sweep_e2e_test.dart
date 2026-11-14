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
// runner -- is spawned through test/helpers/spawn.dart, which hands the child the
// canonical control-variable-clean environment (scripts/regression_catalog_lib.dart:
// GIT_*, GITHUB_*, CONTRACT_SWEEP_*, PRE_COMMIT_*, ... and DART_BIN_OVERRIDE) with
// includeParentEnvironment: false, and reports each child's exit code, stdout and
// stderr under a failing test. Run inside a git hook, a leaked GIT_DIR overrides
// `workingDirectory:` and would point the fixture's `git branch -D` at the REAL repo
// (feedback_mistake_git_hook_env_leak). The sweep (scripts/contract_sweep.dart:31)
// sets CONTRACT_SWEEP_NESTED=1 on the `flutter test` it spawns and selects THIS file
// whenever a push changes docs/sot_registry.yaml, so an unscrubbed child inherited the
// recursion guard and the runner under test skipped: 5 of 7 tests failed (class 2.56,
// diagnose 2026-10-06-spawn-test-env-leak). The poisoned-parent test at the bottom is
// the regression for that.
// Registered in test/contracts/gate_e2e_env_hermetic_test.dart.

@Timeout(Duration(minutes: 6))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/read_screen_source.dart';
import '../helpers/spawn.dart';

/// The two variables the stub `flutter` reads. Not control variables, so they pass the
/// helper's `extra:` guard without a declaration.
Map<String, String> _stubEnv({String record = '', String stubExit = '0'}) =>
    {'SWEEP_RECORD': record, 'SWEEP_STUB_EXIT': stubExit};

ProcessResult _git(List<String> args, String cwd) => runSpawn('git', args,
    workingDirectory: cwd,
    extraEnv: _stubEnv(),
    runInShell: true,
    why: 'sweep fixture: git ${args.join(' ')}');

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
  runSpawn('chmod', ['+x', f.path], why: 'sweep fixture: chmod +x the stub flutter');
  return f.path;
}

void main() {
  final repoRoot = Directory.current.path.replaceAll(r'\', '/');
  final runner = '$repoRoot/scripts/contract_sweep.dart';
  final dart = dartBin();
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

  /// Runs the REAL runner. [env] is what a scenario sets DELIBERATELY (the kill switch, the
  /// recursion guard), so every key in it is declared to the helper's `extra:` guard.
  /// [parent] is the helper's seam for a poisoned parent environment.
  ProcessResult run(List<String> extra,
          {String stubExit = '0', Map<String, String> env = const {}, Map<String, String>? parent}) =>
      runSpawn(dart, ['run', runner, '--flutter-bin', r.stub, ...extra],
          workingDirectory: r.dir,
          extraEnv: {..._stubEnv(record: r.record, stubExit: stubExit), ...env},
          allowControl: env.keys.toSet(),
          parentEnvironment: parent,
          runInShell: true,
          why: 'contract_sweep.dart ${extra.join(' ')} (stub exit $stubExit)');

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

  // THE OBSERVED BUG (class 2.56, 2026-10-05). The sweep runs `flutter test` with
  // CONTRACT_SWEEP_NESTED=1 and selects THIS file whenever a push changes
  // docs/sot_registry.yaml; the old per-file filter removed GIT_*, GITHUB_* and
  // PUSH_BEFORE only, so the runner under test inherited the flag and exited "nested"
  // before spawning the stub: 5 of the 7 tests above failed on every registry-touching
  // push. The parent environment is POISONED through the helper's seam (Dart cannot
  // mutate its own environment) with each variable that makes the runner skip; the
  // runner must still do its work.
  test('a parent environment carrying CONTRACT_SWEEP_NESTED / CONTRACT_SWEEP_SKIP does NOT reach the runner under test', () {
    for (final poison in const ['CONTRACT_SWEEP_NESTED', 'CONTRACT_SWEEP_SKIP']) {
      if (File(r.record).existsSync()) File(r.record).deleteSync();
      final parent = {...Platform.environment, poison: '1'};
      // PRECONDITIONS, so this test cannot pass vacuously: the poison is in the parent, it
      // SURVIVES the filter this file used to carry (GIT_*, GITHUB_*, PUSH_BEFORE only), and
      // the helper's environment for that same parent does not contain it.
      final legacy = Map<String, String>.from(parent)
        ..removeWhere((k, _) {
          final u = k.toUpperCase();
          return u.startsWith('GIT_') || u.startsWith('GITHUB_') || u == 'PUSH_BEFORE';
        });
      expect(legacy.containsKey(poison), isTrue, reason: 'the old filter leaked $poison');
      expect(hermeticEnvironment(parent: parent).containsKey(poison), isFalse);
      final res = run([], parent: parent);
      expect(res.exitCode, 0, reason: '$poison: ${res.stdout}${res.stderr}');
      expect(File(r.record).existsSync(), isTrue,
          reason: '$poison leaked into the child: the runner skipped before spawning the stub flutter');
      expect(File(r.record).readAsStringSync(), contains('test/contracts/a_test.dart'));
      expect('${res.stdout}', isNot(contains('nested')));
      expect('${res.stdout}', isNot(contains('skipped')));
    }
  });

  test('run() hands the poisoned parent to the helper through its seam (the test above would pass '
      'vacuously if it did not)', () {
    final src = readSourceFileStripped('test/scripts/contract_sweep_e2e_test.dart');
    final start = src.indexOf('ProcessResult run(List<String> extra');
    final end = src.indexOf("test('selects the registry test");
    expect(start, greaterThan(-1));
    expect(end, greaterThan(start));
    final body = src.substring(start, end);
    expect(body, contains('parentEnvironment: parent,'));
    expect(body, contains('allowControl: env.keys.toSet(),'),
        reason: 'the scenarios that set a control variable deliberately must declare it');
  });
}
