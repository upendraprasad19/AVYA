// d7a3e5 (Piece B) - presence-only manifest for the `lapse_gap_policy` SoT
// concept (Gate 9 file name). The behavior lives in
// lapse_gap_policy_behavioral_test.dart, lapse_gap_freeze_reset_advance_test.dart,
// test/core/gap_policy_test.dart and supabase/functions/_shared/rank_engine_blank_days_test.ts.
//
// Pins WHO writes and WHO reads, by name, so a rename or a second door shows up:
//   writers: phaseStartAfterGap (gap_policy.dart), resetFreezesAfterGap
//            (streak_progress_service.dart, called ONLY from pro_phase_advance.dart)
//   readers: _calculateStreak + completionRateOverWindow (workout_repository.dart),
//            _getPlanStatus (ai_snapshot_builder.dart), rank_engine.ts.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String path) => File(path)
    .readAsStringSync()
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  test('resetFreezesAfterGap has exactly the two committed-advance callers', () {
    final callers = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (e.path.endsWith('streak_progress_service.dart')) continue;
      final n = 'resetFreezesAfterGap('.allMatches(_src(e.path)).length;
      // Windows walks with `\`; the expectation is written with `/`.
      if (n > 0) callers.add('${e.path.replaceAll(r'\', '/')}:$n');
    }
    expect(callers, ['lib/shared/services/pro_phase_advance.dart:2']);
  });

  test('the start date has one home: nextPhaseStartDate -> phaseStartAfterGap', () {
    expect(
        _src('lib/core/services/workout_schedule_read_service.dart')
            .contains('phaseStartAfterGap('),
        isTrue);
  });

  test('the streak, the rate and the coach all consult the policy switch', () {
    expect(_src('lib/features/train/repositories/workout_repository.dart')
        .contains('lapseGapPolicyEnabled'), isTrue);
    expect(_src('lib/features/ai_coach/services/ai_snapshot_builder.dart')
        .contains('lapseGapPolicyEnabled'), isTrue);
  });

  test('the server rank cron opts in to blank days', () {
    expect(
        File('supabase/functions/evaluate-rank-promotions/index.ts')
            .readAsStringSync()
            .contains('windowWeeks, true)'),
        isTrue);
  });
}
