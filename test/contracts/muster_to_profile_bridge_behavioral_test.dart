// BEHAVIORAL CONTRACT TEST — muster_to_profile_bridge
//
// Concept:   muster_to_profile_bridge
// Writer:    lib/features/ai_coach/services/induction_service.dart
//            (recordMusterAnswer)
// Reader:    userBox['profile']['physique_focus'] — read by
//            lib/features/profile/screens/edit_profile_screen.dart via
//            UserRepository.instance.getProfile()
//
// Retired 2026-09-19 (diagnose e2b8a4): this file used to pin
// known_injuries -> profile.injuries. That bridge had no "don't clobber"
// guard, and since muster always ran AFTER onboarding's Details screen
// (which already collects injuries), muster's answer silently overwrote
// whatever the user told Details — a live writer/reader-drift bug, not
// just redundant UX. known_injuries / typical_wake_time /
// preferred_workout_time are now RETIRED as muster questions entirely
// (Details screen and Edit Profile own those fields respectively).
// body_part_priorities (physique focus) is muster's one surviving
// question, so this file now pins ITS bridge with the same rigor
// previously given to injuries, plus the retirement itself as a
// behavioral fact.
//
// Assert:
//   After recordMusterAnswer('body_part_priorities', [x]), the value
//   appears in userBox['profile']['physique_focus'] (bridge completes
//   synchronously).
//
//   The bridge:
//     recordMusterAnswer → _bridgeToProfile → UserRepository.updateProfileFields
//     → ProfileWriteService.patchProfile → userBox.put('profile', merged)
//
//   All steps are awaited before recordMusterAnswer returns. Cloud sync is
//   fire-and-forget and is gated behind `SupabaseService.currentUser != null`
//   (null in test) — so no network calls happen here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/ai_coach/services/induction_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// ---------------------------------------------------------------------------
// Fake path provider
// ---------------------------------------------------------------------------

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;

  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;

  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;
  const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-000000000030';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir =
        Directory.systemTemp.createTempSync('muster_bridge_behavioral_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveUserSession.openForUser(fakeUserId);
    // Seed a minimal profile so ProfileWriteService.patchProfile can
    // read-modify-write without starting from an empty map.
    await HiveService.instance.userBox.put('profile', <String, dynamic>{
      'id': fakeUserId,
      'full_name': 'Test User',
      'physique_focus': 'balanced',
    });
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
  });

  // -------------------------------------------------------------------------
  // Test 1 — body_part_priorities bridges to profile['physique_focus']
  // -------------------------------------------------------------------------

  test(
    'recordMusterAnswer("body_part_priorities", [x]) writes physique_focus into userBox[profile]',
    () async {
      // ACT — write via the canonical writer.
      await InductionService.instance
          .recordMusterAnswer('body_part_priorities', ['strength']);

      // ASSERT — direct Hive read (same path edit_profile_screen takes via
      // UserRepository.getProfile → userBox.get('profile')).
      final profile =
          HiveService.instance.userBox.get('profile') as Map?;
      expect(profile, isNotNull,
          reason: 'profile must exist in userBox after bridge');
      expect(profile!['physique_focus'], 'strength',
          reason:
              'profile["physique_focus"] must be the muster answer, single-element unwrapped');
    },
  );

  // -------------------------------------------------------------------------
  // Test 2 — physique_focus is also readable via UserRepository.getProfile()
  // -------------------------------------------------------------------------

  test(
    'physique_focus value is readable via UserRepository.getProfile() after bridge',
    () async {
      await InductionService.instance
          .recordMusterAnswer('body_part_priorities', ['glutes_legs']);

      // Reader path used by edit_profile_screen.
      final profile = await UserRepository.instance.getProfile();
      expect(profile, isNotNull,
          reason: 'UserRepository.getProfile() must return the profile');
      expect(profile!['physique_focus'], 'glutes_legs');
    },
  );

  // -------------------------------------------------------------------------
  // Test 3 — coachBox also contains the raw muster answer (canonical SoT)
  // -------------------------------------------------------------------------

  test(
    'body_part_priorities is also persisted in coachBox (muster SoT)',
    () async {
      await InductionService.instance
          .recordMusterAnswer('body_part_priorities', ['chest_shoulders_arms']);

      final coachValue =
          HiveService.instance.coachBox.get('body_part_priorities');
      expect(coachValue, isNotNull,
          reason: 'coachBox must hold the raw muster answer');
      expect((coachValue as List).cast<String>(),
          equals(['chest_shoulders_arms']),
          reason:
              'coachBox["body_part_priorities"] must equal the written list');
    },
  );

  // -------------------------------------------------------------------------
  // Test 4 — profile patch is additive: pre-existing fields are preserved
  // -------------------------------------------------------------------------

  test(
    'bridge is additive: pre-existing profile fields survive the patch',
    () async {
      // Seed a profile with extra fields.
      await HiveService.instance.userBox.put('profile', <String, dynamic>{
        'id': fakeUserId,
        'full_name': 'Kept Name',
        'current_weight_kg': 75.0,
        'physique_focus': 'balanced',
      });

      await InductionService.instance
          .recordMusterAnswer('body_part_priorities', ['strength']);

      final profile =
          HiveService.instance.userBox.get('profile') as Map?;
      expect(profile?['full_name'], 'Kept Name',
          reason: 'full_name must survive the patchProfile call');
      expect(profile?['current_weight_kg'], 75.0,
          reason: 'current_weight_kg must survive the patchProfile call');
      expect(profile?['physique_focus'], 'strength',
          reason: 'physique_focus must be the newly patched value');
    },
  );

  // -------------------------------------------------------------------------
  // Test 5 — the retirement itself: known_injuries / typical_wake_time /
  // preferred_workout_time no longer bridge anything, because
  // recordMusterAnswer rejects them outright (diagnose e2b8a4).
  // -------------------------------------------------------------------------

  test(
    'retired keys (known_injuries, typical_wake_time, preferred_workout_time) '
    'throw and write nothing on either side',
    () async {
      for (final entry in {
        'known_injuries': ['lower_back'],
        'typical_wake_time': '06:30',
        'preferred_workout_time': '07:00',
      }.entries) {
        expect(
          () => InductionService.instance
              .recordMusterAnswer(entry.key, entry.value),
          throwsArgumentError,
          reason: '${entry.key} must be rejected — retired muster question',
        );
        expect(HiveService.instance.coachBox.get(entry.key), isNull,
            reason: '${entry.key} must not land in coachBox either');
      }
      // Profile is untouched by any of the rejected attempts.
      final profile = HiveService.instance.userBox.get('profile') as Map?;
      expect(profile?['injuries'], isNull);
      expect(profile?['wake_up_time'], isNull);
      expect(profile?['preferred_workout_time'], isNull);
    },
  );
}
