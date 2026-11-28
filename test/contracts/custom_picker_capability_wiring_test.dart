// SOURCE-GREP WIRING TEST — hand-pick exercise lists
//
// Founder 2026-11-28: a user adding or swapping by hand can pick ANY exercise, so the four
// hand-pick lists ORDER rows by equipment and never drop one. All four go through
// `PickerRows.arrange`, and none calls an equipment predicate itself. (Until then this
// group pinned the opposite: each list hiding rows, custom-picker-fix 2026-09-17.)
// The file also pins the edit-mode writer contract of the creation sheet.
//
// PRESENCE-ONLY test (source-grep): it cannot see a list that drops the non-matching
// buckets. Each list's own widget test carries that:
// coach_swap_picker_equipment_behavioral_test.dart, swap_sheet_any_equipment_test.dart,
// template_builder_unique_names_test.dart, exercise_name_unique_screen_test.dart.
// The arrangement itself: picker_rows_behavioral_test.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// [path] without its comments, so a call named only in prose does not count.
String _code(String path) => _read(path)
    .split('\n')
    .map((line) {
      final at = line.indexOf('//');
      return at < 0 ? line : line.substring(0, at);
    })
    .join('\n');

const repoRoot = '.';

void main() {
  final sheetSrc = _read(
      '$repoRoot/lib/features/train/widgets/create_custom_exercise_sheet.dart');
  final yourExSrc = _read(
      '$repoRoot/lib/features/train/screens/train/your_exercises_section.dart');
  final chipSrc = _read(
      '$repoRoot/lib/features/train/screens/train/collapsible_section.dart');

  group('hand-pick lists go through PickerRows', () {
    const lists = {
      'swap sheet': 'lib/features/train/widgets/exercise_swap_sheet.dart',
      'mid-workout picker':
          'lib/features/train/screens/active_workout/exercise_picker_sheet.dart',
      'template builder':
          'lib/features/train/screens/template_builder_screen.dart',
      'coach swap list':
          'lib/features/ai_coach/widgets/swap_exercise_coach_sheet.dart',
    };
    for (final MapEntry(key: label, value: path) in lists.entries) {
      test('$label arranges its rows and drops none by equipment', () {
        final code = _code('$repoRoot/$path');
        expect(code.contains('PickerRows.arrange('), isTrue,
            reason: 'one arrangement for every hand-pick list');
        expect(code.contains('canPerform('), isFalse,
            reason: 'equipment orders a hand-pick list, it never filters it');
        expect(code.contains('canOfferInPicker('), isFalse);
      });
    }
  });

  group('creation sheet: muscles + edit mode wiring', () {
    test('create passes the resolved muscle selection', () {
      // Since d5c2e8 the create branch calls
      // WorkoutRepository.createCustomExercise, which stores the list it is
      // given — so the selection is pinned at the call argument.
      expect(sheetSrc.contains('primaryMuscles: _resolvedMuscles'), isTrue,
          reason: 'the hardcoded empty list was the writer half of the bug — '
              'the plan-generator supplement path (the since-removed '
              '_eligibleCustomExercises) never saw a custom');
      expect(sheetSrc.contains("'primary_muscles': <String>[]"), isFalse,
          reason: 'the empty-list hardcode must not return');
    });

    test('edit mode routes through the canonical SoT writer', () {
      expect(sheetSrc.contains('upsertCustomExercise'), isTrue);
      expect(sheetSrc.contains('WriteSource.editSheet'), isTrue);
      expect(sheetSrc.contains('buildEditPayload('), isTrue);
      // Name locked: the v5 UUID is derived from the lowercased name.
      expect(sheetSrc.contains('readOnly: isEdit'), isTrue,
          reason: 'a rename would mint a NEW deterministic id and orphan '
              'the name-keyed log history');
      // onCreated nullable + skipped in edit mode.
      expect(sheetSrc.contains('widget.onCreated?.call'), isTrue);
    });

    test('approved_for_library stamped in exactly ONE place (the create '
        'writer), never by the sheet', () {
      // Since d5c2e8 the create stamp lives in the repository's
      // createCustomExercise; the sheet stamps it nowhere, so the edit
      // payload cannot re-stamp it either (round-2 P1-1).
      expect("'approved_for_library'".allMatches(sheetSrc).length, 0,
          reason: 'the sheet must not stamp approved_for_library — create '
              'belongs to the repository, edit must preserve the stored value');
      final repoSrc = _read(
          '$repoRoot/lib/features/train/repositories/workout_repository.dart');
      expect("'approved_for_library': false".allMatches(repoSrc).length, 1,
          reason: 'exactly one create stamp, in createCustomExercise');
    });
  });

  group('edit entry point: YOUR EXERCISES chips', () {
    test('chip is tappable and opens the sheet in edit mode', () {
      expect(chipSrc.contains('onTap'), isTrue);
      expect(yourExSrc.contains('_openEditCustomExerciseSheet'), isTrue);
      expect(yourExSrc.contains('existing: exercise'), isTrue);
    });
  });
}
