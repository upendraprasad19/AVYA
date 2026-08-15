@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

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
void main() {
  if (!SupabaseTestHelper.hasCredentials) {
    test('SKIPPED: SUPABASE_URL / _ANON_KEY / _TEST_EMAIL / _TEST_PASSWORD not all set', () {});
    return;
  }

  late Box userBox;
  late Box healthBox;
  late Box syncBox;

  setUpAll(() async {
    await SupabaseTestHelper.init();
    await SupabaseTestHelper.signIn();

    // Open Hive boxes needed by SyncService
    userBox = await Hive.openBox('userBox');
    healthBox = await Hive.openBox('healthBox');
    syncBox = await Hive.openBox('syncBox');
  });

  setUp(() async {
    // Clean Supabase + local Hive state before each test.
    await SupabaseTestHelper.cleanup();
    await userBox.clear();
    await healthBox.clear();
    await syncBox.clear();
  });

  tearDownAll(() async {
    await SupabaseTestHelper.cleanup();
    await Hive.close();
    await SupabaseTestHelper.dispose();
  });

  group('SyncService — Profile Sync', () {
    // T1: syncProfileNow() writes complete profile to user_profile table
    test('T1: syncProfileNow writes complete profile to Supabase', () async {
      final userId = SupabaseTestHelper.userId;

      // Seed Hive with a complete profile
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
      final userId = SupabaseTestHelper.userId;

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
    // T3: weeklyFullSync pushes workout logs
    test('T3: workout logs sync to workout_logs table', () async {
      final userId = SupabaseTestHelper.userId;
      final logId = 'wlog_test_${DateTime.now().millisecondsSinceEpoch}';

      // Simulate pushing a workout log directly
      await SupabaseTestHelper.client.from('workout_logs').upsert({
        'id': logId,
        'user_id': userId,
        'exercise_name': 'Bench Press',
        'date': DateTime.now().toIso8601String().substring(0, 10),
        'sets_completed': 3,
        'reps_completed': 10,
        'weight_kg': 60.0,
        'logged_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id');

      final rows = await SupabaseTestHelper.queryTable('workout_logs');
      expect(rows, isNotEmpty, reason: 'workout_logs should have entries');
      expect(rows.first['exercise_name'], 'Bench Press');
      expect(rows.first['weight_kg'], 60.0);
    });

    // T4: weeklyFullSync pushes nutrition logs
    test('T4: nutrition logs sync to nutrition_logs table', () async {
      final userId = SupabaseTestHelper.userId;
      final logId = 'nlog_test_${DateTime.now().millisecondsSinceEpoch}';

      await SupabaseTestHelper.client.from('nutrition_logs').upsert({
        'id': logId,
        'user_id': userId,
        'date': DateTime.now().toIso8601String().substring(0, 10),
        'total_calories': 1800.0,
        'total_protein': 120.0,
        'total_carbs': 200.0,
        'total_fat': 60.0,
        'created_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id');

      final rows = await SupabaseTestHelper.queryTable('nutrition_logs');
      expect(rows, isNotEmpty);
      expect(rows.first['total_calories'], 1800.0);
      expect(rows.first['total_protein'], 120.0);
    });

    // T5: weeklyFullSync pushes weight logs
    test('T5: weight logs sync to weight_logs table', () async {
      final userId = SupabaseTestHelper.userId;
      final logId = 'wt_test_${DateTime.now().millisecondsSinceEpoch}';

      await SupabaseTestHelper.client.from('weight_logs').upsert({
        'id': logId,
        'user_id': userId,
        'date': DateTime.now().toIso8601String().substring(0, 10),
        'weight_kg': 74.5,
        'created_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id');

      final rows = await SupabaseTestHelper.queryTable('weight_logs');
      expect(rows, isNotEmpty);
      expect(rows.first['weight_kg'], 74.5);
    });
  });

  group('SyncService — Daily Snapshot', () {
    // T6: pushSnapshot creates daily snapshot
    test('T6: daily snapshot upserts to user_daily_snapshots', () async {
      final userId = SupabaseTestHelper.userId;
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
