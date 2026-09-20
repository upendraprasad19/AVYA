@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'supabase_test_helper.dart';

/// Layer 1: Auth restore and gap detection tests.
///
/// Verifies the data flow between Hive (local) and Supabase (cloud)
/// during sign-in, sign-out, and profile edit operations.
///
/// Run: flutter test test/supabase/auth_restore_test.dart
void main() {
  if (!SupabaseTestHelper.hasCredentials) {
    test('SKIPPED: SUPABASE_URL / _ANON_KEY / _TEST_EMAIL / _TEST_PASSWORD not all set', () {});
    return;
  }

  late Box userBox;
  late Box configBox;

  setUpAll(() async {
    await SupabaseTestHelper.init();
    await SupabaseTestHelper.signIn();

    userBox = await Hive.openBox('userBox');
    configBox = await Hive.openBox('configBox');
  });

  setUp(() async {
    await SupabaseTestHelper.cleanup();
    await userBox.clear();
    await configBox.clear();
  });

  tearDownAll(() async {
    await SupabaseTestHelper.cleanup();
    await Hive.close();
    await SupabaseTestHelper.dispose();
  });

  group('Onboarding Sync', () {
    // T9: Onboarding sync writes to users, user_profile, user_progress
    test('T9: onboarding sync writes to all 3 tables', () async {
      final userId = SupabaseTestHelper.userId;
      final client = SupabaseTestHelper.client;

      // Simulate _syncOnboardingToSupabase — write to all 3 tables
      await client.from('users').upsert({
        'id': userId,
        'email': SupabaseTestHelper.testEmail,
        'full_name': 'QA Tester',
        'onboarding_completed': true,
        'last_active_at': DateTime.now().toIso8601String(),
      });

      await client.from('user_profile').upsert({
        'user_id': userId,
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
      }, onConflict: 'user_id');

      await client.from('user_progress').upsert({
        'user_id': userId,
        'current_phase': 1,
        'current_week': 1,
        'total_workouts_done': 0,
        'current_streak_weeks': 0,
        'phase_started_at': DateTime.now().toIso8601String(),
        'plan_generated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');

      // Verify all 3 tables
      final users = await client
          .from('users')
          .select()
          .eq('id', userId);
      expect(users, isNotEmpty);
      expect(users.first['full_name'], 'QA Tester');
      expect(users.first['onboarding_completed'], true);

      final profile = await SupabaseTestHelper.queryTable('user_profile');
      expect(profile, isNotEmpty);
      expect(profile.first['primary_goal'], 'build_muscle');
      expect(profile.first['height_cm'], 175.0);

      final progress = await SupabaseTestHelper.queryTable('user_progress');
      expect(progress, isNotEmpty);
      expect(progress.first['current_phase'], 1);
    });
  });

  group('Gap Detection', () {
    // T10: Gap detection pushes missing profile
    test('T10: detects missing user_profile and can push it', () async {
      final userId = SupabaseTestHelper.userId;

      // Ensure user_profile is empty (cleanup already did this)
      final before = await SupabaseTestHelper.queryTable('user_profile');
      expect(before, isEmpty, reason: 'Precondition: no user_profile row');

      // Simulate gap detection: Hive has profile, Supabase doesn't
      await userBox.put('profile', {
        'id': userId,
        'full_name': 'QA Tester',
        'gender': 'male',
        'height_cm': 175.0,
        'current_weight_kg': 75.0,
        'primary_goal': 'build_muscle',
        'fitness_experience': 'intermediate',
        'days_per_week': 4,
        'equipment_access': 'full_gym',
      });

      // Simulate syncProfileNow — push Hive profile to Supabase
      final p = Map<String, dynamic>.from(userBox.get('profile') as Map);
      await SupabaseTestHelper.client.from('user_profile').upsert({
        'user_id': userId,
        if (p['gender'] != null) 'gender': p['gender'],
        if (p['height_cm'] != null) 'height_cm': p['height_cm'],
        if (p['current_weight_kg'] != null)
          'current_weight_kg': p['current_weight_kg'],
        if (p['primary_goal'] != null) 'primary_goal': p['primary_goal'],
        if (p['fitness_experience'] != null)
          'fitness_experience': p['fitness_experience'],
        if (p['days_per_week'] != null) 'days_per_week': p['days_per_week'],
        if (p['equipment_access'] != null)
          'equipment_access': p['equipment_access'],
      }, onConflict: 'user_id');

      // Verify: row now exists
      final after = await SupabaseTestHelper.queryTable('user_profile');
      expect(after, isNotEmpty, reason: 'Gap detection should push profile');
      expect(after.first['primary_goal'], 'build_muscle');
    });

    // T11: Empty row detection — all-NULL row is not treated as returning user
    test('T11: empty user_profile row detected as invalid', () async {
      final userId = SupabaseTestHelper.userId;

      // Insert an empty row (simulates sync error creating stub row)
      await SupabaseTestHelper.client.from('user_profile').upsert({
        'user_id': userId,
        // All other fields NULL
      }, onConflict: 'user_id');

      final rows = await SupabaseTestHelper.queryTable('user_profile');
      expect(rows, isNotEmpty, reason: 'Row exists');

      // Check: hasRealData logic — same as auth_provider.dart
      final row = rows.first;
      final hasRealData =
          row['primary_goal'] != null || row['height_cm'] != null;
      expect(hasRealData, isFalse,
          reason: 'Empty row should NOT be treated as valid returning user');
    });
  });

  group('Profile Edit Sync', () {
    // T12: Profile edit triggers immediate sync
    test('T12: Hive profile update pushes to Supabase immediately', () async {
      final userId = SupabaseTestHelper.userId;

      // Initial profile in Hive
      await userBox.put('profile', {
        'id': userId,
        'current_weight_kg': 75.0,
        'primary_goal': 'build_muscle',
        'height_cm': 175.0,
        'gender': 'male',
      });

      // Simulate profile edit: change weight
      final profile = Map<String, dynamic>.from(userBox.get('profile') as Map);
      profile['current_weight_kg'] = 72.0;
      await userBox.put('profile', profile);

      // Simulate syncProfileNow after edit
      final p = Map<String, dynamic>.from(userBox.get('profile') as Map);
      await SupabaseTestHelper.client.from('user_profile').upsert({
        'user_id': userId,
        if (p['gender'] != null) 'gender': p['gender'],
        if (p['height_cm'] != null) 'height_cm': p['height_cm'],
        if (p['current_weight_kg'] != null)
          'current_weight_kg': p['current_weight_kg'],
        if (p['primary_goal'] != null) 'primary_goal': p['primary_goal'],
      }, onConflict: 'user_id');

      // Verify Supabase has updated weight
      final rows = await SupabaseTestHelper.queryTable('user_profile');
      expect(rows, isNotEmpty);
      expect(rows.first['current_weight_kg'], 72.0,
          reason: 'Supabase should reflect the edit');
    });
  });

  group('Sign-out & Restore', () {
    // T13: Sign-out preserves Supabase data
    test('T13: Supabase data persists after Hive clear', () async {
      final userId = SupabaseTestHelper.userId;

      // Seed Supabase with profile
      await SupabaseTestHelper.client.from('user_profile').upsert({
        'user_id': userId,
        'gender': 'male',
        'height_cm': 175.0,
        'primary_goal': 'build_muscle',
      }, onConflict: 'user_id');

      // Simulate sign-out: clear Hive
      await userBox.clear();
      await configBox.clear();

      // Hive is empty
      expect(userBox.get('profile'), isNull);
      expect(configBox.get('onboarding_completed'), isNull);

      // Supabase should still have the data
      final rows = await SupabaseTestHelper.queryTable('user_profile');
      expect(rows, isNotEmpty,
          reason: 'Supabase data should survive local clear');
      expect(rows.first['primary_goal'], 'build_muscle');
    });

    // T14: Re-login restores profile from Supabase
    test('T14: profile restored from Supabase to Hive on re-login', () async {
      final userId = SupabaseTestHelper.userId;

      // Seed Supabase with profile data
      await SupabaseTestHelper.client.from('user_profile').upsert({
        'user_id': userId,
        'gender': 'male',
        'height_cm': 175.0,
        'current_weight_kg': 75.0,
        'primary_goal': 'build_muscle',
        'fitness_experience': 'intermediate',
      }, onConflict: 'user_id');

      // Simulate: Hive is empty (after sign-out)
      expect(userBox.get('profile'), isNull);

      // Simulate _ensureLocalUser restore logic
      final profileRows = await SupabaseTestHelper.client
          .from('user_profile')
          .select()
          .eq('user_id', userId)
          .limit(1);

      expect(profileRows, isNotEmpty);

      // Check hasRealData
      final remoteProfile =
          Map<String, dynamic>.from(profileRows.first as Map);
      final hasRealData = remoteProfile['primary_goal'] != null ||
          remoteProfile['height_cm'] != null;
      expect(hasRealData, isTrue);

      // Restore to Hive
      remoteProfile['id'] = userId;
      remoteProfile['email'] = SupabaseTestHelper.testEmail;
      await userBox.put('profile', remoteProfile);
      await configBox.put('onboarding_completed', true);

      // Verify Hive is populated
      final restored =
          Map<String, dynamic>.from(userBox.get('profile') as Map);
      expect(restored['primary_goal'], 'build_muscle');
      expect(restored['height_cm'], 175.0);
      expect(configBox.get('onboarding_completed'), true);
    });
  });

  group('Stale Hive Guard', () {
    // T15: onboarding_completed=true but stub profile → should redirect to onboarding
    test('T15: stale Hive with stub profile clears onboarding flag', () async {
      final userId = SupabaseTestHelper.userId;

      // Simulate stale state: flag is set but profile is a minimal stub
      await configBox.put('onboarding_completed', true);
      await userBox.put('profile', {
        'id': userId,
        'email': SupabaseTestHelper.testEmail,
        'created_at': DateTime.now().toIso8601String(),
        // NO primary_goal, NO height_cm — stub only
      });

      // Reproduce the guard logic from splash_screen.dart
      final isOnboarded =
          configBox.get('onboarding_completed', defaultValue: false) as bool;
      expect(isOnboarded, isTrue, reason: 'Precondition: flag is set');

      final profile = userBox.get('profile');
      expect(profile, isNotNull);

      final profileMap = profile as Map;
      final hasRealData =
          profileMap['primary_goal'] != null || profileMap['height_cm'] != null;

      expect(hasRealData, isFalse,
          reason: 'Stub profile should NOT count as real onboarding data');

      // Guard action: clear the stale flag
      if (!hasRealData) {
        await configBox.delete('onboarding_completed');
      }

      expect(configBox.get('onboarding_completed'), isNull,
          reason: 'Stale flag should be cleared → user redirected to onboarding');
    });

    // T16: onboarding_completed=true with real profile → should proceed to home
    test('T16: real profile with flag set passes guard', () async {
      final userId = SupabaseTestHelper.userId;

      await configBox.put('onboarding_completed', true);
      await userBox.put('profile', {
        'id': userId,
        'email': SupabaseTestHelper.testEmail,
        'primary_goal': 'build_muscle',
        'height_cm': 175.0,
        'current_weight_kg': 75.0,
      });

      final profile = userBox.get('profile') as Map;
      final hasRealData =
          profile['primary_goal'] != null || profile['height_cm'] != null;

      expect(hasRealData, isTrue,
          reason: 'Real profile should pass the guard');
      expect(configBox.get('onboarding_completed'), true,
          reason: 'Flag should remain set → user goes to home');
    });
  });
}
