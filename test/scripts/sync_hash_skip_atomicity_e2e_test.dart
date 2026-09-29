@Timeout(Duration(minutes: 2))
library;

// End-to-end coverage for scripts/check_sync_hash_skip_atomicity.dart against
// the REAL script process. sync_write_structure_lib_test.dart proves
// checkSyncStructure's logic; this proves main() is actually wired to it
// (the Gate-44 class: a gate whose own test never invokes main()).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/regression_catalog_lib.dart' show scrubbedChildEnvironment;

late final String _repoRoot;
late final String _gate;

ProcessResult _runGate(String cwd, [List<String> extra = const []]) =>
    Process.runSync(
      'dart',
      ['run', _gate, ...extra],
      workingDirectory: cwd,
      environment: scrubbedChildEnvironment(Platform.environment),
      includeParentEnvironment: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
      runInShell: true,
    );

const _placeholder = 'class Placeholder {}';

void main() {
  late Directory tmp;

  setUpAll(() {
    _repoRoot = Directory.current.path;
    _gate = '$_repoRoot/scripts/check_sync_hash_skip_atomicity.dart';
    expect(File(_gate).existsSync(), isTrue,
        reason: 'the gate must exist where this test spawns it from');
  });

  setUp(() => tmp = Directory.systemTemp.createTempSync('sync_hash_skip_e2e_'));

  tearDown(() {
    // NEVER throws — see closes_oi_performed_e2e_test.dart's identical note:
    // a still-open Windows handle turns cleanup into a second, masking
    // failure. %TEMP% is reaped by the OS regardless.
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // deliberately ignored
    }
  });

  void writeFixtures(String exlogBody, String nlogBody) {
    final dir = Directory('${tmp.path}/lib/core/services/sync')
      ..createSync(recursive: true);
    File('${dir.path}/sync_workout.dart').writeAsStringSync(exlogBody);
    File('${dir.path}/sync_nutrition.dart').writeAsStringSync(nlogBody);
  }

  test('OK (exit 0) when the sync layer has no history write', () {
    writeFixtures(_placeholder, _placeholder);
    final r = _runGate(tmp.path);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout, contains('check_sync_hash_skip_atomicity: OK'));
  });

  const unwrapped = "Future<void> _syncWaterLogs(String u) async {\n"
      "  await _supabase.client.from('water_logs').upsert(e);\n"
      "}\n";

  test('G1: an unwrapped history write FAILS by default (exit 1)', () {
    writeFixtures(_placeholder, unwrapped);
    final r = _runGate(tmp.path);
    expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    expect(r.stderr, contains('FAIL sync write structure'));
    expect(r.stderr, contains('sync_nutrition.dart:2'));
  });

  test('G1: --hard FAILS (exit 1) on the same fixture', () {
    writeFixtures(_placeholder, unwrapped);
    final r = _runGate(tmp.path, ['--hard']);
    expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    expect(r.stderr, contains('unwrapped_write'));
  });
}
