// Batch C1 (docs/plans/2026-10-25-library-batch-c-new-rows.md, R5 and Task 2.3): the injury tags of the new rows.
//
// TABLE GROUP (this file at commit 3): the founder-approved table scripts/data/library_injury_additions_v15.json against
// the NON-held rows of scripts/data/library_batch_c_source.json and the ORIGINAL library rows (E-ids) on disk, using the
// independent Dart recomputation in test/helpers/library_injury_floor.dart. A new row's final tags are
// sorted(raw source tags UNION its table row).
//
// The LIBRARY GROUP (final library vs the table) arrives with the importer at commit 5.
//
// Every check is a pure function over in-memory maps, so each one is mutated below and must go red.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/injury_vocab.dart';

import '../helpers/library_injury_floor.dart';
import '../helpers/spawn.dart';

const _srcRel = 'scripts/data/library_batch_c_source.json';
const _tableRel = 'scripts/data/library_injury_additions_v15.json';
const _libRel = 'assets/data/exercise_library.json';
const _builderRel = 'scripts/build_library_injury_additions_v15.js';

const _classes = {'floor', 'majority', 'family', 'twin', 'judgement'};
const _topPickThreshold = 100;

Map<String, dynamic> _readMap(String p) => jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;
List<Map<String, dynamic>> _rowsOf(Map<String, dynamic> src) => (src['rows'] as List).cast<Map<String, dynamic>>();
List<String> _strs(Object? v) => (v as List? ?? const []).map((e) => e.toString()).toList();
Map<String, dynamic> _tableRows(Map<String, dynamic> t) => t['rows'] as Map<String, dynamic>;
Map<String, dynamic> _trow(Map<String, dynamic> t, String id) => _tableRows(t)[id] as Map<String, dynamic>;
List<Map<String, dynamic>> _shipped(Map<String, dynamic> src) => _rowsOf(src).where((r) => r['hold'] == null).toList();
Map<String, dynamic> _srcRow(Map<String, dynamic> src, String id) => _rowsOf(src).firstWhere((r) => r['id'] == id);
Map<String, dynamic> _deep(Map<String, dynamic> m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

/// sorted(raw source tags UNION the table row tokens): the tags the new row ships with.
List<String> _finalTags(Map<String, dynamic> row, Map<String, dynamic> table) =>
    sortedUnique([..._strs(row['injury_contraindications']), ..._strs(_trow(table, row['id'] as String)['tokens'])]);

List<String> _shapeViolations(Map<String, dynamic> table) {
  final out = <String>[];
  if ((table['_meta'] as Map)['version'] != 15) out.add('table version is not 15');
  for (final e in _tableRows(table).entries) {
    final r = e.value as Map<String, dynamic>;
    final tokens = _strs(r['tokens']);
    if (tokens.join(',') != (sortedUnique(tokens)).join(',')) out.add('${e.key} tokens not sorted and unique');
    for (final t in tokens) {
      if (!InjuryVocab.canonicalTokens.contains(t)) out.add('${e.key} token $t is not canonical');
    }
    if (!_classes.contains(r['class'])) out.add('${e.key} class ${r['class']}');
    final reason = '${r['reason']}'.trim();
    if (reason.isEmpty || reason.startsWith('PENDING')) out.add('${e.key} has no decided reason: $reason');
    if ('${r['variant_family']}'.isEmpty) out.add('${e.key} has no variant_family');
  }
  final safe = _strs(table['safe_pool_additions']);
  if (safe.length != safe.toSet().length) out.add('safe_pool_additions has a duplicate');
  return out;
}

/// The table id set equals the NON-held source ids (a table row for a held id, or a missing row, is red).
List<String> _idSetViolations(Map<String, dynamic> src, Map<String, dynamic> table) {
  final shipped = _shipped(src).map((r) => r['id'] as String).toSet();
  final ids = _tableRows(table).keys.toSet();
  final held = _rowsOf(src).where((r) => r['hold'] != null).map((r) => r['id'] as String).toSet();
  return [
    ...shipped.difference(ids).map((i) => '$i ships but has no table row'),
    ...ids.where(held.contains).map((i) => '$i has a table row but is HELD'),
    ...ids.difference(shipped).difference(held).map((i) => '$i has a table row but is not in the source'),
  ];
}

/// The SOURCE variant_family of every table id equals the table's (a late source edit cannot be ignored silently).
List<String> _familyFreezeViolations(Map<String, dynamic> src, Map<String, dynamic> table) {
  final out = <String>[];
  for (final r in _shipped(src)) {
    final t = _tableRows(table)[r['id']] as Map<String, dynamic>?;
    if (t != null && t['variant_family'] != r['variant_family']) {
      out.add('${r['id']} source family ${r['variant_family']} vs table ${t['variant_family']}');
    }
  }
  return out;
}

/// Every new row ends with its floor, family-rule and twin tokens.
List<String> _floorViolations(Map<String, dynamic> src, Map<String, dynamic> table, List<Map<String, dynamic>> lib) {
  final out = <String>[];
  for (final r in _shipped(src)) {
    if (_tableRows(table)[r['id']] == null) continue;
    final have = _finalTags(r, table);
    for (final t in requiredTokens(r, lib)) {
      if (!have.contains(t)) out.add('${r['id']} ${r['name']} is missing $t (has $have)');
    }
  }
  return out;
}

/// A NON-held new id with at least [_topPickThreshold] picks in the OFF experiment has tags or is a safe-pool name.
List<String> _topPickViolations(Map<String, dynamic> src, Map<String, dynamic> table) {
  final picks = (((src['_meta'] as Map)['off_experiment_picks']) as Map).cast<String, dynamic>();
  final safe = _strs(table['safe_pool_additions']).map((n) => n.toLowerCase()).toSet();
  final out = <String>[];
  for (final e in picks.entries) {
    if ((e.value as int) < _topPickThreshold) continue;
    final r = _rowsOf(src).where((x) => x['id'] == e.key).firstOrNull;
    if (r == null || r['hold'] != null) continue; // a picture-held id is skipped
    if (_tableRows(table)[e.key] == null) continue;
    if (_finalTags(r, table).isEmpty && !safe.contains('${r['name']}'.toLowerCase())) {
      out.add('${e.key} ${r['name']} has ${e.value} picks and no tag');
    }
  }
  return out;
}

/// Each safe_pool_additions name is the name of a NON-held source row (once), that row ends untagged, and no OTHER row ends untagged.
List<String> _safePoolViolations(Map<String, dynamic> src, Map<String, dynamic> table) {
  final names = _strs(table['safe_pool_additions']);
  final shipped = _shipped(src);
  final byName = <String, List<Map<String, dynamic>>>{};
  for (final r in shipped) {
    byName.putIfAbsent('${r['name']}'.toLowerCase(), () => []).add(r);
  }
  final out = <String>[];
  for (final n in names) {
    final hits = byName[n.toLowerCase()] ?? const [];
    if (hits.length != 1) {
      out.add('safe pool name "$n" matches ${hits.length} non-held source rows');
    } else if (_tableRows(table)[hits.first['id']] != null && _finalTags(hits.first, table).isNotEmpty) {
      out.add('safe pool name "$n" ${hits.first['id']} ends with tags ${_finalTags(hits.first, table)}');
    }
  }
  final safe = names.map((n) => n.toLowerCase()).toSet();
  for (final r in shipped) {
    if (_tableRows(table)[r['id']] == null) continue;
    if (_finalTags(r, table).isEmpty && !safe.contains('${r['name']}'.toLowerCase())) {
      out.add('${r['id']} ${r['name']} ends untagged and is not a safe pool name');
    }
  }
  return out;
}

ProcessResult _builder(List<String> args, String why) => runSpawn('node', [_builderRel, ...args], why: why, report: (_) {});

void main() {
  group('table group: the founder table against the source and the original library rows', () {
    late Map<String, dynamic> src;
    late Map<String, dynamic> table;
    late List<Map<String, dynamic>> lib;
    setUpAll(() {
      src = _readMap(_srcRel);
      table = _readMap(_tableRel);
      lib = (jsonDecode(File(_libRel).readAsStringSync()) as List).cast<Map<String, dynamic>>();
    });
    Map<String, dynamic> t() => _deep(table);
    Map<String, dynamic> s() => _deep(src);

    test('shape: version 15, canonical sorted tokens, known classes, a decided reason on every row', () {
      expect(_shapeViolations(table), isEmpty);
    });
    test('MUTATION: a non-canonical token, an unsorted pair, a PENDING reason and an unknown class are each a violation', () {
      final a = t();
      _trow(a, _tableRows(a).keys.first)['tokens'] = ['not_a_token'];
      expect(_shapeViolations(a), isNotEmpty);
      final b = t();
      _trow(b, _tableRows(b).keys.first)['tokens'] = ['shoulder', 'knee'];
      expect(_shapeViolations(b), isNotEmpty);
      final c = t();
      _trow(c, _tableRows(c).keys.first)['reason'] = 'PENDING founder review';
      expect(_shapeViolations(c), isNotEmpty);
      final d = t();
      _trow(d, _tableRows(d).keys.first)['class'] = 'guess';
      expect(_shapeViolations(d), isNotEmpty);
    });

    test('the table ids equal the NON-held source ids', () {
      expect(_idSetViolations(src, table), isEmpty);
      expect(_tableRows(table), isNotEmpty);
    });
    test('MUTATION: delete one table row; add a row for a held id; add a row for an unknown id -> each is a violation', () {
      final a = t();
      _tableRows(a).remove(_tableRows(a).keys.first);
      expect(_idSetViolations(src, a), isNotEmpty);
      final held = _rowsOf(src).firstWhere((r) => r['hold'] != null)['id'] as String;
      final b = t();
      _tableRows(b)[held] = _deep(_trow(b, _tableRows(b).keys.first));
      expect(_idSetViolations(src, b), isNotEmpty);
      final c = t();
      _tableRows(c)['G9999'] = _deep(_trow(c, _tableRows(c).keys.first));
      expect(_idSetViolations(src, c), isNotEmpty);
    });
    test('MUTATION: ship one non-held source row the builder did not see (release a hold) -> red', () {
      final a = s();
      final heldId = _rowsOf(a).firstWhere((r) => r['hold'] != null)['id'] as String;
      _srcRow(a, heldId).remove('hold');
      expect(_idSetViolations(a, table), isNotEmpty);
    });

    test('the SOURCE variant_family of every table id equals the table family', () {
      expect(_familyFreezeViolations(src, table), isEmpty);
    });
    test('MUTATION: change a source variant_family after the table is built; move a table row to another family -> red', () {
      final a = s();
      final id = _shipped(a).firstWhere((r) => r['variant_family'] != null)['id'] as String;
      _srcRow(a, id)['variant_family'] = 'some_other_family';
      expect(_familyFreezeViolations(a, table), isNotEmpty);
      final b = t();
      _trow(b, id)['variant_family'] = 'some_other_family';
      expect(_familyFreezeViolations(src, b), isNotEmpty);
    });

    test('every table row meets floor, family and twin (independent Dart recomputation)', () {
      expect(_floorViolations(src, table, lib), isEmpty);
    });
    test('the four name and pattern rules hold with recomputed denominators', () {
      final shipped = _shipped(src);
      for (final entry in {
        'push-up named': (shipped.where((r) => RegExp(r'push[- ]?up', caseSensitive: false).hasMatch('${r['name']}')).toList(), 'shoulder'),
        'elbow pattern': (shipped.where((r) => _strs(r['movement_pattern']).any((p) => p == 'elbow_flexion' || p == 'elbow_extension')).toList(), 'elbow'),
        'twist / V-up / crunch / sit-up named': (shipped.where((r) => RegExp(r'russian twist|v[- ]?up|crunch|sit[- ]?up', caseSensitive: false).hasMatch('${r['name']}')).toList(), 'lower_back'),
        'hip abduction / adduction named': (shipped.where((r) => RegExp(r'\bhip (abduction|adduction)\b', caseSensitive: false).hasMatch('${r['name']}')).toList(), 'hip'),
      }.entries) {
        final rows = entry.value.$1;
        expect(rows, isNotEmpty, reason: 'denominator for ${entry.key}');
        for (final r in rows) {
          expect(_finalTags(r, table), contains(entry.value.$2), reason: '${entry.key}: ${r['id']} ${r['name']}');
        }
      }
    });
    test('the twin rows carry their library twin tags, read from the library on disk', () {
      for (final e in kTwinLibraryRow.entries) {
        final row = _srcRow(src, e.key);
        final libRow = lib.firstWhere((l) => l['id'] == e.value);
        expect(injuryTagsOf(libRow), isNotEmpty, reason: '${e.value} is the twin of ${e.key}');
        expect(_finalTags(row, table), containsAll(injuryTagsOf(libRow)), reason: e.key);
      }
    });
    test('MUTATION: remove one floor token; drop a twin token; remove shoulder from one push-up-named row -> red', () {
      // A floor token that lives only in the table row: take the first row whose floor is non-empty and whose raw tags lack it.
      final a = t();
      final fl = _shipped(src).firstWhere((r) {
        final miss = floorOf(r['variant_family'] as String?, lib).where((x) => !_strs(r['injury_contraindications']).contains(x));
        return miss.isNotEmpty;
      });
      final tok = floorOf(fl['variant_family'] as String?, lib).firstWhere((x) => !_strs(fl['injury_contraindications']).contains(x));
      _trow(a, fl['id'] as String)['tokens'] = _strs(_trow(a, fl['id'] as String)['tokens']).where((x) => x != tok).toList();
      expect(_floorViolations(src, a, lib), isNotEmpty);
      final b = t();
      _trow(b, 'G0814')['tokens'] = <String>[];
      final b2 = s();
      _srcRow(b2, 'G0814')['injury_contraindications'] = <String>[];
      expect(_floorViolations(b2, b, lib), isNotEmpty);
      final c = t();
      final c2 = s();
      final pu = _shipped(c2).firstWhere((r) => RegExp(r'push[- ]?up', caseSensitive: false).hasMatch('${r['name']}'));
      _srcRow(c2, pu['id'] as String)['injury_contraindications'] = <String>[];
      _trow(c, pu['id'] as String)['tokens'] = <String>[];
      expect(_floorViolations(c2, c, lib), isNotEmpty);
    });

    test('every NON-held id with at least $_topPickThreshold picks in the OFF experiment has tags or is a safe-pool name', () {
      expect(_topPickViolations(src, table), isEmpty);
      final picks = (((src['_meta'] as Map)['off_experiment_picks']) as Map).cast<String, dynamic>();
      expect(picks.values.where((v) => (v as int) >= _topPickThreshold), isNotEmpty);
    });
    test('MUTATION: remove G0845 tags (family rule) and an experiment id outright -> red', () {
      final a = t();
      final a2 = s();
      _trow(a, 'G0845')['tokens'] = <String>[];
      _srcRow(a2, 'G0845')['injury_contraindications'] = <String>[];
      expect(_topPickViolations(a2, a), isNotEmpty);
      expect(_floorViolations(a2, a, lib), isNotEmpty);
    });

    test('safe_pool_additions: each is a NON-held source row name (once), ends untagged, and no other row ends untagged', () {
      expect(_safePoolViolations(src, table), isEmpty);
    });
    test('MUTATION: a name added to safe_pool_additions only; a held row name; an empty-tag row not in the list -> red', () {
      final a = t();
      final tagged = _shipped(src).firstWhere((r) => _finalTags(r, table).isNotEmpty);
      (a['safe_pool_additions'] as List).add(tagged['name']);
      expect(_safePoolViolations(src, a), isNotEmpty, reason: 'a tagged row is not a safe-pool row');
      final b = t();
      final held = _rowsOf(src).firstWhere((r) => r['hold'] != null);
      (b['safe_pool_additions'] as List).add(held['name']);
      expect(_safePoolViolations(src, b), isNotEmpty, reason: 'a held row name matches no non-held row');
      final c = t();
      final c2 = s();
      final victim = _shipped(c2).firstWhere((r) => _finalTags(r, c).isNotEmpty);
      _srcRow(c2, victim['id'] as String)['injury_contraindications'] = <String>[];
      _trow(c, victim['id'] as String)['tokens'] = <String>[];
      expect(_safePoolViolations(c2, c), isNotEmpty, reason: 'an empty-tag row outside the safe-pool list');
    });

    test('the post-fill untagged rate is below the library\'s 11.6% (33 of 285), every untagged row a named safe-pool row', () {
      final shipped = _shipped(src);
      final untagged = shipped.where((r) => _finalTags(r, table).isEmpty).length;
      final rate = untagged / shipped.length;
      printOnFailure('untagged $untagged/${shipped.length} = ${(rate * 100).toStringAsFixed(1)}% vs the library 11.6%');
      expect(rate, lessThan(33 / 285));
      expect(untagged, _strs(table['safe_pool_additions']).length);
    });
  });

  group('builder: add-only and merge-preserving', () {
    late Directory tmp;
    late String copyPath;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lbc_inj_');
      copyPath = '${tmp.path}/table.json';
      File(_tableRel).copySync(copyPath);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    Map<String, dynamic> read() => _readMap(copyPath);

    test('a re-run on the committed table appends nothing and leaves the file byte-identical', () {
      final before = File(copyPath).readAsStringSync();
      final r = _builder(['--table', copyPath], 'builder re-run on a copy of the committed table');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('appended 0 row(s)'));
      expect(File(copyPath).readAsStringSync(), before);
    });

    test('an edited judgement token and an edited safe_pool_additions entry both survive a re-run', () {
      final t = read();
      final id = _tableRows(t).entries.firstWhere((e) => (e.value as Map)['class'] == 'judgement' && _strs((e.value as Map)['tokens']).isNotEmpty).key;
      _trow(t, id)['tokens'] = ['neck'];
      (t['safe_pool_additions'] as List).add('Zz Test Name');
      File(copyPath).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(t)}\n');
      final r = _builder(['--table', copyPath], 'builder re-run after hand edits');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final after = read();
      expect(_strs(_trow(after, id)['tokens']), ['neck']);
      expect(_strs(after['safe_pool_additions']), contains('Zz Test Name'));
    });

    test('--drop removes exactly the row of a HELD id (the committed table has none, so the state is seeded) and appends nothing', () {
      final src = _readMap(_srcRel);
      final held = _rowsOf(src).firstWhere((r) => r['hold'] != null)['id'] as String;
      final t = read();
      expect(_tableRows(t).containsKey(held), isFalse);
      _tableRows(t)[held] = _deep(_trow(t, _tableRows(t).keys.first));
      File(copyPath).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(t)}\n');
      expect(_idSetViolations(src, read()), isNotEmpty, reason: 'seeded state is red in the id-set check');
      final r = _builder(['--table', copyPath, '--drop', held], 'builder --drop of a held id');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final after = read();
      expect(_tableRows(after).containsKey(held), isFalse);
      expect(_tableRows(after).length, _tableRows(_readMap(_tableRel)).length);
      expect(_idSetViolations(src, after), isEmpty);
    });

    test('--drop of a shipped row removes only that row; the next plain run puts a freshly built row back', () {
      final src = _readMap(_srcRel);
      final id = _shipped(src).firstWhere((r) => r['variant_family'] != null)['id'] as String;
      final original = _readMap(_tableRel);
      final r1 = _builder(['--table', copyPath, '--drop', id], 'builder --drop of a shipped id');
      expect(r1.exitCode, 0, reason: '${r1.stdout}${r1.stderr}');
      expect(_tableRows(read()).containsKey(id), isFalse);
      expect(_tableRows(read()).length, _tableRows(original).length - 1);
      final r2 = _builder(['--table', copyPath], 'builder re-run after a drop');
      expect(r2.exitCode, 0, reason: '${r2.stdout}${r2.stderr}');
      expect('${r2.stdout}', contains('appended 1 row(s)'));
      expect(_tableRows(read()).containsKey(id), isTrue);
    });

    test('--out writes elsewhere and leaves the --table input untouched', () {
      final before = File(copyPath).readAsStringSync();
      final out = '${tmp.path}/out.json';
      final r = _builder(['--table', copyPath, '--out', out, '--drop', _tableRows(read()).keys.first], 'builder --out');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(File(copyPath).readAsStringSync(), before);
      expect(File(out).existsSync(), isTrue);
    });
  });
}
