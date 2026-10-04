// test/contracts/user_scoped_provider_rebuilds_on_auth_change_test.dart
//
// Behavioral test for Bug c4055a — every user-scoped Riverpod provider
// MUST re-emit when the auth identity changes.
//
// This test exercises the runtime path:
//   1. Open Hive for user-A. Write profile-A. Read userProfileProvider →
//      observe profile-A.
//   2. Override authUserIdTokenProvider to a different identity (user-B).
//   3. Open Hive for user-B. Write profile-B.
//   4. Read userProfileProvider again → must observe profile-B, not the
//      cached profile-A.
//
// The source-grep test (auth_invalidation_contract_test.dart) pins the
// "is the watch present?" invariant. This test pins the "does the watch
// actually trigger a rebuild?" invariant.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

const _userA = '5f0a13b2-aaaa-bbbb-cccc-dddddddddddd';
const _userB = '5f0a13b2-eeee-ffff-aaaa-bbbbbbbbbbbb';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests(userId: _userA);
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  test(
      'userProfileProvider rebuilds when authUserIdTokenProvider changes '
      '(Bug c4055a)', () async {
    // 1. Seed profile-A under user-A's Hive session.
    await UserRepository.instance.saveProfile({
      'id': _userA,
      'full_name': 'User A',
      'height_cm': 180,
      'current_weight_kg': 90,
    });

    // ProviderContainer with the token pinned to user-A.
    final container = ProviderContainer(overrides: [
      authUserIdTokenProvider.overrideWithValue(_userA),
    ]);
    addTearDown(container.dispose);

    // First read → should reflect profile-A.
    final profileA = container.read(userProfileProvider);
    expect(profileA['full_name'], 'User A',
        reason: 'first read should return user A profile');
    expect((profileA['height_cm'] as num).toInt(), 180);

    // 2. Switch the Hive session to user-B and seed profile-B.
    //    HiveUserSession.openForUser is the production switch path
    //    invoked from auth_provider on sign-in.
    await HiveUserSession.openForUser(_userB);
    await UserRepository.instance.saveProfile({
      'id': _userB,
      'full_name': 'User B',
      'height_cm': 170,
      'current_weight_kg': 70,
    });

    // 3. Flip the token override to user-B. The watch in
    //    UserProfileNotifier.build() must observe the change and
    //    rebuild against the now-user-B Hive box.
    container.updateOverrides([
      authUserIdTokenProvider.overrideWithValue(_userB),
    ]);

    // Sanity: the token override took effect.
    expect(container.read(authUserIdTokenProvider), _userB,
        reason: 'updateOverrides should have flipped the token to user B');

    // 4. Re-read userProfileProvider → must reflect profile-B.
    final profileB = container.read(userProfileProvider);
    expect(profileB['full_name'], 'User B',
        reason:
            'after auth token changes, provider must rebuild against the '
            "new user's Hive box — got: $profileB");
    expect((profileB['height_cm'] as num).toInt(), 170);
    expect((profileB['current_weight_kg'] as num).toInt(), 70);
  });
}
