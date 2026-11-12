// Generator Unit 1B-F2 (seed v27, OI-495, docs/plans/2026-11-12-generator-1bf2-overlay-copy.md Task 5): the core-list
// overlays (`slot_pattern`, `slot_focus`) were copied into the rows' own `movement_pattern` / `target_focus` on 27 rows and
// both keys removed; CoreListSelector reads the row's own fields. This file proves three things on the SHIPPED library:
//
//   1. the data: no row carries an overlay key, and each of the 27 rows holds the record's `after` (N20, a Batch C source
//      row, holds the source's value);
//   2. the identity: what the old reader (`slot_pattern ?? movement_pattern`, `slot_focus ?? target_focus`) saw on the v26
//      library is exactly what the new reader sees on the v27 library, row by row, and the core-list pool of every V4 slot
//      (every goal, 3 to 6 days, every level, phase 1 and 2, variant B quad on and off, bodyweight and full_gym) is the
//      same list in the same order;
//   3. the reader: the selector no longer reads an overlay key. A `slot_pattern` / `slot_focus` planted on the 27 rows with
//      their v26 values (the opposite direction of the copy) must not move one pool.
//
// Mutations (each reddens a test here; recorded in the diagnose doc): skip the importer's overlay-copy stage (the rows keep
// their overlays: test 1); leave one overlay key in place (test 1); edit one row's `after` in the record (test 1); restore
// `slot_pattern ?? movement_pattern` or `slot_focus ?? target_focus` in core_list_selector.dart (test 3).
//
// Pure: CoreListSelector.rankedPool and SplitResolver.selectV4 (with variantBQuad passed) read no Hive.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/core_list_selector.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';

import '../helpers/library_overlay_v26.dart';

const _overlayKeys = ['slot_pattern', 'slot_focus'];

List<Map<String, dynamic>> _shipped() =>
    (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _record() =>
    jsonDecode(File('scripts/data/library_overlay_copy_v27.json').readAsStringSync()) as Map<String, dynamic>;

/// What the pre-1B-F2 reader saw in a row (restated, never imported): the overlay wins over the row's own field.
Map<String, dynamic> _oldReaderView(Map<String, dynamic> r) => {
      for (final e in r.entries)
        if (!_overlayKeys.contains(e.key))
          e.key: e.key == 'movement_pattern'
              ? (r['slot_pattern'] ?? r['movement_pattern'])
              : e.key == 'target_focus'
                  ? (r['slot_focus'] ?? r['target_focus'])
                  : e.value,
    };

/// Every distinct V4 slot, with the level it is generated for.
List<(MuscleSlot, String)> _allSlots() {
  final seen = <String>{};
  final out = <(MuscleSlot, String)>[];
  for (final goal in ['build_muscle', 'lose_fat', 'strength', 'general_fitness']) {
    for (final days in [3, 4, 5, 6]) {
      for (final level in ['beginner', 'intermediate', 'advanced']) {
        for (final bQuad in [true, false]) {
          for (final d in SplitResolver.selectV4(goal, days, experienceLevel: level, variantBQuad: bQuad)) {
            for (final s in [...d.slotsA, ...?d.slotsB]) {
              if (seen.add('$level $s')) out.add((s, level));
            }
          }
        }
      }
    }
  }
  return out;
}

/// The pool's observable output, as one comparable string.
String _pool(List<Map<String, dynamic>> rows, MuscleSlot slot, String level, int phase, String tier) {
  final p = CoreListSelector.rankedPool(
    rows: rows,
    slot: slot,
    level: level,
    phase: phase,
    equipmentTier: tier,
    capability: null,
    exclusions: const {},
    isContraindicated: (_) => false,
    pickedNames: const {},
    demotedNames: const {},
  );
  return '${p.source} ${p.improvisedRemoved} ${p.nonImprovisedInPool} ${(p.families.toList()..sort()).join(',')} '
      '${p.jumpRemoved} ${p.jumpOnlyPool} ${p.likeForLikeImplement} | ${p.ordered.map((r) => r['id']).join(' ')}';
}

void main() {
  final shipped = _shipped();
  final byId = {for (final r in shipped) r['id'] as String: r};

  group('1. the data', () {
    test('no shipped row carries an overlay key', () {
      expect([for (final r in shipped) if (_overlayKeys.any(r.containsKey)) r['id']], isEmpty);
    });

    test("the 26 kept rows hold the record's after; N20 holds the source's copied pattern; the record names 26 kept rows", () {
      final rows = (_record()['rows'] as List).cast<Map<String, dynamic>>();
      expect(rows, hasLength(26));
      for (final e in rows) {
        final row = byId[e['id']];
        expect(row, isNotNull, reason: '${e['id']} ships');
        final after = e['after'] as Map<String, dynamic>;
        expect(row!['movement_pattern'], after['movement_pattern'], reason: '${e['id']} movement_pattern');
        expect(row['target_focus'], after['target_focus'], reason: '${e['id']} target_focus');
      }
      expect(byId['N20']!['movement_pattern'], ['hip_dominant']);
      expect(overlayRowIdsV27, {...rows.map((e) => e['id'] as String), 'N20'});
    });

    test('MIRROR: N19 keeps hip_isolation (founder 2026-11-09), E064 keeps cardio first', () {
      expect(byId['N19']!['movement_pattern'], ['hip_isolation']);
      expect((byId['E064']!['movement_pattern'] as List).first, 'cardio');
    });
  });

  group('2. the identity', () {
    test('per row: the old reader on the v26 library sees exactly the v27 row (key order aside), for all rows', () {
      final diffs = <String>[];
      for (final r in shipped) {
        final old = _oldReaderView(withOverlaysV26(r));
        if (jsonEncode(Map.fromEntries(old.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) !=
            jsonEncode(Map.fromEntries(r.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))) {
          diffs.add(r['id'] as String);
        }
      }
      expect(diffs, isEmpty);
    });

    test('the v26 library really differs (precondition): the 27 rows carry overlays and other own values', () {
      final v26 = [for (final r in shipped) withOverlaysV26(r)];
      expect(v26.where((r) => _overlayKeys.any(r.containsKey)).length, 27);
      expect(withOverlaysV26(byId['E048']!)['movement_pattern'], ['hip_isolation']);
    });

    test('the core-list pool of every V4 slot is the same list on the v27 library as on the v26 library under the old reader', () {
      final slots = _allSlots();
      expect(slots.length, greaterThan(50), reason: 'the slot sweep must see the V4 catalogue');
      final v26Seen = [for (final r in shipped) _oldReaderView(withOverlaysV26(r))];
      final diffs = <String>[];
      var nonEmpty = 0;
      for (final (slot, level) in slots) {
        for (final phase in [1, 2]) {
          for (final tier in ['bodyweight', 'full_gym']) {
            final a = _pool(shipped, slot, level, phase, tier);
            if (!a.endsWith('| ')) nonEmpty++;
            if (a != _pool(v26Seen, slot, level, phase, tier)) diffs.add('$slot $level p$phase $tier');
          }
        }
      }
      expect(diffs, isEmpty);
      expect(nonEmpty, greaterThan(slots.length), reason: 'most pools are non-empty: the comparison is not vacuous');
    });
  });

  group('3. the reader', () {
    test('an overlay key planted on the 27 rows with the v26 value moves no pool (the selector reads the row\'s own fields)', () {
      final rec = {for (final e in (_record()['rows'] as List).cast<Map<String, dynamic>>()) e['id'] as String: e['before'] as Map};
      rec['N20'] = {'movement_pattern': ['knee_dominant']};
      final planted = [
        for (final r in shipped)
          rec.containsKey(r['id'])
              ? {
                  ...r,
                  'slot_pattern': rec[r['id']]!['movement_pattern'],
                  if (rec[r['id']]!.containsKey('target_focus')) 'slot_focus': rec[r['id']]!['target_focus'],
                }
              : r,
      ];
      final diffs = <String>[];
      var changedUnderOld = 0;
      for (final (slot, level) in _allSlots()) {
        for (final phase in [1, 2]) {
          for (final tier in ['bodyweight', 'full_gym']) {
            final a = _pool(shipped, slot, level, phase, tier);
            if (a != _pool(planted, slot, level, phase, tier)) diffs.add('$slot $level p$phase $tier');
            if (a != _pool([for (final r in planted) _oldReaderView(r)], slot, level, phase, tier)) changedUnderOld++;
          }
        }
      }
      expect(diffs, isEmpty);
      // MIRROR: the planted keys are not inert. The old reader would have read them, and the pools would have moved.
      expect(changedUnderOld, greaterThan(0));
    });
  });
}
