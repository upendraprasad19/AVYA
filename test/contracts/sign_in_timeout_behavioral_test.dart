import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';

/// Behavioral regression tests for diagnose a9c4e2 — nothing on the email
/// sign-in path carried a deadline, so a degraded backend produced an
/// unbounded spinner with no error path and no user escape.
///
/// The prod signature (2026-08-13 23:03 IST, prod web): `POST /token` returned
/// **200 in 309ms** — the credentials were never in question — and then
/// `/user` took 9.4s, 27.3s, 35.9s. `state` stayed [AuthStatus.loading]
/// forever, and `sign_in_screen.dart`'s `ref.listen` navigates only on
/// `success` and SnackBars only on `error`, so it had nothing to react to.
///
/// Why behavioral and not source-grep: a grep can only prove `.timeout(`
/// appears in `auth_provider.dart`. It cannot catch a refactor that keeps the
/// call but bounds the wrong future, passes a null/absurd ceiling, or leaves
/// the kill-switch inverted. These assert what actually happens to a future
/// that never completes.
///
/// The seam is [AuthNotifier.boundSignIn] — the real code path.
/// `signInWithEmail` wraps `_performEmailSignIn` in exactly this call, so a
/// regression in the bound reddens these tests.
void main() {
  tearDown(() {
    AuthNotifier.signInTimeoutDisabledForTest = null;
  });

  group('a9c4e2 — email sign-in ceiling', () {
    test('a never-completing sign-in RAISES instead of hanging', () async {
      // The exact prod shape: auth succeeded, the post-auth work never
      // returned. A never-resolving await does not throw — it simply never
      // comes back — which is why the pre-fix spinner was infinite.
      final never = Completer<void>();

      await expectLater(
        AuthNotifier.boundSignIn(() => never.future,
            ceiling: const Duration(milliseconds: 50)),
        throwsA(isA<TimeoutException>()),
        reason: 'PRE-FIX THIS HUNG FOREVER. The ceiling must convert a wedged '
            'backend into a TimeoutException so signInWithEmail can reach a '
            'state the sign-in screen is able to render.',
      );
    });

    test('a sign-in that completes in time is untouched', () async {
      var ran = false;
      await AuthNotifier.boundSignIn(() async {
        ran = true;
      }, ceiling: const Duration(seconds: 5));

      expect(ran, isTrue,
          reason: 'the happy path must not be altered by the bound');
    });

    test('an error from the sign-in body propagates unchanged', () async {
      // The bound must not swallow or reshape real auth failures — the
      // AuthException / generic catch clauses downstream depend on them
      // arriving intact.
      await expectLater(
        AuthNotifier.boundSignIn(
            () async => throw StateError('bad credentials'),
            ceiling: const Duration(seconds: 5)),
        throwsA(isA<StateError>()),
      );
    });

    test('kill-switch restores the pre-fix unbounded await', () async {
      // §4.6 requires the old path stay reachable. With the switch thrown, a
      // slow sign-in must NOT raise — it must be allowed to finish.
      AuthNotifier.signInTimeoutDisabledForTest = true;

      var completed = false;
      await AuthNotifier.boundSignIn(() async {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        completed = true;
      }, ceiling: const Duration(milliseconds: 10));

      expect(completed, isTrue,
          reason: 'with the kill-switch ON the 10ms ceiling must be ignored '
              'and the 120ms body allowed to run to completion');
    });

    test('the shipped default ceiling is finite and sane', () {
      // Guards the two ways a ceiling silently stops being one: an absurdly
      // large value, or a value so small it fails healthy sign-ins.
      expect(AuthNotifier.signInTimeout.inSeconds, greaterThanOrEqualTo(20),
          reason: 'must leave room for legitimate first-run cloud hydration');
      expect(AuthNotifier.signInTimeout.inSeconds, lessThanOrEqualTo(90),
          reason: 'observed prod failures climbed to 36s; a ceiling above ~90s '
              'is indistinguishable from the infinite spinner being fixed');
    });
  });
}
