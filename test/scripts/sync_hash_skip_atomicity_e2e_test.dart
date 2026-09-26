@Timeout(Duration(minutes: 2))
library;

// End-to-end coverage for scripts/check_sync_hash_skip_atomicity.dart against
// the REAL script process. sync_hash_skip_atomicity_lib_test.dart proves
// checkDomainAtomicity's logic; this proves main() is actually wired to it
// (the Gate-44 class: a gate whose own test never invokes main()).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/regression_catalog_lib.dart' show scrubbedChildEnvironment;

late final String _repoRoot;
late final String _gate;

ProcessResult _runGate(String cwd) => Process.runSync(
      'dart',
      ['run', _gate],
      workingDirectory: cwd,
      environment: scrubbedChildEnvironment(Platform.environment),
      includeParentEnvironment: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
      runInShell: true,
    );

const _goodExlogFixture = '''
Future<void> _syncExerciseLogs(String userId) async {
  bool exlogBundleSynced = true;
  try {
    await upsertSets();
  } catch (e) {
    exlogBundleSynced = false;
  }
  if (exlogBundleSynced) {
    exlogHashIndex[key] = fp;
  }
}
''';

const _badExlogFixture = '''
Future<void> _syncExerciseLogs(String userId) async {
  exlogHashIndex[key] = fp;
}
''';

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

  test('OK (exit 0) when the exlog fixture is correctly guarded', () {
    writeFixtures(_goodExlogFixture, _placeholder);
    final r = _runGate(tmp.path);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout, contains('OK'));
  });

  test('FAILS (exit 1) and names the file when exlog is unguarded', () {
    writeFixtures(_badExlogFixture, _placeholder);
    final r = _runGate(tmp.path);
    expect(r.exitCode, 1);
    expect(r.stderr, contains('sync_workout.dart'));
  });

  test('OK (vacuous) when neither file has the mechanism yet', () {
    writeFixtures(_placeholder, _placeholder);
    final r = _runGate(tmp.path);
    expect(r.exitCode, 0);
  });
}
