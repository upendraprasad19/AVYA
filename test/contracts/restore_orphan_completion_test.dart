// Regression contract for APK +34 / obs 5.2 (diagnose e9b4a2): when cloud
// workout_schedule_completions has a completion for a date with NO local
// schedule_<date> row (an out-of-plan-window completion — logged ad-hoc, or a
// past phase the current plan_json window no longer covers), restore must
// SYNTHESIZE a completed schedule row. Pre-fix it skipped silently, so after a
// reinstall the streak walk (_calculateStreak reads schedule_<date>
// status=='completed') and the past-phase scroll-back saw nothing → streak 0
// despite real workouts.
//
// Source-grep (presence) over the restore-writer addition. The streak-counting
// semantic of a completed/logged schedule row is established behavior; a full
// restore round-trip behavioral case is the follow-up (behavioral_test_required
// on the restore_completeness SoT concept).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _strip(String src) {
  var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s
      .split('\n')
      .map((line) {
        final m = RegExp(r'(?<!:)//').firstMatch(line);
        return m == null ? line : line.substring(0, m.start);
      })
      .join('\n');
  return s;
}

void main() {
  test('restore synthesizes a completed row for an orphan completion', () {
    final src =
        _strip(File('lib/core/services/sync/sync_workout.dart').readAsStringSync());
    expect(src.contains('cloud_restore_completion'), isTrue,
        reason:
            'a completion with no local schedule row must synthesize one (was skipped)');
    expect(src.contains("'type': 'logged'"), isTrue,
        reason:
            'synthesized row must be a workout day so the streak walk counts it');
  });
}
