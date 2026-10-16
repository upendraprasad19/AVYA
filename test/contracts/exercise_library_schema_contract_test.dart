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
// reader was a copy-through in swap_service that nothing rendered) = 35 keys
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
};

// Exercise plates (library v11): present on the 165 rows that have a drawing,
// absent on the other 127. They CANNOT join _canonicalKeys -- `missing` would
// then fire on every artwork-less row -- and they cannot simply be ignored
// either, or a typo'd key would slip through `extra`. Hence a second set, and a
// union on the `extra` side only.
const _optionalKeys = <String>{'demo_slug', 'demo_pair'};

void main() {
  final rows = (jsonDecode(
    File('assets/data/exercise_library.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();

  group('exercise_library schema contract (Batch 13-A D-1)', () {
    test('the canonical schema is 35 required keys plus 2 optional', () {
      expect(_canonicalKeys.length, 35);
      expect(_optionalKeys.length, 2);
      expect(_canonicalKeys.intersection(_optionalKeys), isEmpty);
    });

    test('every row carries EXACTLY the 35 required keys and nothing outside '
        'the union with the optional two (blocks stub-shaped rows)', () {
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
          reason: 'Rows deviating from the 35-key canonical schema:\n${offenders.join('\n')}');
    });

    test('demo_slug and demo_pair travel together, on exactly 165 rows', () {
      // The pair is what the asset pipeline and the resolver both key on; one
      // without the other is a half-written row, not a valid state.
      final lonely = rows
          .where((r) => r.containsKey('demo_slug') != r.containsKey('demo_pair'))
          .map((r) => r['id'])
          .toList();
      expect(lonely, isEmpty, reason: 'rows with one plate key but not the other: $lonely');
      expect(rows.where((r) => r.containsKey('demo_slug')).length, 165);
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

    test('292 rows, ids unique (E262-E294 added by OI-89)', () {
      // 259 -> 292, in two waves with different jobs.
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
      expect(rows.length, 292);
      expect(rows.map((r) => r['id']).toSet().length, 292);
      expect(rows.any((r) => r['id'] == 'E261'), isTrue);
      expect(rows.any((r) => r['id'] == 'E294'), isTrue);
    });
  });
}
