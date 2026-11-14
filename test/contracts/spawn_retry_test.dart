// test/contracts/spawn_retry_test.dart
//
// The retry behaviour of test/helpers/spawn.dart (OI-468, OI-311; plan
// docs/plans/2026-11-06-oi468-spawn-status.md, diagnose doc
// docs/diagnoses/2026-11-06-spawn-status-native-assets-race-b7e2d9.md).
//
// A spawned dart child that READS `.dart_tool/native_assets.yaml` while another `dart run`
// is between its truncate and its write exits 254 with `File not formatted as yaml: .`
// before `main` runs; the helpers run such a child again (at most twice), and run any
// child that returned an impossible status again once. This file pins the decision, the
// note, both loops (against the SAME fakes), the real entry points with real children, and
// the shape of the wiring.
//
// WHY A FILE OF ITS OWN. test/contracts/spawn_sites_guard_test.dart allows exactly one raw
// `Process.*` call and one unmatched `startSpawn(` in spawn_helper_test.dart; nothing here
// spawns except through the helper.
//
// SYNTHETIC VALUES ONLY. The two real garbage statuses of the board (1668163832,
// 1752491432) never appear here, and every retry this file PROVOKES goes to a `note` seam
// or a zone that captures `print`. The few spawns that pass no seam (the forwarding checks
// and the `which dart` probe inside `dartBin()`) run children that do not fail, so a
// `[spawn-retry]` line from THEM would be a genuine sighting (a real native-assets race, or
// a real impossible status): exactly what the CI-log count is for.

@Timeout(Duration(minutes: 4))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/read_screen_source.dart';
import '../helpers/spawn.dart';

const _sig = 'File not formatted as yaml: .';

ProcessResult _r(int code, {Object out = '', Object err = ''}) => ProcessResult(0, code, out, err);

/// The measured failure: 254, the sightings' stdout, the signature among other lines.
ProcessResult _race() => _r(254, out: 'Running build hooks...Running build hooks...', err: 'noise before\n$_sig\nnoise after\n');

/// An impossible status (synthetic, not one of the two real values).
ProcessResult _lost([int code = 1668163833]) => _r(code);

/// What one drive of a loop observed.
class _Run {
  _Run(this.result, this.calls, this.events, this.reports, this.notes, this.notesAtCall);
  final ProcessResult result;
  final int calls;
  final List<String> events;
  final List<String> reports;
  final List<String> notes;
  final List<int> notesAtCall;
}

typedef _Driver = Future<_Run> Function(
  ProcessResult Function(int attempt) script, {
  String exe,
  bool? isWindows,
  List<int>? clockMs,
});

DateTime Function()? _clockFrom(List<int>? ms) {
  if (ms == null) return null;
  var i = 0;
  return () => DateTime.fromMillisecondsSinceEpoch(ms[i++]);
}

/// Drives `retryingSpawn` with a scripted child. The fake throws after 10 calls, so a loop
/// that never stops fails here instead of hanging the (synchronous) test.
Future<_Run> _driveSync(
  ProcessResult Function(int attempt) script, {
  String exe = 'dart',
  bool? isWindows,
  List<int>? clockMs,
}) async {
  final events = <String>[];
  final reports = <String>[];
  final notes = <String>[];
  final notesAtCall = <int>[];
  var calls = 0;
  final result = retryingSpawn(
    () {
      events.add('once');
      notesAtCall.add(notes.length);
      calls++;
      if (calls > 10) throw StateError('unbounded retry loop');
      return script(calls);
    },
    exe: exe,
    why: 'w',
    report: (d) {
      reports.add(d);
      events.add('report');
    },
    note: (n) {
      notes.add(n);
      events.add('note');
    },
    isWindows: isWindows,
    clock: _clockFrom(clockMs),
  );
  return _Run(result, calls, events, reports, notes, notesAtCall);
}

/// The same scripted child through `retryingSpawnAsync`.
Future<_Run> _driveAsync(
  ProcessResult Function(int attempt) script, {
  String exe = 'dart',
  bool? isWindows,
  List<int>? clockMs,
}) async {
  final events = <String>[];
  final reports = <String>[];
  final notes = <String>[];
  final notesAtCall = <int>[];
  var calls = 0;
  final result = await retryingSpawnAsync<ProcessResult>(
    () async {
      events.add('once');
      notesAtCall.add(notes.length);
      calls++;
      if (calls > 10) throw StateError('unbounded retry loop');
      return script(calls);
    },
    exitCodeOf: (r) => r.exitCode,
    stdoutOf: (r) => r.stdout,
    stderrOf: (r) => r.stderr,
    exe: exe,
    why: 'w',
    report: (d) {
      reports.add(d);
      events.add('report');
    },
    note: (n) {
      notes.add(n);
      events.add('note');
    },
    isWindows: isWindows,
    clock: _clockFrom(clockMs),
  );
  return _Run(result, calls, events, reports, notes, notesAtCall);
}

/// A hung child fails THIS call in a minute and a half, not the whole file at its 4-minute cap.
const _perCall = Duration(seconds: 90);

void main() {
  group('isDartExecutable: only the dart process itself', () {
    test('yes: dart in any spelling the repo uses', () {
      for (final exe in ['dart', '/a/b/dart', r'C:\a\dart.exe', 'DART.EXE', 'dart.bat', 'dart.cmd', r'C:\flutter\bin\dart.bat', './dart']) {
        expect(isDartExecutable(exe), isTrue, reason: exe);
      }
    });

    test('no: a wrapper, a lookalike, an empty string, a directory named dart', () {
      for (final exe in [
        'sh', '/bin/sh', 'bash', 'git', 'node', 'mydart', 'dart-wrapper', 'dartaotruntime', 'dart.exe.exe',
        '/opt/dart/bin/sh', '', '/a/dart/', r'C:\dart\', 'dart.sh', 'xdart', 'dart2js',
      ]) {
        expect(isDartExecutable(exe), isFalse, reason: '"$exe"');
      }
    });
  });

  group('spawnRetryDecision: the whole decision, pure', () {
    SpawnRetryReason? decide(
      int code, {
      Object? stderr = '',
      String exe = 'dart',
      int race = 0,
      int lost = 0,
      bool windows = false,
    }) =>
        spawnRetryDecision(
            exe: exe, exitCode: code, stderr: stderr, raceRetriesUsed: race, lostStatusRetriesUsed: lost, isWindows: windows);

    test('the race needs ALL of: a dart exe, exit exactly 254, the signature in STDERR', () {
      expect(decide(254, stderr: _sig), SpawnRetryReason.nativeAssetsRace);
      expect(decide(254, stderr: 'before\n$_sig\nafter\n'), SpawnRetryReason.nativeAssetsRace,
          reason: 'the text sits among other lines: contains, not equality');
      expect(decide(254, stderr: _sig, exe: '/x/y/dart'), SpawnRetryReason.nativeAssetsRace);
      expect(decide(254, stderr: _sig, exe: r'C:\a\dart.exe'), SpawnRetryReason.nativeAssetsRace);
      // each conjunct on its own is not enough
      expect(decide(254, stderr: 'a plain compile error'), isNull, reason: 'a bare 254 is a compile error');
      expect(decide(254), isNull);
      for (final code in [0, 1, 2, 253, 255, 127, -9]) {
        expect(decide(code, stderr: _sig), isNull, reason: 'the text with exit $code');
      }
      expect(decide(254, stderr: _sig, exe: 'sh'), isNull, reason: 'a wrapper is not retried');
      expect(decide(254, stderr: _sig, exe: 'git'), isNull);
      expect(decide(254, stderr: _sig, exe: '/bin/sh'), isNull);
    });

    test('near-miss texts do not match (so contains(yaml) and contains(File not formatted) mutants die)', () {
      for (final text in [
        'File not formatted as json: .',
        'file not formatted as yaml: .',
        'File not formatted as yam',
        'File not formatted',
        'not formatted as yaml',
        'yaml',
      ]) {
        expect(decide(254, stderr: text), isNull, reason: text);
      }
    });

    test('raw-bytes stderr (stderrEncoding: null) is decoded; malformed bytes never throw', () {
      expect(decide(254, stderr: utf8.encode('x\n$_sig\n')), SpawnRetryReason.nativeAssetsRace);
      expect(decide(254, stderr: <int>[0xff, 0xfe, 0x80]), isNull);
      expect(decide(1, stderr: <int>[0xff, 0xfe, 0x80]), isNull);
      expect(decide(254, stderr: [...utf8.encode(_sig), 0xff]), SpawnRetryReason.nativeAssetsRace,
          reason: 'a malformed byte after the text does not hide it');
    });

    test('an impossible status is any code above 255 or below -255, for ANY child', () {
      for (final code in [256, 257, 1000, 1668163833, 2147483647, -256, -257, -1000, -2147483648]) {
        expect(decide(code), SpawnRetryReason.lostStatus, reason: '$code');
        expect(decide(code, exe: 'git'), SpawnRetryReason.lostStatus, reason: 'git $code');
        expect(decide(code, exe: 'sh'), SpawnRetryReason.lostStatus, reason: 'sh $code');
      }
      for (final code in [0, 1, 2, 127, 128, 253, 254, 255, -1, -9, -15, -64, -254, -255]) {
        expect(decide(code), isNull, reason: 'a real status $code is never retried');
      }
    });

    test('Windows: an impossible status is legitimate there; the race is not affected', () {
      for (final code in [256, 1668163833, -256, 3221225477]) {
        expect(decide(code, windows: true), isNull, reason: '$code');
      }
      expect(decide(254, stderr: _sig, windows: true), SpawnRetryReason.nativeAssetsRace,
          reason: 'the Windows guard must not leak into the race');
    });

    test('the budgets: race 2, lost 1, per reason and independent', () {
      expect(decide(254, stderr: _sig, race: 0), SpawnRetryReason.nativeAssetsRace);
      expect(decide(254, stderr: _sig, race: 1), SpawnRetryReason.nativeAssetsRace);
      expect(decide(254, stderr: _sig, race: 2), isNull);
      expect(decide(254, stderr: _sig, race: 3), isNull);
      expect(decide(256, lost: 0), SpawnRetryReason.lostStatus);
      expect(decide(256, lost: 1), isNull);
      expect(decide(256, lost: 2), isNull);
      // independent: an exhausted budget of one reason does not touch the other
      expect(decide(254, stderr: _sig, race: 0, lost: 1), SpawnRetryReason.nativeAssetsRace);
      expect(decide(254, stderr: _sig, race: 1, lost: 1), SpawnRetryReason.nativeAssetsRace);
      expect(decide(256, race: 2, lost: 0), SpawnRetryReason.lostStatus);
      expect(decide(256, race: 5, lost: 0), SpawnRetryReason.lostStatus);
      expect(decide(254, stderr: _sig, race: 2, lost: 0), isNull);
      expect(decide(256, race: 0, lost: 1), isNull);
      expect(spawnRaceRetryCap, 2);
      expect(spawnLostStatusRetryCap, 1);
    });
  });

  group('spawnRetryNote: ONE line, the evidence of the failed attempt', () {
    String note({
      SpawnRetryReason reason = SpawnRetryReason.nativeAssetsRace,
      int k = 1,
      int cap = 2,
      String why = 'w',
      int code = 254,
      Object? out = '',
      Object? err = '',
      int ms = 7,
    }) =>
        spawnRetryNote(reason: reason, k: k, cap: cap, why: why, exitCode: code, stdout: out, stderr: err, ms: ms);

    test('the exact shape, with the labels and the retry counters', () {
      expect(note(out: 'a', err: 'bc'),
          '[spawn-retry] native-assets-race retry 1 of 2 w | exit=254 (0xfe) | 7 ms | stdout(1)=a | stderr(2)=bc');
      expect(note(reason: SpawnRetryReason.lostStatus, k: 1, cap: 1, code: 300, ms: 0),
          '[spawn-retry] lost-status retry 1 of 1 w | exit=300 (0x12c) | 0 ms | stdout(0)= | stderr(0)=');
      expect(note(k: 2, cap: 2), contains('retry 2 of 2'));
    });

    test('the hex is of the unsigned 32-bit value, unpadded', () {
      expect(note(code: -300), contains('exit=-300 (0xfffffed4)'));
      expect(note(code: 256), contains('exit=256 (0x100)'));
      expect(note(code: 1668163833), contains('(0x636e28f9)'));
    });

    test('stdout and stderr stay in their own slots', () {
      final n = note(out: 'OUT', err: 'ERR');
      expect(n, contains('stdout(3)=OUT'));
      expect(n, contains('stderr(3)=ERR'));
      expect(n.indexOf('stdout('), lessThan(n.indexOf('stderr(')));
    });

    test('newlines are escaped so the line is one line, and the length is of the ORIGINAL text', () {
      final n = note(err: 'a\r\nb', why: 'x\ny');
      expect(n, isNot(contains('\n')));
      expect(n, isNot(contains('\r')));
      expect(n, contains(r'stderr(4)=a\r\nb'));
      expect(n, contains(r' x\ny |'), reason: 'the label is escaped too');
    });

    test('the excerpt is 300 characters AFTER escaping (not before), cut at exactly 300', () {
      String excerpt(String n) => n.split('stderr(').last.split(')=').last;
      expect(excerpt(note(err: 'x' * 299)), 'x' * 299);
      expect(excerpt(note(err: 'x' * 300)), 'x' * 300);
      expect(excerpt(note(err: 'x' * 301)), 'x' * 300);
      expect(note(err: 'x' * 301), contains('stderr(301)='), reason: 'the length is the original, not the cut');
      // 200 newlines escape to 400 characters; the cut applies to the escaped text
      final cut = excerpt(note(err: '\n' * 200));
      expect(cut.length, 300);
      expect(cut, r'\n' * 150);
    });

    test('raw bytes: decoded text with a BYTE length, no "N bytes" prefix, malformed bytes tolerated', () {
      expect(note(out: <int>[0x68, 0x69]), contains('stdout(2)=hi'));
      expect(note(err: utf8.encode('é')), contains('stderr(2)=é'), reason: 'two bytes, one character');
      expect(note(err: <int>[0xff, 0x41]), contains('stderr(2)='));
      expect(note(out: <int>[0x68, 0x69]), isNot(contains('bytes')));
    });

    test('the label carries no attempt suffix', () {
      expect(note(why: 'a spawn'), contains(' a spawn |'));
      expect(note(why: 'a spawn'), isNot(contains('[attempt')));
    });
  });

  for (final entry in <String, _Driver>{'retryingSpawn (sync)': _driveSync, 'retryingSpawnAsync': _driveAsync}.entries) {
    final name = entry.key;
    final drive = entry.value;

    group('$name: the loop, scripted child (the SAME fakes against both loops)', () {
      test('a race, then success: 2 attempts, one note, the LAST result returned', () async {
        final run = await drive((n) => n == 1 ? _race() : _r(0, out: 'fine'));
        expect(run.calls, 2);
        expect(run.result.exitCode, 0);
        expect(run.result.stdout, 'fine');
        expect(run.notes, hasLength(1));
        expect(run.notes.single, startsWith('[spawn-retry] native-assets-race retry 1 of 2 w | exit=254 (0xfe) | '));
        expect(run.notes.single, contains('stdout(${'Running build hooks...Running build hooks...'.length})=Running build hooks'));
        expect(run.notes.single,
            contains('stderr(${(_race().stderr as String).length})=' r'noise before\nFile not formatted as yaml: .\nnoise after\n'));
        expect(run.reports, hasLength(2));
        expect(run.reports[0], startsWith('w\nexit=254\n'), reason: 'attempt 1 keeps today\'s exact label');
        expect(run.reports[1], startsWith('w [attempt 2]\nexit=0\n'));
      });

      test('an ALWAYS-failing race: 3 attempts, the 254 returned, 3 reports, 2 notes', () async {
        final run = await drive((_) => _race());
        expect(run.calls, 3);
        expect(run.result.exitCode, 254);
        expect(run.reports, hasLength(3));
        expect(run.reports.map((r) => r.split('\n').first), ['w', 'w [attempt 2]', 'w [attempt 3]']);
        expect(run.notes, hasLength(2));
        expect(run.notes[0], contains('native-assets-race retry 1 of 2'));
        expect(run.notes[1], contains('native-assets-race retry 2 of 2'));
      });

      test('an impossible status, then success: 2 attempts, for any child', () async {
        for (final exe in ['git', 'dart', 'sh']) {
          final run = await drive((n) => n == 1 ? _lost() : _r(0), exe: exe, isWindows: false);
          expect(run.calls, 2, reason: exe);
          expect(run.result.exitCode, 0);
          expect(run.notes.single, startsWith('[spawn-retry] lost-status retry 1 of 1 w | exit=1668163833 (0x636e28f9) | '));
          expect(run.reports[1], startsWith('w [attempt 2]\nexit=0\n'));
        }
      });

      test('the DEFAULT isWindows is Platform.isWindows (omitting it keeps the lost-status retry on Linux)', () async {
        final run = await drive((n) => n == 1 ? _lost() : _r(0), exe: 'git');
        expect(run.calls, Platform.isWindows ? 1 : 2);
      }, skip: Platform.isWindows ? 'the default is the Windows rule there' : null);

      test('two impossible statuses in a row: the budget is ONE retry, the second is returned', () async {
        final run = await drive((_) => _lost(), exe: 'git', isWindows: false);
        expect(run.calls, 2);
        expect(run.result.exitCode, 1668163833);
        expect(run.notes, hasLength(1));
        expect(run.reports, hasLength(2));
      });

      test('a mixed sequence (race, lost, race, lost): 4 attempts, suffixes 2 3 4, the LAST lost result returned', () async {
        final run = await drive((n) => n.isOdd ? _race() : _lost(1752491433), isWindows: false);
        expect(run.calls, 4);
        expect(run.result.exitCode, 1752491433);
        expect(run.reports.map((r) => r.split('\n').first), ['w', 'w [attempt 2]', 'w [attempt 3]', 'w [attempt 4]']);
        expect(run.notes, hasLength(3));
        expect(run.notes[0], contains('native-assets-race retry 1 of 2'));
        expect(run.notes[1], contains('lost-status retry 1 of 1'));
        expect(run.notes[2], contains('native-assets-race retry 2 of 2'));
      });

      test('ORDER: the note is printed BEFORE the retry runs, each attempt is reported right after it ran', () async {
        final run = await drive((n) => n < 3 ? _race() : _r(0));
        expect(run.events, ['once', 'report', 'note', 'once', 'report', 'note', 'once', 'report']);
        expect(run.notesAtCall, [0, 1, 2], reason: 'the evidence of attempt n is out before attempt n+1 starts');
      });

      test('MIRRORS: nothing else is retried, and nothing is noted', () async {
        final cases = <String, ProcessResult Function(int)>{
          '254 without the text': (_) => _r(254, err: 'a plain compile error'),
          'the text with exit 1': (_) => _r(1, err: _sig),
          'the text with exit 255': (_) => _r(255, err: _sig),
          'the text on STDOUT only': (_) => _r(254, out: _sig),
          'a normal failure': (_) => _r(2, err: 'boom'),
          'success': (_) => _r(0),
          'a signal': (_) => _r(-9),
        };
        for (final c in cases.entries) {
          final run = await drive(c.value);
          expect(run.calls, 1, reason: c.key);
          expect(run.notes, isEmpty, reason: c.key);
          expect(run.reports, hasLength(1), reason: c.key);
          expect(run.reports.single, startsWith('w\nexit='), reason: c.key);
        }
        final wrapper = await drive((_) => _race(), exe: 'sh');
        expect(wrapper.calls, 1, reason: 'a wrapper that forwards a nested 254 could repeat its own work');
        expect(wrapper.notes, isEmpty);
      });

      test('Windows: an impossible status is returned as is, a race is still retried', () async {
        final lost = await drive((_) => _lost(), exe: 'git', isWindows: true);
        expect(lost.calls, 1);
        expect(lost.notes, isEmpty);
        final race = await drive((n) => n == 1 ? _race() : _r(0), isWindows: true);
        expect(race.calls, 2);
      });

      test('the note time is PER ATTEMPT, from the clock (not cumulative)', () async {
        // two clock reads per attempt: attempt 1 runs 0 -> 120 ms, attempt 2 runs 120 -> 125 ms
        final run = await drive((n) => n < 3 ? _race() : _r(0), clockMs: [0, 120, 120, 125, 125, 126]);
        expect(run.notes[0], contains('| 120 ms |'));
        expect(run.notes[1], contains('| 5 ms |'));
      });

      test('raw-bytes stderr (stderrEncoding: null) is retried and does not throw', () async {
        final run = await drive((n) => n == 1 ? _r(254, err: utf8.encode('x\n$_sig\n')) : _r(0));
        expect(run.calls, 2);
        final other = await drive((_) => _r(3, err: <int>[0xff, 0xfe]));
        expect(other.calls, 1);
      });

      test('a spawn that throws (ProcessException) propagates: nothing is swallowed', () async {
        Future<void> body() async {
          if (name.contains('sync)')) {
            retryingSpawn(() => throw ProcessException('x', const [], 'boom'), exe: 'dart', why: 'w', report: (_) {}, note: (_) {});
          } else {
            await retryingSpawnAsync<ProcessResult>(() async => throw ProcessException('x', const [], 'boom'),
                exitCodeOf: (r) => r.exitCode,
                stdoutOf: (r) => r.stdout,
                stderrOf: (r) => r.stderr,
                exe: 'dart',
                why: 'w',
                report: (_) {},
                note: (_) {});
          }
        }

        await expectLater(body(), throwsA(isA<ProcessException>()));
      });

      test('the DEFAULT note path is print (a zone captures it; nothing reaches stdout, and it shows in a passing test)', () async {
        final printed = <String>[];
        late ProcessResult result;
        await runZoned(() async {
          if (name.contains('sync)')) {
            var n = 0;
            result = retryingSpawn(() => ++n == 1 ? _race() : _r(0), exe: 'dart', why: 'zone', report: (_) {});
          } else {
            var n = 0;
            result = await retryingSpawnAsync<ProcessResult>(() async => ++n == 1 ? _race() : _r(0),
                exitCodeOf: (r) => r.exitCode,
                stdoutOf: (r) => r.stdout,
                stderrOf: (r) => r.stderr,
                exe: 'dart',
                why: 'zone',
                report: (_) {});
          }
        }, zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) => printed.add(line)));
        expect(result.exitCode, 0);
        expect(printed, hasLength(1));
        expect(printed.single, startsWith('[spawn-retry] native-assets-race retry 1 of 2 zone | exit=254 '));
      });
    });
  }

  group('the entry points with REAL children (Dart scripts in a temp dir: no package, so neither writer nor victim)', () {
    late Directory tmp;
    late String dart;
    late String flaky;
    late String cwdDump;
    late String envDump;

    setUpAll(() {
      tmp = Directory.systemTemp.createTempSync('spawn_retry_');
      flaky = '${tmp.path}/flaky.dart';
      // args: <marker> <failUntil> [mode]. Attempt n fails (signature among other lines, 254)
      // while n <= failUntil; it is self-limiting (exit 99 after 6 runs) so an unbounded loop
      // ends in a visible red instead of spinning. mode `stdin`: drain stdin FIRST (no EPIPE
      // race), then print its hex; `plain254`: 254 without the text; `exit1`: the text with 1.
      File(flaky).writeAsStringSync(r'''
import 'dart:io';
Future<void> main(List<String> a) async {
  final marker = File(a[0]);
  final failUntil = int.parse(a[1]);
  final mode = a.length > 2 ? a[2] : '';
  var bytes = <int>[];
  if (mode == 'stdin') {
    await for (final c in stdin) { bytes.addAll(c); }
  }
  final n = (marker.existsSync() ? marker.readAsLinesSync().length : 0) + 1;
  marker.writeAsStringSync('run $n\n', mode: FileMode.append);
  if (n > 6) { stderr.write('runaway'); exit(99); }
  if (mode == 'plain254') { stderr.write('a plain compile error'); exit(254); }
  if (mode == 'exit1') { stderr.write('File not formatted as yaml: .\n'); exit(1); }
  if (n <= failUntil) {
    stdout.write('before-line\n');
    stderr.write('noise before\nFile not formatted as yaml: .\nnoise after\n');
    exit(254);
  }
  final hex = bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  stdout.write(mode == 'stdin' ? 'ECHO:$hex' : 'ok');
}
''');
      cwdDump = '${tmp.path}/cwd_dump.dart';
      File(cwdDump).writeAsStringSync("import 'dart:io';\nvoid main() { stdout.write(Directory.current.path); }\n");
      envDump = '${tmp.path}/env_dump.dart';
      File(envDump).writeAsStringSync("import 'dart:convert';\nimport 'dart:io';\n"
          'void main() { stdout.write(jsonEncode(Platform.environment)); }\n');
      dart = dartBin();
    });
    tearDownAll(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    int attempts(String marker) => File(marker).existsSync() ? File(marker).readAsLinesSync().length : 0;
    String markerOf(String id) => '${tmp.path}/$id.marker';
    String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

    test('the helper recognises the dart this suite spawns (else every retry test below would test nothing)', () {
      expect(isDartExecutable(dart), isTrue, reason: dart);
    });

    test('runSpawn: the first run hits the race, the second passes: result 0, exactly 2 attempts, one note', () {
      final m = markerOf('sync_ok');
      final reports = <String>[];
      final notes = <String>[];
      final r = runSpawn(dart, [flaky, m, '1'],
          why: 'sync flaky', workingDirectory: tmp.path, report: reports.add, note: notes.add);
      expect(r.exitCode, 0, reason: reports.join('\n---\n'));
      expect(r.stdout, 'ok');
      expect(attempts(m), 2);
      expect(notes, hasLength(1));
      expect(notes.single, contains('native-assets-race retry 1 of 2 sync flaky'));
      expect(notes.single, contains('stderr(55)=' r'noise before\nFile not formatted as yaml: .\nnoise after\n'));
      expect(reports, hasLength(2));
      expect(reports[0], startsWith('sync flaky\nexit=254\n'));
      expect(reports[1], startsWith('sync flaky [attempt 2]\nexit=0\n'));
    });

    test('runSpawnAsync: the same', () async {
      final m = markerOf('async_ok');
      final notes = <String>[];
      final reports = <String>[];
      final r = await runSpawnAsync(dart, [flaky, m, '1'],
          why: 'async flaky', workingDirectory: tmp.path, report: reports.add, note: notes.add).timeout(_perCall);
      expect(r.exitCode, 0, reason: reports.join('\n---\n'));
      expect(attempts(m), 2);
      expect(notes, hasLength(1));
      expect(reports, hasLength(2));
    });

    test('runSpawnWithInput: stdin is fed AGAIN on the retry (a String and a List<int> payload)', () async {
      // On Windows `IOSink.write(String)` encodes with the console code page, not UTF-8, so
      // the multi-byte case is Linux/CI only; the bytes case is the same on every platform.
      final text = Platform.isWindows ? 'hello' : 'héllo';
      for (final payload in <Object>[text, <int>[0x00, 0xff, 0x80, 0x41]]) {
        final id = payload is String ? 'input_string' : 'input_bytes';
        final m = markerOf(id);
        final notes = <String>[];
        final reports = <String>[];
        final r = await runSpawnWithInput(dart, [flaky, m, '1', 'stdin'],
            why: id, stdin: payload, workingDirectory: tmp.path, report: reports.add, note: notes.add).timeout(_perCall);
        expect(r.exitCode, 0, reason: reports.join('\n---\n'));
        final expected = payload is String ? utf8.encode(payload) : payload as List<int>;
        expect(r.stdout, 'ECHO:${hex(expected)}', reason: 'the SECOND attempt received the whole payload');
        expect(attempts(m), 2, reason: id);
        expect(notes, hasLength(1), reason: id);
        expect(reports, hasLength(2), reason: id);
      }
    });

    test('an always-failing race: exactly 3 attempts through every entry point, the 254 comes back', () async {
      final ms = markerOf('s_always');
      final sync = runSpawn(dart, [flaky, ms, '99'], why: 'always', workingDirectory: tmp.path, report: (_) {}, note: (_) {});
      expect(sync.exitCode, 254);
      expect(attempts(ms), 3);
      final ma = markerOf('a_always');
      final async = await runSpawnAsync(dart, [flaky, ma, '99'],
          why: 'always', workingDirectory: tmp.path, report: (_) {}, note: (_) {}).timeout(_perCall);
      expect(async.exitCode, 254);
      expect(attempts(ma), 3);
      final mi = markerOf('i_always');
      final withInput = await runSpawnWithInput(dart, [flaky, mi, '99', 'stdin'],
          why: 'always', stdin: 'x', workingDirectory: tmp.path, report: (_) {}, note: (_) {}).timeout(_perCall);
      expect(withInput.exitCode, 254);
      expect(attempts(mi), 3);
    });

    test('MIRRORS with real children: a plain 254 and the text with exit 1 run EXACTLY once, through every entry point', () async {
      for (final mode in ['plain254', 'exit1']) {
        final want = mode == 'plain254' ? 254 : 1;
        final ms = markerOf('s_$mode');
        expect(runSpawn(dart, [flaky, ms, '99', mode], why: mode, workingDirectory: tmp.path, report: (_) {}, note: (_) {}).exitCode, want);
        expect(attempts(ms), 1, reason: 'sync $mode');
        final ma = markerOf('a_$mode');
        expect((await runSpawnAsync(dart, [flaky, ma, '99', mode], why: mode, workingDirectory: tmp.path, report: (_) {}, note: (_) {}).timeout(_perCall)).exitCode, want);
        expect(attempts(ma), 1, reason: 'async $mode');
        final mi = markerOf('i_$mode');
        expect(
            (await runSpawnWithInput(dart, [flaky, mi, '99', mode],
                    why: mode, stdin: '', workingDirectory: tmp.path, report: (_) {}, note: (_) {}).timeout(_perCall))
                .exitCode,
            want);
        expect(attempts(mi), 1, reason: 'withInput $mode');
      }
    });

    test('a WRAPPER (sh running the dart child) is not retried: the signature with 254 comes back after ONE attempt', () {
      final m = markerOf('wrapper');
      final notes = <String>[];
      final r = runSpawn('sh', ['-c', 'exec "\$0" "\$@"', dart, flaky, m, '1'],
          why: 'wrapper', workingDirectory: tmp.path, report: (_) {}, note: notes.add);
      expect(r.exitCode, 254);
      expect(attempts(m), 1);
      expect(notes, isEmpty);
    }, skip: Platform.isWindows ? 'sh wrapper' : null);

    test('runSpawnAsync and runSpawnWithInput still forward workingDirectory, extraEnv and remove', () async {
      final sub = Directory('${tmp.path}/sub')..createSync();
      final parent = {'PATH': Platform.environment['PATH'] ?? '', 'DROP_ME': 'd', 'KEEP_ME': 'k'};
      final a = await runSpawnAsync(dart, [cwdDump], why: 'cwd async', workingDirectory: sub.path, report: (_) {}).timeout(_perCall);
      expect(Directory(a.stdout as String).resolveSymbolicLinksSync(), sub.resolveSymbolicLinksSync());
      final w = await runSpawnWithInput(dart, [cwdDump], why: 'cwd input', stdin: '', workingDirectory: sub.path, report: (_) {}).timeout(_perCall);
      expect(Directory(w.stdout).resolveSymbolicLinksSync(), sub.resolveSymbolicLinksSync());
      final ea = await runSpawnAsync(dart, [envDump],
          why: 'env async', parentEnvironment: parent, extraEnv: {'FROM_EXTRA': 'e'}, remove: {'DROP_ME'}, report: (_) {}).timeout(_perCall);
      final envA = (jsonDecode(ea.stdout as String) as Map).cast<String, String>();
      expect(envA['FROM_EXTRA'], 'e');
      expect(envA['KEEP_ME'], 'k');
      expect(envA.containsKey('DROP_ME'), isFalse);
      final ew = await runSpawnWithInput(dart, [envDump],
          why: 'env input', stdin: '', parentEnvironment: parent, extraEnv: {'FROM_EXTRA': 'e'}, remove: {'DROP_ME'}, report: (_) {}).timeout(_perCall);
      final envW = (jsonDecode(ew.stdout) as Map).cast<String, String>();
      expect(envW['FROM_EXTRA'], 'e');
      expect(envW.containsKey('DROP_ME'), isFalse);
      // runInShell: a shell builtin is only reachable through a shell
      final builtin = Platform.isWindows ? 'ver' : 'export';
      expect((await runSpawnAsync(builtin, const ['X=1'], why: 'builtin async', runInShell: true, report: (_) {}).timeout(_perCall)).exitCode, 0);
      expect((await runSpawnWithInput(builtin, const ['X=1'], why: 'builtin input', stdin: '', runInShell: true, report: (_) {}).timeout(_perCall)).exitCode, 0);
    });
  });

  group('the wiring (PRESENCE and ORDER; the effect is the real runs above)', () {
    late String src;
    setUpAll(() => src = readSourceFileStripped('test/helpers/spawn.dart'));

    String bodyOf(String signature, String next) {
      final start = src.indexOf(signature);
      final end = src.indexOf(next, start + 1);
      expect(start, greaterThan(-1), reason: '$signature must exist');
      expect(end, greaterThan(start), reason: '$next must follow $signature');
      return src.substring(start, end);
    }

    test('the three entry points pass NO isWindows and NO clock (those are loop seams for tests)', () {
      final sync = bodyOf('ProcessResult runSpawn(', 'Future<ProcessResult> runSpawnAsync(');
      final async = bodyOf('Future<ProcessResult> runSpawnAsync(', 'Future<Process> startSpawn(');
      final input = bodyOf('Future<({int exitCode, String stdout, String stderr})> runSpawnWithInput(', 'void reportSpawn(');
      for (final b in [sync, async, input]) {
        expect(b, isNot(contains('isWindows')));
        expect(b, isNot(contains('clock')));
        expect(b, contains('note: note'), reason: 'the note seam is threaded');
        expect(b, contains('report: report'));
      }
    });

    test('runSpawnWithInput: its attempt starts the child through startSpawn(...) and re-writes stdin each time', () {
      final input = bodyOf('Future<({int exitCode, String stdout, String stderr})> runSpawnWithInput(', 'void reportSpawn(');
      expect(input, contains('await startSpawn('));
      expect(input, contains('parentEnvironment: parentEnvironment'));
      expect(input.indexOf('await startSpawn('), lessThan(input.indexOf('retryingSpawnAsync<')),
          reason: 'the attempt closure is built before it is handed to the loop');
      expect(RegExp(r'retryingSpawnAsync<\(\{int exitCode, String stdout, String stderr\}\)>\(\s*once,').hasMatch(input), isTrue);
    });

    test('both loops report an attempt BEFORE asking the decision, and return the LAST result', () {
      final sync = bodyOf('ProcessResult retryingSpawn(', 'Future<T> retryingSpawnAsync<T>(');
      final async = bodyOf('Future<T> retryingSpawnAsync<T>(', 'ProcessResult runSpawn(');
      for (final b in [sync, async]) {
        expect(b.indexOf('reportSpawn('), greaterThan(-1));
        expect(b.indexOf('reportSpawn('), lessThan(b.indexOf('spawnRetryDecision(')),
            reason: 'an attempt is reported even when it is the last');
        expect(b.indexOf('spawnRetryDecision('), lessThan(b.indexOf('emit(')), reason: 'the note follows the decision');
        expect(RegExp(r'if \(reason == null\) return result;').hasMatch(b), isTrue, reason: 'the last result is what comes back');
        expect(b, contains('attempt == 1 ? why'), reason: 'attempt 1 keeps today\'s label byte for byte');
        expect(b, contains('[attempt \$attempt]'));
      }
    });
  });
}
