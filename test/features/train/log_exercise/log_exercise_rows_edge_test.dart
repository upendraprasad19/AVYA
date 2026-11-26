// Batch M2b Task 1 (docs/plans/2026-11-02-library-batch-m2b-tile-and-rows.md):
// in LOG mode the set rows reach the card's right edge on EVERY card. The empty
// check column is gone, a logged set turns its number tile into a tick, and the
// up / same / down arrow moves into the KG box. The per-set path keeps its
// check column.
//
// Finder rules: every row's hintText also reads KG / REPS (InputDecorator keeps
// it in the tree), so header finders are scoped to the table-header Row (the
// only Row whose first child is a 28 dp SizedBox), and header cells are
// Expanded(Center(Text)), so the CELL (the Center) is measured, never the Text.
@Timeout(Duration(minutes: 4))
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/widgets/set_input_row.dart';

import 'card_harness.dart';

/// The table-header Row (`_tableHeaderLabels`): its first child is the 28 dp
/// set-badge spacer. SetInputRow's own Row starts with a GestureDetector.
Finder get headerRow => find.byWidgetPredicate((w) =>
    w is Row &&
    w.children.isNotEmpty &&
    w.children.first is SizedBox &&
    (w.children.first as SizedBox).width == 28);

/// The header Row's right edge, the reference for every "reaches the edge" case.
double headerRight(WidgetTester tester) =>
    tester.getTopRight(headerRow).dx;

/// Header cells (`Expanded(Center(Text))`), scoped to the header Row.
Finder get headerCells =>
    find.descendant(of: headerRow, matching: find.byType(Center));

/// Text fields per set row, by logging type.
const _fieldsPerRow = <String, int>{
  'weight_reps': 2,
  'weighted_bodyweight': 2,
  'bodyweight_reps': 1,
  'timed': 1,
  'cardio': 2,
  'distance': 2,
};

SemanticsData nodeOf(WidgetTester tester, Finder f) =>
    tester.getSemantics(f).getSemanticsData();

void main() {
  tearDownAll(closeHive);

  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  group('LOG mode: rows reach the card edge, every logging type', () {
    for (final type in _fieldsPerRow.keys) {
      testWidgets('$type: last field and last header cell end at the edge',
          (tester) async {
        await pumpCard(tester,
            seed: ActiveWorkoutData(exercises: [exercise(type: type)]),
            logMode: true);
        final edge = headerRight(tester);
        final per = _fieldsPerRow[type]!;
        final fields = find.byType(TextField);
        expect(fields, findsNWidgets(per * 3), reason: '3 sets of $per fields');
        for (var row = 0; row < 3; row++) {
          final last = tester.getTopRight(fields.at(row * per + per - 1)).dx;
          expect((last - edge).abs(), lessThanOrEqualTo(1.0),
              reason: '$type row ${row + 1}: last field right edge $last vs '
                  'header right edge $edge');
        }
        final lastCell = tester.getTopRight(headerCells.last).dx;
        expect((lastCell - edge).abs(), lessThanOrEqualTo(1.0),
            reason: '$type: the last header cell ends at the edge, no trailing '
                'check-column cell');
        expect(find.descendant(of: headerRow, matching: find.text('✓')),
            findsNothing);
      });
    }
  });

  group('LOG mode: logged set', () {
    testWidgets('tick in the set tile, arrow in the KG box, labels',
        (tester) async {
      final handle = tester.ensureSemantics();
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      expect(find.byIcon(Icons.check), findsNothing, reason: 'nothing logged');
      expect(find.text('→'), findsNothing);

      h.container.read(activeWorkoutProvider.notifier).logSets(0, {0});
      await tester.pump();

      final row1 = find.byType(SetInputRow).at(0);
      final tick = find.descendant(of: row1, matching: find.byIcon(Icons.check));
      expect(tick, findsOneWidget, reason: 'one tick, inside set 1');
      // Inside the 28 dp tile at the row's left, not in a trailing check slot.
      expect(tester.getTopLeft(tick).dx - tester.getTopLeft(row1).dx,
          lessThan(28.0));
      expect(find.byIcon(Icons.check), findsOneWidget, reason: 'sets 2, 3 open');
      final tile = find
          .ancestor(of: tick, matching: find.byType(Container))
          .first;
      expect(
          (tester.widget<Container>(tile).decoration! as BoxDecoration).color,
          AppColors.accent,
          reason: 'a working set ticks in accent');
      expect(nodeOf(tester, tick).label,
          WardroomCopy.activeSetLoggedLabelTemplate.replaceAll('{n}', '1'),
          reason: 'the tick tile carries "Set 1, logged"');

      // The arrow: a Stack SIBLING of set 1's KG TextField, set 1 only.
      expect(find.text('→'), findsOneWidget);
      final stack = find.ancestor(of: fieldAt(0), matching: find.byType(Stack));
      expect(stack, findsWidgets);
      expect(find.descendant(of: stack.first, matching: find.text('→')),
          findsOneWidget,
          reason: 'the arrow sits under the nearest Stack of set 1\'s KG box');
      final box = tester.getRect(fieldAt(0));
      final arrow = tester.getRect(find.text('→'));
      expect((arrow.center.dy - box.center.dy).abs(), lessThanOrEqualTo(1.0),
          reason: 'vertically centred in the KG box');
      expect(((box.right - arrow.right) - 9).abs(), lessThanOrEqualTo(1.0),
          reason: '9 dp inside the box\'s right edge');
      handle.dispose();
    });

    testWidgets('the arrow overlay is inert: a tap on it reaches the KG box and '
        'its glyph is not part of the field\'s semantics', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      h.container.read(activeWorkoutProvider.notifier).logSets(0, {0});
      await tester.pump();
      expect(find.text('→'), findsOneWidget, reason: 'precondition: the arrow shows');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(hasFocus(tester, 0), isFalse, reason: 'precondition: KG box not focused');

      await tester.tapAt(tester.getCenter(find.text('→')));
      await tester.pump();
      expect(hasFocus(tester, 0), isTrue,
          reason: 'IgnorePointer: the glyph never swallows a tap meant for the box');
      expect(nodeOf(tester, fieldAt(0)).label, isNot(contains('→')),
          reason: 'ExcludeSemantics: a screen reader does not read the arrow glyph '
              'into the KG field');
      handle.dispose();
    });

    testWidgets('a logged warm-up ticks in warn and says so', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(
              exercises: [exercise()], warmUpSets: const {'0-0': true}),
          logMode: true);
      expect(find.text('W'), findsOneWidget, reason: 'open warm-up shows W');
      h.container.read(activeWorkoutProvider.notifier).logSets(0, {0});
      await tester.pump();
      final tick = find.descendant(
          of: find.byType(SetInputRow).at(0), matching: find.byIcon(Icons.check));
      expect(tick, findsOneWidget);
      final tile = find.ancestor(of: tick, matching: find.byType(Container)).first;
      expect(
          (tester.widget<Container>(tile).decoration! as BoxDecoration).color,
          AppColors.warn,
          reason: 'C-i: a logged warm-up keeps a warn-tinted tick');
      expect(find.text('W'), findsNothing, reason: 'the tick replaces the W');
      expect(nodeOf(tester, tick).label,
          WardroomCopy.activeWarmUpSetLoggedLabelTemplate.replaceAll('{n}', '1'));
      handle.dispose();
    });

    testWidgets('focus across logging: element and focus survive log and re-open',
        (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      final notifier = h.container.read(activeWorkoutProvider.notifier);
      tester.widget<TextField>(fieldAt(0)).focusNode!.requestFocus();
      await tester.pump();
      expect(hasFocus(tester, 0), isTrue, reason: 'precondition: focused');
      final before = tester.element(fieldAt(0));

      notifier.logSets(0, {0});
      await tester.pump();
      expect(find.text('→'), findsOneWidget, reason: 'the logged state rendered');
      expect(identical(tester.element(fieldAt(0)), before), isTrue,
          reason: 'logging must not remount the KG TextField');
      expect(hasFocus(tester, 0), isTrue);

      notifier.unlogSets(0, {0},
          exerciseName: h.state.exercises[0].name, reopened: true);
      await tester.pump();
      expect(find.text('→'), findsNothing, reason: 'the open state rendered');
      expect(identical(tester.element(fieldAt(0)), before), isTrue,
          reason: 're-opening must not remount the KG TextField');
      expect(hasFocus(tester, 0), isTrue);
    });
  });

  group('per-set path (logMode: false) keeps its check column', () {
    testWidgets('check column, check header cell and 5 interactive tiles',
        (tester) async {
      await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: false);
      final edge = headerRight(tester);
      // 3 per-set check tiles + the 28 px `-` and `+` set buttons.
      expect(interactiveCheckTiles, findsNWidgets(5));
      for (var row = 0; row < 3; row++) {
        final last = tester.getTopRight(fieldAt(row * 2 + 1)).dx;
        expect(edge - last, greaterThanOrEqualTo(34.0),
            reason: 'row ${row + 1}: the check slot (28) + gap (6) stay');
      }
      expect(find.descendant(of: headerRow, matching: find.text('✓')),
          findsOneWidget,
          reason: 'the per-set header keeps its tick cell');
      expect(find.text('→'), findsNothing);
    });

    testWidgets('a checked set and a checked warm-up keep their number tile: '
        'the tick lives in the check slot only', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCard(tester,
          seed: ActiveWorkoutData(
            exercises: [exercise()],
            checkedSets: const {'0-0': true, '0-1': true},
            warmUpSets: const {'0-1': true},
          ),
          logMode: false);
      final row1 = find.byType(SetInputRow).at(0);
      final row2 = find.byType(SetInputRow).at(1);
      expect(find.descendant(of: row1, matching: find.text('1')), findsOneWidget,
          reason: 'a checked working set still shows its number');
      expect(find.descendant(of: row2, matching: find.text('W')), findsOneWidget,
          reason: 'a checked warm-up still shows its W');
      expect(find.descendant(of: row1, matching: find.byIcon(Icons.check)),
          findsOneWidget,
          reason: 'one tick per checked row: the check slot, not the number tile');
      expect(find.descendant(of: row2, matching: find.byIcon(Icons.check)),
          findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r', logged$')), findsNothing,
          reason: 'the "Set n, logged" label belongs to LOG mode only');
      handle.dispose();
    });
  });
}
