// test/contracts/graduation_stats_provider_field_test.dart
//
// Contract — graduation TOTAL_SETS + PR count drift fix (closes-diagnose
// <id>). 10th instance of writer/reader drift per debugging skill §2.1.
//
// Pre-fix: lib/features/train/providers/train_provider.dart's
// `graduationStatsProvider` iterated workoutBox.values, filtered by
// `log['type'] == 'exercise_log'` (a field WorkoutWriteService never
// writes — type field is unset on every exlog_* row) AND read
// `log['sets_completed']` (legacy field name; canonical writer field
// is `set_number` per hive_field_name_exlog SoT). Both wrong — every
// user, every phase unlock, sees TOTAL SETS = 0.
//
// PR count was also stale — pre-fix counted per-log `is_pr` boolean
// flags rather than delegating to the canonical
// `allExercisePRsProvider` (per lib/features/home/CLAUDE.md +
// `exercise_personal_records` SoT).
//
// This contract pins:
//   1. The `type == 'exercise_log'` filter is GONE (never written).
//   2. The `set_number` canonical field is the primary read.
//   3. `sets_completed` legacy fallback is preserved.
//   4. Aggregation walks `exlog_*` keys, not `log['type']` filter.
//   5. PR count delegates to allExercisePRsProvider (canonical source).
//
// Source-grep with comment-stripping per
// `feedback_source_grep_strip_comments_first.md`.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

String _extractProviderBody(String src) {
  // Locate `final graduationStatsProvider = Provider<...>((ref) {` and
  // walk to the matching `});`.
  final startIdx = src.indexOf('final graduationStatsProvider');
  if (startIdx < 0) return '';
  final openBrace = src.indexOf('{', startIdx);
  if (openBrace < 0) return '';
  int depth = 1;
  int i = openBrace + 1;
  while (i < src.length && depth > 0) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') depth--;
    i++;
  }
  return src.substring(openBrace, i);
}

void main() {
  late String body;

  setUpAll(() {
    final file = File('lib/features/train/providers/train_provider.dart');
    expect(file.existsSync(), isTrue,
        reason: 'train_provider.dart must exist at expected path');
    final stripped = _stripComments(file.readAsStringSync());
    body = _extractProviderBody(stripped);
    expect(body.isNotEmpty, isTrue,
        reason: 'could not locate graduationStatsProvider body');
  });

  test('does not filter by log[type] == exercise_log (writer never sets type)',
      () {
    // The pre-fix predicate. Writer (WorkoutWriteService.logExercise at
    // lib/core/services/workout_write_service.dart:166) stamps no `type`
    // field on exlog_* rows. Filtering by it returned ZERO rows on every
    // user, every phase unlock.
    expect(
      body.contains("log['type'] == 'exercise_log'"),
      isFalse,
      reason:
          "graduationStatsProvider must not filter by log['type'] == 'exercise_log' — "
          "WorkoutWriteService never writes a `type` field; the filter returned "
          "zero rows. Walk exlog_* keys instead.",
    );
    expect(
      body.contains('log[\'type\'] == \'workout_log\''),
      isFalse,
      reason:
          "sibling pre-fix branch on workout_log type also must be gone — "
          "no log carries a `type` field.",
    );
  });

  test('aggregates sets by walking exlog_ keys (canonical pattern)', () {
    // The canonical aggregation pattern (used by
    // loadAllExercisePRs at workout_repository.dart:622) iterates
    // workoutBox.toMap().entries and filters `keyStr.startsWith('exlog_')`.
    expect(
      body.contains("startsWith('exlog_')"),
      isTrue,
      reason:
          "graduationStatsProvider must walk exlog_* keys directly (the canonical "
          "pattern from loadAllExercisePRs) instead of relying on a missing `type` filter.",
    );
  });

  test('reads canonical set_number field (with sets_completed fallback)', () {
    // set_number is the canonical writer field per hive_field_name_exlog SoT
    // and WorkoutWriteService.logExercise at workout_write_service.dart:171.
    expect(
      body.contains("log['set_number']"),
      isTrue,
      reason:
          "graduationStatsProvider must read log['set_number'] — canonical "
          "writer field since Test #6 (hive_field_name_exlog SoT).",
    );
    // Legacy fallback for rows written pre-Test-#6 (or by sync-restore from
    // older clients).
    expect(
      body.contains("log['sets_completed']"),
      isTrue,
      reason:
          "graduationStatsProvider must keep a sets_completed fallback for "
          "legacy rows / cross-version restore (see EditLogExerciseRow.fromLog "
          "dual-name pattern).",
    );
  });

  test('PR count delegates to allExercisePRsProvider (canonical source)', () {
    // exercise_personal_records SoT canonical reader is
    // allExercisePRsProvider at home_provider.dart:825 — same source as
    // home PRSnapshot + profile rank ladder.
    expect(
      body.contains('ref.watch(allExercisePRsProvider)'),
      isTrue,
      reason:
          'graduationStatsProvider must source PR count + top PRs from '
          'allExercisePRsProvider — the canonical exercise_personal_records '
          'reader. Counting per-log is_pr flags drifts (legacy rows and '
          'sync-restore may carry stale flags).',
    );
  });
}
