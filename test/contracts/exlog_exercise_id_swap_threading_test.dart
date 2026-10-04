// W3.3 (Batch 11-A) — the MANUAL swap / add / create-swap UI paths thread the
// library `exercise_id` into the constructed `ExerciseData`, so a
// manually-swapped or manually-added exercise's logs match progression history
// by id (not just name). B-pass finding 3c9f18f0d42d#1 (P1): before this, the
// three `ExerciseData(...)` builders in swap_sheets.dart silently dropped the
// id (SwapExerciseData had no id field; the add-path map's `id` was unread),
// so the "swap" case the feature is named for never got the id benefit.
//
// This is a source-grep drift guard (the threading is a one-line pass at each
// UI construction site — the recurring writer/reader-drift class) PLUS a
// `SwapExerciseData.id` field round-trip. The resolver's id-match BEHAVIOR is
// proven separately by exlog_exercise_id_behavioral_test.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/features/train/providers/train_provider.dart';

void main() {
  group('SwapExerciseData carries the library id', () {
    test('id round-trips + defaults to null', () {
      const withId =
          SwapExerciseData(name: 'Bench', detail: 'd', id: 'lib_bench');
      expect(withId.id, 'lib_bench');
      const noId = SwapExerciseData(name: 'Bench', detail: 'd');
      expect(noId.id, isNull, reason: 'id must be optional (null → name fallback)');
    });
  });

  group('manual UI paths thread exerciseId into ExerciseData', () {
    late String swapSheets;
    late String swapSheetWidget;

    setUpAll(() {
      swapSheets = _stripComments(File(
              'lib/features/train/screens/active_workout/swap_sheets.dart')
          .readAsStringSync());
      swapSheetWidget = _stripComments(
          File('lib/features/train/widgets/exercise_swap_sheet.dart')
              .readAsStringSync());
    });

    test('add-exercise path threads the picked row id', () {
      expect(swapSheets.contains("exerciseId: exerciseData['id'] as String?"),
          isTrue,
          reason: '_showExercisePickerSheet must thread the added exercise id');
    });

    test('swap path threads the swapped-in id', () {
      expect(swapSheets.contains('exerciseId: swapEx.id'), isTrue,
          reason: '_showSwapSheet must thread SwapExerciseData.id');
    });

    test('create-and-auto-swap path threads the created id (null-safe)', () {
      expect(swapSheets.contains("exerciseId: newExercise['id'] as String?"),
          isTrue,
          reason: '_openCreateAndAutoSwap must thread the created exercise id');
    });

    test('ExerciseSwapSheet populates SwapExerciseData.id from the row', () {
      // Both the library + custom list builders must carry ex['id'].
      final count = "id: ex['id'] as String?".allMatches(swapSheetWidget).length;
      expect(count, greaterThanOrEqualTo(2),
          reason: 'both library + custom SwapExerciseData builders must pass '
              "id: ex['id'] — found $count");
    });
  });
}

/// Strips `/* … */` block + `// …` line comments (canonical form,
/// feedback_source_grep_strip_comments_first.md) so prose can't trip/mask the
/// assertions. These sources contain no `://` URL string.
String _stripComments(String src) {
  var out = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  out = out.replaceAll(RegExp(r'//.*'), '');
  return out;
}
