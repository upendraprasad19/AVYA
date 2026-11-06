// Unit 1 (follow-up to diagnose b3f9e7, 2026-08-03) — regression coverage for
// the onboarding Hive-session-ordering premise.
//
// WHAT THIS EXISTS TO CATCH. `completeOnboarding()`'s first user-scoped Hive
// write (`_userRepo.saveProfile` -> `ProfileWriteService.updateProfile` ->
// `HiveService.instance.userBox.put('profile', ...)`) resolves through
// `wrapUserScopedBox` (lib/core/services/guarded_box.dart). When
// `HiveUserSession.currentOwnerFullId` is still null (session never opened for
// this device), the write cannot land. Today that is NOT reachable for a
// brand-new Google OAuth signup only because of an INCIDENTAL ordering
// property: `RestoringScreen._kickoffRestore` (restoring_screen.dart:116-117)
// fires `SyncService.restoreFromCloudForUser()` in parallel with destination
// resolution, and that method's first substantive line (sync_service.dart:1296)
// is `await HiveUserSession.openForUser(userId)` -- so by the time the user
// clicks through 6 onboarding screens, the session is already open. Nothing
// AWAITS or JOINS that future before allowing onboarding navigation, so a
// future `RestoringScreen` refactor (e.g. navigating the brand-new-user branch
// before kicking off the restore future) could silently reintroduce the
// failure. The defensive guard --
// `HiveUserSession.ensureOpenedForCurrentSession()` in `completeOnboarding` --
// makes the safety an invariant of the method itself rather than of its caller.
//
// WHICH FAILURE BRANCH IS REAL (round-1 review finding S2). `wrapUserScopedBox`
// has TWO owner-null branches (guarded_box.dart:320-338) and they are not
// interchangeable:
//   - UNAUTHENTICATED (no resolvable auth uid) -> throws
//     StateError('HiveUserSession not opened ...') at :335.
//   - AUTHENTICATED but Hive owner still null -> returns `GuardedBox.empty`
//     at :333. On THIS path the throw comes from `GuardedBox.rawBox` at
//     :172 ('GuardedBox.empty: rawBox unavailable ...'), NOT from the
//     write methods' `_emptyStubWriteError` at :87-91 -- because
//     `HiveService.userBox` (hive_service.dart:226) is
//     `userBoxGuarded.rawBox`, so the raw Box is unwrapped before any
//     put/delete is reached. (Round-2 finding B2-2: the first draft of this
//     comment named the write-method site, which is dead code on this path.)
// An onboarding user is AUTHENTICATED by definition (they just signed up), so
// the second branch is the production-reachable one. The first draft of this
// test pinned the unauthenticated branch -- proving a failure mode onboarding
// can never hit. Group A now drives the authenticated branch via the existing
// `debugAuthUidResolverForTests` seam, so it pins the real mechanism.
//
// Run: flutter test test/contracts/onboarding_hive_session_open_before_write_test.dart

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/onboarding/providers/onboarding_provider.dart';
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
    tempDir = Directory.systemTemp.createTempSync('onboarding_session_order_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    // A REAL (non-empty) GuardedBox's every op calls `_assertOwnership()`,
    // which reads `Supabase.instance...` unconditionally -- that throws in a
    // pure-VM harness unless bypassed. Does NOT affect the owner-null branches
    // under test, which fire from `wrapUserScopedBox` before any real
    // GuardedBox exists. Same flag/reasoning as
    // `pro_phase_advance_behavioral_test.dart`.
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    debugAuthUidResolverForTests = null;
    HiveUserSession.debugCurrentUidResolverForTests = null;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    // Every test starts with the session CLOSED and the user AUTHENTICATED --
    // the brand-new-signup premise (signed up, nobody has called openForUser).
    await HiveUserSession.closeAll();
    debugAuthUidResolverForTests = () => testUser;
    HiveUserSession.debugCurrentUidResolverForTests = () => testUser;
  });

  tearDown(() {
    debugAuthUidResolverForTests = null;
    HiveUserSession.debugCurrentUidResolverForTests = null;
  });

  group('A -- the real failure mode (authenticated, session not yet open)', () {
    test(
        'writing the profile before the session is open throws and the write '
        'does NOT land', () async {
      await expectLater(
        ProfileWriteService.instance.updateProfile(
          <String, dynamic>{'full_name': 'Test Soldier'},
          skipSync: true,
        ),
        // The MESSAGE matcher is load-bearing, not decoration (round-2
        // finding B2-1). All three reachable owner-null failures throw
        // StateError, so a bare `isA<StateError>()` cannot tell the
        // production-reachable AUTHENTICATED branch from the unreachable
        // UNAUTHENTICATED one -- round 1 briefly loosened it to exactly that
        // and the round-2 reviewer proved the test then passed green while
        // silently pinning the wrong branch again (delete the
        // `debugAuthUidResolverForTests` line in setUp to reproduce). Pinning
        // 'GuardedBox.empty' is what keeps the S2 fix fixed.
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('GuardedBox.empty'),
          ),
        ),
        reason: 'an authenticated user whose Hive session was never opened '
            'gets GuardedBox.empty -- this is the production-reachable '
            'branch for onboarding (round-1 S2). If this fails with '
            '"HiveUserSession not opened" instead, the test has regressed '
            'to the unauthenticated branch onboarding can never hit.',
      );
    });
  });

  group('B -- the guard itself opens the session (real Hive round-trip)', () {
    test(
        'ensureOpenedForCurrentSession() makes the very same write succeed '
        'and round-trip', () async {
      // This is the guard completeOnboarding calls -- not a stand-in.
      final resolved = await HiveUserSession.ensureOpenedForCurrentSession();
      expect(resolved, testUser,
          reason: 'the guard must resolve the authenticated uid');
      expect(HiveUserSession.currentOwnerFullId, testUser,
          reason: 'and must actually have opened the session for it');

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

  group('C -- completeOnboarding drives the guard (BEHAVIORAL) + a source-pin '
      'on ordering', () {
    // WHY BOTH. Rule 21 wants a behavioral test that fails when the runtime
    // path breaks, not a text search. C1 below is that test. C2 is kept
    // alongside it because the two catch different regressions: C1 proves
    // the guard RAN (it would still pass if the guard were moved AFTER the
    // write, since the write would then simply open nothing and throw --
    // caught, yes, but for the wrong reason); C2 pins the ORDERING
    // explicitly and gives a precise diagnostic when someone reorders the
    // method. Cheap to keep both.
    //
    // HISTORY, recorded because the recovery is the instructive part
    // (round-2 finding B2-4). Round 1 attempted exactly the C1 test below,
    // saw completeOnboarding fail with an opaque `_AssertionError`, and
    // wrote it off as an undiagnosable pure-VM harness limitation --
    // documenting that conclusion in this file and the diagnose-doc.
    // That conclusion was WRONG, and the way it was wrong matters: the
    // assertion text was fully recoverable with zero production changes,
    // because completeOnboarding's own catch passes `e.toString()` to
    // `ErrorTelemetry.logEvent` (onboarding_provider.dart:550-554) and
    // `ErrorTelemetry.debugOnLogEventForTests` (error_telemetry.dart:69-70)
    // exists precisely so a test can read it. Doing that took one run and
    // produced: `Unknown fitness goal token "fat_loss"` --
    // i.e. round 1's own test data was invalid ('fat_loss' is not a token;
    // the real one is 'lose_fat', fitness_goals.dart:74). The "environmental
    // blocker" was a typo in the test. Lesson worth keeping: an opaque
    // failure is a reason to find the seam that makes it legible, not a
    // licence to document it as impossible.
    test(
        'C1 (behavioral): completeOnboarding opens the Hive session via its '
        'guard and its first user-scoped write lands', () async {
      expect(HiveUserSession.currentOwnerFullId, isNull,
          reason: 'precondition: the session must NOT be open on entry, '
              'otherwise this would pass even with the guard deleted');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(onboardingProvider.notifier);
      notifier.setAnswer('full_name', 'Recruit Behavioral');
      notifier.setAnswer('date_of_birth', '1995-06-15');
      notifier.setAnswer('gender', 'male');
      notifier.setAnswer('height_cm', 175);
      notifier.setAnswer('current_weight_kg', 72);
      notifier.setAnswer('target_weight_kg', 68);
      // MUST be a real FitnessGoals token -- see the history note above.
      notifier.setAnswer('primary_goal', 'lose_fat');
      notifier.setAnswer('fitness_experience', 'beginner');
      notifier.setAnswer('days_per_week', 4);
      notifier.setAnswer('equipment_access', 'bodyweight');

      // Capture what completeOnboarding swallows, so a future failure here
      // is self-diagnosing instead of opaque (this is the seam whose
      // absence round 1 wrongly assumed).
      final telemetry = <String>[];
      ErrorTelemetry.debugOnLogEventForTests = (op, {message}) {
        telemetry.add('$op: $message');
      };
      addTearDown(() => ErrorTelemetry.debugOnLogEventForTests = null);

      // completeOnboarding does not throw out of itself: it wraps its whole
      // body in try/catch and converts any failure into `state.error` plus a
      // swallowed `onboarding_complete_failed` telemetry event. So there is
      // deliberately NO bare try/catch here -- an earlier draft had
      // `catch (_) {}`, which would hide a real regression while telling the
      // next reader not to look.
      await notifier.completeOnboarding();

      // It DOES fail internally in this harness, and that is expected and
      // benign: plan generation needs a seeded exercise library this
      // pure-VM test deliberately does not build, so the run ends in
      // `HiveError: Box not found`. What must NEVER happen is a failure of
      // the SESSION-ORDERING class -- that is the regression this whole
      // file exists to catch, and swallowing it silently is exactly how it
      // would hide. So rather than asserting "nothing was swallowed"
      // (false) or ignoring the telemetry entirely (blind), assert on the
      // specific class.
      final sessionClassFailures = telemetry.where((t) =>
          t.startsWith('onboarding_complete_failed') &&
          (t.contains('GuardedBox') || t.contains('HiveUserSession')));
      expect(sessionClassFailures, isEmpty,
          reason: 'completeOnboarding swallowed a Hive-session failure -- '
              'this is the Unit 1 regression class. Captured: $telemetry');

      expect(HiveUserSession.currentOwnerFullId, testUser,
          reason: 'completeOnboarding must have opened the Hive session via '
              'its defensive guard. If the guard was removed, this is the '
              'Unit 1 regression. Swallowed telemetry: $telemetry');

      final saved = UserRepository.instance.getProfile();
      expect(saved, isNotNull,
          reason: 'with the session open, the first user-scoped write must '
              'have landed in real Hive. Swallowed telemetry: $telemetry');
      expect(saved!['full_name'], 'Recruit Behavioral',
          reason: 'and it must be THIS run\'s profile');
    });

    test(
        'C2 (source-pin on ordering): '
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
              'after -- an after-the-fact guard cannot prevent the failure '
              'this test class exists to catch');
    });
  });
}
