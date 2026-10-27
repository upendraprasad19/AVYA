// Batch C1 (docs/plans/2026-10-25-library-batch-c-new-rows.md, Task 4.2): the NEW rows in assets/data/exercise_library.json.
//
// The final library is built ONLY by scripts/add_library_batch_c_v15.js from scripts/data/library_batch_c_source.json and
// the injury table scripts/data/library_injury_additions_v15.json; its `--check` mode is byte equality with the shipped
// file, so a direct JSON edit goes red here. The rest of this file is the contract on the rows themselves: shape, text,
// names, holds, aliases, types, and the E274 relabel.
//
// Every check is a pure function over in-memory maps, so each one is mutated below and must go red. The importer's own
// behaviour (drop-set, held skip, alias mapping) is mutated through temp copies of the data and the --library / --source /
// --table flags.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';

import '../helpers/spawn.dart';

const _libRel = 'assets/data/exercise_library.json';
const _srcRel = 'scripts/data/library_batch_c_source.json';
const _tableRel = 'scripts/data/library_injury_additions_v15.json';
const _mediaTableRel = 'scripts/data/library_media_v16.json';
const _importerRel = 'scripts/add_library_batch_c_v15.js';

/// E001's 43 keys minus demo_slug, demo_pair and variant_family: carried by every library row, in this order.
const _required40 = <String>[
  'id', 'name', 'category', 'movement_pattern', 'exercise_type', 'primary_muscles', 'secondary_muscles',
  'equipment_needed', 'logging_type', 'difficulty_level', 'suitable_for', 'default_sets', 'default_reps',
  'default_rest_secs', 'tempo', 'met_value', 'cal_per_set_est', 'breathing_cue', 'coaching_cues', 'common_mistakes',
  'warmup_protocol', 'pro_tip', 'is_indian_context', 'indian_alternative', 'source', 'is_active', 'is_foundational',
  'injury_contraindications', 'is_bilateral', 'cns_demand', 'target_focus', 'equipment_tier', 'standard_swap',
  'priority_tier', 'rep_range', 'core_levels', 'discipline', 'gym_availability', 'requires_coaching', 'high_impact',
];
const _optionalKeys = <String>{'variant_family', 'skill_track', 'skill_step', 'progression_to', 'regression_to'};
// Plate keys stay forbidden on new rows. The media keys (Batch M1) are allowed ONLY on ids the committed media table maps,
// as a group, last and in this order.
const _plateKeys = <String>{'demo_slug', 'demo_pair'};
const _mediaKeyList = <String>['media_slug', 'media_version', 'media_source'];
const _newId = r'^[GN]\d';

Set<String> _mappedIds() => ((_readMap(_mediaTableRel)['rows'] as Map<String, dynamic>).keys).toSet();
Map<String, dynamic> _readMap(String p) => jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;
List<Map<String, dynamic>> _readLib(String p) => (jsonDecode(File(p).readAsStringSync()) as List).cast<Map<String, dynamic>>();
List<Map<String, dynamic>> _srcRows(Map<String, dynamic> src) => (src['rows'] as List).cast<Map<String, dynamic>>();
List<Map<String, dynamic>> _newRows(List<Map<String, dynamic>> lib) =>
    lib.where((r) => RegExp(_newId).hasMatch(r['id'] as String)).toList();
List<String> _strs(Object? v) => (v as List? ?? const []).map((e) => e.toString()).toList();
T _deep<T>(T v) => jsonDecode(jsonEncode(v)) as T;
List<Map<String, dynamic>> _deepRows(List<Map<String, dynamic>> v) =>
    (jsonDecode(jsonEncode(v)) as List).cast<Map<String, dynamic>>();
Map<String, dynamic> _byId(List<Map<String, dynamic>> rows, String id) => rows.firstWhere((r) => r['id'] == id);

List<String> _keyViolations(List<Map<String, dynamic>> rows, {Set<String>? mapped}) {
  final mappedIds = mapped ?? _mappedIds();
  final out = <String>[];
  for (final r in rows) {
    final id = r['id'];
    for (final k in _required40) {
      if (!r.containsKey(k)) out.add('$id is missing required key $k');
    }
    if (!r.containsKey('variant_family')) out.add('$id has no variant_family');
    for (final k in r.keys) {
      if (_plateKeys.contains(k)) {
        out.add('$id carries plate key $k (plates are not shipped on new rows)');
      } else if (_mediaKeyList.contains(k)) {
        // checked below, as a group
      } else if (!_required40.contains(k) && !_optionalKeys.contains(k)) {
        out.add('$id carries extra key $k');
      }
      if (_optionalKeys.contains(k) && r[k] == null) out.add('$id carries a null $k (omit the key)');
    }
    final keys = r.keys.toList();
    final hasAny = _mediaKeyList.any(r.containsKey);
    if (hasAny && !mappedIds.contains(id)) out.add('$id carries a media key but the media table does not map it');
    if (hasAny) {
      final tail = keys.length >= 3 ? keys.sublist(keys.length - 3) : keys;
      if (tail.join(',') != _mediaKeyList.join(',')) out.add('$id: the media keys must be the last three keys, in order (found ${keys.join(',')})');
    }
  }
  return out;
}

List<String> _floatViolations(List<Map<String, dynamic>> rows) => [
      for (final r in rows)
        for (final k in ['met_value', 'cal_per_set_est'])
          if (r[k] is! double) '${r['id']} $k is ${r[k].runtimeType}, not a double (write 4.0, not 4)',
    ];

List<String> _tokenViolations(List<Map<String, dynamic>> rows) => [
      for (final r in rows)
        for (final t in _strs(r['equipment_needed']))
          if (!EquipmentVocab.canonicalTokens.contains(t)) '${r['id']} equipment token "$t" is not canonical',
    ];

void _walk(Object? v, void Function(String) onString) {
  if (v is String) {
    onString(v);
  } else if (v is List) {
    for (final e in v) {
      _walk(e, onString);
    }
  } else if (v is Map) {
    v.forEach((k, e) {
      onString(k as String);
      _walk(e, onString);
    });
  }
}

List<String> _asciiViolations(List<Map<String, dynamic>> rows) {
  final out = <String>[];
  for (final r in rows) {
    _walk(r, (s) {
      if (s.codeUnits.any((c) => c > 126 || (c < 32 && c != 10))) out.add('${r['id']} has non-ASCII text: $s');
    });
  }
  return out;
}

/// R10: non-empty lists, one cue per item, no ';', no TODO / TBD / '?' / '...', every cue item 3 to 100 characters.
List<String> _textViolations(List<Map<String, dynamic>> rows) {
  final out = <String>[];
  final banned = RegExp(r'TODO|TBD|\?|\.\.\.');
  for (final r in rows) {
    final id = r['id'];
    for (final k in ['coaching_cues', 'common_mistakes']) {
      final items = _strs(r[k]);
      if (items.isEmpty) out.add('$id $k is empty');
      for (final s in items) {
        if (s.contains(';')) out.add('$id $k item has a semicolon: $s');
        if (banned.hasMatch(s)) out.add('$id $k item has a placeholder or question mark: $s');
        if (s.trim().isEmpty) out.add('$id $k has a blank item');
      }
    }
    for (final s in _strs(r['coaching_cues'])) {
      if (s.length < 3 || s.length > 100) out.add('$id coaching cue is ${s.length} characters (3 to 100): $s');
    }
  }
  return out;
}

List<String> _nameViolations(List<Map<String, dynamic>> lib) {
  final seen = <String, String>{};
  final out = <String>[];
  for (final r in lib) {
    final n = (r['name'] as String).toLowerCase();
    final prior = seen[n];
    if (prior != null) out.add('${r['id']} repeats the name of $prior: ${r['name']}');
    seen[n] = r['id'] as String;
  }
  return out;
}

/// No source id carrying `hold` is shipped, every other source id is, and the count equals source minus held.
List<String> _heldViolations(Map<String, dynamic> src, List<Map<String, dynamic>> lib) {
  final ids = lib.map((r) => r['id'] as String).toSet();
  final out = <String>[];
  var held = 0;
  for (final r in _srcRows(src)) {
    final id = r['id'] as String;
    if (r['hold'] != null) {
      held++;
      if (ids.contains(id)) out.add('$id is HELD in the source but shipped');
    } else if (!ids.contains(id)) {
      out.add('$id is not held in the source but missing from the library');
    }
  }
  final shipped = _newRows(lib).length;
  final want = _srcRows(src).length - held;
  if (shipped != want) out.add('shipped new rows $shipped, source minus held is $want');
  final srcIds = _srcRows(src).map((r) => r['id']).toSet();
  for (final r in _newRows(lib)) {
    if (!srcIds.contains(r['id'])) out.add('${r['id']} is a new-looking id that is not in the source');
  }
  return out;
}

bool _edited(Map<String, dynamic> meta, String id) {
  for (final k in ['picture_checked', 'identity_checked']) {
    final e = (meta[k] as Map)[id];
    if (e is Map && e['action'] == 'edited') return true;
  }
  return false;
}

/// R3: a non-held aliased row that no record marks `edited` ships `EquipmentVocab.normalize(original tokens)`.
List<String> _aliasViolations(Map<String, dynamic> src, List<Map<String, dynamic>> lib) {
  final meta = src['_meta'] as Map<String, dynamic>;
  final srcById = {for (final r in _srcRows(src)) r['id'] as String: r};
  final libById = {for (final r in lib) r['id'] as String: r};
  final out = <String>[];
  for (final e in (meta['alias_applied'] as Map<String, dynamic>).entries) {
    final id = e.key;
    if (srcById[id]?['hold'] != null || _edited(meta, id)) continue;
    final row = libById[id];
    if (row == null) {
      out.add('$id is aliased and not held but not shipped');
      continue;
    }
    final want = EquipmentVocab.normalize(_strs(e.value));
    if (_strs(row['equipment_needed']).join('|') != want.join('|')) {
      out.add('$id ships ${row['equipment_needed']} but its original tokens ${e.value} normalise to $want');
    }
  }
  return out;
}

List<String> _typeViolations(List<Map<String, dynamic>> rows) => [
      for (final r in rows)
        if (_strs(r['exercise_type']).contains('isolation') && _strs(r['exercise_type']).contains('compound'))
          '${r['id']} is typed both isolation and compound',
    ];

List<String> _coreSuitableViolations(List<Map<String, dynamic>> rows) {
  final out = <String>[];
  for (final r in rows) {
    final suitable = _strs(r['suitable_for']).map((s) => s.toLowerCase()).toSet();
    for (final l in _strs(r['core_levels'])) {
      if (!suitable.contains(l.toLowerCase())) out.add('${r['id']} is core at $l but suitable_for is ${r['suitable_for']}');
    }
  }
  return out;
}

List<String> _tierViolations(List<Map<String, dynamic>> rows) => [
      for (final r in rows)
        if (const {'calisthenics_skill', 'olympic', 'plyometric'}.contains(r['discipline']) && r['priority_tier'] != 3)
          '${r['id']} is ${r['discipline']} at priority_tier ${r['priority_tier']}, not 3',
    ];

List<String> _coreCountViolations(Map<String, dynamic> src, List<Map<String, dynamic>> rows) {
  final want = (((src['_meta'] as Map)['derived'] as Map)['core'] as Map).cast<String, dynamic>();
  final out = <String>[];
  var coreRows = 0;
  for (final l in ['beginner', 'intermediate', 'advanced']) {
    final n = rows.where((r) => _strs(r['core_levels']).contains(l)).length;
    if (n != want[l]) out.add('core $l: shipped $n, source _meta says ${want[l]}');
  }
  coreRows = rows.where((r) => _strs(r['core_levels']).isNotEmpty).length;
  if (coreRows != want['rows']) out.add('core rows: shipped $coreRows, source _meta says ${want['rows']}');
  return out;
}

List<String> _e274Violations(List<Map<String, dynamic>> lib) {
  final tf = _strs(_byId(lib, 'E274')['target_focus']);
  return tf.join('|') == 'Mid Back' ? const [] : ['E274 target_focus is $tf, want [Mid Back]'];
}

/// Every non-null ladder link of a new row names exactly one row of the final library.
List<String> _linkViolations(List<Map<String, dynamic>> lib) {
  final count = <String, int>{};
  for (final r in lib) {
    count[r['name'] as String] = (count[r['name'] as String] ?? 0) + 1;
  }
  return [
    for (final r in _newRows(lib))
      for (final k in ['progression_to', 'regression_to'])
        if (r[k] != null && count[r[k]] != 1) '${r['id']}.$k = ${r[k]} resolves to ${count[r[k]] ?? 0} rows',
  ];
}

class _Temp {
  _Temp() : dir = Directory.systemTemp.createTempSync('lbc_rows_');
  final Directory dir;
  String put(String name, String text) {
    final f = File('${dir.path}/$name')..writeAsStringSync(text);
    return f.path;
  }

  void dispose() => dir.deleteSync(recursive: true);
}

ProcessResult _importer(List<String> args, String why, {String script = _importerRel}) =>
    runSpawn('node', [script, ...args], why: why, report: (_) {});

// B-pass (reviewer A, 2026-10-26): three field-agreement checks the review found broken on shipped rows.
//   difficulty_level: the library vocabulary is beginner / intermediate / advanced (getFormCues.ts documents exactly those
//     three); seven new rows shipped "elite".
//   is_bilateral: a single-arm / single-leg / one-arm / one-leg row is false on every other new row; G0725 shipped true.
//   same machine: two rows whose pictures show the SAME machine must agree on the equipment; G1432 shipped a pull-up bar and
//     a box while G1431 (read at triage) correctly shipped the weight-stack assist machine.
const _difficultyVocab = {'beginner', 'intermediate', 'advanced'};
final _singleLimbName = RegExp(r'single[- ](arm|leg)|one[- ](arm|leg)', caseSensitive: false);
const _sameMachinePairs = <(String, String)>[('G1431', 'G1432')];

List<String> _difficultyViolations(List<Map<String, dynamic>> lib) => [
      for (final r in lib)
        if (!_difficultyVocab.contains(r['difficulty_level'])) '${r['id']} ${r['name']} has difficulty_level ${r['difficulty_level']}',
    ];

List<String> _singleLimbViolations(List<Map<String, dynamic>> rows) => [
      for (final r in rows)
        if (_singleLimbName.hasMatch('${r['name']}') && r['is_bilateral'] != false) '${r['id']} ${r['name']} is_bilateral ${r['is_bilateral']}',
    ];

List<String> _sameMachineViolations(List<Map<String, dynamic>> lib) {
  final out = <String>[];
  for (final (a, b) in _sameMachinePairs) {
    final x = _byId(lib, a);
    final y = _byId(lib, b);
    for (final k in ['equipment_needed', 'equipment_tier']) {
      if (jsonEncode(x[k]) != jsonEncode(y[k])) out.add('$a $k ${jsonEncode(x[k])} vs $b ${jsonEncode(y[k])}');
    }
  }
  return out;
}

void main() {
  late List<Map<String, dynamic>> lib;
  late List<Map<String, dynamic>> rows;
  late Map<String, dynamic> src;

  setUpAll(() {
    lib = _readLib(_libRel);
    rows = _newRows(lib);
    src = _readMap(_srcRel);
  });

  group('the shipped new rows: each check passes on the real library and goes red on its mutation', () {
    test('there are new rows at all (the library is not still the 285-row base)', () {
      expect(rows, isNotEmpty, reason: 'run: node scripts/add_library_batch_c_v15.js');
    });

    test('40 required keys plus only the optional ones present; media keys only on mapped rows, last and in order', () {
      expect(_keyViolations(rows), isEmpty);
    });

    test('MUTATION: a dropped required key, an extra key, a media key and a null ladder key are each a violation', () {
      final a = _deepRows(rows)..first.remove('tempo');
      expect(_keyViolations(a), isNotEmpty, reason: 'drop a required key');
      final b = _deepRows(rows)..first['_coreAdded'] = true;
      expect(_keyViolations(b), isNotEmpty, reason: 'an extra key (a _coreAdded on a row)');
      final c = _deepRows(rows)..first['demo_slug'] = 'x';
      expect(_keyViolations(c), isNotEmpty, reason: 'a demo_slug on a shipped row');
      final mapped = _mappedIds();
      final unmapped = rows.firstWhere((r) => !mapped.contains(r['id']));
      final f = _deepRows(rows);
      _byId(f, unmapped['id'] as String)..['media_slug'] = '0001-x'..['media_version'] = 1..['media_source'] = 'wardroom';
      expect(_keyViolations(f), isNotEmpty, reason: 'media keys on an unmapped row');
      final onMapped = rows.firstWhere((r) => mapped.contains(r['id']));
      final g = _deepRows(rows);
      final victim = _byId(g, onMapped['id'] as String);
      final slug = victim.remove('media_slug');
      victim['media_slug'] = slug; // moved to the end: order is now version, source, slug
      expect(_keyViolations(g), isNotEmpty, reason: 'the media keys out of order');
      final h = _deepRows(rows);
      _byId(h, onMapped['id'] as String)['extra_after'] = 1;
      expect(_keyViolations(h), isNotEmpty, reason: 'a key after the media keys (and an extra key)');
      final d = _deepRows(rows)..first['progression_to'] = null;
      expect(_keyViolations(d), isNotEmpty, reason: 'a null ladder key');
      final e = _deepRows(rows)..first.remove('variant_family');
      expect(_keyViolations(e), isNotEmpty, reason: 'no variant_family');
    });

    test('met_value and cal_per_set_est are doubles (Dart keeps 4.0 typed, 4 becomes an int)', () {
      expect(_floatViolations(rows), isEmpty);
    });

    test('MUTATION: an int met_value and an int cal_per_set_est are each a violation', () {
      final a = _deepRows(rows)..first['met_value'] = 4;
      expect(_floatViolations(a), isNotEmpty);
      final b = _deepRows(rows)..first['cal_per_set_est'] = 4;
      expect(_floatViolations(b), isNotEmpty);
    });

    test('equipment tokens are canonical', () {
      expect(_tokenViolations(rows), isEmpty);
    });

    test('MUTATION: a raw token is a violation', () {
      final a = _deepRows(rows)..first['equipment_needed'] = ['weight plate'];
      expect(_tokenViolations(a), isNotEmpty);
    });

    test('new rows are ASCII', () {
      expect(_asciiViolations(rows), isEmpty);
    });

    test('MUTATION: a non-ASCII character in a cue is a violation', () {
      final a = _deepRows(rows);
      (a.first['coaching_cues'] as List)[0] = 'Press ${String.fromCharCode(0xe9)}';
      expect(_asciiViolations(a), isNotEmpty);
    });

    test('R10 text: non-empty lists, no placeholders, no semicolon, cue items 3 to 100 characters', () {
      expect(_textViolations(rows), isEmpty);
    });

    test('MUTATION: an empty list, each placeholder, a 2-character item and a 120-character item are each a violation', () {
      Map<String, dynamic> first(List<Map<String, dynamic>> r) => r.first;
      final empty = _deepRows(rows);
      first(empty)['coaching_cues'] = <String>[];
      expect(_textViolations(empty), isNotEmpty, reason: 'empty cue list');
      for (final bad in ['TODO fix', 'TBD', 'Is this right?', 'Wait for it...']) {
        final m = _deepRows(rows);
        (first(m)['coaching_cues'] as List)[0] = bad;
        expect(_textViolations(m), isNotEmpty, reason: 'cue "$bad"');
      }
      final two = _deepRows(rows);
      (first(two)['coaching_cues'] as List)[0] = 'Up';
      expect(_textViolations(two), isNotEmpty, reason: '2-character item');
      final long = _deepRows(rows);
      (first(long)['coaching_cues'] as List)[0] = List.filled(120, 'a').join();
      expect(_textViolations(long), isNotEmpty, reason: '120-character item');
      final semi = _deepRows(rows);
      (first(semi)['common_mistakes'] as List)[0] = 'one; two';
      expect(_textViolations(semi), isNotEmpty, reason: 'semicolon');
    });

    test('names are unique case-insensitively across the final library', () {
      expect(_nameViolations(lib), isEmpty);
    });

    test('MUTATION: a duplicate name is a violation', () {
      final a = _deepRows(lib);
      a.last['name'] = (a.first['name'] as String).toUpperCase();
      expect(_nameViolations(a), isNotEmpty);
    });

    test('no held source row is shipped, every other source row is, and the count is source minus held', () {
      expect(_heldViolations(src, lib), isEmpty);
    });

    test('MUTATION: shipping a held row, losing a shipped row, and a count off by one are each a violation', () {
      final held = _srcRows(src).firstWhere((r) => r['hold'] != null);
      final a = _deepRows(lib)..add({..._deep(rows.first), 'id': held['id']});
      expect(_heldViolations(src, a), isNotEmpty, reason: 'a held row shipped');
      final b = _deepRows(lib)..removeWhere((r) => r['id'] == rows.first['id']);
      expect(_heldViolations(src, b), isNotEmpty, reason: 'a shipped row lost');
      final c = _deepRows(lib)..add({..._deep(rows.first), 'id': 'G9999'});
      expect(_heldViolations(src, c), isNotEmpty, reason: 'an id outside the source');
    });

    test('an aliased row that no record marks edited ships the vocabulary mapping of its original tokens', () {
      expect(_aliasViolations(src, lib), isEmpty);
      final meta = src['_meta'] as Map<String, dynamic>;
      final checked = (meta['alias_applied'] as Map).keys.where((id) {
        final r = _srcRows(src).firstWhere((x) => x['id'] == id);
        return r['hold'] == null && !_edited(meta, id as String);
      });
      expect(checked, isNotEmpty, reason: 'the alias check must have rows to look at');
    });

    test('MUTATION: landmine mapped to machines for one aliased row is a violation', () {
      final meta = src['_meta'] as Map<String, dynamic>;
      final id = (meta['alias_applied'] as Map).keys.cast<String>().firstWhere((id) {
        final r = _srcRows(src).firstWhere((x) => x['id'] == id);
        return r['hold'] == null && !_edited(meta, id);
      });
      final a = _deepRows(lib);
      _byId(a, id)['equipment_needed'] = ['machines'];
      expect(_aliasViolations(src, a), isNotEmpty);
    });

    test('no new row is typed both isolation and compound', () {
      expect(_typeViolations(rows), isEmpty);
    });

    test('MUTATION: G0845 typed back to both is a violation', () {
      final a = _deepRows(rows);
      _byId(a, 'G0845')['exercise_type'] = ['isolation', 'compound'];
      expect(_typeViolations(a), isNotEmpty);
    });

    test('every core level of a new row is in its suitable_for', () {
      expect(_coreSuitableViolations(rows), isEmpty);
    });

    test('MUTATION: Beginner dropped from G0757 is a violation', () {
      final a = _deepRows(rows);
      final r = _byId(a, 'G0757');
      (r['suitable_for'] as List).remove('Beginner');
      expect(_coreSuitableViolations(a), isNotEmpty);
    });

    test('every new skill, olympic or plyometric row is priority_tier 3', () {
      expect(_tierViolations(rows), isEmpty);
    });

    test('MUTATION: a plyometric row at tier 2 is a violation', () {
      final a = _deepRows(rows);
      final r = a.firstWhere((x) => x['discipline'] == 'plyometric');
      r['priority_tier'] = 2;
      expect(_tierViolations(a), isNotEmpty);
    });

    test('per-level core counts of the new rows equal the source _meta', () {
      expect(_coreCountViolations(src, rows), isEmpty);
    });

    test('MUTATION: a source count off by one and a lost core level are each a violation', () {
      final s = _deep(src);
      (((s['_meta'] as Map)['derived'] as Map)['core'] as Map)['beginner'] = 57;
      expect(_coreCountViolations(s, rows), isNotEmpty);
      final a = _deepRows(rows);
      a.firstWhere((x) => _strs(x['core_levels']).isNotEmpty)['core_levels'] = <String>[];
      expect(_coreCountViolations(src, a), isNotEmpty);
    });

    test('every ladder link of a new row names exactly one row', () {
      expect(_linkViolations(lib), isEmpty);
    });

    test('MUTATION: a dangling link and an ambiguous link are each a violation', () {
      final a = _deepRows(lib);
      final r = _newRows(a).firstWhere((x) => x['progression_to'] != null);
      r['progression_to'] = 'No Such Exercise';
      expect(_linkViolations(a), isNotEmpty, reason: 'dangling');
      final b = _deepRows(lib);
      final target = _newRows(b).firstWhere((x) => x['progression_to'] != null)['progression_to'];
      b.add({..._deep(b.first), 'id': 'G9998', 'name': target});
      expect(_linkViolations(b), isNotEmpty, reason: 'two rows share the target name');
    });

    test('E274 target_focus is Mid Back (the only kept-row edit of Batch C1)', () {
      expect(_e274Violations(lib), isEmpty);
    });

    test('MUTATION: E274 set back to Upper Back is a violation', () {
      final a = _deepRows(lib);
      _byId(a, 'E274')['target_focus'] = ['Upper Back'];
      expect(_e274Violations(a), isNotEmpty);
    });

    test('difficulty_level is beginner, intermediate or advanced on every library row', () {
      expect(_difficultyViolations(lib), isEmpty);
    });

    test('MUTATION: "elite" on one new row is a violation', () {
      final a = _deepRows(lib);
      _newRows(a).first['difficulty_level'] = 'elite';
      expect(_difficultyViolations(a), isNotEmpty);
    });

    test('a single-arm, single-leg, one-arm or one-leg new row is not bilateral', () {
      expect(_singleLimbViolations(rows), isEmpty);
      expect(rows.where((r) => _singleLimbName.hasMatch('${r['name']}')).length, greaterThan(60), reason: 'the check must cover the single-limb rows');
    });

    test('MUTATION: G0725 Single Arm Push Up back to bilateral is a violation', () {
      final a = _deepRows(lib);
      _byId(a, 'G0725')['is_bilateral'] = true;
      expect(_singleLimbViolations(_newRows(a)), isNotEmpty);
    });

    test('rows that show the same machine agree on equipment and tier (G1431 and G1432, the weight-stack assist machine)', () {
      expect(_sameMachineViolations(lib), isEmpty);
      expect(_byId(lib, 'G1432')['equipment_needed'], ['machines']);
      expect(_byId(lib, 'G1432')['equipment_tier'], ['full_gym']);
    });

    test('MUTATION: G1432 back to a pull-up bar and a box is a violation', () {
      final a = _deepRows(lib);
      _byId(a, 'G1432')['equipment_needed'] = ['pull-up bar', 'elevated surface'];
      expect(_sameMachineViolations(a), isNotEmpty);
    });
  });

  group('the importer: the shipped file is its byte-exact output, and its rules hold when the inputs change', () {
    test('--check: the shipped JSON equals a fresh import, byte for byte', () {
      final r = _importer(['--check'], 'importer --check against the shipped library');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    });

    test('MUTATION: one cue edited directly in the JSON makes --check red', () {
      // Edit the RAW text so the formatter round-trip still passes and only the content differs.
      final t = _Temp();
      addTearDown(t.dispose);
      final text = File(_libRel).readAsStringSync();
      final cue = (rows.first['coaching_cues'] as List).first as String;
      final mutated = text.replaceFirst(jsonEncode(cue), jsonEncode('$cue by hand'));
      expect(mutated, isNot(text), reason: 'the mutation must apply');
      final p = t.put('lib.json', mutated);
      expect(_importer(['--check', '--library', p], 'importer --check on a hand-edited library').exitCode, isNot(0));
    });

    test('MUTATION: a tag list emptied directly in the JSON makes --check red', () {
      final t = _Temp();
      addTearDown(t.dispose);
      final text = File(_libRel).readAsStringSync();
      final victim = rows.firstWhere((x) => _strs(x['injury_contraindications']).isNotEmpty);
      final at = text.indexOf('"id": "${victim['id']}"');
      expect(at, greaterThan(0));
      final tail = text.substring(at).replaceFirst(RegExp(r'"injury_contraindications": \[[^\]]*\]'), '"injury_contraindications": []');
      final mutated = text.substring(0, at) + tail;
      expect(mutated, isNot(text), reason: 'the mutation must apply');
      final p = t.put('lib.json', mutated);
      expect(_importer(['--check', '--library', p], 'importer --check on a library missing a tag').exitCode, isNot(0));
    });

    test('importing twice is byte-identical (the second run changes nothing)', () {
      final t = _Temp();
      addTearDown(t.dispose);
      final p = t.put('lib.json', File(_libRel).readAsStringSync());
      final first = _importer(['--library', p], 'importer second run over the shipped library');
      expect(first.exitCode, 0, reason: '${first.stdout}${first.stderr}');
      expect(File(p).readAsStringSync(), File(_libRel).readAsStringSync());
    });

    test('MUTATION: a shipped row held in the source leaves the library on the next run (the drop-set is every source id)', () {
      final t = _Temp();
      addTearDown(t.dispose);
      final s = _deep(src);
      final victim = _srcRows(s).firstWhere((r) => r['hold'] == null);
      victim['hold'] = {'class': 'picture', 'reason': 'test', 'owner': 'founder'};
      final sp = t.put('src.json', jsonEncode(s));
      final lp = t.put('lib.json', File(_libRel).readAsStringSync());
      final r = _importer(['--library', lp, '--source', sp, '--media', 'none'], 'importer run with a newly held row');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final out = _readLib(lp);
      expect(out.where((x) => x['id'] == victim['id']), isEmpty);
      expect(_heldViolations(s, out), isEmpty);
    });

    test('MUTATION: landmine mapped to machines for one shipped aliased row in the source goes red in the alias check', () {
      final t = _Temp();
      addTearDown(t.dispose);
      final s = _deep(src);
      final meta = s['_meta'] as Map<String, dynamic>;
      final id = (meta['alias_applied'] as Map).keys.cast<String>().firstWhere((id) {
        final r = _srcRows(s).firstWhere((x) => x['id'] == id);
        return r['hold'] == null && !_edited(meta, id);
      });
      _srcRows(s).firstWhere((x) => x['id'] == id)['equipment_needed'] = ['machines'];
      final sp = t.put('src.json', jsonEncode(s));
      final lp = t.put('lib.json', File(_libRel).readAsStringSync());
      final r = _importer(['--library', lp, '--source', sp], 'importer run with a changed alias target');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(_aliasViolations(s, _readLib(lp)), isNotEmpty);
    });

    test('MUTATION: an importer that ships held rows is caught by the held-row check', () {
      final t = _Temp();
      addTearDown(t.dispose);
      final text = File(_importerRel).readAsStringSync();
      const marker = '/*HELD-SKIP*/';
      expect(text.contains(marker), isTrue, reason: 'the importer must carry the $marker marker on its held-skip line');
      final mutated = text.replaceFirst(RegExp(r'/\*HELD-SKIP\*/[^\n]*'), '/*HELD-SKIP*/ const shipped = rows;');
      expect(mutated, isNot(text), reason: 'the mutation must apply');
      // A source of the NON-held rows plus ONE newly held clean row (the 79 real holds carry raw tokens and no table row,
      // so a mutated importer would throw on them and the test would pass for the wrong reason).
      final s = _deep(src);
      final clean = _srcRows(s).where((r) => r['hold'] == null).toList();
      clean.first['hold'] = {'class': 'picture', 'reason': 'test', 'owner': 'founder'};
      s['rows'] = clean;
      final script = t.put('importer.js', mutated);
      final sp = t.put('src.json', jsonEncode(s));
      final tp = t.put('table.json', File(_tableRel).readAsStringSync());

      final control = t.put('lib_control.json', File(_libRel).readAsStringSync());
      final c = _importer(['--library', control, '--source', sp, '--table', tp, '--media', 'none'], 'unmutated importer, one newly held row');
      expect(c.exitCode, 0, reason: '${c.stdout}${c.stderr}');
      expect(_heldViolations(s, _readLib(control)), isEmpty, reason: 'the unmutated importer drops the held row');

      final lp = t.put('lib.json', File(_libRel).readAsStringSync());
      final r = _importer(['--library', lp, '--source', sp, '--table', tp, '--media', 'none'], 'mutated importer shipping held rows', script: script);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(_heldViolations(s, _readLib(lp)), isNotEmpty, reason: 'the held-row check must redden when the importer ships a held row');
    });

    test('a shipped row with no injury-table row stops the importer (the injury gate cannot be skipped)', () {
      final t = _Temp();
      addTearDown(t.dispose);
      final tbl = _readMap(_tableRel);
      final rowsMap = tbl['rows'] as Map<String, dynamic>;
      rowsMap.remove(rowsMap.keys.first);
      final tp = t.put('table.json', jsonEncode(tbl));
      final lp = t.put('lib.json', File(_libRel).readAsStringSync());
      expect(_importer(['--library', lp, '--table', tp], 'importer with a table row missing').exitCode, isNot(0));
    });
  });
}
