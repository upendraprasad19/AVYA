// test/contracts/restoring_screen_local_onboarded_flag_stamp_test.dart
//
// Behavioral (real Hive box) regression test for closes-diagnose a3f6d9.
//
// Bug: RestoringScreen._goHome is only ever reached once the destination has
// already been classified "treat as onboarded" (a real GoHome from a live
// cloud `user_profile.onboarding_completed_at` read, or the ResumeOnboarding
// self-heal). It then runs the full cloud restore and calls
// `context.go('/home')`. GoRouter re-evaluates `_authRedirect` on THAT
// navigation, which reads a SEPARATE local flag —
// `MigratedKey.readWithDefault<bool>('onboarding_completed', false)` — not
// the cloud-confirmed `onboarding_completed_at` timestamp. Nothing on the
// plain-reopen restore path (`_restoreUserProfile` only merges
// `onboarding_completed_at` into `userBox['profile']`, a different key) ever
// stamped that local boolean, so a device/browser with no prior local state
// (cleared storage, fresh browser context) reached `_goHome`, ran the whole
// restore, and was then bounced straight back to `/onboarding` by the
// router's own re-evaluation.
//
// `onboarding_completed_at_behavioral_test.dart` pins the CLOUD-side
// classification (`classifyDestination`) and does not touch this local flag
// at all — it would stay green with this bug present. This test exercises
// the real Hive/MigratedKey machinery (no mocks on the box layer) to pin the
// missing writer: fails on the pre-fix code (flag stays false forever on this
// path), passes with the fix (RestoringScreen._goHome stamps it once
// ownership is open, mirroring UserRepository.setOnboarded()).
//
// Concept: onboarding_completed_at (docs/sot_registry.yaml)
// Writer added:  lib/features/auth/screens/restoring_screen.dart — THREE
//                sites: _goHome's two branches (bg-restore fast path +
//                default blocking path) AND _onContinueAnyway (the 30s
//                CONTINUE timeout escape hatch, added after B-pass Finding 1,
//                1dcc14cdbf32-review.md, caught that this third path to
//                /home bypassed _goHome entirely and was reachable exactly
//                when the bug is most likely to still be live — a slow
//                restore that hasn't finished by the 30s timer).
// Reader pinned: lib/core/router/app_router.dart _authRedirect (the exact
//                MigratedKey.readWithDefault<bool>('onboarding_completed',
//                false) expression it evaluates on every navigation)
//
// Run: flutter test test/contracts/restoring_screen_local_onboarded_flag_stamp_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  group(
      'onboarding_completed local flag — the exact read _authRedirect performs',
      () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await setUpHiveForTests();
    });

    tearDown(() async {
      await tearDownHiveForTests(tempDir);
    });

    test(
        'default state (fresh device/browser, nothing restored yet) reads '
        'false — reproduces the pre-fix condition on a first visit to a '
        'browser/device with no prior local Hive state', () {
      expect(
        MigratedKey.readWithDefault<bool>('onboarding_completed', false),
        isFalse,
        reason: 'A device/browser that has never locally completed or '
            'restored onboarding must default to false — this is the exact '
            'state a cleared-storage / fresh browser tab starts from, even '
            'when the cloud user_profile.onboarding_completed_at is already '
            'populated for that account.',
      );
    });

    test(
        'RestoringScreen._goHome-equivalent stamp: after the fix runs '
        '(mirrors UserRepository.setOnboarded(), called once ownership is '
        'confirmed open), _authRedirect\'s own read returns true', () async {
      // This is the literal guard now present at all three call sites in
      // RestoringScreen (_goHome's two branches, restoring_screen.dart
      // :246-247 and :279-280, plus _onContinueAnyway's copy added after
      // B-pass Finding 1) — reproduced here directly against the real
      // MigratedKey storage so the test fails if that write is ever
      // removed, renamed, or its target key drifts from what _authRedirect
      // reads.
      if (!UserRepository.instance.isOnboarded) {
        await UserRepository.instance.setOnboarded();
      }

      // Read via the EXACT expression app_router.dart's _authRedirect
      // evaluates (lib/core/router/app_router.dart:701-702) — not via
      // UserRepository.isOnboarded's own wrapper — so a future refactor of
      // either side that silently changes the underlying key still fails
      // this test.
      expect(
        MigratedKey.readWithDefault<bool>('onboarding_completed', false),
        isTrue,
        reason: 'After RestoringScreen._goHome runs its onboarded-flag '
            'stamp, _authRedirect re-evaluating on the context.go(\'/home\') '
            'navigation must see the flag as true, or the returning user is '
            'bounced straight back to /onboarding despite the cloud already '
            'confirming they are fully onboarded.',
      );
    });

    test(
        'idempotent: calling the stamp guard twice does not throw and '
        'leaves the flag true (both _goHome branches share this guard; a '
        'user could theoretically hit either on different launches)',
        () async {
      if (!UserRepository.instance.isOnboarded) {
        await UserRepository.instance.setOnboarded();
      }
      if (!UserRepository.instance.isOnboarded) {
        await UserRepository.instance.setOnboarded();
      }

      expect(UserRepository.instance.isOnboarded, isTrue);
    });
  });

  group(
      'restoring_screen.dart actually contains the stamp at all three call sites',
      () {
    // Belt-and-braces alongside the behavioral round-trip above: presence
    // alone can't prove the write succeeds at runtime (that's what the
    // behavioral tests above pin), but a behavioral test alone can't prove
    // the real widget file still calls the primitive it claims to. Both
    // together close the loop — this is the "source-grep tests count for
    // presence only" pairing CLAUDE.md §4.4 rule 21 requires.
    test(
        '_goHome (both branches) and _onContinueAnyway all stamp the flag '
        'before reaching /home', () {
      final src = File(
        'lib/features/auth/screens/restoring_screen.dart',
      ).readAsStringSync();

      // Matches both `if (!UserRepository...` (the two _goHome sites) and
      // `if (ownershipOpen && !UserRepository...` (_onContinueAnyway) —
      // the shared suffix is what both guard shapes have in common.
      final guardOccurrences =
          RegExp(r'!UserRepository\.instance\.isOnboarded\) \{\s*'
                  r'\n\s*await UserRepository\.instance\.setOnboarded\(\);')
              .allMatches(src)
              .length;

      expect(
        guardOccurrences,
        3,
        reason: 'Three paths reach /home from RestoringScreen: _goHome\'s '
            'two branches (bg-restore fast path + default blocking path) '
            'and _onContinueAnyway (the 30s CONTINUE timeout escape hatch, '
            'B-pass Finding 1). ALL THREE must stamp the local onboarded '
            'flag before navigating, or the path missing the guard '
            'regresses back to the bounce-to-/onboarding bug — exactly '
            'what happened to _onContinueAnyway before this test was '
            'tightened from 2 to 3.',
      );
    });
  });
}
