// Behavioral contract: the deployment counter (F18 wiring, diagnose b9f4d2).
//
// 1 deployment = 1 completed phase → deployments_complete = current_phase - 1.
// Stamped in UserRepository.saveProgress (the single progress writer every
// phase-advance path funnels through) and read by RankService._readEvaluationState
// as the PO(>=2)/CPO(>=3) gate input. The field is MONOTONIC / only-increment
// (a lifetime "earned" value per feedback_monotonic_field_recompute_demotion.md):
// a current_phase that moves backward must NOT demote the count.
//
// closes-diagnose: 2026-05-31-rank-cron-nonexistent-columns-b9f4d2
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  group('b9f4d2 — deployments_complete = current_phase - 1 (monotonic)', () {
    test('saveProgress derives the count from current_phase', () async {
      final repo = UserRepository.instance;

      await repo.saveProgress({'current_phase': 1, 'current_week': 1});
      expect(repo.getProgress()!['deployments_complete'], 0,
          reason: 'phase 1 → 0 deployments');

      await repo.saveProgress({'current_phase': 5, 'current_week': 1});
      expect(repo.getProgress()!['deployments_complete'], 4,
          reason: 'phase 5 → 4 deployments');
    });

    test('updateProgress advances the count as phases complete', () async {
      final repo = UserRepository.instance;

      await repo.updateProgress({'current_phase': 1});
      expect(repo.getProgress()!['deployments_complete'], 0);

      await repo.updateProgress({'current_phase': 2});
      expect(repo.getProgress()!['deployments_complete'], 1,
          reason: 'PO gate (deployments>=2) starts opening here');

      await repo.updateProgress({'current_phase': 13});
      expect(repo.getProgress()!['deployments_complete'], 12,
          reason: 'post-phase-12 deployment cycles keep the count climbing');
    });

    test('a backward current_phase does NOT demote the lifetime count', () async {
      final repo = UserRepository.instance;

      await repo.updateProgress({'current_phase': 13});
      expect(repo.getProgress()!['deployments_complete'], 12);

      // e.g. content template recycles / a defensive lower write — the EARNED
      // deployment count must hold (monotonic).
      await repo.updateProgress({'current_phase': 9});
      expect(repo.getProgress()!['deployments_complete'], 12,
          reason: 'monotonic: never demote earned deployments');
    });
  });
}
