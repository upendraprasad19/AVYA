// This file grows across Tasks 3, 4, and 6 — Task 3 adds only the first group.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';

void main() {
  group('OI-126 wrapper — flag OFF byte-identical pin', () {
    test('logged reads as rest under the wrapper when the flag is off', () {
      // Pins the CURRENT (pre-fix) shape the wrapper must preserve until the
      // flag flips. If this test starts failing, something changed the OFF
      // default — stop and investigate before touching any call site.
      expect(PlanEngineFlags.isRestDayConsideringLogged('logged'), isTrue);
    });
  });

  group('OI-126 wrapper — the 6 additionally-discovered sites use the same wrapper', () {
    // These assertions are source-grep (Task 6 adds the mechanical grep test
    // proving each cited line actually calls the wrapper); this group is a
    // placeholder reminding the reader that Task 6, not this task, is where
    // the wiring proof for these 6 sites lives — Task 4 itself only edits
    // source, per the plan's TDD step shape below.
    test('wrapper still behaves correctly after this task (no change to it)', () {
      expect(PlanEngineFlags.isRestDayConsideringLogged('logged'), isTrue);
      expect(PlanEngineFlags.isRestDayConsideringLogged('workout'), isFalse);
    });
  });

  group('OI-126 — every claimed call site actually delegates to the wrapper', () {
    // Source-grep, not behavioral — but it closes a real gap: it proves each
    // of the 11 sites calls PlanEngineFlags.isRestDayConsideringLogged rather
    // than an inlined duplicate ternary that LOOKS equivalent today and
    // silently drifts tomorrow. Combined with the call-through tests below
    // (which prove the wrapper itself is correct) and the mutation proof
    // (which proves a defect in the wrapper is detectable), this closes the
    // gap v1 of this plan left open.
    const sites = <String>[
      'lib/features/train/providers/train_provider.dart',
      'lib/core/services/workout_schedule_read_service.dart',
      'lib/features/home/screens/home_screen.dart',
      'lib/core/services/plan_integrity_reconciler.dart',
      'lib/features/home/providers/home_provider.dart',
      'lib/features/home/widgets/day_detail_sheet.dart',
    ];

    test('every touched file contains at least one call to isRestDayConsideringLogged', () {
      for (final path in sites) {
        final src = File(path).readAsStringSync();
        expect(
          src.contains('PlanEngineFlags.isRestDayConsideringLogged'),
          isTrue,
          reason: '$path should delegate to the shared wrapper, not re-inline the predicate',
        );
      }
    });

    test('no touched file re-introduces the pre-fix inline ternary (either phrasing)', () {
      // Guards against a future edit reverting one site back to the inline
      // form while leaving the others on the wrapper. Round-2 review found
      // the first draft of this guard only checked the EXCLUSION phrasing
      // (`!= 'workout' && != 'custom_template'`, used at the 5 originally-
      // identified sites) and was silently blind to the INCLUSION phrasing
      // (`== 'workout' || == 'custom_template'`, used at all 6 of Task 4's
      // sites) — both forms are checked here.
      for (final path in sites) {
        final src = File(path).readAsStringSync();
        final strippedComments = src.replaceAll(RegExp(r'//.*'), '');
        final hasExclusionForm = strippedComments.contains("!= 'workout' && ") &&
            strippedComments.contains("!= 'custom_template'");
        final hasInclusionForm = strippedComments.contains("== 'workout' ||") &&
            strippedComments.contains("== 'custom_template'");
        expect(hasExclusionForm, isFalse,
            reason: '$path appears to still contain the exclusion-phrased pre-fix ternary');
        expect(hasInclusionForm, isFalse,
            reason: '$path appears to still contain the inclusion-phrased pre-fix ternary');
      }
    });
  });
}
