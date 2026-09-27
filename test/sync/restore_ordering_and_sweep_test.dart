import 'package:flutter_test/flutter_test.dart';

import '../contracts/_sync_service_source.dart';

/// APK Test #12.9 — pin two restore-stack contracts.
///
/// 1. `_restoreWorkoutPlan` runs in step A, BEFORE step B's
///    `_restoreScheduledWorkouts` writes the cloud-authoritative
///    `status='completed'` to the same `schedule_<date>` keys. Pre-12.9
///    both ran in parallel via `Future.wait`; the plan-snapshot
///    `status='planned'` could win the race and clobber completed
///    state on logout-login restore. Founder symptom: only Mon DONE
///    despite cloud having Mon/Tue/Wed/Thu completed.
///
/// 2. `_restoreWorkoutTemplates` ends with a stale-key sweep that
///    deletes any `tmpl_*` Hive entries not in the canonical cloud
///    set. Pre-12.9 in-place APK upgrades over a populated workoutBox
///    accumulated stragglers from earlier broken restore-key formulas
///    (8 cards pre-12.8 → 11 cards post-12.8 instead of 3 from cloud).
///
/// Source-grep contract — cheap, durable, regression-proof.
void main() {
  final file = loadSyncServiceSource();
  late final String source;

  setUpAll(() {
    expect(file.existsSync(), isTrue);
    source = file.readAsStringSync();
  });

  group('restore ordering — _restoreWorkoutPlan before _restoreScheduledWorkouts', () {
    test('restoreFromCloudForUser: workout_plan in step A, scheduled_workouts in step B', () {
      // Step A is the FIRST `Future.wait([...])`, step B is the SECOND.
      final stepAStart = source.indexOf("// Step A");
      final stepBStart = source.indexOf("// Step B");
      expect(stepAStart, greaterThan(0));
      expect(stepBStart, greaterThan(stepAStart));

      final planIdx = source.indexOf("'workout_plan'", stepAStart);
      final schedIdx = source.indexOf("'scheduled_workouts'", stepBStart);
      expect(planIdx, greaterThan(0));
      expect(schedIdx, greaterThan(0));

      // workout_plan token must be inside step A (between A start and B start).
      expect(planIdx, lessThan(stepBStart),
          reason: '_restoreWorkoutPlan must run in step A so it cannot '
              'race with _restoreScheduledWorkouts and clobber completed status');
      // scheduled_workouts must be after step B start.
      expect(schedIdx, greaterThan(stepBStart));
    });

    test('restoreFromCloud: workout_plan called serially BEFORE the parallel batch', () {
      // The legacy entry point should run _restoreWorkoutPlan as a
      // pre-step (await _safeRestoreOp) before the Future.wait.
      final method = _extractMethod(source, 'restoreFromCloud');
      expect(method, contains("await _safeRestoreOp('workout_plan'"));
      // And inside the parallel Future.wait that follows, workout_plan
      // must NOT appear (otherwise it can still race).
      final parallelStart = method.indexOf('await Future.wait');
      expect(parallelStart, greaterThan(0));
      final parallelChunk = method.substring(parallelStart);
      expect(parallelChunk.contains("'workout_plan'"), isFalse,
          reason: 'workout_plan must not appear inside Future.wait — would re-introduce race');
    });

    test('_restoreWorkoutPlan defends against clobbering local completed status', () {
      final method = _extractMethod(source, '_restoreWorkoutPlan');
      // The completed-day-preserving merge was extracted to the shared
      // PlanIntegrityReconciler.mergeScheduleEntry (diagnose a7d3f1) so the
      // restore path + the boot heal can't drift. Behavioral preservation
      // (a local 'completed' day survives the planned plan_json snapshot) is
      // pinned in test/contracts/restore_plan_json_authoritative_test.dart.
      expect(method, contains('PlanIntegrityReconciler.mergeScheduleEntry'),
          reason: 'restore must route schedule merges through the shared '
              'completed-day-preserving helper');
    });
  });

  group('templates deleted-row removal (OI-252 — replaces the old stale-key sweep)', () {
    // OI-252 (2026-09-27): the old canonicalKeys/deleteAll SWEEP (delete
    // every local tmpl_* not in the cloud's live set) is GONE entirely —
    // deliberately, per round-review: a blanket sweep would delete every
    // not-yet-pushed local template on a device's first restore. It is
    // replaced by POSITIVE-EVIDENCE-ONLY removal, keyed on each row's own
    // `deleted_at` tombstone (migration 145's rename-on-delete trigger),
    // never on absence from a snapshot. These 3 tests previously pinned the
    // sweep mechanism; repointed (not deleted — CLAUDE.md's
    // extraction-breaks-source-grep-contracts pitfall) to the mechanism
    // that replaced it. Behavioral coverage for the removal itself lives in
    // test/sync/oi252_deleted_template_restore_behavioral_test.dart.
    test('_restoreWorkoutTemplates removes a local copy on positive '
        'deleted_at evidence, never on mere absence', () {
      final method = _extractMethod(source, '_restoreWorkoutTemplates');
      expect(method, contains("map['deleted_at'] != null"),
          reason: 'removal must be keyed on the row\'s OWN tombstone field, '
              'not on it being missing from any collected set');
      expect(method, contains('_hive.workoutBox.delete(hiveKey)'),
          reason: 'a locally-cached copy of a tombstoned template must be '
              'removed');
    });

    test('an offline local delete is never undone by a racing restore', () {
      final method = _extractMethod(source, '_restoreWorkoutTemplates');
      expect(method, contains('pendingDeleteIds'),
          reason: 'a row this device itself queued for deletion via '
              'PendingTemplateDeletes must be skipped even while the cloud '
              'still (briefly) reports it live — the new mechanism\'s '
              'analogue of the old sweep\'s query-failure defensiveness: '
              'never act on stale/partial state as though it were '
              'authoritative');
    });

    test('removal cleans schedule references + emits telemetry for '
        'observability', () {
      final method = _extractMethod(source, '_restoreWorkoutTemplates');
      expect(method, contains('_cleanScheduleReferencesToTemplate'),
          reason: 'a removed template must not leave dangling schedule_* '
              'references behind');
      expect(method, contains('deleted_template_removed_during_restore'),
          reason: 'op_type lets us correlate "template resurrected" '
              'reports to removal frequency in client_errors — the '
              'observability parity the old sweep\'s '
              '"templates_stale_keys_swept" event provided');
    });
  });
}

/// Crude method extractor — finds the IMPLEMENTATION of
/// `Future<X> <name>(` (signature, not callsite) and returns the
/// substring up to the matching `}` at the same indent. Skips
/// callsite occurrences (e.g. `_safeRestoreOp('x', _restoreX(...))`)
/// by requiring the match be preceded by a return-type token.
String _extractMethod(String source, String name) {
  // Match `Future<...> name(` or `Future name(` — implementation only.
  final pattern = RegExp(
    r'Future\s*(?:<[^>]+>)?\s+' + RegExp.escape(name) + r'\s*\(',
  );
  final match = pattern.firstMatch(source);
  if (match == null) return '';
  // Skip the parameter list (match.end is just past the signature's opening
  // `(`) so a named/optional param group `{...}` is not mistaken for the body
  // brace — the C3 single-call refactor added `{Object? preFetched}` params.
  int pi = match.end;
  int pdepth = 1;
  while (pi < source.length && pdepth > 0) {
    if (source[pi] == '(') pdepth++;
    if (source[pi] == ')') pdepth--;
    pi++;
  }
  // Find the opening `{` of the BODY after the parameter list.
  final openBrace = source.indexOf('{', pi);
  if (openBrace < 0) return '';
  // Walk to the matching close brace.
  int depth = 0;
  for (int i = openBrace; i < source.length; i++) {
    if (source[i] == '{') {
      depth++;
    } else if (source[i] == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(match.start, i + 1);
      }
    }
  }
  return source.substring(match.start);
}
