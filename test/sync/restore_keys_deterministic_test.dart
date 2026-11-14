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
  // After refactor/sync-service-part-split (2026-05-13) the union source
  // can end on a method (no trailing `Future<void>` if the last extracted
  // method is the file's last). Fall back to end-of-source.
  final next = src.indexOf('\n  Future<void> ', start + 1);
  final end = next > start ? next : src.length;
  return src.substring(start, end);
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

    test('_restoreExerciseLogs routes through WorkoutWriteService.exlogKey', () {
      final body = _restoreBody(src, 'ExerciseLogs');
      // Pre-fix: `exlog_${ts}_${name.hashCode}` (raw ms, raw name).
      expect(
        body.contains(r"'exlog_${ts}_${name.hashCode}'"),
        isFalse,
        reason:
            'Pre-fix `exlog_<ms>_<name.hashCode>` (no IST, no normalize) '
            'must not appear',
      );
      // Post-Test-#16.1 / Bug A: restore body uses the CANONICAL
      // `WorkoutWriteService.exlogKey(date, name)` helper, which
      // internally does lower+trim+IST. Pin the routing, not the
      // implementation details (which now live in the canonical method).
      expect(
        body.contains('WorkoutWriteService.exlogKey('),
        isTrue,
        reason: '_restoreExerciseLogs must derive the Hive key via '
            'WorkoutWriteService.exlogKey() (Test #16.1 / Bug A centralized '
            'the formula). The canonical method does lower+trim+IST '
            'internally — do NOT inline the normalization in the restore '
            'body or you re-open the rogue-key class.',
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

    test('_restoreSavedMeals derives Hive key via canonical savedMealKey, not cloud UUID',
        () {
      final body = _restoreBody(src, 'SavedMeals');
      // Post-b8d5c2 (2026-06-03): the restore routes through the CANONICAL
      // NutritionWriteService.savedMealKey(name) helper (UUID v5 over the
      // lowercased+trimmed name) — the SAME key the writer produces — instead of
      // an inline name.hashCode. Pin the ROUTING, not the implementation details
      // (mirrors _restoreExerciseLogs → WorkoutWriteService.exlogKey). A
      // name-empty fallback (id-hash) is allowed but must not be the primary path.
      expect(
        body.contains('NutritionWriteService.savedMealKey('),
        isTrue,
        reason: 'must derive the Hive key via the canonical savedMealKey() helper '
            '(b8d5c2 centralized the formula; inlining name.hashCode re-opens the '
            'writer/restore key drift)',
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

    test('_restoreWorkoutTemplates derives key from the cloud UUID via '
        'templateKeyFor, NOT from name (OI-252 f4a8c2 supersedes Bug #1)',
        () {
      // OI-252 (2026-09-27, diagnose f4a8c2) — deriving the local key from
      // NAME (this test's ORIGINAL assertion) turned out to be the root
      // cause of a WORSE bug: a deleted template and a fresh one created
      // under the same name deterministically collided on the identical
      // Hive key, so a delete-then-recreate could resurrect the deleted
      // one. The fix derives the key from the template's own permanent,
      // stable cloud identity (a client-minted UUID, immutable across
      // rename/delete/recreate) instead of from mutable content.
      final body = _restoreBody(src, 'WorkoutTemplates');
      expect(
        body.contains('templateKeyFor(id)'),
        isTrue,
        reason: 'must derive the Hive key from the cloud id via '
            'templateKeyFor, not from the template name',
      );
      expect(
        body.contains('tmplName.hashCode'),
        isFalse,
        reason: 'the superseded name-hash key formula must not reappear — '
            'it is the exact mechanism that let a delete and its '
            'same-named replacement collide on one key',
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

  group('Bug #4 → OI-252 f4a8c2 supersedes: _syncWorkoutTemplates upserts '
      'the client-minted id DIRECTLY', () {
    test('parent upsert payload DOES pass id — client-minted, stable, '
        'targets onConflict: id', () {
      // OI-252 (2026-09-27) inverted this invariant on purpose. Bug #4's
      // original fix (omit 'id', let the server generate one via
      // gen_random_uuid(), then SELECT it back by name) was itself the
      // mechanism that made template identity name-derived — the root
      // cause of the WORSE delete-then-recreate resurrection bug. The
      // template's permanent identity is now minted CLIENT-SIDE at create
      // time (WorkoutWriteService.newTemplateKey()) and is stable across
      // rename/delete/recreate, so the upsert targets it directly.
      //
      // Merge of day-swapper-sync-load (2026-09-28): the header map lives in
      // a local `headerPayload()` closure (Task 16, so the same map also
      // feeds the domain's SyncSkipIndex fingerprint), and the call site is
      // `.upsert(headerPayload(), onConflict: 'id')`. The id assertion reads
      // the closure body; the conflict-target assertion reads the call site.
      final start = src.indexOf('Future<void> _syncWorkoutTemplates(');
      expect(start, greaterThan(0));
      final next = src.indexOf('\n  Future<void> ', start + 1);
      final body = src.substring(start, next);

      final headerStart =
          body.indexOf('Map<String, dynamic> headerPayload() =>');
      expect(headerStart, greaterThan(0),
          reason: 'headerPayload() closure must exist — it is what is '
              'actually sent to workout_templates AND fingerprinted');
      final headerEnd = body.indexOf('};', headerStart);
      expect(headerEnd, greaterThan(headerStart));
      final headerBlock = body.substring(headerStart, headerEnd);

      expect(
        headerBlock.contains("'id': cloudTmplId,"),
        isTrue,
        reason: "OI-252 — parent upsert must pass 'id': cloudTmplId "
            '(the id resolved from the client-minted Hive key via '
            'cloudIdFromKey), not omit it',
      );
      expect(
        body.contains(".from('workout_templates').upsert(headerPayload(), "
            "onConflict: 'id')"),
        isTrue,
        reason: "the upsert must feed FROM headerPayload() and target "
            "onConflict: 'id', not 'user_id,name' — the old name-based "
            'conflict target is what let a delete and its same-named '
            'replacement collide',
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

    test('id is already known from the key — no SELECT-by-name lookup '
        'before children (OI-252 supersedes Bug #4)', () {
      // OI-252 (2026-09-27) removes this lookup entirely: the id is the
      // client-minted uuid baked into the Hive key (cloudIdFromKey(key)),
      // known BEFORE the upsert runs, so there is nothing left to resolve
      // by name afterward. A surviving name-based lookup here would be a
      // regression toward the old ambiguous-identity design.
      final start = src.indexOf('Future<void> _syncWorkoutTemplates(');
      final next = src.indexOf('\n  Future<void> ', start + 1);
      final body = src.substring(start, next);

      expect(
        body.contains(".eq('name', tmplName)"),
        isFalse,
        reason: 'must not look up the cloud parent id by (user_id, name) '
            "any more — that lookup is what made a template's identity "
            'ambiguous between a deleted row and its same-named '
            'replacement',
      );
      expect(
        body.contains('cloudIdFromKey(key)'),
        isTrue,
        reason: 'the id must come from the Hive key itself via '
            'cloudIdFromKey, resolved before the upsert runs',
      );
    });
  });
}
