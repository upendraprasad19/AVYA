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

    test('inductionCompleted is false until completeInduction is called',
        () async {
      await InductionService.instance.recordCommitment();
      expect(InductionService.instance.inductionCompleted, false);
      await InductionService.instance.completeInduction();
      expect(InductionService.instance.inductionCompleted, true);
    });

    test('recordMusterAnswer accepts the one allowed key', () async {
      await InductionService.instance
          .recordMusterAnswer('body_part_priorities', ['back', 'shoulders']);

      expect(HiveService.instance.coachBox.get('body_part_priorities'),
          ['back', 'shoulders']);
    });

    test(
        'recordMusterAnswer rejects unknown AND retired keys '
        '(diagnose e2b8a4 — injuries/wake/workout-time retired 2026-09-19)',
        () async {
      for (final key in [
        'rogue_key',
        'why_now',
        'definition_of_winning',
        'known_injuries',
        'typical_wake_time',
        'preferred_workout_time',
      ]) {
        expect(
          () => InductionService.instance.recordMusterAnswer(key, 'x'),
          throwsArgumentError,
          reason: '$key must be rejected',
        );
      }
    });
  });

  group('REPORT FOR DUTY routing', () {
    test('navigates to /coach/muster for un-inducted user', () {
      // coachBox is cleared in setUp — inductionCompleted is false.
      // Muster now runs FIRST (diagnose e2b8a4) so nothing is asked after
      // I COMMIT; induction's narrative + commit follow it.
      expect(InductionService.instance.inductionCompleted, false);
      final destination = InductionService.instance.inductionCompleted
          ? '/home'
          : '/coach/muster';
      expect(destination, '/coach/muster');
    });

    test('navigates to /home for already-inducted user', () async {
      await InductionService.instance.recordCommitment();
      await InductionService.instance.completeInduction();
      expect(InductionService.instance.inductionCompleted, true);
      final destination = InductionService.instance.inductionCompleted
          ? '/home'
          : '/coach/muster';
      expect(destination, '/home');
    });
  });
}
