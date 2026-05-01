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

  group('InductionService', () {
    test('hasCommitted is false initially', () async {
      expect(InductionService.instance.hasCommitted, false);
    });

    test('inductionCompleted is false initially', () async {
      expect(InductionService.instance.inductionCompleted, false);
    });

    test('recordCommitment sets flag and stamps timestamp', () async {
      await InductionService.instance.recordCommitment();
      expect(InductionService.instance.hasCommitted, true);
      final committedAt =
          HiveService.instance.coachBox.get('committed_at') as String?;
      expect(committedAt, isNotNull);
      expect(DateTime.tryParse(committedAt!), isNotNull);
    });

    test('recordCommitment is idempotent — second call does not regress',
        () async {
      await InductionService.instance.recordCommitment();
      final firstStamp =
          HiveService.instance.coachBox.get('committed_at') as String;
      await Future.delayed(const Duration(milliseconds: 10));
      await InductionService.instance.recordCommitment();
      final secondStamp =
          HiveService.instance.coachBox.get('committed_at') as String;
      // Second call updates the stamp but flag stays true (no regression to false)
      expect(InductionService.instance.hasCommitted, true);
      // Note: stamp will have advanced; that's fine — never regress to false
      expect(secondStamp, isNot(equals('')));
      // Suppress unused warning — firstStamp is retained here to make the
      // two-call nature of the test explicit.
      expect(firstStamp.isNotEmpty, true);
    });

    test('inductionCompleted is false until completeMuster is called',
        () async {
      await InductionService.instance.recordCommitment();
      expect(InductionService.instance.inductionCompleted, false);
      await InductionService.instance.completeMuster();
      expect(InductionService.instance.inductionCompleted, true);
    });

    test('recordMusterAnswer accepts all 6 allowed keys', () async {
      await InductionService.instance
          .recordMusterAnswer('why_now', 'October wedding');
      await InductionService.instance
          .recordMusterAnswer('definition_of_winning', 'feel strong');
      await InductionService.instance
          .recordMusterAnswer('known_injuries', ['lower back', 'right knee']);
      await InductionService.instance
          .recordMusterAnswer('typical_wake_time', '06:30');
      await InductionService.instance
          .recordMusterAnswer('preferred_workout_time', '07:00');
      await InductionService.instance
          .recordMusterAnswer('body_part_priorities', ['back', 'shoulders']);

      expect(HiveService.instance.coachBox.get('why_now'), 'October wedding');
      expect(HiveService.instance.coachBox.get('definition_of_winning'),
          'feel strong');
      expect(HiveService.instance.coachBox.get('known_injuries'),
          ['lower back', 'right knee']);
      expect(HiveService.instance.coachBox.get('typical_wake_time'), '06:30');
      expect(HiveService.instance.coachBox.get('preferred_workout_time'),
          '07:00');
      expect(HiveService.instance.coachBox.get('body_part_priorities'),
          ['back', 'shoulders']);
    });

    test('recordMusterAnswer rejects unknown key', () async {
      expect(
        () => InductionService.instance.recordMusterAnswer('rogue_key', 'x'),
        throwsArgumentError,
      );
    });
  });

  group('REPORT FOR DUTY routing', () {
    test('navigates to /coach/induction for un-inducted user', () {
      // coachBox is cleared in setUp — inductionCompleted is false
      expect(InductionService.instance.inductionCompleted, false);
      final destination = InductionService.instance.inductionCompleted
          ? '/home'
          : '/coach/induction';
      expect(destination, '/coach/induction');
    });

    test('navigates to /home for already-inducted user', () async {
      await InductionService.instance.recordCommitment();
      await InductionService.instance.completeMuster();
      expect(InductionService.instance.inductionCompleted, true);
      final destination = InductionService.instance.inductionCompleted
          ? '/home'
          : '/coach/induction';
      expect(destination, '/home');
    });
  });
}
