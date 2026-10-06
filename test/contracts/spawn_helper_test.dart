// test/contracts/spawn_helper_test.dart
//
// Behaviour of test/helpers/spawn.dart, the one way a test spawns a child
// process (class 2.56 + 2.90; docs/plans/spawn-tests-env-and-stderr.md).
//
// The strip expectations here are a LITERAL list written in this file, never the
// constants exported by scripts/regression_catalog_lib.dart, so deleting a constant
// cannot delete its own assertion. The two-way check against what the repo's scripts
// actually READ is test/contracts/spawn_env_manifest_test.dart.
//
// Real child processes are Dart scripts run through `dartBin()` (not the `env`
// binary: on Windows `env` is Git for Windows' MSYS env.exe, which rewrites keys).

@Timeout(Duration(minutes: 4))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/regression_catalog_lib.dart';
import '../helpers/read_screen_source.dart';
import '../helpers/spawn.dart';

/// Every variable the helper must keep out of a child, as a literal.
const _stripped = <String>[
  'CONTRACT_SWEEP_NESTED', 'CONTRACT_SWEEP_SKIP',
  'PRE_COMMIT_FULL', 'PRE_COMMIT_LEGACY', 'PRE_COMMIT_GATE_JOBS', 'PRE_PUSH_FULL',
  'DISCIPLINE_HOOK_MEMORY_PATH', 'DISCIPLINE_HOOK_SYNC_SKIP',
  'MINT_OI_TRANSPORT', 'MINT_OI_REMOTE', 'MINT_OI_OWNER_REPO', 'MINT_OI_GH_BIN',
  'MINT_OI_TEST_HOOK_BEFORE_PUSH',
  'MINT_MIG_TRANSPORT', 'MINT_MIG_REMOTE', 'MINT_MIG_OWNER_REPO', 'MINT_MIG_GH_BIN',
  'MINT_MIG_TEST_HOOK_BEFORE_PUSH',
  'ALLOW_MAIN_COMMIT', 'ALLOW_RAW_GIT', 'FOUNDER_APPROVED_NO_VERIFY', 'PUSH_BEFORE',
  'SUPABASE_ACCESS_TOKEN', 'SUPABASE_ACCESS_TOKEN_FITNESS', 'SUPABASE_SERVICE_ROLE_KEY',
  'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'RAZORPAY_KEY_ID', 'USDA_API_KEY',
  '_SKIP_RENDER_CHECK', 'ANDROID_DEVICE_ID',
  'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_SSH_COMMAND', 'GITHUB_ACTIONS',
  'GITHUB_EVENT_PATH', 'GITHUB_REF', 'GITHUB_REPOSITORY_OWNER',
  'EMAIL',
];

/// What a child must keep seeing. `PATH` is in the list on purpose: an over-strip
/// (a prefix widened, a deny-list turned allow-list) cannot hide behind an empty map.
const _kept = <String, String>{
  'PATH': '/usr/bin', 'HOME': '/home/u', 'USERPROFILE': 'C:/u', 'TZ': 'Asia/Kolkata',
  'JAVA_HOME': '/jdk', 'ANDROID_HOME': '/a', 'ANDROID_SDK_ROOT': '/a', 'LOCALAPPDATA': 'C:/l',
  'SystemRoot': 'C:/Windows', 'PATHEXT': '.EXE', 'FLUTTER_ROOT': '/f',
  'SUPABASE_PROJECT_REF': 'k', 'ANDROID_SERIAL': 'k', 'MY_GIT_TOKEN': 'k',
};

void main() {
  group('hermeticEnvironment: what a child may inherit', () {
    test('every control variable is removed, in any letter case', () {
      for (final name in _stripped) {
        expect(hermeticEnvironment(parent: {name: 'x', 'PATH': '/p'}).keys, ['PATH'],
            reason: '$name must not reach a spawned test');
        expect(hermeticEnvironment(parent: {name.toLowerCase(): 'x', 'PATH': '/p'}).keys, ['PATH'],
            reason: '${name.toLowerCase()} (Windows environment names are case-insensitive)');
      }
    });

    test('everything the child needs stays, PATH first among them', () {
      expect(hermeticEnvironment(parent: {..._kept, 'GIT_DIR': '/x'}), _kept);
    });

    test('DART_BIN_OVERRIDE: the canonical scrub keeps it, the helper removes it, '
        'a scenario can re-supply it (the two-level rule)', () {
      const parent = {'DART_BIN_OVERRIDE': '/dart', 'PATH': '/p'};
      expect(scrubbedChildEnvironment(parent), parent,
          reason: 'the merge walk\'s flutter-test child needs it to find dart');
      expect(hermeticEnvironment(parent: parent), {'PATH': '/p'},
          reason: 'a spawned SCRIPT must not be sent to the real dart by an inherited override');
      expect(
          hermeticEnvironment(parent: parent, extra: {'DART_BIN_OVERRIDE': '/mine'}),
          {'PATH': '/p', 'DART_BIN_OVERRIDE': '/mine'});
    });

    test('`remove` is case-insensitive and is how a scenario drops a KEPT variable', () {
      final env = hermeticEnvironment(
          parent: {'HOME': '/h', 'Userprofile': 'C:/u', 'PATH': '/p'}, remove: {'home', 'USERPROFILE'});
      expect(env, {'PATH': '/p'});
    });

    test('order: scrub, helper defaults, remove, then extra LAST', () {
      // remove then extra: a variable can be removed and re-supplied.
      expect(
          hermeticEnvironment(parent: {'FOO': '1'}, remove: {'FOO'}, extra: {'FOO': '2'}), {'FOO': '2'});
      // extra wins over the parent's value.
      expect(hermeticEnvironment(parent: {'FOO': '1'}, extra: {'FOO': '3'}), {'FOO': '3'});
      // extra AFTER the scrub: a declared control variable set by the scenario survives the
      // scrub (discipline_hook_main_sync_e2e_test sets GIT_CONFIG_GLOBAL after the strip).
      expect(
          hermeticEnvironment(
              parent: {'GIT_DIR': '/leak'},
              extra: {'GIT_CONFIG_GLOBAL': '/cfg'},
              allowControl: {'GIT_CONFIG_GLOBAL'}),
          {'GIT_CONFIG_GLOBAL': '/cfg'});
    });

    test('GUARD: a control variable in `extra` throws unless declared in allowControl', () {
      // A whole-parent map passed as `extra` is the way the leak comes back
      // ({...Platform.environment, 'GIT_DIR': x}); a MINIMAL synthetic poisoned parent.
      const poisoned = {'PATH': '/p', 'CONTRACT_SWEEP_NESTED': '1', 'GIT_DIR': '/g'};
      expect(
          () => hermeticEnvironment(parent: const {}, extra: {...poisoned}),
          throwsA(isA<ArgumentError>().having((e) => '${e.message}', 'message',
              allOf(contains('CONTRACT_SWEEP_NESTED'), contains('GIT_DIR')))));
      // Declared (any case): allowed, and the value reaches the child.
      final env = hermeticEnvironment(
          parent: const {}, extra: {...poisoned}, allowControl: {'contract_sweep_nested', 'git_dir'});
      expect(env, poisoned);
      // A non-control key never needs a declaration.
      expect(hermeticEnvironment(parent: const {}, extra: {'SWEEP_RECORD': 'r'}), {'SWEEP_RECORD': 'r'});
      // Letter case never matters, on either side (Windows environment names are case-insensitive):
      // a lowercase control key still needs a declaration, and a declaration in another case counts.
      expect(() => hermeticEnvironment(parent: const {}, extra: {'git_dir': '/g'}), throwsA(isA<ArgumentError>()));
      expect(hermeticEnvironment(parent: const {}, extra: {'git_dir': '/g'}, allowControl: {'GIT_DIR'}), {'git_dir': '/g'});
      expect(hermeticEnvironment(parent: const {}, extra: {'GIT_DIR': '/g'}, allowControl: {'git_dir'}), {'GIT_DIR': '/g'});
    });

    test('the parent seam is honoured and the caller\'s map is not mutated', () {
      final parent = {'GIT_DIR': '/x', 'PATH': '/p', 'ONLY_IN_SEAM': '1'};
      final env = hermeticEnvironment(parent: parent);
      expect(env, {'PATH': '/p', 'ONLY_IN_SEAM': '1'});
      expect(parent.containsKey('GIT_DIR'), isTrue);
    });
  });

  group('spawnDiag: the failure report text', () {
    test('why, exit code, stdout and stderr, in that order, with distinct values', () {
      expect(spawnDiag(3, 'OUT', 'ERR', 'the why'), 'the why\nexit=3\nstdout=OUT\nstderr=ERR');
    });

    test('a 60-line stderr is carried whole (a compile error is many lines)', () {
      final long = [for (var i = 1; i <= 60; i++) 'lib/x.dart:$i:1: Error: line $i of a compile error'].join('\n');
      final msg = spawnDiag(254, '', long, 'why');
      expect(msg, contains('stderr=lib/x.dart:1:1: Error: line 1 of'));
      expect(msg.endsWith(long), isTrue, reason: 'nothing may be cut off the end of stderr');
    });

    test('raw bytes (stdoutEncoding: null) render without throwing', () {
      expect(spawnDiag(0, [0xff, 0x41, 0x42], '', 'raw'), contains('stdout=3 bytes \u{fffd}AB'));
    });
  });

  group('real child processes (Dart scripts through dartBin())', () {
    late Directory tmp;
    late String outErr;
    late String envDump;
    late String bytes;
    late String cwdDump;
    late String dart;

    setUpAll(() {
      tmp = Directory.systemTemp.createTempSync('spawn_helper_');
      outErr = '${tmp.path}/out_err.dart';
      File(outErr).writeAsStringSync("import 'dart:io';\n"
          'void main(List<String> a) {\n'
          "  stdout.write('OUT-LINE');\n"
          "  stderr.write('ERR-LINE');\n"
          '  exit(int.parse(a.first));\n'
          '}\n');
      envDump = '${tmp.path}/env_dump.dart';
      File(envDump).writeAsStringSync("import 'dart:convert';\nimport 'dart:io';\n"
          'void main() { stdout.write(jsonEncode(Platform.environment)); }\n');
      bytes = '${tmp.path}/bytes.dart';
      File(bytes).writeAsStringSync("import 'dart:io';\n"
          'void main() { stdout.add([0xff, 0x41]); }\n');
      cwdDump = '${tmp.path}/cwd_dump.dart';
      File(cwdDump).writeAsStringSync("import 'dart:io';\n"
          'void main() { stdout.write(Directory.current.path); }\n');
      dart = dartBin();
    });
    tearDownAll(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('runSpawn: a FAILING child is reported whole (why, exit, stdout, stderr) and returned', () {
      final reports = <String>[];
      final r = runSpawn(dart, [outErr, '3'], why: 'a failing child', report: reports.add);
      expect(r.exitCode, 3);
      expect(reports, hasLength(1), reason: 'one spawn, one report');
      expect(reports.single, 'a failing child\nexit=3\nstdout=OUT-LINE\nstderr=ERR-LINE');
    });

    test('runSpawn: a PASSING child is reported too (printOnFailure, not runSpawn, decides what is shown)', () {
      final reports = <String>[];
      final r = runSpawn(dart, [outErr, '0'], why: 'a passing child', report: reports.add);
      expect(r.exitCode, 0);
      expect(reports.single, 'a passing child\nexit=0\nstdout=OUT-LINE\nstderr=ERR-LINE');
    });

    test('runSpawnAsync reports the same way', () async {
      final reports = <String>[];
      final r = await runSpawnAsync(dart, [outErr, '4'], why: 'async child', report: reports.add);
      expect(r.exitCode, 4);
      expect(reports.single, 'async child\nexit=4\nstdout=OUT-LINE\nstderr=ERR-LINE');
    });

    test('startSpawn + reportSpawn: the child is clean, the caller reports what it collected', () async {
      final p = await startSpawn(dart, [outErr, '5']);
      final out = p.stdout.transform(utf8.decoder).join();
      final err = p.stderr.transform(utf8.decoder).join();
      final code = await p.exitCode;
      final reports = <String>[];
      reportSpawn(code, await out, await err, 'a started child', report: reports.add);
      expect(code, 5);
      expect(reports.single, 'a started child\nexit=5\nstdout=OUT-LINE\nstderr=ERR-LINE');
      // and the environment of a STARTED child is the hermetic one too
      final dump = await startSpawn(dart, [envDump],
          parentEnvironment: {'CONTRACT_SWEEP_NESTED': '1', 'KEEP_ME': '1'});
      final text = await dump.stdout.transform(utf8.decoder).join();
      await dump.exitCode;
      final child = (jsonDecode(text) as Map).cast<String, String>();
      expect(child.keys.where((k) => k.toUpperCase().startsWith('CONTRACT_SWEEP_')), isEmpty);
      expect(child['KEEP_ME'], '1');
    });

    test('the child environment is EXACTLY the declared one (a Dart child prints it)', () {
      // A MINIMAL synthetic parent, not a superset of the real environment: otherwise a
      // child that also inherited the real environment would still contain the declared
      // keys and an `includeParentEnvironment: true` mutant would survive.
      final reports = <String>[];
      final r = runSpawn(dart, [envDump],
          why: 'env dump',
          parentEnvironment: {
            'SYNTH_ONLY_IN_PARENT': 'p',
            'KEEP_ME': 'k',
            'GIT_DIR': '/leak',
            'CONTRACT_SWEEP_NESTED': '1',
            'DART_BIN_OVERRIDE': '/leak',
            'EMAIL': 'a@b',
          },
          extraEnv: {'FROM_EXTRA': 'e'},
          report: reports.add);
      expect(r.exitCode, 0, reason: reports.join('\n'));
      final child = (jsonDecode(r.stdout as String) as Map).cast<String, String>();
      // The Flutter `dart` wrapper script (used when the SDK exe beside it cannot be found)
      // adds these three itself; they are not the helper's doing.
      const wrapperAdds = {'PWD', 'SHLVL', 'FLUTTER_ROOT', '_'};
      final seen = {
        for (final e in child.entries)
          if (!wrapperAdds.contains(e.key.toUpperCase())) e.key.toUpperCase(): e.value,
      };
      expect(seen, {'SYNTH_ONLY_IN_PARENT': 'p', 'KEEP_ME': 'k', 'FROM_EXTRA': 'e'},
          reason: 'exactly the parent minus the control variables (and DART_BIN_OVERRIDE), plus extra');
    });

    test('workingDirectory is forwarded', () {
      final dir = Directory('${tmp.path}/sub')..createSync();
      final r = runSpawn(dart, [cwdDump], why: 'cwd', workingDirectory: dir.path);
      expect(r.exitCode, 0);
      expect(Directory(r.stdout as String).resolveSymbolicLinksSync(), dir.resolveSymbolicLinksSync());
    });

    test('runInShell is forwarded (a shell BUILTIN is only reachable through a shell)', () {
      // `export` exists only as a POSIX shell builtin, `echo` only as a cmd.exe builtin:
      // no executable of that name is on PATH, so without a shell the spawn throws.
      final builtin = Platform.isWindows ? 'echo' : 'export';
      final r = runSpawn(builtin, const ['X=1'], why: 'shell builtin', runInShell: true);
      expect(r.exitCode, 0);
      expect(() => runSpawn(builtin, const ['X=1'], why: 'no shell'), throwsA(isA<ProcessException>()),
          reason: 'without runInShell the builtin name is looked up as an executable');
    });

    test('encoding defaults equal Process.runSync\'s, and an explicit null returns bytes from BOTH entry points', () async {
      final viaHelper = runSpawn(dart, [outErr, '0'], why: 'defaults', report: (_) {});
      final viaProcess = Process.runSync(dart, [outErr, '0'], includeParentEnvironment: false, environment: {});
      expect(viaHelper.stdout.runtimeType, viaProcess.stdout.runtimeType);
      expect(viaHelper.stdout, isA<String>());

      final reports = <String>[];
      final sync = runSpawn(dart, [bytes], why: 'raw bytes', stdoutEncoding: null, report: reports.add);
      expect(sync.stdout, [0xff, 0x41]);
      final async =
          await runSpawnAsync(dart, [bytes], why: 'raw bytes async', stdoutEncoding: null, report: reports.add);
      expect(async.stdout, [0xff, 0x41]);
      expect(reports, everyElement(contains('stdout=2 bytes ')),
          reason: 'the reporter must not crash on a List<int> stdout');
    });
  });

  group('defaultSpawnReport: the two zones (class 2.90, round 1 R1-05 / round 2 finding 5)', () {
    // `printOnFailure` throws StateError outside a test zone, and nine test files spawn
    // `which dart` from main() at load time. A null #test.invoker in a child zone
    // shadows the parent's (zone.dart), a faithful stand-in for "no current invoker".
    late Directory tmp;
    late String outErr;
    late String dart;

    setUpAll(() {
      tmp = Directory.systemTemp.createTempSync('spawn_report_');
      outErr = '${tmp.path}/out_err.dart';
      File(outErr).writeAsStringSync("import 'dart:io';\n"
          'void main(List<String> a) {\n'
          "  stdout.write('OUT-LINE');\n"
          "  stderr.write('ERR-LINE');\n"
          '  exit(int.parse(a.first));\n'
          '}\n');
      dart = dartBin();
    });
    tearDownAll(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    List<String> runIn(Map<Object?, Object?>? zoneValues, int exitCode) {
      final printed = <String>[];
      runZoned(
        () => runSpawn(dart, [outErr, '$exitCode'], why: 'zone probe'),
        zoneValues: zoneValues,
        zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) => printed.add(line)),
      );
      return printed;
    }

    test('no current invoker + success: silent (a successful `which dart` must not print)', () {
      expect(runIn({#test.invoker: null}, 0), isEmpty);
    });

    test('no current invoker + failure: the whole diagnostic is printed', () {
      final printed = runIn({#test.invoker: null}, 3);
      expect(printed, hasLength(1));
      expect(printed.single, 'zone probe\nexit=3\nstdout=OUT-LINE\nstderr=ERR-LINE');
    });

    test('inside a (passing) test the default prints NOTHING: printOnFailure buffers it', () {
      // Kills the "print as the default" mutant behaviourally: a plain print would show here.
      expect(runIn(null, 0), isEmpty);
      expect(runIn(null, 3), isEmpty);
    });

    test('the default reporter is printOnFailure in a test zone and a failing-only print outside', () {
      final src = readSourceFileStripped('test/helpers/spawn.dart');
      final start = src.indexOf('void defaultSpawnReport(');
      final end = src.indexOf('ProcessResult runSpawn(');
      expect(start, greaterThan(-1));
      final body = src.substring(start, end);
      expect(RegExp(r'try\s*\{\s*printOnFailure\(diag\);\s*\}\s*on StateError\s*\{\s*if \(exitCode != 0\) \{\s*print\(diag\);')
          .hasMatch(body), isTrue,
          reason: 'printOnFailure first; on a missing invoker, print only a failed child');
    });
  });

  group('the helper\'s wiring (PRESENCE and ORDER; the effect is the real runs above)', () {
    late String src;
    setUpAll(() => src = readSourceFileStripped('test/helpers/spawn.dart'));

    String bodyOf(String signature, String next) {
      final start = src.indexOf(signature);
      final end = src.indexOf(next, start + 1);
      expect(start, greaterThan(-1), reason: '$signature must exist');
      expect(end, greaterThan(start), reason: '$next must follow $signature');
      return src.substring(start, end);
    }

    test('runSpawn spawns, THEN reports that very result, then returns it', () {
      final body = bodyOf('ProcessResult runSpawn(', 'Future<ProcessResult> runSpawnAsync(');
      expect(
          RegExp(r'final result = Process\.runSync\([^;]*\);\s*'
                  r'reportSpawn\(result\.exitCode, result\.stdout, result\.stderr, why, report: report\);\s*'
                  r'return result;\s*\}')
              .hasMatch(body),
          isTrue,
          reason: 'no condition around the report, no early return before it, `why` carried through');
      expect(body, contains('includeParentEnvironment: false'));
    });

    test('runSpawnAsync does the same', () {
      final body = bodyOf('Future<ProcessResult> runSpawnAsync(', 'Future<Process> startSpawn(');
      expect(
          RegExp(r'final result = await Process\.run\([^;]*\);\s*'
                  r'reportSpawn\(result\.exitCode, result\.stdout, result\.stderr, why, report: report\);\s*'
                  r'return result;\s*\}')
              .hasMatch(body),
          isTrue);
      expect(body, contains('includeParentEnvironment: false'));
    });

    test('startSpawn never inherits the parent either', () {
      expect(bodyOf('Future<Process> startSpawn(', 'void reportSpawn(').contains('includeParentEnvironment: false'),
          isTrue);
    });

    test('the hermetic environment applies scrub, helper defaults, remove, then extra (in that order)', () {
      final body = bodyOf('Map<String, String> hermeticEnvironment(', 'String spawnDiag(');
      final scrub = body.indexOf('scrubbedChildEnvironment(parent ?? Platform.environment)');
      final defaults = body.indexOf('...spawnDefaultRemovals');
      final remove = body.indexOf('...remove.map');
      final extra = body.indexOf('env.addAll(extra)');
      expect(scrub, greaterThan(-1));
      expect(defaults, greaterThan(scrub));
      expect(remove, greaterThan(defaults));
      expect(extra, greaterThan(remove));
    });

    test('the encodings are defaulted parameters, not `?? systemEncoding` (an explicit null must survive)', () {
      expect(src, isNot(contains('?? systemEncoding')));
      expect(RegExp(r'Encoding\? stdoutEncoding = systemEncoding,').allMatches(src).length, 2);
      expect(RegExp(r'Encoding\? stderrEncoding = systemEncoding,').allMatches(src).length, 2);
    });
  });
}
