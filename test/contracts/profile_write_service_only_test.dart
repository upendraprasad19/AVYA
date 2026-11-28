// Tech-debt audit 2026-05-20 finding A4 — behavioral contract for
// ProfileWriteService.
//
// Closes the gap surfaced by Gate 35: prior to this batch, 7 sites
// across auth / home / ai_coach / workout_schedule_service /
// sync_profile / user_repository / tool_dispatcher each issued
// `userBox.put('profile', ...)` independently. There was no
// chokepoint to enforce `updated_at` stamping, no mutex against
// concurrent goal-vs-weight write races, and no canonical place to
// hook future invariants (BMR recompute on weight change, badge
// revalidation on goal change).
//
// This test is BEHAVIORAL (per CLAUDE.md feedback_source_grep_
// false_confidence.md) — it spins up Hive on a temp dir and asserts
// the service's effects on the actual userBox state. Source-grep
// coverage of the no-other-writers invariant is provided by
// `scripts/check_profile_write_service_only.dart` (Gate 35).
//
// Run: flutter test test/contracts/profile_write_service_only_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/profile/services/profile_write_service.dart';
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
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp =
        Directory.systemTemp.createTempSync('profile_write_service_').path;
    PathProviderPlatform.instance = _FakePathProvider(tmp);
    Hive.init(tmp);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
  });

  setUp(() async {
    await HiveUserSession.closeAll();
    const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    await HiveUserSession.openForUser(fakeUserId);
    await HiveService.instance.userBox.clear();
  });

  group('ProfileWriteService — behavioral contract', () {
    test('updateProfile replaces the full profile shape', () async {
      // Seed an existing profile so we can verify replace semantics.
      await ProfileWriteService.instance.updateProfile({
        'id': 'user-1',
        'primary_goal': 'fat_loss',
        'height_cm': 175,
      });

      await ProfileWriteService.instance.updateProfile({
        'id': 'user-1',
        'primary_goal': 'muscle_gain',
        'current_weight_kg': 78.5,
      });

      final stored = HiveService.instance.userBox.get('profile') as Map;
      expect(stored['id'], 'user-1');
      expect(stored['primary_goal'], 'muscle_gain');
      expect(stored['current_weight_kg'], 78.5);
      // height_cm was in the first write but absent from the second —
      // updateProfile is a REPLACE, so it must be gone.
      expect(stored.containsKey('height_cm'), isFalse,
          reason: 'updateProfile is a full-shape replace, not a merge');
      // updated_at must be stamped on every write.
      expect(stored['updated_at'], isA<String>(),
          reason: 'updateProfile must stamp updated_at on every write');
    });

    test('patchProfile merges into existing without dropping other keys',
        () async {
      await ProfileWriteService.instance.updateProfile({
        'id': 'user-2',
        'primary_goal': 'muscle_gain',
        'height_cm': 180,
        'current_weight_kg': 80.0,
      });

      await ProfileWriteService.instance.patchProfile({
        'current_weight_kg': 75.0,
      });

      final stored = HiveService.instance.userBox.get('profile') as Map;
      // Patched field reflects the new value.
      expect(stored['current_weight_kg'], 75.0);
      // Untouched fields survive.
      expect(stored['id'], 'user-2');
      expect(stored['primary_goal'], 'muscle_gain');
      expect(stored['height_cm'], 180);
      expect(stored['updated_at'], isA<String>());
    });

    test('updateField changes exactly one field, leaves others intact',
        () async {
      await ProfileWriteService.instance.updateProfile({
        'id': 'user-3',
        'primary_goal': 'fat_loss',
        'height_cm': 170,
        'current_weight_kg': 72.0,
      });

      await ProfileWriteService.instance
          .updateField('primary_goal', 'recomp');

      final stored = HiveService.instance.userBox.get('profile') as Map;
      expect(stored['primary_goal'], 'recomp');
      expect(stored['id'], 'user-3');
      expect(stored['height_cm'], 170);
      expect(stored['current_weight_kg'], 72.0);
      expect(stored['updated_at'], isA<String>());
    });

    test('patchProfile on empty Hive creates the profile', () async {
      // No prior profile in Hive.
      expect(HiveService.instance.userBox.get('profile'), isNull);

      await ProfileWriteService.instance
          .patchProfile({'id': 'user-4', 'primary_goal': 'general_fitness'});

      final stored = HiveService.instance.userBox.get('profile') as Map;
      expect(stored['id'], 'user-4');
      expect(stored['primary_goal'], 'general_fitness');
    });
  });
}
