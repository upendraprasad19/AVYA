// U2 safe-omission edge (review CRIT-1 general case).
//
// When every universal-pool move for a slot's pattern is contraindicated for
// the user, the slot must be SAFELY OMITTED — a distinct outcome from a bug
// `(none)` — so production `_cascadeFill` returns null (drops the slot, never
// injures the user) and the Batch-0 harness classifies it as `safelyOmitted`
// (a gate PASS), NOT `missing` (a hard failure). No matrix persona triggers this
// today (the one unsafe pattern, shoulder_isolation, has safe pool members), so
// this synthetic test is the coverage for the drop-safe path.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'v4_diagnostic/cascade_tracer.dart';

void main() {
  const slot = MuscleSlot(
    targetMuscle: 'Rear Delts',
    movementPattern: 'shoulder_isolation',
    exerciseType: 'isolation',
    priority: 3,
  );

  // A library where the ONLY shoulder_isolation exercises are the three
  // universal-pool members, all shoulder-contraindicated.
  final allContraLibrary = <Map<String, dynamic>>[
    for (final name in const ['Pike Push Up', 'Arm Circles', 'Band Pull Apart'])
      {
        'name': name,
        'movement_pattern': 'shoulder_isolation',
        'exercise_type': 'isolation',
        'target_focus': 'rear delt',
        'primary_muscles': const ['rear deltoid'],
        'equipment_tier': const ['full_gym'],
        'suitable_for': const ['Beginner', 'Intermediate', 'Advanced'],
        'is_foundational': true,
        'injury_contraindications': const ['shoulder'],
      },
  ];

  test('whole pool contraindicated → safelyOmitted, not (none)', () {
    final trace = CascadeTracer.trace(
      allContraLibrary,
      slot: slot,
      equipmentTier: 'full_gym',
      effectiveExp: 'advanced',
      phase: 1,
      injuries: const ['shoulder'],
      pickedNames: <String>{},
    );
    expect(trace.finalPick, isNotNull);
    expect(
      trace.finalPick!.source,
      CascadePickSource.safelyOmitted,
      reason: 'every shoulder_isolation move is shoulder-contraindicated → the '
          'slot is safely omitted, not a bug-(none)',
    );
  });

  test('no injuries → same pool resolves to a real pick (no false omission)', () {
    final trace = CascadeTracer.trace(
      allContraLibrary,
      slot: slot,
      equipmentTier: 'full_gym',
      effectiveExp: 'advanced',
      phase: 1,
      injuries: const [],
      pickedNames: <String>{},
    );
    expect(trace.finalPick, isNotNull);
    expect(trace.finalPick!.source, isNot(CascadePickSource.safelyOmitted),
        reason: 'an uninjured user must still get a real pick from the pool');
  });
}
