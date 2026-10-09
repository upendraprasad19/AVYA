// test/scripts/check_migration_ledger_paired_e2e_test.dart
//
// END-TO-END for scripts/check_migration_ledger_paired.dart (Gate-MLP) in a real scratch git
// repo. Before 2026-09-29 the staged-path regex was `(\\d{3,})_.*\\.sql$`: `.*` matched `/`, so
// `supabase/migrations/041_chunks/041_00_alter.sql` read as migration 041, and a letter-suffix
// file (`152b_x.sql`) was never matched at all. The ledger-side extractor also dropped the
// suffix (`152b` -> `152`). No test existed for this gate.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

void main() {
  late Directory tmp;
  final repoRoot = Directory.current.path;
  final dart = dartBin();

  ProcessResult git(List<String> args) =>
      runSpawn('git', args, why: 'scratch-repo git ${args.join(' ')}', workingDirectory: tmp.path);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gate_mlp_');
    Directory('${tmp.path}/scripts').createSync(recursive: true);
    File('$repoRoot/scripts/check_migration_ledger_paired.dart').copySync('${tmp.path}/scripts/check_migration_ledger_paired.dart');
    expect(git(['init', '-q']).exitCode, 0);
    git(['config', 'user.email', 't@t']);
    git(['config', 'user.name', 't']);
    Directory('${tmp.path}/backups').createSync(recursive: true);
  });
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Stages [migrations] (repo-relative paths) plus a ledger holding [ledgerIds].
  ProcessResult stageAndRun(List<String> migrations, List<String> ledgerIds) {
    for (final m in migrations) {
      final f = File('${tmp.path}/$m')..createSync(recursive: true);
      f.writeAsStringSync('select 1;\n');
    }
    File('${tmp.path}/backups/applied_migrations.json').writeAsStringSync(jsonEncode([
      for (final id in ledgerIds)
        {'migration': id, 'applied_at': '2026-09-29T00:00:00+05:30', 'hash': 'sha256:x', 'applier': 't'},
    ]));
    expect(git(['add', '-A']).exitCode, 0);
    return runSpawn(dart, ['scripts/check_migration_ledger_paired.dart'],
        why: 'Gate-MLP pairing gate against the staged scratch repo', workingDirectory: tmp.path);
  }

  test('a normal staged migration with a matching ledger entry passes', () {
    final r = stageAndRun(['supabase/migrations/152_x.sql'], ['152']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });

  test('a staged migration with NO ledger entry FAILS', () {
    final r = stageAndRun(['supabase/migrations/153_x.sql'], ['152']);
    expect(r.exitCode, 1);
    expect('${r.stderr}', contains('153'));
  });

  test('LETTER SUFFIX: staged `152b_x.sql` with only ledger id `152` FAILS (before: never matched, so it passed)', () {
    final r = stageAndRun(['supabase/migrations/152b_x.sql'], ['152']);
    expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    expect('${r.stderr}', contains('152b'));
  });

  test('LETTER SUFFIX: staged `152b_x.sql` with ledger id `152b` passes', () {
    final r = stageAndRun(['supabase/migrations/152b_x.sql'], ['152b']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });

  test('`041_chunks/` files are NOT migrations (before: read as migration 041 and demanded a ledger entry)', () {
    final r = stageAndRun(['supabase/migrations/041_chunks/041_99_extra.sql'], ['001']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });

  test('timestamp-scheme adds (`supabase migration new`) still REQUIRE a ledger entry — the 3-digit grammar is for allocation, not pairing', () {
    final r = stageAndRun(['supabase/migrations/20261001000001_x.sql'], ['001']);
    expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
  });

  test('a staged migration without the ledger STAGED fails', () {
    final f = File('${tmp.path}/supabase/migrations/154_x.sql')..createSync(recursive: true);
    f.writeAsStringSync('select 1;\n');
    File('${tmp.path}/backups/applied_migrations.json').writeAsStringSync('[]');
    git(['add', 'supabase/migrations/154_x.sql']);
    final r = runSpawn(dart, ['scripts/check_migration_ledger_paired.dart'],
        why: 'Gate-MLP pairing gate, ledger not staged', workingDirectory: tmp.path);
    expect(r.exitCode, 1);
  });
}
