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

  // F2 (audit 2026-06-07): the L8 reader-side gap that let rank_ladder_screen
  // read total_workouts_done under the DEPLOYMENTS label while the RANK card read
  // deployments_complete — two surfaces showing different numbers for the same
  // user. Pin BOTH display readers to deployments_complete.
  group('F2 — both DEPLOYMENTS display readers source deployments_complete', () {
    String strip(String s) {
      final noBlock = s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
      return noBlock
          .split('\n')
          .map((l) {
            final i = l.indexOf('//');
            return i >= 0 ? l.substring(0, i) : l;
          })
          .join('\n');
    }

    test('rank_ladder_screen + service_record_section both read deployments_complete', () {
      final ladder =
          strip(File('lib/features/profile/screens/rank_ladder_screen.dart').readAsStringSync());
      final record =
          strip(File('lib/features/profile/widgets/service_record_section.dart').readAsStringSync());

      expect(ladder.contains("progress['deployments_complete']"), isTrue,
          reason: 'rank_ladder DEPLOYMENTS tile must read deployments_complete (F2)');
      expect(record.contains("progress['deployments_complete']"), isTrue,
          reason: 'service_record DEPLOYMENTS must read deployments_complete');
      // The F2 regression: reading total_workouts_done under the DEPLOYMENTS label.
      expect(ladder.contains("final deployments = (progress['total_workouts_done']"), isFalse,
          reason: 'F2: rank_ladder DEPLOYMENTS must NOT read total_workouts_done');
    });
  });
}
