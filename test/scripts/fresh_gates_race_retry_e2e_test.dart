@Timeout(Duration(minutes: 5))
library;

// OI-483: check_gate_index_fresh, check_adr_index_fresh and check_incident_index_fresh sit in the parallel pre-commit
// loop and spawn `dart run <builder>`, so they are the sites a lost native-assets race reaches most easily. Any
// non-zero from the builder is `FAIL: builder errored`, exit 1: that blocks a commit, and the hook-level retry keys on
// 254 and cannot see it. The gate runs from the repo path in the plain form with a fixture cwd, so only its inner
// `dart run` reads the fixture's empty yaml (dart resolves the package from the script); `dart run` does not heal it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

const gates = <String, (String, String)>{
  'check_gate_index_fresh.dart': ('docs/audit/GATE_INDEX.md', 'build_gate_index.dart'),
  'check_adr_index_fresh.dart': ('docs/adr/INDEX.md', 'build_adr_index.dart'),
  'check_incident_index_fresh.dart': ('docs/incidents/INDEX.md', 'build_incident_index.dart'),
};

Directory fixture(String index, String builder) {
  final d = Directory.systemTemp.createTempSync('fresh_race_');
  addTearDown(() => d.deleteSync(recursive: true));
  File('${d.path}/$index')
    ..createSync(recursive: true)
    ..writeAsStringSync('index\n');
  File('${d.path}/scripts/$builder')
    ..createSync(recursive: true)
    ..writeAsStringSync('void main() {}\n');
  return d;
}

void poison(Directory d) => File('${d.path}/.dart_tool/native_assets.yaml')
  ..createSync(recursive: true)
  ..writeAsStringSync('');

ProcessResult runGate(String gate, Directory cwd, {bool off = false}) => runSpawn(
      dartBin(),
      [File('scripts/$gate').absolute.path],
      why: '$gate in a fixture, off=$off',
      workingDirectory: cwd.path,
      extraEnv: off ? const {'AVYA_DART_RUN_RETRY': '0'} : const {},
      allowControl: const {'AVYA_DART_RUN_RETRY'},
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

int notes(ProcessResult r) => RegExp(r'\[dart-run-retry\]').allMatches('${r.stderr}').length;

void main() {
  for (final e in gates.entries) {
    final gate = e.key;
    final (index, builder) = e.value;

    test('$gate CONTROL: a healthy fixture passes, so a red below is the race', () {
      final d = fixture(index, builder);
      final r = runGate(gate, d);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(notes(r), 0);
    });

    test('$gate: a lost race is retried twice with a note each before the gate reports it', () {
      final d = fixture(index, builder);
      poison(d);
      final r = runGate(gate, d);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect('${r.stderr}', contains('FAIL: builder errored'));
      expect(notes(r), 2, reason: '${r.stderr}');
    });

    test('$gate KILL SWITCH: one attempt, today\'s failure', () {
      final d = fixture(index, builder);
      poison(d);
      final r = runGate(gate, d, off: true);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect('${r.stderr}', contains('FAIL: builder errored'));
      expect(notes(r), 0, reason: '${r.stderr}');
    });
  }
}
