// This file grows across Tasks 3, 4, and 6 — Task 3 adds only the first group.
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
}
