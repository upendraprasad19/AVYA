// Batch M2b Task 2 (docs/plans/2026-11-02-library-batch-m2b-tile-and-rows.md): the
// tile-led header of the FOCUSED, expanded card on a row with an animation. One
// 124 dp tile flush top-left, name / meta / LAST / TRY / icons beside it, an
// ENLARGE chip at the tile's bottom-right, the tile freezing whenever a route on
// its own navigator covers the screen. Since Part B the tile, the chip and every
// other card's 44 px still open the logging VIEWER (not the plate sheet), and the
// FORM & CUES panel is gone from a row with an animation (D4): the viewer carries
// it.
//
// Harness facts this file leans on (card_harness.dart, plan Step 0): the card
// host has no name-keyed ancestor (a swap reaches `didUpdateWidget`); every
// helper runs a FakeExerciseMediaRepository; the layout cases keep a CUE-LESS
// media row from Part A, when the panel still sat on media rows and its header
// overflowed under Ahem at 360 dp; flutter_test renders every glyph in Ahem, so
// real-font widths are read in the Chrome check, not here.
@Timeout(Duration(minutes: 6))
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/screens/active_workout/exercise_header_tile.dart';
import 'package:icanbefitter/features/train/screens/active_workout/exercise_media_viewer.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_animation_view.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_sheet.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_thumb.dart';

import '../../../helpers/fake_exercise_media_repository.dart';
import '../../../helpers/image_fixture.dart';
import 'card_harness.dart';

const _bench = 'Barbell Bench Press';
const _situp = 'Sit Up Probe';
const _calf = 'Standing Calf Raise';
const _cueless = 'Cue-less Bench';
const _longName = 'Cue-less Incline Dumbbell Bench Press Long';

/// Library rows. Every media row carries a coaching field, so "no FORM & CUES on
/// a media row" (D4) is not vacuous: the panel WOULD render if it were built.
/// The cue-less rows are the layout rows.
final _rows = <Map<String, dynamic>>[
  {
    'id': 'T_BENCH',
    'name': _bench,
    'media_slug': '0025-barbell-bench-press',
    'media_version': 1,
    'coaching_cues': ['Keep your wrists stacked'],
  },
  {
    'id': 'T_SITUP',
    'name': _situp,
    'media_slug': '0001-three-quarter-situp',
    'media_version': 1,
    'coaching_cues': ['Curl up slowly'],
  },
  {
    'id': 'T_CALF',
    'name': _calf,
    'coaching_cues': ['Pause at the top'],
  },
  {
    'id': 'T_CUELESS',
    'name': _cueless,
    'media_slug': '0025-barbell-bench-press',
    'media_version': 1,
  },
  {
    'id': 'T_LONG',
    'name': _longName,
    'media_slug': '0025-barbell-bench-press',
    'media_version': 1,
  },
];

/// A history with a suggested weight, so a TRY row builds (the default
/// `LastPerformanceData(60, 8)` has none).
const _perfWithTry =
    LastPerformanceData(lastWeight: 100, lastReps: 8, suggestedWeight: 102.5);

ActiveWorkoutData _seed(String name,
        {double? factor, Map<String, bool>? checked}) =>
    ActiveWorkoutData(
      exercises: [exercise(name: name)],
      sessionDetrainingFactor: factor ?? 1.0,
      checkedSets: checked ?? const {},
    );

Finder get _tile => find.byType(ExerciseHeaderTile);
Finder get _tileView =>
    find.descendant(of: _tile, matching: find.byType(ExerciseAnimationView));

/// The tile's own view (with a sheet open there are TWO views on screen).
bool _tileAutoplay(WidgetTester tester) =>
    tester.widget<ExerciseAnimationView>(_tileView).autoplay;

Finder get _viewer => find.byType(ExerciseMediaViewer);

/// Taps [door] and lets the viewer's 150 ms fade and one settling frame pass. NOT
/// `pumpAndSettle`: the viewer's own animation loops forever.
Future<void> _openViewer(WidgetTester tester, Finder door) async {
  await tester.tap(door);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

/// The back arrow, then enough frames for the reverse animation to start and end.
Future<void> _closeViewer(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('exercise-viewer-back')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// The table-header Row (first child is a 28 dp SizedBox); its right edge is the
/// card's inner right edge.
Finder get _headerRow => find.byWidgetPredicate((w) =>
    w is Row &&
    w.children.isNotEmpty &&
    w.children.first is SizedBox &&
    (w.children.first as SizedBox).width == 28);

SemanticsData _nodeOf(WidgetTester tester, Finder f) =>
    tester.getSemantics(f).getSemanticsData();

/// Settles a view that holds bytes: the decode needs the real zone.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  // The view cross-fades (250 ms) to its frozen face; a FadeTransition at opacity
  // 0 excludes its semantics, so run the clock past it.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Strips `//` comments, so a source-grep pin cannot be satisfied by a comment.
String _stripComments(String src) =>
    src.split('\n').map((l) => l.replaceFirst(RegExp(r'//.*$'), '')).join('\n');

void main() {
  tearDownAll(closeHive);

  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  group('which card shows the tile', () {
    testWidgets('focused + expanded + media: one tile, no thumb, no panel (D4)',
        (tester) async {
      await pumpCard(tester,
          seed: _seed(_bench),
          logMode: true,
          isFocused: true,
          libraryRows: _rows);
      expect(_tile, findsOneWidget);
      expect(find.byType(ExercisePlateThumb), findsNothing);
      expect(find.text('ENLARGE'), findsOneWidget,
          reason: "the chip is the tile's one visible door to the sheet");
      expect(find.text('FORM & CUES'), findsNothing,
          reason: 'D4: the panel moved into the viewer, this row has cues');
    });

    testWidgets('expanded but NOT focused (a superset partner): thumb, no tile',
        (tester) async {
      await pumpCard(tester,
          seed: _seed(_bench), logMode: true, libraryRows: _rows);
      expect(_tile, findsNothing);
      expect(find.byType(ExercisePlateThumb), findsOneWidget);
    });

    testWidgets('focused + move mode: no tile', (tester) async {
      await pumpCard(tester,
          seed: _seed(_bench),
          logMode: true,
          isFocused: true,
          moveModeActive: true,
          libraryRows: _rows);
      expect(_tile, findsNothing);
      expect(find.byType(ExercisePlateThumb), findsOneWidget);
    });

    testWidgets('focused + superset-grouping mode: tile and thumb take no tap',
        (tester) async {
      final handle = tester.ensureSemantics();
      var groupSelects = 0;
      await pumpCard(tester,
          seed: _seed(_bench),
          logMode: true,
          isFocused: true,
          isInSupersetGroupMode: true,
          onLongPressHeader: () => groupSelects++,
          libraryRows: _rows);
      expect(_tile, findsOneWidget);
      expect(find.text('ENLARGE'), findsNothing,
          reason: 'a tile with no tap shows no dead ENLARGE chip');
      await tester.tap(_tile);
      await tester.pumpAndSettle();
      expect(find.byType(ExercisePlateSheet), findsNothing,
          reason: 'C-f: the tap belongs to the group-select');
      expect(_viewer, findsNothing);
      expect(groupSelects, 1,
          reason: "the tile's tap falls through to the card's group-select "
              '(its outer detector calls the long-press-header handler)');
      expect(find.bySemanticsLabel(RegExp('^Enlarge')), findsNothing,
          reason: 'no Enlarge node: the tile has no tap to announce');
      handle.dispose();

      await pumpCard(tester,
          seed: _seed(_bench),
          logMode: true,
          isInSupersetGroupMode: true,
          libraryRows: _rows);
      await tester.tap(find.byType(ExercisePlateThumb));
      await tester.pumpAndSettle();
      expect(find.byType(ExercisePlateSheet), findsNothing,
          reason: 'the thumb takes no tap in grouping mode either');
      expect(_viewer, findsNothing);
    });

    testWidgets('focused + no media row: the thumb as today', (tester) async {
      await pumpCard(tester,
          seed: _seed(_calf),
          logMode: true,
          isFocused: true,
          libraryRows: _rows);
      expect(_tile, findsNothing);
      expect(find.byType(ExercisePlateThumb), findsOneWidget);
    });

    testWidgets('kill switch set: the thumb as today', (tester) async {
      await pumpCard(tester,
          seed: _seed(_bench),
          logMode: true,
          isFocused: true,
          animationsOff: true,
          libraryRows: _rows);
      expect(_tile, findsNothing);
      expect(find.byType(ExercisePlateThumb), findsOneWidget);
    });

    testWidgets('every exercise done: the tile does not autoplay',
        (tester) async {
      await pumpCard(tester,
          seed: _seed(_bench,
              checked: const {'0-0': true, '0-1': true, '0-2': true}),
          logMode: true,
          isFocused: true,
          libraryRows: _rows);
      expect(_tile, findsOneWidget);
      expect(_tileAutoplay(tester), isFalse);
    });

    testWidgets('ANOTHER exercise done, this one not: the tile still autoplays '
        '(all done means EVERY exercise)', (tester) async {
      await pumpCard(tester,
          seed: ActiveWorkoutData(
            exercises: [exercise(name: _bench), exercise(name: _situp)],
            checkedSets: const {'1-0': true, '1-1': true, '1-2': true},
          ),
          logMode: true,
          isFocused: true,
          libraryRows: _rows);
      expect(_tile, findsOneWidget);
      expect(_tileAutoplay(tester), isTrue,
          reason: 'after LOG the focus advances to an exercise that is not done: '
              'its tile must play');
    });

    testWidgets('a working session: the tile autoplays', (tester) async {
      await pumpCard(tester,
          seed: _seed(_bench),
          logMode: true,
          isFocused: true,
          libraryRows: _rows);
      expect(_tileAutoplay(tester), isTrue);
    });
  });

  group('the freeze: every door to the plate sheet', () {
    testWidgets('door 1: the tile opens the viewer and freezes under it',
        (tester) async {
      await pumpCard(tester,
          seed: _seed(_bench),
          logMode: true,
          isFocused: true,
          nestedNavigator: true,
          libraryRows: _rows);
      expect(_tileAutoplay(tester), isTrue);
      await _openViewer(tester, _tile);
      expect(_viewer, findsOneWidget);
      expect(find.byType(ExercisePlateSheet), findsNothing,
          reason: 'Part B: the tile opens the viewer, not the sheet');
      expect(_tileAutoplay(tester), isFalse, reason: 'frozen under the viewer');
      await _closeViewer(tester);
      expect(_viewer, findsNothing);
      expect(_tileAutoplay(tester), isTrue, reason: 'plays again after it');
    });

    testWidgets('a throw while the viewer opens does not lock the door: the '
        'next tap still reaches the focus callback and opens it',
        (tester) async {
      var focusCalls = 0;
      await pumpCard(tester,
          seed: _seed(_bench),
          logMode: true,
          isFocused: true,
          nestedNavigator: true,
          libraryRows: _rows,
          onFocus: () {
            focusCalls++;
            if (focusCalls == 1) throw StateError('focus callback failed');
          });
      // `_openPicture` is a discarded Future, so its throw is an UNCAUGHT async
      // error: catch it in a guarded zone around the tap.
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        await tester.tap(_tile);
        await tester.pump();
      }, (error, _) => uncaught.add(error));
      expect(focusCalls, 1);
      expect(uncaught, hasLength(1));
      expect(_viewer, findsNothing);
      await _openViewer(tester, _tile);
      expect(focusCalls, 2,
          reason: 'a stuck _viewerOpen would return before onFocus');
      expect(_viewer, findsOneWidget);
      await _closeViewer(tester);
      expect(_viewer, findsNothing);
    });

    testWidgets('door 2: the thumb of ANOTHER card on the real screen opens '
        'THAT card viewer, and the focused tile freezes under it',
        (tester) async {
      await pumpScreen(tester,
          exercises: [exercise(name: _bench), exercise(name: _situp)],
          libraryRows: _rows);
      expect(_tileAutoplay(tester), isTrue);
      final thumb = find.byType(ExercisePlateThumb).first;
      await tester.ensureVisible(thumb);
      await tester.pump();
      await _openViewer(tester, thumb);
      expect(_viewer, findsOneWidget);
      expect(find.byType(ExercisePlateSheet), findsNothing);
      expect(tester.widget<ExerciseMediaViewer>(_viewer).exerciseName, _situp,
          reason: 'D9: the viewer is the tapped card one');
      expect(_tileAutoplay(tester), isFalse,
          reason: 'the focus moved to the opened card; its tile is covered');
      await _closeViewer(tester);
      expect(_tileAutoplay(tester), isTrue);
    });

    testWidgets('a root-navigator dialog leaves the tile playing (nested '
        'Navigator, like the real Train branch)', (tester) async {
      await pumpCard(tester,
          seed: _seed(_bench),
          logMode: true,
          isFocused: true,
          nestedNavigator: true,
          libraryRows: _rows);
      unawaited(showDialog<void>(
        context: tester.element(_tile),
        builder: (_) => const AlertDialog(title: Text('dlg')),
      ));
      await tester.pumpAndSettle();
      expect(find.text('dlg'), findsOneWidget);
      expect(_tileAutoplay(tester), isTrue,
          reason: 'the dialog is on the ROOT navigator: the branch route is '
              'still current');
    });

    testWidgets('the same dialog on a single Navigator DOES cover the route '
        '(why the nested shape exists)', (tester) async {
      await pumpCard(tester,
          seed: _seed(_bench),
          logMode: true,
          isFocused: true,
          libraryRows: _rows);
      unawaited(showDialog<void>(
        context: tester.element(_tile),
        builder: (_) => const AlertDialog(title: Text('dlg')),
      ));
      await tester.pumpAndSettle();
      expect(find.text('dlg'), findsOneWidget);
      expect(_tileAutoplay(tester), isFalse,
          reason: 'one Navigator: the dialog covers the only route');
    });
  });

  group('swap, flag flip, focus', () {
    testWidgets('swap (same State): the tile follows the new exercise',
        (tester) async {
      final h = await pumpCard(tester,
          seed: _seed(_bench),
          logMode: true,
          isFocused: true,
          libraryRows: _rows);
      expect(tester.widget<ExerciseHeaderTile>(_tile).media.objectName,
          '0025-barbell-bench-press_v1.webp');
      h.container
          .read(activeWorkoutProvider.notifier)
          .swapExercise(0, exercise(name: _situp));
      await tester.pump();
      final tile = tester.widget<ExerciseHeaderTile>(_tile);
      expect(tile.exerciseName, _situp);
      expect(tile.media.objectName, '0001-three-quarter-situp_v1.webp',
          reason: 'the media is re-resolved on a name change');
    });

    testWidgets('swap on the real screen shows the new animation',
        (tester) async {
      final h = await pumpScreen(tester,
          exercises: [exercise(name: _bench), exercise(name: _calf)],
          libraryRows: _rows);
      expect(tester.widget<ExerciseHeaderTile>(_tile).exerciseName, _bench);
      h.notifier.swapExercise(0, exercise(name: _situp));
      await tester.pump();
      await tester.pump();
      expect(tester.widget<ExerciseHeaderTile>(_tile).exerciseName, _situp);
    });

    testWidgets('flag flip (same State): thumb while off, tile again when on',
        (tester) async {
      final h = await pumpCard(tester,
          seed: _seed(_bench),
          logMode: true,
          isFocused: true,
          libraryRows: _rows);
      final notifier = h.container.read(activeWorkoutProvider.notifier);
      expect(_tile, findsOneWidget);

      await tester.runAsync(() => HiveService.instance.configBox
          .put('disable_exercise_animations', true));
      notifier.toggleWarmUp(0, 0); // a provider change forces the rebuild
      await tester.pump();
      expect(_tile, findsNothing, reason: 'animations switched off mid-session');
      expect(find.byType(ExercisePlateThumb), findsOneWidget);

      await tester.runAsync(() =>
          HiveService.instance.configBox.delete('disable_exercise_animations'));
      notifier.toggleWarmUp(0, 0);
      await tester.pump();
      expect(_tile, findsOneWidget, reason: 'and on again');
    });

    testWidgets('focus retention: a focused set field survives the header '
        'toggling between tile and thumb', (tester) async {
      final h = await pumpCard(tester,
          seed: _seed(_bench),
          logMode: true,
          isFocused: true,
          libraryRows: _rows);
      tester.widget<TextField>(fieldAt(0)).focusNode!.requestFocus();
      await tester.pump();
      expect(hasFocus(tester, 0), isTrue, reason: 'precondition');
      final before = tester.element(fieldAt(0));

      h.focused.value = false;
      await tester.pump();
      expect(_tile, findsNothing);
      expect(find.byType(ExercisePlateThumb), findsOneWidget);
      expect(identical(tester.element(fieldAt(0)), before), isTrue,
          reason: 'the set rows keep their elements across the toggle');
      expect(hasFocus(tester, 0), isTrue);

      h.focused.value = true;
      await tester.pump();
      expect(_tile, findsOneWidget);
      expect(identical(tester.element(fieldAt(0)), before), isTrue);
      expect(hasFocus(tester, 0), isTrue);
    });
  });

  group('TRY gate (never shame): both header layouts', () {
    for (final focused in [false, true]) {
      final layout = focused ? 'tile' : 'thumb';
      testWidgets('$layout layout: TRY hidden under a session cut, shown '
          'without one', (tester) async {
        await pumpCard(tester,
            seed: _seed(_bench, factor: 0.9),
            logMode: true,
            isFocused: focused,
            lastPerf: _perfWithTry,
            libraryRows: _rows);
        expect(find.textContaining('LAST:'), findsOneWidget);
        expect(find.textContaining('TRY:'), findsNothing,
            reason: 'a TRY directive would contradict the reduced prefill');

        await pumpCard(tester,
            seed: _seed(_bench, factor: 1.0),
            logMode: true,
            isFocused: focused,
            lastPerf: _perfWithTry,
            libraryRows: _rows);
        expect(find.textContaining('TRY:'), findsOneWidget,
            reason: 'precondition: the fixture builds a TRY row');
      });
    }
  });

  group('layout', () {
    testWidgets('360 dp: the tile is 124 x 124, icons stay in the column, the '
        'ENLARGE chip sits bottom-right', (tester) async {
      tester.view.physicalSize = const Size(360, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpCard(tester,
          seed: _seed(_cueless),
          logMode: true,
          isFocused: true,
          lastPerf: _perfWithTry,
          libraryRows: _rows);
      expect(tester.takeException(), isNull);
      final tile = tester.getRect(_tile);
      expect(tile.size, const Size(124, 124));
      expect(find.textContaining('TRY:'), findsOneWidget,
          reason: 'precondition: a TRY row is in the column');

      final edge = tester.getTopRight(_headerRow).dx;
      final swap = tester.getRect(find.byIcon(Icons.swap_horiz));
      expect(swap.left, greaterThanOrEqualTo(tile.right),
          reason: 'the icon is in the column, right of the tile');
      expect(swap.right, lessThanOrEqualTo(edge + 1));

      final chip = tester.getRect(find
          .ancestor(of: find.text('ENLARGE'), matching: find.byType(DecoratedBox))
          .first);
      expect(chip.center.dx, greaterThan(tile.center.dx),
          reason: 'D5: the chip\'s centre is in the tile\'s right half');
      expect(chip.center.dy, greaterThan(tile.center.dy),
          reason: '... and in its bottom half');
      expect(tile.contains(chip.center), isTrue);
    });

    testWidgets('the PICTURE inside the tile is 124 x 124 too, not just its frame',
        (tester) async {
      await pumpCard(tester,
          seed: _seed(_bench),
          logMode: true,
          isFocused: true,
          libraryRows: _rows);
      expect(tester.getSize(_tile), const Size(124, 124));
      expect(tester.getSize(_tileView), const Size(124, 124),
          reason: 'the animation view fills the frame');
      // The frame's tight constraints force the view to 124 whatever it is told,
      // so the laid-out box cannot show a wrong `size`; its DECODE width follows
      // this value, and a smaller one decodes the picture soft and stretches it.
      expect(tester.widget<ExerciseAnimationView>(_tileView).size, kHeaderTileSize);
    });

    testWidgets('320 dp at 1.3x text with a long name: no overflow and the '
        'tile is still 124 x 124', (tester) async {
      tester.view.physicalSize = const Size(320, 2000);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpCard(tester,
          seed: _seed(_longName),
          logMode: true,
          isFocused: true,
          lastPerf: _perfWithTry,
          libraryRows: _rows);
      expect(tester.takeException(), isNull,
          reason: 'no RenderFlex overflow in the header column');
      expect(find.textContaining('TRY:'), findsOneWidget,
          reason: 'precondition: a TRY row, the line that must ellipsise');
      expect(tester.getSize(_tile), const Size(124, 124),
          reason: 'a column taller than the tile must not stretch it');
      final column = find
          .byWidgetPredicate((w) =>
              w is Column && w.mainAxisAlignment == MainAxisAlignment.spaceBetween)
          .first;
      expect(tester.getSize(column).height, greaterThan(124),
          reason: 'precondition: the column IS taller here, or the '
              'stretch case cannot bite');
    });

    testWidgets('a long press on the tile or the name reaches the header '
        'handler, not the sheet', (tester) async {
      var held = 0;
      await pumpCard(tester,
          seed: _seed(_bench),
          logMode: true,
          isFocused: true,
          onLongPressHeader: () => held++,
          libraryRows: _rows);
      await tester.longPress(_tile);
      await tester.pump();
      expect(held, 1);
      await tester.longPress(find.text(_bench));
      await tester.pump();
      expect(held, 2);
      expect(find.byType(ExercisePlateSheet), findsNothing);
      expect(_viewer, findsNothing);
    });
  });

  group('the real screen', () {
    testWidgets('a superset: exactly one view plays, and the tile follows the '
        'focus', (tester) async {
      await pumpScreen(tester,
          exercises: [
            exercise(name: _bench).copyWith(supersetGroup: () => 0),
            exercise(name: _situp).copyWith(supersetGroup: () => 0),
          ],
          libraryRows: _rows);
      expect(find.byType(ExerciseAnimationView), findsOneWidget,
          reason: 'the partner is expanded but unfocused: a thumb, no view');
      expect(tester.widget<ExerciseAnimationView>(find.byType(ExerciseAnimationView))
              .autoplay,
          isTrue);
      expect(tester.widget<ExerciseHeaderTile>(_tile).exerciseName, _bench);

      final partner = find.text(_situp);
      await tester.ensureVisible(partner);
      await tester.pump();
      await tester.tap(partner);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(tester.widget<ExerciseHeaderTile>(_tile).exerciseName, _situp,
          reason: 'tapping the partner\'s header moves the tile to it');
      expect(find.byType(ExerciseAnimationView), findsOneWidget);
    });
  });

  group('semantics', () {
    testWidgets('one Enlarge node; a frozen tile has a SEPARATE play node',
        (tester) async {
      final handle = tester.ensureSemantics();
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpCard(tester,
          seed: _seed(_bench),
          logMode: true,
          isFocused: true,
          mediaBytes: Uint8List.fromList(kTinyPng),
          libraryRows: _rows);
      await _settle(tester);

      final node = _nodeOf(tester, _tile);
      expect(node.label, 'Enlarge $_bench',
          reason: 'EXACTLY the label, not merged with header text');
      expect(node.hasAction(SemanticsAction.tap), isTrue);
      expect(node.hasAction(SemanticsAction.longPress), isTrue);

      expect(find.text('PLAY'), findsOneWidget,
          reason: 'reduced motion: the view is frozen on its first frame');
      final play = tester.getSemantics(find.text('PLAY'));
      expect(play.id, isNot(tester.getSemantics(_tile).id),
          reason: 'the pill is its own node: its taps are not the tile\'s');
      expect(play.getSemanticsData().label, contains('Play'));
      expect(play.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });
  });

  group('semantic actions reach the right handlers', () {
    testWidgets('activate opens the viewer; long press starts grouping, never '
        'the other way round', (tester) async {
      final handle = tester.ensureSemantics();
      var held = 0;
      await pumpCard(tester,
          seed: _seed(_bench),
          logMode: true,
          isFocused: true,
          onLongPressHeader: () => held++,
          libraryRows: _rows);
      final node = find.semantics.byLabel('Enlarge $_bench');
      expect(node, findsOneWidget);

      tester.semantics.longPress(node);
      await tester.pump();
      expect(held, 1, reason: "the screen reader's long press is the header's");
      expect(find.byType(ExercisePlateSheet), findsNothing);
      expect(_viewer, findsNothing);

      tester.semantics.tap(node);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(_viewer, findsOneWidget,
          reason: "the screen reader's activate opens the logging viewer");
      expect(find.byType(ExercisePlateSheet), findsNothing);
      expect(held, 1);
      handle.dispose();
    });
  });

  group('a mode change keeps the playing view', () {
    testWidgets('onEnlarge / onLongPress turning null and back never remounts '
        'the animation view', (tester) async {
      await ensureHive(tester);
      await seedLibrary(tester);
      Future<void> pumpTile({VoidCallback? onEnlarge, VoidCallback? onLongPress}) =>
          tester.pumpWidget(ProviderScope(
            overrides: mediaOverrides(FakeExerciseMediaRepository()),
            child: MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: ExerciseHeaderTile(
                    media: const ExerciseMedia(
                        slug: '0025-barbell-bench-press', version: 1),
                    exerciseName: _bench,
                    autoplay: true,
                    onEnlarge: onEnlarge,
                    onLongPress: onLongPress,
                  ),
                ),
              ),
            ),
          ));
      void noop() {}
      await pumpTile(onEnlarge: noop, onLongPress: noop);
      final before = tester.state(_tileView);
      // Superset grouping (no enlarge), move mode (neither), and back again: the
      // card flips these on the SAME focused card while the animation plays.
      for (final handlers in <(VoidCallback?, VoidCallback?)>[
        (null, noop),
        (null, null),
        (noop, null),
        (noop, noop),
      ]) {
        await pumpTile(onEnlarge: handlers.$1, onLongPress: handlers.$2);
        expect(identical(tester.state(_tileView), before), isTrue,
            reason: 'enlarge ${handlers.$1 != null}, long press '
                '${handlers.$2 != null}: the view State must survive, or the '
                'animation restarts from the still');
      }
    });
  });

  group('presence pins (comments stripped)', () {
    final card = _stripComments(File(
            'lib/features/train/screens/active_workout/exercise_card.dart')
        .readAsStringSync());
    final screen = _stripComments(
        File('lib/features/train/screens/active_workout/screen.dart')
            .readAsStringSync());

    test('the build site derives isFocused from the focused index, not '
        'from isExpanded', () {
      final site = screen.indexOf('_ExerciseCard(');
      expect(site, greaterThan(0));
      final args = screen.substring(site, site + 1400);
      expect(args, contains('isFocused: exIdx == _effectiveFocusedIndex(data)'));
      expect(args, isNot(contains('isFocused: isExpanded')));
    });

    test('_media is assigned in initState and didUpdateWidget only; '
        'resolveMedia( never in build; the freeze uses isCurrentOf', () {
      final build = card.substring(
          card.indexOf('Widget build(BuildContext context) {'),
          card.indexOf('VoidCallback? get _headerTap'));
      expect(build, isNot(contains('resolveMedia(')),
          reason: 'a local resolveMedia in build would pass a "never assign '
              '_media in build" pin');
      expect(RegExp(r'\b_media\s*=').allMatches(build), isEmpty);
      expect(RegExp(r'\b_media\s*=\s*resolveMedia\(').allMatches(card).length,
          2,
          reason: 'exactly initState and didUpdateWidget');
      expect(build, contains('ModalRoute.isCurrentOf(context)'));
      expect(build, isNot(contains('ModalRoute.of(')),
          reason: 'of() would subscribe every card to every route aspect');
    });
  });
}

// Unused import guard for WardroomCopy: the labels are asserted by value above.
// ignore: unused_element
const _copyUsed = WardroomCopy.activeEnlargeChip;
