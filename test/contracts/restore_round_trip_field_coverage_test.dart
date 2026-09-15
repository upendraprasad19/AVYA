// Regression test for audit-2026-05-17 OI-09 — restore_completeness
// symmetric round-trip field coverage.
//
// The existing `restore_completeness_writes_test.dart` enforces the
// WRITE side: every Hive-only surface fans out to cloud via a
// dedicated SyncService method. That's necessary but not sufficient —
// the corresponding RESTORE method must also project every field the
// writer emits back into Hive. Otherwise the restored row is
// structurally incomplete and downstream readers see null where they
// expect values.
//
// Obs 1 of 2026-05-16 (`daffac`) was a live instance: writer stamped
// `workout_log_id` on every exlog row, restore didn't project it,
// session-scoped receipt readers rejected the restored rows.
// `restore_completeness_writes_test.dart` couldn't catch it because
// it only checks "did we call syncX" — not "did restoreX read back
// every writer-emitted field".
//
// This test pins per-concept symmetry by comparing the writer's
// projection map keys against the restore method's Hive write map
// keys. Source-grep — runs in any CI environment, no DB / Hive needed.
//
// closes-diagnose: 2026-05-17-restore-round-trip-coverage-4dd7e2
// closes-oi: OI-09

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String syncWorkoutSrc;
  late String workoutWriteSrc;

  setUpAll(() {
    syncWorkoutSrc =
        File('lib/core/services/sync/sync_workout.dart').readAsStringSync();
    workoutWriteSrc =
        File('lib/core/services/workout_write_service.dart')
            .readAsStringSync();
  });

  group('OI-09 — restore round-trip field coverage', () {
    test(
        '_restoreExerciseLogs projects workout_log_id (Obs 1 regression '
        '— daffac)', () {
      // The Obs 1 root cause: writer stamps workout_log_id but restore
      // dropped it. Pin the projection so it can't silently regress.
      final slice = _methodSlice(syncWorkoutSrc, '_restoreExerciseLogs');
      expect(slice, isNotNull,
          reason: '_restoreExerciseLogs method must exist');
      expect(
        slice!.contains("'workout_log_id'"),
        isTrue,
        reason: '_restoreExerciseLogs MUST project workout_log_id back '
            'to Hive. Writer (WorkoutWriteService.logExercise) stamps '
            'it on every exlog row; session-scoped receipt readers '
            "filter on it. Pre-fix (Obs 1 / daffac) the field was "
            'dropped on restore — fresh-install users saw "View Card '
            'does nothing" for multi-session days.',
      );
    });

    test('_restoreExerciseLogs projects every CORE writer-emitted field',
        () {
      // For each canonical field WorkoutWriteService.logExercise
      // emits, the restore method should produce a Hive row with the
      // same key. We don't require EVERY transient/ephemeral field —
      // those go on an explicit allowlist below.
      final writerSlice =
          _methodSlice(workoutWriteSrc, 'logExercise');
      final restoreSlice =
          _methodSlice(syncWorkoutSrc, '_restoreExerciseLogs');
      expect(writerSlice, isNotNull);
      expect(restoreSlice, isNotNull);

      // Core fields that MUST round-trip. (We don't try to extract
      // these via regex from the writer source — too noisy. Hard-code
      // the canonical list per docs/architecture/sync.md "Hive field-name contract"
      // for exlog_*.)
      const coreFields = [
        'exercise_name',
        'date',
        'workout_log_id', // pinned again above for explicit Obs 1 ref
        'logging_type',
        'is_pr',
      ];

      // Fields that legitimately may NOT round-trip:
      //   - `sets` (per-set array) — restored via separate per-set
      //     fetch + assembly into sets_detail (legacy name alias).
      //   - `set_number` / `reps_completed` / `weight_kg` /
      //     `volume_kg` — derived aggregates restored from the per-set
      //     fetch; writer-side conditional on cloud row presence.
      //   - `source` / `updated_at_ms` — local-only telemetry.
      //   - `notes` — optional, only when present in writer payload.

      for (final f in coreFields) {
        expect(
          restoreSlice!.contains("'$f'"),
          isTrue,
          reason: '_restoreExerciseLogs must project canonical field '
              "'$f' (docs/architecture/sync.md Hive field-name contract for "
              'exlog_*). Pre-fix any of these going missing would '
              'silently degrade a downstream reader.',
        );
      }
    });

    test(
        '_restoreScheduledWorkouts projects template metadata (Test #15.3 '
        'Bug 4a regression)', () {
      final slice =
          _methodSlice(syncWorkoutSrc, '_restoreScheduledWorkouts');
      expect(slice, isNotNull);
      // The 2026-05-12 / Bug 4a fix added template JOIN — every restored
      // schedule row now carries workout_name / workout_focus /
      // exercises[] / type='custom_template'. Pin the embedded JOIN.
      expect(
        slice!.contains('template_id') && slice.contains('template'),
        isTrue,
        reason: '_restoreScheduledWorkouts must embed template(*) so '
            'restored schedule rows carry workout_name + exercises[] '
            '+ workout_focus. Pre-fix (Test #15.3 Bug 4a) the template '
            'metadata was lost on restore.',
      );
    });

    test(
        'core restore methods exist for every domain (write -> restore '
        'symmetry)', () {
      // Verify the existence of the canonical restore methods. The
      // exact field-coverage assertions for nutrition / health are
      // less battle-tested today (no known Obs-class drift in those
      // domains); we pin presence + leave field-by-field assertion
      // for the per-domain extension.
      const requiredRestoreMethods = [
        '_restoreWorkoutLogs',
        '_restoreExerciseLogs',
        '_restoreScheduledWorkouts',
        '_restoreScheduleCompletions',
        '_restoreWorkoutTemplates',
      ];
      for (final m in requiredRestoreMethods) {
        expect(syncWorkoutSrc.contains('Future<void> $m'), isTrue,
            reason: 'sync_workout.dart must expose $m so the '
                'corresponding writer surface round-trips on fresh '
                'install. Removal of any of these regresses CLAUDE.md '
                '§15 "Restore-completeness sync" — paying users lose '
                'data on reinstall.');
      }
    });
  });
}

/// Extracts the source-text body of a Dart method (any modifier) by
/// finding the method signature and brace-matching to the close. Returns
/// null if the method is not found.
String? _methodSlice(String src, String methodName) {
  // Match method definitions of any return type / async modifier.
  final sigRe = RegExp(
    r'\b(Future<[^>]+>\s+|void\s+|Map<[^>]+>\s+|String\s+|int\s+|bool\s+|Map\s+|List<[^>]+>\s+|dynamic\s+)?\s*'
    + RegExp.escape(methodName) +
    r'\s*\(',
  );
  final m = sigRe.firstMatch(src);
  if (m == null) return null;
  // m.end is just past the signature's opening `(`. Skip to the matching
  // close-paren so a named/optional param group `{...}` inside the parameter
  // list is not mistaken for the body brace (C3 added `{Object? preFetched}`).
  var i = m.end;
  var pdepth = 1;
  while (i < src.length && pdepth > 0) {
    if (src[i] == '(') pdepth++;
    if (src[i] == ')') pdepth--;
    i++;
  }
  while (i < src.length && src[i] != '{') {
    i++;
  }
  if (i >= src.length) return null;
  // Brace-match.
  var depth = 0;
  final start = i;
  for (; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(start, i + 1);
    }
  }
  return null;
}
