// Batch M2b Part B, Task B2: the logging viewer behind ENLARGE and the 44 px
// still. Plan docs/plans/2026-11-03-library-batch-m2b-viewer.md (B2 Step 1).
//
// The viewer is pushed on the same single Navigator `pumpScreen` builds, which
// is faithful: the screen's route stops being current exactly as under the
// branch navigator in the app. The covered card is ON stage under the
// non-opaque route, so viewer finders scope with `_inViewer` and the CARD's
// boxes are read OUTSIDE the viewer, under `ActiveWorkoutScreen`.
//
// Same-frame events are DIRECT callback invocations: `tester.tap` cannot deliver
// two events in one frame (the first tap's route already ignores pointers).
@Timeout(Duration(minutes: 6))
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/screens/active_workout/exercise_header_tile.dart';
import 'package:icanbefitter/features/train/screens/active_workout/exercise_media_viewer.dart';
import 'package:icanbefitter/features/train/screens/active_workout/screen.dart';
import 'package:icanbefitter/features/train/services/log_exercise_flags.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_animation_view.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_sheet.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_thumb.dart';

import 'card_harness.dart';

const _bench = 'Barbell Bench Press';
const _situp = 'Sit Up Probe';
const _calf = 'Standing Calf Raise';
const _full = 'Viewer Full Probe';
const _longName = 'Cue-less Incline Dumbbell Bench Press Long Name Probe Row';

final _rows = <Map<String, dynamic>>[
  {
    'id': 'V_BENCH',
    'name': _bench,
    'media_slug': '0025-barbell-bench-press',
    'media_version': 1,
    'coaching_cues': ['Keep your wrists stacked'],
  },
  {
    'id': 'V_SITUP',
    'name': _situp,
    'media_slug': '0001-three-quarter-situp',
    'media_version': 1,
    'coaching_cues': ['Curl up slowly'],
  },
  {
    'id': 'V_CALF',
    'name': _calf,
    'coaching_cues': ['Pause at the top'],
  },
  {
    'id': 'V_FULL',
    'name': _full,
    'media_slug': '0025-barbell-bench-press',
    'media_version': 1,
    'coaching_cues': ['Drive through the floor'],
    'common_mistakes': ['Bouncing the bar'],
    'breathing_cue': 'Exhale on the press',
    'warmup_protocol': 'Two light sets first',
  },
  {
    'id': 'V_LONG',
    'name': _longName,
    'media_slug': '0025-barbell-bench-press',
    'media_version': 1,
  },
];

class _CompletableNotifier extends SeededNotifier {
  _CompletableNotifier(super.seed);
  void markComplete() => state = state.copyWith(isComplete: true);
}

Finder get _viewer => find.byType(ExerciseMediaViewer);
Finder _inViewer(Finder f) => find.descendant(of: _viewer, matching: f);
Finder get _viewerFields => _inViewer(find.byType(TextField));
Finder get _cardFields => find.descendant(
    of: find.byType(ActiveWorkoutScreen), matching: find.byType(TextField));
Finder get _tile => find.byType(ExerciseHeaderTile);
Finder get _back => find.byKey(const Key('exercise-viewer-back'));
Finder get _animation => find.byKey(const Key('exercise-viewer-animation'));
Finder _logDetector(String label) => find
    .ancestor(of: _inViewer(find.text(label)), matching: find.byType(GestureDetector))
    .first;

TextEditingController _ctrl(WidgetTester tester, Finder f) =>
    tester.widget<TextField>(f).controller!;

/// Taps the focused card's tile and lets the 150 ms fade and one settling
/// frame pass (the route's `opaque` flag takes effect when the push animation
/// ends and the Overlay rebuilds a frame later).
Future<void> _openViewer(WidgetTester tester, {Finder? door}) async {
  await tester.tap(door ?? _tile);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  expect(_viewer, findsOneWidget);
}

/// A pop started by a post-frame callback (the self-closing cases) begins its
/// reverse animation on the NEXT frame, whose first tick has elapsed zero: it
/// needs one more frame past the 150 ms before the route leaves the overlay.
Future<void> _closeSettled(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void _view(WidgetTester tester, double w, double h,
    {double keyboard = 0, double top = 0, double bottom = 0, double scale = 1}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(w, h);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  tester.view.viewPadding = FakeViewPadding(top: top, bottom: bottom);
  // A real engine reports `padding.bottom = max(0, viewPadding.bottom -
  // viewInsets.bottom)`: 0 while the keyboard is up.
  final padBottom = (bottom - keyboard) > 0 ? bottom - keyboard : 0.0;
  tester.view.padding = FakeViewPadding(top: top, bottom: padBottom);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

void main() {
  tearDownAll(closeHive);

  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  group('route flags', () {
    testWidgets('the route is non-opaque and keeps state', (tester) async {
      await pumpScreen(tester, exercises: [exercise(name: _bench)], libraryRows: _rows);
      final route = ExerciseMediaViewer.show(
        tester.element(find.byType(ActiveWorkoutScreen)),
        exerciseName: _bench,
        exerciseIndex: 0,
        media: tester.widget<ExerciseHeaderTile>(_tile).media,
      );
      await tester.pump();
      expect(route.opaque, isFalse);
      expect(route.maintainState, isTrue);
      expect(route.transitionDuration, const Duration(milliseconds: 150));
      expect(route.reverseTransitionDuration, const Duration(milliseconds: 150));
      await unmountScreen(tester);
    });

    testWidgets('reduced motion: no fade in or out, the viewer is there after '
        'one frame', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpScreen(tester, exercises: [exercise(name: _bench)], libraryRows: _rows);
      final route = ExerciseMediaViewer.show(
        tester.element(find.byType(ActiveWorkoutScreen)),
        exerciseName: _bench,
        exerciseIndex: 0,
        media: tester.widget<ExerciseHeaderTile>(_tile).media,
      );
      await tester.pump();
      expect(route.transitionDuration, Duration.zero);
      expect(route.reverseTransitionDuration, Duration.zero);
      expect(_viewer, findsOneWidget);
      await tester.tap(_back);
      await tester.pump();
      await tester.pump();
      expect(_viewer, findsNothing, reason: 'no reverse animation to wait out');
      await unmountScreen(tester);
    });
  });

  group('open, D4 and the second input surface', () {
    testWidgets('the tile opens the viewer: animation, rows, LOG and the four '
        'cue sections; the card shows no FORM & CUES', (tester) async {
      await pumpScreen(tester, exercises: [exercise(name: _full)], libraryRows: _rows);
      expect(find.text('FORM & CUES'), findsNothing,
          reason: 'D4: a row with an animation has no panel');
      await _openViewer(tester);
      expect(_animation, findsOneWidget);
      expect(_viewerFields.evaluate().length, 6);
      expect(_inViewer(find.text('LOG 3 SETS ✓')), findsOneWidget);
      for (final t in ['FORM', 'COMMON MISTAKES', 'BREATHING', 'WARM-UP']) {
        expect(_inViewer(find.text(t)), findsOneWidget, reason: t);
      }
      expect(_inViewer(find.text('Drive through the floor')), findsOneWidget);
      expect(_inViewer(find.text('Two light sets first')), findsOneWidget);
      await unmountScreen(tester);
    });

    testWidgets('a media-less row keeps the FORM & CUES panel', (tester) async {
      await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise(name: _calf)]),
          logMode: true,
          isFocused: true,
          libraryRows: _rows);
      expect(find.text('FORM & CUES'), findsOneWidget);
    });

    testWidgets('a value typed in the viewer is the card box value',
        (tester) async {
      await pumpScreen(tester,
          exercises: [exercise(name: _bench)],
          libraryRows: _rows,
          lastPerf: const LastPerformanceData());
      await _openViewer(tester);
      await tester.enterText(_viewerFields.at(0), '77');
      await tester.pump();
      expect(_ctrl(tester, _cardFields.at(0)).text, '77');
      expect(_ctrl(tester, _cardFields.at(2)).text, '77', reason: 'mirror');
      await unmountScreen(tester);
    });

    testWidgets('+ and - through the REAL pushed route: rows, stepper and the '
        'LOG label follow, the card stays in step', (tester) async {
      await pumpScreen(tester, exercises: [exercise(name: _bench)], libraryRows: _rows);
      await _openViewer(tester);
      await tester.tap(_inViewer(find.byIcon(Icons.add)));
      await tester.pump();
      await tester.pump();
      expect(_viewerFields.evaluate().length, 8);
      expect(_inViewer(find.text('LOG 4 SETS ✓')), findsOneWidget);
      // Two "4"s: the stepper digit and the new fourth row's number tile.
      expect(_inViewer(find.text('4')), findsNWidgets(2));
      expect(_cardFields.evaluate().length, 8);
      await tester.tap(_inViewer(find.byIcon(Icons.remove)));
      await tester.pump();
      expect(_viewerFields.evaluate().length, 6,
          reason: 'the count guard shows 3 rows in the first frame');
      expect(_inViewer(find.text('4')), findsNothing,
          reason: 'neither the stepper nor a fourth row shows a 4 any more');
      expect(tester.takeException(), isNull);
      await tester.pump();
      expect(_cardFields.evaluate().length, 6);
      await unmountScreen(tester);
    });
  });

  group('LOG and back', () {
    testWidgets('LOG logs the exercise, pops once, and the next exercise is '
        'the expanded one', (tester) async {
      final h = await pumpScreen(tester,
          exercises: [exercise(name: _bench), exercise(name: _situp)],
          libraryRows: _rows);
      await _openViewer(tester);
      await tapWithRealIo(tester, _inViewer(find.text('LOG 3 SETS ✓')));
      await _closeSettled(tester);
      expect(h.state.isExerciseDone(0), isTrue);
      expect(_viewer, findsNothing);
      expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
      expect(tester.widget<ExerciseHeaderTile>(_tile).exerciseName, _situp);
      await unmountScreen(tester);
    });

    testWidgets('UNDO after a viewer LOG: the toast is on the screen and UNDO '
        'puts the exercise back', (tester) async {
      final h = await pumpScreen(tester,
          exercises: [exercise(name: _bench), exercise(name: _situp)],
          libraryRows: _rows);
      await _openViewer(tester);
      await tapWithRealIo(tester, _inViewer(find.text('LOG 3 SETS ✓')));
      await _closeSettled(tester);
      expect(h.state.isExerciseDone(0), isTrue);
      expect(find.text('UNDO'), findsOneWidget,
          reason: 'the in-tree toast is armed by the same LOG path');
      // A tap inside the LOG input guard (`kLogInputGuard`, a real-time
      // stopwatch) is ignored by design: wait it out.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 700)));
      await tapWithRealIo(tester, find.text('UNDO'));
      expect(h.state.isExerciseDone(0), isFalse);
      await unmountScreen(tester);
    });

    testWidgets('a blocked LOG keeps the viewer open and focuses the VIEWER '
        'box', (tester) async {
      final h = await pumpScreen(tester,
          exercises: [exercise(name: _bench)],
          libraryRows: _rows,
          lastPerf: const LastPerformanceData());
      await _openViewer(tester);
      await tester.tap(_inViewer(find.text('Add weight')));
      await tester.pump();
      expect(_viewer, findsOneWidget);
      expect(tester.widget<TextField>(_viewerFields.at(0)).focusNode!.hasFocus,
          isTrue);
      expect(h.state.isExerciseDone(0), isFalse);
      await unmountScreen(tester);
    });

    testWidgets('back pops without logging; the typed text survives; no field '
        'keeps focus', (tester) async {
      final h = await pumpScreen(tester,
          exercises: [exercise(name: _bench)],
          libraryRows: _rows,
          lastPerf: const LastPerformanceData());
      await _openViewer(tester);
      await tester.enterText(_viewerFields.at(0), '66');
      await tester.pump();
      await tester.tap(_back);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.context?.widget,
          isNot(isA<EditableText>()),
          reason: 'the keyboard goes down at once (a behaviour pin)');
      await _closeSettled(tester);
      expect(_viewer, findsNothing);
      expect(h.state.isExerciseDone(0), isFalse);
      expect(_ctrl(tester, _cardFields.at(0)).text, '66');
      await unmountScreen(tester);
    });

    testWidgets('(t1) a CARD field focused when the still is tapped: after '
        'the pop no field has focus', (tester) async {
      await pumpScreen(tester, exercises: [exercise(name: _bench)], libraryRows: _rows);
      await tester.tap(_cardFields.at(0));
      await tester.pump();
      expect(tester.widget<TextField>(_cardFields.at(0)).focusNode!.hasFocus, isTrue);
      await _openViewer(tester);
      await tester.tap(_back);
      await _closeSettled(tester);
      expect(tester.widget<TextField>(_cardFields.at(0)).focusNode!.hasFocus, isFalse,
          reason: 'popping the viewer must not restore focus to a card field');
      await unmountScreen(tester);
    });

    testWidgets('LOGGED inside the viewer re-opens in place and does not pop',
        (tester) async {
      final h = await pumpScreen(tester,
          exercises: [exercise(name: _bench), exercise(name: _situp)],
          libraryRows: _rows);
      await tapWithRealIo(tester, find.text('LOG 3 SETS ✓').first);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1300)));
      await tester.pump();
      expect(h.state.isExerciseDone(0), isTrue);
      // The logged card collapsed when focus moved on; its still opens it.
      await _openViewer(tester, door: find.byType(ExercisePlateThumb).first);
      expect(_inViewer(find.text('LOGGED ✓')), findsOneWidget);
      await tester.tap(_inViewer(find.text('LOGGED ✓')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_viewer, findsOneWidget, reason: 're-open stays in the viewer');
      expect(h.state.isExerciseDone(0), isFalse);
      await unmountScreen(tester);
    });
  });

  group('same-frame events (direct callbacks)', () {
    testWidgets('LOG then back in one frame: one pop, the screen stays',
        (tester) async {
      await pumpScreen(tester, exercises: [exercise(name: _bench)], libraryRows: _rows);
      await _openViewer(tester);
      final log = tester.widget<GestureDetector>(_logDetector('LOG 3 SETS ✓')).onTap!;
      final back = tester.widget<GestureDetector>(_back).onTap!;
      await tester.runAsync(() async {
        log();
        back();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await _closeSettled(tester);
      expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
      expect(_viewer, findsNothing);
      await unmountScreen(tester);
    });

    testWidgets('back then back in one frame: one pop, the screen stays',
        (tester) async {
      await pumpScreen(tester, exercises: [exercise(name: _bench)], libraryRows: _rows);
      await _openViewer(tester);
      final back = tester.widget<GestureDetector>(_back).onTap!;
      back();
      back();
      await _closeSettled(tester);
      expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
      expect(_viewer, findsNothing);
      await unmountScreen(tester);
    });

    testWidgets('the still invoked twice in one frame pushes ONE viewer',
        (tester) async {
      await pumpScreen(tester, exercises: [exercise(name: _bench)], libraryRows: _rows);
      final tap = tester
          .widget<GestureDetector>(find
              .descendant(of: _tile, matching: find.byType(GestureDetector))
              .first)
          .onTap!;
      tap();
      tap();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_viewer.evaluate().length, 1);
      await unmountScreen(tester);
    });
  });

  group('doors and modes', () {
    testWidgets('D9: the still of a COLLAPSED card opens its viewer, focuses '
        'it, and LOG logs THAT exercise', (tester) async {
      final h = await pumpScreen(tester,
          exercises: [exercise(name: _bench), exercise(name: _situp)],
          libraryRows: _rows);
      expect(tester.widget<ExerciseHeaderTile>(_tile).exerciseName, _bench);
      await _openViewer(tester, door: find.byType(ExercisePlateThumb).first);
      expect(_inViewer(find.text(_situp.toUpperCase())), findsOneWidget);
      await tapWithRealIo(tester, _inViewer(find.text('LOG 3 SETS ✓')));
      await _closeSettled(tester);
      expect(h.state.isExerciseDone(1), isTrue);
      expect(h.state.isExerciseDone(0), isFalse);
      await unmountScreen(tester);
    });

    testWidgets('D9: the still of a superset PARTNER (expanded, not focused) '
        'opens its viewer, and LOG logs that partner only', (tester) async {
      final h = await pumpScreen(tester,
          exercises: [
            exercise(name: _bench).copyWith(supersetGroup: () => 0),
            exercise(name: _situp).copyWith(supersetGroup: () => 0),
          ],
          libraryRows: _rows);
      expect(tester.widget<ExerciseHeaderTile>(_tile).exerciseName, _bench);
      await _openViewer(tester, door: find.byType(ExercisePlateThumb));
      expect(tester.widget<ExerciseMediaViewer>(_viewer).exerciseIndex, 1);
      expect(_inViewer(find.text(_situp.toUpperCase())), findsOneWidget);
      await tapWithRealIo(tester, _inViewer(find.text('LOG 3 SETS ✓')));
      await _closeSettled(tester);
      expect(_viewer, findsNothing);
      expect(h.state.isExerciseDone(1), isTrue);
      expect(h.state.isExerciseDone(0), isFalse);
      await unmountScreen(tester);
    });

    testWidgets('back from a collapsed card\'s viewer leaves THAT card open',
        (tester) async {
      await pumpScreen(tester,
          exercises: [exercise(name: _bench), exercise(name: _situp)],
          libraryRows: _rows);
      await _openViewer(tester, door: find.byType(ExercisePlateThumb).first);
      await tester.tap(_back);
      await _closeSettled(tester);
      expect(tester.widget<ExerciseHeaderTile>(_tile).exerciseName, _situp,
          reason: 'C-c: opening focuses the card');
      await unmountScreen(tester);
    });

    testWidgets('a row without media opens the plate sheet, not the viewer',
        (tester) async {
      await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise(name: _calf)]),
          logMode: true,
          isFocused: true,
          libraryRows: _rows);
      await tester.tap(find.byType(ExercisePlateThumb));
      await tester.pumpAndSettle();
      expect(find.byType(ExercisePlateSheet), findsOneWidget);
      expect(_viewer, findsNothing);
    });

    testWidgets('the LOG flag off: the viewer is the animation and the cues, '
        'no rows, no LOG', (tester) async {
      await pumpScreen(tester,
          exercises: [exercise(name: _full)], libraryRows: _rows, logMode: false);
      await _openViewer(tester);
      expect(_viewerFields, findsNothing);
      expect(_inViewer(find.textContaining('LOG')), findsNothing);
      expect(_inViewer(find.text('FORM')), findsOneWidget);
      await unmountScreen(tester);
    });

    testWidgets('review mode (saved): LOG is disabled', (tester) async {
      await pumpScreen(tester,
          exercises: [exercise(name: _bench)],
          libraryRows: _rows,
          seed: (b) => b.copyWith(isSaved: true));
      await _openViewer(tester);
      final h = tester.widget<GestureDetector>(_logDetector('LOG 3 SETS ✓'));
      expect(h.onTap, isNull);
      await unmountScreen(tester);
    });

    testWidgets('the thumb\'s existing tap action opens the viewer through '
        'semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester,
          exercises: [exercise(name: _bench), exercise(name: _situp)],
          libraryRows: _rows);
      // The image carries the label; the tap action sits on the node of the
      // thumb's own GestureDetector above it (pre-existing structure).
      SemanticsNode? node = find.semantics.byLabel(_situp).evaluate().single;
      while (node != null && !node.getSemanticsData().hasAction(SemanticsAction.tap)) {
        node = node.parent;
      }
      expect(node, isNotNull, reason: 'the thumb exposes a tap action');
      node!.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_viewer, findsOneWidget);
      handle.dispose();
      await unmountScreen(tester);
    });
  });

  group('logging types', () {
    // Box order per SetInputRow: weight_reps KG REPS; bodyweight_reps REPS;
    // weighted_bodyweight KG REPS; timed SEC; cardio MIN KM; distance KM KG.
    // `typed` maps a viewer box index to the text entered before the LOG tap
    // (the harness seeds reps '8' and weight '0kg'; duration and distance
    // start blank). `box` is the viewer box the blocked tap must focus.
    final cases = <({
      String type,
      Map<int, String> typed,
      String label,
      int box,
    })>[
      (type: 'bodyweight_reps', typed: {0: ''}, label: 'Add reps', box: 0),
      (type: 'weighted_bodyweight', typed: {1: ''}, label: 'Add reps', box: 1),
      (type: 'timed', typed: {}, label: 'Add time', box: 0),
      (type: 'cardio', typed: {}, label: 'Add time', box: 0),
      (
        type: 'cardio',
        typed: {0: '20', 1: '400'},
        label: 'Fix distance',
        box: 1
      ),
      (type: 'distance', typed: {}, label: 'Add distance', box: 0),
    ];
    for (final c in cases) {
      testWidgets('${c.type}: ${c.label} focuses viewer box ${c.box}',
          (tester) async {
        final h = await pumpScreen(tester,
            exercises: [exercise(name: _bench, type: c.type)],
            libraryRows: _rows,
            lastPerf: const LastPerformanceData());
        await _openViewer(tester);
        expect(_viewerFields, findsWidgets);
        for (final e in c.typed.entries) {
          await tester.enterText(_viewerFields.at(e.key), e.value);
        }
        await tester.pump();
        final blocked = _inViewer(find.text(c.label));
        expect(blocked, findsOneWidget, reason: 'the LOG button names the gap');
        await tester.tap(blocked);
        await tester.pump();
        expect(_viewer, findsOneWidget);
        expect(FocusManager.instance.primaryFocus,
            tester.widget<TextField>(_viewerFields.at(c.box)).focusNode,
            reason: 'the VIEWER box for that field holds the focus');
        expect(h.state.isExerciseDone(0), isFalse);
        expect(tester.takeException(), isNull);
        await unmountScreen(tester);
      });
    }
  });

  group('warm-up hint', () {
    testWidgets('a warm-up toggle inside the viewer shows no hint and does '
        'not consume it', (tester) async {
      await pumpScreen(tester,
          exercises: [exercise(name: _bench)], libraryRows: _rows, hintSeen: true);
      await _openViewer(tester);
      await tester.longPress(_inViewer(find.text('1')).first);
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
      // Not consumed: after back, the first toggle on the CARD shows it.
      await tester.tap(_back);
      await _closeSettled(tester);
      expect(_viewer, findsNothing);
      await tester.longPress(find.text('2').first);
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget,
          reason: 'the hint was neither shown nor consumed under the viewer');
      await unmountScreen(tester);
    });
  });

  group('swap, remove, complete under the open viewer', () {
    testWidgets('a swap pops the viewer, renders no rows in the same frame, '
        'and keeps the screen', (tester) async {
      final h = await pumpScreen(tester,
          exercises: [exercise(name: _bench), exercise(name: _situp)],
          libraryRows: _rows);
      await _openViewer(tester);
      h.notifier.swapExercise(0, exercise(name: _calf));
      await tester.pump();
      expect(_viewerFields, findsNothing,
          reason: 'no field may stay mounted on controllers about to be disposed');
      expect(tester.takeException(), isNull);
      await _closeSettled(tester);
      expect(_viewer, findsNothing);
      expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
      await unmountScreen(tester);
    });

    testWidgets('removing the exercise pops the viewer', (tester) async {
      final h = await pumpScreen(tester,
          exercises: [exercise(name: _bench), exercise(name: _situp)],
          libraryRows: _rows);
      await _openViewer(tester);
      h.notifier.removeExercise(0);
      await _closeSettled(tester);
      expect(_viewer, findsNothing);
      expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
      await unmountScreen(tester);
    });

    testWidgets('removing the LAST exercise while its own viewer is open: no '
        'range error, the viewer closes', (tester) async {
      final h = await pumpScreen(tester,
          exercises: [exercise(name: _bench), exercise(name: _situp)],
          libraryRows: _rows);
      // The still of the collapsed second card opens ITS viewer (index 1).
      await _openViewer(tester, door: find.byType(ExercisePlateThumb).first);
      expect(tester.widget<ExerciseMediaViewer>(_viewer).exerciseIndex, 1);
      h.notifier.removeExercise(1);
      await _closeSettled(tester);
      expect(tester.takeException(), isNull,
          reason: 'index 1 no longer exists: the viewer must not read it');
      expect(_viewer, findsNothing);
      expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
      await unmountScreen(tester);
    });

    testWidgets('the workout completing pops the viewer', (tester) async {
      final h = await pumpScreen(tester,
          exercises: [exercise(name: _bench)],
          libraryRows: _rows,
          notifierFor: _CompletableNotifier.new);
      await _openViewer(tester);
      (h.notifier as _CompletableNotifier).markComplete();
      await _closeSettled(tester);
      expect(_viewer, findsNothing);
      await unmountScreen(tester);
    });

    testWidgets('a route above the viewer: a swap removes the viewer from '
        'underneath, the sheet and the screen stay', (tester) async {
      final h = await pumpScreen(tester,
          exercises: [exercise(name: _bench), exercise(name: _situp)],
          libraryRows: _rows);
      await _openViewer(tester);
      unawaited(ExercisePlateSheet.show(tester.element(_viewer), _situp));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ExercisePlateSheet), findsOneWidget);
      h.notifier.swapExercise(0, exercise(name: _calf));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_viewer, findsNothing);
      expect(find.byType(ExercisePlateSheet), findsOneWidget);
      expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
      await unmountScreen(tester);
    });
  });

  group('a viewer that outlives what it borrows from', () {
    testWidgets('the LOG flag flipped off under the open viewer: LOG logs '
        'nothing and throws nothing', (tester) async {
      final h = await pumpScreen(tester,
          exercises: [exercise(name: _bench)], libraryRows: _rows);
      await _openViewer(tester);
      await tester.runAsync(
          () => HiveService.instance.configBox.put(LogExerciseFlags.key, false));
      h.notifier.setElapsedSeconds(5);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_viewer, findsOneWidget);
      await tapWithRealIo(tester, _inViewer(find.text('LOG 3 SETS ✓')));
      expect(tester.takeException(), isNull);
      expect(h.state.isExerciseDone(0), isFalse);
      await unmountScreen(tester);
    });

    testWidgets('a close fired after the viewer is gone is a no-op and never '
        'takes the screen with it', (tester) async {
      await pumpScreen(tester,
          exercises: [exercise(name: _bench), exercise(name: _situp)],
          libraryRows: _rows);
      await _openViewer(tester);
      final lateClose = tester.widget<GestureDetector>(_back).onTap!;
      await tester.tap(_back);
      await _closeSettled(tester);
      expect(_viewer, findsNothing);
      lateClose();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ActiveWorkoutScreen), findsOneWidget,
          reason: 'a bare pop would have taken the screen\'s page');
      await unmountScreen(tester);
    });

    testWidgets('a field edit and a LOG tap fired after the card is gone are '
        'no-ops', (tester) async {
      final h = await pumpScreen(tester,
          exercises: [exercise(name: _bench), exercise(name: _situp)],
          libraryRows: _rows);
      await _openViewer(tester);
      final lateEdit = tester.widget<TextField>(_viewerFields.at(0)).onChanged!;
      final lateLog =
          tester.widget<GestureDetector>(_logDetector('LOG 3 SETS ✓')).onTap!;
      h.notifier.removeExercise(0);
      await _closeSettled(tester);
      expect(_viewer, findsNothing);
      lateEdit('70');
      lateLog();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(h.state.isExerciseDone(0), isFalse);
      await unmountScreen(tester);
    });
  });

  group('freeze, keep-alive, semantics', () {
    testWidgets('the covered tile freezes while the viewer is open and plays '
        'again after', (tester) async {
      await pumpScreen(tester, exercises: [exercise(name: _bench)], libraryRows: _rows);
      bool autoplay() => tester
          .widget<ExerciseAnimationView>(find.descendant(
              of: _tile, matching: find.byType(ExerciseAnimationView)))
          .autoplay;
      expect(autoplay(), isTrue);
      await _openViewer(tester);
      expect(autoplay(), isFalse);
      await tester.tap(_back);
      await _closeSettled(tester);
      expect(autoplay(), isTrue);
      await unmountScreen(tester);
    });

    testWidgets('the card keeps itself alive while the viewer is open',
        (tester) async {
      await pumpScreen(tester, exercises: [exercise(name: _bench)], libraryRows: _rows);
      bool keepAlive() {
        RenderObject? ro = tester.renderObject(_tile);
        while (ro != null && ro.parentData is! SliverMultiBoxAdaptorParentData) {
          ro = ro.parent;
        }
        final data = ro?.parentData;
        return data is SliverMultiBoxAdaptorParentData && data.keepAlive;
      }

      expect(keepAlive(), isFalse);
      await _openViewer(tester);
      expect(keepAlive(), isTrue);
      await tester.tap(_back);
      await _closeSettled(tester);
      expect(keepAlive(), isFalse);
      await unmountScreen(tester);
    });

    testWidgets('the route is named, the back control is a separate button '
        'node, and there is no duplicate BACK TO WORKOUT node', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, exercises: [exercise(name: _bench)], libraryRows: _rows);
      await _openViewer(tester);
      expect(tester.takeException(), isNull,
          reason: 'scopesRoute needs explicitChildNodes');
      expect(find.semantics.byLabel('Back to workout'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('BACK TO WORKOUT')), findsNothing);
      tester.semantics.tap(find.semantics.byLabel('Back to workout'));
      await _closeSettled(tester);
      expect(_viewer, findsNothing);
      handle.dispose();
      await unmountScreen(tester);
    });
  });

  group('cue sections hidden when empty', () {
    const headings = ['FORM', 'COMMON MISTAKES', 'BREATHING', 'WARM-UP'];

    testWidgets('only coaching_cues: FORM shows, the other three headings do '
        'not', (tester) async {
      await pumpScreen(tester, exercises: [exercise(name: _bench)], libraryRows: _rows);
      await _openViewer(tester);
      expect(_inViewer(find.text('FORM')), findsOneWidget);
      for (final h in headings.skip(1)) {
        expect(_inViewer(find.text(h)), findsNothing, reason: '$h has no content');
      }
      expect(tester.takeException(), isNull);
      await unmountScreen(tester);
    });

    testWidgets('no cues at all: no heading, no exception', (tester) async {
      await pumpScreen(tester, exercises: [exercise(name: _longName)], libraryRows: _rows);
      await _openViewer(tester);
      for (final h in headings) {
        expect(_inViewer(find.text(h)), findsNothing, reason: '$h has no content');
      }
      expect(tester.takeException(), isNull);
      await unmountScreen(tester);
    });
  });

  group('cues and LAST / TRY', () {
    testWidgets('TRY is hidden under a session cut, LAST stays',
        (tester) async {
      const perf = LastPerformanceData(
          lastWeight: 100, lastReps: 8, suggestedWeight: 102.5);
      await pumpScreen(tester,
          exercises: [exercise(name: _bench)],
          libraryRows: _rows,
          lastPerf: perf,
          seed: (b) => b.copyWith(sessionDetrainingFactor: 0.8));
      await _openViewer(tester);
      expect(_inViewer(find.textContaining('LAST:')), findsOneWidget);
      expect(_inViewer(find.textContaining('TRY:')), findsNothing);
      await unmountScreen(tester);
    });

    testWidgets('inline puts LAST and TRY on one line when they fit, stacked '
        'when they do not', (tester) async {
      const perf = LastPerformanceData(
          lastWeight: 100, lastReps: 8, suggestedWeight: 102.5);
      _view(tester, 800, 900);
      await pumpScreen(tester,
          exercises: [exercise(name: _bench)], libraryRows: _rows, lastPerf: perf);
      await _openViewer(tester);
      var last = tester.getTopLeft(_inViewer(find.byKey(const Key('exercise-last-line'))));
      var tryy = tester.getTopLeft(_inViewer(find.byKey(const Key('exercise-try-line'))));
      expect(last.dy, tryy.dy, reason: 'side by side at 800 dp');
      await unmountScreen(tester);

      _view(tester, 360, 900);
      await pumpScreen(tester,
          exercises: [exercise(name: _bench)], libraryRows: _rows, lastPerf: perf);
      await _openViewer(tester);
      last = tester.getTopLeft(_inViewer(find.byKey(const Key('exercise-last-line'))));
      tryy = tester.getTopLeft(_inViewer(find.byKey(const Key('exercise-try-line'))));
      expect(tryy.dy, greaterThan(last.dy), reason: 'stacked at 360 dp');
      await unmountScreen(tester);
    });
  });

  group('layout', () {
    double side(WidgetTester tester) => tester.getSize(_animation).width;
    double bodyHeight(WidgetTester tester) =>
        tester.getSize(find.byKey(const Key('exercise-viewer-body'))).height;
    double expectedSide(WidgetTester tester, double width) =>
        (bodyHeight(tester) - kViewerScrollMinDp).clamp(0.0, width).toDouble();

    testWidgets('360 x 780, no keyboard: the square is the full width and '
        'rows 1 to 3 are in the scroll viewport', (tester) async {
      _view(tester, 360, 780);
      await pumpScreen(tester, exercises: [exercise(name: _bench)], libraryRows: _rows);
      await _openViewer(tester);
      expect(side(tester), closeTo(360, 1));
      final scroll = tester.getRect(_inViewer(find.byType(SingleChildScrollView)));
      final row3 = tester.getRect(_viewerFields.at(4));
      expect(row3.bottom, lessThanOrEqualTo(scroll.bottom + 1),
          reason: 'rows 1 to 3 are inside the scroll viewport under the square');
      expect(tester.takeException(), isNull);
      await unmountScreen(tester);
    });

    testWidgets('360 x 640, no keyboard: set row 3 is inside the scroll '
        'viewport', (tester) async {
      _view(tester, 360, 640);
      await pumpScreen(tester, exercises: [exercise(name: _bench)], libraryRows: _rows);
      await _openViewer(tester);
      final scroll = tester.getRect(_inViewer(find.byType(SingleChildScrollView)));
      final row3 = tester.getRect(_viewerFields.at(4));
      expect(row3.bottom, lessThanOrEqualTo(scroll.bottom + 1),
          reason: 'kViewerScrollMinDp keeps three rows visible');
      expect(scroll.height, greaterThanOrEqualTo(kViewerScrollMinDp - 0.5));
      await unmountScreen(tester);
    });

    testWidgets('360 x 800 with a 300 dp keyboard: the square follows the '
        'formula and is smaller than without a keyboard', (tester) async {
      _view(tester, 360, 800, keyboard: 300);
      await pumpScreen(tester, exercises: [exercise(name: _bench)], libraryRows: _rows);
      await _openViewer(tester);
      final withKeyboard = side(tester);
      expect(withKeyboard, closeTo(expectedSide(tester, 360), 1));
      expect(withKeyboard, lessThan(360));
      expect(tester.getSize(_inViewer(find.byType(SingleChildScrollView))).height,
          greaterThanOrEqualTo(kViewerScrollMinDp - 0.5));
      await unmountScreen(tester);
    });

    testWidgets('360 x 640, 300 dp keyboard, notch: no overflow, the LOG row '
        'is above the keyboard, the animation is hidden, and the Scaffold is '
        'the full view (no strips)', (tester) async {
      _view(tester, 360, 640, keyboard: 300, top: 24, bottom: 48);
      await pumpScreen(tester, exercises: [exercise(name: _bench)], libraryRows: _rows);
      await _openViewer(tester);
      expect(tester.takeException(), isNull);
      expect(_animation, findsNothing);
      final scaffold = tester.getRect(_inViewer(find.byType(Scaffold)));
      expect(scaffold, const Rect.fromLTWH(0, 0, 360, 640),
          reason: 'a SafeArea above the Scaffold would leave a strip');
      final log = tester.getRect(_inViewer(find.text('LOG 3 SETS ✓')));
      expect(log.bottom, lessThanOrEqualTo(640 - 300 + 0.5));
      await unmountScreen(tester);
    });

    testWidgets('text scale 2.0 at 340 x 640 with the keyboard: no overflow '
        '(the back label shrinks)', (tester) async {
      _view(tester, 340, 640, keyboard: 300, top: 24, bottom: 48, scale: 2.0);
      await pumpScreen(tester, exercises: [exercise(name: _bench)], libraryRows: _rows);
      await _openViewer(tester);
      expect(tester.takeException(), isNull);
      await unmountScreen(tester);
    });

    testWidgets('a view wider than 480: the square is at most 480',
        (tester) async {
      _view(tester, 800, 1400);
      await pumpScreen(tester, exercises: [exercise(name: _bench)], libraryRows: _rows);
      await _openViewer(tester);
      expect(side(tester), lessThanOrEqualTo(480));
      await unmountScreen(tester);
    });

    testWidgets('a 57-character name at 320 dp: at most two lines, no overflow',
        (tester) async {
      _view(tester, 320, 800);
      await pumpScreen(tester, exercises: [exercise(name: _longName)], libraryRows: _rows);
      await _openViewer(tester);
      expect(_longName.length, 57);
      expect(tester.takeException(), isNull);
      final nameFinder = _inViewer(find.text(_longName.toUpperCase()));
      final name = tester.getSize(nameFinder);
      // One line of the name as RENDERED (the theme's default text style is
      // merged in, which a bare TextPainter would miss). Under Ahem the 57
      // characters (glyph + letter spacing) wrap to THREE lines in the 288 dp
      // column, so a lost `maxLines: 2` makes the block three lines tall.
      final line = tester
          .renderObject<RenderParagraph>(nameFinder)
          .getFullHeightForCaret(const TextPosition(offset: 0));
      expect(name.height, greaterThan(line + 0.5),
          reason: 'the name does wrap (else the cap below proves nothing)');
      // Lines are laid out on whole pixels (16 dp each for a 15.7 dp caret).
      expect(name.height, lessThanOrEqualTo(2 * line.ceilToDouble() + 0.5),
          reason: 'maxLines 2 caps the name block at two lines');
      await unmountScreen(tester);
    });
  });
}
