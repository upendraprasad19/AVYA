// test/scripts/migration_ledger_hash_cli_test.dart
//
// scripts/migration_ledger_hash.dart is the DOCUMENTED writer of every new ledger hash (Gate 39's
// failure message and supabase/migrations/CLAUDE.md both send people to it), and until the B-pass
// (2026-09-29, lens 8) no test ran it. These run the REAL CLI as a subprocess.
//
// What is pinned here is WIRING — that it prints `sha256:` + the LF-form hash, that an ambiguous id
// exits 2 and asks for a path, and that usage errors exit 64. The SHA-256 itself is proven against
// NIST vectors and `sha256sum` in migration_ledger_hash_lib_test.dart.

@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/migration_ledger_hash_lib.dart';
import '../helpers/spawn.dart';

ProcessResult _cli(List<String> args) {
  return runSpawn(dartBin(), ['scripts/migration_ledger_hash.dart', ...args],
      why: 'migration_ledger_hash CLI ${args.join(' ')}',
      workingDirectory: Directory.current.path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8);
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('mig_hash_cli_'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a CRLF file prints the hash of its LF FORM — the same answer on every machine', () {
    final lf = utf8.encode('select 1;\nselect 2;\n');
    final crlf = toCrlf(lf);
    final f = File('${tmp.path}/200_x.sql')..writeAsBytesSync(crlf);
    final r = _cli([f.path]);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect((r.stdout as String).trim(), 'sha256:${sha256Hex(lf)}');
    expect((r.stdout as String).trim(), isNot('sha256:${sha256Hex(crlf)}'),
        reason: 'fixture must actually differ between the two forms');
  });

  test('a bare id resolves against the REAL supabase/migrations and equals the ledger entry Gate 39 verifies', () {
    // 151 is not grandfathered, so its ledger hash must equal what the CLI prints.
    final ledger = (jsonDecode(File('backups/applied_migrations.json').readAsStringSync()) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final recorded = ledger.firstWhere((e) => e['migration'] == '151')['hash'] as String;
    final r = _cli(['151']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect((r.stdout as String).trim(), recorded);
  });

  test('an AMBIGUOUS id (145 has two files) exits 2 and asks for a path', () {
    final r = _cli(['145']);
    expect(r.exitCode, 2, reason: '${r.stdout}${r.stderr}');
    expect(r.stderr as String, contains('ambiguous'));
    expect((r.stdout as String).trim(), isEmpty, reason: 'nothing hash-shaped may reach stdout on failure');
  });

  test('an id with no file exits 2; no argument exits 64', () {
    expect(_cli(['998']).exitCode, 2);
    expect(_cli([]).exitCode, 64);
  });
}
