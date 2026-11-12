// Library Batch S1a (plan docs/plans/2026-11-08-library-batch-s1-core-data.md, Table A): core_levels for the core-list
// pool (then behind enable_core_list_pool; the only picker since Unit 1B-F), founder-approved 2026-11-08.
//
// Kept (E) rows change through scripts/data/library_s1_core_levels.json, applied by the core-levels stage of
// scripts/add_library_batch_c_v15.js; source (G, N) rows change in scripts/data/library_batch_c_source.json. The
// "before" state is the committed fixture test/fixtures/library_core_levels_before_s1a.json (CI checks out shallow, so
// no test here reads git history).
//
// Pins: every Table A id ships its value; nothing else moved; every core level lies inside suitable_for except the two
// named exceptions, and each exception still disagrees (so fixing one forces this map to shrink).
//
// Run: flutter test test/contracts/library_s1_core_levels_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

typedef Json = Map<String, dynamic>;

const _libraryPath = 'assets/data/exercise_library.json';
const _recordPath = 'scripts/data/library_s1_core_levels.json';
const _sourcePath = 'scripts/data/library_batch_c_source.json';
const _fixturePath = 'test/fixtures/library_core_levels_before_s1a.json';

const _b = 'beginner', _i = 'intermediate', _a = 'advanced';

/// Table A of the plan, restated here (never read from the record, so a wrong record cannot agree with itself).
const _tableA = <String, List<String>>{
  // R1: Quads compound (dumbbells and bodyweight) at advanced.
  // E038 Goblet Squat left Table A in Library Batch S1b-1 (founder 2026-11-09: off the advanced gym Quads pools); it is
  // back at its fixture value, which 'no fixture row outside Table A changed' enforces.
  'G0413': [_b, _i, _a], 'G0336': [_b, _i, _a], 'G0381': [_b, _i, _a],
  'E044': [_b, _i, _a], 'E042': [_b, _i, _a], 'E143': [_a], 'G1476': [_a], 'G0411': [_a],
  // R1: Hamstrings hinge and curl above beginner; Nordic Curl advanced.
  'N11': [_b, _i, _a], 'E253': [_b, _i, _a], 'E292': [_b, _i, _a], 'N08': [_i, _a], 'E046': [_a],
  // R1: Calves above beginner; Single Leg Glute Bridge advanced.
  'G1373': [_b, _i, _a], 'G1387': [_i, _a], 'G1490': [_i, _a], 'E291': [_b, _i, _a],
  // R7 (b): Biceps, Lateral Delts, Rear Delts at intermediate and advanced.
  'E268': [_b, _i, _a], 'E269': [_b, _i, _a], 'E282': [_b, _i, _a], 'E273': [_b, _i, _a], 'E289': [_b, _i, _a],
  'E276': [_b, _i, _a], 'E274': [_b, _i, _a], 'E277': [_b, _i, _a],
  // Advanced Hip and Glutes isolation.
  'G3667': [_b, _i, _a], 'E257': [_b, _i, _a],
  // Library Batch S1b-1 (founder 2026-11-09, gym users get gym kit in the Hip slot, every level): the machine for
  // full_gym (was [_a] in S1a) and a cables row for basic_gym, which has no machines.
  'E107': [_b, _i, _a], 'G0168': [_b, _i, _a],
  // ...and E109 Glute Kickback (Cable) at beginner, so a gym beginner Glutes isolation slot reduces to it (both S1b-1
  // reviewers: otherwise E107 took that slot on the id tie with E257).
  'E109': [_b, _i, _a],
  // A dumbbell curl for equipped users in the Hamstrings curl slot (review #2).
  'G0339': [_i, _a],
  // A second loaded lateral raise, so a day's second Lateral Delts slot keeps a dumbbell row once E013 is taken
  // (the improvised filter then removes the towel move; measured 2026-11-08, 5-day home_dumbbells).
  'G0355': [_i, _a],
  // Level agreement.
  'E020': [_i], 'E134': [_a], 'E255': [],
};

/// Rows whose core_levels stay outside suitable_for on purpose. Empty since Library Batch S1b-2: the founder widened
/// E010 Pike Push Up (Advanced) and E045 Romanian Deadlift (Beginner) instead (2026-11-09, board d12;
/// scripts/data/library_s1b2_suitable_for.json). A future exception goes here with its reason.
const _namedExceptions = <String, String>{};

Json _json(String path) => jsonDecode(File(path).readAsStringSync()) as Json;
List<String> _strs(Object? v) => v is List ? v.map((e) => '$e').toList() : const [];

void main() {
  final lib = (jsonDecode(File(_libraryPath).readAsStringSync()) as List).cast<Json>();
  final byId = {for (final r in lib) r['id'] as String: r};
  final before = (_json(_fixturePath)['core_levels'] as Map).cast<String, dynamic>();
  final record = _json(_recordPath);
  final sourceIds = {for (final r in (_json(_sourcePath)['rows'] as List).cast<Json>()) r['id'] as String};

  test('every Table A id ships its value', () {
    expect([
      for (final e in _tableA.entries)
        if (jsonEncode(_strs(byId[e.key]?['core_levels'])) != jsonEncode(e.value))
          '${e.key}: ${byId[e.key]?['core_levels']} (want ${e.value})'
    ], isEmpty);
  });

  test('no row present in the fixture and outside Table A changed core_levels', () {
    expect([
      for (final e in before.entries)
        if (!_tableA.containsKey(e.key) && byId.containsKey(e.key) &&
            jsonEncode(byId[e.key]!['core_levels']) != jsonEncode(e.value))
          e.key
    ], isEmpty);
    // The fixture is the full pre-S1a library (FROZEN). S1a removes nothing; the only fixture rows that no longer ship are
    // the ones a later batch removed by name: E053 Donkey Calf Raise (Library Batch S1b-3, merged into G1373).
    const removedSince = {'E053'};
    for (final id in removedSince) {
      expect(before.containsKey(id), isTrue, reason: '$id is named as removed since S1a, so the frozen fixture holds it');
      expect(byId.containsKey(id), isFalse, reason: '$id is named as removed since S1a but still ships');
    }
    expect(before.keys.where((i) => !byId.containsKey(i) && !removedSince.contains(i)), isEmpty);
  });

  test('every Table A id actually changed (no no-op entry hides a wrong before)', () {
    expect([
      for (final e in _tableA.entries)
        if (jsonEncode(before[e.key]) == jsonEncode(e.value)) e.key
    ], isEmpty);
  });

  test('the record holds exactly the kept (E) Table A ids, before = fixture, after = Table A', () {
    final rows = (record['rows'] as List).cast<Json>();
    final ids = rows.map((r) => r['id'] as String).toList();
    expect(ids.toSet().length, ids.length, reason: 'duplicate id');
    expect(ids.toSet(), {for (final i in _tableA.keys) if (!sourceIds.contains(i)) i});
    for (final r in rows) {
      final id = r['id'] as String;
      expect(jsonEncode(r['before']), jsonEncode(before[id]), reason: '$id before');
      expect(jsonEncode(r['after']), jsonEncode(_tableA[id]), reason: '$id after');
    }
  });

  test('core_levels lie inside suitable_for for every row (no named exception since Library Batch S1b-2)', () {
    expect([
      for (final r in lib)
        if (!_namedExceptions.containsKey(r['id']) &&
            _strs(r['core_levels'])
                .any((l) => !_strs(r['suitable_for']).map((s) => s.toLowerCase()).contains(l)))
          '${r['id']} ${r['core_levels']} vs ${r['suitable_for']}'
    ], isEmpty);
  });

  test('each named exception still disagrees (a fixed one must leave the map)', () {
    for (final id in _namedExceptions.keys) {
      final r = byId[id]!;
      final sf = _strs(r['suitable_for']).map((s) => s.toLowerCase()).toSet();
      expect(_strs(r['core_levels']).any((l) => !sf.contains(l)), isTrue,
          reason: '$id now agrees: remove it from _namedExceptions (${_namedExceptions[id]})');
    }
  });
}
