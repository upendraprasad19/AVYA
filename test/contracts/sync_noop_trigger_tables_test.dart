// Regression test for the day-swapper-sync-load batch, Task 7
// (closes-diagnose: a9d3f6). Pins migration 149's generic
// no-op-suppression trigger table set against two independent sources:
// (a) the plan's own Section 13 row 6 enumeration (hardcoded below -- this
// assertion needs nothing else and is the PRIMARY regression guard), and
// (b) `enumerateSyncWriteTables` from scripts/sync_hash_skip_atomicity_lib.dart
// (plan Task 3, gate G1) run over the REAL sync layer: every table it finds
// must be classified below as generic-trigger, custom-guard or untriggered.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/sync_hash_skip_atomicity_lib.dart';

/// The 19 tables plan Section 13 row 6 names for the generic
/// suppress_redundant_updates_trigger() trigger. `scheduled_workouts` is
/// deliberately excluded (it gets ONLY the custom completed-day guard,
/// migration 149 Section 2) and `user_profile` is deliberately excluded
/// (its sole writer chains `.upsert().select()` -- plan Section 13 row 7).
const _expectedGenericTriggerTables = <String>{
  'workout_logs',
  'workout_log_exercises',
  'workout_log_sets',
  'workout_schedule_completions',
  'streaks',
  'workout_templates',
  'template_exercises',
  'nutrition_logs',
  'nutrition_log_items',
  'water_logs',
  'user_saved_meals',
  'readiness_daily',
  'sleep_logs',
  'weight_logs',
  'body_measurements',
  'daily_steps',
  'user_custom_exercises',
  'user_custom_foods',
  'ai_coach_interactions',
};

const _migrationPath =
    'supabase/migrations/149_sync_noop_suppress_completed_guard_sync_epoch.sql';

/// Strips the commented rollback block, then strips `--` line comments, so a
/// table name mentioned only in header prose or the commented rollback
/// cannot satisfy a `contains`/regex assertion below (CLAUDE.md: strip
/// comments before any absent/present-pattern grep).
String _activeSql(String sql) {
  final active = sql.split('-- Rollback (commented')[0];
  return active
      .split('\n')
      .map((line) {
        final idx = line.indexOf('--');
        return idx == -1 ? line : line.substring(0, idx);
      })
      .join('\n');
}

/// Extracts every `CREATE TRIGGER trg_suppress_redundant_updates ... ON
/// public.<table>` target from the (already comment-stripped) migration text.
Set<String> _triggerTablesInMigration(String activeSql) {
  final pattern = RegExp(
    r'CREATE TRIGGER\s+trg_suppress_redundant_updates\s+'
    r'BEFORE UPDATE ON public\.(\w+)',
    multiLine: true,
  );
  return pattern.allMatches(activeSql).map((m) => m.group(1)!).toSet();
}

void main() {
  group('sync no-op trigger table set (migration 149, diagnose a9d3f6)', () {
    late String rawMigration;
    late String active;

    setUpAll(() {
      rawMigration = File(_migrationPath).readAsStringSync();
      active = _activeSql(rawMigration);
    });

    test(
      'migration 149 triggers exactly the 19 tables in plan Section 13 row 6, no more no fewer',
      () {
        final actual = _triggerTablesInMigration(active);
        expect(actual, equals(_expectedGenericTriggerTables));
      },
    );

    test('scheduled_workouts gets the custom guard, not the generic trigger', () {
      expect(
        active,
        contains(
          'CREATE TRIGGER trg_scheduled_workouts_completed_guard\n'
          '  BEFORE UPDATE ON public.scheduled_workouts',
        ),
      );
      // The guard function lives in `private` (anon-invisible, like 133/138);
      // a revert to `public.` must fail here, not only at the live check.
      expect(active,
          contains('CREATE OR REPLACE FUNCTION private.scheduled_workouts_completed_guard()'));
      expect(active,
          isNot(contains('FUNCTION public.scheduled_workouts_completed_guard')));
      expect(
        active,
        isNot(
          contains(
            'CREATE TRIGGER trg_suppress_redundant_updates\n'
            '  BEFORE UPDATE ON public.scheduled_workouts',
          ),
        ),
      );
    });

    test('sync_epoch column is added to user_progress with default 0', () {
      expect(
        active,
        contains(
          'ADD COLUMN IF NOT EXISTS sync_epoch integer NOT NULL DEFAULT 0',
        ),
      );
    });

    // Cross-check against Task 3's enumeration of what the REAL sync layer
    // writes. Task 3 is committed in wave 0, before this worktree branches.
    // enumerateSyncWriteTables takes repo-relative path -> RAW source (Task 3
    // Step 1). Every table the sync layer writes must be classified here as
    // generic-trigger, custom-guard or deliberately-untriggered, so a NEW
    // sync-written table fails this test until someone decides its trigger.
    test('every sync-written table is classified (Task 3 enumeration)', () {
      final written = enumerateSyncWriteTables(_realSyncSources());
      expect(
        written,
        equals(<String>{
          ..._expectedGenericTriggerTables,
          'scheduled_workouts',
          ..._deliberatelyUntriggered.keys,
        }),
      );
      // The three sets must not overlap: a table in two classes is a
      // classification error, not a harmless duplicate.
      expect(
        _expectedGenericTriggerTables.intersection(
            _deliberatelyUntriggered.keys.toSet()),
        isEmpty,
      );
      expect(_deliberatelyUntriggered.containsKey('scheduled_workouts'),
          isFalse);
    });
  });
}

/// Tables the sync layer writes that get NO trigger, each with its reason.
/// Spec §5.10 rule 1 scopes the generic trigger to tables a HISTORY LOOP
/// writes; these are single-row or one-shot writes.
const _deliberatelyUntriggered = <String, String>{
  // Chains .upsert().select().single(): a suppressed no-op returns 0 rows
  // and .single() would throw (sync_profile.dart:300-304,
  // sync_service.dart:913-917).
  'user_profile': 'chained .select().single()',
  // Same chain (sync_coach.dart:94-97).
  'coach_memory': 'chained .select().single()',
  // One row per user, written on settings changes, not in a loop.
  'user_preferences': 'single row, not a history loop',
  // One row per user; plan_json bundle push is already fingerprint-skipped
  // (Task 20) and sync_epoch is added to it by this migration.
  'user_progress': 'single row, fingerprint-skipped push',
  // One upsert per inbox entry at creation time; never re-pushed in a loop.
  'notifications_inbox': 'one-shot per entry',
  // One upsert per saved plan at save time; never re-pushed in a loop.
  'saved_diet_plans': 'one-shot per plan',
};

/// Repo-relative path -> raw source for the whole sync layer, the same input
/// set Task 3's own "the real sync layer" group uses.
Map<String, String> _realSyncSources() {
  final out = <String, String>{
    'lib/core/services/sync_service.dart':
        File('lib/core/services/sync_service.dart').readAsStringSync(),
  };
  for (final f in Directory('lib/core/services/sync')
      .listSync(recursive: true)
      .whereType<File>()) {
    final rel = f.path.replaceAll(r'\', '/');
    if (rel.endsWith('.dart')) out[rel] = f.readAsStringSync();
  }
  return out;
}
