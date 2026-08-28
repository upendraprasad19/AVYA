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

const _canonicalKeys = <String>{
  'id', 'name', 'category', 'movement_pattern', 'exercise_type', 'primary_muscles',
  'secondary_muscles', 'equipment_needed', 'logging_type', 'difficulty_level',
  'suitable_for', 'default_sets', 'default_reps', 'default_rest_secs', 'tempo',
  'met_value', 'cal_per_set_est', 'breathing_cue', 'coaching_cues', 'common_mistakes',
  'warmup_protocol', 'pro_tip', 'is_indian_context', 'indian_alternative', 'source',
  'image_start_url', 'image_end_url', 'gif_url', 'is_active', 'is_foundational',
  'injury_contraindications', 'is_bilateral', 'cns_demand', 'target_focus',
  'equipment_tier', 'standard_swap', 'priority_tier', 'rep_range',
};

void main() {
  final rows = (jsonDecode(
    File('assets/data/exercise_library.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();

  group('exercise_library schema contract (Batch 13-A D-1)', () {
    test('the canonical schema is exactly 38 keys', () {
      expect(_canonicalKeys.length, 38);
    });

    test('every row carries EXACTLY the 38 canonical keys (blocks stub-shaped rows)', () {
      final offenders = <String>[];
      for (final r in rows) {
        final keys = r.keys.toSet();
        final missing = _canonicalKeys.difference(keys);
        final extra = keys.difference(_canonicalKeys);
        if (missing.isNotEmpty || extra.isNotEmpty) {
          offenders.add('${r['id']}: missing=$missing extra=$extra');
        }
      }
      expect(offenders, isEmpty,
          reason: 'Rows deviating from the 38-key canonical schema:\n${offenders.join('\n')}');
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
