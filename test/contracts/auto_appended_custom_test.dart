// c3e9a4 (d4b8e1 Batch 0b) — the ONE predicate for "a custom exercise the
// removed generator lever L2 appended on its own", shared by the one-time
// repair migrator and the repeat-pin read. Pure: no Hive.
//
// Mutations (rule 21): drop the `swapped_via` clause in isAutoAppendedCustom →
// "a coach swap to a custom stays" goes RED; drop the `custom_origin` clause →
// "a repeat-pinned custom stays" goes RED.

import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/core/services/auto_appended_custom.dart';

void main() {
  const customs = {'tuck planche', 'elbow lever'};
  bool noLibrary(String _) => false;

  Map<String, dynamic> ex(String name, {bool coach = false}) => {
        'exercise_name': name,
        'sets': 3,
        if (coach) 'swapped_via': 'ai_coach',
      };

  group('isAutoAppendedCustom', () {
    test('a custom name the library does not hold is auto-appended', () {
      expect(
          isAutoAppendedCustom(ex('Tuck Planche'),
              customNamesLower: customs, libraryHas: noLibrary),
          isTrue);
    });

    test('case and surrounding whitespace do not matter', () {
      expect(
          isAutoAppendedCustom(ex('  ELBOW Lever '),
              customNamesLower: customs, libraryHas: noLibrary),
          isTrue);
    });

    test('a coach swap to a custom stays (swapped_via)', () {
      expect(
          isAutoAppendedCustom(ex('Tuck Planche', coach: true),
              customNamesLower: customs, libraryHas: noLibrary),
          isFalse);
    });

    test('a repeat-pinned custom stays (custom_origin)', () {
      expect(
          isAutoAppendedCustom(
              {...ex('Tuck Planche'), 'custom_origin': 'repeat_pin'},
              customNamesLower: customs,
              libraryHas: noLibrary),
          isFalse);
    });

    test('a library exercise stays', () {
      expect(
          isAutoAppendedCustom(ex('Barbell Bench Press'),
              customNamesLower: customs, libraryHas: noLibrary),
          isFalse);
    });

    test('a custom whose name the library also holds stays (library wins)', () {
      expect(
          isAutoAppendedCustom(ex('Tuck Planche'),
              customNamesLower: customs,
              libraryHas: (n) => n.trim().toLowerCase() == 'tuck planche'),
          isFalse);
    });

    test('a missing, non-string or empty name stays', () {
      for (final e in <Map>[
        {'sets': 3},
        {'exercise_name': 7},
        {'exercise_name': '   '},
      ]) {
        expect(
            isAutoAppendedCustom(e,
                customNamesLower: {...customs, ''}, libraryHas: noLibrary),
            isFalse,
            reason: '$e');
      }
    });

    test('libraryHas is asked only about names in the custom set', () {
      final asked = <String>[];
      isAutoAppendedCustom(ex('Barbell Bench Press'),
          customNamesLower: customs,
          libraryHas: (n) {
            asked.add(n);
            return true;
          });
      expect(asked, isEmpty);
    });
  });

  group('isLibraryRow', () {
    test('a bundled row is library; a community-approved custom is not', () {
      expect(isLibraryRow({'name': 'Cable Fly', 'movement_pattern': 'x'}),
          isTrue);
      expect(isLibraryRow({'name': 'L Sit', 'source': 'community'}), isFalse);
    });
  });

  group('stripRow / stripAutoAppendedCustoms', () {
    test('strips the auto-appended customs, keeps everything else in order',
        () {
      final row = {
        'status': 'planned',
        'arranged_at_ms': 123,
        'exercises': [
          ex('Barbell Bench Press'),
          ex('Tuck Planche'),
          'not-a-map',
          ex('Elbow Lever', coach: true),
          ex('elbow lever'),
          ex('Cable Fly'),
        ],
      };
      final out = stripRow(row, customNamesLower: customs, libraryHas: noLibrary);
      expect(
          (out['exercises'] as List)
              .map((e) => e is Map ? e['exercise_name'] : e)
              .toList(),
          ['Barbell Bench Press', 'not-a-map', 'Elbow Lever', 'Cable Fly']);
      expect(out['status'], 'planned');
      expect(out['arranged_at_ms'], 123);
    });

    test('never mutates the input row or its list', () {
      final list = [ex('Barbell Bench Press'), ex('Tuck Planche')];
      final row = {'exercises': list};
      final out = stripRow(row, customNamesLower: customs, libraryHas: noLibrary);
      expect(list, hasLength(2));
      expect(identical(row['exercises'], list), isTrue);
      expect(identical(out, row), isFalse);
      expect(identical(out['exercises'], list), isFalse);
    });

    test('a row without an exercises list is copied unchanged', () {
      final row = {'type': 'rest', 'workout_name': 'Rest Day'};
      final out = stripRow(row, customNamesLower: customs, libraryHas: noLibrary);
      expect(out, row);
      expect(out.containsKey('exercises'), isFalse);
    });

    test('nothing to strip: same length, equal content', () {
      final list = [ex('Barbell Bench Press'), ex('Cable Fly')];
      final out = stripAutoAppendedCustoms(list,
          customNamesLower: customs, libraryHas: noLibrary);
      expect(out, hasLength(list.length));
      expect(out, list);
    });
  });
}
