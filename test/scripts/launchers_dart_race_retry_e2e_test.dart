@Timeout(Duration(minutes: 6))
library;

// OI-483: `run_dart_cli` (scripts/_dart_bin.sh), the supervised call of land_pr.sh, sync_with_main.sh and
// safe_pr_merge.sh. Each row runs the REAL wrapper and the REAL helper against a stub dart (through
// DART_BIN_OVERRIDE) that follows a plan, one step per call: a status, `slow` (sleeps until signalled, exec, so its
// pid is the one the wrapper holds), `trap3` / `trap254` (exit with that status on TERM, so the REAL status is
// visible) or `trap3x2` (exits 3 on the SECOND TERM). `perl` restores the default SIGINT and SIGHUP, because a parent
// that ignores them hands that to the shell, which cannot then trap them (land_pr_wrapper_e2e_test.dart, same recipe).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

const _control = <String>{'DART_BIN_OVERRIDE', 'AVYA_DART_RUN_RETRY'};

const _stubDart = r'''#!/bin/sh
n=$(( $(cat "$STUB_DIR/calls" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$STUB_DIR/calls"
echo $$ >> "$STUB_DIR/pids"
for a in "$@"; do printf '[%s]' "$a"; done >> "$STUB_DIR/argv"; echo >> "$STUB_DIR/argv"
step=$(echo "$STUB_PLAN" | cut -d' ' -f"$n")
[ -n "$step" ] || step=$(echo "$STUB_PLAN" | awk '{print $NF}')
case "$step" in
  slow) touch "$STUB_DIR/ready.$n"; exec /bin/sleep 60 ;;
  trap3)
    /bin/sleep 60 &
    s=$!
    trap 'kill "$s"; exit 3' TERM
    touch "$STUB_DIR/ready.$n"
    wait "$s"
    ;;
  trap254)
    /bin/sleep 60 &
    s=$!
    trap 'kill "$s"; exit 254' TERM
    touch "$STUB_DIR/ready.$n"
    wait "$s"
    ;;
  trap3x2)
    /bin/sleep 60 &
    s=$!
    seen=0
    trap 'seen=$((seen + 1)); touch "$STUB_DIR/term.$seen"; if [ "$seen" -ge 2 ]; then kill "$s"; exit 3; fi' TERM
    touch "$STUB_DIR/ready.$n"
    while :; do wait "$s"; done
    ;;
  *) exit "$step" ;;
esac
''';

const _stubSleep = r'''#!/bin/sh
echo "$1" >> "$STUB_DIR/backoffs"
touch "$STUB_DIR/in_backoff"
[ -z "${SLEEP_REAL:-}" ] || /bin/sleep "$SLEEP_REAL"
''';

/// One launcher: how to call it and what its clamp does to a status.
class Launcher {
  const Launcher(this.script, this.cli, this.args, this.clampAbove);
  final String script;
  final String cli;
  final List<String> args;
  final int? clampAbove;
  int exitFor(int status) => clampAbove != null && status > clampAbove! ? 4 : status;
  bool clamps(int status) => clampAbove != null && status > clampAbove!;
}

const launchers = [
  Launcher('land_pr.sh', 'land_pr.dart', ['191'], 7),
  Launcher('sync_with_main.sh', 'sync_with_main.dart', [], 4),
  Launcher('safe_pr_merge.sh', 'safe_pr_merge.dart', ['191'], null),
];

class Fx {
  Fx(this.dir, this.stub);
  final String dir; // a git repo whose scripts/ holds the wrapper, the real helper and a placeholder CLI
  final String stub; // what the stubs write to
  String read(String n) => File('$stub/$n').existsSync() ? File('$stub/$n').readAsStringSync() : '';
  int get calls => int.tryParse(read('calls').trim()) ?? 0;
  List<String> get argv => read('argv').split('\n').where((l) => l.isNotEmpty).toList();
  List<int> get pids => read('pids').split('\n').where((l) => l.isNotEmpty).map(int.parse).toList();
  int get backoffs => read('backoffs').split('\n').where((l) => l.isNotEmpty).length;
}

Fx build(Launcher l, Directory tmp) {
  final base = tmp.createTempSync('l_').resolveSymbolicLinksSync();
  final dir = '$base/repo';
  final stub = '$base/stub';
  Directory('$dir/scripts').createSync(recursive: true);
  Directory('$stub/bin').createSync(recursive: true);
  expect(runSpawn('git', ['init', '-q'], why: 'launcher fixture', workingDirectory: dir).exitCode, 0);
  final src = Directory.current.path;
  File('$src/scripts/${l.script}').copySync('$dir/scripts/${l.script}');
  File('$src/scripts/_dart_bin.sh').copySync('$dir/scripts/_dart_bin.sh');
  File('$dir/scripts/${l.cli}').writeAsStringSync('void main() {}\n');
  File('$stub/dart').writeAsStringSync(_stubDart);
  File('$stub/bin/sleep').writeAsStringSync(_stubSleep);
  expect(runSpawn('chmod', ['+x', '$stub/dart', '$stub/bin/sleep'], why: 'launcher fixture stubs').exitCode, 0);
  return Fx(dir, stub);
}

Map<String, String> envFor(Fx fx, String plan, {String? sleepReal, Map<String, String> extra = const {}}) => {
      'STUB_DIR': fx.stub,
      'STUB_PLAN': plan,
      'DART_BIN_OVERRIDE': '${fx.stub}/dart',
      'PATH': '${fx.stub}/bin:${Platform.environment['PATH'] ?? ''}',
      'SLEEP_REAL': ?sleepReal,
      ...extra,
    };

ProcessResult runL(Launcher l, Fx fx, String shell, String plan, {Map<String, String> extra = const {}, List<String>? args}) => runSpawn(
      shell,
      ['scripts/${l.script}', ...(args ?? l.args)],
      why: '${l.script} under $shell, plan $plan',
      workingDirectory: fx.dir,
      extraEnv: envFor(fx, plan, extra: extra),
      allowControl: _control,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

int notes(String err) => RegExp(r'\[dart-run-retry\]').allMatches(err).length;

/// Starts [l], waits for [marker], sends [signal], waits for the wrapper. Returns its exit code and stdout + stderr.
Future<({int code, String out, String err})> runAndSignal(
  Launcher l,
  Fx fx,
  String shell,
  String plan,
  String marker, {
  ProcessSignal signal = ProcessSignal.sigterm,
  String? sleepReal,
}) async {
  final p = await startSpawn(
    'perl',
    ['-e', r'$SIG{HUP} = $SIG{INT} = "DEFAULT"; exec @ARGV', shell, 'scripts/${l.script}', ...l.args],
    workingDirectory: fx.dir,
    extraEnv: envFor(fx, plan, sleepReal: sleepReal),
    allowControl: _control,
  );
  final o = StringBuffer();
  final e = StringBuffer();
  final d1 = p.stdout.transform(utf8.decoder).forEach(o.write);
  final d2 = p.stderr.transform(utf8.decoder).forEach(e.write);
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!File('${fx.stub}/$marker').existsSync() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(File('${fx.stub}/$marker').existsSync(), isTrue, reason: 'the fixture never reached $marker: $e');
  p.kill(signal);
  final code = await p.exitCode.timeout(const Duration(seconds: 45));
  await Future.wait([d1, d2]);
  reportSpawn(code, o.toString(), e.toString(), '${l.script} after a $signal', report: (_) {});
  return (code: code, out: o.toString(), err: e.toString());
}

/// True when [pid] is gone: a harmless signal to a live process succeeds.
bool dead(int pid) => !Process.killPid(pid, ProcessSignal.sigcont);

Future<void> waitFor(Fx fx, String marker) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!File('${fx.stub}/$marker').existsSync() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(File('${fx.stub}/$marker').existsSync(), isTrue, reason: 'the fixture never reached $marker');
}

/// Runs `run_dart_cli` itself, with no launcher clamp in front of its status. [prelude] goes after the helper is
/// sourced, [act] gets the driver process once it runs.
Future<({int rc, String err})> driveCli(
  Fx fx,
  String shell,
  String plan,
  Future<void> Function(Process driver) act, {
  String prelude = '',
  String? sleepReal,
}) async {
  final driver = File('${fx.stub}/driver.sh')
    ..writeAsStringSync('''
. "${Directory.current.path}/scripts/_dart_bin.sh"
$prelude
run_dart_cli "${fx.stub}/dart"
echo "RC=\$?"
''');
  final p = await startSpawn(
    'perl',
    ['-e', r'$SIG{HUP} = $SIG{INT} = "DEFAULT"; exec @ARGV', shell, driver.path],
    workingDirectory: fx.dir,
    extraEnv: envFor(fx, plan, sleepReal: sleepReal),
    allowControl: _control,
  );
  final o = p.stdout.transform(utf8.decoder).join();
  final e = p.stderr.transform(utf8.decoder).join();
  await act(p);
  final code = await p.exitCode.timeout(const Duration(seconds: 30));
  reportSpawn(code, await o, await e, 'the run_dart_cli driver', report: (_) {});
  final rc = RegExp(r'RC=(\d+)').firstMatch(await o)?.group(1);
  expect(rc, isNotNull, reason: 'the driver died before reporting: ${await o}${await e}');
  return (rc: int.parse(rc!), err: await e);
}

void main() {
  late Directory tmp;
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('launcher_race_'));
  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  for (final shell in const ['sh', 'bash']) {
    for (final l in launchers) {
      group('[$shell] ${l.script}', () {
        void expectFinal(ProcessResult r, int status) {
          expect(r.exitCode, l.exitFor(status), reason: '${r.stdout}${r.stderr}');
          if (l.clamps(status)) {
            expect('${r.stdout}'.trim().split('\n').last, 'result: error');
          }
        }

        test('a status other than 254 passes through after one call, with no note', () {
          final fx = build(l, tmp);
          final r = runL(l, fx, shell, '2');
          expectFinal(r, 2);
          expect(fx.calls, 1);
          expect(notes('${r.stderr}'), 0);
          expect(fx.backoffs, 0);
        });

        test('exit 0 stays exit 0', () {
          final fx = build(l, tmp);
          expectFinal(runL(l, fx, shell, '0'), 0);
          expect(fx.calls, 1);
        });

        test('a lost race is retried and the second attempt decides', () {
          final fx = build(l, tmp);
          final r = runL(l, fx, shell, '254 0');
          expectFinal(r, 0);
          expect(fx.calls, 2);
          expect(notes('${r.stderr}'), 1);
          expect('${r.stderr}', contains('retry 1 of 2'));
          expect('${r.stderr}', contains(l.cli));
          expect('${r.stdout}', isNot(contains('dart-run-retry')), reason: 'stdout belongs to the wrapper\'s last line');
          expect(fx.backoffs, 1);
          expect(fx.read('backoffs').trim(), '1');
        });

        test('two lost races, then a real status comes back', () {
          final fx = build(l, tmp);
          final r = runL(l, fx, shell, '254 254 1');
          expectFinal(r, 1);
          expect(fx.calls, 3);
          expect(notes('${r.stderr}'), 2);
        });

        test('the budget is 2 retries: three lost races end the run with the status today\'s call reports', () {
          final fx = build(l, tmp);
          final r = runL(l, fx, shell, '254 254 254 0');
          expectFinal(r, 254);
          expect(fx.calls, 3);
          expect(fx.backoffs, 2);
        });

        test('255 (an uncaught exception, main ran) is NOT retried', () {
          final fx = build(l, tmp);
          final r = runL(l, fx, shell, '255 0');
          expectFinal(r, 255);
          expect(fx.calls, 1);
        });

        test('the kill switch, exactly 0, is one attempt; `false` keeps the retry', () {
          final off = build(l, tmp);
          final r = runL(l, off, shell, '254 0', extra: const {'AVYA_DART_RUN_RETRY': '0'});
          expectFinal(r, 254);
          expect(off.calls, 1);
          expect(notes('${r.stderr}'), 0);
          final on = build(l, tmp);
          expectFinal(runL(l, on, shell, '254 0', extra: const {'AVYA_DART_RUN_RETRY': 'false'}), 0);
          expect(on.calls, 2);
        });

        test('a TERM during the first attempt reaches the child: it dies, no further attempt', () async {
          final fx = build(l, tmp);
          final r = await runAndSignal(l, fx, shell, 'slow', 'ready.1');
          expect(fx.calls, 1);
          expect(dead(fx.pids.single), isTrue, reason: 'an orphaned dart: ${r.err}');
          expect(r.code, l.exitFor(143), reason: r.err);
        });

        test('a TERM during a RETRY reaches that child, not a stale pid', () async {
          final fx = build(l, tmp);
          final r = await runAndSignal(l, fx, shell, '254 slow', 'ready.2');
          expect(fx.calls, 2);
          expect(dead(fx.pids.last), isTrue, reason: 'an orphaned dart: ${r.err}');
          expect(r.code, l.exitFor(143), reason: r.err);
        });

        test('a TERM during the backoff ends the run: no further attempt, the race status is reported', () async {
          final fx = build(l, tmp);
          final r = await runAndSignal(l, fx, shell, '254 0', 'in_backoff', sleepReal: '0.4');
          expect(fx.calls, 1, reason: 'a signal must stop the retry: ${r.err}');
          expect(r.code, l.exitFor(254), reason: r.err);
        });

        for (final sig in const [ProcessSignal.sigint, ProcessSignal.sighup]) {
          test('$sig is forwarded as TERM: the child dies', () async {
            final fx = build(l, tmp);
            final r = await runAndSignal(l, fx, shell, 'slow', 'ready.1', signal: sig);
            expect(dead(fx.pids.single), isTrue, reason: 'an orphaned dart: ${r.err}');
            expect(r.code, l.exitFor(143), reason: r.err);
          });
        }

        test('a TERM keeps the child\'s REAL status: the wrapper waits for it', () async {
          final fx = build(l, tmp);
          final r = await runAndSignal(l, fx, shell, 'trap3', 'ready.1');
          expect(r.code, 3, reason: r.err);
          expect(fx.calls, 1);
        });

        test('the child gets exactly the wrapper\'s arguments, and the flag when it is given', () {
          final fx = build(l, tmp);
          runL(l, fx, shell, '0');
          expect(fx.argv.single, endsWith(l.args.isEmpty ? 'scripts/${l.cli}]' : 'scripts/${l.cli}][191]'));
          if (l.args.isNotEmpty) {
            final flagged = build(l, tmp);
            runL(l, flagged, shell, '0', args: const ['191', '--allow-workflow-change']);
            expect(flagged.argv.single, endsWith('scripts/${l.cli}][191][--allow-workflow-change]'));
          }
        });

        test('REAL SDK: an empty yaml is a real 254 beside the CLI, the retry reaches its real main once', () {
          final fx = build(l, tmp);
          File('${fx.dir}/pubspec.yaml').writeAsStringSync('name: p\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n');
          File('${fx.dir}/.dart_tool/package_config.json')
            ..createSync(recursive: true)
            ..writeAsStringSync('{"configVersion":2,"packages":[{"name":"p","rootUri":"../","packageUri":"lib/","languageVersion":"3.0"}]}\n');
          final yaml = File('${fx.dir}/.dart_tool/native_assets.yaml')..writeAsStringSync('');
          File('${fx.dir}/scripts/${l.cli}').writeAsStringSync("import 'dart:io';\nvoid main() {\n  stdout.writeln('MAIN RAN');\n  exit(3);\n}\n");
          // A shim for the real dart that deletes the yaml after a 254: the writer finishing.
          final shim = File('${fx.stub}/shim')
            ..writeAsStringSync('#!/bin/sh\n"${dartBin()}" "\$@"\nrc=\$?\n'
                '[ "\$rc" = 254 ] && echo lost >> "${fx.stub}/lost" && rm -f "${yaml.path}"\nexit "\$rc"\n');
          expect(runSpawn('chmod', ['+x', shim.path], why: 'launcher fixture shim').exitCode, 0);
          final r = runL(l, fx, shell, '0', extra: {'DART_BIN_OVERRIDE': shim.path});
          expect(r.exitCode, 3, reason: '${r.stdout}${r.stderr}');
          expect(fx.read('lost').trim(), 'lost', reason: 'attempt 1 must be a REAL 254: ${r.stderr}');
          expect(RegExp('MAIN RAN').allMatches('${r.stdout}').length, 1);
          expect(notes('${r.stderr}'), 1);
          expect('${r.stderr}', contains(nativeAssetsRaceSignature), reason: 'stderr stays live');
        });
      });
    }

    group('[$shell] run_dart_cli, the signal handler', () {
      test('after the child is reaped the handler signals nothing: a pid may have been reused', () async {
        final fx = build(launchers.first, tmp);
        final r = await driveCli(
          fx,
          shell,
          '254 0',
          (p) async {
            await waitFor(fx, 'in_backoff');
            p.kill(ProcessSignal.sigterm);
          },
          prelude: 'kill() { echo "kill \$*" >> "${fx.stub}/kills"; command kill "\$@"; }',
          sleepReal: '0.4',
        );
        expect(r.rc, 254, reason: r.err);
        expect(fx.read('kills'), isNot(contains('-TERM')), reason: fx.read('kills'));
        expect(fx.calls, 1);
      });

      test('a child that answers a TERM with 254 is not retried and earns no note: the run is being stopped', () async {
        final fx = build(launchers.first, tmp);
        final r = await driveCli(fx, shell, 'trap254 0', (p) async {
          await waitFor(fx, 'ready.1');
          p.kill(ProcessSignal.sigterm);
        });
        expect(r.rc, 254, reason: r.err);
        expect(fx.calls, 1);
        expect(notes(r.err), 0, reason: r.err);
        expect(fx.backoffs, 0);
      });

      test('a second TERM interrupts the wait again: the wrapper still waits for the child and reports its REAL status', () async {
        final fx = build(launchers.first, tmp);
        final r = await driveCli(fx, shell, 'trap3x2', (p) async {
          await waitFor(fx, 'ready.1');
          p.kill(ProcessSignal.sigterm);
          await waitFor(fx, 'term.1');
          await Future<void>.delayed(const Duration(milliseconds: 100));
          p.kill(ProcessSignal.sigterm);
        });
        expect(r.rc, 3, reason: r.err);
        expect(dead(fx.pids.single), isTrue, reason: 'an orphaned dart: ${r.err}');
      });

      test('a child reaped while the handler still runs keeps its REAL status: `kill -0` finds nothing, the re-wait does', () async {
        final fx = build(launchers.first, tmp);
        final r = await driveCli(
          fx,
          shell,
          'trap3',
          (p) async {
            await waitFor(fx, 'ready.1');
            p.kill(ProcessSignal.sigterm);
          },
          // Holds the handler open until the child has exited, so the shell has reaped it before `kill -0` runs.
          prelude: 'kill() { command kill "\$@"; _k=\$?; case "\$1" in -TERM) /bin/sleep 0.4 ;; esac; return "\$_k"; }',
        );
        expect(r.rc, 3, reason: r.err);
      });

      test('a child killed from outside reports 128 + the signal: the re-wait finds no such child (127) and that is not its status', () async {
        final fx = build(launchers.first, tmp);
        final r = await driveCli(fx, shell, 'slow', (p) async {
          await waitFor(fx, 'ready.1');
          expect(Process.killPid(fx.pids.single, ProcessSignal.sigterm), isTrue);
        });
        expect(r.rc, 143, reason: r.err);
        expect(fx.calls, 1);
      });
    });
  }

  group('safe_pr_merge.sh keeps today\'s call behind the switch', () {
    int wrapperPidIfExec(Fx fx, Map<String, String> extra) {
      final r = runSpawn(
        'sh',
        ['-c', 'echo \$\$ > "${fx.stub}/wrapper"; exec sh scripts/safe_pr_merge.sh 191'],
        why: 'safe_pr_merge.sh, is the child the same process?',
        workingDirectory: fx.dir,
        extraEnv: envFor(fx, '0', extra: extra),
        allowControl: _control,
      );
      expect(r.exitCode, 0, reason: '${r.stderr}');
      return int.parse(fx.read('wrapper').trim());
    }

    test('with AVYA_DART_RUN_RETRY=0 the child IS the wrapper process: the literal exec ran', () {
      final fx = build(launchers.last, tmp);
      expect(fx.pids.isEmpty, isTrue);
      final pid = wrapperPidIfExec(fx, const {'AVYA_DART_RUN_RETRY': '0'});
      expect(fx.pids.single, pid);
    });

    test('by default the child is a background job of the wrapper, whose pid it can signal', () {
      final fx = build(launchers.last, tmp);
      final pid = wrapperPidIfExec(fx, const {});
      expect(fx.pids.single, isNot(pid));
    });

    test('a helper without the function reaches the literal exec, so a broken helper cannot stop a merge wrapper', () {
      final fx = build(launchers.last, tmp);
      File('${fx.dir}/scripts/_dart_bin.sh').writeAsStringSync('resolve_dart_bin() {\n  echo "${fx.stub}/dart"\n}\n');
      final pid = wrapperPidIfExec(fx, const {});
      expect(fx.pids.single, pid);
    });

    test('a helper that does not parse reaches the literal exec on the bare dart', () {
      final fx = build(launchers.last, tmp);
      File('${fx.dir}/scripts/_dart_bin.sh').writeAsStringSync('if then fi (\n');
      File('${fx.stub}/bin/dart').writeAsStringSync('#!/bin/sh\nexec "${fx.stub}/dart" "\$@"\n');
      expect(runSpawn('chmod', ['+x', '${fx.stub}/bin/dart'], why: 'bare dart stub').exitCode, 0);
      final pid = wrapperPidIfExec(fx, const {});
      expect(fx.pids.single, pid);
    });

    test('source pins: the supervised call precedes both exec lines and turns errexit off for the wait', () {
      final sh = File('scripts/safe_pr_merge.sh').readAsStringSync();
      final call = sh.indexOf('run_dart_cli "\$DART_BIN" scripts/safe_pr_merge.dart "\$1" "\$ALLOW"');
      expect(call, greaterThan(0));
      expect(sh.substring(0, call), contains('set +e'));
      expect(sh.substring(call), contains('run_dart_cli "\$DART_BIN" scripts/safe_pr_merge.dart "\$1"\n'));
      expect(sh.substring(call), contains('exec "\$DART_BIN" scripts/safe_pr_merge.dart "\$1" "\$ALLOW"'));
      expect(sh.substring(call), contains('exec "\$DART_BIN" scripts/safe_pr_merge.dart "\$1"\n'));
    });
  });
}
