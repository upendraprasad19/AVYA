// test/contracts/exercise_library_cloud_seeded_test.dart
//
// Contract for closes-diagnose ada3fb (2026-05-27):
//
// Cloud `exercise_library` must be seeded — the coach's `getFormCues`
// tool (supabase/functions/_shared/tools/exercise/getFormCues.ts) reads
// it, and so did the `beat-my-coach` Edge Function until its source was
// removed (OI-395). Until 2026-05-27 it was empty (bundled seed
// shipped to Hive but never to cloud), silently degrading the coach's
// form-cue answers.
//
// This is a source-grep contract — it asserts that the seed
// migration file exists with the expected INSERT row count, and
// that the ledger records the apply. It does NOT hit live cloud
// (that requires integration test infra). The behavioral assertion
// "live cloud has rows" is enforced via the build-time Gate path:
//   `node .claude/apply_migration_via_api.js dedsavbjuwgarrhphgnl supabase/migrations/074_seed_exercise_library.sql`
// is re-runnable; any future schema-wipe is caught by the
// supabase/migrations apply ledger pair-update rule.
//
// Batch C1 (library v15, 914 rows) adds: the generator CLI (`<name> [--split] [--out <dir>]`, no default name), the
// per-row cloud-uuid check, the rollback pin (`source = 'exercise-gif-set'`), and mutations of each on the GENERATED text.
// The tests that read the newest seed file on disk are red until that file exists (Task 7); the generator tests run now.
//
// See:
//   - docs/diagnoses/2026-05-27-exercise-library-cloud-empty-ada3fb.md
//   - scripts/seed_exercise_library.js (regenerator)
//   - supabase/functions/_shared/tools/exercise/getFormCues.ts:65,92 (the cloud reader)
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import '../helpers/spawn.dart';

/// scripts/seed_exercise_library.js NAMESPACE: cloud ids are UUID v5 of
/// `exercise_library|` followed by the library id (E001, G0380, N10).
const _namespace = '5a1f0b0c-9dad-11d1-80b4-00c04fd430c8';
String _cloudId(String libraryId) =>
    const Uuid().v5(_namespace, 'exercise_library|$libraryId');

/// Rows the Batch C1 importer writes carry this `source`; it is also the rollback selector.
const _newRowSource = 'exercise-gif-set';
const _rollbackLine = "UPDATE exercise_library SET is_active = false WHERE source = '$_newRowSource';";
const _generator = 'scripts/seed_exercise_library.js';
final _tupleStart = RegExp(r"^\('[0-9a-f]{8}-", multiLine: true);

/// The highest-numbered `*_*seed_exercise_library.sql` on disk.
///
/// Sorted by the numeric prefix, not lexically: '99' sorts above '125' as a
/// string, which would silently pick an older file the day the numbering passes
/// three digits -- and it already has.
File _newestSeedMigration() {
  final dir = Directory('supabase/migrations');
  final seeds = dir
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'[/\\]\d+_\w*seed_exercise_library\.sql$')
          .hasMatch(f.path))
      .toList();
  int num(File f) =>
      int.parse(RegExp(r'[/\\](\d+)_').firstMatch(f.path)!.group(1)!);
  seeds.sort((a, b) => num(a).compareTo(num(b)));
  return seeds.last;
}

/// Every library row has exactly one VALUES tuple carrying its cloud uuid, and no tuple is extra.
List<String> _tupleViolations(String sql, List<Map<String, dynamic>> rows) {
  final tupleIds = RegExp(r"^\('([0-9a-f-]{36})'", multiLine: true).allMatches(sql).map((m) => m.group(1)!).toList();
  final want = {for (final r in rows) _cloudId(r['id'] as String): r['id'] as String};
  final out = <String>[];
  final seen = <String>{};
  for (final id in tupleIds) {
    if (!want.containsKey(id)) out.add('tuple $id is no library row');
    if (!seen.add(id)) out.add('tuple $id appears twice');
  }
  for (final e in want.entries) {
    if (!seen.contains(e.key)) out.add('${e.value} (${e.key}) has no tuple');
  }
  return out;
}

/// The inline rollback deactivates exactly the new rows, and the header counts them.
List<String> _rollbackViolations(String sql, List<Map<String, dynamic>> rows) {
  final out = <String>[];
  final newRows = rows.where((r) => r['source'] == _newRowSource).length;
  if (!sql.contains('-- Rollback strategy: inline')) out.add('no inline rollback strategy header');
  if (!sql.contains('--   $_rollbackLine')) out.add('the commented rollback block does not hold the deactivation line');
  if (!sql.contains("-- Rollback strategy: inline   -- $_rollbackLine")) out.add('the Rollback strategy header does not name the deactivation');
  if (!sql.contains('(selects exactly the $newRows new rows;')) out.add('the header does not count the $newRows new rows');
  return out;
}

Future<ProcessResult> _generateAsync(List<String> args, String why) =>
    runSpawnAsync('node', [_generator, ...args], why: why, report: (_) {})
        .timeout(const Duration(seconds: 60), onTimeout: () => throw TimeoutException('generator run timed out: $why'));

void main() {
  group('exercise_library cloud seed (diagnose ada3fb)', () {
    // 074 was the ORIGINAL seed (259 rows) and is applied, therefore immutable.
    // A library change mints the NEXT seed migration rather than rewriting it, so
    // this resolves the newest one instead of naming a number that goes stale on
    // the next re-seed -- which is exactly what happened when OI-89 grew the
    // library to 271 and this test still measured 074.
    final seedFile = _newestSeedMigration();
    final originalSeed =
        File('supabase/migrations/074_seed_exercise_library.sql');
    final ledgerFile = File('backups/applied_migrations.json');
    final bundledSeed = File('assets/data/exercise_library.json');

    test('074_seed_exercise_library.sql exists with required header tags', () {
      expect(seedFile.existsSync(), isTrue,
          reason: 'Seed migration must be present on disk for re-apply.');
      expect(originalSeed.existsSync(), isTrue,
          reason: '074 is referenced by the applied ledger and must stay on '
              'disk -- it is also the rollback path for every later re-seed.');
      final content = seedFile.readAsStringSync();
      expect(content, contains('-- Intent:'),
          reason: 'Migration must have Intent header per supabase/migrations/CLAUDE.md.');
      expect(content, contains('-- Destructive?:'),
          reason: 'Migration must declare Destructive flag.');
      expect(content, contains('-- Rollback strategy:'),
          reason: 'Migration must declare Rollback strategy.');
      expect(content, contains('-- Linked diagnose-doc:'),
          reason: 'Migration must link to a diagnose-doc.');
      expect(content, contains('INSERT INTO exercise_library'),
          reason: 'Migration must perform the seed INSERT.');
      expect(content, contains('ON CONFLICT (id) DO UPDATE'),
          reason: 'Migration must be idempotent via ON CONFLICT DO UPDATE.');
    });

    test('seed row count matches bundled JSON entry count', () {
      final jsonData = jsonDecode(bundledSeed.readAsStringSync()) as List;
      final expectedRows = jsonData.length;
      // Count VALUES tuples by counting opening `(` at start of a line — each
      // single-line VALUES tuple from the generator begins with `(`.
      final sql = seedFile.readAsStringSync();
      final tupleStarts = _tupleStart.allMatches(sql).length;
      expect(tupleStarts, equals(expectedRows),
          reason:
              'Seed SQL must contain one VALUES tuple per bundled exercise '
              '(json=$expectedRows, sql=$tupleStarts). Re-run '
              'scripts/seed_exercise_library.js if drift detected.');
      // Sanity floor — the coach's form-cue tool needs a healthy library.
      expect(expectedRows, greaterThanOrEqualTo(250),
          reason:
              'Bundled exercise_library shrank below 250 entries; '
              'verify intentional curation OR investigate accidental deletion.');
    });

    // Batch C1: every shipped row, new ones included, reaches the cloud seed under the uuid the
    // namespace gives it (a tuple count alone passes if one row is dropped and another doubled).
    test('every library row has exactly one tuple under its cloud uuid, new rows included', () {
      final rows = (jsonDecode(bundledSeed.readAsStringSync()) as List).cast<Map<String, dynamic>>();
      expect(rows.where((r) => r['source'] == _newRowSource), isNotEmpty);
      expect(_tupleViolations(seedFile.readAsStringSync(), rows), isEmpty);
    });

    test('the inline rollback deactivates exactly the new rows, and the header counts them', () {
      final rows = (jsonDecode(bundledSeed.readAsStringSync()) as List).cast<Map<String, dynamic>>();
      expect(_rollbackViolations(seedFile.readAsStringSync(), rows), isEmpty);
    });

    // Batch A (library v12): 7 rows were retired into a kept twin (merged_ids).
    // Cloud keeps the retired row (is_active = false) because nothing deletes
    // there, and it takes the kept row's cues: getFormCues matches by exact
    // name with no is_active filter, and three retired rows (E165/E167/E168)
    // are shifted rows whose own cue text is wrong.
    group('library v12 merges reach the cloud seed', () {
      final rows = (jsonDecode(bundledSeed.readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();
      final sql = seedFile.readAsStringSync();

      test('the namespace still yields the ids live cloud holds', () {
        // E241 read back from live exercise_library on 2026-10-22.
        expect(_cloudId('E241'), '0916f91b-33e0-579f-9e1d-269520b60e47');
      });

      test('name_aliases is an INSERT column and is updated on conflict', () {
        final columns = RegExp(r'INSERT INTO exercise_library \(([^)]*)\)')
            .firstMatch(sql)!
            .group(1)!;
        expect(columns, contains('name_aliases'));
        expect(sql, contains('name_aliases = EXCLUDED.name_aliases'));
      });

      test('each retired row is deactivated and takes its kept twin\'s cues', () {
        final missing = <String>[];
        var pairs = 0;
        for (final kept in rows.where((r) => r['merged_ids'] is List)) {
          for (final retired in kept['merged_ids'] as List) {
            pairs++;
            final stmt = 'UPDATE exercise_library r SET is_active = false, '
                'coaching_cues = k.coaching_cues, '
                'common_mistakes = k.common_mistakes '
                'FROM exercise_library k '
                "WHERE r.id = '${_cloudId(retired as String)}' "
                "AND k.id = '${_cloudId(kept['id'] as String)}';";
            if (!sql.contains(stmt)) missing.add('$retired -> ${kept['id']}');
          }
        }
        expect(pairs, 7);
        expect(missing, isEmpty);
      });

      test('the retire UPDATEs run after the upsert has repaired the kept cues',
          () {
        // Each UPDATE copies the kept twin's cues. Before the upsert those are
        // still the shifted text, so the order is what makes the copy right.
        // lastIndexOf: a --split file ends the first statement earlier than the second.
        final upsertEnd = sql.lastIndexOf('name_aliases = EXCLUDED.name_aliases;');
        final firstUpdate = sql.indexOf('UPDATE exercise_library r ');
        expect(upsertEnd, greaterThan(0));
        expect(firstUpdate, greaterThan(upsertEnd));
      });

      test('no UPDATE line starts like a VALUES tuple', () {
        final bad = sql
            .split('\n')
            .where((l) => l.startsWith("('") && l.contains('UPDATE'))
            .toList();
        expect(bad, isEmpty);
      });

      test('the header declares the row rewrite and an inline rollback', () {
        // supabase/migrations/CLAUDE.md: "yes" when a migration rewrites rows.
        expect(sql, contains('-- Destructive?: yes'));
        expect(sql, contains('-- Rollback strategy: inline'));
      });
    });

    test('backups/applied_migrations.json records the 074 apply', () {
      expect(ledgerFile.existsSync(), isTrue);
      final raw = jsonDecode(ledgerFile.readAsStringSync()) as List;
      final entries = raw
          .map((e) => e is String ? {'migration': e} : e as Map<String, dynamic>)
          .toList();
      final has074 = entries.any((e) => e['migration'] == '074');
      expect(has074, isTrue,
          reason:
              'Migration 074 must be in backups/applied_migrations.json '
              'per CLAUDE.md §4.5 (feedback_migration_apply_record_pair.md).');
      final entry = entries.firstWhere((e) => e['migration'] == '074');
      expect(entry['diagnose'], equals('ada3fb'),
          reason: 'Entry should link to diagnose ada3fb for traceability.');
      expect(entry['hash'], isNotNull,
          reason: 'Entry must carry sha256 hash for integrity audit.');
    });

    test('getFormCues is a cloud reader of exercise_library and is listed in the tool registry', () {
      // Pin the cloud-reader contract — the coach's form-cue tool is the
      // remaining Edge Function code that SELECTs exercise_library (the
      // beat-my-coach reader's source was removed in OI-395; promote-community-item
      // only INSERTs). If someone refactors it away from exercise_library,
      // this test reminds them to update the SoT model in
      // docs/architecture/database.md.
      String stripComments(String src) => src
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
          .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

      final tool =
          File('supabase/functions/_shared/tools/exercise/getFormCues.ts');
      expect(tool.existsSync(), isTrue);
      // Comment-stripped, and BOTH reads (stage 1 exact match, stage 2 partial
      // match): either one alone, or a commented-out one, must not pass.
      final reads = RegExp(r'\.from\("exercise_library"\)')
          .allMatches(stripComments(tool.readAsStringSync()))
          .length;
      expect(reads, greaterThanOrEqualTo(2),
          reason:
              'getFormCues is the canonical cloud reader for exercise_library '
              '(stage 1 exact + stage 2 partial; found $reads live reads). '
              'If you removed a read, also update docs/architecture/database.md '
              'and consider deleting migration 074.');

      // A reader nobody can reach is not a reader: the tool must still be an
      // ENTRY of the ALL_TOOLS array the tool loop offers. Scoped to the array
      // body (the import line also ends in `getFormCuesTool`, and once a
      // second exercise tool joins it the formatter makes the import
      // multi-line with trailing commas), comments stripped so a
      // commented-out entry does not count.
      final registry = File('supabase/functions/_shared/tools/registry.ts');
      expect(registry.existsSync(), isTrue);
      final raw = registry.readAsStringSync();
      final start = raw.indexOf('const ALL_TOOLS');
      final end = raw.indexOf('];', start);
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));
      final arrayBody = stripComments(raw.substring(start, end));
      expect(arrayBody, contains('getFormCuesTool,'),
          reason:
              'getFormCuesTool must stay an ALL_TOOLS entry, or the '
              'cloud reader of exercise_library becomes an orphan file.');
    });
  });

  // The generator itself, run into a temp directory (never into supabase/migrations): these are green before the
  // migration file exists, and the mutations act on the GENERATED text.
  group('the seed generator CLI (Batch C1): <name> [--split] [--out <dir>]', () {
    late Directory tmp;
    late List<Map<String, dynamic>> rows;
    late String plain;
    late String split;
    setUpAll(() async {
      tmp = Directory.systemTemp.createTempSync('seedgen_');
      rows = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
      final a = await _generateAsync(['999_reseed_exercise_library.sql', '--out', '${tmp.path}/plain'], 'generator, one statement');
      expect(a.exitCode, 0, reason: '${a.stdout}${a.stderr}');
      final b = await _generateAsync(['--split', '998_reseed_exercise_library.sql', '--out', '${tmp.path}/split'], 'generator --split with the flag first');
      expect(b.exitCode, 0, reason: '${b.stdout}${b.stderr}');
      plain = File('${tmp.path}/plain/999_reseed_exercise_library.sql').readAsStringSync();
      split = File('${tmp.path}/split/998_reseed_exercise_library.sql').readAsStringSync();
    });
    tearDownAll(() => tmp.deleteSync(recursive: true));

    test('a run without a file name exits non-zero and writes nothing (it never falls back to an applied migration)', () async {
      final r = await _generateAsync(const [], 'generator without a name');
      expect(r.exitCode, isNot(0));
      final r2 = await _generateAsync(['--out', '${tmp.path}/none'], 'generator with only --out');
      expect(r2.exitCode, isNot(0));
      expect(Directory('${tmp.path}/none').existsSync(), isFalse);
    });

    test('a name whose number the applied ledger records is refused unless --out redirects it', () async {
      final r = await _generateAsync(['162_reseed_exercise_library.sql'], 'generator against an applied number');
      expect(r.exitCode, isNot(0), reason: 'would have rewritten the immutable applied migration 162');
      expect('${r.stderr}', contains('already in the applied ledger'));
    });

    test('--out and the name work in either order; the default output directory is not touched', () async {
      final r = await _generateAsync(['--out', '${tmp.path}/order', '997_reseed_exercise_library.sql'], 'generator with --out first');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(File('${tmp.path}/order/997_reseed_exercise_library.sql').existsSync(), isTrue);
      expect(File('supabase/migrations/997_reseed_exercise_library.sql').existsSync(), isFalse);
    });

    test('one INSERT by default; --split gives two, each ending in the ON CONFLICT clause, tuples equal the JSON length', () {
      expect('INSERT INTO exercise_library'.allMatches(plain).length, 1);
      expect('INSERT INTO exercise_library'.allMatches(split).length, 2);
      expect('name_aliases = EXCLUDED.name_aliases;'.allMatches(split).length, 2);
      expect(_tupleStart.allMatches(plain).length, rows.length);
      expect(_tupleStart.allMatches(split).length, rows.length);
      // Each statement closes with its own conflict clause before the next one starts.
      final firstStart = split.indexOf('INSERT INTO exercise_library');
      final firstEnd = split.indexOf('name_aliases = EXCLUDED.name_aliases;');
      final secondStart = split.indexOf('INSERT INTO exercise_library', firstStart + 1);
      expect(firstStart, greaterThanOrEqualTo(0));
      expect(firstStart, lessThan(firstEnd));
      expect(firstEnd, lessThan(secondStart));
      expect(_tupleViolations(split, rows), isEmpty);
    });

    test('the generated file carries the C1 header, every row uuid and the pinned rollback', () {
      expect(plain, contains('-- Destructive?: yes'));
      expect(plain, contains('-- Linked diagnose-doc: 2026-10-26-library-batch-c1-c1d7a4'));
      expect(_tupleViolations(plain, rows), isEmpty);
      expect(_rollbackViolations(plain, rows), isEmpty);
      expect(_rollbackViolations(split, rows), isEmpty);
    });

    test('MUTATION: a dropped tuple, a doubled tuple and a foreign tuple are each a violation', () {
      final lines = plain.split('\n');
      final i = lines.indexWhere((l) => l.startsWith("('"));
      final dropped = [...lines]..removeAt(i);
      expect(_tupleViolations(dropped.join('\n'), rows), isNotEmpty, reason: 'dropped');
      final doubled = [...lines]..insert(i, lines[i]);
      expect(_tupleViolations(doubled.join('\n'), rows), isNotEmpty, reason: 'doubled');
      final foreign = [...lines]..insert(i, lines[i].replaceFirst(RegExp(r"^\('[0-9a-f-]{36}'"), "('00000000-0000-5000-8000-000000000000'"));
      expect(_tupleViolations(foreign.join('\n'), rows), isNotEmpty, reason: 'foreign uuid');
    });

    test('MUTATION: deleting the deactivation line, or pointing it at another source, is a violation', () {
      final gone = plain.replaceAll(_rollbackLine, '');
      expect(gone, isNot(plain), reason: 'the mutation must apply');
      expect(_rollbackViolations(gone, rows), isNotEmpty, reason: 'line deleted');
      final other = plain.replaceAll("source = '$_newRowSource'", "source = 'icanbefitter_seed'");
      expect(other, isNot(plain), reason: 'the mutation must apply');
      expect(_rollbackViolations(other, rows), isNotEmpty, reason: 'wrong selector');
    });

    test('MUTATION: a --split file that loses one conflict clause is caught by the clause count', () {
      final broken = split.replaceFirst('name_aliases = EXCLUDED.name_aliases;', 'name_aliases = EXCLUDED.name_aliases');
      expect(broken, isNot(split), reason: 'the mutation must apply');
      expect('name_aliases = EXCLUDED.name_aliases;'.allMatches(broken).length, isNot(2));
    });
  });
}
