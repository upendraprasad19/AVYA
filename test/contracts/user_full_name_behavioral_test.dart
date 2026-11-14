// test/contracts/user_full_name_behavioral_test.dart
//
// BEHAVIORAL contract for the `user_full_name` SoT registry concept.
//
// Concept: a `full_name` written to `userBox['profile']` via
// `ProfileWriteService.instance.updateProfile(map)` MUST be readable
// via `UserRepository.instance.getProfile()['full_name']`.
//
// This test exercises the real write→read round-trip:
//   writer: ProfileWriteService.updateProfile → userBox.put('profile', stamped)
//           (same path used by onboarding_provider.completeOnboarding via
//            UserRepository.saveProfile(profile) → ProfileWriteService.updateProfile)
//           (same path used by _restoreUserProfile via
//            ProfileWriteService.updateProfile(merged, skipSync: true))
//   reader: UserRepository.getProfile → _hive.userBox.get('profile')
//
// It FAILS if:
//   - the Hive key 'profile' is renamed on either side
//   - the field 'full_name' inside the map drifts to 'name', 'fullName', etc.
//   - ProfileWriteService strips 'full_name' when stamping updated_at
//   - UserRepository.getProfile reads from a different box
//
// Bug class prevented: if the writer stamps under 'full_name' but the reader
// looks for 'name', every user appears as a blank or their email on profile
// screen.  Source-grep of 'full_name' passes even when one side uses a
// different key; only a Hive round-trip through the real writer+reader catches
// the semantic drift.
//
// Concepts covered: `user_full_name`
// Writer: lib/features/profile/services/profile_write_service.dart (updateProfile)
//         Same path is reached from:
//           lib/features/onboarding/providers/onboarding_provider.dart
//             → UserRepository.saveProfile
//             → ProfileWriteService.updateProfile
//           lib/core/services/sync/sync_profile.dart (_restoreUserProfile)
//             → ProfileWriteService.updateProfile(merged, skipSync: true)
// Reader: lib/shared/repositories/user_repository.dart (getProfile)
//           → HiveService.instance.userBox.get('profile')
//
// Run: flutter test test/contracts/user_full_name_behavioral_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/profile/services/profile_write_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('user_full_name_hive_');
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
    await HiveUserSession.closeAll();
  });

  group('user_full_name — write→read round-trip (behavioral)', () {
    test(
        'ProfileWriteService.updateProfile preserves full_name in userBox["profile"] '
        'and UserRepository.getProfile reads the same field name', () async {
      const userId = 'eeee1111-eeee-eeee-eeee-eeeeeeeeeeee';
      await HiveUserSession.openForUser(userId);

      // --- Write via the canonical onboarding/restore writer path ---
      // This is exactly what onboarding_provider.completeOnboarding does
      // (via UserRepository.saveProfile → ProfileWriteService.updateProfile)
      // and what _restoreUserProfile does
      // (ProfileWriteService.updateProfile(merged, skipSync: true)).
      await ProfileWriteService.instance.updateProfile(<String, dynamic>{
        'full_name': 'Arjun Singh',
        'date_of_birth': '1995-06-15',
        'primary_goal': 'build_muscle',
        'current_weight_kg': 72.5,
        'height_cm': 175.0,
        'fitness_experience': 'beginner',
      });

      // --- Read via the canonical reader path ---
      // UserRepository.getProfile → _hive.userBox.get('profile')
      final profile = UserRepository.instance.getProfile();

      expect(profile, isNotNull,
          reason: 'getProfile() must return non-null after updateProfile');

      expect(profile!['full_name'], 'Arjun Singh',
          reason: "The field key MUST be exactly 'full_name' on both sides. "
              "If the writer stamps 'name' or 'fullName' the reader returns null "
              "and the profile screen shows a blank display name.");
    });

    test(
        'restore path (skipSync: true) also preserves full_name '
        '(the _restoreUserProfile code path)', () async {
      const userId = 'eeee2222-eeee-eeee-eeee-eeeeeeeeeeee';
      await HiveUserSession.openForUser(userId);

      // _restoreUserProfile calls updateProfile with skipSync: true.
      // The skipSync flag must NOT strip or transform any profile fields.
      await ProfileWriteService.instance.updateProfile(
        <String, dynamic>{
          'full_name': 'Priya Sharma',
          'date_of_birth': '1998-02-20',
          'primary_goal': 'lose_fat',
          'current_weight_kg': 60.0,
          'height_cm': 162.0,
        },
        skipSync: true,
      );

      final profile = UserRepository.instance.getProfile();

      expect(profile, isNotNull);
      expect(profile!['full_name'], 'Priya Sharma',
          reason: 'skipSync: true must NOT affect the Hive write — '
              'full_name must survive the restore-class write path.');
    });

    test(
        'patchProfile preserves existing full_name when unrelated fields are updated '
        '(goal/weight edits must not clobber the display name)', () async {
      const userId = 'eeee3333-eeee-eeee-eeee-eeeeeeeeeeee';
      await HiveUserSession.openForUser(userId);

      // Establish initial profile with full_name.
      await ProfileWriteService.instance.updateProfile(<String, dynamic>{
        'full_name': 'Rohit Verma',
        'primary_goal': 'build_muscle',
        'current_weight_kg': 80.0,
      });

      // Simulate Edit Profile → goal change: patchProfile called with goal only.
      await ProfileWriteService.instance
          .patchProfile(<String, dynamic>{'primary_goal': 'maintain'});

      final profile = UserRepository.instance.getProfile();

      expect(profile, isNotNull);
      expect(profile!['full_name'], 'Rohit Verma',
          reason: 'patchProfile must merge over the existing map, not replace '
              'it — full_name written by onboarding must survive a '
              'subsequent goal edit. If this fails, patchProfile is '
              'starting from an empty base instead of the existing map.');
      expect(profile['primary_goal'], 'maintain',
          reason: 'patch target field must be updated');
    });

    test(
        'full_name is user-scoped: user-A full_name not visible to user-B '
        '(userBox namespacing works for profile map)', () async {
      const userA = 'eeee4444-eeee-eeee-eeee-aaaaaaaaaaaa';
      const userB = 'eeee5555-eeee-eeee-eeee-bbbbbbbbbbbb';

      // User A writes profile.
      await HiveUserSession.openForUser(userA);
      await ProfileWriteService.instance.updateProfile(<String, dynamic>{
        'full_name': 'User Alpha',
        'primary_goal': 'build_muscle',
      });
      final profileA = UserRepository.instance.getProfile();
      expect(profileA!['full_name'], 'User Alpha',
          reason: 'sanity: user-A can read their own full_name');

      // Swap to user B.
      await HiveUserSession.closeAll();
      await HiveUserSession.openForUser(userB);

      final profileB = UserRepository.instance.getProfile();
      expect(profileB, isNull,
          reason: 'user-B must not see user-A\'s profile — '
              'userBox is namespaced per user; a non-null profile here '
              'would mean the namespace broke and user-B is reading '
              'user-A\'s data (cross-user full_name leak).');
    });
  });
}
