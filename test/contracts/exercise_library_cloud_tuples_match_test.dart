// Batch M1 (plan R6, Task 3): the cloud copy of the library is the library, tuple for tuple.
//
// `scripts/seed_exercise_library.js` generates the cloud re-seed SQL from the committed
// `assets/data/exercise_library.json`. The newest applied seed migration is that SQL for the library
// as it stood when the migration was minted. This test regenerates the SQL from the committed library in a
// sandbox and compares every non-comment line with the newest migration, so a library change that the cloud
// does not carry (a new row, an edited cue, a changed equipment list, an activation flag) cannot ship without
// a new seed migration. The media keys (`media_slug`, `media_version`, `media_source`) are not cloud columns,
// so adding them to a row must leave the comparison green.
//
// Sandbox: a COPY of the generator and of the library in a temp tree with the same relative layout
// (`<tmp>/scripts/`, `<tmp>/assets/data/`). With an `--out` other than `supabase/migrations` the generator does
// not read the applied ledger, so a number that is already applied can be used for a throw-away file.
//
// The guard is new protection for existing behaviour: it is green on the committed files, and the mutations
// below are its proof.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

const _generatorRel = 'scripts/seed_exercise_library.js';
const _libRel = 'assets/data/exercise_library.json';
const _outName = '999_reseed_exercise_library.sql';

File _newestSeedMigration() {
  final seeds = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'[/\\]\d+_\w*seed_exercise_library\.sql$').hasMatch(f.path))
      .toList();
  int num(File f) => int.parse(RegExp(r'[/\\](\d+)_').firstMatch(f.path)!.group(1)!);
  seeds.sort((a, b) => num(a).compareTo(num(b)));
  return seeds.last;
}

List<String> _sqlLines(String text) =>
    const LineSplitter().convert(text).where((l) => !l.startsWith('--')).toList();

/// The number of positions at which the two line lists differ (a length difference counts too).
int _diffCount(List<String> a, List<String> b) {
  final n = a.length > b.length ? a.length : b.length;
  var d = 0;
  for (var i = 0; i < n; i++) {
    if ((i < a.length ? a[i] : null) != (i < b.length ? b[i] : null)) d++;
  }
  return d;
}

class _Sandbox {
  _Sandbox() : dir = Directory.systemTemp.createTempSync('lib_cloud_') {
    Directory('${dir.path}/scripts').createSync(recursive: true);
    Directory('${dir.path}/assets/data').createSync(recursive: true);
    Directory('${dir.path}/scripts/data').createSync(recursive: true);
    Directory('${dir.path}/out').createSync();
    // Every record the generator reads lives in scripts/data/library_*.json: the removals file (Batch C2a; without it
    // the sandbox would emit no deactivations) and the kept-row records (Batch C2c E230 retag, Library Batch S1b-2
    // suitable_for; a missing record is a hard stop in the generator). Copying the whole family, not a list of names,
    // keeps the sandbox in step when a batch adds a record (S1b-2 added one and a named list missed it).
    final records = Directory('scripts/data')
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'/library_[^/]*\.json$').hasMatch(f.path))
        .toList();
    expect(records.map((f) => f.path.split('/').last),
        containsAll(['library_batch_c2_removals.json', 'library_e230_retag.json', 'library_s1b2_suitable_for.json',
          'library_s1b3_merges.json', 'library_s1b3_name_aliases.json']));
    for (final f in records) {
      File('${dir.path}/scripts/data/${f.path.split('/').last}').writeAsStringSync(f.readAsStringSync());
    }
    // The previous seed migration (174 since Library Batch S1b-3): the generator checks each kept-row record's `before`
    // against its tuple there, and reads a merged row's own cues from it for the rollback.
    Directory('${dir.path}/supabase/migrations').createSync(recursive: true);
    File('${dir.path}/supabase/migrations/174_reseed_exercise_library.sql')
        .writeAsStringSync(File('supabase/migrations/174_reseed_exercise_library.sql').readAsStringSync());
    File(script).writeAsStringSync(File(_generatorRel).readAsStringSync());
    File(libPath).writeAsStringSync(File(_libRel).readAsStringSync());
  }

  final Directory dir;
  String get script => '${dir.path}/scripts/seed_exercise_library.js';
  String get libPath => '${dir.path}/assets/data/exercise_library.json';
  String get outPath => '${dir.path}/out/$_outName';

  List<Map<String, dynamic>> readLib() =>
      (jsonDecode(File(libPath).readAsStringSync()) as List).cast<Map<String, dynamic>>();
  void writeLib(List<Map<String, dynamic>> rows) => File(libPath).writeAsStringSync(jsonEncode(rows));

  /// Text-mutates the sandbox copy of the generator; the replacement must apply.
  void mutateScript(String from, String to) {
    final text = File(script).readAsStringSync();
    expect(text.contains(from), isTrue, reason: 'the script mutation must apply: $from');
    File(script).writeAsStringSync(text.replaceFirst(from, to));
  }

  /// Runs the sandbox generator and returns its non-comment lines.
  Future<List<String>> generate() async {
    final r = await runSpawnAsync(
      'node',
      [script, _outName, '--out', '${dir.path}/out'],
      why: 'seed_exercise_library.js on a sandbox copy',
      report: (_) {},
    ).timeout(const Duration(seconds: 60), onTimeout: () => throw TimeoutException('generator run timed out'));
    expect(r.exitCode, 0, reason: 'the sandbox generator must run: ${r.stdout}${r.stderr}');
    return _sqlLines(File(outPath).readAsStringSync());
  }

  void dispose() => dir.deleteSync(recursive: true);
}

void main() {
  late List<String> migration;
  late _Sandbox sb;

  setUpAll(() {
    migration = _sqlLines(_newestSeedMigration().readAsStringSync());
  });
  setUp(() => sb = _Sandbox());
  tearDown(() => sb.dispose());

  test('the SQL generated from the committed library equals the newest seed migration, line for line', () async {
    final generated = await sb.generate();
    expect(generated, isNotEmpty);
    expect(_diffCount(generated, migration), 0,
        reason: 'the cloud copy ${_newestSeedMigration().path} is out of date: mint the next seed migration '
            '(scripts/mint_migration.sh, then scripts/seed_exercise_library.js)');
  });

  test('a media key added to a row leaves it green (media keys are not cloud columns)', () async {
    final rows = sb.readLib();
    rows.first['media_slug'] = '0001-x';
    rows.first['media_version'] = 1;
    rows.first['media_source'] = 'wardroom';
    sb.writeLib(rows);
    expect(_diffCount(await sb.generate(), migration), 0);
  });

  group('MUTATION: a change the cloud does not carry reddens it', () {
    for (final field in ['name', 'coaching_cues', 'equipment_needed', 'is_active']) {
      test('one row\'s $field changed', () async {
        final rows = sb.readLib();
        final row = rows.firstWhere((r) => r['is_active'] == true);
        switch (field) {
          case 'name':
            row['name'] = '${row['name']} changed';
          case 'coaching_cues':
            row['coaching_cues'] = [...(row['coaching_cues'] as List), 'an extra cue'];
          case 'equipment_needed':
            row['equipment_needed'] = ['kettlebell'];
          case 'is_active':
            row['is_active'] = false;
        }
        sb.writeLib(rows);
        expect(_diffCount(await sb.generate(), migration), greaterThan(0), reason: 'a changed $field must differ');
      });
    }

    test('a row removed', () async {
      // The first row (an ordinary one), not the last: since Library Batch S1b-2 the last rows are the batch's new
      // rows, and removing one of those is a hard stop in the generator (BATCH.newRowIds), not a different SQL.
      final rows = sb.readLib();
      expect(rows.first['id'], startsWith('E'));
      rows.removeAt(0);
      sb.writeLib(rows);
      expect(_diffCount(await sb.generate(), migration), greaterThan(0));
    });

    test('a row added', () async {
      final rows = sb.readLib();
      final copy = (jsonDecode(jsonEncode(rows.first)) as Map<String, dynamic>)..['id'] = 'E9999';
      sb.writeLib([...rows, copy]);
      expect(_diffCount(await sb.generate(), migration), greaterThan(0));
    });

    test('the generator drops one column from the SET list', () async {
      sb.mutateScript('  is_indian_context = EXCLUDED.is_indian_context,\n', '');
      expect(_diffCount(await sb.generate(), migration), greaterThan(0));
    });

    test('the generator drops its retire statements', () async {
      sb.mutateScript(
        'const retireStatements = data\n  .filter((item) => Array.isArray(item.merged_ids))',
        'const retireStatements = data\n  .filter((item) => false)',
      );
      expect(_diffCount(await sb.generate(), migration), greaterThan(0));
    });
  });
}
