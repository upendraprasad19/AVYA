// BEHAVIOURAL: the swap sheet lists EVERY exercise (founder 2026-11-28). The user's
// equipment only orders the list: matching rows first, then the user's own, then the rest
// under MORE FROM THE LIBRARY. One name is listed once.
//
// Reader: lib/features/train/widgets/exercise_swap_sheet.dart, through
// lib/shared/repositories/picker_rows.dart. The names a session already holds stay greyed
// (SoT `exercise_name_unique_in_day`).
@Timeout(Duration(minutes: 3))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/widgets/exercise_swap_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

import '../features/train/log_exercise/card_harness.dart';

const _current = 'Wall Slide Test';
const _barbell = 'Barbell Row Test';
const _floor = 'Floor Press Test';
const _own = 'Own Move Test';
const _header = 'MORE FROM THE LIBRARY';

Map<String, dynamic> _lib(String id, String name, List<String> equipment,
        {String category = 'Push', List<String>? aliases, String? source}) =>
    <String, dynamic>{
      'id': id,
      'name': name,
      'category': category,
      'logging_type': 'weight_reps',
      'equipment_needed': equipment,
      'name_aliases': ?aliases,
      'source': ?source,
    };

/// The barbell row is keyed FIRST in Hive, so an order assertion cannot pass unless the
/// sheet really puts the user's equipment first.
final _library = <Map<String, dynamic>>[
  _lib('A0', _barbell, ['barbell']),
  _lib('L1', _floor, ['bodyweight']),
  _lib('L9', _current, ['bodyweight']),
];

Future<void> _pump(
  WidgetTester tester, {
  required String tier,
  List<Map<String, dynamic>>? library,
  List<Map<String, dynamic>> custom = const [],
  Set<String> taken = const {},
  String? category,
  List<SwapExerciseData>? picked,
}) async {
  await ensureHive(tester);
  await seedLibrary(tester, rows: library ?? _library);
  await tester.runAsync(() async {
    final box = HiveService.instance.customBox;
    await box.clear();
    for (final row in [
      <String, dynamic>{
        'id': 'custom_exercise_own',
        'name': _own,
        'category': 'Push',
        'equipment_needed': <String>[],
      },
      ...custom,
    ]) {
      await box.put(row['id'], <String, dynamic>{'type': 'exercise', ...row});
    }
  });
  // Tall enough that the lazy list builds every row.
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ExerciseSwapSheet(
        key: UniqueKey(),
        currentExerciseName: _current,
        category: category,
        capability: EquipmentVocab.effectiveItems(tier, const [], const []),
        takenNames: taken,
        onSelect: (data) => picked?.add(data),
      ),
    ),
  ));
  await tester.pump();
}

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

Finder _selectIn(String name) => find.descendant(
    of: find.ancestor(of: find.text(name), matching: find.byType(InkWell)).first,
    matching: find.widgetWithText(WardButton, 'SELECT'));

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

void main() {
  tearDownAll(closeHive);

  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  testWidgets('a bodyweight user sees every row: theirs, then own, then the rest',
      (tester) async {
    await _pump(tester, tier: 'bodyweight');
    expect(_top(tester, _floor), lessThan(_top(tester, _own)));
    expect(_top(tester, _own), lessThan(_top(tester, _header)));
    expect(_top(tester, _header), lessThan(_top(tester, _barbell)));
    expect(_selectIn(_barbell), findsOneWidget);
    expect(find.text(_current), findsOneWidget,
        reason: 'the outgoing exercise is the header only, never a row');
  });

  testWidgets('SELECT on a row outside the user\'s equipment picks it',
      (tester) async {
    final picked = <SwapExerciseData>[];
    await _pump(tester, tier: 'bodyweight', picked: picked);
    await tester.tap(_selectIn(_barbell));
    await tester.pump();
    expect([for (final p in picked) (p.id, p.name)], [('A0', _barbell)]);
  });

  testWidgets('a taken name outside the equipment is listed and cannot be picked',
      (tester) async {
    final picked = <SwapExerciseData>[];
    await _pump(tester,
        tier: 'bodyweight', taken: {'barbell row test'}, picked: picked);
    expect(find.text(_barbell), findsOneWidget);
    expect(_selectIn(_barbell), findsNothing);
    expect(find.text(WardroomCopy.activeAlreadyInWorkoutTag), findsOneWidget);
    await tester.tap(find.text(_barbell));
    await tester.pump();
    expect(picked, isEmpty);
    expect(_selectIn(_floor), findsOneWidget, reason: 'mirror: the rest stay live');
  });

  testWidgets('mirror: when the equipment covers every row there is no new header',
      (tester) async {
    await _pump(tester, tier: 'full_gym');
    expect(find.text(_header), findsNothing);
    expect(_top(tester, _barbell), lessThan(_top(tester, _own)),
        reason: 'library first, then the user\'s own, as before');
  });

  testWidgets('an older name finds the own exercise that replaced a library row',
      (tester) async {
    await _pump(tester, tier: 'bodyweight', library: [
      ..._library,
      _lib('E7', 'My Hinge Test', ['bodyweight'],
          aliases: ['Old Hinge Name Test']),
    ], custom: [
      {
        'id': 'custom_exercise_hinge',
        'name': 'My Hinge Test',
        'category': 'Pull',
        'equipment_needed': <String>[],
      },
    ]);
    await _search(tester, 'old hinge');
    expect(find.text('My Hinge Test'), findsOneWidget);
    expect(find.text('CUSTOM'), findsOneWidget);
    expect(find.text(_floor), findsNothing, reason: 'mirror: the search narrows');
  });

  testWidgets('an own exercise and a built-in of one name are one row',
      (tester) async {
    await _pump(tester, tier: 'bodyweight', category: 'Core', library: [
      ..._library,
      _lib('E8', 'Dead Bug Test', ['barbell'], category: 'core'),
    ], custom: [
      {
        'id': 'custom_exercise_bug',
        'name': 'Dead Bug Test',
        'category': 'Flexibility',
        'equipment_needed': <String>[],
      },
    ]);
    expect(find.text('Dead Bug Test'), findsOneWidget);
    expect(find.text(_header), findsNothing,
        reason: 'the Core chip has no other library row once the twin is gone');
  });

  testWidgets('the category chip never hides the user\'s own exercises',
      (tester) async {
    await _pump(tester, tier: 'bodyweight', category: 'Pull', custom: [
      {
        'id': 'custom_exercise_yoga',
        'name': 'Surya Test',
        'category': 'indian_traditional',
        'equipment_needed': <String>[],
      },
    ]);
    expect(find.text('Surya Test'), findsOneWidget);
    expect(find.text(_own), findsOneWidget);
    expect(find.text(_floor), findsNothing, reason: 'mirror: the chip filters');
    expect(find.text(_barbell), findsNothing);
  });

  testWidgets('the outgoing exercise is removed whatever its apostrophe',
      (tester) async {
    await _pump(tester, tier: 'bodyweight', library: [
      ..._library.where((r) => r['name'] != _current),
      _lib('E9', 'Wall  slide test', ['bodyweight']),
    ]);
    expect(find.text('Wall  slide test'), findsNothing);
    expect(find.text(_floor), findsOneWidget);
  });
}
