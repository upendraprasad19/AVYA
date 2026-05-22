// test/contracts/phase_history_screen_test.dart
//
// Contract — Theme H-followup (closes-diagnose 5cb912).
//
// Pins:
//   - PhaseHistoryScreen file exists at the expected path.
//   - GoRouter declares /train/history route with name 'phaseHistory'.
//   - GraduationScreen surfaces a "VIEW PAST PHASES" entry point that
//     pushes /train/history.
//   - Screen reads schedule_* keys from workoutBox (Theme H's
//     upsertScheduled completed-day guard keeps the data intact).
//
// Source-grep with comment-stripping per
// `feedback_source_grep_strip_comments_first.md`.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

void main() {
  test('phase_history_screen.dart exists', () {
    expect(
      File('lib/features/train/screens/phase_history_screen.dart')
          .existsSync(),
      isTrue,
      reason: 'PhaseHistoryScreen must live at the expected path so '
          'app_router.dart import resolves.',
    );
  });

  test('GoRouter declares /train/history route as phaseHistory', () {
    final src = _strip(
        File('lib/core/router/app_router.dart').readAsStringSync());
    expect(
      RegExp(r"path:\s*'history'[\s\S]{0,200}?"
              r"name:\s*'phaseHistory'")
          .hasMatch(src),
      isTrue,
      reason: 'app_router.dart must declare a /train/history GoRoute '
          'with name `phaseHistory` and builder returning '
          'PhaseHistoryScreen.',
    );
    expect(
      src.contains('PhaseHistoryScreen()'),
      isTrue,
      reason: 'router must instantiate PhaseHistoryScreen.',
    );
  });

  test('graduation_screen surfaces VIEW PAST PHASES entry point', () {
    final src = _strip(
        File('lib/features/train/screens/graduation_screen.dart')
            .readAsStringSync());
    expect(
      src.contains("'VIEW PAST PHASES'"),
      isTrue,
      reason: 'graduation_screen must offer a "VIEW PAST PHASES" entry '
          '— the natural place for the founder to reflect on completed '
          'phases at graduation time.',
    );
    expect(
      src.contains("context.push('/train/history')"),
      isTrue,
      reason: 'entry point must push /train/history (push not go — '
          'history is a sub-route the user backs out of).',
    );
  });

  test('PhaseHistoryScreen reads schedule_* keys (Theme H data path)', () {
    final src = _strip(
        File('lib/features/train/screens/phase_history_screen.dart')
            .readAsStringSync());
    expect(
      src.contains("startsWith('schedule_')"),
      isTrue,
      reason: 'PhaseHistoryScreen must read schedule_* entries from the '
          'workoutBox — same data source as the train screen weekly '
          'renderer. Theme H (b0baa5) guards these from planGenerator '
          'overwrite, so the history stays intact across phase unlocks.',
    );
  });

  test('PhaseHistoryScreen filters by status==completed', () {
    final src = _strip(
        File('lib/features/train/screens/phase_history_screen.dart')
            .readAsStringSync());
    expect(
      RegExp(r"m\['status'\]\s*==\s*'completed'").hasMatch(src),
      isTrue,
      reason: 'PhaseHistoryScreen must only surface phases with at least '
          'one completed day — empty/in-progress phases are not history.',
    );
  });

  test('PhaseHistoryScreen handles empty state', () {
    final src = _strip(
        File('lib/features/train/screens/phase_history_screen.dart')
            .readAsStringSync());
    expect(
      src.contains('No completed phases yet'),
      isTrue,
      reason: 'empty state copy must inform a new user that the screen '
          'will populate as they complete phases. Per CLAUDE.md §4.4 '
          'rule 13 every screen handles loading / error / empty.',
    );
  });
}
