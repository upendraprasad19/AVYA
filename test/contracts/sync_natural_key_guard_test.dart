import 'package:flutter_test/flutter_test.dart';

import '_sync_service_source.dart';

/// Audit 2026-05-15 — belt-and-suspenders null-key guard contract.
///
/// Background: audit 2026-05-12 P0-A + P0-B (closes-diagnose 3f8a91)
/// switched four sync upserts to natural-key onConflict targets after
/// production telemetry showed 47 × `23505` PostgrestException rows in
/// 24h. The natural keys are:
///
///   workout_logs                 → (user_id, date, exercise_name)
///   workout_log_exercises        → (workout_log_id, exercise_id, set_number)
///   workout_log_sets             → (workout_log_id, exercise_id, set_number)
///   nutrition_logs               → (user_id, date, meal_type)
///
/// The natural-key columns are guarded by partial UNIQUE indexes — if
/// the client ships a row whose natural-key columns are NULL/empty, two
/// failure modes are possible:
///   1. PostgREST 23502 (not_null_violation) on a NOT NULL column,
///      where the row is silently dropped (caught by outer try/catch).
///   2. The natural-key columns are nullable on cloud (future schema
///      regression) and PostgREST merges multiple unrelated rows onto
///      a single null-keyed cloud row — silent data loss.
///
/// Defence: every upsert site reads the natural-key columns into local
/// vars, validates them, and if any are null/empty:
///   - emits `ErrorTelemetry.logEvent('sync_skipped_null_natural_key', ...)`
///     so we can audit production occurrences via `client_errors`
///   - `continue`s the outer loop, preserving the source-row in Hive
///     for the next sync attempt (the underlying data is still safe).
///
/// This test source-greps each upsert site to assert the guard pattern
/// is present and emits the expected `sync_skipped_null_natural_key`
/// op_type. Pinned by the same `_sync_service_source.dart` facade used
/// by every other writer/reader contract in this folder.
///
/// closes-diagnose: 2026-05-15-sync-null-key-guard-9f4ab2
void main() {
  late String syncSrc;

  setUpAll(() {
    // Strip comments BEFORE windowing (per
    // feedback_source_grep_strip_comments_first.md + debugging skill
    // §2.18). Diagnose c9f2a7 (2026-06-01) added a ~28-line explanatory
    // comment block between the nutrition guard's `log['date']` read and
    // its upsert marker, pushing the guard outside the char window and
    // breaking this test even though the guard code was unchanged.
    // Stripping makes the window measure CODE distance, not prose, so
    // future comment churn can't re-break the contract. Stripping only
    // moves each guard CLOSER to its marker, so the other groups stay
    // green. The sync sources contain no `://` (verified), so the naive
    // line-comment strip can't eat a URL string.
    syncSrc = _stripComments(loadSyncServiceSource().readAsStringSync());
  });

  /// Return the slice of `syncSrc` that ends at the upsert call
  /// matching [marker] and reaches back [windowChars] characters.
  String windowBefore(String marker, {int windowChars = 800}) {
    final idx = syncSrc.indexOf(marker);
    expect(idx, greaterThan(0),
        reason: 'upsert marker must exist in concatenated sync source: '
            '$marker');
    final start = (idx - windowChars).clamp(0, syncSrc.length);
    return syncSrc.substring(start, idx);
  }

  group('sync_skipped_null_natural_key guard — workout_logs', () {
    final marker =
        "from('workout_logs').upsert({";
    test('guard reads natural-key columns and skips on null/empty', () {
      final pre = windowBefore(marker);
      // Reads `date` + `workout_name` (exercise_name is sourced from
      // workout_name in this projection).
      expect(pre.contains("log['date']"), isTrue,
          reason: 'workout_logs guard must read log[date]');
      expect(pre.contains("log['workout_name']"), isTrue,
          reason: 'workout_logs guard must read log[workout_name]');
      // Emits telemetry op_type.
      expect(pre.contains("'sync_skipped_null_natural_key'"), isTrue,
          reason: 'workout_logs guard must emit '
              "ErrorTelemetry.logEvent('sync_skipped_null_natural_key', ...)");
      // Skips via continue so the outer loop preserves the source row.
      expect(pre.contains('continue;'), isTrue,
          reason: 'workout_logs guard must `continue` past the upsert when '
              'the natural-key is null/empty');
    });
  });

  group(
      'sync_skipped_null_natural_key guard — workout_log_exercises (summary)',
      () {
    final marker =
        "from('workout_log_exercises').upsert({";
    test('guard validates workout_log_id + exercise_id', () {
      final pre = windowBefore(marker);
      // Guard pulls workoutLogId / exerciseId into local guards.
      expect(
        pre.contains('workout_log_exercises') &&
            pre.contains("'sync_skipped_null_natural_key'"),
        isTrue,
        reason: 'workout_log_exercises summary upsert must be preceded by a '
            "'sync_skipped_null_natural_key' telemetry emission",
      );
      expect(pre.contains('continue;'), isTrue,
          reason: 'workout_log_exercises guard must `continue` on null key');
    });
  });

  group('sync_skipped_null_natural_key guard — workout_log_sets (per-set)',
      () {
    final marker =
        "from('workout_log_sets')";
    test('guard validates workout_log_id + exercise_id + set_number', () {
      // windowChars spans the wls_reps_out_of_range clamp now sitting between
      // the set_number guard and the upsert (diagnose d9a4f2); the guard still
      // `continue`s past the upsert, it is just further from the marker now.
      final pre = windowBefore(marker, windowChars: 2600);
      expect(
        pre.contains('workout_log_sets') &&
            pre.contains("'sync_skipped_null_natural_key'"),
        isTrue,
        reason: 'workout_log_sets per-set upsert must be preceded by a '
            "'sync_skipped_null_natural_key' telemetry emission",
      );
      // Per-set rows already skip when setNum is null; the explicit
      // telemetry on the set_number_null path makes it auditable.
      expect(pre.contains('set_number_null=true'), isTrue,
          reason: 'workout_log_sets guard must telemetry-flag '
              'set_number_null=true when individual per-set rows are '
              'dropped for a missing set_number');
    });
  });

  group('sync_skipped_null_natural_key guard — nutrition_logs', () {
    final marker = 'from("nutrition_logs").upsert(';
    test('guard reads date + meal_type and skips on null/empty', () {
      // Wider window than the 800 default: even with comments stripped,
      // the guard's `log['date']` read sits ~1.5K chars above the marker
      // because the c9f2a7 `parentPayload` map is legitimately long code.
      final pre = windowBefore(marker, windowChars: 2000);
      expect(pre.contains("log['date']"), isTrue,
          reason: 'nutrition_logs guard must read log[date]');
      expect(pre.contains("log['meal_type']"), isTrue,
          reason: 'nutrition_logs guard must read log[meal_type]');
      expect(pre.contains("'sync_skipped_null_natural_key'"), isTrue,
          reason: 'nutrition_logs guard must emit '
              "ErrorTelemetry.logEvent('sync_skipped_null_natural_key', ...)");
      expect(pre.contains('continue;'), isTrue,
          reason: 'nutrition_logs guard must `continue` on null key');
    });
  });

  group('telemetry op_type appears 4+ times in the sync layer', () {
    test('op_type construction count', () {
      // syncSrc is comment-stripped in setUpAll, so this counts only the
      // real `ErrorTelemetry.logEvent('sync_skipped_null_natural_key', …)`
      // CODE sites (4 guards + the per-set extra = 5), never a comment.
      final occurrences = "'sync_skipped_null_natural_key'"
          .allMatches(syncSrc)
          .length;
      // 4 upsert sites × 1 guard each = 4 baseline. The per-set helper
      // emits the op_type twice (parent-key empty path + per-row
      // set_number_null path) so 5 is the realistic minimum.
      expect(occurrences, greaterThanOrEqualTo(4),
          reason: 'expected at least 4 occurrences of '
              "'sync_skipped_null_natural_key' (one per guard site) — found "
              '$occurrences');
    });
  });
}

/// Strips `/* … */` block comments and `// …` line comments so the
/// window assertions measure CODE distance, not explanatory prose.
/// Canonical form, matching `no_top_level_duration_seconds_reads_test.dart`
/// (feedback_source_grep_strip_comments_first.md). Safe for the sync
/// sources because none contain `://` (no URL string the naive line-strip
/// could truncate).
String _stripComments(String src) {
  final block = RegExp(r'/\*[\s\S]*?\*/');
  var out = src.replaceAll(block, '');
  final line = RegExp(r'//.*');
  out = out.replaceAll(line, '');
  return out;
}
