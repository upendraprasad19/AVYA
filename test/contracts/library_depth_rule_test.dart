// Batch C2a (OI-460, docs/plans/2026-11-04-library-batch-c2a-removals.md) Task 2: the depth rule, permanent.
//
// Removing a sheet-drop row must leave min(depth_before, 3) rows in every cell the row occupies, under BOTH
// `movement_pattern` and `slot_pattern ?? movement_pattern`. The helper (test/helpers/library_depth.dart) computes it;
// scripts/data/library_batch_c2_removals.json freezes the decision; this file proves the two agree on the BASE library
// (test/fixtures/library_c2_base_depth.json) and that the SHIPPED library still honours the rule.
// Batch C2b (OI-462): the four twin rows (test/fixtures/library_c2b_twin_rows.json) are added to the base, so a removal is
// judged with its twin present; the mirror guard below pins that fixture to the shipped G rows.
// Every literal is computed from the files.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/migration_ledger_hash_lib.dart' show sha256Hex;
import '../helpers/library_depth.dart';

Map<String, dynamic> _json(String p) => jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final file = _json('scripts/data/library_batch_c2_removals.json');
  final fx = _json('test/fixtures/library_c2_base_depth.json');
  final twinFx = _json('test/fixtures/library_c2b_twin_rows.json');
  final twinRows = (twinFx['rows'] as List).cast<Map<String, dynamic>>();
  final baseOnly = (fx['rows'] as List).cast<Map<String, dynamic>>();
  final base = [...baseOnly, ...twinRows];
  final shipped = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final entries = (file['entries'] as List).cast<Map<String, dynamic>>();
  final sheet = [for (final d in fx['drop'] as List) (d as Map)['id'] as String];
  final byId = {for (final r in base) r['id'] as String: r};
  final sets = depthInjurySets(base);

  Set<String> idsWhere(bool Function(Map<String, dynamic>) f) => {
        for (final e in entries)
          if (f(e)) e['id'] as String,
      };
  final removeIds = idsWhere((e) => e['decision'] == 'remove');
  final fileKeep = idsWhere((e) => e['decision'] == 'keep');
  final forced = idsWhere((e) => e['keep_reason'] == 'forced');
  final frozen = <String, Map<String, int>>{
    for (final e in entries)
      e['id'] as String: {
        for (final c in (e['depth_before'] as Map<String, dynamic>).entries) c.key: c.value as int,
      },
  };

  Set<String> computed({Set<DepthSemantics> semantics = const {DepthSemantics.movementPattern, DepthSemantics.slotPattern}}) => {
        for (final s in semantics) ...computeDepthKeeps(base, sheet, forced: forced, sem: s, sets: sets),
      }.difference(forced);

  group('depth rule on the BASE library reproduces the frozen decision', () {
    test('computed depth keeps and forced keeps make exactly the file keep set', () {
      final c = computed();
      expect(c.difference(fileKeep), isEmpty, reason: 'a computed keep the file removes');
      expect(fileKeep.difference(c), forced, reason: 'file_keep minus computed_keep must be exactly the forced keeps');
    });

    test('the helper never keeps an ineligible row (E138 is conditioning)', () {
      expect(byId['E138']!['discipline'], 'conditioning');
      expect(computed().contains('E138'), isFalse);
    });

    test('the frozen depth_before equals the replay on the base fixture, cell for cell', () {
      for (final e in entries.where((e) => e['decision'] == 'remove')) {
        final row = byId[e['id']]!;
        final replay = <String, int>{};
        for (final sem in DepthSemantics.values) {
          for (final c in depthCells(base, row, sem: sem, sets: sets).entries) {
            if (c.value < 3) replay[c.key] = c.value;
          }
        }
        expect(frozen[e['id']], replay, reason: '${e['id']} frozen depth_before drifted from the base fixture');
      }
    });

    test('simulated removal on the base fixture breaks no cell', () {
      final rows = [for (final i in removeIds) byId[i]!];
      expect(depthViolations(base, rows, removeIds: removeIds, sets: sets, frozenBefore: frozen), isEmpty);
    });
  });

  group('the SHIPPED library honours the rule', () {
    test('every remove entry leaves its cells at min(frozen before, 3) on assets/data/exercise_library.json', () {
      final rows = [for (final i in removeIds) byId[i]!];
      // `without: removeIds` makes the check the same before and after the removals ship.
      expect(depthViolations(shipped, rows, removeIds: removeIds, sets: sets, frozenBefore: frozen), isEmpty);
    });
  });

  group('mutations: each way the rule can be neutered is caught', () {
    test('flip a depth keep (E261) to remove', () {
      final rows = [for (final i in {...removeIds, 'E261'}) byId[i]!];
      final v = depthViolations(base, rows, removeIds: {...removeIds, 'E261'}, sets: sets, frozenBefore: frozen);
      expect(v.any((s) => s.startsWith('E261')), isTrue);
    });

    test('keep a harmless row (E125) and remove a needed one (E261)', () {
      final swapped = {...removeIds.difference({'E125'}), 'E261'};
      final rows = [for (final i in swapped) byId[i]!];
      final v = depthViolations(base, rows, removeIds: swapped, sets: sets, frozenBefore: frozen);
      expect(v.any((s) => s.startsWith('E261')), isTrue);
    });

    test('a removable row occupies no thin cell, so the frozen table is empty and every cell needs 3', () {
      // A cell with before < 3 contains the row itself, so removing it drops the cell below min(before, 3): such a
      // row is a keep. The frozen map is therefore empty for every remove entry; a non-empty one means a row was
      // marked remove that the rule forbids.
      expect(frozen.values.every((m) => m.isEmpty), isTrue);
      final thin = {...removeIds, 'E261'};
      final v = depthViolations(base, [for (final i in thin) byId[i]!], removeIds: thin, sets: sets, frozenBefore: frozen);
      expect(v, isNotEmpty, reason: 'the empty table still reddens a row that thins a cell');
    });

    test('one semantics only misses E263 (slot) and E148 (movement pattern)', () {
      final mpOnly = computed(semantics: {DepthSemantics.movementPattern});
      final slotOnly = computed(semantics: {DepthSemantics.slotPattern});
      expect(mpOnly.union(slotOnly), computed());
      expect(mpOnly.length < computed().length || slotOnly.length < computed().length, isTrue,
          reason: 'at least one keep exists under one semantics only');
    });
  });

  group('the twin rows (Batch C2b)', () {
    test('with G1489 in the base E111 is removable; without it E111 is a computed depth keep', () {
      expect(computed().contains('E111'), isFalse);
      final withoutTwin = [for (final r in base) if (r['id'] != 'G1489') r];
      final c = {
        for (final s in DepthSemantics.values)
          ...computeDepthKeeps(withoutTwin, sheet, forced: forced, sem: s, sets: depthInjurySets(withoutTwin)),
      };
      expect(c.contains('E111'), isTrue, reason: 'the twin row is what frees E111');
    });

    test('the six rows C2a kept as twin_pending are removals with a twin replacement now', () {
      const pairs = {'E084': 'G1368', 'E211': 'G1368', 'E111': 'G1489', 'E162': 'G2567', 'E169': 'G2567', 'E179': 'G0474'};
      for (final e in pairs.entries) {
        final entry = entries.firstWhere((x) => x['id'] == e.key);
        expect(entry['decision'], 'remove', reason: e.key);
        expect(entry['replacement'], e.value, reason: e.key);
        expect(entry['removed_in'], 'c2b', reason: e.key);
      }
    });

    test('the twin fixture sha256 is the one the removals file recorded (an edit of the fixture without a regeneration is red)', () {
      final bytes = File('test/fixtures/library_c2b_twin_rows.json').readAsBytesSync();
      expect(sha256Hex(bytes), (file['_meta'] as Map)['twin_fixture_sha256']);
      expect((file['_meta'] as Map)['twin_fixture'], 'test/fixtures/library_c2b_twin_rows.json');
    });

    test('mirror guard: the fixture rows equal the shipped G rows depth fields', () {
      final shippedById = {for (final r in shipped) r['id'] as String: r};
      expect(twinRows, hasLength(4));
      for (final t in twinRows) {
        final s = shippedById[t['id']];
        expect(s, isNotNull, reason: '${t['id']} must ship');
        for (final k in ['name', 'discipline', 'movement_pattern', 'injury_contraindications', 'equipment_tier']) {
          expect(t[k], s![k], reason: '${t['id']} $k drifted from the shipped row');
        }
        expect(t['slot_pattern'], s!['slot_pattern'], reason: '${t['id']} slot_pattern drifted');
      }
    });
  });
}
