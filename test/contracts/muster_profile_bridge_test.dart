// APK Test #15.4 / Bug 2b, retired 2026-09-19 (diagnose e2b8a4) — pins the
// muster → profile bridge contract.
//
// Bug class: writer/reader drift. The muster used to capture injuries /
// wake time / preferred workout time / physique focus into coachBox, live-
// bridging each into userBox['profile'] on every answer. That bridge had
// no "don't clobber" guard — since muster always ran AFTER onboarding, its
// injuries answer silently overwrote whatever the user told Details.
// known_injuries / typical_wake_time / preferred_workout_time are RETIRED
// as muster questions: injuries is Details screen's job now (no double-ask,
// no clobber), wake/workout-time is Edit Profile's job (which already had
// full UI for it — muster was pure duplication). recordMusterAnswer now
// REJECTS all three.
//
// This contract pins:
//   - The 3 retired keys throw ArgumentError — recordMusterAnswer is no
//     longer a live writer for them.
//   - body_part_priorities (physique focus, muster's one surviving
//     question) still bridges into BOTH coachBox and userBox['profile'],
//     only when single-element (post-B2d migration) — legacy multi-select
//     shapes are skipped (no fuzzy guess).
//   - why_now / definition_of_winning were already dead (Q1/Q2 dropped
//     per APK Test #15.4/B2a) and are now also rejected, for the same
//     reason as the other retirees: recordMusterAnswer should only accept
//     keys a live caller can actually send.

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
    final tmp = Directory.systemTemp.createTempSync('muster_bridge_').path;
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
    // Per-test fresh user session so user-scoped boxes (userBox,
    // coachBox) are wrapped behind the post-Test-#15.1 GuardedBox.
    await HiveUserSession.closeAll();
    const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    await HiveUserSession.openForUser(fakeUserId);

    await HiveService.instance.userBox.clear();
    await HiveService.instance.coachBox.clear();
    // Seed a minimal profile so updateProfileFields doesn't error.
    await UserRepository.instance.saveProfile({'id': 'test-uid'});
  });

  test('known_injuries is rejected — retired muster question', () async {
    expect(
      () => InductionService.instance
          .recordMusterAnswer('known_injuries', ['shoulders']),
      throwsArgumentError,
    );
    // No write happened on either side.
    expect(HiveService.instance.coachBox.get('known_injuries'), isNull);
  });

  test('typical_wake_time is rejected — retired muster question', () async {
    expect(
      () => InductionService.instance
          .recordMusterAnswer('typical_wake_time', '06:30'),
      throwsArgumentError,
    );
    expect(HiveService.instance.coachBox.get('typical_wake_time'), isNull);
  });

  test('preferred_workout_time is rejected — retired muster question',
      () async {
    expect(
      () => InductionService.instance
          .recordMusterAnswer('preferred_workout_time', '07:15'),
      throwsArgumentError,
    );
    expect(
        HiveService.instance.coachBox.get('preferred_workout_time'), isNull);
  });

  test('body_part_priorities single -> profile.physique_focus', () async {
    await InductionService.instance
        .recordMusterAnswer('body_part_priorities', ['glutes_legs']);

    expect(HiveService.instance.coachBox.get('body_part_priorities'),
        ['glutes_legs']);
    expect(UserRepository.instance.getProfile()!['physique_focus'],
        'glutes_legs');
  });

  test('body_part_priorities multi (legacy) -> no profile write', () async {
    // Pre-B2d data shape: 2+ elements. Bridge must skip to avoid
    // arbitrary picks.
    await UserRepository.instance
        .updateProfileFields({'physique_focus': 'balanced'});
    await InductionService.instance
        .recordMusterAnswer('body_part_priorities', ['legs', 'glutes']);

    expect(HiveService.instance.coachBox.get('body_part_priorities'),
        ['legs', 'glutes']);
    // Profile field stays at the pre-existing value — no fuzzy guess.
    expect(UserRepository.instance.getProfile()!['physique_focus'],
        'balanced');
  });

  test('why_now / definition_of_winning are rejected — dropped pre-B2a',
      () async {
    expect(
      () => InductionService.instance
          .recordMusterAnswer('why_now', 'October wedding'),
      throwsArgumentError,
    );
    expect(
      () => InductionService.instance
          .recordMusterAnswer('definition_of_winning', 'Feel strong'),
      throwsArgumentError,
    );
    expect(HiveService.instance.coachBox.get('why_now'), isNull);
    expect(HiveService.instance.coachBox.get('definition_of_winning'),
        isNull);
  });
}
