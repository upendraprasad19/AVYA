// Bug 2026-05-22 (diagnose dc52a4) regression test — pins the
// invariant that splash_screen.dart's _runDeferredInit must NOT touch
// any user-scoped GuardedBox before HiveUserSession.openForUser has
// been called (which happens inside SyncService.restoreFromCloudForUser,
// invoked from RestoringScreen — AFTER splash navigates away).
//
// Pre-fix splash had:
//   1. `_restoreSub` listener calling refillIfNewWeek + provider invalidations
//      — DEAD CODE because splash disposes before restore completes
//   2. `userBox['progress']` read for the streak_freeze_just_used clear
//      — threw HiveUserSession not opened
//   3. `DayRolloverObserver.runRolloverNow(ref)` — touched userBox via
//      StreakProgressService.refillIfNewWeek; threw the same exception
//
// telemetry confirmed `day_rollover_streak_freeze_refill` failed on
// every trigger since at least 2026-05-06.
//
// All three moved to RestoringScreen._ensureOwnershipBeforeHome where
// HiveUserSession.openForUser HAS been called via restoreFromCloudForUser.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/read_screen_source.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// Extract the body of a top-level method by signature, returning the
/// next maxChars of source (stripped of comments) so we only check that
/// method's lines rather than the whole file.
String _methodBody(String src, String signature, {int maxChars = 4000}) {
  final start = src.indexOf(signature);
  if (start == -1) return '';
  final end = (start + maxChars).clamp(0, src.length);
  return _stripComments(src.substring(start, end));
}

void main() {
  final splashSrc =
      File('lib/features/auth/screens/splash_screen.dart').readAsStringSync();
  // Scope the splash checks to _runDeferredInit — _autoGenerateNextPhaseForPro
  // has its own defensive HiveUserSession.ensureOpenedForCurrentSession()
  // bootstrap before it touches userBox, so it's allowed to call
  // getProfile/getProgress (C-7 audit-2026-05-11). The race only happens
  // when userBox is touched WITHOUT first ensuring the session is open,
  // which is what _runDeferredInit used to do.
  final splashRunDeferredInit =
      _methodBody(splashSrc, 'Future<void> _runDeferredInit() async {');
  final splashInitState =
      _methodBody(splashSrc, 'void initState() {', maxChars: 3000);
  final restoringSrc =
      readRestoringScreenSource();
  final restoringStripped = _stripComments(restoringSrc);

  group('Splash must not touch userBox before HiveUserSession opens', () {
    test('_runDeferredInit does not call UserRepository.getProgress', () {
      expect(
        splashRunDeferredInit.contains('UserRepository.instance.getProgress()'),
        isFalse,
        reason: "_runDeferredInit body must NOT call "
            "UserRepository.instance.getProgress() — userBox is a "
            "GuardedBox that throws 'HiveUserSession not opened' at this "
            "point in cold start. Move userBox reads to RestoringScreen "
            "after HiveUserSession.openForUser has run. "
            "(_autoGenerateNextPhaseForPro is exempt — it has its own "
            "ensureOpenedForCurrentSession bootstrap.)",
      );
    });

    test('_runDeferredInit does not call UserRepository.updateProgress', () {
      expect(
        splashRunDeferredInit
            .contains('UserRepository.instance.updateProgress('),
        isFalse,
        reason: "_runDeferredInit body must NOT call updateProgress() — "
            "same GuardedBox race as getProgress. Move to RestoringScreen.",
      );
    });

    test('_runDeferredInit does not invoke DayRolloverObserver.runRolloverNow',
        () {
      expect(
        splashRunDeferredInit
            .contains('DayRolloverObserver.instance.runRolloverNow'),
        isFalse,
        reason: "_runDeferredInit body must NOT call runRolloverNow(ref) — "
            "it internally writes userBox via "
            "StreakProgressService.refillIfNewWeek and hits the same "
            "HiveUserSession-not-opened race.",
      );
    });

    test('_runDeferredInit does not invoke StreakProgressService.refillIfNewWeek',
        () {
      expect(
        splashRunDeferredInit
            .contains('StreakProgressService.instance.refillIfNewWeek'),
        isFalse,
        reason: "_runDeferredInit body must NOT call refillIfNewWeek() — "
            "same race. Move to RestoringScreen.",
      );
    });

    test('initState does not subscribe to onRestoreComplete (dead code removed)',
        () {
      // The listener at the top of initState was dead — splash disposes
      // before the restoreFuture emits. Removed entirely.
      expect(
        splashInitState.contains('onRestoreComplete.listen'),
        isFalse,
        reason: "splash initState must NOT subscribe to "
            "onRestoreComplete — splash disposes within ~3s of mount, "
            "long before restoreFromCloudForUser emits (~36s). The "
            "subscription was dead code that never fired.",
      );
    });
  });

  group('RestoringScreen owns the post-auth bootstrap', () {
    test('RestoringScreen reads userBox via UserRepository.getProgress', () {
      // The just_used clear that we moved over lives here now.
      expect(
        restoringStripped.contains('UserRepository.instance.getProgress()'),
        isTrue,
        reason: "RestoringScreen must call getProgress() as part of the "
            "post-openForUser bootstrap (just_used clear).",
      );
    });

    test('RestoringScreen invokes DayRolloverObserver.runRolloverNow', () {
      expect(
        restoringStripped
            .contains('DayRolloverObserver.instance.runRolloverNow'),
        isTrue,
        reason: "RestoringScreen must call runRolloverNow(ref) after "
            "openForUser so day-rollover providers invalidate before "
            "/home renders.",
      );
    });

    test('RestoringScreen invokes StreakProgressService.refillIfNewWeek', () {
      expect(
        restoringStripped
            .contains('StreakProgressService.instance.refillIfNewWeek'),
        isTrue,
        reason: "RestoringScreen must call refillIfNewWeek() as the "
            "post-restore defence-in-depth for the obs 1+2 race fix.",
      );
    });
  });
}
