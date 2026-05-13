// APK Test #15.4 / B2 — pins the one-shot muster → profile backfill
// for users who completed the muster BEFORE the bridge (Phase 3) shipped.
//
// Bug class: writer/reader drift across versions. The bridge in
// `recordMusterAnswer` only fires for NEW muster answers. Existing users
// already have answers in `coachBox` that pre-date the bridge — those
// values must be mirrored into `userBox['profile']` exactly once per
// device, idempotently, without clobbering values the user has since
// edited.
//
// Contract pins:
//   1. Backfill copies coachBox values into profile defaults.
//   2. Backfill is a no-op when the migration flag is already set.
//   3. Backfill never clobbers user-edited values (only writes when the
//      profile field is at its default).
//   4. Backfill skips multi-select legacy `body_part_priorities`
//      (length > 1) — same rule as the live bridge.
//   5. Backfill skips when the only single-select value is `'balanced'`
//      (already the default).
//
// Per CLAUDE.md §15 "Source of Truth Rules" — the muster is the SoT for
// these facts; profile reads from a mirrored copy.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/ai_coach/services/induction_service.dart';
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
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp = Directory.systemTemp.createTempSync('muster_backfill_').path;
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
    // Per-test fresh user session so user-scoped boxes (userBox, coachBox)
    // are wrapped behind the post-Test-#15.1 GuardedBox. Migration box is
    // shared / not user-scoped — opened directly.
    await HiveUserSession.closeAll();
    const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    await HiveUserSession.openForUser(fakeUserId);
    if (!Hive.isBoxOpen(HiveService.migrationBoxName)) {
      await Hive.openBox(HiveService.migrationBoxName);
    }

    await HiveService.instance.userBox.clear();
    await HiveService.instance.coachBox.clear();
    await HiveService.instance.migrationBox.clear();
    // Seed a profile at known defaults so the backfill has something to
    // compare "is this still the default?" against.
    await UserRepository.instance.saveProfile({
      'id': 'test-uid',
      'injuries': ['none'],
      'physique_focus': 'balanced',
    });
  });

  test('backfill copies coachBox into profile defaults', () async {
    await HiveService.instance.coachBox
        .put('known_injuries', ['shoulders']);
    await HiveService.instance.coachBox
        .put('typical_wake_time', '06:30');
    await HiveService.instance.coachBox
        .put('preferred_workout_time', '07:15');
    await HiveService.instance.coachBox
        .put('body_part_priorities', ['glutes_legs']);

    await InductionService.instance.backfillMusterToProfileIfNeeded();

    final profile = UserRepository.instance.getProfile()!;
    expect(profile['injuries'], ['shoulders']);
    expect(profile['wake_up_time'], '06:30');
    expect(profile['preferred_workout_time'], '07:15');
    expect(profile['physique_focus'], 'glutes_legs');

    // Flag is set so re-run is a no-op.
    expect(
      HiveService.instance.migrationBox
          .get('muster_bridge_backfill_v1_done'),
      true,
    );
  });

  test('backfill is no-op when flag already set', () async {
    await HiveService.instance.migrationBox
        .put('muster_bridge_backfill_v1_done', true);
    await HiveService.instance.coachBox
        .put('known_injuries', ['shoulders']);

    await InductionService.instance.backfillMusterToProfileIfNeeded();

    // Injuries stayed at the seeded default — backfill did not run.
    expect(UserRepository.instance.getProfile()!['injuries'], ['none']);
  });

  test('backfill does not clobber user-edited values', () async {
    // User manually edited injuries to a real value post-muster.
    await UserRepository.instance
        .updateProfileFields({'injuries': ['lower back']});
    // CoachBox has an older value that should NOT overwrite the edit.
    await HiveService.instance.coachBox
        .put('known_injuries', ['shoulders']);

    await InductionService.instance.backfillMusterToProfileIfNeeded();

    expect(UserRepository.instance.getProfile()!['injuries'],
        ['lower back']);
  });

  test('backfill skips multi-select legacy body_part_priorities',
      () async {
    await HiveService.instance.coachBox
        .put('body_part_priorities', ['legs', 'glutes']);

    await InductionService.instance.backfillMusterToProfileIfNeeded();

    // physique_focus stays at default — no fuzzy guess for multi-pick.
    expect(UserRepository.instance.getProfile()!['physique_focus'],
        'balanced');
  });

  test('backfill skips when body_part_priorities[0] is balanced (default)',
      () async {
    await HiveService.instance.coachBox
        .put('body_part_priorities', ['balanced']);

    await InductionService.instance.backfillMusterToProfileIfNeeded();

    // No-op — already at default.
    expect(UserRepository.instance.getProfile()!['physique_focus'],
        'balanced');
  });
}
