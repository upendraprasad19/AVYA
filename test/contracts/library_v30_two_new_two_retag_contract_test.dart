// Library v30 (docs/plans/2026-11-28-media-two-new-two-retag.md): the founder-approved values of the two new rows and
// the two retagged rows, typed from the approval, plus the media each of the four carries.
//
// Run: flutter test test/contracts/library_v30_two_new_two_retag_contract_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, Map<String, dynamic>> _library() => {
      for (final r in jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List)
        (r as Map)['id'] as String: r.cast<String, dynamic>(),
    };

const _expected = <String, Map<String, Object>>{
  'G0592': {
    'name': 'Machine Preacher Curl',
    'category': 'pull',
    'movement_pattern': ['elbow_flexion'],
    'exercise_type': ['isolation'],
    'primary_muscles': ['Biceps'],
    'secondary_muscles': ['Brachialis', 'Forearms'],
    'target_focus': ['Biceps (Short Head)'],
    'equipment_needed': ['machines'],
    'equipment_tier': ['full_gym'],
    'difficulty_level': 'intermediate',
    'default_sets': 3,
    'default_reps': '10-12',
    'default_rest_secs': 60,
    'logging_type': 'weight_reps',
    'is_bilateral': true,
    'injury_contraindications': ['elbow'],
    'variant_family': 'preacher_curl',
    'core_levels': <String>[],
    'gym_availability': 'well_equipped_gym',
    'coaching_cues': [
      'Set the seat so your upper arms rest flat on the pad',
      'Hold the handles with your palms up',
      'Curl without lifting your elbows',
      'Lower slowly, stopping just before your arms are fully straight',
    ],
    'common_mistakes': [
      'Lifting your elbows',
      'Dropping the weight and snapping your elbows straight',
      'Shrugging because the seat is poorly adjusted',
    ],
    'media_slug': '0592-preacher-curl',
  },
  'G0979': {
    'name': 'Band Pallof Press',
    'category': 'core',
    'movement_pattern': ['core'],
    'exercise_type': ['isolation'],
    'primary_muscles': ['Core', 'Obliques'],
    'secondary_muscles': ['Front Delts'],
    'target_focus': ['Core/Obliques'],
    'equipment_needed': ['resistance band'],
    'equipment_tier': ['home_dumbbells', 'basic_gym', 'full_gym'],
    'difficulty_level': 'beginner',
    'suitable_for': ['Beginner', 'Intermediate', 'Advanced'],
    'default_sets': 3,
    'default_reps': '10-12 each side',
    'default_rest_secs': 60,
    'logging_type': 'weight_reps',
    'is_bilateral': false,
    'injury_contraindications': <String>[],
    'variant_family': 'anti_rotation',
    'core_levels': <String>[],
    'gym_availability': 'home',
    'coaching_cues': [
      'Stand sideways to the anchor with the band at chest height',
      'Brace your core',
      'Press straight forward without turning',
      'Pause for one second, return slowly, and repeat on both sides',
    ],
    'common_mistakes': ['Twisting toward the anchor', 'Leaning away', 'Shrugging or rushing'],
    'media_slug': '0979-band-horizontal-pallof-press',
  },
  'E027': {
    'name': 'T-Bar Row',
    'equipment_needed': ['machines'],
    'equipment_tier': ['full_gym'],
    'gym_availability': 'well_equipped_gym',
    'injury_contraindications': ['lower_back'],
    'coaching_cues': [
      'Stand on the platform with your feet planted',
      'Hinge at the hips',
      'Keep your back flat',
      'Pull towards your lower chest',
    ],
    'media_slug': '0606-t-bar-row',
  },
  'E120': {
    'name': 'Svend Press',
    'equipment_needed': ['dumbbells'],
    'equipment_tier': ['home_dumbbells', 'basic_gym', 'full_gym'],
    'gym_availability': 'home',
    'injury_contraindications': <String>[],
    'coaching_cues': ['Hold plate between palms', 'squeeze plate hard', 'press forward', 'return slowly'],
    'media_slug': '0856-weighted-svend-press',
  },
};

void main() {
  final lib = _library();

  for (final e in _expected.entries) {
    test('${e.key} ships the approved values', () {
      final row = lib[e.key];
      expect(row, isNotNull, reason: '${e.key} is not in the library');
      for (final v in e.value.entries) {
        expect(row![v.key], v.value, reason: '${e.key}.${v.key}');
      }
      expect(row!['media_version'], 1);
      expect(row['media_source'], 'wardroom');
      expect(File('assets/exercise_stills/${row['media_slug']}.webp').existsSync(), isTrue, reason: 'the bundled still');
    });
  }

  test('the held old-row pictures 0592 and 0979 are shown by the new rows only', () {
    for (final entry in {'0592-preacher-curl': 'G0592', '0979-band-horizontal-pallof-press': 'G0979'}.entries) {
      expect([for (final r in lib.values) if (r['media_slug'] == entry.key) r['id']], [entry.value]);
    }
    expect(lib['E095']!.containsKey('media_slug'), isFalse);
    expect(lib['E132']!.containsKey('media_slug'), isFalse);
  });
}
