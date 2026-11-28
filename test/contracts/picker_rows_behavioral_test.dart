// BEHAVIOURAL: how every hand-pick exercise list is arranged (founder 2026-11-28).
//
// A user adding or swapping by hand sees EVERY exercise. Rows their equipment covers come
// first, and one name is listed once. Plan: docs/plans/2026-11-28-hand-pick-any-exercise.md.
//
// Reader: lib/shared/repositories/picker_rows.dart `PickerRows.arrange`, used by the
// mid-workout picker, the swap sheet, the template builder and the coach's swap list.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/shared/repositories/picker_rows.dart';

Map<String, dynamic> row(
  String id,
  String name, {
  List<String>? equipment,
  String? category,
  String? source,
  List<String>? aliases,
}) =>
    <String, dynamic>{
      'id': id,
      'name': name,
      'equipment_needed': equipment ?? <String>['bodyweight'],
      'category': ?category,
      'source': ?source,
      'name_aliases': ?aliases,
    };

Map<String, dynamic> community(String id, String name,
        {List<String>? equipment, String? category, List<String>? aliases}) =>
    row(id, name,
        equipment: equipment,
        category: category,
        aliases: aliases,
        source: 'community');

List<String> ids(List<Map<String, dynamic>> rows) =>
    [for (final r in rows) r['id'] as String];

void main() {
  final bodyweight =
      EquipmentVocab.effectiveItems('bodyweight', const [], const []);

  PickerRows arrange(
    List<Map<String, dynamic>> library, {
    List<Map<String, dynamic>> custom = const [],
    Set<String>? capability,
  }) =>
      PickerRows.arrange(
          library: library, custom: custom, capability: capability);

  group('every row is listed; the user\'s equipment only orders', () {
    final library = [
      row('L1', 'Barbell Squat', equipment: ['barbell']),
      row('L2', 'Air Squat'),
      row('L3', 'Cable Row', equipment: ['cable machine']),
      row('L4', 'Wall Sit'),
      row('L5', 'Unlisted Gear', equipment: <String>[]),
    ];
    final custom = [
      row('C1', 'Own Barbell Move', equipment: ['barbell']),
      row('C2', 'Own Move', equipment: <String>[]),
    ];

    test('nothing is dropped, and each bucket keeps input order', () {
      final r = arrange(library, custom: custom, capability: bodyweight);
      expect(ids(r.matchingLibrary), ['L2', 'L4']);
      expect(ids(r.otherLibrary), ['L1', 'L3', 'L5']);
      expect(ids(r.matchingCustom), ['C2'],
          reason: 'an own custom with no recorded equipment matches');
      expect(ids(r.otherCustom), ['C1']);
      expect(ids(r.merged), ['L2', 'L4', 'C2', 'L1', 'L3', 'L5', 'C1']);
      expect(ids(r.custom), ['C2', 'C1']);
    });

    test('no capability (rule off or no profile): everything matches, in order',
        () {
      final r = arrange(library, custom: custom);
      expect(ids(r.matchingLibrary), ['L1', 'L2', 'L3', 'L4', 'L5']);
      expect(ids(r.matchingCustom), ['C1', 'C2']);
      expect(r.otherLibrary, isEmpty);
      expect(r.otherCustom, isEmpty);
    });
  });

  group('one row per name', () {
    test('own and community with the SAME id but different names: own stays',
        () {
      final r = arrange([community('X', 'Approved Name')],
          custom: [row('X', 'My Name')]);
      expect(r.matchingLibrary, isEmpty);
      expect(ids(r.matchingCustom), ['X']);
      expect(r.matchingCustom.single['name'], 'My Name');
      expect(r.matchingCustom.single['name_aliases'], ['Approved Name']);
    });

    test('own beside an equipment-less community row, same name, other id', () {
      final r = arrange([community('X', 'My Move', equipment: <String>[])],
          custom: [row('C1', 'my  move')], capability: bodyweight);
      expect(r.matchingLibrary, isEmpty);
      expect(r.otherLibrary, isEmpty);
      expect(ids(r.matchingCustom), ['C1']);
    });

    test('own beside a built-in of the same name: own stays', () {
      final r = arrange([row('E1', 'Goblet Squat', equipment: ['dumbbells'])],
          custom: [row('C1', 'Goblet Squat')], capability: bodyweight);
      expect(r.matchingLibrary, isEmpty);
      expect(r.otherLibrary, isEmpty);
      expect(ids(r.matchingCustom), ['C1']);
    });

    test('community beside a built-in of the same name: the built-in stays', () {
      final r = arrange([
        community('00', 'Goblet Squat'),
        row('E1', 'Goblet Squat', equipment: ['dumbbells']),
      ], capability: bodyweight);
      expect(r.matchingLibrary, isEmpty,
          reason: 'the built-in wins even though only the copy matches');
      expect(ids(r.otherLibrary), ['E1']);
    });

    test('two community rows: the first MATCHING one stays', () {
      final r = arrange([
        community('A', 'Sled Push', equipment: ['barbell']),
        community('B', 'Sled Push'),
      ], capability: bodyweight);
      expect(ids(r.matchingLibrary), ['B']);
      expect(r.otherLibrary, isEmpty);
    });

    test('two community rows, none matching: the first stays', () {
      final r = arrange([
        community('A', 'Sled Push', equipment: ['barbell']),
        community('B', 'Sled Push', equipment: <String>[]),
      ], capability: bodyweight);
      expect(ids(r.otherLibrary), ['A']);
      expect(r.matchingLibrary, isEmpty);
    });

    test('community + built-in + own: only the own row, carrying both', () {
      final r = arrange([
        community('A', 'my move', category: 'legs', aliases: ['Old Copy']),
        row('E1', 'My Move', category: 'core', aliases: ['Older Built In']),
      ], custom: [
        row('C1', 'My Move', category: 'Flexibility')
      ]);
      expect(r.matchingLibrary, isEmpty);
      expect(ids(r.matchingCustom), ['C1']);
      final own = r.matchingCustom.single;
      expect(own['category'], 'Flexibility',
          reason: 'the picker writes this into the session: never changed');
      expect(own['picker_categories'], unorderedEquals(['legs', 'core']));
      expect(own['name_aliases'],
          unorderedEquals(['Old Copy', 'Older Built In']));
    });

    test('the custom that claimed the NAME collects, before the id claimant',
        () {
      final r = arrange([
        community('X', 'Name One', category: 'legs'),
      ], custom: [
        row('X', 'Name Two', category: 'push'),
        row('C2', 'Name One', category: 'pull'),
      ]);
      expect(r.matchingCustom[0]['picker_categories'], isNull);
      expect(r.matchingCustom[1]['picker_categories'], ['legs']);
    });

    test('the input rows are not changed', () {
      final lib = [community('X', 'Approved Name', category: 'legs')];
      final own = [row('X', 'My Name', category: 'push')];
      arrange(lib, custom: own);
      expect(own.single.containsKey('name_aliases'), isFalse);
      expect(own.single.containsKey('picker_categories'), isFalse);
      expect(lib.single['name'], 'Approved Name');
    });
  });

  group('mirrors: different exercises all stay', () {
    test('different names are all listed', () {
      final r = arrange([community('A', 'One'), row('E1', 'Two')],
          custom: [row('C1', 'Three')]);
      expect(ids(r.merged), ['A', 'E1', 'C1']);
    });

    test('a BUILT-IN sharing an id with a custom of another name stays', () {
      final r = arrange([row('X', 'Library Move')],
          custom: [row('X', 'My Move')]);
      expect(ids(r.matchingLibrary), ['X'],
          reason: 'the swap write lets the built-in win an id clash');
      expect(ids(r.matchingCustom), ['X']);
    });

    test('two built-ins with one name, and two customs with one name', () {
      final r = arrange([row('E1', 'Twin'), row('E2', 'Twin')],
          custom: [row('C1', 'Mine'), row('C2', 'Mine')]);
      expect(ids(r.merged), ['E1', 'E2', 'C1', 'C2']);
    });

    test('blank names and empty ids claim nothing', () {
      final r = arrange([community('', ''), community('', ' ')],
          custom: [row('', '')]);
      expect(r.matchingLibrary, hasLength(2));
      expect(r.matchingCustom, hasLength(1));
    });

    test('rows with empty ids never drop each other by id', () {
      final r = arrange([community('', 'A')], custom: [row('', 'B')]);
      expect(r.matchingLibrary, hasLength(1));
      expect(r.matchingCustom, hasLength(1));
    });
  });

  group('inCategory', () {
    test('the row\'s own category, any case', () {
      expect(PickerRows.inCategory({'category': 'core'}, 'Core'), isTrue);
      expect(PickerRows.inCategory({'category': 'core'}, 'Push'), isFalse);
      expect(PickerRows.inCategory({}, 'Push'), isFalse);
    });

    test('a replaced row\'s category counts too', () {
      final kept = {
        'category': 'Flexibility',
        'picker_categories': ['core']
      };
      expect(PickerRows.inCategory(kept, 'Core'), isTrue);
      expect(PickerRows.inCategory(kept, 'flexibility'), isTrue);
      expect(PickerRows.inCategory(kept, 'Legs'), isFalse);
    });
  });

  group('isTaken', () {
    test('case, spaces and curly apostrophes do not hide a taken name', () {
      final taken = {"child's pose"};
      expect(PickerRows.isTaken('Child’s  Pose', taken), isTrue);
      expect(PickerRows.isTaken("CHILD'S POSE", taken), isTrue);
    });

    test('mirror: another name, or no name, is not taken', () {
      final taken = {"child's pose"};
      expect(PickerRows.isTaken('Pose', taken), isFalse);
      expect(PickerRows.isTaken('', taken), isFalse);
      expect(PickerRows.isTaken('', {''}), isFalse);
    });
  });
}
