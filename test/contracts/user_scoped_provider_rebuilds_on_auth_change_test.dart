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
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_flag_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

const _userA = '5f0a13b2-aaaa-bbbb-cccc-dddddddddddd';
const _userB = '5f0a13b2-eeee-ffff-aaaa-bbbbbbbbbbbb';
// A different first-8-hex prefix: the per-user box name is derived from it, so
// _userA and _userB above share ONE set of boxes (hive_user_session.dart
// namespacedBoxName).
const _userC = '7a1b2c3d-aaaa-bbbb-cccc-eeeeeeeeeeee';

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

  // L2b Landing B: the two user-scoped providers of the measurements sheet
  // follow the auth token as well (Bug c4055a class).
  test('bodyMeasurementsProvider rebuilds against the new user\'s box when '
      'authUserIdTokenProvider changes', () async {
    await HiveService.instance.healthBox.put('measurement_2026-10-05', {
      'id': 'a',
      'date': '2026-10-05',
      'waist': 81.0,
      'updated_at_ms': 1,
    });
    final container = ProviderContainer(overrides: [
      authUserIdTokenProvider.overrideWithValue(_userA),
    ]);
    addTearDown(container.dispose);
    final sub = container.listen(bodyMeasurementsProvider, (_, __) {});
    addTearDown(sub.close);

    expect(container.read(bodyMeasurementsProvider).latest['waist']?.cm, 81.0,
        reason: 'first read reflects user A');

    await HiveUserSession.openForUser(_userC);
    await HiveService.instance.healthBox.put('measurement_2026-10-06', {
      'id': 'b',
      'date': '2026-10-06',
      'chest': 100.0,
      'updated_at_ms': 1,
    });
    container.updateOverrides([
      authUserIdTokenProvider.overrideWithValue(_userC),
    ]);

    final s = container.read(bodyMeasurementsProvider);
    expect(s.latest.keys.toSet(), {'chest'},
        reason: 'after the token changes the provider rebuilds from B\'s box');
    expect(s.latest.containsKey('waist'), isFalse);
  });

  test('measurementsEnabledProvider re-reads the flag when the token '
      'changes', () async {
    final container = ProviderContainer(overrides: [
      authUserIdTokenProvider.overrideWithValue(_userA),
    ]);
    addTearDown(container.dispose);
    final sub = container.listen(measurementsEnabledProvider, (_, __) {});
    addTearDown(sub.close);
    expect(container.read(measurementsEnabledProvider), isTrue,
        reason: 'absent reads the default ON since the 2026-10-16 flip');
    container.updateOverrides([
      authUserIdTokenProvider.overrideWithValue(_userC),
    ]);
    await HiveService.instance.configBox.put('enable_body_measurements', false);
    container.updateOverrides([
      authUserIdTokenProvider.overrideWithValue(_userA),
    ]);
    expect(container.read(measurementsEnabledProvider), isFalse,
        reason: 'a stored false (the kill switch) is re-read on a token change');

    await HiveService.instance.configBox.put('enable_body_measurements', true);
    expect(container.read(measurementsEnabledProvider), isFalse,
        reason: 'cached until something tells it');

    container.updateOverrides([
      authUserIdTokenProvider.overrideWithValue(_userB),
    ]);
    expect(container.read(measurementsEnabledProvider), isTrue);
  });
}
