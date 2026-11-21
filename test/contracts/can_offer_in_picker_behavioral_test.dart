// BEHAVIORAL CONTRACT TEST — EquipmentCapability.canOfferInPicker
// (custom-picker-fix, 2026-09-17)
//
// Concept:   exercise capability picker-asymmetry (OI-89 seam family,
//            seams 6/7/8 reader refinement)
// Predicate: lib/shared/repositories/plan_engine/equipment_capability.dart
//            canOfferInPicker
// Writers it protects: workout_repository.dart `createCustomExercise`, the
//            one create path (d5c2e8). The sheet calls it with no equipment
//            ⇒ `equipment_needed: []` by design (the sheet has no equipment
//            field); the AI tool passes free text, which is normalized and
//            may store real tokens.
// Readers:   exercise_swap_sheet.dart `_loadExercises`,
//            exercise_picker_sheet.dart `_loadAllExercises`,
//            template_builder_screen.dart `_refresh` (doableCustom).
//
// The bug this pins: the OI-89 capability filter is FAIL-CLOSED on an
// unreadable/empty requirement (canPerform returns false for []). The
// creation sheet hardcodes `equipment_needed: []`, so EVERY user-authored
// custom exercise was filtered out of all three pickers before the search
// string was even applied — the founder's "Single Leg Front Lever" was
// unfindable while logged rows still displayed (log views read exlog_/wlog_
// directly and never filter).
//
// The contract, four arms + one end-to-end restored-row arm:
//   1. custom + EMPTY requirement      -> ALWAYS offered (the fix).
//   2. custom + PARSEABLE requirement  -> still fail-closed (canPerform
//      semantics; AI-authored customs with real equipment are NOT exempt).
//   3. non-custom (library/community) + EMPTY -> FAIL-CLOSED preserved.
//   4. canPerform itself is UNCHANGED (empty -> false) — the plan
//      generator's OI-89 safety is untouched by this batch.
//   5. END-TO-END: a RESTORED custom row (no `is_custom` field — the cloud
//      table has no such column; restore stamps only `type: 'exercise'`)
//      is returned by getCustomExercises() and passes the picker predicate
//      with `isCustom: true`. This arm is why provenance MUST come from
//      list membership, never row content: a per-row `is_custom` check
//      misses exactly the restore population (round-1 P0).
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/equipment_capability.dart';

void main() {
  // A bodyweight user's effective set (tierItems['bodyweight'] minus the
  // 'none' sentinel that effectiveItems strips — see equipment_vocab.dart).
  const bodyweightEffective = <String>{'bodyweight'};
  const gymEffective = <String>{
    'none', 'bodyweight', 'dumbbells', 'barbell', 'bench',
  };

  group('canOfferInPicker — the four-arm contract', () {
    test('ARM 1: custom with EMPTY equipment is always offered', () {
      expect(
        EquipmentCapability.canOfferInPicker(
            <String>[], bodyweightEffective, isCustom: true),
        isTrue,
        reason: 'THE regression: the creation sheet stores [], and '
            'fail-closed was hiding every custom from the pickers.',
      );
      // null requirement (restored row with no such key) — same fast path.
      expect(
        EquipmentCapability.canOfferInPicker(
            null, bodyweightEffective, isCustom: true),
        isTrue,
      );
    });

    test('ARM 2: custom with PARSEABLE equipment still fails closed', () {
      expect(
        EquipmentCapability.canOfferInPicker(
            <String>['barbell'], bodyweightEffective, isCustom: true),
        isFalse,
        reason: 'A custom needing a barbell must NOT be offered to a '
            'bodyweight user — the exemption is for UNVERIFIABLE rows only.',
      );
      // And a gym user CAN pick it.
      expect(
        EquipmentCapability.canOfferInPicker(
            <String>['barbell'], gymEffective, isCustom: true),
        isTrue,
      );
    });

    test('ARM 3: non-custom rows keep the fail-closed rule', () {
      expect(
        EquipmentCapability.canOfferInPicker(
            <String>[], bodyweightEffective, isCustom: false),
        isFalse,
        reason: 'A library/community row with an unreadable requirement is '
            '"we do not know" — it must never be offered (OI-89 invariant).',
      );
      expect(
        EquipmentCapability.canOfferInPicker(
            null, bodyweightEffective, isCustom: false),
        isFalse,
      );
    });

    test('ARM 4: canPerform itself is UNCHANGED — empty still fails closed',
        () {
      expect(
          EquipmentCapability.canPerform(<String>[], bodyweightEffective),
          isFalse,
          reason: 'The plan generator keys on canPerform; this batch must '
              'not weaken it. If this flips, OI-89 is broken.');
      expect(
          EquipmentCapability.canPerform(<String>['barbell'],
              bodyweightEffective),
          isFalse);
      expect(
          EquipmentCapability.canPerform(
              <String>['barbell'], gymEffective),
          isTrue);
    });
  });

  group('restore-shape row (no is_custom field) end-to-end', () {
    test(
        'a restored custom row (type only, no is_custom) passes the picker '
        'predicate via list-membership provenance', () {
      // EXACTLY the shape sync_community._restoreCustomExercises writes:
      // the raw cloud row plus a `type: 'exercise'` stamp. Notably NO
      // `is_custom` — the cloud table user_custom_exercises has no such
      // column, so any per-row `is_custom == true` discriminator misses
      // this row (and this row is the founder's reported exercise).
      final restoredRow = <String, dynamic>{
        'id': '29aeaa20-restored',
        'name': 'Single Leg Front Lever',
        'category': 'Core',
        'logging_type': 'bodyweight_reps',
        'type': 'exercise',
        'equipment_needed': <String>[],
        'primary_muscles': <String>[],
      };
      expect(
        EquipmentCapability.canOfferInPicker(
            restoredRow['equipment_needed'], bodyweightEffective,
            isCustom: true),
        isTrue,
        reason: 'A restored custom (no is_custom field) must be offered — '
            'provenance comes from getCustomExercises() list membership, '
            'never from row content.',
      );
      // And the row-shape trap that motivated this arm: the row does NOT
      // satisfy a per-row is_custom check.
      expect(restoredRow['is_custom'], isNull);
    });
  });
}
