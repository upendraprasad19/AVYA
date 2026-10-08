@Timeout(Duration(minutes: 2))
library;

// End-to-end coverage for scripts/check_sync_no_now_fallback.dart against the
// REAL script process: the lib test proves findNowFallbacks; this proves
// main() is wired to it (the Gate-44 class: a gate whose test never runs main()).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

late final String _gate;

ProcessResult _runGate(String cwd, [List<String> extra = const []]) =>
    runSpawn(
      dartBin(),
      ['run', _gate, ...extra],
      why: 'sync no-now-fallback gate against a fixture',
      workingDirectory: cwd,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
      runInShell: true,
    );

const _bad = "Future<void> f() async {\n"
    "  final p = {'created_at': row['created_at'] ?? DateTime.now().toIso8601String()};\n"
    "}\n";
const _good = "Future<void> f() async {\n"
    "  final p = {if (row['created_at'] != null) 'created_at': row['created_at']};\n"
    "}\n";

void main() {
  late Directory tmp;

  setUpAll(() {
    _gate = '${Directory.current.path}/scripts/check_sync_no_now_fallback.dart';
    expect(File(_gate).existsSync(), isTrue,
        reason: 'the gate must exist where this test spawns it from');
  });

  setUp(() => tmp = Directory.systemTemp.createTempSync('no_now_fallback_e2e_'));

  tearDown(() {
    // Never throws: a still-open Windows handle would turn cleanup into a
    // second failure that masks the real one. %TEMP% is reaped regardless.
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // deliberately ignored
    }
  });

  void writeFixture(String body) {
    final dir = Directory('${tmp.path}/lib/core/services/sync')
      ..createSync(recursive: true);
    File('${dir.path}/sync_workout.dart').writeAsStringSync(body);
  }

  test('default run FAILS (exit 1) and names the file:line', () {
    writeFixture(_bad);
    final r = _runGate(tmp.path);
    expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    expect(r.stderr, contains('FAIL'));
    expect(r.stderr, contains('sync_workout.dart:2'));
  });

  test('--hard FAILS (exit 1) on the same fixture', () {
    writeFixture(_bad);
    final r = _runGate(tmp.path, ['--hard']);
    expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    expect(r.stderr, contains('FAIL'));
  });

  test('OK (exit 0) when the payload omits the field instead', () {
    writeFixture(_good);
    final r = _runGate(tmp.path, ['--hard']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout, contains('OK'));
  });
}
