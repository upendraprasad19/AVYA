// CLAUDE.md §19 entry #147 regression test (CLAUDE.md decluttering Milestone 4).
//
// Pins the rule: Cloud `workout_logs.rpe` column is projected by
// `_syncWorkoutLogs` in the sync service (Audit 2026-05-12 P2-F).
//
// IMPORTANT — RULE STATUS AT MILESTONE 4 (2026-05-18):
// Migration 067 (`067_drop_dead_columns.sql`) DROPPED `workout_logs.rpe`
// because the cloud column was 100% NULL (audit-2026-05-16 E.12). The Hive
// field is retained for restore round-trip + migrators, but the cloud
// projection no longer carries the value. Per `sync_workout.dart:110-112`:
//
//   // audit-2026-05-16 E.12 — `sets_completed`, `rpe` columns dropped
//   // from workout_logs in migration 067 (cloud was 100% NULL). Hive
//   // fields retained for restore round-trip + migrators.
//
// As a result, the §19 #147 rule as written (projection MUST include `'rpe':`)
// is STALE and cannot be enforced by source-grep. This test inverts the
// assertion: the projection MUST NOT include `'rpe':` because doing so would
// 23502-reject against a column that no longer exists.
//
// Recommendation: reclassify §19 entry #147 from Class B → Class D (delete
// outright) in the Milestone 6 sweep. The rule it pinned was superseded by
// migration 067; the entry is now actively misleading.
//
// Source-grep contract — strips comments first per
// feedback_source_grep_strip_comments_first.md (the audit notes block in
// sync_workout.dart quotes `'rpe'` in comments).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strip Dart line + block comments before source-grep.
String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  test('§19 #147 — workout_logs upsert projection must NOT include rpe (column dropped in migration 067)', () {
    final file = File('lib/core/services/sync/sync_workout.dart');
    expect(file.existsSync(), isTrue,
        reason:
            'Expected lib/core/services/sync/sync_workout.dart to exist '
            '(home of _syncWorkoutLogs).');

    final src = file.readAsStringSync();
    final stripped = _stripComments(src);

    // Find the upsert block targeting the `workout_logs` table and confirm
    // it does not project `'rpe':`. The block starts at `.from('workout_logs').upsert({`
    // and runs to the closing `}`. We scan the whole stripped source for
    // any literal `'rpe':` to keep the test resilient to formatting changes.
    final hasRpeProjection =
        stripped.contains("'rpe':") || stripped.contains('"rpe":');

    expect(hasRpeProjection, isFalse,
        reason:
            'Found `\'rpe\':` (or `"rpe":`) projection in sync_workout.dart. '
            'Migration 067 dropped `workout_logs.rpe` — projecting this field '
            'will 23502-reject the upsert. The Hive field is retained for '
            'restore round-trip, but it must not be sent to cloud. See '
            'sync_workout.dart audit comment dated 2026-05-16 E.12.');
  });
}
