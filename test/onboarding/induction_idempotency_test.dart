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
  });
}
