// APK Test #12.8 / Bug #1 — restore methods MUST derive deterministic
// local Hive keys from row data, NOT from the cloud UUID. Pre-fix
// founder ended up with 30+ exlog rows for one workout day on May 4
// because every cold restore wrote a sibling row keyed by the cloud
// UUID's hash instead of collapsing onto the locally-written
// `exlog_<istDate>_<lower(name).hashCode>` key produced by
// WorkoutWriteService.exlogKey.
//
// These are source-grep tests in the established sync_gap_test.dart
// pattern — they assert the production code follows the deterministic
// shape rather than spinning up Hive boxes + Supabase mocks.

import 'package:flutter_test/flutter_test.dart';

import '../contracts/_sync_service_source.dart';

/// Returns the body of `Future<void> _restore<Name>(...)` from
/// [src] up to the next top-level `Future<void>` declaration.
String _restoreBody(String src, String name) {
  final start = src.indexOf('Future<void> _restore$name(');
  expect(start, greaterThan(0), reason: '_restore$name function must exist');
  final next = src.indexOf('\n  Future<void> ', start + 1);
  expect(next, greaterThan(start));
  return src.substring(start, next);
}

void main() {
  late String src;

  setUpAll(() {
    src = loadSyncServiceSource().readAsStringSync();
  });

  group('Bug #1 — restore writes deterministic Hive keys', () {
    test('_restoreWorkoutLogs keys by IST date, not raw ms timestamp', () {
      final body = _restoreBody(src, 'WorkoutLogs');
      // Must construct key from a date string (YYYY-MM-DD shape), not
      // ms-since-epoch. Pre-fix: `final logId = 'wlog_$ts';` with
      // `ts = DateTime.parse(...).millisecondsSinceEpoch`.
      expect(
        body.contains("'wlog_\$ts'"),
        isFalse,
        reason: 'Pre-fix `wlog_\$ts` (ms) must not appear; must use IST date',
      );
      // Either `wlog_$dateStr` or equivalent shape.
      expect(
        RegExp(r"wlog_\$").hasMatch(body),
        isTrue,
        reason: 'must build wlog_<dateStr> deterministically',
      );
    });

    test('_restoreExerciseLogs keys by IST date + lower(name).hashCode', () {
      final body = _restoreBody(src, 'ExerciseLogs');
      // Pre-fix: `exlog_${ts}_${name.hashCode}` (raw ms, raw name).
      expect(
        body.contains(r"'exlog_${ts}_${name.hashCode}'"),
        isFalse,
        reason:
            'Pre-fix `exlog_<ms>_<name.hashCode>` (no IST, no normalize) '
            'must not appear',
      );
      // Must lowercase + trim before hashCode (mirror of
      // WorkoutWriteService.exlogKey).
      expect(
        body.contains('toLowerCase()') && body.contains('.trim()'),
        isTrue,
        reason: 'name must be lower+trim before hashCode (matches '
            'WorkoutWriteService.exlogKey)',
      );
    });

    test('_restoreNutritionLogs derives Hive key, not cloud UUID', () {
      final body = _restoreBody(src, 'NutritionLogs');
      // Pre-fix: `_hive.nutritionBox.put(id, map)` where `id` was the
      // cloud UUID. Must instead build `nlog_<...>` from row data.
      expect(
        body.contains('_nlogKeyForRestore'),
        isTrue,
        reason: 'must call deterministic key helper '
            '_nlogKeyForRestore(date, mealType, items)',
      );
      // Must put under the deterministic key (not the cloud id).
      expect(
        RegExp(r"nutritionBox\.put\(localKey").hasMatch(body),
        isTrue,
        reason: 'put() must target the locally-derived key',
      );
    });

    test('_restoreSavedMeals derives Hive key from name, not cloud UUID', () {
      final body = _restoreBody(src, 'SavedMeals');
      // Pre-fix had no `name.hashCode` path AND used `startsWith('saved_meal_')`
      // ternary (which always hit else for cloud UUIDs). The fix must
      // hash on name (lowercased + trimmed). A name-empty fallback is
      // allowed but must not be the primary path.
      expect(
        body.contains('name.hashCode') ||
            body.contains('name.toLowerCase()'),
        isTrue,
        reason: 'must derive Hive key from name field, not cloud UUID',
      );
      // The startsWith ternary used by the pre-fix is gone.
      expect(
        body.contains("startsWith('saved_meal_') ? id : 'saved_meal_"),
        isFalse,
        reason: 'pre-fix startsWith ternary must not appear',
      );
    });

    test('_restoreCoachInteractions derives key from created_at, not UUID',
        () {
      final body = _restoreBody(src, 'CoachInteractions');
      // Must use millisecondsSinceEpoch from created_at to mirror
      // ai_coach_repository's `coach_<ts>` local-write convention.
      expect(
        body.contains('millisecondsSinceEpoch'),
        isTrue,
        reason:
            'must build hive key from created_at.millisecondsSinceEpoch',
      );
      expect(
        body.contains("startsWith('coach_') ? id : 'coach_"),
        isFalse,
        reason: 'pre-fix startsWith ternary must not appear',
      );
    });

    test('_restoreWorkoutTemplates derives key from name, not cloud UUID',
        () {
      final body = _restoreBody(src, 'WorkoutTemplates');
      // Must derive from name (cloud always returns a UUID id, never
      // a `tmpl_*` prefix, so the old startsWith-check ALWAYS hit the
      // else branch and produced the dup).
      expect(
        body.contains('tmplName.hashCode') ||
            (body.contains("map['name']") &&
                body.contains('toLowerCase')),
        isTrue,
        reason: 'must derive Hive key from name field',
      );
      expect(
        body.contains("startsWith('tmpl_') ? id : 'tmpl_"),
        isFalse,
        reason: 'pre-fix startsWith ternary must not appear',
      );
    });
  });

  group('Bug #2 — _restoreUserProfile pulls users.full_name', () {
    test('queries public.users for full_name + email', () {
      final body = _restoreBody(src, 'UserProfile');
      // Must do a SELECT on users(id, full_name, email).
      expect(
        body.contains(".from('users')"),
        isTrue,
        reason: 'must SELECT from users table for canonical full_name',
      );
      expect(
        body.contains('full_name'),
        isTrue,
        reason: 'must request the full_name column',
      );
    });

    test('merges users-table columns into profile map', () {
      final body = _restoreBody(src, 'UserProfile');
      // After the SELECT, usersRow's non-null entries must overlay
      // the merged map (so canonical full_name beats stale local).
      expect(
        body.contains('usersRow.entries'),
        isTrue,
        reason: 'usersRow entries must layer into the merged profile map',
      );
    });
  });

  group('Bug #3 — _restoreScheduledWorkouts merges status/completed_at', () {
    test('does NOT skip when local schedule entry exists', () {
      final body = _restoreBody(src, 'ScheduledWorkouts');
      // Pre-fix: `if (_hive.workoutBox.get(key) != null) continue;`
      // discarded cloud-side completed status when a planned local
      // entry was already populated by _restoreWorkoutPlan.
      expect(
        body.contains(
            'if (_hive.workoutBox.get(key) != null) continue;'),
        isFalse,
        reason: 'must not early-skip; must merge cloud status onto local',
      );
    });

    test('writes status + completed_at fields on every restore', () {
      final body = _restoreBody(src, 'ScheduledWorkouts');
      expect(
        body.contains("'status':"),
        isTrue,
        reason: 'cloud status must be projected into Hive map',
      );
      expect(
        body.contains("'completed_at':"),
        isTrue,
        reason: 'cloud completed_at must be projected into Hive map',
      );
    });
  });

  group('Bug #4 — _syncWorkoutTemplates does NOT include id in upsert', () {
    test('parent upsert payload omits id', () {
      // Narrow to _syncWorkoutTemplates only (NOT _restore).
      final start = src.indexOf('Future<void> _syncWorkoutTemplates(');
      expect(start, greaterThan(0));
      final next = src.indexOf('\n  Future<void> ', start + 1);
      final body = src.substring(start, next);

      // Find the workout_templates upsert block. Pre-fix had `'id': cloudTmplId,`.
      final upsertStart =
          body.indexOf(".from('workout_templates').upsert({");
      expect(upsertStart, greaterThan(0),
          reason: 'workout_templates upsert must exist');
      final upsertEnd = body.indexOf('}', upsertStart);
      final upsertBlock = body.substring(upsertStart, upsertEnd);

      expect(
        upsertBlock.contains("'id':"),
        isFalse,
        reason:
            "Bug #4 — parent upsert must NOT pass 'id'; cloud column "
            'has gen_random_uuid() default and FK loop fires on UPDATE',
      );
    });

    test('child template_exercises upsert omits id', () {
      // APK Test #15 closeout / Backlog #2 — switched from
      // .from('template_exercises').insert({}) to .upsert({},
      // onConflict: 'template_id,order_index') after migration 051 added
      // the UNIQUE constraint. Pre-Test-#15 this test pinned `.insert(`;
      // updated to `.upsert(` so the contract continues to enforce the
      // Bug #4 invariant ("no 'id':" in payload) under the new write
      // shape. The id-omission rule is the load-bearing assertion;
      // insert vs upsert is the implementation detail.
      final start = src.indexOf('Future<void> _syncWorkoutTemplates(');
      final next = src.indexOf('\n  Future<void> ', start + 1);
      final body = src.substring(start, next);

      final childStart = body.indexOf(
          ".from('template_exercises').upsert({");
      expect(childStart, greaterThan(0),
          reason:
              'template_exercises must upsert (post-migration-051) '
              "without 'id'. closes-diagnose: "
              '2026-05-10-template-exercises-upsert-a8b2c7');
      final childEnd = body.indexOf('}', childStart);
      final childBlock = body.substring(childStart, childEnd);

      expect(
        childBlock.contains("'id':"),
        isFalse,
        reason:
            "Bug #4 — child upsert must NOT pass 'id'; column default "
            'gen_random_uuid() handles it. The onConflict target is '
            "(template_id, order_index), so 'id' is preserved on UPDATE "
            'and generated on INSERT.',
      );
    });

    test('SELECTs real cloud parent id by (user_id, name) before children',
        () {
      final start = src.indexOf('Future<void> _syncWorkoutTemplates(');
      final next = src.indexOf('\n  Future<void> ', start + 1);
      final body = src.substring(start, next);

      // Lookup must use SELECT id WHERE user_id=? AND name=?.
      expect(
        body.contains(
            ".from('workout_templates')") &&
            body.contains(".select('id')") &&
            body.contains(".eq('name', tmplName)"),
        isTrue,
        reason:
            'Bug #4 — must look up cloud parent id via (user_id, name) '
            'before child insert so FK targets the migration-050 keeper '
            'row, not a freshly-derived deterministic UUID',
      );
    });
  });
}
