@Timeout(Duration(minutes: 8))
library;

// test/scripts/sync_with_main_wrapper_e2e_test.dart
//
// Rows E11 and E13 of docs/plans/sync-resolver.md section 5: the shell wrapper (arguments, locating Dart,
// the `result:` line it owns, signals) and the git configuration variants (rerere, conflictStyle, merge.ff).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/merge_scope_repo.dart';
import '../helpers/spawn.dart';
import '../helpers/sync_cli_fixture.dart';
import '../helpers/sync_resolver_fixtures.dart';

const String kOpenIssues = 'docs/audit/open_issues.md';
const String kBugClasses = '.claude/skills/debugging/bug-classes.md';

SyncCli oiScenario() {
  final c = SyncCli.create();
  c.featureCommit({kOpenIssues: board([oi(1), oi(2), oi(3)])});
  c.mainCommit({kOpenIssues: board([oi(1), oi(2), oi(4)])});
  return c;
}

SyncCli cleanScenario() {
  final c = SyncCli.create();
  c.featureCommit({'README.md': 'feature readme\n'});
  c.mainCommit({'lib/a.dart': 'line1\nmain edit\nline3\n'});
  return c;
}

/// A copy of the wrapper and `_dart_bin.sh` in a temp scripts directory next to a FIXTURE CLI whose body is [dartBody].
String fixtureScripts(SyncCli c, String dartBody) {
  final d = Directory('${c.repo.root.path}/fixture_scripts')..createSync(recursive: true);
  File('${c.srcRoot}/scripts/sync_with_main.sh').copySync('${d.path}/sync_with_main.sh');
  File('${c.srcRoot}/scripts/_dart_bin.sh').copySync('${d.path}/_dart_bin.sh');
  File('${d.path}/sync_with_main.dart').writeAsStringSync("import 'dart:io';\n\n$dartBody\n");
  return '${d.path}/sync_with_main.sh';
}

ProcessResult runFixtureWrapper(SyncCli c, String script, {List<String> args = const []}) => runSpawn(
      'sh',
      [script, ...args],
      why: 'fixture wrapper $script',
      workingDirectory: c.dir,
      extraEnv: c.repo.env,
      allowControl: ScopeRepo.allowControl,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

void main() {
  group('E11 the wrapper', () {
    test('it forwards only --commit: a clean merge is concluded', () {
      final c = cleanScenario();
      final r = c.run(['--commit'], viaWrapper: true);
      expectResult(r, 0, 'committed');
      expect(c.mergePending, isFalse);
    });

    test('any other argument is a usage error owned by the wrapper: result refused, exit 2, nothing changed', () {
      final c = cleanScenario();
      final snap = c.snapshot();
      for (final args in [
        ['--no-fetch'],
        ['--fetch-timeout-ms=1'],
        ['--force'],
        ['--commit', '--commit'],
        ['main'],
      ]) {
        final r = c.run(args, viaWrapper: true);
        expectResult(r, 2, 'refused');
        expect(stdoutOf(r), contains('sync_with_main: refused:'), reason: args.join(' '));
      }
      expect(c.snapshot(), snap);
    });

    test('it works from a subdirectory and against a repository that holds none of the scripts', () {
      final c = oiScenario();
      expect(File('${c.dir}/scripts/sync_with_main.dart').existsSync(), isFalse);
      final r = c.run([], viaWrapper: true, cwd: '${c.dir}/docs/audit');
      expectResult(r, 0, 'ready');
      expect(c.read(kOpenIssues), board([oi(1), oi(2), oi(4), oi(3)]));
    });

    test('with no dart on the PATH: result refused, exit 2', () {
      final c = cleanScenario();
      final r = c.run([], viaWrapper: true, path: c.minimalPath(['git', 'sh', 'dirname', 'tr']));
      expectResult(r, 2, 'refused');
      expect(stdoutOf(r), contains('no dart on the PATH'));
    });

    test('it runs the dart that the _dart_bin.sh next to it resolves, not whatever `dart` is on the PATH', () {
      final c = cleanScenario();
      final script = fixtureScripts(c, 'void main() {\n  stdout.writeln("result: fixture");\n}');
      final d = File(script).parent.path;
      final marker = '$d/resolved.marker';
      File('$d/marker_dart.sh').writeAsStringSync('#!/bin/sh\necho used > "$marker"\nexec "${dartBin()}" "\$@"\n');
      // Appended to the copied helper, so the later definition wins and run_dart_cli stays.
      File('$d/_dart_bin.sh').writeAsStringSync('resolve_dart_bin() {\n  echo "$d/marker_dart.sh"\n}\n', mode: FileMode.append);
      runSpawn('chmod', ['755', '$d/marker_dart.sh'], why: 'make the fixture dart executable');
      final r = runFixtureWrapper(c, script);
      expectResult(r, 0, 'fixture');
      expect(File(marker).existsSync(), isTrue, reason: 'the wrapper must run the binary resolve_dart_bin printed');
    });

    test('with a PATH holding only symlinks to dart, git, sh, dirname and tr it works, with empty stderr', () {
      final c = cleanScenario();
      final d = Directory('${c.repo.root.path}/layout')..createSync();
      Link('${d.path}/dart').createSync(dartBin());
      for (final t in ['git', 'sh', 'dirname', 'tr']) {
        Link('${d.path}/$t').createSync(whichTool(t));
      }
      final r = c.run(['--commit'], viaWrapper: true, path: d.path);
      expectResult(r, 0, 'committed');
      expect(r.stderr, isEmpty);
    });

    for (final code in [254, 255, 137, 130, 6]) {
      test('a CLI that ends with status $code is reported as result error, exit 4, as the last stdout line', () {
        final c = cleanScenario();
        final script = fixtureScripts(c, 'void main() {\n  stdout.writeln("fixture output");\n  exit($code);\n}');
        final r = runFixtureWrapper(c, script);
        expectResult(r, 4, 'error');
        expect(stdoutOf(r), contains('fixture output'));
      });
    }

    for (final code in [0, 1, 2, 3, 4]) {
      test('a CLI status of $code passes through and the wrapper adds no result line of its own', () {
        final c = cleanScenario();
        final script = fixtureScripts(c, 'void main() {\n  stdout.writeln("result: fixture");\n  exit($code);\n}');
        final r = runFixtureWrapper(c, script);
        expect(r.exitCode, code);
        expect(lastLine(stdoutOf(r)), 'result: fixture');
        expect(RegExp(r'^result: ', multiLine: true).allMatches(stdoutOf(r)).length, 1);
      });
    }

    test('a TERM sent to the wrapper reaches the CLI it started', () async {
      final c = cleanScenario();
      final pidFile = '${c.repo.root.path}/cli.pid';
      final script = fixtureScripts(c, "void main() {\n  File('$pidFile').writeAsStringSync('\$pid');\n  sleep(const Duration(seconds: 60));\n}");
      final p = await startSpawn('sh', [script], workingDirectory: c.dir, extraEnv: c.repo.env, allowControl: ScopeRepo.allowControl);
      final out = StringBuffer(), err = StringBuffer();
      final outDone = p.stdout.transform(utf8.decoder).forEach(out.write);
      final errDone = p.stderr.transform(utf8.decoder).forEach(err.write);
      final stopAt = DateTime.now().add(const Duration(seconds: 40));
      while (!File(pidFile).existsSync() && DateTime.now().isBefore(stopAt)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(File(pidFile).existsSync(), isTrue, reason: 'the fixture CLI did not start');
      final childPid = File(pidFile).readAsStringSync().trim();
      p.kill(ProcessSignal.sigterm);
      final code = await p.exitCode.timeout(const Duration(seconds: 30));
      await outDone;
      await errDone;
      reportSpawn(code, out.toString(), err.toString(), 'wrapper after a TERM: the CLI child must be reached');
      expect(code, 4);
      expect(lastLine(out.toString()), 'result: error');
      final alive = runSpawn('sh', ['-c', 'kill -0 $childPid'], why: 'is the CLI child still alive?');
      expect(alive.exitCode, isNot(0), reason: 'the TERM must reach the child');
    });

    test('a TERM makes the wrapper wait for the child\'s REAL status, not report the signal', () async {
      final c = cleanScenario();
      final readyFile = '${c.repo.root.path}/cli.ready';
      final script = fixtureScripts(c, '''
Future<void> main() async {
  ProcessSignal.sigterm.watch().listen((_) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    stdout.writeln("result: slow-exit");
    exit(3);
  });
  File('$readyFile').writeAsStringSync('up');
  await Future<void>.delayed(const Duration(seconds: 60));
}
''');
      final p = await startSpawn('sh', [script], workingDirectory: c.dir, extraEnv: c.repo.env, allowControl: ScopeRepo.allowControl);
      final out = StringBuffer(), err = StringBuffer();
      final outDone = p.stdout.transform(utf8.decoder).forEach(out.write);
      final errDone = p.stderr.transform(utf8.decoder).forEach(err.write);
      final stopAt = DateTime.now().add(const Duration(seconds: 40));
      while (!File(readyFile).existsSync() && DateTime.now().isBefore(stopAt)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(File(readyFile).existsSync(), isTrue, reason: 'the fixture CLI did not start');
      p.kill(ProcessSignal.sigterm);
      final code = await p.exitCode.timeout(const Duration(seconds: 30));
      await outDone;
      await errDone;
      reportSpawn(code, out.toString(), err.toString(), 'wrapper after a TERM: the real status of a slow-exiting CLI');
      expect(code, 3, reason: 'the child\'s status, after it finished its own shutdown');
      expect(lastLine(out.toString()), 'result: slow-exit');
    });

    test('a TERM before a CHILD EXIT 0 keeps exit 0 and ONE result line (the mirror of the exit-3 case)', () async {
      final c = cleanScenario();
      final readyFile = '${c.repo.root.path}/cli.ready';
      final script = fixtureScripts(c, '''
Future<void> main() async {
  ProcessSignal.sigterm.watch().listen((_) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    stdout.writeln("result: slow-ready");
    exit(0);
  });
  File('$readyFile').writeAsStringSync('up');
  await Future<void>.delayed(const Duration(seconds: 60));
}
''');
      final p = await startSpawn('sh', [script], workingDirectory: c.dir, extraEnv: c.repo.env, allowControl: ScopeRepo.allowControl);
      final out = StringBuffer(), err = StringBuffer();
      final outDone = p.stdout.transform(utf8.decoder).forEach(out.write);
      final errDone = p.stderr.transform(utf8.decoder).forEach(err.write);
      final stopAt = DateTime.now().add(const Duration(seconds: 40));
      while (!File(readyFile).existsSync() && DateTime.now().isBefore(stopAt)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(File(readyFile).existsSync(), isTrue, reason: 'the fixture CLI did not start');
      p.kill(ProcessSignal.sigterm);
      final code = await p.exitCode.timeout(const Duration(seconds: 30));
      await outDone;
      await errDone;
      reportSpawn(code, out.toString(), err.toString(), 'wrapper after a TERM: a slow CLI that exits 0');
      expect(code, 0, reason: 'the child\'s status, after it finished its own shutdown');
      expect(lastLine(out.toString()), 'result: slow-ready');
      expect('result:'.allMatches(out.toString()), hasLength(1), reason: 'exactly one result line');
    });

    test('the CLI itself rejects an unknown flag with exit 2 and a result line', () {
      final c = cleanScenario();
      expectResult(c.run(['--bogus']), 2, 'refused');
    });
  });

  group('E13 git configuration variants', () {
    test('rerere.enabled with rerere.autoupdate: git resolves and stages, nothing is unmerged, the tool exits 0 without an abort', () {
      final c = SyncCli.create();
      c.repo.must(['config', 'rerere.enabled', 'true']);
      c.repo.must(['config', 'rerere.autoupdate', 'true']);
      c.featureCommit({'lib/a.dart': 'line1\nours\nline3\n'});
      c.mainCommit({'lib/a.dart': 'line1\ntheirs\nline3\n'});
      expect(c.handMerge().exitCode, 1);
      c.repo.write('lib/a.dart', 'line1\nboth\nline3\n');
      c.repo.stage(['lib/a.dart']);
      c.repo.must(['commit', '-q', '-m', 'hand merge']);
      c.repo.must(['reset', '-q', '--hard', 'HEAD~1']);
      final r = c.run([]);
      expectResult(r, 0, 'ready');
      expect(c.unmerged(), isEmpty);
      expect(c.read('lib/a.dart'), 'line1\nboth\nline3\n');
      expect(c.mergePending, isTrue);
    });

    test('plain rerere.enabled: the file is resolved but not staged, so it is not overwritten and `git add` is advised', () {
      final c = SyncCli.create();
      c.repo.must(['config', 'rerere.enabled', 'true']);
      c.featureCommit({kBugClasses: '# Bug classes\n\n${bugClass('2.1')}${bugClass('2.2', body: 'ours')}'});
      c.mainCommit({kBugClasses: '# Bug classes\n\n${bugClass('2.1')}${bugClass('2.2', body: 'theirs')}'});
      expect(c.handMerge().exitCode, 1);
      final human = '# Bug classes\n\n${bugClass('2.1')}${bugClass('2.2', body: 'ours and theirs')}';
      c.repo.write(kBugClasses, human);
      c.repo.stage([kBugClasses]);
      c.repo.must(['commit', '-q', '-m', 'hand merge']);
      c.repo.must(['reset', '-q', '--hard', 'HEAD~1']);
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.read(kBugClasses), human, reason: 'rerere replayed the human resolution; the tool must not replace it');
      expect(c.unmerged(), [kBugClasses]);
      expect(stdoutOf(r), contains(RegExp(r'left\s+\.claude/skills/debugging/bug-classes\.md\s+resolved but not staged')));
    });

    for (final style in ['diff3', 'zdiff3']) {
      test('merge.conflictStyle=$style does not change what the tool resolves', () {
        final c = oiScenario();
        c.repo.must(['config', 'merge.conflictStyle', style]);
        final r = c.run([]);
        expectResult(r, 0, 'ready');
        expect(c.read(kOpenIssues), board([oi(1), oi(2), oi(4), oi(3)]));
      });
    }

    test('merge.ff=only does not turn the tool\'s --no-ff merge into a failure', () {
      final c = oiScenario();
      c.repo.must(['config', 'merge.ff', 'only']);
      final r = c.run([]);
      expectResult(r, 0, 'ready');
      expect(c.mergePending, isTrue);
    });

    test('a signing default cannot block the tool\'s own merge or the clean --commit', () {
      final c = cleanScenario();
      c.repo.must(['config', 'commit.gpgsign', 'false']);
      expectResult(c.run(['--commit']), 0, 'committed');
    });
  });
}
