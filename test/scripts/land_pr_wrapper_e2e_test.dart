@Timeout(Duration(minutes: 8))
library;

// test/scripts/land_pr_wrapper_e2e_test.dart
//
// The shell wrapper scripts/land_pr.sh (landing D, docs/plans/merge-train.md sections 3.1 and 5): its arguments, locating Dart,
// the `result:` line it owns, the statuses it passes through, signals.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/land_pr_fixture.dart';
import '../helpers/merge_scope_repo.dart';
import '../helpers/spawn.dart';
import '../helpers/sync_cli_fixture.dart';

/// A copy of the wrapper and `_dart_bin.sh` in a temp scripts directory next to a FIXTURE CLI whose body is [dartBody].
String fixtureScripts(LandFixture fx, String dartBody) {
  final d = Directory('${fx.cli.repo.root.path}/fixture_scripts')..createSync(recursive: true);
  File('${fx.cli.srcRoot}/scripts/land_pr.sh').copySync('${d.path}/land_pr.sh');
  File('${fx.cli.srcRoot}/scripts/_dart_bin.sh').copySync('${d.path}/_dart_bin.sh');
  File('${d.path}/land_pr.dart').writeAsStringSync("import 'dart:io';\n\n$dartBody\n");
  return '${d.path}/land_pr.sh';
}

ProcessResult runFixtureWrapper(LandFixture fx, String script, {List<String> args = const ['191']}) => runSpawn(
      'sh',
      [script, ...args],
      why: 'fixture wrapper $script',
      workingDirectory: fx.dir,
      extraEnv: fx.cli.repo.env,
      allowControl: ScopeRepo.allowControl,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

void main() {
  group('the wrapper arguments', () {
    test('any argument shape but `<pr> [--allow-workflow-change]` is a usage error owned by the wrapper: refused, exit 2, nothing asked of gh', () {
      final fx = LandFixture.create();
      for (final args in [
        <String>[],
        ['191', '192'],
        ['abc'],
        ['191', '--bogus'],
        ['--allow-workflow-change'],
        ['--allow-workflow-change', '191'],
        ['191', '--gh', 'x'],
        ['191', '--scripts-dir', '/tmp'],
        ['191', '--poll-ms', '1'],
        ['191', '--record-gate', 'x'],
        ['191', '--allow-workflow-change', 'extra'],
        ['1x'],
        [''],
      ]) {
        final r = fx.runWrapper(args);
        expectResult(r, 2, 'refused');
        expect(stdoutOf(r), contains('land_pr: refused:'), reason: args.join(' '));
        // The WRAPPER owns this refusal (the CLI would refuse some of these too, with its own words).
        final wrapperOwned = args.isNotEmpty && args[0] == '--allow-workflow-change'
            ? 'the PR number comes first'
            : args.length == 2 && args[0] == '191'
                ? 'unknown argument'
                : args.length == 1
                    ? 'is not a PR number'
                    : 'land_pr: refused:';
        expect(stdoutOf(r), contains(wrapperOwned), reason: args.join(' '));
      }
      expect(fx.log, isEmpty, reason: 'the wrapper refused before anything ran');
    });

    test('--allow-workflow-change is forwarded to the CLI, and nothing else is', () {
      final fx = LandFixture.create();
      final script = fixtureScripts(fx, 'void main(List<String> a) {\n  stdout.writeln("args=\${a.join("|")}");\n  stdout.writeln("result: merged");\n}');
      expect(stdoutOf(runFixtureWrapper(fx, script, args: ['191', '--allow-workflow-change'])), contains('args=191|--allow-workflow-change'));
      expect(stdoutOf(runFixtureWrapper(fx, script, args: ['191'])), contains('args=191\n'));
    });

    test('it works against a repository that holds none of the scripts, from a subdirectory', () {
      final fx = LandFixture.create();
      expect(File('${fx.dir}/scripts/land_pr.dart').existsSync(), isFalse);
      Directory('${fx.dir}/docs/audit').createSync(recursive: true);
      final script = fixtureScripts(fx, 'void main() {\n  stdout.writeln("cwd=\${Directory.current.path.split("/").last}");\n  stdout.writeln("result: merged");\n}');
      final r = runSpawn('sh', [script, '191'],
          why: 'wrapper from a subdirectory',
          workingDirectory: '${fx.dir}/docs/audit',
          extraEnv: fx.cli.repo.env,
          allowControl: ScopeRepo.allowControl,
          stdoutEncoding: utf8);
      expectResult(r, 0, 'merged');
      expect(stdoutOf(r), contains('cwd=audit'));
    });

    test('with no dart on the PATH: result refused, exit 2', () {
      final fx = LandFixture.create();
      final r = fx.runWrapper(['191'], path: fx.cli.minimalPath(['git', 'sh', 'dirname', 'tr']));
      expectResult(r, 2, 'refused');
      expect(stdoutOf(r), contains('no dart on the PATH'));
    });

    test('it runs the dart that the _dart_bin.sh next to it resolves, not whatever `dart` is on the PATH', () {
      final fx = LandFixture.create();
      final script = fixtureScripts(fx, 'void main() {\n  stdout.writeln("result: merged");\n}');
      final d = File(script).parent.path;
      final marker = '$d/resolved.marker';
      File('$d/marker_dart.sh').writeAsStringSync('#!/bin/sh\necho used > "$marker"\nexec "${dartBin()}" "\$@"\n');
      File('$d/_dart_bin.sh').writeAsStringSync('resolve_dart_bin() {\n  echo "$d/marker_dart.sh"\n}\n');
      runSpawn('chmod', ['755', '$d/marker_dart.sh'], why: 'make the fixture dart executable');
      expectResult(runFixtureWrapper(fx, script), 0, 'merged');
      expect(File(marker).existsSync(), isTrue);
    });
  });

  group('statuses and the result line', () {
    for (final code in [8, 9, 254, 255, 137, 130]) {
      test('a CLI that ends with status $code is reported as result error, exit 4, as the last stdout line', () {
        final fx = LandFixture.create();
        final script = fixtureScripts(fx, 'void main() {\n  stdout.writeln("fixture output");\n  exit($code);\n}');
        final r = runFixtureWrapper(fx, script);
        expectResult(r, 4, 'error');
        expect(stdoutOf(r), contains('fixture output'));
      });
    }

    for (final code in [0, 1, 2, 3, 4, 5, 6, 7]) {
      test('a CLI status of $code passes through and the wrapper adds no result line of its own', () {
        final fx = LandFixture.create();
        final script = fixtureScripts(fx, 'void main() {\n  stdout.writeln("result: fixture");\n  exit($code);\n}');
        final r = runFixtureWrapper(fx, script);
        expect(r.exitCode, code);
        expect(lastLine(stdoutOf(r)), 'result: fixture');
        expect(RegExp(r'^result: ', multiLine: true).allMatches(stdoutOf(r)).length, 1);
      });
    }

    test('a CLI that prints its result line and then dies with 255 gets exactly ONE added line after it (the wrapper cannot know)', () {
      final fx = LandFixture.create();
      final script = fixtureScripts(fx, 'void main() {\n  stdout.writeln("result: merged");\n  exit(255);\n}');
      final r = runFixtureWrapper(fx, script);
      expect(r.exitCode, 4);
      expect(lastLine(stdoutOf(r)), 'result: error');
    });
  });

  group('signals', () {
    Future<(int, String)> runAndTerm(LandFixture fx, String script, {String shell = 'sh', ProcessSignal signal = ProcessSignal.sigterm}) async {
      final ready = File('${fx.stub}/wrapper_ready');
      // A parent that ignores SIGHUP/SIGINT (nohup, a background job) hands that to the shell, which then cannot trap it:
      // perl puts the default back and execs, so the test does not depend on how the suite was started.
      final p = await startSpawn('perl', ['-e', r'$SIG{HUP} = $SIG{INT} = "DEFAULT"; exec @ARGV', shell, script, '191'],
          workingDirectory: fx.dir, extraEnv: fx.cli.repo.env, allowControl: ScopeRepo.allowControl);
      final o = StringBuffer();
      final e = StringBuffer();
      final d1 = p.stdout.transform(utf8.decoder).forEach(o.write);
      final d2 = p.stderr.transform(utf8.decoder).forEach(e.write);
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (!ready.existsSync() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(ready.existsSync(), isTrue, reason: 'the fixture CLI never started');
      p.kill(signal);
      final code = await p.exitCode.timeout(const Duration(seconds: 60));
      await Future.wait([d1, d2]);
      reportSpawn(code, o.toString(), e.toString(), 'wrapper after a $signal');
      return (code, o.toString());
    }

    test('a TERM reaches the CLI, the wrapper waits for its REAL status (exit 3 here) and adds no second result line', () async {
      final fx = LandFixture.create();
      final script = fixtureScripts(fx, '''
Future<void> main() async {
  ProcessSignal.sigterm.watch().listen((_) async {
    stdout.writeln("result: ci-failed");
    await stdout.flush();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(3);
  });
  File("${fx.stub}/wrapper_ready").writeAsStringSync("1");
  await Future<void>.delayed(const Duration(seconds: 30));
}
''');
      final (code, text) = await runAndTerm(fx, script);
      expect(code, 3, reason: text);
      expect(lastLine(text), 'result: ci-failed');
      expect(RegExp(r'^result: ', multiLine: true).allMatches(text).length, 1);
    });

    test('a TERM before a CHILD EXIT 0 keeps exit 0 and ONE result line', () async {
      final fx = LandFixture.create();
      final script = fixtureScripts(fx, '''
Future<void> main() async {
  ProcessSignal.sigterm.watch().listen((_) async {
    stdout.writeln("result: merged");
    await stdout.flush();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  });
  File("${fx.stub}/wrapper_ready").writeAsStringSync("1");
  await Future<void>.delayed(const Duration(seconds: 30));
}
''');
      final (code, text) = await runAndTerm(fx, script);
      expect(code, 0, reason: text);
      expect(lastLine(text), 'result: merged');
      expect(RegExp(r'^result: ', multiLine: true).allMatches(text).length, 1);
    });

    String quickCli(LandFixture fx, String word, int code) => fixtureScripts(fx, '''
Future<void> main() async {
  ProcessSignal.sigterm.watch().listen((_) {
    stdout.writeln("result: $word");
    exit($code);
  });
  File("${fx.stub}/wrapper_ready").writeAsStringSync("1");
  await Future<void>.delayed(const Duration(seconds: 30));
}
''');

    for (final sig in [ProcessSignal.sigint, ProcessSignal.sighup]) {
      test('a $sig sent to the wrapper is forwarded to the CLI as a TERM: its own result and status stand', () async {
        final fx = LandFixture.create();
        final (code, text) = await runAndTerm(fx, quickCli(fx, 'ci-failed', 3), signal: sig);
        expect(code, 3, reason: text);
        expect(lastLine(text), 'result: ci-failed');
        expect(RegExp(r'^result: ', multiLine: true).allMatches(text).length, 1);
      });
    }

    // sh is dash here; bash reaps a child inside its SIGCHLD handler, which once made the wrapper keep the signal's 143.
    test('the same TERM under bash (it reaps the child early): the CLI status and ONE result line still stand', () async {
      if (runSpawn('sh', ['-c', 'command -v bash'], why: 'is bash installed').exitCode != 0) return;
      final fx = LandFixture.create();
      final (code, text) = await runAndTerm(fx, quickCli(fx, 'merged', 0), shell: 'bash');
      expect(code, 0, reason: text);
      expect(lastLine(text), 'result: merged');
      expect(RegExp(r'^result: ', multiLine: true).allMatches(text).length, 1);
    });

    test('a CLI killed by a real signal (SIGKILL, status 137) is reported as result: error, exit 4', () async {
      final fx = LandFixture.create();
      final script = fixtureScripts(fx, 'void main() {\n  Process.killPid(pid, ProcessSignal.sigkill);\n}');
      final r = runFixtureWrapper(fx, script);
      expectResult(r, 4, 'error');
    });

    test('a scripts directory with a space in its path works', () {
      final fx = LandFixture.create();
      final script = fixtureScripts(fx, 'void main() {\n  stdout.writeln("result: merged");\n}');
      final spaced = '${fx.stub}/a b';
      runSpawn('cp', ['-r', File(script).parent.path, spaced], why: 'copy the fixture scripts to a spaced path');
      final r = runSpawn('sh', ['$spaced/land_pr.sh', '191'],
          why: 'wrapper from a spaced path',
          workingDirectory: fx.dir,
          extraEnv: fx.cli.repo.env,
          allowControl: ScopeRepo.allowControl,
          stdoutEncoding: utf8);
      expectResult(r, 0, 'merged');
    });
  });
}
