// CONTRACT TEST — diagnose 7c3e91 (the START button nobody listed).
//
// The 2026-07-20 fix for "Home START dead-end" (b7f30a) and the 2026-09-15
// resume guard (e8f4a1) found START buttons by searching for callers of
// `startWorkout`. A button that never calls it (the Home calendar day sheet's,
// which only closed the sheet from 2026-03-24 to this fix) cannot be found that
// way. This test finds them by LABEL: every file under `lib/` that spells a
// START / RESUME button label must be in the inventory below, with how it
// reaches the ONE start path (`beginWorkoutWithReadiness`). A new START button
// in a new file fails here until someone writes down where it goes.
//
// MUTATION: add `'START WORKOUT'` to a new lib file -> the first test fails;
// delete `beginWorkoutWithReadiness` from hero_cards.dart -> the second fails.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// file -> how its START reaches the start path.
const _inventory = <String, String>{
  // Hosts that call `beginWorkoutWithReadiness` themselves.
  'lib/features/train/screens/train/hero_cards.dart': 'calls',
  'lib/features/train/screens/train/planned_expansion.dart': 'calls',
  // The canonical path itself (the readiness sheet's own START WORKOUT).
  'lib/features/train/widgets/readiness_sheet.dart': 'is the path',
  // Presentational: the host passes `onStart`; the host is checked below.
  'lib/features/home/widgets/today_workout_card.dart': 'onStart',
  'lib/features/home/widgets/day_detail_sheet.dart': 'onStart',
  // Train widgets with a START label that no screen builds today.
  'lib/features/train/widgets/day_card.dart': 'unused',
  'lib/features/train/widgets/today_workout_card.dart': 'unused',
  // A copy constant no screen reads today (checked below).
  'lib/core/copy/wardroom_copy.dart': 'unused',
  // Same word, not a workout START button.
  'lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart': 'not a button',
  'lib/shared/widgets/wardroom/ward_phase_block.dart': 'not a button',
};

String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

List<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

String _norm(String p) => p.replaceAll('\\', '/');

void main() {
  // A literal that IS the label, or any literal containing "START WORKOUT"
  // (e.g. the copy file's '▸ START WORKOUT →').
  final label =
      RegExp(r"'(START|RESUME)( WORKOUT)?'|'[^'\n]*START WORKOUT[^'\n]*'");

  test('every file that spells a START / RESUME label is in the inventory', () {
    final found = <String>{
      for (final f in _libFiles())
        if (label.hasMatch(_code(f.path))) _norm(f.path),
    };
    expect(found.difference(_inventory.keys.toSet()), isEmpty,
        reason: 'a new START/RESUME label: add it to _inventory with the route '
            'it takes to beginWorkoutWithReadiness');
    expect(_inventory.keys.toSet().difference(found), isEmpty,
        reason: 'an inventory entry no longer has a START label: remove it');
  });

  test('the hosts that own a start path call beginWorkoutWithReadiness', () {
    for (final e in _inventory.entries.where((e) => e.value == 'calls')) {
      expect(_code(e.key), contains('beginWorkoutWithReadiness'),
          reason: '${e.key} spells START and must reach the one start path');
    }
  });

  test('the Home screen routes both of its START buttons to one method', () {
    final src = _code('lib/features/home/screens/home_screen.dart');
    expect(src, contains('beginWorkoutWithReadiness'));
    expect(RegExp(r'onStart:[^\n]*\(\) => _startTodayWorkout\(context, ref\)')
        .allMatches(src)
        .length, 2,
        reason: 'the Today card and the calendar day sheet');
  });

  test('the START copy constant is still unused (else wire its button first)',
      () {
    final users = _libFiles()
        .where((f) => _norm(f.path) != 'lib/core/copy/wardroom_copy.dart')
        .where((f) => _code(f.path).contains('trainStartWorkoutCta'))
        .toList();
    expect(users, isEmpty,
        reason: 'a screen now reads WardroomCopy.trainStartWorkoutCta: list it '
            'in _inventory with the route its button takes');
  });

  test('the "unused" START widgets are still unused (else wire them first)', () {
    final all = _libFiles().map((f) => _code(f.path)).join('\n');
    // `DayCard(` also matches `ExpandableDayCard(`-free: anchor on a word edge.
    expect(RegExp(r'(?<![A-Za-z])DayCard\(').allMatches(all).length, 1,
        reason: 'only its own constructor; a use needs a wired onStart');
    final trainTwc = _code('lib/features/train/widgets/today_workout_card.dart');
    expect(trainTwc, contains('class TodayWorkoutCard'));
    final users = _libFiles()
        .where((f) => _norm(f.path) != 'lib/features/train/widgets/today_workout_card.dart')
        .where((f) => _code(f.path).contains(
            "features/train/widgets/today_workout_card.dart"))
        .toList();
    expect(users, isEmpty,
        reason: 'nothing imports the Train TodayWorkoutCard');
  });
}
