// Behavioral regression test for diagnose d3a7c9 — Google sign-in hung on the
// sign-in screen forever even though Supabase had already issued the token.
//
// `signInWithOAuth` returns as soon as the external browser launches; it has no
// session to report. The session arrives LATER on `onAuthStateChange`. Nothing
// else in the app observes that: `refreshListenable` appears zero times in
// `lib/`, and `sign_in_screen.dart:167` navigates only on `AuthStatus.success`.
//
// ⚠ THE SECOND, SUBTLER BUG (round-1 review, P0): `onAuthStateChange` is a
// `ReplaySubject` with no maxSize (gotrue_client.dart:94, exposed at :132). It
// replays EVERY event it has ever emitted to each new subscriber. A watch that
// trusted the event PAYLOAD would therefore resolve against a historical
// session — sign in, sign out, tap Google again in the same process, and the
// replayed `signedIn` looks exactly like the redirect returning. That would
// navigate to /restoring with NO session and disarm the watch, so the real
// session then gets no observer: strictly worse than the bug being fixed.
//
// The first version of this test could not see that, because its stub was a
// plain non-replaying StreamController — the fake was MORE FORGIVING than
// production at precisely the seam carrying the defect. It now models the real
// hazard: the event is treated as a mere nudge, and only a CHANGE in the live
// access token counts as the redirect completing.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:icanbefitter/features/auth/providers/auth_provider.dart';

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._events, {this.launchThrows = false});

  final Stream<AuthState> _events;
  final bool launchThrows;
  int launchCount = 0;

  /// The token the fake Supabase client reports as LIVE. Tests mutate this to
  /// simulate a session genuinely arriving (or deliberately fail to, to
  /// simulate a replayed event that changes nothing).
  String? liveToken;

  @override
  Future<bool> ensureSupabaseReady() async => true;

  @override
  Stream<AuthState> authStateChanges() => _events;

  @override
  String? currentAccessToken() => liveToken;

  @override
  Future<bool> launchGoogleOAuth() async {
    launchCount++;
    if (launchThrows) {
      throw AuthException('consent screen unavailable');
    }
    return true;
  }
}

/// A structurally-valid [Session], used as the event payload so the tests can
/// prove the payload is IGNORED.
Session _fakeSession() => Session.fromJson(<String, dynamic>{
      'access_token': 'fake-access-token',
      'token_type': 'bearer',
      'refresh_token': 'fake-refresh-token',
      'user': <String, dynamic>{
        'id': 'fake-user-id',
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z',
      },
    })!;

void main() {
  group('Google OAuth completes the sign-in state machine (d3a7c9)', () {
    late StreamController<AuthState> events;
    late ProviderContainer container;
    late _StubAuthNotifier notifier;

    void buildContainer({bool launchThrows = false, String? startingToken}) {
      events = StreamController<AuthState>.broadcast();
      container = ProviderContainer(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(events.stream, launchThrows: launchThrows),
          ),
        ],
      );
      notifier =
          container.read(authNotifierProvider.notifier) as _StubAuthNotifier;
      notifier.liveToken = startingToken;
    }

    tearDown(() {
      container.dispose();
      unawaited(events.close());
    });

    test('a session arriving after the redirect flips loading -> success',
        () async {
      buildContainer();
      unawaited(notifier.signInWithGoogle());
      await Future<void>.delayed(Duration.zero);

      expect(container.read(authNotifierProvider).status, AuthStatus.loading,
          reason: 'browser launched, no session yet');
      expect(notifier.launchCount, 1);

      // The redirect really did produce a session: the LIVE token changes.
      notifier.liveToken = 'token-from-the-redirect';
      events.add(AuthState(AuthChangeEvent.signedIn, _fakeSession()));
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(authNotifierProvider).status,
        AuthStatus.success,
        reason: 'THE REGRESSION (d3a7c9): the session arrives out of band and '
            'nothing else in the app observes it. Without the watch the status '
            'stays loading forever — both buttons spin and sign_in_screen '
            'never reaches its context.go(/restoring).',
      );
    });

    test('REPLAYED event with an unchanged live token must NOT resolve',
        () async {
      // Sign in, sign out, tap Google again in the same process. gotrue's
      // ReplaySubject re-delivers the old signedIn event the instant we
      // subscribe. Its payload carries a perfectly real Session.
      buildContainer(startingToken: 'stale-token-from-a-previous-session');
      unawaited(notifier.signInWithGoogle());
      await Future<void>.delayed(Duration.zero);

      // Payload says "signed in, here is a session" — and it is a LIE about
      // the present. The live token has not moved.
      events.add(AuthState(AuthChangeEvent.signedIn, _fakeSession()));
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(authNotifierProvider).status,
        AuthStatus.loading,
        reason: 'P0 from round-1 review: trusting the event payload resolves '
            'against a HISTORICAL session — navigating with no session AND '
            'disarming the watch, so the real redirect is then unobserved. '
            'Only a CHANGE in the live token is evidence.',
      );

      // ...and the watch must still be armed, so the real session still works.
      notifier.liveToken = 'token-from-the-actual-redirect';
      events.add(AuthState(AuthChangeEvent.tokenRefreshed, _fakeSession()));
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(authNotifierProvider).status,
        AuthStatus.success,
        reason: 'ignoring the replayed event must not COST us the real one — '
            'that would trade one hang for another',
      );
    });

    test('a NULL live session must not be mistaken for success', () async {
      buildContainer();
      unawaited(notifier.signInWithGoogle());
      await Future<void>.delayed(Duration.zero);

      events.add(const AuthState(AuthChangeEvent.signedOut, null));
      events.add(const AuthState(AuthChangeEvent.initialSession, null));
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(authNotifierProvider).status,
        AuthStatus.loading,
        reason: 'DISCRIMINATOR: initialSession fires with no session on every '
            'signed-out client. Keying on "an event happened" would navigate '
            'a user who never signed in.',
      );
    });

    test('a failed launch cancels the watch so a stray session cannot navigate',
        () async {
      buildContainer(launchThrows: true);
      await notifier.signInWithGoogle();

      expect(container.read(authNotifierProvider).status, AuthStatus.error);

      notifier.liveToken = 'late-unrelated-token';
      events.add(AuthState(AuthChangeEvent.signedIn, _fakeSession()));
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(authNotifierProvider).status,
        AuthStatus.error,
        reason: 'the launch already failed; a later unrelated session must not '
            'resurrect success and navigate anyway',
      );
    });

    test('an abandoned consent screen releases the spinner back to idle', () {
      fakeAsync((async) {
        buildContainer();
        unawaited(notifier.signInWithGoogle());
        async.flushMicrotasks();

        expect(container.read(authNotifierProvider).status, AuthStatus.loading);

        async.elapse(
            AuthNotifier.oauthSessionWait + const Duration(seconds: 1));

        expect(
          container.read(authNotifierProvider).status,
          AuthStatus.idle,
          reason: 'user dismissed Google consent, so no session ever arrives. '
              'IDLE not ERROR — a deliberate cancel is not a failure, but the '
              'buttons must be usable again either way.',
        );
      });
    });
  });
}
