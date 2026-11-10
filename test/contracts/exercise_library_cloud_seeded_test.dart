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

import 'package:icanbefitter/core/services/library_retired_ids.dart';

import '../helpers/spawn.dart';

/// scripts/seed_exercise_library.js NAMESPACE: cloud ids are UUID v5 of
/// `exercise_library|` followed by the library id (E001, G0380, N10).
const _namespace = '5a1f0b0c-9dad-11d1-80b4-00c04fd430c8';
String _cloudId(String libraryId) =>
    const Uuid().v5(_namespace, 'exercise_library|$libraryId');

/// Rows the Batch C1 importer writes carry this `source`: the C1 rows plus the four Batch C2b twins.
const _newRowSource = 'exercise-gif-set';

/// Batch C2a: the `decision: remove` library ids of scripts/data/library_batch_c2_removals.json, ascending.
List<String> _removedIds() {
  final entries = ((jsonDecode(File('scripts/data/library_batch_c2_removals.json').readAsStringSync()) as Map<String, dynamic>)['entries'] as List)
      .cast<Map<String, dynamic>>();
  return [for (final e in entries) if (e['decision'] == 'remove') e['id'] as String]..sort();
}

/// Batch C2b: the removals this batch made itself (`removed_in: c2b`) and the twins that replace them. ALL removals are deactivated
/// (idempotent); only this batch's own are reactivated by its rollback, and its twins are deactivated by it (cloud never deletes).
List<Map<String, dynamic>> _removalEntries() =>
    ((jsonDecode(File('scripts/data/library_batch_c2_removals.json').readAsStringSync()) as Map<String, dynamic>)['entries'] as List)
        .cast<Map<String, dynamic>>()
        .where((e) => e['decision'] == 'remove')
        .toList();
List<String> _ownRemovedIds() => [for (final e in _removalEntries()) if (e['removed_in'] == 'c2b') e['id'] as String]..sort();
List<String> _twinIds() =>
    {for (final e in _removalEntries()) if (e['removed_in'] == 'c2b' && e['replacement_new'] == true) e['replacement'] as String}.toList()..sort();

String _rollbackLine() =>
    "UPDATE exercise_library SET is_active = true WHERE id IN (${_ownRemovedIds().map((i) => "'${_cloudId(i)}'").join(', ')});";
String _twinRollbackLine() =>
    "UPDATE exercise_library SET is_active = false WHERE id IN (${_twinIds().map((i) => "'${_cloudId(i)}'").join(', ')});";
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

/// Batch C2c (OI-474): the E230 retag record. `before` is what the migration's inline rollback restores.
Map<String, dynamic> _retagRecord() => jsonDecode(File('scripts/data/library_e230_retag.json').readAsStringSync()) as Map<String, dynamic>;

String _sqlArray(List<dynamic> values) => "ARRAY[${values.map((s) => "'${'$s'.replaceAll("'", "''")}'").join(',')}]::text[]";

/// The restore line of the C2c migration, built in Dart from the record's `before`: the four cloud columns of E230.
String _retagRollbackLine() {
  final rec = _retagRecord();
  final before = (rec['before'] as Map).cast<String, dynamic>();
  return 'UPDATE exercise_library SET equipment_needed = ${_sqlArray(before['equipment_needed'] as List)}, '
      "logging_type = '${before['logging_type']}', "
      'coaching_cues = ${_sqlArray(before['coaching_cues'] as List)}, '
      'common_mistakes = ${_sqlArray(before['common_mistakes'] as List)} '
      "WHERE id = '${_cloudId(rec['id'] as String)}';";
}

/// The batch a seed file names in its Intent line: `(862 exercises, library v20, Batch C2c)`, `(871 exercises, library v23,
/// Batch S1b-2)`, `(870 exercises, library v24, Batch S1b-3)`. The rollback text is shaped by the batch, so the checks are too; a label this test does not know is a
/// violation, never a pass.
String? _batchLabel(String sql) =>
    RegExp(r'exercises, library v\d+, Batch (C2[a-z]|S1b-[23])\)').firstMatch(sql)?.group(1);

/// Library Batch S1b-2: the suitable_for record (E010, E045) and the nine rows the batch inserts (restated from the plan).
Map<String, dynamic> _s1b2Record() =>
    jsonDecode(File('scripts/data/library_s1b2_suitable_for.json').readAsStringSync()) as Map<String, dynamic>;
const _s1b2NewIds = ['N14', 'N15', 'N16', 'N17', 'N18', 'N19', 'N20', 'N21', 'N22'];

/// The restore lines of the S1b-2 migration, built in Dart from the record's `before`.
List<String> _s1b2RestoreLines() => [
      for (final e in (_s1b2Record()['rows'] as List).cast<Map<String, dynamic>>())
        "UPDATE exercise_library SET suitable_for = ${_sqlArray(e['before'] as List)} WHERE id = '${_cloudId(e['id'] as String)}';",
    ];
String _s1b2DeactivateLine() =>
    "UPDATE exercise_library SET is_active = false WHERE id IN (${_s1b2NewIds.map((i) => "'${_cloudId(i)}'").join(', ')});";

/// Library Batch S1b-2: the rollback restores E010 / E045 suitable_for from the record's `before` and deactivates the nine
/// inserted rows (the cloud never deletes); the batch owns no removal, so there is no reactivation line.
List<String> _rollbackViolationsS1b2(String sql) {
  final out = <String>[];
  final restores = _s1b2RestoreLines();
  final deactivate = _s1b2DeactivateLine();
  if (restores.length != 2) out.add('the S1b-2 record holds ${restores.length} rows, not E010 and E045');
  if (!sql.contains('-- Rollback strategy: inline   -- ${restores.join(' ')} $deactivate')) {
    out.add('the Rollback strategy header does not name the two restores and the deactivation');
  }
  for (final l in [...restores, deactivate]) {
    if (!sql.contains('--   $l')) out.add('the commented rollback block does not hold: ${l.substring(0, 60)}');
  }
  if (!sql.contains('and INSERTs 9 new row(s)')) out.add('the Destructive header does not count the 9 inserted rows');
  if (sql.contains('IN ()')) out.add('an empty IN () list (a SQL syntax error)');
  if (RegExp(r'^--   UPDATE exercise_library SET is_active = true WHERE id IN', multiLine: true).hasMatch(sql)) {
    out.add('Batch S1b-2 removes no row, so its rollback has no reactivation line');
  }
  if (_removalEntries().any((e) => e['removed_in'] == 's1b2')) out.add('the removals file has an entry removed_in s1b2; this batch owns none');
  return out;
}

/// Library Batch S1b-3 (OI-147): the name_aliases record (G1373), and E053, merged into G1373 by the importer's merge stage.
Map<String, dynamic> _s1b3Record() =>
    jsonDecode(File('scripts/data/library_s1b3_name_aliases.json').readAsStringSync()) as Map<String, dynamic>;
/// E053 as the v23 bundle shipped it (restated; migration 174 seeded these cues).
Map<String, dynamic> _e053V23() =>
    (jsonDecode(File('test/fixtures/library_e053_row_v23.json').readAsStringSync()) as Map<String, dynamic>)['row'] as Map<String, dynamic>;
String _s1b3RestoreLine() {
  final e = (_s1b3Record()['rows'] as List).cast<Map<String, dynamic>>().single;
  expect(e['id'], 'G1373');
  expect(e['before'], isNull);
  return "UPDATE exercise_library SET name_aliases = NULL WHERE id = '${_cloudId('G1373')}';";
}
/// Built in Dart from the restated v23 row, never from the generator's scan of 174.
String _s1b3ReactivateLine() {
  final e = _e053V23();
  return 'UPDATE exercise_library SET is_active = true, coaching_cues = ${_sqlArray(e['coaching_cues'] as List)}, '
      "common_mistakes = ${_sqlArray(e['common_mistakes'] as List)} WHERE id = '${_cloudId('E053')}';";
}

/// Library Batch S1b-3: the rollback restores G1373 name_aliases to NULL and reactivates E053 with its OWN cues (the retire
/// UPDATE gave it G1373's); the batch inserts no row and owns no removals-file entry, so there is no deactivation line and no
/// IN () list. The header says E053's retire UPDATE is a first-time deactivation, not an idempotent repeat.
List<String> _rollbackViolationsS1b3(String sql) {
  final out = <String>[];
  final restore = _s1b3RestoreLine();
  final reactivate = _s1b3ReactivateLine();
  if (!sql.contains('-- Rollback strategy: inline   -- $restore $reactivate  (')) {
    out.add('the Rollback strategy header does not name the G1373 restore and the E053 reactivation');
  }
  for (final l in [restore, reactivate]) {
    if (!sql.contains('--   $l')) out.add('the commented rollback block does not hold: ${l.substring(0, 60)}');
  }
  if (!sql.contains('and INSERTs 0 new row(s)')) out.add('the Destructive header does not say no row is inserted');
  if (!sql.contains("1 first-time, this batch's merge of E053 Donkey Calf Raise into G1373")) {
    out.add('the Intent line does not name E053 as a first-time deactivation');
  }
  if (!sql.contains('on the 1 row(s) this batch merged away (E053 Donkey Calf Raise into G1373)')) {
    out.add('the Destructive line does not name the merged row');
  }
  if (sql.contains('this batch removes and adds no row')) out.add('the header claims the batch touches no row');
  if (sql.contains('IN ()')) out.add('an empty IN () list (a SQL syntax error)');
  if (RegExp(r'^--   UPDATE exercise_library SET is_active = (true|false) WHERE id IN', multiLine: true).hasMatch(sql)) {
    out.add('Batch S1b-3 owns no removals-file entry and inserts no row, so its rollback has no IN-list line');
  }
  if (_removalEntries().any((e) => e['removed_in'] == 's1b3')) out.add('the removals file has an entry removed_in s1b3; this batch owns none');
  return out;
}

/// Batch C2c: the rollback restores E230's four cloud columns from the record's `before`; the batch owns no removal and no twin,
/// so there is no reactivation or deactivation line and no empty `IN ()` list.
List<String> _rollbackViolationsC2c(String sql) {
  final out = <String>[];
  final line = _retagRollbackLine();
  if (!sql.contains('-- Rollback strategy: inline')) out.add('no inline rollback strategy header');
  if (!sql.contains('--   $line')) out.add('the commented rollback block does not hold the E230 restore line');
  if (!sql.contains('-- Rollback strategy: inline   -- $line')) out.add('the Rollback strategy header does not name the E230 restore');
  if (sql.contains('IN ()')) out.add('an empty IN () list (a SQL syntax error)');
  if (RegExp(r'^--   UPDATE exercise_library SET is_active = (true|false) WHERE id IN', multiLine: true).hasMatch(sql)) {
    out.add('Batch C2c removes and adds no row, so its rollback has no reactivation or deactivation line');
  }
  if (_removalEntries().any((e) => e['removed_in'] == 'c2c')) out.add('the removals file has an entry removed_in c2c; this batch owns none');
  return out;
}

/// The inline rollback of the batch the file names: C2b reactivates exactly the rows it removed (not C2a's 50) and deactivates its
/// twins, C2c restores E230. The header counts what it does.
List<String> _rollbackViolations(String sql, List<Map<String, dynamic>> rows) {
  final label = _batchLabel(sql);
  if (label == 'S1b-3') return _rollbackViolationsS1b3(sql);
  if (label == 'S1b-2') return _rollbackViolationsS1b2(sql);
  if (label == 'C2c') return _rollbackViolationsC2c(sql);
  if (label != 'C2b') return ['the Intent line names batch ${label ?? '(none)'}, which this test has no rollback shape for'];
  final out = <String>[];
  final own = _ownRemovedIds().length;
  final earlier = _removedIds().length - own;
  final twins = _twinIds().length;
  if (!sql.contains('-- Rollback strategy: inline')) out.add('no inline rollback strategy header');
  if (!sql.contains('--   ${_rollbackLine()}')) out.add('the commented rollback block does not hold the reactivation line');
  if (!sql.contains('-- Rollback strategy: inline   -- ${_rollbackLine()}')) out.add('the Rollback strategy header does not name the reactivation');
  if (!sql.contains('--   ${_twinRollbackLine()}')) out.add('the commented rollback block does not hold the twin deactivation line');
  if (!sql.contains('(reactivates exactly the $own rows this batch removed, not the $earlier of Batch C2a; a second line deactivates the $twins inserted twins;')) {
    out.add('the header does not count the $own own removals, the $earlier of C2a and the $twins twins');
  }
  if (own != 6 || twins != 4) out.add('Batch C2b removes 6 rows into 4 twins, the removals file says $own into $twins');
  return out;
}

/// Batch C2a: every removed id is deactivated by exactly one statement, after the upsert, and no removed id is upserted.
List<String> _removalViolations(String sql) {
  final out = <String>[];
  final upsertEnd = sql.lastIndexOf('name_aliases = EXCLUDED.name_aliases;');
  for (final id in _removedIds()) {
    final u = _cloudId(id);
    final plain = "UPDATE exercise_library SET is_active = false WHERE id = '$u';";
    final cue = "UPDATE exercise_library r SET is_active = false, coaching_cues = k.coaching_cues, common_mistakes = k.common_mistakes FROM exercise_library k WHERE r.id = '$u' AND";
    final n = plain.allMatches(sql).length + cue.allMatches(sql).length;
    if (n != 1) out.add('$id ($u) is deactivated by $n statements');
    final at = sql.indexOf("id = '$u'");
    if (at >= 0 && at < upsertEnd) out.add('$id deactivation precedes the upsert');
    if (RegExp("^\\('$u'", multiLine: true).hasMatch(sql)) out.add('$id is still upserted');
  }
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

    test('the inline rollback is the one the batch label names (C2b reactivates its removals, C2c restores E230, S1b-2 restores E010 / E045 and deactivates its nine rows, S1b-3 restores G1373 name_aliases and reactivates E053 with its own cues), and the header counts it', () {
      final rows = (jsonDecode(bundledSeed.readAsStringSync()) as List).cast<Map<String, dynamic>>();
      expect(_rollbackViolations(seedFile.readAsStringSync(), rows), isEmpty);
    });

    test('Batch C2a: every removed id is deactivated once, after the upsert, and not upserted', () {
      expect(_removalViolations(seedFile.readAsStringSync()), isEmpty);
    });

    // Batch A (library v12): 7 rows were retired into a kept twin (merged_ids); Library Batch S1b-3 merged an 8th
    // (E053 into G1373) through the importer's merge stage, with the same cloud statement.
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
        expect(pairs, 8);
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

    // B-pass finding (reviewer A, 2026-10-26): the ledger refusal ran only when --out was ABSENT, so the explicit spelling of
    // the default directory skipped it and rewrote the applied, immutable migration. The mirror of "default directory" is
    // "an --out that resolves to the default directory", in every spelling.
    test('an explicit --out that IS supabase/migrations is refused for an applied number, in every spelling, and writes nothing', () async {
      final applied = File('supabase/migrations/162_reseed_exercise_library.sql');
      final before = applied.readAsBytesSync();
      for (final out in ['supabase/migrations', './supabase/migrations', 'supabase/../supabase/migrations/', Directory('supabase/migrations').absolute.path]) {
        final r = await _generateAsync(['162_reseed_exercise_library.sql', '--out', out], 'generator, applied number, --out $out');
        expect(r.exitCode, isNot(0), reason: '--out $out rewrote the immutable applied migration 162');
        expect('${r.stderr}', contains('already in the applied ledger'), reason: '--out $out');
      }
      expect(applied.readAsBytesSync(), before);
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
      expect(plain, contains('-- Linked diagnose-doc: 2026-11-10-library-batch-s1b3-retire-donkey-calf-raise-c3e8f1'));
      expect(_batchLabel(plain), 'S1b-3', reason: 'the generator names the batch the rollback checks are shaped by');
      expect(_removalViolations(plain), isEmpty);
      expect(_removalViolations(split), isEmpty);
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

    // Batch C2b's rollback shape is still checked, against the applied file 171 (immutable, on disk): the shape-aware branch
    // for a label other than the newest batch's must keep catching what it caught.
    test('MUTATION (C2b branch, migration 171): deleting the reactivation line, or turning it into a deactivation, is a violation', () {
      final c2b = File('supabase/migrations/171_reseed_exercise_library.sql').readAsStringSync();
      expect(_batchLabel(c2b), 'C2b');
      expect(_rollbackViolations(c2b, rows), isEmpty, reason: 'the applied file 171 is green under its own shape');
      final gone = c2b.replaceAll(_rollbackLine(), '');
      expect(gone, isNot(c2b), reason: 'the mutation must apply');
      expect(_rollbackViolations(gone, rows), isNotEmpty, reason: 'line deleted');
      final other = c2b.replaceAll('SET is_active = true WHERE id IN', 'SET is_active = false WHERE id IN');
      expect(other, isNot(c2b), reason: 'the mutation must apply');
      expect(_rollbackViolations(other, rows), isNotEmpty, reason: 'wrong direction');
    });

    // Batch C2c (OI-474): the rollback restores E230's four cloud columns. Each mutation is a way the line is lost or changed.
    // Since Library Batch S1b-2 the generator emits the S1b-2 shape, so the C2c branch is checked against the applied file 173
    // (immutable, on disk), as the C2b branch is against 171.
    test('the C2c file (migration 173) restores the four E230 columns from the record before, and its arrays are verbatim those of migration 171', () {
      final c2c = File('supabase/migrations/173_reseed_exercise_library.sql').readAsStringSync();
      expect(_batchLabel(c2c), 'C2c');
      final before = (_retagRecord()['before'] as Map).cast<String, dynamic>();
      final line = _retagRollbackLine();
      expect(c2c, contains('--   $line'));
      expect(line, contains("equipment_needed = ARRAY['cables']::text[]"));
      expect(line, contains("logging_type = 'weight_reps'"));
      // MIRROR: the restored values are the ones the PREVIOUS seed gave the row, byte for byte (the tuple of E230 in 171).
      final c2b = File('supabase/migrations/171_reseed_exercise_library.sql').readAsStringSync();
      final tuple = c2b.split('\n').singleWhere((l) => l.startsWith("('${_cloudId('E230')}'"));
      for (final k in ['equipment_needed', 'coaching_cues', 'common_mistakes']) {
        expect(tuple, contains(_sqlArray(before[k] as List)), reason: '$k: before must be what 171 seeded');
      }
      expect(tuple, contains("'${before['logging_type']}'"));
    });

    test('MUTATION (C2c, migration 173): a deleted restore line, one changed cue, a dropped WHERE, an empty IN () and a stray reactivation are each a violation', () {
      final plain = File('supabase/migrations/173_reseed_exercise_library.sql').readAsStringSync();
      final line = _retagRollbackLine();
      expect(_rollbackViolations(plain, rows), isEmpty);
      final gone = plain.replaceAll('--   $line', '');
      expect(gone, isNot(plain), reason: 'the mutation must apply');
      expect(_rollbackViolations(gone, rows), isNotEmpty, reason: 'line deleted');
      final cue = ((_retagRecord()['before'] as Map)['coaching_cues'] as List).first as String;
      final edited = plain.replaceAll("'$cue'", "'${cue}x'");
      expect(edited, isNot(plain), reason: 'the mutation must apply');
      expect(_rollbackViolations(edited, rows), isNotEmpty, reason: 'one cue of the restore changed');
      final noWhere = plain.replaceAll(" WHERE id = '${_cloudId('E230')}';", ';');
      expect(noWhere, isNot(plain), reason: 'the mutation must apply');
      expect(_rollbackViolations(noWhere, rows), isNotEmpty, reason: 'WHERE dropped');
      expect(_rollbackViolations('$plain\n-- UPDATE exercise_library SET is_active = true WHERE id IN ();', rows), isNotEmpty, reason: 'empty IN ()');
      expect(_rollbackViolations('$plain\n--   UPDATE exercise_library SET is_active = true WHERE id IN (\'x\');', rows), isNotEmpty, reason: 'stray reactivation');
    });

    test('an Intent line that names a batch this test has no shape for (or none) is a violation, never a pass', () {
      final unknown = plain.replaceFirst('Batch S1b-3)', 'Batch C2z)');
      expect(unknown, isNot(plain), reason: 'the mutation must apply');
      expect(_rollbackViolations(unknown, rows), isNotEmpty);
      final none = plain.replaceFirst(RegExp(r'exercises, library v\d+, Batch S1b-3\)'), 'exercises)');
      expect(none, isNot(plain), reason: 'the mutation must apply');
      expect(_rollbackViolations(none, rows), isNotEmpty);
    });

    // Since Library Batch S1b-3 the generator emits the S1b-3 shape, so the S1b-2 checks run against the applied file 174
    // (immutable, on disk), as the C2c branch runs against 173 and C2b against 171.
    test('Batch S1b-2 (migration 174) owns no removal: no removals entry is removed_in s1b2; the file has no reactivation line and ONE deactivation of its nine rows', () {
      final plain = File('supabase/migrations/174_reseed_exercise_library.sql').readAsStringSync();
      expect(_batchLabel(plain), 'S1b-2');
      expect(_removalEntries().where((e) => e['removed_in'] == 's1b2'), isEmpty);
      expect(plain, isNot(contains('IN ()')));
      expect(plain, isNot(contains('SET is_active = true WHERE id IN')));
      expect('SET is_active = false WHERE id IN'.allMatches(plain).length, 2, reason: 'the header and the commented block');
      expect(plain, contains(_s1b2DeactivateLine()));
    });

    test('the S1b-2 restores are the values migration 173 seeded for E010 and E045, and the nine rows have no tuple in 173', () {
      final plain = File('supabase/migrations/174_reseed_exercise_library.sql').readAsStringSync();
      final c2c = File('supabase/migrations/173_reseed_exercise_library.sql').readAsStringSync();
      for (final e in (_s1b2Record()['rows'] as List).cast<Map<String, dynamic>>()) {
        final tuple = c2c.split('\n').singleWhere((l) => l.startsWith("('${_cloudId(e['id'] as String)}'"));
        expect(tuple, contains(_sqlArray(e['before'] as List)), reason: '${e['id']}: before must be what 173 seeded');
      }
      for (final id in _s1b2NewIds) {
        expect(c2c, isNot(contains("('${_cloudId(id)}'")), reason: '$id is new in S1b-2');
        expect(plain, contains("('${_cloudId(id)}'"), reason: '$id has a tuple in the S1b-2 file');
      }
    });

    test('MUTATION (S1b-2, migration 174): a deleted restore, a changed restore value, a dropped deactivation and a stray reactivation are each a violation', () {
      final plain = File('supabase/migrations/174_reseed_exercise_library.sql').readAsStringSync();
      expect(_rollbackViolations(plain, rows), isEmpty);
      final restore = _s1b2RestoreLines().first;
      final gone = plain.replaceAll('--   $restore', '');
      expect(gone, isNot(plain), reason: 'the mutation must apply');
      expect(_rollbackViolations(gone, rows), isNotEmpty, reason: 'restore deleted');
      final value = plain.replaceAll("ARRAY['Beginner','Intermediate']::text[] WHERE id = '${_cloudId('E010')}'",
          "ARRAY['Beginner','Intermediate','Advanced']::text[] WHERE id = '${_cloudId('E010')}'");
      expect(value, isNot(plain), reason: 'the mutation must apply');
      expect(_rollbackViolations(value, rows), isNotEmpty, reason: 'restore value changed');
      final noDeactivate = plain.replaceAll('--   ${_s1b2DeactivateLine()}', '');
      expect(noDeactivate, isNot(plain), reason: 'the mutation must apply');
      expect(_rollbackViolations(noDeactivate, rows), isNotEmpty, reason: 'deactivation dropped');
      expect(_rollbackViolations('$plain\n--   UPDATE exercise_library SET is_active = true WHERE id IN (\'x\');', rows), isNotEmpty,
          reason: 'stray reactivation');
    });

    test('MUTATION (S1b-3): a deleted restore, a reactivation that lost E053\'s own cue, a dropped reactivation, an idempotent claim and a stray IN-list line are each a violation', () {
      expect(_rollbackViolations(plain, rows), isEmpty);
      final restore = _s1b3RestoreLine();
      final gone = plain.replaceAll('--   $restore', '');
      expect(gone, isNot(plain), reason: 'the mutation must apply');
      expect(_rollbackViolations(gone, rows), isNotEmpty, reason: 'restore deleted');
      final cue = (_e053V23()['coaching_cues'] as List).first as String;
      final edited = plain.replaceAll("'${cue.replaceAll("'", "''")}','", "'${cue}x','");
      expect(edited, isNot(plain), reason: 'the mutation must apply');
      expect(_rollbackViolations(edited, rows), isNotEmpty, reason: 'one of E053\'s own cues changed');
      final noReactivate = plain.replaceAll('--   ${_s1b3ReactivateLine()}', '');
      expect(noReactivate, isNot(plain), reason: 'the mutation must apply');
      expect(_rollbackViolations(noReactivate, rows), isNotEmpty, reason: 'reactivation dropped');
      final idempotent = plain.replaceAll("1 first-time, this batch's merge of E053 Donkey Calf Raise into G1373", 'all idempotent');
      expect(idempotent, isNot(plain), reason: 'the mutation must apply');
      expect(_rollbackViolations(idempotent, rows), isNotEmpty, reason: 'E053 claimed already inactive');
      expect(_rollbackViolations('$plain\n--   UPDATE exercise_library SET is_active = false WHERE id IN (\'x\');', rows), isNotEmpty,
          reason: 'stray deactivation');
      // MIRROR: the reactivation's cues are the ones migration 174 seeded for E053, byte for byte.
      final m174 = File('supabase/migrations/174_reseed_exercise_library.sql').readAsStringSync();
      final tuple = m174.split('\n').singleWhere((l) => l.startsWith("('${_cloudId('E053')}'"));
      expect(tuple, contains(_sqlArray(_e053V23()['coaching_cues'] as List)));
      expect(tuple, contains(_sqlArray(_e053V23()['common_mistakes'] as List)));
    });

    // The generator's own guard: it must refuse (exit 2, nothing written) rather than seed one thing and roll back to another.
    test('the generator refuses: a missing or drifted kept-row record, a wrong before, a record naming no row or a new row, a missing previous seed, a missing new row, a missing merges record, a merged id still shipped or listed by no kept row, and a previous-seed tuple of the wrong shape; the unmodified files still generate', () async {
      Future<ProcessResult> run(Directory root, String why) => runSpawnAsync('node', ['${root.path}/scripts/seed_exercise_library.js', '999_guard_seed_exercise_library.sql', '--out', '${root.path}/out'],
              why: why, report: (_) {})
          .timeout(const Duration(seconds: 60));
      File out(Directory root) => File('${root.path}/out/999_guard_seed_exercise_library.sql');
      Future<void> refused(Directory root, String why, List<String> says) async {
        final r = await run(root, why);
        expect(r.exitCode, 2, reason: '$why: ${r.stdout}${r.stderr}');
        for (final w in says) {
          expect('${r.stderr}', contains(w), reason: why);
        }
        expect(out(root).existsSync(), isFalse, reason: '$why: nothing written');
      }
      final root = Directory.systemTemp.createTempSync('s1b3_guard_');
      try {
        Directory('${root.path}/scripts/data').createSync(recursive: true);
        Directory('${root.path}/assets/data').createSync(recursive: true);
        final gen = File('${root.path}/scripts/seed_exercise_library.js')..writeAsStringSync(File(_generator).readAsStringSync());
        final genText = gen.readAsStringSync();
        File('${root.path}/scripts/data/library_batch_c2_removals.json').writeAsStringSync(File('scripts/data/library_batch_c2_removals.json').readAsStringSync());
        final mergesFile = File('${root.path}/scripts/data/library_s1b3_merges.json');
        final mergesText = File('scripts/data/library_s1b3_merges.json').readAsStringSync();
        Directory('${root.path}/supabase/migrations').createSync(recursive: true);
        final prevFile = File('${root.path}/supabase/migrations/174_reseed_exercise_library.sql')
          ..writeAsStringSync(File('supabase/migrations/174_reseed_exercise_library.sql').readAsStringSync());
        final prevText = prevFile.readAsStringSync();
        final libText = File('assets/data/exercise_library.json').readAsStringSync();
        final libFile = File('${root.path}/assets/data/exercise_library.json')..writeAsStringSync(libText);
        final recFile = File('${root.path}/scripts/data/library_s1b3_name_aliases.json');
        final recText = File('scripts/data/library_s1b3_name_aliases.json').readAsStringSync();
        final rec = _s1b3Record();
        final recRow = (rec['rows'] as List).cast<Map<String, dynamic>>().single;

        // The merges record missing: a hard stop (the importer skips; the generator cannot know what to reactivate).
        await refused(root, 'no merges record', ['merges record not found']);
        mergesFile.writeAsStringSync(mergesText);

        await refused(root, 'no kept-row record', ['kept-row record not found']);
        recFile.writeAsStringSync(jsonEncode({...rec, 'rows': [{...recRow, 'after': ['Something Else']}]}));
        await refused(root, 'a record whose after differs', ['G1373', 'name_aliases']);
        recFile.writeAsStringSync(jsonEncode({...rec, 'rows': [recRow, {'id': 'E999', 'before': null, 'after': null}]}));
        await refused(root, 'a record naming no library row', ['E999', 'not a library row']);
        // `before` is what the rollback restores: G1373 restored to an alias 174 never seeded.
        recFile.writeAsStringSync(jsonEncode({...rec, 'rows': [{...recRow, 'before': ['Calf Raise']}]}));
        await refused(root, 'a record whose before is not what 174 seeded', ['G1373', 'previous seed migration (174)']);
        recFile.writeAsStringSync(recText);

        // The previous seed migration missing: the guard has no input, so it stops instead of passing.
        prevFile.deleteSync();
        await refused(root, 'no previous seed migration', ['previous seed migration 174']);
        prevFile.writeAsStringSync(prevText);

        // A record row that is one of the batch's new rows, and a new row the library lacks (S1b-3 inserts none, so the
        // sandbox generator is told it does).
        gen.writeAsStringSync(genText.replaceFirst('  newRowIds: [],', "  newRowIds: ['G1373'],"));
        await refused(root, 'a record naming a new row', ['G1373', 'BATCH.newRowIds']);
        gen.writeAsStringSync(genText.replaceFirst('  newRowIds: [],', "  newRowIds: ['N99'],"));
        await refused(root, 'a new row missing from the library', ['N99', 'newRowIds']);
        gen.writeAsStringSync(genText);

        // A merged id back in the library (it would be upserted active, then retired: a row that ships dead).
        final lib = (jsonDecode(libText) as List).cast<Map<String, dynamic>>();
        libFile.writeAsStringSync(jsonEncode([...lib, {..._e053V23()}]));
        await refused(root, 'E053 back in the library', ['E053', 'still in the library']);
        // No kept row lists the merged id.
        libFile.writeAsStringSync(jsonEncode([for (final r in lib) r['id'] == 'G1373' ? (Map<String, dynamic>.from(r)..remove('merged_ids')) : r]));
        await refused(root, 'G1373 without merged_ids', ['E053', 'no kept row lists it']);
        libFile.writeAsStringSync(libText);

        // E053's tuple in 174 of the wrong shape: a 7th array (a row with aliases), one array dropped, a changed tail.
        final e053 = prevText.split('\n').singleWhere((l) => l.startsWith("('${_cloudId('E053')}'"));
        expect(e053, endsWith('NULL, now()),'), reason: 'E053 is mid-slice in 174: the tail check must strip the comma');
        for (final (bad, says) in [
          (e053.replaceFirst('NULL, now()),', "ARRAY['x']::text[], now()),"), 'holds 7 array literals'),
          (e053.replaceFirst("ARRAY['Calves']::text[], ", "'Calves', "), 'holds 5 array literals'),
          (e053.replaceFirst('NULL, now()),', "'x', now()),"), 'does not end with'),
        ]) {
          prevFile.writeAsStringSync(prevText.replaceFirst(e053, bad));
          await refused(root, 'E053 tuple: $says', ['E053', says]);
        }
        // A cue holding an escaped quote and a bracket inside the string is spliced verbatim (quote-aware scan).
        final tricky = e053.replaceFirst("'full range'", "'don''t [stop] short'");
        expect(tricky, isNot(e053), reason: 'the mutation must apply');
        prevFile.writeAsStringSync(prevText.replaceFirst(e053, tricky));
        final quoted = await run(root, 'E053 cue with a quote and a bracket');
        expect(quoted.exitCode, 0, reason: '${quoted.stdout}${quoted.stderr}');
        expect(out(root).readAsStringSync(), contains("'weight on balls of feet','don''t [stop] short']::text[], common_mistakes = "));
        out(root).deleteSync();
        prevFile.writeAsStringSync(prevText);

        // MIRROR: the unmodified files generate, and write the S1b-3 shape.
        final ok = await run(root, 'seed generator with the unmodified records');
        expect(ok.exitCode, 0, reason: '${ok.stdout}${ok.stderr}');
        expect(_batchLabel(out(root).readAsStringSync()), 'S1b-3');
        expect(_rollbackViolations(out(root).readAsStringSync(), rows), isEmpty);

        // MIRROR (the branch the S1b-3 shape never takes): a batch that owns removals and twins gets its reactivation and twin
        // lines, with non-empty lists. The sandbox generator is told its batch is c2b (6 own removals, 4 twins).
        out(root).deleteSync();
        expect(genText, contains("batchTag: 's1b3'"), reason: 'the mutation must apply');
        gen.writeAsStringSync(genText.replaceFirst("batchTag: 's1b3'", "batchTag: 'c2b'"));
        final owns = await run(root, 'seed generator told it owns the C2b removals');
        expect(owns.exitCode, 0, reason: '${owns.stdout}${owns.stderr}');
        final sql = out(root).readAsStringSync();
        expect(sql, contains('--   ${_rollbackLine()}'));
        expect(sql, contains('--   ${_twinRollbackLine()}'));
        expect(sql, isNot(contains('IN ()')));
        expect(sql, isNot(contains('this batch removes and adds no row')), reason: 'the header must not claim "no row" for a batch that owns some');
        expect(sql, isNot(contains('first-time')), reason: 'the c2b tag owns no merge, so no merged row is called first-time');
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('MUTATION (C2a): a dropped deactivation, a deactivation before the upsert and a still-upserted removed row are each a violation', () {
      final first = _removedIds().first;
      final stmt = "UPDATE exercise_library SET is_active = false WHERE id = '${_cloudId(first)}';";
      expect(plain, contains(stmt));
      final dropped = plain.replaceFirst(stmt, '');
      expect(dropped, isNot(plain), reason: 'the mutation must apply');
      expect(_removalViolations(dropped), isNotEmpty, reason: 'dropped');
      final early = '$stmt\n${plain.replaceFirst(stmt, '')}';
      expect(_removalViolations(early), isNotEmpty, reason: 'before the upsert');
      final lines = plain.split('\n');
      final i = lines.indexWhere((l) => l.startsWith("('"));
      final upserted = [...lines]..insert(i, lines[i].replaceFirst(RegExp(r"^\('[0-9a-f-]{36}'"), "('${_cloudId(first)}'"));
      expect(_removalViolations(upserted.join('\n')), isNotEmpty, reason: 'still upserted');
    });

    test('MUTATION (C2a): a removed id that is back in the library makes the generator refuse (exit 2), not ship it dead', () async {
      final lib = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
      final back = Map<String, dynamic>.from(lib.first)..['id'] = _removedIds().first;
      final tmp = Directory.systemTemp.createTempSync('c2a_readded');
      try {
        final f = File('${tmp.path}/lib.json')..writeAsStringSync(jsonEncode([...lib, back]));
        final r = await runSpawnAsync('node', [_generator, '999_readded_seed_exercise_library.sql', '--out', tmp.path],
            why: 'seed generator on a library with a removed id re-added', extraEnv: {'SEED_LIBRARY_JSON': f.path}, report: (_) {})
            .timeout(const Duration(seconds: 60));
        expect(r.exitCode, 2, reason: 'stderr: ${r.stderr}');
        expect(r.stderr.toString(), contains(_removedIds().first));
        expect(File('${tmp.path}/999_readded_seed_exercise_library.sql').existsSync(), isFalse);
        // MIRROR: the unmodified library still generates.
        final ok = await _generateAsync(['999_readded_seed_exercise_library.sql', '--out', tmp.path], 'unmodified library still generates');
        expect(ok.exitCode, 0, reason: 'stderr: ${ok.stderr}');
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('the generator, the removals file and the Dart prune set name the same ids', () {
      final fromSql = RegExp(r"UPDATE exercise_library SET is_active = false WHERE id = '([0-9a-f-]{36})';")
          .allMatches(plain)
          .map((m) => m.group(1)!)
          .toSet();
      // Batch C2b: four removed rows share a name with a twin, so they take the twin's cues (the cue-copy form); the seven Batch A
      // retire statements use the same form and are not removals.
      final cueForm = RegExp(r"UPDATE exercise_library r SET is_active = false, coaching_cues = k.coaching_cues, common_mistakes = k.common_mistakes FROM exercise_library k WHERE r.id = '([0-9a-f-]{36})' AND")
          .allMatches(plain)
          .map((m) => m.group(1)!)
          .toSet();
      final retiredBatchA = {
        for (final r in (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>())
          for (final i in (r['merged_ids'] as List? ?? const [])) _cloudId(i as String),
      };
      final fromFile = {for (final i in _removedIds()) _cloudId(i)};
      expect({...fromSql, ...cueForm.difference(retiredBatchA)}, fromFile);
      expect(cueForm.difference(retiredBatchA).length, 4, reason: 'E084 E111 E169 E179 share a name with their twin');
      expect(_removedIds().toSet(), kRetiredLibraryIdsNoTwin);
    });

    test('MUTATION: a --split file that loses one conflict clause is caught by the clause count', () {
      final broken = split.replaceFirst('name_aliases = EXCLUDED.name_aliases;', 'name_aliases = EXCLUDED.name_aliases');
      expect(broken, isNot(split), reason: 'the mutation must apply');
      expect('name_aliases = EXCLUDED.name_aliases;'.allMatches(broken).length, isNot(2));
    });
  });
}
