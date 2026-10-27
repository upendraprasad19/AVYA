import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/services/induction_service.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  test('the one muster answer (physique focus) persists to coachBox',
      () async {
    // Diagnose e2b8a4 (2026-09-19): injuries and wake/workout-time were
    // retired as muster questions — recordMusterAnswer now rejects them.
    // See test/contracts/muster_question_count_test.dart +
    // muster_profile_bridge_test.dart for the retirement contract.
    await InductionService.instance
        .recordMusterAnswer('body_part_priorities', ['back', 'shoulders']);

    expect(HiveService.instance.coachBox.get('body_part_priorities'),
        ['back', 'shoulders']);
  });

  test('completeInduction sets induction_completed_at', () async {
    // Renamed from completeMuster (diagnose e2b8a4) — muster is no longer
    // the last step of the sequence, so the terminal stamp is fired from
    // InductionScreen's I COMMIT handler instead.
    await InductionService.instance.recordCommitment();
    await InductionService.instance.completeInduction();
    expect(
        HiveService.instance.coachBox.get('induction_completed_at'),
        isA<String>());
    expect(InductionService.instance.inductionCompleted, true);
  });

  test('unknown muster key throws ArgumentError', () async {
    expect(
      () => InductionService.instance.recordMusterAnswer('bad_key', 'value'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('retired muster keys throw ArgumentError', () async {
    for (final key in [
      'known_injuries',
      'typical_wake_time',
      'preferred_workout_time',
      'why_now',
      'definition_of_winning',
    ]) {
      expect(
        () => InductionService.instance.recordMusterAnswer(key, 'value'),
        throwsA(isA<ArgumentError>()),
        reason: '$key must be rejected — retired muster question',
      );
    }
  });

  test('None chip stores empty list', () async {
    // When user selects 'None' chip, body_part_priorities stores []
    await InductionService.instance
        .recordMusterAnswer('body_part_priorities', <String>[]);
    expect(
        HiveService.instance.coachBox.get('body_part_priorities'),
        isEmpty);
  });
}
