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

    test('259 rows, ids unique (E261 added, 9 stubs kept)', () {
      expect(rows.length, 259);
      expect(rows.map((r) => r['id']).toSet().length, 259);
      expect(rows.any((r) => r['id'] == 'E261'), isTrue);
    });
  });
}
