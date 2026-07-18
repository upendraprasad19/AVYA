import 'package:flutter_test/flutter_test.dart';

import '_sync_service_source.dart';

/// W3.3 (Batch 11-A) — the library `exercise_id` stays HIVE-LOCAL contract.
///
/// The new forward-only `exlog_*.exercise_id` (a library exercise id written by
/// `WorkoutWriteService.logExercise`, read by `ProgressionResolver` for id-keyed
/// history matching) must NEVER be projected into the cloud `_syncExerciseLogs`
/// upward path. The cloud `workout_log_exercises.exercise_id` column is a
/// DIFFERENT thing — a NAME-derived stable identity
/// (`(log['exercise_name'] as String?) ?? key`) that is the natural-key member
/// of the upsert `onConflict: 'user_id,workout_log_id,exercise_id,set_number'`.
///
/// If a future edit sourced that cloud column from the Hive `log['exercise_id']`
/// (the library id), the onConflict key would shift for every existing row →
/// PostgREST would INSERT duplicates instead of merging (the Round-4c REG
/// constraint: "keep it Hive-local"). This gate pins the separation at the
/// source seam.
///
/// The upward projection's Hive-map variables in `_syncExerciseLogs` are
/// `raw` → `log` (the summary row) and `sm` (the per-set row). The downward
/// restore path uses a DIFFERENT variable (`map` / `row`) and legitimately reads
/// the cloud `map['exercise_id']` — so a `map[...]` read is NOT flagged.
///
/// Comment-stripped first (feedback_source_grep_strip_comments_first.md) so
/// prose mentioning `log['exercise_id']` can't trip or mask the assertion.
void main() {
  late String syncSrc;

  setUpAll(() {
    syncSrc = _stripComments(loadSyncServiceSource().readAsStringSync());
  });

  group('library exercise_id never leaks into the cloud sync payload', () {
    test('_syncExerciseLogs upward-map vars never read [exercise_id]', () {
      // Summary-row Hive map (`raw` cast to `log`) — the library id must not be
      // read into the cloud projection.
      expect(syncSrc.contains("log['exercise_id']"), isFalse,
          reason: 'the summary-row projection must NOT read the Hive library '
              "log['exercise_id'] — the cloud exercise_id is name-derived");
      expect(syncSrc.contains("raw['exercise_id']"), isFalse,
          reason: 'the pre-cast exlog row must NOT read raw[exercise_id]');
      // Per-set Hive map (`sm`).
      expect(syncSrc.contains("sm['exercise_id']"), isFalse,
          reason: 'the per-set projection must NOT read sm[exercise_id]');
    });

    test('cloud exercise_id stays the NAME-derived stable identity', () {
      // The positive contract: the cloud identity is still sourced from
      // exercise_name (fallback key), NOT the library id.
      expect(
        syncSrc.contains("(log['exercise_name'] as String?) ?? key"),
        isTrue,
        reason: 'the cloud exercise_id must remain '
            "(log['exercise_name'] as String?) ?? key — the name-derived "
            'natural-key identity',
      );
    });

    test('exercise-log upserts keep the name-derived natural onConflict key', () {
      // Both the summary and per-set upserts must keep the unchanged natural
      // key, so the (unchanged, name-derived) exercise_id cannot mint duplicates.
      final occurrences =
          "onConflict: 'user_id,workout_log_id,exercise_id,set_number'"
              .allMatches(syncSrc)
              .length;
      expect(occurrences, greaterThanOrEqualTo(2),
          reason: 'workout_log_exercises (summary) + workout_log_sets (per-set) '
              'must both keep onConflict '
              "'user_id,workout_log_id,exercise_id,set_number' — found "
              '$occurrences');
    });
  });
}

/// Strips `/* … */` block comments and `// …` line comments. Canonical form,
/// matching `sync_natural_key_guard_test.dart`
/// (feedback_source_grep_strip_comments_first.md). Safe for the sync sources
/// because none contain `://` (no URL string the naive line-strip could eat).
String _stripComments(String src) {
  final block = RegExp(r'/\*[\s\S]*?\*/');
  var out = src.replaceAll(block, '');
  final line = RegExp(r'//.*');
  out = out.replaceAll(line, '');
  return out;
}
