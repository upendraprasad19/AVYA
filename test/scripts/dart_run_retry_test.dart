// test/scripts/dart_run_retry_test.dart
//
// OI-482: the git hooks' `"$DART_BIN" run` sites contain the `dart run` native-assets race.
// Plan: docs/plans/2026-11-06-oi482-hook-dart-run-race.md. Diagnose: b7e2d9 (the mechanism),
// the OI-482 diagnose beside it (this change).
//
// WHAT IS UNDER TEST. `_dart_run_retrying` and `use_dart_race_retry`, two shell functions in
// scripts/_dart_bin.sh: `use_dart_race_retry` makes DART_BIN the NAME of the function, so the 22
// unchanged call sites of the five hooks run it; the function re-runs a `dart run` that exits 254
// WITH the signature on stderr (the child died before `main`), at most twice, and prints one note
// per retry. The hooks themselves run in test/scripts/hooks_dart_run_retry_e2e_test.dart.
//
// FOUR KINDS OF EVIDENCE, because a stub only proves the function against the author's picture of dart:
//   1. a table against a STUB dart (call counts by marker file, argv, stdin, closed fds, set -e / -u),
//   2. the REAL SDK: an EMPTY .dart_tool/native_assets.yaml makes `dart bin/x.dart` and `dart run <abs>`
//      exit 254 with the signature, deterministically and with no timing (the canary); the function
//      around a SHIM that heals the file after a real 254 retries a REAL failure to a REAL success,
//      with a stdin payload read by a real Dart script,
//   3. the kill switch (AVYA_DART_RUN_RETRY=0 restores today's call: the same real failure comes back),
//   4. pins on the wiring text of the five hooks and of the gate loop.
//
// SPAWN SHAPE. Every child here is a `sh` driver (a wrapper is NOT retried by the OI-468 helper,
// test/helpers/spawn.dart), so a real 254 is never retried twice and no bogus `[spawn-retry]` line
// reaches a CI log. The absolute dart comes from dartBin() (the flutter_tester trap). cwd is a throwaway
// directory, never the repo root (a `dart run` there would WRITE the shared native_assets.yaml).

@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

const _control = <String>{'AVYA_DART_RUN_RETRY'};

/// Stubs on a PATH, /bin symlinks and `sh`: POSIX only. A Windows (Git Bash) check is the founder's A/B with the kill switch.
final String? _posixOnly = Platform.isWindows ? 'POSIX-only: stub dart/sleep on PATH, /bin links (the Windows check is the kill-switch A/B)' : null;

void posixGroup(String name, void Function() body) => group(name, body, skip: _posixOnly);

late Directory tmp;
late String helper;
late String stub;
var _seq = 0;

/// One run of a driver: its result and the files its stubs left behind.
class Run {
  Run(this.id, this.r);
  final String id;
  final ProcessResult r;
  String get out => '${r.stdout}';
  String get err => '${r.stderr}';
  int get exit => r.exitCode;
  String _file(String suffix) => '${tmp.path}/$id.$suffix';
  List<String> _lines(String suffix) =>
      File(_file(suffix)).existsSync() ? File(_file(suffix)).readAsLinesSync() : <String>[];

  /// How many times the stub dart ran.
  int get calls => File(_file('mark')).existsSync() ? int.parse(File(_file('mark')).readAsStringSync().trim()) : 0;

  /// One entry per stub call: its argv, each argument in brackets.
  List<String> get argv => _lines('mark.args');

  /// The arguments the logging `sleep` stub received (one line per backoff).
  List<String> get backoff => _lines('backoff');
  int get notes => RegExp(r'\[dart-run-retry\]').allMatches(err).length;
}

const _driver = r'''
@@OPTS@@
. "$HELPER"
unset DART_BIN_REAL
PATH="$TMP/bin:$PATH"
DART_BIN="$STUB"
use_dart_race_retry
@@BODY@@
''';

/// Runs [body] in a `sh` driver that sources the REAL scripts/_dart_bin.sh, puts a logging `sleep` stub
/// first on PATH, points DART_BIN at [stub] and calls `use_dart_race_retry` (as a hook does).
Run drive(
  String body, {
  String opts = '',
  Map<String, String> env = const {},
  Set<String> allowControl = const {},
}) {
  final id = 'd${_seq++}';
  final file = File('${tmp.path}/$id.sh')
    ..writeAsStringSync(_driver.replaceFirst('@@OPTS@@', opts).replaceFirst('@@BODY@@', body));
  final r = runSpawn(
    'sh',
    [file.path],
    why: 'dart_run_retry driver $id',
    workingDirectory: tmp.path,
    extraEnv: {
      'HELPER': helper,
      'STUB': stub,
      'TMP': tmp.path,
      'STUB_MARK': '${tmp.path}/$id.mark',
      'BACKOFF_LOG': '${tmp.path}/$id.backoff',
      ...env,
    },
    allowControl: allowControl,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  return Run(id, r);
}

const _stubDart = r'''#!/bin/sh
# Stub dart. STUB_MARK counts calls, STUB_MARK.args logs each call's argv; the first STUB_FAIL_UNTIL calls fail
# in the STUB_MODE shape, later ones succeed (STUB_RC, STUB_READ_STDIN, STUB_OK_STDERR). It never reads stdin on a
# failing call (a child that dies before main leaves its stdin unread).
n=$(( $(cat "$STUB_MARK" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$STUB_MARK"
for a in "$@"; do printf '[%s]' "$a"; done >> "$STUB_MARK.args"; echo >> "$STUB_MARK.args"
fail=no
[ "$n" -le "${STUB_FAIL_UNTIL:-0}" ] && fail=yes
case " ${STUB_FAIL_CALLS:-} " in *" $n "*) fail=yes ;; esac
if [ "$fail" = yes ]; then
  case "${STUB_MODE:-sig}" in
    sig)   printf 'Running build hooks...'; echo 'File not formatted as yaml: .' >&2; exit 254 ;;
    long)  printf 'Running build hooks...'
           i=0; while [ "$i" -lt 20 ]; do echo "line $i noise noise noise noise" >&2; i=$((i+1)); done
           echo 'File not formatted as yaml: .' >&2; exit 254 ;;
    nosig) echo 'some other error' >&2; exit 254 ;;
    exit1) echo 'File not formatted as yaml: .' >&2; exit 1 ;;
    stdout) echo 'File not formatted as yaml: .'; exit 254 ;;
  esac
fi
if [ -n "${STUB_READ_STDIN:-}" ]; then printf 'STDIN:%s\n' "$(cat)"; fi
echo "ran $*"
[ -z "${STUB_OK_STDERR:-}" ] || echo 'warning on success' >&2
exit "${STUB_RC:-0}"
''';

void main() {
  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('dart_run_retry_');
    helper = '${Directory.current.path}/scripts/_dart_bin.sh';
    stub = '${tmp.path}/stubdart.sh';
    File(stub).writeAsStringSync(_stubDart);
    Directory('${tmp.path}/bin').createSync();
    File('${tmp.path}/bin/sleep')
        .writeAsStringSync('#!/bin/sh\necho "\$1" >> "\$BACKOFF_LOG"\n[ -z "\${SLEEP_FAIL:-}" ] || exit 1\n');
    File('${tmp.path}/bin/dart').writeAsStringSync('#!/bin/sh\nexec "\$STUB" "\$@"\n');
    final chmod = runSpawn('chmod', ['+x', stub, '${tmp.path}/bin/sleep', '${tmp.path}/bin/dart'],
        why: 'dart_run_retry: make the stubs executable');
    expect(chmod.exitCode, 0);
  });
  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  posixGroup('the function against a stub dart', () {
    const run = '"\$DART_BIN" run scripts/x.dart';

    test('a lost race is retried once and the second answer is returned; the note starts on its own line', () {
      final r = drive('$run\necho "RC=\$?"', env: {'STUB_FAIL_UNTIL': '1'});
      expect(r.exit, 0, reason: '${r.out}|${r.err}');
      expect(r.calls, 2);
      expect(r.out, contains('RC=0'));
      expect(r.out, contains('ran run scripts/x.dart'));
      expect(r.err, startsWith('\n[dart-run-retry] native-assets race: retry 1 of 2 | run scripts/x.dart | exit=254 | stderr=File not formatted as yaml: .'));
      expect(r.notes, 1);
      expect(r.backoff, ['1'], reason: 'one `sleep 1` before the one retry');
    });

    test('an always-failing race: exactly 3 attempts, 2 notes, the 254 and the child\'s own stderr come back last', () {
      final r = drive('rc=0\n$run || rc=\$?\necho "RC=\$rc"', env: {'STUB_FAIL_UNTIL': '9'});
      expect(r.out, contains('RC=254'));
      expect(r.calls, 3);
      expect(r.notes, 2);
      expect(r.backoff, ['1', '1'], reason: 'N-1 backoffs for N attempts: none before the first, none after the last');
      expect(r.err.trimRight(), endsWith('File not formatted as yaml: .'));
      expect(r.err, contains('retry 2 of 2'));
    });

    for (final c in <({String name, String mode, int rc, String stream, String text})>[
      (name: '254 without the signature', mode: 'nosig', rc: 254, stream: 'err', text: 'some other error'),
      (name: 'the signature with exit 1', mode: 'exit1', rc: 1, stream: 'err', text: 'File not formatted as yaml'),
      (name: 'the signature on STDOUT only', mode: 'stdout', rc: 254, stream: 'out', text: 'File not formatted as yaml'),
    ]) {
      test('${c.name} runs exactly once (not the race)', () {
        final r = drive('rc=0\n$run || rc=\$?\necho "RC=\$rc"', env: {'STUB_FAIL_UNTIL': '9', 'STUB_MODE': c.mode});
        expect(r.out, contains('RC=${c.rc}'));
        expect(r.calls, 1);
        expect(r.notes, 0);
        expect(r.backoff, isEmpty);
        expect(c.stream == 'out' ? r.out : r.err, contains(c.text), reason: 'the child\'s own text is not swallowed');
      });
    }

    test('an ordinary failing status passes through after one call, and a success with stderr text is re-emitted', () {
      final f = drive('rc=0\n$run || rc=\$?\necho "RC=\$rc"', env: {'STUB_RC': '3'});
      expect(f.out, contains('RC=3'));
      expect(f.calls, 1);
      final ok = drive(run, env: {'STUB_OK_STDERR': '1'});
      expect(ok.exit, 0);
      expect(ok.err, contains('warning on success'));
      expect(ok.out, contains('ran run scripts/x.dart'), reason: 'stdout passes straight through');
    });

    test('only `run` is retried: --version and pub get with a 254+signature stub run once', () {
      for (final args in ['--version', 'pub get', '']) {
        final r = drive('rc=0\n"\$DART_BIN" $args || rc=\$?\necho "RC=\$rc"', env: {'STUB_FAIL_UNTIL': '5'});
        expect(r.out, contains('RC=254'), reason: 'args=[$args]');
        expect(r.calls, 1, reason: 'args=[$args]');
        expect(r.notes, 0, reason: 'args=[$args]');
      }
    });

    test('OI-483: the plain form is retried too, argv kept, and the note names the script', () {
      for (final script in ['scripts/x.dart', '/abs dir/x.dart']) {
        final r = drive('rc=0\n"\$DART_BIN" "$script" a || rc=\$?\necho "RC=\$rc"', env: {'STUB_FAIL_UNTIL': '1'});
        expect(r.out, contains('RC=0'), reason: script);
        expect(r.calls, 2, reason: script);
        expect(r.notes, 1, reason: script);
        expect(r.err, contains(script));
        expect(r.argv, ['[$script][a]', '[$script][a]']);
      }
    });

    test('OI-483: only a first argument ENDING in .dart is the plain form: a flag first, or a longer name, runs once', () {
      for (final args in ['--enable-asserts x.dart', 'x.dart.bak', 'x.dartx']) {
        final r = drive('rc=0\n"\$DART_BIN" $args || rc=\$?\necho "RC=\$rc"', env: {'STUB_FAIL_UNTIL': '5'});
        expect(r.out, contains('RC=254'), reason: 'args=[$args]');
        expect(r.calls, 1, reason: 'args=[$args]');
      }
    });

    test('OI-483: the plain form honours the budget and the kill switch', () {
      final budget = drive('rc=0\n"\$DART_BIN" x.dart || rc=\$?\necho "RC=\$rc"', env: {'STUB_FAIL_UNTIL': '5'});
      expect(budget.out, contains('RC=254'));
      expect(budget.calls, 3);
      final off = drive('rc=0\n"\$DART_BIN" x.dart || rc=\$?\necho "RC=\$rc"',
          env: {'STUB_FAIL_UNTIL': '1', 'AVYA_DART_RUN_RETRY': '0'}, allowControl: _control);
      expect(off.out, contains('RC=254'));
      expect(off.calls, 1);
    });

    test('argv survives a retry byte for byte: spaces, a glob, an empty argument, a quote', () {
      final r = drive('"\$DART_BIN" run \'a b\' \'*\' \'\' \'c"d\'', env: {'STUB_FAIL_UNTIL': '1'});
      expect(r.exit, 0);
      expect(r.argv, ['[run][a b][*][][c"d]', '[run][a b][*][][c"d]']);
    });

    test('stdin is read by the retry: a child that died before main left the pipe unread', () {
      final r = drive('printf \'payload-line\\n\' | $run -', env: {'STUB_FAIL_UNTIL': '1', 'STUB_READ_STDIN': '1'});
      expect(r.exit, 0);
      expect(r.out, contains('STDIN:payload-line'));
      expect(r.calls, 2);
    });

    test('a note for a long multi-line stderr is ONE line, cut at 300 characters, after a leading newline', () {
      final r = drive(run, env: {'STUB_FAIL_UNTIL': '1', 'STUB_MODE': 'long'});
      final lines = r.err.split('\n');
      expect(lines.first, '', reason: 'the note starts with a newline: real dart prints its preamble with none');
      final note = lines.where((l) => l.startsWith('[dart-run-retry]')).single;
      expect(note.substring(note.indexOf('stderr=') + 7).length, 300);
      expect(note, contains('line 0 noise'));
    });

    test('stdout CLOSED: the child still runs and its status is returned (the capture idiom must not skip it)', () {
      final r = drive('rc=0\n$run >&- || rc=\$?\necho "RC=\$rc" >&2', env: {'STUB_RC': '7'});
      expect(r.err, contains('RC=7'));
      expect(r.calls, 1, reason: 'ran once; the unfixed idiom returned 0 without running it');
    });

    test('stderr CLOSED under set -e: the hook survives a note it cannot print', () {
      final r = drive('$run 2>&-\necho SURVIVED', opts: 'set -e', env: {'STUB_FAIL_UNTIL': '1'});
      expect(r.out, contains('SURVIVED'));
      expect(r.calls, 2);
    });

    test('set -eu: nothing aborts, and a call with no arguments runs the real binary plainly', () {
      final r = drive('$run\necho "after:\$?"\n"\$DART_BIN"', opts: 'set -eu', env: {'STUB_FAIL_UNTIL': '1'});
      expect(r.exit, 0, reason: '${r.out}|${r.err}');
      expect(r.out, contains('after:0'));
      expect(r.calls, 3, reason: 'two for the retried run, one for the bare call');
    });

    test('a backoff that FAILS (sleep exits 1) does not abort a set -e hook: the retry still happens', () {
      final r = drive('$run\necho "after:\$?"', opts: 'set -e', env: {'STUB_FAIL_UNTIL': '1', 'SLEEP_FAIL': '1'});
      expect(r.exit, 0, reason: '${r.out}|${r.err}');
      expect(r.out, contains('after:0'));
      expect(r.calls, 2);
    });

    test('no tr on PATH under set -e: the retry still happens, the note is just empty', () {
      final nobin = Directory('${tmp.path}/nobin')..createSync();
      Link('${nobin.path}/cat').createSync('/bin/cat');
      File('${nobin.path}/sleep').writeAsStringSync('#!/bin/sh\n:\n');
      expect(runSpawn('chmod', ['+x', '${nobin.path}/sleep'], why: 'dart_run_retry: nobin sleep').exitCode, 0);
      final r = drive('PATH="\$TMP/nobin"\n$run\necho "after:\$?"', opts: 'set -e', env: {'STUB_FAIL_UNTIL': '1'});
      expect(r.exit, 0, reason: '${r.out}|${r.err}');
      expect(r.out, contains('after:0'));
      expect(r.calls, 2);
      expect(r.err, contains('[dart-run-retry]'));
    });

    test('stdout CLOSED under set -e: the capture group\'s failed redirect must not abort the hook', () {
      final r = drive('$run >&-\necho SURVIVED >&2', opts: 'set -e');
      expect(r.err, contains('SURVIVED'));
      expect(r.calls, 1);
    });

    test('stderr CLOSED under set -e with text on stderr to re-emit: the final printf must not abort the hook', () {
      final r = drive('$run 2>&-\necho SURVIVED', opts: 'set -e', env: {'STUB_OK_STDERR': '1'});
      expect(r.out, contains('SURVIVED'));
      expect(r.calls, 1);
    });

    test('DART_BIN_REAL UNSET under set -u: the function falls back to dart on PATH instead of an unbound variable', () {
      final r = drive('unset DART_BIN_REAL\n$run\necho done', opts: 'set -u');
      expect(r.exit, 0, reason: '${r.out}|${r.err}');
      expect(r.out, contains('done'));
      expect(r.calls, 1, reason: 'bin/dart forwarded to the stub');
    });

    test('a same-shell SEQUENCE: each call gets its own retry budget and its own ran-flag', () {
      final r = drive(
        '$run; echo "A:\$?"\n$run; echo "B:\$?"\nrc=0; $run >&- || rc=\$?; echo "C:\$rc" >&2\n',
        env: {'STUB_FAIL_CALLS': '1 2 4 5'},
      );
      expect(r.out, contains('A:0'));
      expect(r.out, contains('B:0'), reason: 'a stale retry counter would leave B with no retries and return 254');
      expect(r.calls, 7, reason: 'A: 3 calls, B: 3 calls, C: 1 call; a stale ran-flag would skip C');
      expect(r.err, contains('C:0'));
    });

    test('in a pipeline, a background subshell and a command substitution the function is what runs', () {
      final r = drive(
        'x=\$($run)\n'
        'echo "SUBST:\$x"\n'
        '( $run >"\$TMP/bg.out" 2>&1 ) &\nwait\n'
        'echo "BG:\$(cat "\$TMP/bg.out")"\n'
        '$run | cat\n',
        env: {'STUB_FAIL_UNTIL': '1'},
      );
      expect(r.exit, 0, reason: '${r.out}|${r.err}');
      expect(r.out, contains('SUBST:Running build hooks...ran run scripts/x.dart'));
      expect(r.calls, 4, reason: 'call 1 fails and is retried (2); calls 3 and 4 succeed first time');
    });
  });

  posixGroup('use_dart_race_retry', () {
    test('it wraps by default, is idempotent, and keeps the real binary', () {
      final r = drive('use_dart_race_retry\necho "\$DART_BIN|\$DART_BIN_REAL"');
      expect(r.out.trim(), '_dart_run_retrying|$stub');
    });

    for (final v in ['false', 'off', '']) {
      test('AVYA_DART_RUN_RETRY=[$v] does NOT disable it (only the exact value 0 does)', () {
        final r = drive('echo "\$DART_BIN"', env: {'AVYA_DART_RUN_RETRY': v}, allowControl: _control);
        expect(r.out.trim(), '_dart_run_retrying');
      });
    }

    test('AVYA_DART_RUN_RETRY=0 leaves DART_BIN alone: today\'s call, no retry', () {
      final r = drive('echo "\$DART_BIN"\nrc=0\n"\$DART_BIN" run scripts/x.dart || rc=\$?\necho "RC=\$rc"',
          env: {'AVYA_DART_RUN_RETRY': '0', 'STUB_FAIL_UNTIL': '1'}, allowControl: _control);
      expect(r.out, contains(stub));
      expect(r.out, contains('RC=254'));
      expect(r.calls, 1);
      expect(r.notes, 0);
    });

    test('an empty DART_BIN is left empty (and DART_BIN_REAL stays unset)', () {
      final r = drive('echo "[\$DART_BIN][\${DART_BIN_REAL:-unset}]"', env: {'STUB': ''});
      expect(r.out.trim(), '[][unset]');
    });

    test('a helper that has the setter but LOST the function leaves DART_BIN alone: the sites keep working instead of "not found"', () {
      final r = drive('unset -f _dart_run_retrying\nDART_BIN="\$STUB"\nuse_dart_race_retry\necho "[\$DART_BIN]"\n"\$DART_BIN" run scripts/x.dart\necho "rc=\$?"');
      expect(r.out, contains('[$stub]'));
      expect(r.out, contains('rc=0'), reason: '${r.out}|${r.err}');
      expect(r.calls, 1);
      expect(r.err, isNot(contains('not found')));
    });

    test('DART_BIN_REAL naming the function itself does not recurse: it falls back to the dart on PATH', () {
      final r = drive('DART_BIN_REAL=_dart_run_retrying\n"\$DART_BIN" run scripts/x.dart\necho done');
      expect(r.out, contains('done'));
      expect(r.calls, 1, reason: 'bin/dart (first on PATH) forwarded to the stub exactly once');
    });
  });

  posixGroup('the REAL SDK (an empty .dart_tool/native_assets.yaml is the deterministic race)', () {
    late String dart;
    late String pkg;
    late String yaml;
    late String shim;
    setUpAll(() {
      dart = dartBin();
      pkg = '${tmp.path}/pkg';
      yaml = '$pkg/.dart_tool/native_assets.yaml';
      Directory('$pkg/bin').createSync(recursive: true);
      Directory('$pkg/.dart_tool').createSync(recursive: true);
      Directory('${tmp.path}/cwd').createSync();
      File('$pkg/pubspec.yaml').writeAsStringSync('name: canary\nenvironment:\n  sdk: ^3.0.0\n');
      File('$pkg/.dart_tool/package_config.json').writeAsStringSync(
          '{"configVersion":2,"packages":[{"name":"canary","rootUri":"../","packageUri":"lib/","languageVersion":"3.0"}]}');
      File('$pkg/bin/x.dart').writeAsStringSync(
          "import 'dart:io';\nvoid main() { stdout.write('STDIN:' + (stdin.readLineSync() ?? '')); }\n");
      shim = '${tmp.path}/shim.sh';
      File(shim).writeAsStringSync(
          '#!/bin/sh\n"\$REAL_DART" "\$@"\nrc=\$?\nif [ "\$rc" = 254 ]; then rm -f "\$PKG/.dart_tool/native_assets.yaml"; fi\nexit \$rc\n');
      expect(runSpawn('chmod', ['+x', shim], why: 'dart_run_retry: shim executable').exitCode, 0);
    });
    void emptyYaml() => File(yaml).writeAsStringSync('');
    void noYaml() {
      if (File(yaml).existsSync()) File(yaml).deleteSync();
    }

    // Through a `sh` wrapper on purpose: the OI-468 helper retries a dart child that exits 254 with the
    // signature, and these children are SUPPOSED to fail once.
    ProcessResult real(String form) => runSpawn(
          'sh',
          ['-c', form == 'run' ? 'echo hi | "\$0" run "\$1"' : 'echo hi | "\$0" "\$1"', dart,
            form == 'run' ? '$pkg/bin/x.dart' : 'bin/x.dart'],
          why: 'real SDK $form',
          workingDirectory: form == 'run' ? '${tmp.path}/cwd' : pkg,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );

    test('CONTROL: with no yaml both forms run (so a red below cannot be a different failure)', () {
      noYaml();
      for (final form in ['run', 'plain']) {
        final r = real(form);
        expect(r.exitCode, 0, reason: '$form: ${r.stdout}|${r.stderr}');
        expect(r.stdout, 'STDIN:hi');
      }
    });

    test('CANARY: an EMPTY yaml makes the real SDK exit 254 with the signature, through both forms', () {
      emptyYaml();
      for (final form in ['run', 'plain']) {
        final r = real(form);
        expect(r.exitCode, 254, reason: form);
        expect('${r.stderr}', contains(nativeAssetsRaceSignature), reason: form);
      }
    });

    test('CANARY (OI-483): the harness form `dart run --verbosity=error` gives the same status and signature', () {
      emptyYaml();
      final r = runSpawn('sh', ['-c', 'echo hi | "\$0" run --verbosity=error "\$1"', dart, '$pkg/bin/x.dart'],
          why: 'real SDK, the harness form',
          workingDirectory: '${tmp.path}/cwd',
          stdoutEncoding: utf8,
          stderrEncoding: utf8);
      expect(r.exitCode, 254);
      expect('${r.stderr}', contains(nativeAssetsRaceSignature));
      expect('${r.stdout}', isNot(contains('STDIN')), reason: 'it died before main');
    });

    test('the signature the hooks match is the one the SDK prints and the test helper retries', () {
      expect(nativeAssetsRaceSignature, 'File not formatted as yaml');
      expect(File(helper).readAsStringSync(), contains('*"$nativeAssetsRaceSignature"*'),
          reason: 'scripts/_dart_bin.sh and test/helpers/spawn.dart (nativeAssetsRaceSignature) must change together on a Flutter bump');
    });

    test('a REAL 254 is retried to a REAL success, with a stdin payload read by a real Dart script', () {
      emptyYaml();
      final r = drive('printf \'payload\\n\' | "\$DART_BIN" run "\$PKG/bin/x.dart"',
          env: {'STUB': shim, 'REAL_DART': dart, 'PKG': pkg});
      expect(r.exit, 0, reason: '${r.out}|${r.err}');
      expect(r.out, 'STDIN:payload');
      expect(r.notes, 1);
      expect(r.err, contains('exit=254 | stderr=File not formatted as yaml'));
      expect(r.backoff, ['1']);
      expect(File(yaml).existsSync(), isFalse, reason: 'the shim healed the file after the first real failure');
    });

    test('OI-483: a REAL 254 in the PLAIN form is retried to a REAL success', () {
      emptyYaml();
      final r = drive('cd "\$PKG"; printf \'payload\\n\' | "\$DART_BIN" bin/x.dart',
          env: {'STUB': shim, 'REAL_DART': dart, 'PKG': pkg});
      expect(r.exit, 0, reason: '${r.out}|${r.err}');
      expect(r.out, 'STDIN:payload');
      expect(r.notes, 1);
    });

    test('KILL SWITCH: with AVYA_DART_RUN_RETRY=0 the same real failure comes back (today\'s call)', () {
      emptyYaml();
      final r = drive('rc=0\nprintf \'payload\\n\' | "\$DART_BIN" run "\$PKG/bin/x.dart" || rc=\$?\necho "RC=\$rc"',
          env: {'STUB': shim, 'REAL_DART': dart, 'PKG': pkg, 'AVYA_DART_RUN_RETRY': '0'}, allowControl: _control);
      expect(r.out, contains('RC=254'));
      expect(r.notes, 0);
      expect(r.backoff, isEmpty);
    });
  });

  posixGroup('the wiring text of the five hooks and of the gate loop', () {
    const hooks = ['pre-commit', 'commit-msg', 'prepare-commit-msg', 'pre-push', 'pre-merge-commit'];
    const guarded = 'type use_dart_race_retry >/dev/null 2>&1 && use_dart_race_retry || true';

    for (final h in hooks) {
      test('$h: ONE guarded call, right after its DART_BIN assignment; DART_BIN is never exported', () {
        final lines = File('scripts/$h.sh').readAsLinesSync();
        final assign = lines.indexWhere((l) => l.trimLeft().startsWith(r'DART_BIN="$(resolve_dart_bin)"'));
        expect(assign, greaterThan(0), reason: '$h assigns DART_BIN from the resolver');
        final calls = [for (var i = 0; i < lines.length; i++) if (lines[i].trim() == guarded) i];
        expect(calls, hasLength(1), reason: h);
        expect(calls.single - assign, inInclusiveRange(1, 4), reason: 'comments may sit between, nothing else');
        for (var i = assign + 1; i < calls.single; i++) {
          expect(lines[i].trimLeft(), startsWith('#'), reason: '$h line ${i + 1}');
        }
        expect(File('scripts/$h.sh').readAsStringSync(), isNot(contains('export DART_BIN')));
      });
    }

    test('the helper defines each of the four functions once at the top level and never exports DART_BIN', () {
      final src = File(helper).readAsStringSync();
      expect(src, isNot(contains('export DART_BIN')));
      for (final fn in ['_dart_race_backoff()', '_dart_run_retrying()', 'use_dart_race_retry()', 'resolve_dart_bin()']) {
        expect(RegExp('^${RegExp.escape(fn)}', multiLine: true).allMatches(src), hasLength(1), reason: fn);
      }
    });

    test('the gate loop keeps each gate\'s output and no longer discards it', () {
      final src = File('scripts/pre-commit.sh').readAsStringSync();
      expect(src, contains(r'"$DART_BIN" run "$GATE" >"$GATE_OUTDIR/$GATE_NAME" 2>&1 || gate_rc=$?'));
      expect(src, isNot(contains(r'run "$GATE" >/dev/null')));
      final wait = src.indexOf('wait || true\n# Diagnostics (OI-482, OI-117)');
      final diag = src.indexOf('\n_gate_diag || true\n');
      final failCount = src.indexOf('GATE_FAIL=0\nfor MARK');
      expect(wait, greaterThan(0));
      expect(diag, greaterThan(wait));
      expect(failCount, greaterThan(diag), reason: 'the diagnostics print BEFORE the GATE FAIL lines');
      expect(src.split('\n').where((l) => l.trim() == '_gate_diag || true'), hasLength(1));
      expect(src, contains(r'rm -rf "$GATE_FAILDIR" "$GATE_OUTDIR"'));
      expect(RegExp(r'^\s*printf .*dart run', multiLine: true).hasMatch(src), isFalse,
          reason: 'lines that mention "dart run" are echo lines (dart_bin_resolver_test flags a printf one)');
    });

    test('the FOUR sites that discard stderr retry SILENTLY, by design (a closed inventory)', () {
      for (final h in ['pre-commit', 'prepare-commit-msg', 'pre-push']) {
        final silent = File('scripts/$h.sh')
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('#') && l.contains('blast_radius_from_diff.dart') && l.contains('2>/dev/null'));
        expect(silent, hasLength(1), reason: '$h: the note goes to the discarded stderr there (declared in the plan)');
      }
      final quiet = File('scripts/commit-msg.sh')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('#') && l.contains('validate_diagnose_doc.dart') && l.contains('>/dev/null 2>&1'));
      expect(quiet, hasLength(1), reason: 'commit-msg.sh: the quiet pre-check; a visible re-run follows it');
      // and nothing else under scripts/ that a hook runs through DART_BIN discards stderr
      for (final h in ['pre-commit', 'commit-msg', 'prepare-commit-msg', 'pre-push', 'pre-merge-commit']) {
        final extra = File('scripts/$h.sh').readAsLinesSync().where((l) =>
            !l.trimLeft().startsWith('#') &&
            l.contains(r'"$DART_BIN" run') &&
            (l.contains('2>/dev/null') || l.contains('>/dev/null 2>&1')) &&
            !l.contains('blast_radius_from_diff.dart') &&
            !(h == 'commit-msg' && l.contains('validate_diagnose_doc.dart')));
        expect(extra, isEmpty, reason: '$h: a new silent site must be added to the inventory (and the plan\'s deviation list)');
      }
    });

    test('the helper\'s guard message stays true now that it defines more than one function', () {
      final src = File(helper).readAsStringSync();
      expect(src, contains('only defines functions'));
      expect(src, isNot(contains('only defines resolve_dart_bin()')));
      expect(src, contains('must be SOURCED'), reason: 'dart_bin_resolver_test pins this substring');
    });
  });
}
