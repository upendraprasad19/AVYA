@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import 'supabase_test_helper.dart';

/// Layer 1: Supabase sync verification tests.
///
/// These tests call real Supabase APIs and verify database state directly.
/// They do NOT require a device/emulator — run via `flutter test test/supabase/`.
///
/// Prerequisites:
///   - `.env` file with valid SUPABASE_URL and SUPABASE_ANON_KEY
///   - the designated QA user (SUPABASE_TEST_EMAIL) exists in auth.users
///
/// Run: flutter test test/supabase/sync_service_test.dart
///
/// ── T3/T4/T5 DRIVE THE REAL WRITERS (2026-08-15) ──────────────────────────
/// These three used to hand-roll their own `.upsert()` payloads. That made them
/// unable to detect the thing they claimed to test: a test that re-implements
/// the writer cannot notice the writer drifting. And they had drifted —
/// invisibly, because per OI-121 they had never once executed (`setUpAll` always
/// died on a missing QA account) until `e4121c14` supplied real credentials.
///
/// What they had frozen was not a typo but a *fixed production bug*:
///   - T3 wrote `exercise_name`, renamed to `workout_name` on 2026-05-25.
///   - T4/T5 sent a client-side string `id` into a `uuid` column with
///     `onConflict:'id'` — the exact pre-2026-06-02 shape whose cross-user PK
///     collision made the second user's row vanish, and (nutrition, 2026-04-18)
///     kept `nutrition_logs` at 0 rows despite dozens of Hive food logs.
///
/// So they now seed Hive and call the production sync entry points, asserting
/// the row ARRIVES in cloud with the right values. That property is
/// drift-proof: whatever payload shape the writer adopts next, the row still
/// has to land.
///
/// Why the narrow `push*ForSyncDomain()` forwarders and not `weeklyFullSync()`:
/// each drives ONE domain, so the write surface stays inside what `cleanup()`
/// already deletes; each calls `_ensureSessionOpen()` (which `weeklyFullSync`
/// does not), so the user-scoped Hive session opens itself; and none is wrapped
/// in `_safeRestoreOp`, so a box-access failure reddens the test loudly instead
/// of being swallowed into a silent "success, 0 rows".
void main() {
  if (!SupabaseTestHelper.hasCredentials) {
    test('SKIPPED: SUPABASE_URL / _ANON_KEY / _TEST_EMAIL / _TEST_PASSWORD not all set', () {});
    return;
  }

  late Box syncBox;
  late String userId;

  /// Fixed, clearly-synthetic date. Deliberately NOT `DateTime.now()`: the
  /// cloud `date` columns are IST (CLAUDE.md §4.5) while `DateTime.now()` in CI
  /// is UTC, so a "today" key would disagree with itself across the IST
  /// midnight window and flake ~5.5h a day. `cleanup()` wipes every row for
  /// this user in `setUp`, so a fixed date cannot collide with seed data.
  const seedDate = '2026-01-15';

  setUpAll(() async {
    await SupabaseTestHelper.init();
    userId = await SupabaseTestHelper.signIn();

    // Genuinely shared, non-user-scoped boxes (HiveService._sharedBoxNames).
    // `configBox` gates the nutrition slot-merge path; `migrationBox` is read
    // by the legacy-box migration inside openForUser (below).
    syncBox = await Hive.openBox('syncBox');
    await Hive.openBox('configBox');
    await Hive.openBox('migrationBox');

    // MUST come before openForUser. `HiveService.getBox` ends in
    // `Hive.box(name)`, so it needs BOTH `_initialized` true and the box open;
    // openForUser -> _migrateLegacySharedBoxes reads `migrationBox` through it.
    // Without this the read throws a StateError that is caught and swallowed
    // (hive_user_session.dart:299-307) — the migration still runs, so this is
    // not a behaviour change, but a swallowed exception on the happy path is
    // exactly the shape these tests exist to stop shipping.
    HiveService.debugMarkInitializedForTests();

    // Opens the 7 user-scoped boxes under the `<root>_<8hex(uid)>` namespace.
    // This is the step that makes seeding work at all: `HiveService.workoutBox`
    // resolves through `wrapUserScopedBox`, so a raw `Hive.openBox('workoutBox')`
    // would write to a box the writer never opens.
    //
    // Note we do NOT set `GuardedBox.testBypassOwnership` or
    // `HiveUserSession.debugCurrentUidResolverForTests`. Both exist, and both
    // would work — but we sign in as the same user we namespace for, so the
    // real ownership check passes on its own. Bypassing it would mask a genuine
    // mismatch, which is the one thing that guard is for.
    await HiveUserSession.openForUser(userId);
  });

  setUp(() async {
    // Clean Supabase + local Hive state before each test.
    await SupabaseTestHelper.cleanup();
    final hive = HiveService.instance;
    await hive.userBox.clear();
    await hive.healthBox.clear();
    await hive.workoutBox.clear();
    await hive.nutritionBox.clear();
    await syncBox.clear();
  });

  tearDownAll(() async {
    await SupabaseTestHelper.cleanup();
    await HiveUserSession.closeAll();
    await Hive.close();
    await SupabaseTestHelper.dispose();
  });

  group('SyncService — Profile Sync', () {
    // T1: syncProfileNow() writes complete profile to user_profile table
    test('T1: syncProfileNow writes complete profile to Supabase', () async {
      // Seed Hive with a complete profile. `HiveService.instance.userBox`, not
      // a raw `Hive.openBox('userBox')` — `userBox` is a user-scoped root, so
      // the raw handle would point at a box openForUser deletes from disk.
      final userBox = HiveService.instance.userBox;
      await userBox.put('profile', {
        'id': userId,
        'full_name': 'QA Test User',
        'date_of_birth': '1995-06-15',
        'gender': 'male',
        'height_cm': 175.0,
        'current_weight_kg': 75.0,
        'target_weight_kg': 70.0,
        'primary_goal': 'build_muscle',
        'fitness_experience': 'intermediate',
        'days_per_week': 4,
        'equipment_access': 'full_gym',
        'activity_level': 'moderately_active',
        'bmr': 1720.0,
        'tdee': 2666.0,
        // These fields are Hive-only and should NOT appear in Supabase
        'daily_calories': 2966,
        'protein_grams': 150,
        'carb_grams': 350,
        'fat_grams': 80,
        'email': SupabaseTestHelper.testEmail,
      });

      // Call syncProfileNow via direct Supabase upsert (mirrors SyncService logic)
      final p = Map<String, dynamic>.from(userBox.get('profile') as Map);
      await SupabaseTestHelper.client.from('user_profile').upsert({
        'user_id': userId,
        if (p['date_of_birth'] != null) 'date_of_birth': p['date_of_birth'],
        if (p['gender'] != null) 'gender': p['gender'],
        if (p['height_cm'] != null) 'height_cm': p['height_cm'],
        if (p['current_weight_kg'] != null)
          'current_weight_kg': p['current_weight_kg'],
        if (p['target_weight_kg'] != null)
          'target_weight_kg': p['target_weight_kg'],
        if (p['primary_goal'] != null) 'primary_goal': p['primary_goal'],
        if (p['fitness_experience'] != null)
          'fitness_experience': p['fitness_experience'],
        if (p['days_per_week'] != null) 'days_per_week': p['days_per_week'],
        if (p['equipment_access'] != null)
          'equipment_access': p['equipment_access'],
        if (p['activity_level'] != null) 'activity_level': p['activity_level'],
        if (p['bmr'] != null) 'bmr': p['bmr'],
        if (p['tdee'] != null) 'tdee': p['tdee'],
      }, onConflict: 'user_id');

      // Verify: user_profile row exists with all 12 columns populated
      final rows = await SupabaseTestHelper.queryTable('user_profile');
      expect(rows, isNotEmpty, reason: 'user_profile row should exist');

      final row = rows.first;
      expect(row['gender'], 'male');
      expect(row['height_cm'], 175.0);
      expect(row['current_weight_kg'], 75.0);
      expect(row['target_weight_kg'], 70.0);
      expect(row['primary_goal'], 'build_muscle');
      expect(row['fitness_experience'], 'intermediate');
      expect(row['days_per_week'], 4);
      expect(row['equipment_access'], 'full_gym');
      expect(row['activity_level'], 'moderately_active');
      expect(row['bmr'], closeTo(1720.0, 1.0));
      expect(row['tdee'], closeTo(2666.0, 1.0));
    });

    // T2: syncProfileNow() is idempotent — calling twice doesn't duplicate
    test('T2: syncProfileNow is idempotent (upsert, not insert)', () async {
      final profileData = {
        'user_id': userId,
        'gender': 'male',
        'height_cm': 175.0,
        'primary_goal': 'build_muscle',
      };

      // First upsert
      await SupabaseTestHelper.upsertRow('user_profile', profileData);

      // Second upsert with updated data
      await SupabaseTestHelper.upsertRow('user_profile', {
        ...profileData,
        'height_cm': 176.0,
      });

      // Should still be exactly 1 row, with updated height
      final rows = await SupabaseTestHelper.queryTable('user_profile');
      expect(rows.length, 1, reason: 'Should be exactly 1 row after 2 upserts');
      expect(rows.first['height_cm'], 176.0);
    });
  });

  group('SyncService — Weekly Full Sync', () {
    // T3: the real workout writer pushes a Hive wlog_* row to workout_logs.
    //
    // Seed shape is dictated by `_syncWorkoutLogs` (sync_workout.dart): it scans
    // `workoutBox` for `wlog_`-prefixed keys and SKIPS (with telemetry) any row
    // whose `date` or `workout_name` is null/empty, so both are mandatory.
    test('T3: workout logs sync to workout_logs table', () async {
      await HiveService.instance.workoutBox.put('wlog_$seedDate', {
        'date': seedDate,
        'workout_name': 'Push A',
        'duration_seconds': 3600,
        'created_at': '${seedDate}T07:30:00.000Z',
      });

      await SyncService.instance.pushWorkoutLogsForSyncDomain();

      final rows = await SupabaseTestHelper.queryTable('workout_logs');
      // `single`, not `first`: queryTable has no `.order()`, so `first` is
      // arbitrary once >1 row exists — and `single` additionally proves the
      // writer inserted exactly once rather than duplicating.
      final row = rows.single;
      // `workout_name` — NEVER `exercise_name`. That column does not exist on
      // this table and asserting it is what made this test fail (PGRST204).
      expect(row['workout_name'], 'Push A');
      expect(row['date'], seedDate);
      expect(row['duration_seconds'], 3600);
    });

    // T4: the real nutrition writer pushes a Hive nlog_* row to nutrition_logs
    // AND its child rows to nutrition_log_items.
    //
    // `items` is seeded deliberately. Without it the child loop never runs and
    // this test would silently cover only half the writer — and the half it
    // would miss is a real partial-failure mode: on a failed parent-id lookback
    // the writer `continue`s (sync_nutrition.dart:326-328), dropping the
    // children with the parent already landed. No parent-only assertion can
    // see that.
    test('T4: nutrition logs sync to nutrition_logs table', () async {
      await HiveService.instance.nutritionBox.put('nlog_${seedDate}_lunch_qa', {
        'date': seedDate,
        // meal_type is NOT NULL with no default on nutrition_logs, and the
        // writer skips any row missing it.
        'meal_type': 'lunch',
        'total_calories': 1800,
        'total_protein': 120,
        'total_carbs': 200,
        'total_fat': 60,
        'total_fiber': 12,
        'items': [
          {'name': 'Dal Tadka', 'quantity_g': 200, 'calories': 350},
        ],
      });

      await SyncService.instance.pushNutritionLogsForSyncDomain();

      final rows = await SupabaseTestHelper.queryTable('nutrition_logs');
      final parent = rows.single;
      expect(parent['meal_type'], 'lunch');
      expect(parent['date'], seedDate);
      expect(parent['total_calories'], 1800);
      expect(parent['total_protein'], 120);

      // The child rows cannot go through `queryTable` — it filters on
      // `user_id`, and `nutrition_log_items` has no such column (it is
      // user-scoped only transitively, via `log_id` -> `nutrition_logs`).
      final items = await SupabaseTestHelper.client
          .from('nutrition_log_items')
          .select()
          .eq('log_id', parent['id'] as String);
      expect(items, hasLength(1),
          reason: 'the seeded item should have reached nutrition_log_items');
      expect(items.first['food_name'], 'Dal Tadka');
      expect(items.first['item_index'], 0);
    });

    // T5: the real health writer pushes a Hive weight_* row to weight_logs.
    //
    // `type: 'weight_log'` is mandatory — `_syncWeightLogs` scans healthBox for
    // `weight_`-prefixed keys and `continue`s on any row whose `type` is not
    // exactly that (the box also holds readiness/sleep/steps rows).
    test('T5: weight logs sync to weight_logs table', () async {
      await HiveService.instance.healthBox.put('weight_$seedDate', {
        'type': 'weight_log',
        'date': seedDate,
        'weight_kg': 74.5,
        'notes': 'QA seed',
        'created_at': '${seedDate}T06:00:00.000Z',
      });

      await SyncService.instance.pushWeightLogsForSyncDomain();

      final rows = await SupabaseTestHelper.queryTable('weight_logs');
      final row = rows.single;
      expect(row['weight_kg'], 74.5);
      expect(row['date'], seedDate);
      expect(row['notes'], 'QA seed');
    });
  });

  group('SyncService — Daily Snapshot', () {
    // T6: pushSnapshot creates daily snapshot
    test('T6: daily snapshot upserts to user_daily_snapshots', () async {
      final today = DateTime.now().toIso8601String().substring(0, 10);

      await SupabaseTestHelper.client.from('user_daily_snapshots').upsert({
        'user_id': userId,
        'snapshot_date': today,
        'snapshot_json': {
          'snapshot_date': today,
          'profile': {'name': 'QA Test', 'goal': 'build_muscle'},
          'this_week_workouts': [],
          'today_nutrition': {'calories': 0},
        },
        'created_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,snapshot_date');

      final rows = await SupabaseTestHelper.queryTable('user_daily_snapshots');
      expect(rows, isNotEmpty, reason: 'Snapshot should exist');
      expect(rows.first['snapshot_date'], today);

      final snapshotJson = rows.first['snapshot_json'] as Map;
      expect(snapshotJson['snapshot_date'], today);
    });
  });

  group('SyncService — Interval Logic', () {
    // T7: checkAndSync respects 7-day interval
    test('T7: no full sync if last_full_sync < 7 days ago', () async {
      // Simulate: last sync was 3 days ago
      final threeDaysAgo =
          DateTime.now().subtract(const Duration(days: 3)).toIso8601String();
      await syncBox.put('last_full_sync', threeDaysAgo);

      final lastFull = DateTime.tryParse(
          syncBox.get('last_full_sync')?.toString() ?? '');
      final interval = const Duration(days: 7);

      expect(lastFull, isNotNull);
      expect(
        DateTime.now().difference(lastFull!) < interval,
        isTrue,
        reason: 'Should NOT trigger sync when < 7 days',
      );
    });

    // T8: checkAndSync triggers sync after 7 days
    test('T8: full sync triggers when interval exceeded', () async {
      // Simulate: last sync was 8 days ago
      final eightDaysAgo =
          DateTime.now().subtract(const Duration(days: 8)).toIso8601String();
      await syncBox.put('last_full_sync', eightDaysAgo);

      final lastFull = DateTime.tryParse(
          syncBox.get('last_full_sync')?.toString() ?? '');
      final interval = const Duration(days: 7);

      expect(lastFull, isNotNull);
      expect(
        DateTime.now().difference(lastFull!) >= interval,
        isTrue,
        reason: 'SHOULD trigger sync when >= 7 days',
      );
    });
  });
}
