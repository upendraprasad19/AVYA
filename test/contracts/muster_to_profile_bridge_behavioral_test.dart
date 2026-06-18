// BEHAVIORAL CONTRACT TEST — muster_to_profile_bridge
//
// Concept:   muster_to_profile_bridge
// Writer:    lib/features/ai_coach/services/induction_service.dart
//            (recordMusterAnswer)
// Reader:    userBox['profile']['injuries'] — read by
//            lib/features/profile/screens/edit_profile_screen.dart via
//            UserRepository.instance.getProfile()
//
// Assert:
//   After recordMusterAnswer('known_injuries', [...]), the value appears in
//   userBox['profile']['injuries'] (bridge completes synchronously).
//
//   The bridge:
//     recordMusterAnswer → _bridgeToProfile → UserRepository.updateProfileFields
//     → ProfileWriteService.patchProfile → userBox.put('profile', merged)
//
//   All steps are awaited before recordMusterAnswer returns.  Cloud sync is
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
      'injuries': <String>[],
    });
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
  });

  // -------------------------------------------------------------------------
  // Test 1 — known_injuries bridges to profile['injuries']
  // -------------------------------------------------------------------------

  test(
    'recordMusterAnswer("known_injuries", [...]) writes injuries into userBox[profile]',
    () async {
      final injuries = ['lower_back', 'right_knee'];

      // ACT — write via the canonical writer.
      await InductionService.instance
          .recordMusterAnswer('known_injuries', injuries);

      // ASSERT — direct Hive read (same path edit_profile_screen takes via
      // UserRepository.getProfile → userBox.get('profile')).
      final profile =
          HiveService.instance.userBox.get('profile') as Map?;
      expect(profile, isNotNull,
          reason: 'profile must exist in userBox after bridge');

      final stored = (profile!['injuries'] as List?)?.cast<String>();
      expect(stored, isNotNull,
          reason: 'profile["injuries"] must be present after bridge');
      expect(stored, equals(injuries),
          reason:
              'profile["injuries"] must equal the list passed to '
              'recordMusterAnswer("known_injuries", ...)');
    },
  );

  // -------------------------------------------------------------------------
  // Test 2 — injuries list is also readable via UserRepository.getProfile()
  // -------------------------------------------------------------------------

  test(
    'injuries value is readable via UserRepository.getProfile() after bridge',
    () async {
      final injuries = ['left_shoulder'];

      await InductionService.instance
          .recordMusterAnswer('known_injuries', injuries);

      // Reader path used by edit_profile_screen.
      final profile = await UserRepository.instance.getProfile();
      expect(profile, isNotNull,
          reason: 'UserRepository.getProfile() must return the profile');

      final stored = (profile!['injuries'] as List?)?.cast<String>();
      expect(stored, equals(injuries),
          reason:
              'UserRepository.getProfile()["injuries"] must reflect the '
              'muster answer written via recordMusterAnswer');
    },
  );

  // -------------------------------------------------------------------------
  // Test 3 — coachBox also contains the raw muster answer (canonical SoT)
  // -------------------------------------------------------------------------

  test(
    'known_injuries is also persisted in coachBox (muster SoT)',
    () async {
      final injuries = ['neck', 'lower_back'];

      await InductionService.instance
          .recordMusterAnswer('known_injuries', injuries);

      final coachValue = HiveService.instance.coachBox.get('known_injuries');
      expect(coachValue, isNotNull,
          reason: 'coachBox must hold the raw muster answer');
      expect((coachValue as List).cast<String>(), equals(injuries),
          reason: 'coachBox["known_injuries"] must equal the written list');
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
        'injuries': <String>[],
      });

      await InductionService.instance
          .recordMusterAnswer('known_injuries', ['knee']);

      final profile =
          HiveService.instance.userBox.get('profile') as Map?;
      expect(profile?['full_name'], 'Kept Name',
          reason: 'full_name must survive the patchProfile call');
      expect(profile?['current_weight_kg'], 75.0,
          reason: 'current_weight_kg must survive the patchProfile call');
      expect((profile?['injuries'] as List?)?.cast<String>(), ['knee'],
          reason: 'injuries must be the newly patched value');
    },
  );
}
