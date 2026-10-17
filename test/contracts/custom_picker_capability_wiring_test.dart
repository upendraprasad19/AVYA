// SOURCE-GREP WIRING TEST — custom-picker-fix (2026-09-17)
//
// Pins that all three exercise pickers route CUSTOM exercises through
// `EquipmentCapability.canOfferInPicker` (unverifiable-equipment customs
// stay visible) while library/community rows keep the fail-closed
// `canPerform`, and that the edit-mode writer contract exists.
//
// PRESENCE-ONLY test (source-grep) — the BEHAVIORAL proof for the
// predicate itself lives in `can_offer_in_picker_behavioral_test.dart`,
// and the edit write→read-same-key arm lives in
// `custom_exercises_mutations_behavioral_test.dart` (Test 5). Per repo
// rule 21, source-greps count for presence only; the pairing is
// deliberate: grep pins the WIRING (which file calls what), the
// behavioral tests pin the SEMANTICS.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

const repoRoot = '.';

void main() {
  final swapSrc =
      _read('$repoRoot/lib/features/train/widgets/exercise_swap_sheet.dart');
  final pickerSrc = _read(
      '$repoRoot/lib/features/train/screens/active_workout/exercise_picker_sheet.dart');
  final templateSrc =
      _read('$repoRoot/lib/features/train/screens/template_builder_screen.dart');
  final sheetSrc = _read(
      '$repoRoot/lib/features/train/widgets/create_custom_exercise_sheet.dart');
  final yourExSrc = _read(
      '$repoRoot/lib/features/train/screens/train/your_exercises_section.dart');
  final chipSrc = _read(
      '$repoRoot/lib/features/train/screens/train/collapsible_section.dart');

  group('picker capability wiring (custom-picker-fix)', () {
    test('swap sheet: custom list uses canOfferInPicker, library keeps '
        'canPerform', () {
      expect(swapSrc.contains('canOfferInPicker'), isTrue,
          reason: 'the custom list must use the picker-asymmetric predicate');
      // Library list keeps the fail-closed check; customs use the
      // canOfferInPicker exemption — exactly ONE canPerform call remains.
      expect('canPerform('.allMatches(swapSrc).length, 1,
          reason: 'the library list keeps canPerform; the custom list must '
              'have switched to canOfferInPicker');
      expect(swapSrc.contains('isCustom: true'), isTrue,
          reason: 'provenance is list membership (getCustomExercises output), '
              'NOT a per-row is_custom field — restored rows carry none');
    });

    test('picker sheet: filter-then-merge, no per-row discriminator', () {
      expect(pickerSrc.contains('filteredLibrary'), isTrue);
      expect(pickerSrc.contains('filteredCustom'), isTrue,
          reason: 'the two lists filter SEPARATELY then merge — a per-row '
              'is_custom check would miss the restored population');
      expect('canPerform('.allMatches(pickerSrc).length, 1,
          reason: 'library keeps the fail-closed check');
      expect(pickerSrc.contains('canOfferInPicker'), isTrue);
      expect(pickerSrc.contains('cap == null'), isTrue,
          reason: 'the flag-OFF skip is preserved: no filtering at all when '
              'capability is unresolvable');
    });

    test('template builder: doableCustom for the custom list', () {
      expect(templateSrc.contains('doableCustom'), isTrue);
      expect('canPerform('.allMatches(templateSrc).length, 1,
          reason: 'library lists keep canPerform inside doable()');
      expect(templateSrc.contains('canOfferInPicker'), isTrue);
      expect(templateSrc.contains('cap == null'), isTrue);
    });

    test('no picker site applies canPerform to a CUSTOM list', () {
      // The old bug shape: `getCustomExercises()` result piped through
      // canPerform. If that literal shape reappears in any of the three
      // sites, customs with [] equipment go dark again.
      final bugShape = RegExp(r'getCustomExercises\(\)[\s\S]{0,200}canPerform\(');
      expect(bugShape.hasMatch(swapSrc), isFalse, reason: 'swap sheet');
      expect(bugShape.hasMatch(pickerSrc), isFalse, reason: 'picker sheet');
      expect(bugShape.hasMatch(templateSrc), isFalse, reason: 'template builder');
    });
  });

  group('creation sheet: muscles + edit mode wiring', () {
    test('create passes the resolved muscle selection', () {
      // Since d5c2e8 the create branch calls
      // WorkoutRepository.createCustomExercise, which stores the list it is
      // given — so the selection is pinned at the call argument.
      expect(sheetSrc.contains('primaryMuscles: _resolvedMuscles'), isTrue,
          reason: 'the hardcoded empty list was the writer half of the bug — '
              'the plan-generator supplement path ('
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
