// test/contracts/exercise_library_schema_contract_test.dart
//
// Batch 13-A (D-1): the 9 malformed stubs E252-E260 (which used muscle_primary/
// is_compound/sets_default/... and were MISSING injury_contraindications) were
// normalized to the canonical 38-key schema + injury-tagged. A missing
// injury_contraindications field is never excluded by the queryV4 injury filter
// (`contra is List && contra.isNotEmpty`), so E252 Wall Sit was served to
// knee-injured users. This structural contract blocks any future row from
// re-introducing a stub-shaped / under-keyed schema.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// 38 - 3 dead image URL fields (image_start_url / image_end_url / gif_url,
// removed by the exercise-plates batch: every populated URL 404'd and the only
// reader was a copy-through in swap_service that nothing rendered) = 35 keys (+5 core-list keys in v13 = 40)
// REQUIRED on every row.
const _canonicalKeys = <String>{
  'id', 'name', 'category', 'movement_pattern', 'exercise_type', 'primary_muscles',
  'secondary_muscles', 'equipment_needed', 'logging_type', 'difficulty_level',
  'suitable_for', 'default_sets', 'default_reps', 'default_rest_secs', 'tempo',
  'met_value', 'cal_per_set_est', 'breathing_cue', 'coaching_cues', 'common_mistakes',
  'warmup_protocol', 'pro_tip', 'is_indian_context', 'indian_alternative', 'source',
  'is_active', 'is_foundational',
  'injury_contraindications', 'is_bilateral', 'cns_demand', 'target_focus',
  'equipment_tier', 'standard_swap', 'priority_tier', 'rep_range',
  // Core-list selection fields (library v13, Batch B1 Task 2) — on every row;
  // values pinned by exercise_library_core_fields_contract_test.dart.
  'core_levels', 'discipline', 'gym_availability', 'requires_coaching',
  'high_impact',
};

// Exercise plates (library v11): present on the rows that have a drawing,
// absent on the rest. They CANNOT join _canonicalKeys -- `missing` would
// then fire on every artwork-less row -- and they cannot simply be ignored
// either, or a typo'd key would slip through `extra`. Hence a second set, and a
// union on the `extra` side only.
// Duplicate merges (library v12, Batch A): `name_aliases` and `merged_ids` sit
// only on the 7 rows that absorbed a retired twin.
// Core-list (library v13, Batch B1 Task 2): `variant_family` is absent on the
// 66 discarded rows; `slot_focus` / `slot_pattern` are ON-only overlays on 19 /
// 12 rows; the skill-ladder keys sit only on skill rows.
const _optionalKeys = <String>{
  'demo_slug', 'demo_pair', 'name_aliases', 'merged_ids',
  'variant_family', 'slot_focus', 'slot_pattern', 'skill_track', 'skill_step',
  'regression_to', 'progression_to',
};

void main() {
  final rows = (jsonDecode(
    File('assets/data/exercise_library.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();

  group('exercise_library schema contract (Batch 13-A D-1)', () {
    test('the canonical schema is 40 required keys plus 11 optional', () {
      expect(_canonicalKeys.length, 40);
      expect(_optionalKeys.length, 11);
      expect(_canonicalKeys.intersection(_optionalKeys), isEmpty);
    });

    test('name_aliases and merged_ids, when present, are non-empty string lists',
        () {
      final bad = <String>[];
      for (final r in rows) {
        for (final key in ['name_aliases', 'merged_ids']) {
          if (!r.containsKey(key)) continue;
          final v = r[key];
          if (v is! List || v.isEmpty || v.any((e) => e is! String || e.trim().isEmpty)) {
            bad.add('${r['id']}.$key=$v');
          }
        }
      }
      expect(bad, isEmpty);
    });

    test('every row carries EXACTLY the 40 required keys and nothing outside '
        'the union with the optional set (blocks stub-shaped rows)', () {
      final offenders = <String>[];
      final allowed = _canonicalKeys.union(_optionalKeys);
      for (final r in rows) {
        final keys = r.keys.toSet();
        final missing = _canonicalKeys.difference(keys);
        final extra = keys.difference(allowed);
        if (missing.isNotEmpty || extra.isNotEmpty) {
          offenders.add('${r['id']}: missing=$missing extra=$extra');
        }
      }
      expect(offenders, isEmpty,
          reason: 'Rows deviating from the 40-key canonical schema:\n${offenders.join('\n')}');
    });

    test('demo_slug and demo_pair travel together, on exactly 156 rows', () {
      // The pair is what the asset pipeline and the resolver both key on; one
      // without the other is a half-written row, not a valid state.
      final lonely = rows
          .where((r) => r.containsKey('demo_slug') != r.containsKey('demo_pair'))
          .map((r) => r['id'])
          .toList();
      expect(lonely, isEmpty, reason: 'rows with one plate key but not the other: $lonely');
      // 165 -> 158: Batch A retired 7 plated duplicates into their twins;
      // 158 -> 156: E207 and E179 pointed at another movement's drawing.
      expect(rows.where((r) => r.containsKey('demo_slug')).length, 156);
    });

    test('no row is MISSING a List injury_contraindications (the E252 live hole)', () {
      final offenders = rows
          .where((r) =>
              !r.containsKey('injury_contraindications') ||
              r['injury_contraindications'] is! List)
          .map((r) => r['id'] as String)
          .toList();
      expect(offenders, isEmpty,
          reason: 'Rows missing a List injury_contraindications: $offenders');
    });

    test('primary_muscles is a non-empty List on every row (muscle-based selection)', () {
      final offenders = rows
          .where((r) => r['primary_muscles'] is! List || (r['primary_muscles'] as List).isEmpty)
          .map((r) => r['id'] as String)
          .toList();
      expect(offenders, isEmpty, reason: 'Rows with empty/absent primary_muscles: $offenders');
    });

    test('285 rows, ids unique (E262-E294 added by OI-89; 7 retired in v12)', () {
      // 259 -> 292, in two waves with different jobs, then 292 -> 285 when Batch A
      // (seed v12) retired 7 duplicates into their twins (merged_ids).
      //
      //
      // Wave 1 (E262-E273, 12 rows) closed a CORRECTNESS deficit the OI-89
      // restore + audit left: vertical_pull had ZERO baseline rows, and
      // horizontal_pull / elbow_flexion / elbow_extension had none performable
      // with the un-excludable floor alone.
      //
      // Wave 2 (E274-E294, 21 rows) closed a DEPTH deficit wave 1 exposed. Three
      // rows satisfies the floor invariant and cannot build a plan: the generator
      // dedups on pickedNames across the whole plan, so a 3-row pool is exhausted
      // inside one week. Measured with the capability floor ON, wave 1 alone left
      // 331 EMPTY SLOTS, all bodyweight-tier, in exactly the six patterns it had
      // taken to 3. Calibrated against the two patterns that already worked:
      // horizontal_push had 6 baseline rows and zero missing, hip_isolation 5 and
      // zero. Six to seven is the working number; three is not.
      expect(rows.length, 285);
      expect(rows.map((r) => r['id']).toSet().length, 285);
      expect(rows.any((r) => r['id'] == 'E261'), isTrue);
      expect(rows.any((r) => r['id'] == 'E294'), isTrue);
    });
  });
}
