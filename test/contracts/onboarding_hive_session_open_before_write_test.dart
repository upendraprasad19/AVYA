// Unit 1 (follow-up to diagnose b3f9e7, 2026-08-03) — regression coverage for
// the onboarding Hive-session-ordering premise.
//
// WHAT THIS EXISTS TO CATCH. `completeOnboarding()`'s first Hive write
// (`_userRepo.saveProfile` -> `ProfileWriteService.updateProfile` ->
// `HiveService.instance.userBox.put('profile', ...)`) resolves through
// `wrapUserScopedBox` (lib/core/services/guarded_box.dart). When
// `HiveUserSession.currentOwnerFullId` is still null (session never opened
// for this device) AND there is no resolvable auth uid, `wrapUserScopedBox`
// throws `StateError('HiveUserSession not opened ...')` before any write
// happens (guarded_box.dart:335). Today this is NOT reachable for a brand-new
// Google OAuth signup only because of an INCIDENTAL ordering property:
// `RestoringScreen._kickoffRestore` (restoring_screen.dart:116-117) fires
// `SyncService.restoreFromCloudForUser()` in parallel with destination
// resolution, and that method's first substantive line
// (sync_service.dart:1296) is `await HiveUserSession.openForUser(userId)` --
// so by the time the user clicks through 6 onboarding screens to reach
// completeOnboarding, the session is already open. Nothing AWAITS or JOINS
// that future before allowing onboarding navigation, so a future
// `RestoringScreen` refactor (e.g. navigating the brand-new-user branch
// before kicking off the restore future) could silently reintroduce the
// throw with no test catching it.
//
// WHY THIS TEST CANNOT DRIVE completeOnboarding() END-TO-END. The real
// method reads `ref.read(referralCodeStashProvider)` and calls
// `WorkoutScheduleService.instance.generateAndSchedule` (full plan
// generation) -- exercising that honestly needs the real exercise-library
// harness `repeat_content_scheduling_test.dart` already established, plus a
// live `ProviderContainer`. That is orthogonal to what this test verifies
// (session-open-before-write ordering), so instead this drives the EXACT
// SAME production write call chain `completeOnboarding` uses
// (`ProfileWriteService.instance.updateProfile`, reached via
// `UserRepository.saveProfile`) directly against real Hive.
//
// WHY GROUP C IS SOURCE-PINNED, NOT BEHAVIORAL (rule 21 honesty note,
// mirrors `pro_phase_advance_behavioral_test.dart` Group E). The defensive
// guard being added -- `HiveUserSession.ensureOpenedForCurrentSession()` --
// reads `SupabaseService.instance.currentUser?.id`, which returns null
// whenever Supabase was never initialised (supabase_service.dart:80-83).
// There is no `debugAuthUidResolverForTests`-style seam on
// `HiveUserSession.ensureOpenedForCurrentSession` itself (only
// `wrapUserScopedBox` has one), so a pure-VM test cannot make it resolve a
// uid and actually call `openForUser`. Group C therefore pins PRESENCE ONLY:
// that `completeOnboarding`'s source calls the guard textually before its
// first Hive write. Groups A+B behaviorally prove the causal mechanism the
// guard depends on (open-before-write prevents the throw; the guard's own
// correctness is exercised by its many other existing call sites).
//
// Run: flutter test test/contracts/onboarding_hive_session_open_before_write_test.dart

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
  const testUser = 'b00b1e5e-0a1e-4c1c-9999-c0ffeec0ffee';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir =
        Directory.systemTemp.createTempSync('onboarding_session_order_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    // Required for Group B's write to succeed at all: a REAL (non-empty)
    // GuardedBox's every op calls `_assertOwnership()`, which reads
    // `Supabase.instance...` unconditionally (no test seam) -- that throws
    // in a pure-VM harness unless bypassed. Does NOT affect Group A's
    // throw, which fires from `wrapUserScopedBox` itself, before any
    // GuardedBox instance exists. Same flag, same reasoning, as
    // `pro_phase_advance_behavioral_test.dart`.
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    // Every test starts with the session CLOSED -- the brand-new-signup
    // premise (nobody has called openForUser yet).
    await HiveUserSession.closeAll();
  });

  group('A -- the failure mode the bug class would cause (real Hive)', () {
    test(
        'writing the profile before the session is open throws StateError',
        () async {
      expect(
        () => ProfileWriteService.instance.updateProfile(
          <String, dynamic>{'full_name': 'Test Soldier'},
          skipSync: true,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('HiveUserSession not opened'),
          ),
        ),
      );
    });
  });

  group('B -- the fix: open-before-write succeeds (real Hive round-trip)',
      () {
    test('writing the profile after openForUser succeeds and round-trips',
        () async {
      // Stands in for what the defensive guard does once it resolves a
      // uid: open the session BEFORE the write, exactly like
      // RestoringScreen's incidental early `openForUser` does today.
      await HiveUserSession.openForUser(testUser);

      await ProfileWriteService.instance.updateProfile(
        <String, dynamic>{'full_name': 'Test Soldier'},
        skipSync: true,
      );

      final saved = UserRepository.instance.getProfile();
      expect(saved, isNotNull);
      expect(saved!['full_name'], 'Test Soldier',
          reason: 'the write must reach the real namespaced Hive box, not '
              'just avoid throwing');
    });
  });

  group('C -- completeOnboarding calls the guard before its first write '
      '(source-pin, presence only -- see file header)', () {
    test(
        'HiveUserSession.ensureOpenedForCurrentSession() precedes '
        '_userRepo.saveProfile(profile) in completeOnboarding', () {
      final src = File(
        'lib/features/onboarding/providers/onboarding_provider.dart',
      ).readAsStringSync();

      final methodIdx = src.indexOf('Future<Phase?> completeOnboarding');
      expect(methodIdx, greaterThanOrEqualTo(0),
          reason: 'completeOnboarding must exist at its known signature -- '
              'if this fails the method was renamed/moved and this test '
              'needs updating, not deleting');

      final guardIdx = src.indexOf(
        'HiveUserSession.ensureOpenedForCurrentSession()',
        methodIdx,
      );
      final writeIdx = src.indexOf(
        '_userRepo.saveProfile(profile)',
        methodIdx,
      );

      expect(guardIdx, greaterThanOrEqualTo(0),
          reason: 'the defensive guard call is missing from '
              'completeOnboarding -- Unit 1 regressed');
      expect(writeIdx, greaterThan(guardIdx),
          reason: 'the guard must run BEFORE the first Hive write, not '
              'after -- an after-the-fact guard cannot prevent the throw '
              'this test class exists to catch');
    });
  });
}
