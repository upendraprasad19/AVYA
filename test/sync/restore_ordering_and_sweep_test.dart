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

  group('templates stale-key sweep', () {
    test('_restoreWorkoutTemplates collects canonicalKeys + sweeps stragglers', () {
      final method = _extractMethod(source, '_restoreWorkoutTemplates');
      expect(method, contains('canonicalKeys'),
          reason: 'must track canonical keys during write');
      expect(method, contains("startsWith('tmpl_')"),
          reason: 'sweep must scan tmpl_* keys');
      expect(method, contains('deleteAll'),
          reason: 'sweep must call deleteAll for stale keys');
      expect(method, contains('canonicalKeys.contains'),
          reason: 'sweep must filter by canonicalKeys.contains');
    });

    test('sweep is gated on canonicalKeys.isNotEmpty (defensive against query failure)', () {
      final method = _extractMethod(source, '_restoreWorkoutTemplates');
      expect(method, contains('canonicalKeys.isNotEmpty'),
          reason: 'must skip sweep when cloud returned zero rows');
    });

    test('sweep emits telemetry event for observability', () {
      final method = _extractMethod(source, '_restoreWorkoutTemplates');
      expect(method, contains('templates_stale_keys_swept'),
          reason: 'op_type lets us correlate "templates dup" reports to '
              'sweep frequency in client_errors');
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
  // Find the opening `{` after the signature.
  final openBrace = source.indexOf('{', match.start);
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
