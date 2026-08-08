// APK Test #15.4 / Bug 2b — pins the muster → profile bridge contract.
//
// Bug class: writer/reader drift. The muster (coach induction Q1-Q5)
// captures injuries / wake time / preferred workout time / physique
// focus into coachBox. Edit Profile + plan generator read profile
// fields from userBox['profile']. Pre-B2b, the muster never mirrored
// its values into the profile, so the user answered the questions and
// the profile still read defaults.
//
// This contract pins:
//   - Bridged keys land in BOTH coachBox (existing) and
//     userBox['profile'] (new).
//   - body_part_priorities only bridges when single-element (post-B2d
//     migration); legacy multi-select shapes are skipped (no fuzzy
//     guess).
//   - why_now / definition_of_winning are NOT mapped to profile.
//
// Per docs/architecture/sync.md "Source of Truth Rules" — the muster is the SoT
// for these facts; profile reads from a mirrored copy.

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

  test('known_injuries -> profile.injuries', () async {
    await InductionService.instance
        .recordMusterAnswer('known_injuries', ['shoulders', 'lower back']);

    // Raw muster answer is stored verbatim in coachBox.
    expect(HiveService.instance.coachBox.get('known_injuries'),
        ['shoulders', 'lower back']);
    // U1 (a1f6c3): the profile (engine-facing) value is CANONICALIZED via
    // InjuryVocab so the plan engine's exact-match filter matches it
    // ('shoulders' → shoulder, 'lower back' → lower_back).
    final profile = UserRepository.instance.getProfile()!;
    expect(profile['injuries'], ['shoulder', 'lower_back']);
  });

  test('typical_wake_time -> profile.wake_up_time', () async {
    await InductionService.instance
        .recordMusterAnswer('typical_wake_time', '06:30');

    expect(HiveService.instance.coachBox.get('typical_wake_time'), '06:30');
    expect(UserRepository.instance.getProfile()!['wake_up_time'], '06:30');
  });

  test('preferred_workout_time -> profile.preferred_workout_time', () async {
    await InductionService.instance
        .recordMusterAnswer('preferred_workout_time', '07:15');

    expect(HiveService.instance.coachBox.get('preferred_workout_time'),
        '07:15');
    expect(UserRepository.instance.getProfile()!['preferred_workout_time'],
        '07:15');
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

  test('why_now / definition_of_winning -> no profile write', () async {
    await InductionService.instance
        .recordMusterAnswer('why_now', 'October wedding');
    await InductionService.instance
        .recordMusterAnswer('definition_of_winning', 'Feel strong');

    expect(HiveService.instance.coachBox.get('why_now'), 'October wedding');
    expect(HiveService.instance.coachBox.get('definition_of_winning'),
        'Feel strong');
    final profile = UserRepository.instance.getProfile()!;
    // No bridged fields landed.
    expect(profile['injuries'], isNull);
    expect(profile['wake_up_time'], isNull);
    expect(profile['preferred_workout_time'], isNull);
    expect(profile['physique_focus'], isNull);
  });
}
