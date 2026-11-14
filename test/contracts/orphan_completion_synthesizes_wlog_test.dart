// Bug b3f9d1 — the orphan-completion restore branch
// (_restoreScheduleCompletions, "no local schedule row" / out-of-plan-window
// case) synthesizes a schedule_<date> row (type:'logged') that satisfies the
// streak walk — but it wrote NO wlog_<date> row, so the completion was NOT
// counted by the type=='workout_log' readers (getWeeklyWorkoutCounts → "This
// Week" tile + frequency chart, getWorkoutLogs, badge total, AI snapshot) when
// the SEPARATE workout_logs restore path had no row for that date. Fix: also
// synthesize an ADDITIVE wlog_<date> row (mirroring the canonical f1c8e4 shape:
// type:'workout_log' + completed_at), local-wins so it never overwrites a real
// logged session.
//
// Scoped source-grep (the file legitimately writes type:'workout_log' elsewhere
// — in _restoreWorkoutLogs + _syncWorkoutLogs — so we scope to the synthesize
// branch and strip comments).
//
// closes-diagnose: b3f9d1

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('orphan completion synthesizes a counted wlog_ row (b3f9d1)', () {
    late String scoped;

    setUpAll(() {
      final src =
          File('lib/core/services/sync/sync_workout.dart').readAsStringSync();
      final idx = src.indexOf('_restoreScheduleCompletions(');
      expect(idx, isNot(-1),
          reason: '_restoreScheduleCompletions method must exist');
      final raw = src.substring(idx, (idx + 4000).clamp(0, src.length));
      // Strip comments so the explanatory block doesn't false-positive.
      scoped = raw
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
          .join('\n');
    });

    test('writes an additive wlog_<date> row', () {
      expect(
        scoped.contains(r"'wlog_$date'") || scoped.contains(r'"wlog_$date"'),
        isTrue,
        reason: 'the synthesize branch must put a wlog_<date> row so the '
            'orphan completion is counted by the workout-log readers.',
      );
    });

    test('the synthesized wlog row carries type:workout_log', () {
      expect(
        scoped.contains("'type': 'workout_log'"),
        isTrue,
        reason: 'count/history readers filter type==workout_log; the '
            'synthesized wlog row must carry it (f1c8e4 contract).',
      );
    });

    test('the wlog write is additive (skip-if-local-exists)', () {
      expect(
        RegExp(r"_hive\.workoutBox\.get\(wlogKey\)\s*==\s*null")
            .hasMatch(scoped),
        isTrue,
        reason: 'must only fill the gap — never overwrite a real logged '
            'session (which carries duration + per-exercise data).',
      );
    });
  });
}
