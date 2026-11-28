// test/contracts/exercise_media_viewer_routing_test.dart
//
// Batch M2b Part B (the logging viewer): PRESENCE-ONLY source pins (comments
// stripped first) over who may open the viewer and how it is built. Presence
// pins prove the shape, never the behaviour: the behaviour is
// test/features/train/log_exercise/exercise_media_viewer_test.dart and
// exercise_media_viewer_router_test.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_source_slice.dart';

const _card = 'lib/features/train/screens/active_workout/exercise_card.dart';
const _viewer =
    'lib/features/train/screens/active_workout/exercise_media_viewer.dart';
const _calendarSheet = 'lib/features/home/widgets/day_detail_sheet.dart';
const _planCard = 'lib/features/train/widgets/expandable_day_card.dart';

String _src(String path) => stripDartComments(File(path).readAsStringSync());

void main() {
  test('_openPicture branches on the animation kill switch', () {
    final src = _src(_card);
    final body = functionBody(src, 'Future<void> _openPicture(');
    // The kill switch is read at the SINK (`_mediaNow`), the one getter every
    // reader of the card's animation goes through.
    expect(body.contains('_mediaNow'), isTrue,
        reason: 'the door must read the animation through the kill-switch sink');
    expect(body.contains('_media;') || body.contains('_media)'), isFalse,
        reason: 'reading the raw `_media` would bypass the kill switch');
    expect(src.contains('_mediaNow => PlateFlags.animationsEnabled ? _media : null'),
        isTrue);
    expect(body.contains('ExerciseMediaViewer.show('), isTrue);
    expect(body.contains('ExercisePlateSheet.show('), isTrue,
        reason: 'a row with no animation still opens the plate sheet');
  });

  test('only the active-workout card opens the viewer: the calendar sheet and '
      'the plan-list card keep the plate sheet', () {
    for (final p in [_calendarSheet, _planCard]) {
      final src = _src(p);
      expect(src.contains('ExerciseMediaViewer'), isFalse, reason: p);
      expect(src.contains('ExercisePlateSheet.show('), isTrue, reason: p);
    }
  });

  test('the handle\'s buildLogRow hands the HOST context to the card as '
      'focusContext', () {
    final src = _src(_card);
    expect(src.contains('focusContext: context'), isTrue,
        reason: 'a blocked LOG must request the viewer\'s own node from the '
            'viewer\'s focus scope');
  });

  test('the viewer resolves the cues once (initState), never in build, and '
      'does not use the root navigator', () {
    final src = _src(_viewer);
    final init = src.indexOf('void initState()');
    final build = src.indexOf('Widget build(BuildContext context)');
    expect(init, isNonNegative);
    expect(build, isNonNegative);
    final initBody = src.substring(init, build);
    expect(initBody.contains('exerciseCuesOf('), isTrue);
    expect(src.substring(build).contains('exerciseCuesOf('), isFalse,
        reason: 'the viewer rebuilds every second and on every keystroke');
    expect(src.contains('rootNavigator'), isFalse,
        reason: 'the viewer lives on the BRANCH navigator (call C-a)');
  });

  test('the route-naming Semantics sets explicitChildNodes with scopesRoute',
      () {
    final src = _src(_viewer);
    expect(src.contains('scopesRoute: true'), isTrue);
    expect(src.contains('explicitChildNodes: true'), isTrue,
        reason: 'scopesRoute without it asserts on every debug build');
  });

  test('the route is non-opaque, keeps state, and returns itself to the '
      'caller', () {
    final src = _src(_viewer);
    expect(src.contains('opaque: false'), isTrue);
    expect(src.contains('maintainState: true'), isTrue);
    expect(src.contains('static PageRoute<void> show('), isTrue);
  });
}
