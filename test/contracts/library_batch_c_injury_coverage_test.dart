// Batch C1 (docs/plans/2026-10-25-library-batch-c-new-rows.md, R5 and Task 2.3): the injury tags of the new rows.
//
// TABLE GROUP (this file at commit 3): the founder-approved table scripts/data/library_injury_additions_v15.json against
// the NON-held rows of scripts/data/library_batch_c_source.json and the ORIGINAL library rows (E-ids) on disk, using the
// independent Dart recomputation in test/helpers/library_injury_floor.dart. A new row's final tags are
// sorted(raw source tags UNION its table row).
//
// The LIBRARY GROUP (final library vs the table, and kV14SafePool vs safe_pool_additions) landed with the importer at commit 5.
//
// Every check is a pure function over in-memory maps, so each one is mutated below and must go red.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/injury_vocab.dart';

import '../helpers/injury_safe_pool.dart';
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

/// The 33 names `kV14SafePool` held before Batch C1, pinned as a literal: `injury_safe_pool.dart` is one flat list, so the
/// additions are the remainder after these.
const _original33 = <String>[
  'Machine Chest Press', 'Floor Press', 'Chest Squeeze Press', 'Svend Press', 'Face Pull', 'Band Pull Apart',
  'Reverse Fly', 'Bodyweight Rear Delt Raise', 'Dumbbell Row', 'Seated Cable Row', 'Chest Supported Row', 'Seal Row',
  'Inverted Row', 'TRX Row', 'Machine High Row', 'Machine Low Row', 'Glute Bridge', 'Lateral Band Walk', 'Plank',
  'Dead Bug', 'Pallof Press', 'Cycling (Stationary)', 'Assault Bike', 'Sled Push', 'Prowler Push', 'Slow Walking',
  'Arm Circles', 'Deep Breathing', 'Cat-Cow Stretch', 'Thoracic Extension (Foam Roller)', 'Thoracic Rotation',
  'Foam Roll IT Band', 'Foam Roll Upper Back',
];

List<Map<String, dynamic>> _libNew(List<Map<String, dynamic>> lib) =>
    lib.where((r) => RegExp(r'^[GN]\d').hasMatch('${r['id']}')).toList();

/// LIBRARY GROUP. For every table id the shipped row's tags equal sorted(raw source tags UNION table row) and its
/// variant_family is the frozen one.
List<String> _libTagViolations(Map<String, dynamic> src, Map<String, dynamic> table, List<Map<String, dynamic>> lib) {
  final byId = {for (final r in lib) r['id'] as String: r};
  final out = <String>[];
  for (final r in _shipped(src)) {
    final id = r['id'] as String;
    if (_tableRows(table)[id] == null) continue; // reported by the id-set check
    final row = byId[id];
    if (row == null) {
      out.add('$id has a table row but is not in the library');
      continue;
    }
    final want = _finalTags(r, table);
    final have = _strs(row['injury_contraindications']);
    if (have.join(',') != want.join(',')) out.add('$id ships tags $have, source UNION table is $want');
    if (row['variant_family'] != _trow(table, id)['variant_family']) {
      out.add('$id ships variant_family ${row['variant_family']}, the table froze ${_trow(table, id)['variant_family']}');
    }
  }
  return out;
}

/// The set of shipped new-row ids equals the set of table ids (a release that only deletes `hold` skips the gate otherwise).
List<String> _libIdSetViolations(Map<String, dynamic> table, List<Map<String, dynamic>> lib) {
  final shipped = _libNew(lib).map((r) => r['id'] as String).toSet();
  final ids = _tableRows(table).keys.toSet();
  return [
    ...shipped.difference(ids).map((i) => '$i ships but has no table row'),
    ...ids.difference(shipped).map((i) => '$i has a table row but is not shipped'),
  ];
}

/// Every shipped new row ends with its floor, family-rule and twin tokens, computed from the ORIGINAL library rows.
List<String> _libFloorViolations(List<Map<String, dynamic>> lib) {
  final out = <String>[];
  for (final r in _libNew(lib)) {
    final have = injuryTagsOf(r);
    for (final t in requiredTokens(r, lib)) {
      if (!have.contains(t)) out.add('${r['id']} ${r['name']} ships without $t (has $have)');
    }
  }
  return out;
}

/// kV14SafePool starts with the original 33 names and its remainder equals safe_pool_additions; each name is one library row.
List<String> _poolViolations(Map<String, dynamic> table, List<String> pool, List<Map<String, dynamic>> lib) {
  final out = <String>[];
  if (pool.length < _original33.length || pool.sublist(0, _original33.length).join('|') != _original33.join('|')) {
    out.add('the first 33 names of kV14SafePool are not the original 33');
  }
  final extra = pool.length > _original33.length ? pool.sublist(_original33.length) : <String>[];
  final additions = _strs(table['safe_pool_additions']);
  if (extra.toSet().length != extra.length) out.add('kV14SafePool repeats a name');
  out.addAll(extra.toSet().difference(additions.toSet()).map((n) => '"$n" is in kV14SafePool but not in safe_pool_additions'));
  out.addAll(additions.toSet().difference(extra.toSet()).map((n) => '"$n" is in safe_pool_additions but not in kV14SafePool'));
  final count = <String, int>{};
  for (final r in lib) {
    count.update('${r['name']}'.toLowerCase(), (v) => v + 1, ifAbsent: () => 1);
  }
  for (final n in pool) {
    if (count[n.toLowerCase()] != 1) out.add('kV14SafePool name "$n" matches ${count[n.toLowerCase()] ?? 0} library rows');
  }
  return out;
}

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

  group('library group: the shipped library against the table (added with the importer, commit 5)', () {
    late Map<String, dynamic> src;
    late Map<String, dynamic> table;
    late List<Map<String, dynamic>> lib;
    setUpAll(() {
      src = _readMap(_srcRel);
      table = _readMap(_tableRel);
      lib = (jsonDecode(File(_libRel).readAsStringSync()) as List).cast<Map<String, dynamic>>();
    });
    List<Map<String, dynamic>> l() => (jsonDecode(jsonEncode(lib)) as List).cast<Map<String, dynamic>>();
    Map<String, dynamic> t() => _deep(table);
    Map<String, dynamic> row(List<Map<String, dynamic>> rows, String id) => rows.firstWhere((r) => r['id'] == id);

    test('every table id ships with sorted(raw source tags UNION table row) and the frozen variant_family', () {
      expect(_libTagViolations(src, table, lib), isEmpty);
    });

    test('MUTATION: a floor token deleted from one shipped row, and a changed shipped family, are each red', () {
      final a = l();
      final victim = _libNew(a).firstWhere((r) => _strs(r['injury_contraindications']).isNotEmpty);
      (victim['injury_contraindications'] as List).removeAt(0);
      expect(_libTagViolations(src, table, a), isNotEmpty, reason: 'tag removed');
      final b = l();
      _libNew(b).first['variant_family'] = 'not_the_frozen_family';
      expect(_libTagViolations(src, table, b), isNotEmpty, reason: 'family changed');
    });

    test('the set of shipped new-row ids equals the set of table ids', () {
      expect(_libIdSetViolations(table, lib), isEmpty);
    });

    test('MUTATION: a deleted table row, and a shipped row the builder did not see, are each red', () {
      final a = t();
      _tableRows(a).remove(_tableRows(a).keys.first);
      expect(_libIdSetViolations(a, lib), isNotEmpty, reason: 'table row deleted');
      final b = l();
      b.add({..._libNew(b).first, 'id': 'G9999', 'name': 'Zz Unseen Row'});
      expect(_libIdSetViolations(table, b), isNotEmpty, reason: 'a shipped row with no table row');
    });

    test('every shipped new row carries its floor, family-rule and twin tokens (read from the shipped library)', () {
      expect(_libFloorViolations(lib), isEmpty);
    });

    test('G0845 carries lower_back; G0814 carries E075 tags; G1428 carries E210 tags (read from the shipped rows)', () {
      expect(injuryTagsOf(row(lib, 'G0845')), contains('lower_back'));
      expect(injuryTagsOf(row(lib, 'G0814')), containsAll(injuryTagsOf(row(lib, 'E075'))));
      expect(injuryTagsOf(row(lib, 'G1428')), containsAll(injuryTagsOf(row(lib, 'E210'))));
    });

    test('MUTATION: a floor token removed, G0845 untagged, a twin token dropped and shoulder removed from a push-up row are each red', () {
      final withFloor = _libNew(l()).firstWhere((r) => floorOf(r['variant_family'] as String?, lib).isNotEmpty);
      final a = l();
      final fr = row(a, withFloor['id'] as String);
      final floor = floorOf(fr['variant_family'] as String?, lib).first;
      (fr['injury_contraindications'] as List).remove(floor);
      expect(_libFloorViolations(a), isNotEmpty, reason: 'floor token removed');
      final b = l();
      (row(b, 'G0845')['injury_contraindications'] as List).remove('lower_back');
      expect(_libFloorViolations(b), isNotEmpty, reason: 'G0845 lower_back removed');
      final c = l();
      (row(c, 'G0814')['injury_contraindications'] as List).removeLast();
      expect(_libFloorViolations(c), isNotEmpty, reason: 'twin token dropped');
      final d = l();
      final push = _libNew(d).firstWhere((r) => RegExp(r'push[- ]?up', caseSensitive: false).hasMatch('${r['name']}'));
      (push['injury_contraindications'] as List).remove('shoulder');
      expect(_libFloorViolations(d), isNotEmpty, reason: 'shoulder removed from a push-up-named row');
    });

    test('kV14SafePool is the original 33 plus safe_pool_additions, each name one library row', () {
      expect(_poolViolations(table, kV14SafePool, lib), isEmpty);
    });

    test('MUTATION: a name added to kV14SafePool only, to safe_pool_additions only, and a HELD row name in both are each red', () {
      expect(_poolViolations(table, [...kV14SafePool, 'Zz Pool Only'], lib), isNotEmpty, reason: 'pool only');
      final a = t();
      (a['safe_pool_additions'] as List).add('Zz Additions Only');
      expect(_poolViolations(a, kV14SafePool, lib), isNotEmpty, reason: 'additions only');
      final libNames = lib.map((r) => '${r['name']}'.toLowerCase()).toSet();
      final held = _rowsOf(src).firstWhere((r) => r['hold'] != null && !libNames.contains('${r['name']}'.toLowerCase()))['name'] as String;
      final b = t();
      (b['safe_pool_additions'] as List).add(held);
      expect(_poolViolations(b, [...kV14SafePool, held], lib), isNotEmpty, reason: 'a held row name is no library row');
    });

    test('MUTATION: an importer that skips the tag table ships rows the library group rejects', () {
      final tmp = Directory.systemTemp.createTempSync('lbc_inj_imp_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final text = File('scripts/add_library_batch_c_v15.js').readAsStringSync();
      const needle = '[...rawTags, ...tableRow.tokens]';
      expect(text.contains(needle), isTrue, reason: 'the importer must merge the table tokens on this expression');
      final script = File('${tmp.path}/importer.js')..writeAsStringSync(text.replaceFirst(needle, '[...rawTags]'));
      final out = '${tmp.path}/lib.json';
      File(_libRel).copySync(out);
      final r = runSpawn(
        'node',
        [script.path, '--library', out, '--source', _srcRel, '--table', _tableRel],
        why: 'mutated importer that skips the tag table',
        report: (_) {},
      );
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final built = (jsonDecode(File(out).readAsStringSync()) as List).cast<Map<String, dynamic>>();
      expect(_libTagViolations(src, table, built), isNotEmpty);
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

    // B-pass finding (reviewer A, 2026-10-26): the builder read the sibling pool from the WHOLE library file. That was
    // right at commit 3 (only E rows) and wrong from commit 5 on (the file also holds the shipped G/N rows, and the row
    // being built is one of them), so a from-scratch build or a `--drop` and re-run disagreed with the independent
    // original-rows-only recomputation in test/helpers/library_injury_floor.dart.
    test('a from-scratch build reproduces every non-judgement row of the committed table (siblings are ORIGINAL rows only)', () {
      final fresh = '${tmp.path}/fresh.json'; // absent: the builder builds EVERY shipped row
      final r = _builder(['--table', fresh], 'builder from-scratch build against the committed library');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final built = _tableRows(_readMap(fresh));
      final committed = _tableRows(_readMap(_tableRel));
      final decided = committed.entries.where((e) => (e.value as Map)['class'] != 'judgement').toList();
      expect(decided.length, greaterThan(500), reason: 'the comparison must cover the floor, majority, family and twin rows');
      final diffs = <String>[];
      var droppedRows = 0;
      for (final e in decided) {
        final b = built[e.key] as Map<String, dynamic>?;
        final c = e.value as Map<String, dynamic>;
        if (b == null) {
          diffs.add('${e.key}: not built');
        } else if ('${c['reason']}'.contains(' dropped (')) {
          // A founder-dropped majority token: the committed reason is the built reason plus the recorded drop, and the
          // committed tokens are the built tokens minus the dropped one.
          droppedRows++;
          final tokensOk = _strs(c['tokens']).every(_strs(b['tokens']).contains) && _strs(c['tokens']).length < _strs(b['tokens']).length;
          if (!'${c['reason']}'.startsWith('${b['reason']}; ') || !tokensOk || c['class'] != b['class']) {
            diffs.add('${e.key}: built ${jsonEncode(b)} vs committed ${jsonEncode(c)}');
          }
        } else if (jsonEncode(b) != jsonEncode(c)) {
          diffs.add('${e.key}: built ${jsonEncode(b)} vs committed ${jsonEncode(c)}');
        }
      }
      expect(droppedRows, greaterThan(0), reason: 'the founder-drop branch must be exercised');
      expect(diffs, isEmpty, reason: '${diffs.length} rows differ, first: ${diffs.take(3).join(' | ')}');
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
