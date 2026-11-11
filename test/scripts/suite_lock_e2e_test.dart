// test/scripts/suite_lock_e2e_test.dart
//
// One LOCAL full suite at a time (docs/plans/review-ci-suite-lock.md, CLAUDE.md §4.12.8): scripts/_suite_lock.sh,
// scripts/run_full_suite.sh, and the hooks' use of them.
//
// EVERY scenario runs in a THROWAWAY git repository with the scripts copied into it and a stub `flutter` first on
// PATH, so its lock file is that repo's `.git/avya_full_suite.lock`, never the real clone's: this file may itself run
// inside a suite that holds the real lock (scripts/run_full_suite.sh), and touching it would deadlock that suite.
// The nesting marker AVYA_SUITE_LOCK_HELD is a STRIPPED child-env name (scripts/regression_catalog_lib.dart), so the
// children below never inherit it from such a suite; the one scenario that sets it says so in `allowControl`.
//
// Linux-only where it reads /proc (the stub's fd-9 probe); flock is required (the VPS has /usr/bin/flock).
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

const String _marker = 'AVYA_SUITE_LOCK_HELD';

/// The stub `flutter`: one `start` line (argv, TZ, the marker, whether fd 9 reached it) and one `end` line, with
/// nanosecond stamps, so a test can read the ORDER of two runs instead of guessing from wall time.
const String _stubFlutter = r'''#!/bin/sh
fd9=closed
[ -e "/proc/$$/fd/9" ] && fd9=open
echo "$$ start $(date +%s%N) argv=[$*] tz=${TZ:-} marker=${AVYA_SUITE_LOCK_HELD:-} fd9=$fd9" >> "$STUB_LOG"
if [ -n "${STUB_PIDFILE:-}" ]; then echo "$$" > "$STUB_PIDFILE"; fi
sleep "${STUB_SLEEP:-0}"
echo "$$ end $(date +%s%N)" >> "$STUB_LOG"
exit "${STUB_EXIT:-0}"
''';

class _Fx {
  _Fx._(this.root, this.repo, this.stub, this.log);

  final String root;
  final String repo;
  final String stub;
  final File log;
  final List<_Run> runs = <_Run>[];
  final List<int> stubPids = <int>[];

  static _Fx create() {
    final root = Directory.systemTemp.createTempSync('suite_lock_').resolveSymbolicLinksSync();
    final repo = '$root/repo';
    Directory('$repo/scripts').createSync(recursive: true);
    for (final s in ['_suite_lock.sh', 'run_full_suite.sh']) {
      File('scripts/$s').copySync('$repo/scripts/$s');
    }
    _must('git', ['init', '--quiet'], repo);
    final stub = '$root/stub';
    Directory(stub).createSync();
    File('$stub/flutter').writeAsStringSync(_stubFlutter);
    _must('chmod', ['+x', '$stub/flutter'], root);
    final log = File('$root/stub.log')..writeAsStringSync('');
    return _Fx._(root, repo, stub, log);
  }

  static void _must(String exe, List<String> args, String cwd) {
    final r = runSpawn(exe, args, why: 'suite_lock fixture: $exe ${args.join(' ')}', workingDirectory: cwd);
    if (r.exitCode != 0) throw StateError('$exe ${args.join(' ')} failed: ${r.stderr}');
  }

  String get lockFile => '$repo/.git/avya_full_suite.lock';

  /// Starts `<shell> -c '<script>'` in the repo with the stub first on PATH (unless [path] replaces PATH entirely).
  Future<_Run> start(String script,
      {String shell = 'sh', Map<String, String> env = const {}, String? path, Set<String> allowControl = const {}}) async {
    final pathSet = path == null ? 'PATH="$stub:\$PATH"; export PATH; ' : 'PATH="$path"; export PATH; ';
    final why = 'suite_lock: $shell -c $script ${env.keys.join(',')}';
    final p = await startSpawn(shell, ['-c', '$pathSet$script'],
        workingDirectory: repo, extraEnv: {'STUB_LOG': log.path, ...env}, allowControl: allowControl);
    final r = _Run(p, why);
    runs.add(r);
    return r;
  }

  List<String> lines() => log.readAsStringSync().split('\n').where((l) => l.trim().isNotEmpty).toList();

  /// The stamp of the [kind] line (`start`/`end`) of the [n]th distinct stub pid in the log (0-based).
  int stamp(int n, String kind) {
    final pids = <String>[];
    for (final l in lines()) {
      final pid = l.split(' ').first;
      if (!pids.contains(pid)) pids.add(pid);
    }
    final pid = pids[n];
    final l = lines().firstWhere((x) => x.startsWith('$pid $kind '));
    return int.parse(l.split(' ')[2]);
  }

  Future<void> waitFor(bool Function() cond, {Duration within = const Duration(seconds: 20)}) async {
    final end = DateTime.now().add(within);
    while (!cond()) {
      if (DateTime.now().isAfter(end)) throw TimeoutException('condition not met within $within');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Kills [pid] and every descendant, deepest first: killing only the top would orphan a `sleep` (the stub's, or the
  /// one `flock … sleep` forks), the very orphan class this lock is designed around.
  static void _killTree(int pid) {
    final kids = runSpawn('pgrep', ['-P', '$pid'], why: 'suite_lock: children of $pid');
    for (final k in (kids.stdout as String).split('\n').map((l) => int.tryParse(l.trim())).whereType<int>()) {
      _killTree(k);
    }
    Process.killPid(pid, ProcessSignal.sigkill);
  }

  void dispose() {
    for (final r in runs) {
      _killTree(r.process.pid);
    }
    for (final pid in stubPids) {
      _killTree(pid);
    }
    try {
      Directory(root).deleteSync(recursive: true);
    } on FileSystemException {
      // a killed child may still hold a file for a moment; the temp dir is the OS's to reap
    }
  }
}

class _Run {
  _Run(this.process, this.why);
  final Process process;
  final String why;
  final StringBuffer out = StringBuffer();
  final StringBuffer err = StringBuffer();
  late final Future<int> done = _collect();

  Future<int> _collect() async {
    await Future.wait([
      process.stdout.transform(utf8.decoder).forEach(out.write),
      process.stderr.transform(utf8.decoder).forEach(err.write),
    ]);
    final code = await process.exitCode;
    reportSpawn(code, out.toString(), err.toString(), why);
    return code;
  }
}

void main() {
  late _Fx fx;
  setUp(() => fx = _Fx.create());
  tearDown(() => fx.dispose());

  group('run_full_suite.sh', () {
    for (final shell in ['sh', 'bash']) {
      test('[$shell] two runs never overlap: the second waits (and says so) until the first has ended', () async {
        final a = await fx.start('exec $shell scripts/run_full_suite.sh', shell: shell, env: {'STUB_SLEEP': '3'});
        await fx.waitFor(() => fx.lines().isNotEmpty);
        final b = await fx.start('exec $shell scripts/run_full_suite.sh', shell: shell);
        expect(await a.done.timeout(const Duration(seconds: 60)), 0, reason: '${a.err}');
        expect(await b.done.timeout(const Duration(seconds: 60)), 0, reason: '${b.err}');
        expect(fx.stamp(1, 'start'), greaterThanOrEqualTo(fx.stamp(0, 'end')),
            reason: 'the second suite started before the first ended: the lock did not serialise them\n${fx.lines().join('\n')}');
        expect(b.err.toString(), contains('another local full suite is running'));
        expect(b.err.toString(), contains('waiting'));
      });
    }

    test("runs exactly CI's invocation, with the marker, without fd 9, and exits with the suite's status", () async {
      final r = await fx.start('exec sh scripts/run_full_suite.sh', env: {'STUB_EXIT': '3'});
      expect(await r.done.timeout(const Duration(seconds: 60)), 3, reason: '${r.err}');
      final start = fx.lines().singleWhere((l) => l.contains(' start '));
      expect(start, contains('argv=[test test/ --exclude-tags golden]'));
      expect(start, contains('tz=Asia/Kolkata'));
      expect(start, contains('marker=1'), reason: 'a hook run inside this suite must skip the lock the suite holds');
      expect(start, contains('fd9=closed'), reason: 'a suite child that inherits fd 9 keeps the lock after the runner dies');
      expect(r.out.toString(), contains('full suite ended: exit 3'));
    });

    test('refuses any argument (usage, exit 2) and never runs the suite', () async {
      final r = await fx.start('exec sh scripts/run_full_suite.sh test/foo_test.dart');
      expect(await r.done.timeout(const Duration(seconds: 30)), 2);
      expect(r.err.toString(), contains('usage: sh scripts/run_full_suite.sh'));
      expect(fx.lines(), isEmpty);
    });

    test('no flock on the PATH: a WARNING, the suite still runs unlocked, its status is the exit status', () async {
      // A PATH of symlinks to exactly the tools the runner and the stub use, and no flock.
      final bin = Directory('${fx.root}/noflock')..createSync();
      for (final tool in ['sh', 'git', 'date', 'dirname', 'tr', 'cat', 'sleep']) {
        final w = runSpawn('sh', ['-c', 'command -v $tool'], why: 'suite_lock: locate $tool');
        Link('${bin.path}/$tool').createSync((w.stdout as String).trim());
      }
      expect(File('${bin.path}/flock').existsSync(), isFalse);
      final r = await fx.start('exec sh scripts/run_full_suite.sh', path: '${fx.stub}:${bin.path}', env: {'STUB_EXIT': '3'});
      expect(await r.done.timeout(const Duration(seconds: 60)), 3, reason: '${r.err}');
      expect(r.err.toString(), contains("no 'flock' on the PATH"));
      expect(fx.lines().where((l) => l.contains(' start ')), hasLength(1));
    });

    test('the holder SHELL is SIGKILLed while its suite child keeps running: the next run gets the lock at once', () async {
      final pidFile = '${fx.root}/stub.pid';
      final a = await fx.start('exec sh scripts/run_full_suite.sh', env: {'STUB_SLEEP': '30', 'STUB_PIDFILE': pidFile});
      await fx.waitFor(() => File(pidFile).existsSync() && File(pidFile).readAsStringSync().trim().isNotEmpty);
      final stubPid = int.parse(File(pidFile).readAsStringSync().trim());
      fx.stubPids.add(stubPid);
      a.process.kill(ProcessSignal.sigkill);
      // The exit code, not `done`: the orphaned stub still holds the killed shell's stdout/stderr pipes open.
      expect(await a.process.exitCode.timeout(const Duration(seconds: 10)), isNot(0));
      expect(Directory('/proc/$stubPid').existsSync(), isTrue, reason: 'premise: the orphaned suite child is still running');
      final b = await fx.start('exec sh scripts/run_full_suite.sh');
      // With fd 9 inherited by the child (no `9>&-`) the orphan would hold the lock for its 30 s and this times out.
      expect(await b.done.timeout(const Duration(seconds: 15)), 0, reason: '${b.err}');
      expect(b.err.toString(), isNot(contains('waiting')));
    });
  });

  group('_suite_lock.sh', () {
    for (final shell in ['sh', 'bash']) {
      test('[$shell] executing it instead of sourcing it exits 64 with the correct invocation', () async {
        final r = await fx.start('exec $shell scripts/_suite_lock.sh', shell: shell);
        expect(await r.done.timeout(const Duration(seconds: 30)), 64);
        expect(r.err.toString(), contains('must be SOURCED, not executed'));
      });
    }

    test('--no-wait with the lock held returns 1 at once and names the last recorded holder', () async {
      File('${fx.lockFile}.holder').writeAsStringSync('pid=4242 since=x dir=/somewhere\n');
      await holdLockFor(fx);
      final r = await fx.start('. scripts/_suite_lock.sh; suite_lock_acquire --no-wait; echo "rc=\$?"');
      expect(await r.done.timeout(const Duration(seconds: 10)), 0);
      expect(r.out.toString(), contains('rc=1'));
      expect(r.err.toString(), contains('last recorded holder: pid=4242 since=x dir=/somewhere'));
    });

    test('with the nesting marker the waiting mode returns 0 at once, even with the lock held', () async {
      await holdLockFor(fx);
      final r = await fx.start('. scripts/_suite_lock.sh; suite_lock_acquire; echo "rc=\$?"',
          env: {_marker: '1'}, allowControl: {_marker});
      expect(await r.done.timeout(const Duration(seconds: 10)), 0);
      expect(r.out.toString(), contains('rc=0'));
      expect(r.err.toString(), isEmpty, reason: 'the marker path is silent');
    });

    test('the waiting mode with a free lock returns 0 and records the holder', () async {
      final r = await fx.start('. scripts/_suite_lock.sh; suite_lock_acquire; echo "rc=\$?"; suite_lock_release; echo released');
      expect(await r.done.timeout(const Duration(seconds: 10)), 0);
      expect(r.out.toString(), contains('rc=0'));
      expect(r.out.toString(), contains('released'));
      expect(File('${fx.lockFile}.holder').readAsStringSync(), contains('dir=${fx.repo}'));
    });
  });

  group('the pre-push hook with the lock (a copy of the real hook in the throwaway repo)', () {
    late File calls;

    void stageHook({required bool brokenHelper}) {
      File('scripts/pre-push.sh').copySync('${fx.repo}/scripts/pre-push.sh');
      if (brokenHelper) File('${fx.repo}/scripts/_suite_lock.sh').writeAsStringSync('suite_lock_acquire() {\n  (\n');
      File('${fx.stub}/dart').writeAsStringSync('#!/bin/sh\ncat > /dev/null\nprintf "Blast-radius: feature\\n"\nexit 0\n');
      runSpawn('chmod', ['+x', '${fx.stub}/dart'], why: 'suite_lock: chmod stub dart');
      // pre-push's own flutter calls go to a second log: argv only.
      File('${fx.stub}/flutter').writeAsStringSync('#!/bin/sh\necho "\$1" >> "\$HOOK_CALLS"\nexit 0\n');
      calls = File('${fx.root}/hook_calls.log')..writeAsStringSync('');
    }

    Future<_Run> pushFull({Map<String, String> env = const {}, Set<String> allow = const {}}) => fx.start(
          'exec sh scripts/pre-push.sh < /dev/null',
          env: {'PRE_PUSH_FULL': '1', 'CONTRACT_SWEEP_SKIP': '1', 'HOOK_CALLS': calls.path, ...env},
          allowControl: {'PRE_PUSH_FULL', 'CONTRACT_SWEEP_SKIP', ...allow},
        );

    List<String> hookCalls() => calls.readAsStringSync().split('\n').where((l) => l.isNotEmpty).toList();

    test('another suite holds the lock: the full-suite path refuses at once (exit 1) and never runs the suite', () async {
      stageHook(brokenHelper: false);
      await holdLockFor(fx);
      final r = await pushFull();
      expect(await r.done.timeout(const Duration(seconds: 30)), 1, reason: '${r.out}\n${r.err}');
      expect(hookCalls(), ['analyze'], reason: 'analyze runs, the suite does not');
      expect(r.err.toString(), contains('another local full suite is running'));
    });

    test('the same, with the nesting marker: the suite runs (a hook inside a locked suite must not wait on it)', () async {
      stageHook(brokenHelper: false);
      await holdLockFor(fx);
      final r = await pushFull(env: {_marker: '1'}, allow: {_marker});
      expect(await r.done.timeout(const Duration(seconds: 30)), 0, reason: '${r.out}\n${r.err}');
      expect(hookCalls(), ['analyze', 'test']);
    });

    test('a syntactically BROKEN helper is not sourced: the hook still runs the suite (no-op lock)', () async {
      stageHook(brokenHelper: true);
      expect(runSpawn('sh', ['-n', '${fx.repo}/scripts/_suite_lock.sh'], why: 'suite_lock: premise, helper is broken').exitCode,
          isNot(0));
      final r = await pushFull();
      expect(await r.done.timeout(const Duration(seconds: 30)), 0, reason: '${r.out}\n${r.err}');
      expect(hookCalls(), ['analyze', 'test']);
    });
  });

  group('source pins (the paths the e2e above does not drive)', () {
    String code(String p) => File(p).readAsLinesSync().where((l) => !l.trimLeft().startsWith('#')).join('\n');

    test('pre-commit: PRE_COMMIT_FULL and PRE_COMMIT_LEGACY take the lock --no-wait right before their suite', () {
      final c = code('scripts/pre-commit.sh');
      for (final suite in ['  flutter test 9>&-\n', '  flutter test test/contracts/ 9>&-\n']) {
        final i = c.indexOf(suite);
        expect(i, greaterThan(-1), reason: 'missing: $suite');
        final before = c.substring(0, i).trimRight().split('\n').last.trim();
        expect(before, 'suite_lock_acquire --no-wait || exit 1', reason: 'the line before "$suite"');
      }
    });

    test('pre-push: run_full_suite takes the lock --no-wait right before its CI-equivalent invocation', () {
      final c = code('scripts/pre-push.sh');
      final i = c.indexOf('  TZ=Asia/Kolkata flutter test test/ --exclude-tags golden 9>&-\n');
      expect(i, greaterThan(-1));
      expect(c.substring(0, i).trimRight().split('\n').last.trim(), 'suite_lock_acquire --no-wait || exit 1');
    });

    test('both hooks source the helper only after a parse check, and fall back to no-op functions', () {
      for (final h in ['scripts/pre-push.sh', 'scripts/pre-commit.sh']) {
        final c = code(h);
        expect(c, contains('if [ -r "\$REPO_ROOT/scripts/_suite_lock.sh" ] && sh -n "\$REPO_ROOT/scripts/_suite_lock.sh" 2>/dev/null; then'),
            reason: h);
        expect(c, contains('type suite_lock_acquire >/dev/null 2>&1 || suite_lock_acquire() { :; }'), reason: h);
        expect(c, contains('type suite_lock_release >/dev/null 2>&1 || suite_lock_release() { :; }'), reason: h);
      }
    });
  });
}

/// Holds the throwaway repo's lock from a separate `flock … sleep` process until the fixture is disposed.
Future<void> holdLockFor(_Fx fx) async {
  await fx.start('exec flock "${fx.lockFile}" sleep 30');
  await fx.waitFor(() {
    final t = runSpawn('flock', ['-n', fx.lockFile, 'true'], why: 'suite_lock: is the lock held yet');
    return t.exitCode != 0;
  });
}
