// Regression contract for diagnose a1f9c4 — the boot + onboarding navigation
// paths must be Hive-first: no un-timed cloud/IO `await` may sit on the critical
// path, or a slow/stalled backend strands the user on the AVYA seal (splash) or
// the REPORT FOR DUTY spinner (onboarding) forever, with no error and no escape.
//
// This is a SOURCE-STRUCTURE contract (comment-stripped per
// feedback_source_grep_strip_comments_first). It FAILS on the pre-fix code
// (cloud calls awaited in the critical path / no `_syncOnboardingAndPostActions`
// method / no splash init timeout). The behavioral proof is the founder's live
// signup re-walk (REPORT FOR DUTY navigates instantly; the splash reaches Home
// even on a slow backend). A fakeAsync behavioral test that injects a hanging
// Supabase needs a service-fake/DI seam — tracked as a follow-up.
//
// Run: flutter test test/contracts/boot_onboarding_hive_first_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strips `/* */` block comments and `//` line comments so a comment that
/// merely *mentions* a banned pattern can't pass/fail the structural check.
String _stripComments(String src) {
  src = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return src
      .split('\n')
      .map((line) {
        final idx = line.indexOf('//');
        return idx >= 0 ? line.substring(0, idx) : line;
      })
      .join('\n');
}

void main() {
  group('boot + onboarding are Hive-first (no un-timed cloud await on the nav '
      'path) — a1f9c4', () {
    test('splash _initAndNavigate bounds the deferred init with a timeout', () {
      final src = _stripComments(
        File('lib/features/auth/screens/splash_screen.dart').readAsStringSync(),
      );
      expect(src.contains('_initAndNavigate'), isTrue);
      expect(src.contains('_runDeferredInit('), isTrue);
      // The init future MUST be bounded so `_navigateNext` always runs.
      expect(src.contains('_kInitTimeout'), isTrue,
          reason: 'splash must define the bounded-init timeout constant (a1f9c4)');
      expect(src.contains('.timeout('), isTrue,
          reason: 'splash deferred init must be bounded with `.timeout(` so the '
              'AVYA seal can never hang forever (a1f9c4)');
    });

    test(
        'completeOnboarding fires the cloud chain UNAWAITED and does NOT await '
        'redeem-referral / verifyFromServer on its critical path', () {
      final src = _stripComments(
        File('lib/features/onboarding/providers/onboarding_provider.dart')
            .readAsStringSync(),
      );

      final start = src.indexOf('completeOnboarding() async');
      expect(start, greaterThan(-1));

      // The cloud chain MUST be extracted into a dedicated background method.
      final defIdx =
          src.indexOf('Future<void> _syncOnboardingAndPostActions(');
      expect(defIdx, greaterThan(start),
          reason: 'the cloud chain must be extracted into the unawaited '
              '_syncOnboardingAndPostActions background method (a1f9c4)');

      final completeBody = src.substring(start, defIdx);
      final bgBody = src.substring(defIdx);

      // completeOnboarding fires the catch-up fire-and-forget, not awaited.
      expect(completeBody.contains('_syncOnboardingAndPostActions('), isTrue,
          reason: 'completeOnboarding must call the background cloud method');
      expect(completeBody.contains('unawaited('), isTrue,
          reason: 'completeOnboarding must fire the cloud catch-up unawaited so '
              'REPORT FOR DUTY navigates immediately (Hive-first)');

      // The cloud calls must NOT block the REPORT FOR DUTY critical path.
      expect(completeBody.contains("callFunction('redeem-referral'"), isFalse,
          reason: 'redeem-referral must run in the background method, never on '
              'the critical path (a1f9c4)');
      expect(completeBody.contains('verifyFromServer('), isFalse,
          reason: 'verifyFromServer must run in the background method, never on '
              'the critical path (a1f9c4)');

      // The background method holds the chain, sync BEFORE referral (the EF
      // reads the public.users row the upsert writes).
      expect(bgBody.contains("callFunction('redeem-referral'"), isTrue);
      final syncIdx = bgBody.indexOf('_syncOnboardingToSupabase(');
      final referralIdx = bgBody.indexOf("callFunction('redeem-referral'");
      expect(syncIdx, greaterThan(-1));
      expect(referralIdx, greaterThan(syncIdx),
          reason: 'the user_profile/users upsert must precede the referral '
              'redeem in the background chain (ordering preserved)');
    });
  });
}
