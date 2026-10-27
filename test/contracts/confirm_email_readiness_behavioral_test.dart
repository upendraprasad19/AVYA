import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';

/// Behavioral coverage for `AuthNotifier.confirmEmail`'s Supabase-readiness
/// guard.
///
/// `confirm_email_error_mapping_test.dart`'s own doc comment explains why
/// `confirmEmail` can't be tested end-to-end: it calls the real
/// `Supabase.instance.client.auth.verifyOTP` with no DI seam. That's true,
/// and it's also exactly how this bug survived — nobody wrote a test for
/// what happens BEFORE verifyOTP is reached. This file doesn't need a seam
/// for verifyOTP; it tests the guard in front of it, the same way
/// `check_email_registered_behavioral_test.dart` tests
/// `checkEmailRegistered`'s use of the identical `ensureSupabaseReady`
/// method — by overriding the whole (`@visibleForTesting`) method on a
/// subclass, not the private network call itself.
///
/// The negative case doubles as the regression pin: with the guard removed,
/// `confirmEmail` falls through into the real (uninitialized, in this VM
/// test process) `Supabase.instance.client`, whose `late` field throws
/// `LateInitializationError` — landing in the generic catch-all and
/// producing the exact misleading "invalid or has expired" message this fix
/// exists to prevent, even though the link itself was never actually
/// checked.
class _FakeSupabaseNotReadyNotifier extends AuthNotifier {
  @override
  Future<bool> ensureSupabaseReady() async {
    // Mirrors the real ensureSupabaseReady()'s own failure-path state
    // update (auth_provider.dart) so this fake's contract matches
    // production, not just its return value.
    state = state.copyWith(
      status: AuthStatus.error,
      errorMessage: 'Connection failed. Please check your internet and try again.',
    );
    return false;
  }
}

void main() {
  test(
    'confirmEmail short-circuits on a not-ready Supabase before ever '
    'reaching verifyOTP',
    () async {
      final container = ProviderContainer(
        overrides: [
          authNotifierProvider
              .overrideWith(() => _FakeSupabaseNotReadyNotifier()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(authNotifierProvider.notifier);
      await notifier.confirmEmail('some-real-token-hash');

      final state = container.read(authNotifierProvider);
      expect(state.status, AuthStatus.error);
      expect(
        state.errorMessage,
        'Connection failed. Please check your internet and try again.',
        reason:
            'this must be ensureSupabaseReady\'s OWN message, not the '
            'generic fallback — proving the guard fired and confirmEmail '
            'returned before ever touching verifyOTP.',
      );
      expect(
        state.errorMessage,
        isNot(contains('invalid or has expired')),
        reason:
            'the pre-fix bug: an uninitialized Supabase produced exactly '
            'this misleading message, telling the user their real, '
            'never-actually-checked link was bad.',
      );
    },
  );

  test(
    'with the REAL ensureSupabaseReady (not overridden), confirmEmail '
    'surfaces the accurate init-failure reason instead of the misleading '
    'invalid-or-expired fallback',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(authNotifierProvider.notifier);
      await notifier.confirmEmail('some-real-token-hash');

      final state = container.read(authNotifierProvider);
      expect(state.status, AuthStatus.error);
      // SupabaseService.initialize() throws its own explicit StateError on
      // empty .env values (this test process's real environment) — caught
      // and surfaced by the REAL ensureSupabaseReady(), which this test
      // does NOT override. This is the regression pin: pre-fix, nothing
      // called ensureSupabaseReady() at all, so confirmEmail instead fell
      // through to the raw `Supabase.instance` singleton and produced the
      // generic "invalid or has expired" fallback — see the mutation-proof
      // note in this file's header.
      expect(
        state.errorMessage,
        contains('SUPABASE_URL or SUPABASE_ANON_KEY is empty'),
      );
      expect(state.errorMessage, isNot(contains('invalid or has expired')));
    },
  );

  group('ensureSupabaseReady() must precede the OI-205 guard (B-pass '
      'Finding 1, diagnose 42a98d)', () {
    // Source-order pin, not a behavioral one: proving the TRUE branch of
    // confirmEmailAuthGuardState end-to-end needs a real persisted session
    // in local storage, which this VM test harness cannot produce — the
    // same documented gap this guard's own history already names (see
    // auth_provider.dart's comment on confirmEmail). `SupabaseAuth
    // .initialize()` restores a persisted session as part of the SAME
    // awaited chain ensureSupabaseReady() awaits (`setInitialSession`,
    // supabase_auth.dart), so `_supabase.isAuthenticated` is not just
    // unavailable but actively WRONG (always false) until that call has
    // resolved. Reading it before ensureSupabaseReady() would let a cold
    // /confirm load past the OI-205 guard while reporting "not signed in"
    // for a device that actually has a valid session — reopening the exact
    // silent-account-switch class OI-205 exists to block. This test pins
    // the STRUCTURAL fix (positional order in source) as the next-best
    // proof given the seam gap above.
    late String providerSrc;

    setUpAll(() {
      providerSrc = File(
        'lib/features/auth/providers/auth_provider.dart',
      ).readAsStringSync();
    });

    test('ensureSupabaseReady() call precedes confirmEmailAuthGuardState '
        'call, inside confirmEmail\'s body', () {
      final start = providerSrc.indexOf('Future<void> confirmEmail(');
      expect(start, isNot(-1));
      final end = providerSrc.indexOf(
        '\n  /// Pure decision for the OI-205 interim guard',
        start,
      );
      expect(end, isNot(-1));
      final body = providerSrc.substring(start, end);

      // Match the exact CODE STATEMENT, not a bare substring — this file's
      // own surrounding comments mention "ensureSupabaseReady()" in prose
      // (explaining why the order matters), and a naive substring match
      // finds that comment text regardless of where the real call sits.
      // Caught by mutation: an early version of this test used
      // `body.indexOf('ensureSupabaseReady()')` and stayed GREEN when the
      // code call was moved after the guard, because the comment above the
      // guard still contained the literal phrase.
      final readyIndex =
          body.indexOf('if (!await ensureSupabaseReady()) return;');
      final guardIndex = body.indexOf('confirmEmailAuthGuardState(');
      expect(readyIndex, isNot(-1));
      expect(guardIndex, isNot(-1));
      expect(
        readyIndex,
        lessThan(guardIndex),
        reason:
            'ensureSupabaseReady() must be awaited BEFORE '
            'confirmEmailAuthGuardState reads _supabase.isAuthenticated — '
            'reversing this order silently breaks the OI-205 guard for a '
            'device with a real persisted session.',
      );
    });
  });
}
