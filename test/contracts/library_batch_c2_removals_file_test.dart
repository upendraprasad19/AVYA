// Batch C2a (OI-460, docs/plans/2026-11-04-library-batch-c2a-removals.md) Task 1:
// scripts/data/library_batch_c2_removals.json, the frozen decision for each of the 66 sheet-drop library rows.
//
// The problem list is a pure function of (removals file, shipped library, base fixture), so the same function
// runs on the real files (must be empty) and on in-memory mutations of them (each must name the break).
// Every count is computed from the files, never typed.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

const _removalsRel = 'scripts/data/library_batch_c2_removals.json';
const _fixtureRel = 'test/fixtures/library_c2_base_depth.json';
const _libRel = 'assets/data/exercise_library.json';
const _srcRel = 'scripts/data/library_batch_c_source.json';

Map<String, dynamic> _json(String p) => jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> _deep(Map<String, dynamic> m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

List<String> _problems(Map<String, dynamic> file, List<Map<String, dynamic>> lib, Map<String, dynamic> fx) {
  final out = <String>[];
  final entries = (file['entries'] as List).cast<Map<String, dynamic>>();
  final libIds = {for (final r in lib) r['id'] as String};
  final removedIds = {
    for (final e in (file['entries'] as List).cast<Map<String, dynamic>>())
      if (e['decision'] == 'remove') e['id'] as String,
  };
  // The names of the rows that REMAIN: before the removals ship the removed rows are still in the library, and a
  // removed row's own name is exactly what becomes the alias.
  final libNames = {
    for (final r in lib)
      if (!removedIds.contains(r['id'])) (r['name'] as String).toLowerCase(),
  };
  final sheet = [for (final d in fx['drop'] as List) (d as Map)['id'] as String];
  final seen = <String>{};
  for (final e in entries) {
    final id = e['id'] as String;
    if (!seen.add(id)) out.add('$id has two entries');
    if (!sheet.contains(id)) out.add('$id is not a sheet-drop id');
    final d = e['decision'];
    if (d != 'remove' && d != 'keep') out.add('$id decision is $d');
    final rep = e['replacement'] as String?;
    final alias = e['alias_to'] as String?;
    if (rep != null && !libIds.contains(rep)) out.add('$id replacement $rep is not a shipped row');
    if (alias != null && !libIds.contains(alias)) out.add('$id alias_to $alias is not a shipped row');
    if (alias != null && alias != rep) out.add('$id alias_to must equal its replacement');
    if (alias != null && libNames.contains((e['name'] as String).toLowerCase())) {
      out.add('$id alias "${e['name']}" equals a row name');
    }
    if (d == 'keep') {
      final why = e['keep_reason'];
      if (why != 'depth' && why != 'forced' && why != 'twin_pending') out.add('$id keep_reason is $why');
      if (why == 'forced' && ((e['reason'] as String?) ?? '').trim().isEmpty) out.add('$id forced keep has no reason');
      if (why == 'twin_pending') {
        final twin = e['twin'] as String?;
        if (twin == null) {
          out.add('$id twin_pending names no twin');
        } else if (libIds.contains(twin)) {
          out.add('$id twin $twin already ships: it is a removal, not twin_pending');
        }
      }
    } else if (d == 'remove') {
      if (e.containsKey('keep_reason')) out.add('$id is a remove with a keep_reason');
      if (e.containsKey('twin')) out.add('$id is a remove with a twin');
    }
  }
  for (final id in sheet) {
    if (!seen.contains(id)) out.add('$id (sheet-drop) has no decision');
  }
  final meta = file['_meta'] as Map<String, dynamic>;
  final counts = meta['counts'] as Map<String, dynamic>;
  final nRemove = entries.where((e) => e['decision'] == 'remove').length;
  final nKeep = entries.where((e) => e['decision'] == 'keep').length;
  if (counts['remove'] != nRemove || counts['keep'] != nKeep || counts['total'] != entries.length) {
    out.add('_meta.counts disagree with the entries');
  }
  return out;
}

void main() {
  final file = _json(_removalsRel);
  final fx = _json(_fixtureRel);
  final lib = (jsonDecode(File(_libRel).readAsStringSync()) as List).cast<Map<String, dynamic>>();

  group('removals file (C2a): the frozen decision for the 66 sheet-drop rows', () {
    test('the real file has no problem', () {
      expect(_problems(file, lib, fx), isEmpty);
    });

    test('the sheet hash equals the C1 source meta and the fixture holds the 66 ids', () {
      final src = _json(_srcRel);
      expect((file['_meta'] as Map)['sheet_sha256'], (src['_meta'] as Map)['merged_sha256']);
      expect((fx['_meta'] as Map)['sheet_sha256'], (src['_meta'] as Map)['merged_sha256']);
      expect((fx['drop'] as List), hasLength(66));
    });

    test('the generator --check says the committed file is current', () {
      final r = runSpawn('node', ['scripts/library_batch_c2_removals_gen.js', '--check'],
          why: 'removals generator --check on the real fixture');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    });

    test('E138 (conditioning, in no pool) is a removal and E293 is a removal with replacement E291', () {
      final byId = {for (final e in file['entries'] as List) (e as Map)['id'] as String: e};
      expect(byId['E138']!['decision'], 'remove');
      expect(byId['E293']!['decision'], 'remove');
      expect(byId['E293']!['replacement'], 'E291');
    });
  });

  group('mutations: each break the file contract exists to catch is named', () {
    test('delete a decision', () {
      final m = _deep(file);
      (m['entries'] as List).removeWhere((e) => (e as Map)['id'] == 'E125');
      expect(_problems(m, lib, fx).any((p) => p.startsWith('E125')), isTrue);
    });

    test('point a replacement at a missing id', () {
      final m = _deep(file);
      final e = (m['entries'] as List).cast<Map<String, dynamic>>().firstWhere((e) => e['id'] == 'E254');
      e['replacement'] = 'G9999';
      expect(_problems(m, lib, fx).any((p) => p.contains('G9999')), isTrue);
    });

    test('an alias equal to a row name', () {
      final m = _deep(file);
      final e = (m['entries'] as List).cast<Map<String, dynamic>>().firstWhere((e) => e['id'] == 'E144');
      e['name'] = 'Forward Lunge';
      expect(_problems(m, lib, fx).any((p) => p.contains('equals a row name')), isTrue);
    });

    test('a remove row marked twin_pending whose twin already ships', () {
      final m = _deep(file);
      final e = (m['entries'] as List).cast<Map<String, dynamic>>().firstWhere((e) => e['id'] == 'E144');
      e['decision'] = 'keep';
      e['keep_reason'] = 'twin_pending';
      e['twin'] = 'G3470';
      expect(_problems(m, lib, fx).any((p) => p.contains('already ships')), isTrue);
    });

    test('a forced keep without a reason', () {
      final m = _deep(file);
      final e = (m['entries'] as List).cast<Map<String, dynamic>>().firstWhere((e) => e['id'] == 'E208');
      e['reason'] = '';
      expect(_problems(m, lib, fx).any((p) => p.contains('forced keep has no reason')), isTrue);
    });
  });
}
