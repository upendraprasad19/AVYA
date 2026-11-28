// BEHAVIOURAL: `saveBodyFatAssessment` decides under the profile write lock
// (diagnose d7a2e4). The AI call takes seconds, and the write may wait behind
// another profile write: the account and the stored value are read when the
// write actually runs, never before it queues.
//
// A plain test, not a widget test: the lock is held across real futures.
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/profile/screens/edit_profile_screen.dart';
import 'package:icanbefitter/features/profile/services/profile_write_service.dart';

import '../helpers/hive_test_setup.dart';

const _other = 'aaaa0000-0000-0000-0000-000000000000';
const _result = <String, dynamic>{
  'body_fat_percent': 18.0,
  'body_fat_assessed_at': '2026-11-26T04:00:00.000Z',
};

void main() {
  late Directory dir;
  late ProviderContainer container;

  setUp(() async {
    dir = await setUpHiveForTests();
    await HiveService.instance.userBox
        .put('profile', <String, dynamic>{'body_fat_percent': 22.0});
    container = ProviderContainer(overrides: [
      authUserIdTokenProvider.overrideWithValue(kTestUserId),
    ]);
    container.read(userProfileProvider);
  });

  tearDown(() async {
    container.dispose();
    await tearDownHiveForTests(dir);
  });

  double? stored() => ((HiveService.instance.userBox.get('profile')
          as Map)['body_fat_percent'] as num?)
      ?.toDouble();

  /// Queues the save behind a held lock, runs [whileQueued], then releases.
  Future<bool> saveBehindLock(
      Future<void> Function() whileQueued, String Function() ownerNow) async {
    final release = Completer<void>();
    final held =
        ProfileWriteService.instance.debugHoldLockUntil(release.future);
    final pending = saveBodyFatAssessment(
        container: container,
        ownerAtStart: kTestUserId,
        ownerNow: ownerNow,
        bodyFatAtStart: 22.0,
        updates: Map<String, dynamic>.from(_result));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await whileQueued();
    release.complete();
    await held;
    return pending;
  }

  test('a write that only waited is stored and reaches the provider', () async {
    expect(await saveBehindLock(() async {}, () => kTestUserId), isTrue);
    expect(stored(), 18.0);
    expect(container.read(userProfileProvider)['body_fat_percent'], 18.0);
  });

  test('mirror: the account changing while the write waits writes nothing',
      () async {
    var owner = kTestUserId;
    expect(await saveBehindLock(() async => owner = _other, () => owner),
        isFalse);
    expect(stored(), 22.0);
  });

  test('mirror: a value stored while the write waits is not replaced', () async {
    expect(
        await saveBehindLock(
            () async => HiveService.instance.userBox
                .put('profile', <String, dynamic>{'body_fat_percent': 15.0}),
            () => kTestUserId),
        isFalse);
    expect(stored(), 15.0);
  });
}
